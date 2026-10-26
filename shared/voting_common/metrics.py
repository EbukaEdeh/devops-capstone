"""Prometheus HTTP metrics shared by the web services.

The containers run a single gunicorn worker with threads, so the default
Prometheus registry is safe without multiprocess mode. Scale horizontally
with Kubernetes replicas and aggregate across pods in PromQL.
"""

from __future__ import annotations

import time
from typing import TYPE_CHECKING

from prometheus_client import (
    CONTENT_TYPE_LATEST,
    REGISTRY,
    CollectorRegistry,
    Counter,
    Histogram,
    generate_latest,
)

if TYPE_CHECKING:
    from flask import Flask


class HttpMetrics:
    def __init__(
        self,
        service: str,
        registry: CollectorRegistry | None = None,
    ) -> None:
        self.service = service
        self.registry = registry or REGISTRY
        self.requests = Counter(
            "http_requests_total",
            "Total HTTP requests handled by the service.",
            ["service", "method", "route", "status"],
            registry=self.registry,
        )
        self.duration = Histogram(
            "http_request_duration_seconds",
            "HTTP request duration in seconds.",
            ["service", "method", "route"],
            buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
            registry=self.registry,
        )
        self.in_flight = Counter(
            "http_requests_started_total",
            "Total HTTP requests started by the service.",
            ["service", "method", "route"],
            registry=self.registry,
        )

    def instrument(self, app: "Flask") -> None:
        from flask import g, request

        @app.before_request
        def _start_timer() -> None:
            g.http_started_at = time.perf_counter()

        @app.after_request
        def _record(response):  # type: ignore[no-untyped-def]
            if request.path in {"/metrics", "/healthz", "/readyz"}:
                return response

            route = request.url_rule.rule if request.url_rule is not None else "unmatched"
            started = getattr(g, "http_started_at", None)
            elapsed = time.perf_counter() - started if started is not None else 0.0

            self.in_flight.labels(self.service, request.method, route).inc()
            self.requests.labels(
                self.service, request.method, route, str(response.status_code)
            ).inc()
            self.duration.labels(self.service, request.method, route).observe(elapsed)
            return response

    def response(self):  # type: ignore[no-untyped-def]
        from flask import Response

        return Response(
            generate_latest(self.registry),
            headers={"Content-Type": CONTENT_TYPE_LATEST},
        )
