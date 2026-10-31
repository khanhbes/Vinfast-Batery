"""QA 140 (items 1, 9): charging habits, the overall assessment and the
suggested schedule are built only from the owner's finished sessions."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from shelly.habits import VN, charge_habits

NOW = datetime(2026, 11, 1, 12, 0, tzinfo=timezone.utc)


def _session(days_ago, hour, start, end, *, wh=900, reason="planned_timer", confirmed=True,
             temp=None, state="completed"):
    at = (NOW - timedelta(days=days_ago)).astimezone(VN).replace(hour=hour, minute=5)
    at = at.astimezone(timezone.utc)
    return SimpleNamespace(
        state=state, hidden_at=None, energy_used_wh=wh, stopped_at=at + timedelta(hours=2),
        relay_on_at=at, created_at=at - timedelta(seconds=8), start_soc=start,
        actual_end_soc=end if confirmed else None, estimated_soc=end, stop_reason=reason,
        shelly_temperature_c=temp)


def test_too_few_charges_give_numbers_but_no_verdict():
    out = charge_habits([_session(1, 21, 30, 80), _session(3, 21, 30, 80)], now=NOW)
    assert out["sessions"] == 2 and not out["enough"]
    assert out["score"] is None and out["schedule"] is None
    assert out["stats"]["avgStartPct"] == 30


def test_good_habits_score_high_with_no_warnings():
    sessions = [_session(d, 21, 30, 85) for d in range(1, 15, 2)]
    out = charge_habits(sessions, now=NOW, wh_per_pct=26, power_w=440)
    assert out["enough"] and out["score"] >= 90 and out["grade"] == "good"
    assert all(c["level"] != "warn" for c in out["comments"])
    schedule = out["schedule"]
    assert schedule["startHour"] == 21 and schedule["targetPct"] == 85
    # 30 -> 85 % x 26 Wh / 440 W = 3.25 h.
    assert schedule["estimatedMinutes"] == 195


def test_full_charges_and_deep_discharges_lower_the_score_and_say_why():
    sessions = [_session(d, 7, 8, 100, reason="battery_full") for d in range(1, 12)]
    out = charge_habits(sessions, now=NOW)
    assert out["score"] <= 60 and out["grade"] == "poor"
    texts = " ".join(c["text"] for c in out["comments"])
    assert "100%" in texts and "dưới 15%" in texts
    assert any("80–90%" in s for s in out["suggestions"])
    assert out["stats"]["equivalentCycles"] == round(11 * 92 / 100, 1)


def test_a_hot_outlet_is_flagged():
    sessions = [_session(d, 21, 30, 85, temp=63 if d == 3 else 41) for d in range(1, 9)]
    out = charge_habits(sessions, now=NOW)
    assert any("63 °C" in c["text"] for c in out["comments"])


def test_plugged_in_and_out_and_old_sessions_are_ignored():
    sessions = [_session(1, 21, 30, 85, wh=10), _session(90, 21, 30, 85),
                _session(2, 21, 30, 85, state="unknown"), _session(3, 21, 30, 85)]
    out = charge_habits(sessions, now=NOW)
    assert out["sessions"] == 1


def test_charts_count_start_hours_and_weekly_energy():
    sessions = [_session(d, 22, 40, 90) for d in range(1, 8)]
    out = charge_habits(sessions, now=NOW)
    heat = out["charts"]["weekdayHour"]
    assert sum(row[22] for row in heat) == 7 and sum(map(sum, heat)) == 7
    assert out["charts"]["startPct"][4] == 7 and out["charts"]["endPct"][9] == 7
    assert round(sum(w["kWh"] for w in out["charts"]["weeklyKWh"]), 2) == 6.3
    assert out["stats"]["nightShare"] == 1.0


def test_free_sees_the_score_and_one_comment_pro_sees_everything():
    from tests.test_task126_charge_model import _service

    service, repo, _provider, clock = _service()
    clock.now = NOW
    sessions = [_session(d, 7, 8, 100, reason="battery_full") for d in range(1, 12)]
    for item in sessions:
        item.vehicle_id = "car"
        item.average_power_w = 440
    repo.history = lambda uid, limit=20: sessions

    class _Plan:
        def __init__(self, allowed):
            self.allowed = allowed

        def allows(self, uid, feature):
            return self.allowed

    service.entitlements = _Plan(False)
    free = service.charge_assessment("owner", "car")
    assert free["full"] is False and free["score"] is not None
    assert len(free["comments"]) == 1 and free["charts"] is None and free["schedule"] is None
    service.entitlements = _Plan(True)
    pro = service.charge_assessment("owner", "car")
    assert pro["full"] is True and len(pro["comments"]) >= 2
    assert pro["charts"] is not None and pro["schedule"]["startHour"] == 7
