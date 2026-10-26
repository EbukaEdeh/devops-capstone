import json
import logging

from voting_common.logging import JsonFormatter


def test_json_formatter_includes_service_and_extras():
    record = logging.LogRecord(
        name="test",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg="vote queued",
        args=(),
        exc_info=None,
    )
    record.choice = "cats"

    payload = json.loads(JsonFormatter("vote").format(record))
    assert payload["service"] == "vote"
    assert payload["level"] == "info"
    assert payload["message"] == "vote queued"
    assert payload["choice"] == "cats"
    assert payload["timestamp"].endswith("Z")
