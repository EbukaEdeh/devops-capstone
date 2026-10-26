from services.result.app import build_results


def test_empty_results_are_zeroed():
    payload = build_results({})
    assert payload["total"] == 0
    assert [choice["percent"] for choice in payload["choices"]] == [0.0, 0.0]


def test_percentages_are_rounded_and_total_is_preserved():
    payload = build_results({"cats": 2, "dogs": 1})
    assert payload["total"] == 3
    by_id = {choice["id"]: choice for choice in payload["choices"]}
    assert by_id["cats"]["count"] == 2
    assert by_id["cats"]["percent"] == 66.7
    assert by_id["dogs"]["percent"] == 33.3


def test_unknown_counts_do_not_break_the_payload():
    payload = build_results({"cats": 1, "birds": 4})
    assert payload["total"] == 5
    by_id = {choice["id"]: choice for choice in payload["choices"]}
    assert by_id["cats"]["percent"] == 20.0
