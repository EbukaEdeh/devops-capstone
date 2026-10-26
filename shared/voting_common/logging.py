"""Structured JSON logging with optional trace correlation.

Every service writes one JSON object per line to stdout. Kubernetes and
Fluent Bit can then parse the stream without fragile regex rules.
"""

from __future__ import annotations

import json
import logging
import os
import sys
from datetime import datetime, timezone
from typing import Any

try:  # OpenTelemetry is optional during unit tests.
    from opentelemetry import trace
except Exception:  # pragma: no cover - only hit when OTel is absent
    trace = None  # type: ignore[assignment]


_STANDARD_ATTRS = {
    "args",
    "asctime",
    "created",
    "exc_info",
    "exc_text",
    "filename",
    "funcName",
    "levelname",
    "levelno",
    "lineno",
    "module",
    "msecs",
    "message",
    "msg",
    "name",
    "pathname",
    "process",
    "processName",
    "relativeCreated",
    "stack_info",
    "thread",
    "threadName",
    "taskName",
}


def _json_safe(value: Any) -> Any:
    try:
        json.dumps(value)
        return value
    except (TypeError, ValueError):
        return repr(value)


class JsonFormatter(logging.Formatter):
    def __init__(self, service: str) -> None:
        super().__init__()
        self.service = service

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc)
            .isoformat(timespec="milliseconds")
            .replace("+00:00", "Z"),
            "level": record.levelname.lower(),
            "service": self.service,
            "logger": record.name,
            "message": record.getMessage(),
        }

        for key, value in record.__dict__.items():
            if key not in _STANDARD_ATTRS and not key.startswith("_"):
                payload[key] = _json_safe(value)

        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        if trace is not None:
            span_context = trace.get_current_span().get_span_context()
            if span_context.is_valid:
                payload["trace_id"] = format(span_context.trace_id, "032x")
                payload["span_id"] = format(span_context.span_id, "016x")

        return json.dumps(payload, ensure_ascii=True, default=str)


def setup_logging(service: str) -> None:
    """Configure root logging once per process."""

    level = os.getenv("LOG_LEVEL", "INFO").upper()
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter(service))

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level)

    # Access logs are emitted separately by gunicorn; keep noisy internals quiet.
    logging.getLogger("werkzeug").setLevel(logging.WARNING)
    logging.getLogger("opentelemetry").setLevel(logging.WARNING)
    logging.getLogger("opentelemetry.sdk.trace.export").setLevel(logging.ERROR)
