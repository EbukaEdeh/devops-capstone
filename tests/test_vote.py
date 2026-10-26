import json
import math
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import fakeredis
import pytest
from prometheus_client import CollectorRegistry
from prometheus_client.parser import text_string_to_metric_families

from services.vote.app import create_app


def metric_value(body: str, name: str) -> float:
    for family in text_string_to_metric_families(body):
        if family.name == name:
            return float(family.samples[0].value)
    raise AssertionError(f"metric {name} not found in exposition")


@pytest.fixture()
def app_and_redis():
    redis_client = fakeredis.FakeRedis(decode_responses=True)
    app = create_app(redis_client, registry=CollectorRegistry())
    app.config.update(TESTING=True)
    return app, redis_client


def test_index_renders_ballot(app_and_redis):
    app, _ = app_and_redis
    response = app.test_client().get("/")
    assert response.status_code == 200
    assert b"Pick a side" in response.data
    assert b"Cats" in response.data
    assert b"Dogs" in response.data


def test_vote_is_queued_with_an_id(app_and_redis):
    app, redis_client = app_and_redis
    response = app.test_client().post("/vote", data={"choice": "cats"})

    assert response.status_code == 303
    assert response.headers["Location"].endswith("/?voted=cats")

    queued = redis_client.lrange("votes", 0, -1)
    assert len(queued) == 1
    payload = json.loads(queued[0])
    assert payload["choice"] == "cats"
    assert payload["id"]
    assert payload["created_at"]


def test_invalid_choice_is_rejected(app_and_redis):
    app, redis_client = app_and_redis
    response = app.test_client().post("/vote", data={"choice": "ferrets"})

    assert response.status_code == 400
    assert redis_client.llen("votes") == 0


def test_readyz_checks_redis(app_and_redis):
    app, _ = app_and_redis
    response = app.test_client().get("/readyz")
    assert response.status_code == 200
    assert response.get_json()["status"] == "ok"


def test_metrics_report_queue_depth_and_oldest_age(app_and_redis):
    app, redis_client = app_and_redis
    created_at = (datetime.now(timezone.utc) - timedelta(seconds=90)).isoformat()
    redis_client.rpush(
        "votes",
        json.dumps(
            {"id": str(uuid4()), "choice": "cats", "created_at": created_at}
        ),
    )

    body = app.test_client().get("/metrics").get_data(as_text=True)

    assert metric_value(body, "vote_queue_depth") == 1
    age = metric_value(body, "vote_queue_oldest_age_seconds")
    assert 85 <= age <= 100


def test_metrics_report_zero_age_for_an_empty_queue(app_and_redis):
    app, _ = app_and_redis

    body = app.test_client().get("/metrics").get_data(as_text=True)

    assert metric_value(body, "vote_queue_depth") == 0
    assert metric_value(body, "vote_queue_oldest_age_seconds") == 0


def test_metrics_keep_depth_when_a_payload_is_malformed(app_and_redis):
    app, redis_client = app_and_redis
    redis_client.rpush("votes", "not-json")

    response = app.test_client().get("/metrics")
    body = response.get_data(as_text=True)

    assert response.status_code == 200
    assert metric_value(body, "vote_queue_depth") == 1
    assert math.isnan(metric_value(body, "vote_queue_oldest_age_seconds"))
