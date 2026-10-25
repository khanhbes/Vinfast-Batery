"""QA 136: Lộ trình moved from Ultra to Pro; the aurora look is Ultra."""
from billing import features


def test_trip_planner_is_pro():
    assert features.required_tier("trip_estimate") == "pro"
    assert not features.allows("free", "trip_estimate")
    assert features.allows("pro", "trip_estimate")
    assert features.allows("ultra", "trip_estimate")


def test_ultra_look_is_ultra_only():
    assert features.feature_map("pro")["ultra_look"] is False
    assert features.feature_map("ultra")["ultra_look"] is True


def test_assistant_knows_trip_is_pro():
    from assistant import engine, knowledge

    plans = next(item for item in knowledge.BUILTIN if item["id"] == "premium-plans")
    pro, ultra = plans["body"].split("Ultra (", 1)
    assert "Lộ trình" in pro and "lộ trình" not in ultra.lower()
    assert "lộ trình, % pin chai" in engine.PERSONA
