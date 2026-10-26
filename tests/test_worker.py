from datetime import timezone
from uuid import uuid4

import pytest

from services.worker.worker import parse_vote


def test_parse_valid_vote():
    vote_id = uuid4()
    vote = parse_vote(
        '{"id":"%s","choice":"dogs","created_at":"2026-01-02T03:04:05+00:00"}'
        % vote_id
    )
    assert vote.id == vote_id
    assert vote.choice == "dogs"
    assert vote.created_at.tzinfo is not None


def test_choice_is_normalized():
    vote = parse_vote('{"id":"%s","choice":"CATS"}' % uuid4())
    assert vote.choice == "cats"
    assert vote.created_at.tzinfo == timezone.utc


@pytest.mark.parametrize(
    "payload",
    [
        "not-json",
        "[]",
        '{"choice":"cats"}',
        '{"id":"not-a-uuid","choice":"cats"}',
        '{"id":"%s","choice":"birds"}' % uuid4(),
        '{"id":"%s","choice":"cats","created_at":"yesterday"}' % uuid4(),
    ],
)
def test_invalid_votes_are_rejected(payload):
    with pytest.raises(ValueError):
        parse_vote(payload)
