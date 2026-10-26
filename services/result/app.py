"""Result frontend: reads live totals from PostgreSQL."""

from __future__ import annotations

import logging
import os
import threading
from datetime import datetime, timezone
from typing import Any

from flask import Flask, jsonify, render_template
from prometheus_client import REGISTRY, CollectorRegistry, Gauge
from psycopg import Error as PsycopgError
from psycopg_pool import ConnectionPool, PoolTimeout

from voting_common.db import ensure_schema, make_pool
from voting_common.logging import setup_logging
from voting_common.metrics import HttpMetrics
from voting_common.votes import VOTE_CHOICES

logger = logging.getLogger(__name__)
SERVICE_NAME = "result"


def build_results(counts: dict[str, int]) -> dict[str, Any]:
    """Turn raw database counts into the payload used by the UI and API."""

    total = sum(max(int(value), 0) for value in counts.values())
    choices = []
    for choice_id, metadata in VOTE_CHOICES.items():
        count = max(int(counts.get(choice_id, 0)), 0)
        percent = round((count / total) * 100, 1) if total else 0.0
        choices.append(
            {
                "id": choice_id,
                "label": metadata["label"],
                "tagline": metadata["tagline"],
                "count": count,
                "percent": percent,
            }
        )

    return {
        "total": total,
        "choices": choices,
        "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


def create_app(
    pool: ConnectionPool | None = None,
    registry: CollectorRegistry | None = None,
) -> Flask:
    app = Flask(__name__)
    app.config["JSON_SORT_KEYS"] = False
    setup_logging(SERVICE_NAME)

    active_registry = registry or REGISTRY
    http_metrics = HttpMetrics(SERVICE_NAME, registry=active_registry)
    http_metrics.instrument(app)

    db_up = Gauge(
        "result_db_up",
        "Whether the result service can read from PostgreSQL.",
        ["service"],
        registry=active_registry,
    )

    db_pool = pool or make_pool("voting-result")
    if db_pool.closed:
        db_pool.open(wait=False)
    app.extensions["db_pool"] = db_pool

    schema_ready = False
    schema_lock = threading.Lock()

    def read_counts() -> dict[str, int]:
        nonlocal schema_ready

        if db_pool.closed:
            db_pool.open(wait=False)

        with db_pool.connection(timeout=4) as conn:
            if not schema_ready:
                with schema_lock:
                    if not schema_ready:
                        ensure_schema(conn)
                        schema_ready = True
                    else:
                        conn.rollback()

            with conn.cursor() as cur:
                cur.execute("SELECT choice, COUNT(*) FROM votes GROUP BY choice")
                counts = {str(row[0]): int(row[1]) for row in cur.fetchall()}
            conn.commit()

        db_up.labels(SERVICE_NAME).set(1)
        return counts

    def safe_read_counts() -> dict[str, int]:
        try:
            return read_counts()
        except (PsycopgError, PoolTimeout):
            db_up.labels(SERVICE_NAME).set(0)
            logger.exception("could not read results from postgres")
            raise

    @app.get("/")
    def index():  # type: ignore[no-untyped-def]
        try:
            initial = build_results(safe_read_counts())
            degraded = False
        except (PsycopgError, PoolTimeout):
            initial = build_results({})
            degraded = True

        return render_template("index.html", initial=initial, degraded=degraded)

    @app.get("/api/results")
    def api_results():  # type: ignore[no-untyped-def]
        try:
            payload = build_results(safe_read_counts())
        except (PsycopgError, PoolTimeout):
            return (
                jsonify(error="results are temporarily unavailable", retry_after_seconds=3),
                503,
                {"Retry-After": "3"},
            )
        return jsonify(payload)

    @app.get("/healthz")
    def healthz():  # type: ignore[no-untyped-def]
        return jsonify(status="ok", service=SERVICE_NAME)

    @app.get("/readyz")
    def readyz():  # type: ignore[no-untyped-def]
        try:
            if db_pool.closed:
                db_pool.open(wait=False)
            with db_pool.connection(timeout=3) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
                    cur.fetchone()
            db_up.labels(SERVICE_NAME).set(1)
        except (PsycopgError, PoolTimeout):
            db_up.labels(SERVICE_NAME).set(0)
            return jsonify(status="degraded", dependency="postgres"), 503
        return jsonify(status="ok", service=SERVICE_NAME)

    @app.get("/metrics")
    def metrics():  # type: ignore[no-untyped-def]
        return http_metrics.response()

    return app


if os.getenv("VOTING_TEST_MODE") != "1":
    app = create_app()


if __name__ == "__main__":
    create_app().run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
