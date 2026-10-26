"""Queue worker: moves votes from Redis into PostgreSQL."""

from __future__ import annotations

import json
import logging
import os
import signal
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any
from uuid import UUID

import redis
from prometheus_client import Counter, Gauge, start_http_server
from psycopg import Error as PsycopgError
from psycopg_pool import ConnectionPool, PoolTimeout
from redis.exceptions import RedisError

from voting_common.db import ensure_schema, make_pool
from voting_common.logging import setup_logging
from voting_common.votes import VALID_CHOICES

logger = logging.getLogger(__name__)

SERVICE_NAME = "worker"
STOP = threading.Event()

VOTES_PROCESSED = Counter(
    "votes_processed_total",
    "Votes written to PostgreSQL.",
    ["service", "choice"],
)
VOTES_DUPLICATE = Counter(
    "votes_duplicate_total",
    "Votes ignored because their ID was already stored.",
    ["service"],
)
VOTES_FAILED = Counter(
    "votes_failed_total",
    "Votes that could not be processed.",
    ["service", "reason"],
)
QUEUE_DEPTH = Gauge(
    "worker_queue_depth",
    "Observed depth of the Redis vote queue.",
    ["service"],
)


@dataclass(frozen=True)
class Vote:
    id: UUID
    choice: str
    created_at: datetime


def parse_vote(raw: str) -> Vote:
    """Validate a queued message before it reaches PostgreSQL."""

    try:
        payload: Any = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError("payload is not valid JSON") from exc

    if not isinstance(payload, dict):
        raise ValueError("payload must be an object")

    try:
        vote_id = UUID(str(payload["id"]))
    except (KeyError, ValueError, TypeError) as exc:
        raise ValueError("payload has an invalid id") from exc

    choice = str(payload.get("choice", "")).lower()
    if choice not in VALID_CHOICES:
        raise ValueError("payload has an invalid choice")

    created_at_raw = payload.get("created_at")
    if created_at_raw:
        try:
            created_at = datetime.fromisoformat(str(created_at_raw).replace("Z", "+00:00"))
            if created_at.tzinfo is None:
                created_at = created_at.replace(tzinfo=timezone.utc)
        except ValueError as exc:
            raise ValueError("payload has an invalid created_at") from exc
    else:
        created_at = datetime.now(timezone.utc)

    return Vote(id=vote_id, choice=choice, created_at=created_at)


def store_vote(conn, vote: Vote) -> bool:  # type: ignore[no-untyped-def]
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO votes (id, choice, created_at)
            VALUES (%s::uuid, %s, %s)
            ON CONFLICT (id) DO NOTHING
            """,
            (str(vote.id), vote.choice, vote.created_at),
        )
        inserted = cur.rowcount > 0
    conn.commit()
    return inserted


def open_pool() -> ConnectionPool:
    pool = make_pool("voting-worker")
    pool.open(wait=False)
    return pool


def wait_for_database(pool: ConnectionPool) -> bool:
    while not STOP.is_set():
        try:
            with pool.connection(timeout=5) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
                    cur.fetchone()
                ensure_schema(conn)
            logger.info("database connection ready")
            return True
        except (PsycopgError, PoolTimeout):
            logger.warning("waiting for database", exc_info=True)
            STOP.wait(2)
    return False


def consume(redis_client: redis.Redis, pool: ConnectionPool) -> None:
    while not STOP.is_set():
        try:
            queue_item = redis_client.blpop("votes", timeout=5)
            QUEUE_DEPTH.labels(SERVICE_NAME).set(redis_client.llen("votes"))
        except RedisError:
            QUEUE_DEPTH.labels(SERVICE_NAME).set(float("nan"))
            logger.exception("redis unavailable; retrying")
            STOP.wait(2)
            continue

        if queue_item is None:
            continue

        raw = queue_item[1]
        try:
            vote = parse_vote(raw)
        except ValueError as exc:
            VOTES_FAILED.labels(SERVICE_NAME, "invalid_payload").inc()
            redis_client.rpush(
                "votes:dead",
                json.dumps({"reason": str(exc), "payload": raw}, default=str),
            )
            logger.error("vote moved to dead letter queue", extra={"reason": str(exc)})
            continue

        try:
            with pool.connection(timeout=10) as conn:
                inserted = store_vote(conn, vote)
        except (PsycopgError, PoolTimeout):
            VOTES_FAILED.labels(SERVICE_NAME, "database").inc()
            redis_client.lpush("votes", raw)
            logger.exception(
                "could not store vote; returned to queue",
                extra={"vote_id": str(vote.id), "choice": vote.choice},
            )
            STOP.wait(2)
            continue

        if inserted:
            VOTES_PROCESSED.labels(SERVICE_NAME, vote.choice).inc()
            logger.info(
                "vote stored",
                extra={"vote_id": str(vote.id), "choice": vote.choice},
            )
        else:
            VOTES_DUPLICATE.labels(SERVICE_NAME).inc()
            logger.info(
                "duplicate vote ignored",
                extra={"vote_id": str(vote.id), "choice": vote.choice},
            )


def main() -> int:
    setup_logging(SERVICE_NAME)
    metrics_port = int(os.getenv("WORKER_METRICS_PORT", "9101"))
    start_http_server(metrics_port)
    logger.info("worker starting", extra={"metrics_port": metrics_port})

    def request_stop(signum: int, _frame: object) -> None:
        logger.info("shutdown requested", extra={"signal": signum})
        STOP.set()

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    redis_client = redis.Redis.from_url(
        os.getenv("REDIS_URL", "redis://localhost:6379/0"),
        decode_responses=True,
        socket_connect_timeout=3,
        socket_timeout=10,
        health_check_interval=30,
    )
    pool = open_pool()

    if not wait_for_database(pool):
        pool.close()
        return 1

    try:
        consume(redis_client, pool)
    finally:
        pool.close()
        logger.info("worker stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
