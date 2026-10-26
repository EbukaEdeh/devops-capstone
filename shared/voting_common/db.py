"""PostgreSQL connection and schema helpers."""

from __future__ import annotations

import os

from psycopg import Connection
from psycopg.conninfo import make_conninfo
from psycopg_pool import ConnectionPool

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS votes (
    id UUID PRIMARY KEY,
    choice TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS votes_created_at_idx ON votes (created_at DESC);
"""


def conninfo() -> str:
    """Build a libpq connection string from standard environment variables."""

    if url := os.getenv("DATABASE_URL"):
        return url

    return make_conninfo(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=os.getenv("POSTGRES_PORT", "5432"),
        dbname=os.getenv("POSTGRES_DB", "voting"),
        user=os.getenv("POSTGRES_USER", "voting"),
        password=os.getenv("POSTGRES_PASSWORD", ""),
    )


def make_pool(application_name: str) -> ConnectionPool:
    return ConnectionPool(
        conninfo=conninfo(),
        min_size=1,
        max_size=5,
        timeout=5,
        open=False,
        kwargs={"application_name": application_name},
    )


def ensure_schema(conn: Connection) -> None:
    with conn.cursor() as cur:
        cur.execute(SCHEMA_SQL)
    conn.commit()
