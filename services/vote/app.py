"""Vote frontend: accepts a ballot and queues it in Redis."""

from __future__ import annotations

import json
import logging
import os
import uuid
from datetime import datetime, timezone

import redis
from flask import Flask, abort, jsonify, redirect, render_template, request, url_for
from prometheus_client import REGISTRY, CollectorRegistry, Counter, Gauge
from redis.exceptions import RedisError

from voting_common.logging import setup_logging
from voting_common.metrics import HttpMetrics
from voting_common.votes import VOTE_CHOICES

logger = logging.getLogger(__name__)

SERVICE_NAME = "vote"


def create_app(
    redis_client: redis.Redis | None = None,
    registry: CollectorRegistry | None = None,
) -> Flask:
    app = Flask(__name__)
    app.config["JSON_SORT_KEYS"] = False
    setup_logging(SERVICE_NAME)

    active_registry = registry or REGISTRY
    http_metrics = HttpMetrics(SERVICE_NAME, registry=active_registry)
    http_metrics.instrument(app)

    votes_cast = Counter(
        "votes_cast_total",
        "Votes accepted and queued by the vote service.",
        ["service", "choice"],
        registry=active_registry,
    )
    queue_depth = Gauge(
        "vote_queue_depth",
        "Number of votes waiting in the Redis queue.",
        ["service"],
        registry=active_registry,
    )
    queue_oldest_age = Gauge(
        "vote_queue_oldest_age_seconds",
        "Age of the oldest vote waiting in the Redis queue.",
        ["service"],
        registry=active_registry,
    )

    client = redis_client or redis.Redis.from_url(
        os.getenv("REDIS_URL", "redis://localhost:6379/0"),
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
        health_check_interval=30,
    )
    app.extensions["redis"] = client
    app.extensions["votes_cast"] = votes_cast

    @app.get("/")
    def index():  # type: ignore[no-untyped-def]
        voted = request.args.get("voted")
        selected = VOTE_CHOICES.get(voted or "")
        return render_template(
            "index.html",
            options=VOTE_CHOICES,
            selected=selected,
        )

    @app.post("/vote")
    def cast_vote():  # type: ignore[no-untyped-def]
        choice = (request.form.get("choice") or "").strip().lower()
        if choice not in VOTE_CHOICES:
            abort(400, description="Unknown vote choice.")

        vote_id = str(uuid.uuid4())
        payload = {
            "id": vote_id,
            "choice": choice,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }

        try:
            client.rpush("votes", json.dumps(payload))
        except RedisError:
            logger.exception("could not enqueue vote", extra={"choice": choice})
            return render_template("unavailable.html"), 503

        votes_cast.labels(SERVICE_NAME, choice).inc()
        logger.info(
            "vote queued",
            extra={"choice": choice, "vote_id": vote_id, "queue": "votes"},
        )
        return redirect(url_for("index", voted=choice), code=303)

    @app.get("/healthz")
    def healthz():  # type: ignore[no-untyped-def]
        return jsonify(status="ok", service=SERVICE_NAME)

    @app.get("/readyz")
    def readyz():  # type: ignore[no-untyped-def]
        try:
            client.ping()
        except RedisError:
            return jsonify(status="degraded", dependency="redis"), 503
        return jsonify(status="ok", service=SERVICE_NAME)

    @app.get("/metrics")
    def metrics():  # type: ignore[no-untyped-def]
        try:
            queue_depth.labels(SERVICE_NAME).set(client.llen("votes"))
            oldest = client.lindex("votes", 0)
        except RedisError:
            queue_depth.labels(SERVICE_NAME).set(float("nan"))
            queue_oldest_age.labels(SERVICE_NAME).set(float("nan"))
            logger.warning("could not read queue metrics", exc_info=True)
            return http_metrics.response()

        if not oldest:
            queue_oldest_age.labels(SERVICE_NAME).set(0.0)
            return http_metrics.response()

        try:
            payload = json.loads(oldest)
            created_at = datetime.fromisoformat(
                str(payload["created_at"]).replace("Z", "+00:00")
            )
            if created_at.tzinfo is None:
                created_at = created_at.replace(tzinfo=timezone.utc)
            age = (datetime.now(timezone.utc) - created_at).total_seconds()
            queue_oldest_age.labels(SERVICE_NAME).set(max(age, 0.0))
        except (KeyError, TypeError, ValueError):
            # The worker will move malformed messages to votes:dead. Keep the
            # queue depth accurate and report only the age as unknown.
            queue_oldest_age.labels(SERVICE_NAME).set(float("nan"))
            logger.warning("could not compute queue age", exc_info=True)
        return http_metrics.response()

    return app


if os.getenv("VOTING_TEST_MODE") != "1":
    app = create_app()


if __name__ == "__main__":
    create_app().run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
