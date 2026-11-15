"""QA 158: the gauge drifts between full charges. Its trust (charges and
energy since the last full one, every real charge counted) sets the margin,
the weight of each charge in learning and when to recalibrate; each full
charge measures the drift and recalibrates."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from shelly import charge_ai, charge_model
from shelly.charge_model import LearnedProfile

NOW = datetime(2026, 11, 15, 8, 0, tzinfo=timezone.utc)


def _session(i, *, days_ago, wh=1500.0, reason="target_reached", end=None, state="completed"):
    began = NOW - timedelta(days=days_ago, hours=3)
    return SimpleNamespace(session_id=f"s{i}", vehicle_id="car", state=state, energy_used_wh=wh,
                           created_at=began, stopped_at=began + timedelta(hours=3),
                           updated_at=began + timedelta(hours=3), stop_reason=reason,
                           actual_end_soc=end)


def _row(i, *, day, start, actual, wh=26.4, gain=None, trust=None, label="user"):
    gain = gain if gain is not None else actual - start
    row = {"sessionId": f"r{i}", "whPerPct": wh, "energyWh": wh * gain, "startPct": float(start),
           "actualEndPct": float(actual), "censored": False, "labelSource": label,
           "at": (NOW - timedelta(days=day)).isoformat()}
    if trust:
        row["trust"] = trust
    return row


# ── trust ──────────────────────────────────────────────────────────────────

def test_a_timed_charge_that_reached_full_is_an_anchor_and_every_real_charge_counts():
    sessions = [
        _session(0, days_ago=10, reason="planned_timer", wh=2600),
        _session(1, days_ago=9, reason="battery_full", wh=2500),  # timed, reached full
        _session(2, days_ago=6),                                   # no % typed
        _session(3, days_ago=4),
        _session(4, days_ago=2, wh=10),                            # no load: not a charge
        _session(5, days_ago=1, state="active"),                   # still running
    ]
    trust = charge_ai.gauge_trust(LearnedProfile(wh_per_pct=26.4), sessions, now=NOW)
    assert trust["anchored"] and trust["sessionsSinceFull"] == 2
    assert trust["fullsSinceFull"] == pytest.approx(3000 / 2640, abs=0.01)
    assert trust["level"] == "medium" and trust["source"] == "sessions"
    # Right after the full charge: high.
    early = charge_ai.gauge_trust(LearnedProfile(wh_per_pct=26.4), sessions,
                                  before=sessions[2].created_at, now=NOW)
    assert early["sessionsSinceFull"] == 0 and early["level"] == "high"


def test_energy_also_counts_and_no_full_charge_is_never_high():
    one_big = [_session(0, days_ago=5, reason="battery_full"), _session(1, days_ago=2, wh=4500)]
    assert charge_ai.gauge_trust(LearnedProfile(wh_per_pct=26.4), one_big, now=NOW)["level"] == "medium"
    never = [_session(0, days_ago=2)]
    trust = charge_ai.gauge_trust(LearnedProfile(wh_per_pct=26.4), never, now=NOW)
    assert not trust["anchored"] and trust["level"] == "medium"
    many = [_session(i, days_ago=10 - i) for i in range(1, 6)]
    assert charge_ai.gauge_trust(LearnedProfile(wh_per_pct=26.4),
                                 [_session(0, days_ago=11, reason="battery_full"), *many],
                                 now=NOW)["level"] == "low"


def test_no_margin_without_a_full_charge_none_right_after_one_more_later():
    profile = LearnedProfile(wh_per_pct=26.4)
    def margin(sessions, start=10, target=80):
        trust = charge_ai.gauge_trust(profile, sessions, now=NOW)
        return charge_ai.drift_margin(profile, start, target, trust)
    full = _session(0, days_ago=10, reason="battery_full")
    assert margin([_session(i, days_ago=9 - i) for i in range(1, 5)]) == 0.0  # never anchored
    assert margin([full]) == 0.0
    assert margin([full, _session(1, days_ago=8)]) == 0.0
    assert margin([full, _session(1, days_ago=8), _session(2, days_ago=6)]) == 1.0
    low = [full, *[_session(i, days_ago=9 - i) for i in range(1, 6)]]
    assert margin(low) == 3.0
    assert margin(low, start=10, target=100) == 0.0  # the charger ends a charge to full
    assert margin(low, start=70, target=80) == 1.0   # at most a tenth of the charge


# ── learning on clean charges ──────────────────────────────────────────────

def test_older_charges_get_the_trust_of_their_place():
    rows = [_row(0, day=30, start=0, actual=100), _row(1, day=28, start=10, actual=80),
            _row(2, day=26, start=10, actual=80), _row(3, day=24, start=10, actual=80),
            _row(4, day=22, start=10, actual=80), _row(5, day=20, start=10, actual=80),
            _row(6, day=18, start=10, actual=100), _row(7, day=16, start=10, actual=80)]
    charge_model.stamp_trust(rows)
    assert [row["trust"] for row in rows[1:6]] == ["high", "high", "medium", "medium", "low"]
    assert rows[7]["trust"] == "high"
    kept = [{**rows[1], "trust": "low"}]
    charge_model.stamp_trust(kept)
    assert kept[0]["trust"] == "low"  # a stored trust is never overwritten


def test_charges_far_from_a_full_one_barely_move_wh_per_pct():
    clean = [_row(i, day=10 + i, start=10, actual=80, wh=26.4, trust="high") for i in range(3)]
    drifted = [_row(10 + i, day=5 + i, start=10, actual=80, wh=32.0, trust="low") for i in range(4)]
    wh = charge_model._robust_wh([*clean, *drifted], 26.67, NOW)
    assert wh == pytest.approx(26.4)
    # Judged on the clean charges when there are three of them.
    assert all(item["trust"] == "high" for item in charge_model._scoring_set([*clean, *drifted]))


def test_only_drifted_charges_lately_keep_the_value_in_use():
    old_clean = [_row(i, day=100 + i, start=10, actual=80, trust="high") for i in range(3)]
    recent = [_row(10 + i, day=2 + i, start=10, actual=80, wh=31.0, trust="low") for i in range(3)]
    profile = LearnedProfile(wh_per_pct=26.4, samples=old_clean, pending=recent)
    updated, report = charge_model.train(profile, base_wh_per_pct=26.67, now=NOW)
    assert report["decision"] == "kept_no_clean_data" and updated.wh_per_pct == 26.4
    assert updated.pending == [] and len(updated.samples) == 6


# ── recalibration at a full charge ─────────────────────────────────────────

def test_a_full_charge_measures_the_drift_and_recalibrates_at_most_halfway():
    samples = [_row(i, day=20 + i, start=10, actual=80, wh=26.4, trust="high") for i in range(4)]
    newer = [_row(10 + i, day=5 + i, start=10, actual=80, wh=29.0, trust="high") for i in range(4)]
    # The gauge read 0 % but took 2284 Wh to full: it had drifted 13.5 % low.
    full = _row(99, day=1, start=0, actual=100, wh=22.84, label="taper_full", trust="low")
    profile = LearnedProfile(wh_per_pct=26.4, samples=samples, pending=[*newer, full])
    updated, report = charge_model.recalibrate(
        profile, base_wh_per_pct=26.67, now=NOW, full=full, exact=True,
        sessions_since=5, fulls_since=3.2, days_since=12)
    assert report["reason"] == "full_charge"
    assert report["driftPct"] == pytest.approx(100 - 2284 / 26.4, abs=0.01)
    assert updated.drift_log[-1]["sessions"] == 5 and updated.drift_log[-1]["fulls"] == 3.2
    # The clean charges say about 29: more than 3 % away, so halfway.
    assert report["stepLimited"] is True
    assert 26.4 < updated.wh_per_pct < 29.0
    assert updated.wh_history[-1]["whPerPct"] == 26.4
    assert updated.pending == []


def test_a_typed_100_is_not_a_drift_measure():
    full = _row(1, day=1, start=10, actual=100, label="user")
    profile = LearnedProfile(wh_per_pct=26.4, samples=[_row(0, day=3, start=10, actual=80)], pending=[full])
    updated, report = charge_model.recalibrate(profile, base_wh_per_pct=26.67, now=NOW, full=full,
                                               exact=False, sessions_since=1, fulls_since=0.7,
                                               days_since=3)
    assert report["driftPct"] is None and updated.drift_log == []


def test_trust_limits_follow_the_measured_drift():
    log = [{"driftPct": 6.0, "fulls": 2.0} for _ in range(5)]
    calibration = charge_model.calibrate_trust(log, NOW)
    assert calibration["driftPctPerFull"] == 3.0
    assert calibration["highFulls"] == 0.7 and calibration["mediumFulls"] == 1.2
    assert charge_model.calibrate_trust(log[:4], NOW) is None
    # Limits read back through the profile.
    assert charge_model.trust_level(1, 1.0, anchored=True, limits=calibration) == "medium"
    assert charge_model.trust_level(1, 1.0, anchored=True) == "high"


def test_a_wearing_battery_is_followed_faster():
    prior = [_row(i, day=120 + i, start=10, actual=80, wh=26.4, trust="high") for i in range(3)]
    recent = [_row(10 + i, day=10 + i, start=10, actual=80, wh=25.2, trust="high") for i in range(3)]
    trend = charge_model.wh_trend([*prior, *recent], NOW)
    assert trend["fastFollow"] is True and trend["whDropPct"] == pytest.approx(4.5, abs=0.1)
    assert charge_model.wh_trend(recent, NOW) is None


def test_the_profile_keeps_what_it_measured():
    profile = LearnedProfile(wh_per_pct=26.4, drift_log=[{"driftPct": 2.0}],
                             trust_calibration={"highFulls": 1.0}, wh_history=[{"whPerPct": 26.1}],
                             cross_log=[{"km": 40}], trend={"fastFollow": False})
    again = LearnedProfile.from_dict(profile.to_dict())
    assert again.drift_log == profile.drift_log and again.cross_log == profile.cross_log
    assert again.trust_calibration == {"highFulls": 1.0} and again.trend == {"fastFollow": False}
    assert again.wh_history == [{"whPerPct": 26.1}]


def test_the_report_and_the_watch():
    rows = [_row(0, day=30, start=0, actual=100)]
    rows += [_row(1 + i, day=28 - i, start=10, actual=80, wh=26.4 * (1.05 if i % 2 else 0.95))
             for i in range(2)]
    status = charge_ai.status(LearnedProfile(wh_per_pct=26.4, ledger=rows))
    assert status["drift"]["high"]["n"] == 2 and status["trust"]["level"] == "medium"
    assert status["needsCalibration"] is False
