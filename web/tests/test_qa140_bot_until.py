"""QA 140: Pinova Bot "sạc đến 9:30" — a clock time becomes the timed charge."""
from __future__ import annotations

from datetime import datetime, timedelta

from assistant import engine


def test_clock_times_are_read_in_vietnam_time():
    assert engine._clock_time("9:30") == "09:30"
    assert engine._clock_time("21h05") == "21:05"
    assert engine._clock_time("25:00") is None and engine._clock_time("chiều") is None
    now = datetime(2026, 11, 1, 7, 0, tzinfo=engine._VN)
    assert engine._minutes_until("09:30", now) == 150
    # Already passed today: tomorrow, within the 10-hour limit or refused.
    assert engine._minutes_until("06:30", datetime(2026, 11, 1, 23, 0, tzinfo=engine._VN)) == 450
    assert engine._minutes_until("06:30", now) is None


def test_the_action_carries_the_clock_time_and_its_minutes():
    soon = (datetime.now(engine._VN) + timedelta(hours=2)).strftime("%H:%M")
    out = engine.validate_action("start_timed_charging", {"until": soon, "target_percent": 85}, {})
    assert out["until"] == soon and out["target_percent"] == 85
    assert 118 <= out["minutes"] <= 121
    # Minutes alone still work as before.
    assert engine.validate_action("start_timed_charging", {"minutes": 30}, {}) == {"minutes": 30}
