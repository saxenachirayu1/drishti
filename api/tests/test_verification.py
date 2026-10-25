from app.services.verification import decide_result


def test_cleared_after_two_empty_scenes():
    assert decide_result([3000, 0, 0]) == "cleared"


def test_shrinking():
    assert decide_result([3000, 2000, 1000]) == "shrinking"


def test_still_present():
    assert decide_result([3000, 3100, 3200]) == "still_present"


def test_empty_defaults_present():
    assert decide_result([]) == "still_present"
