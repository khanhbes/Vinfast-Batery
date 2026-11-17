"""QA 164 (owner's choice): battery health against the battery's own start.

The main figure is the capacity now against the first months the app followed
the battery (it does not depend on the assumed charger efficiency); a monthly
log keeps it for the battery's whole life, past the 200-charge ledger.
"""
from __future__ import annotations

import os
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from shelly import charge_model as cm  # noqa: E402

START = datetime(2026, 1, 5, 8, 0, tzinfo=timezone.utc)


def _charges(n, *, every_days=3.0, wh_at=lambda i: 26.0, start=START, gain=(15, 80), sid="c"):
    out = []
    for i in range(n):
        lo, hi = gain
        out.append({
            "sessionId": f"{sid}{i}", "at": (start + timedelta(days=every_days * i)).isoformat(),
            "startPct": float(lo), "actualEndPct": float(hi),
            "energyWh": round(wh_at(i) * (hi - lo), 2), "whPerPct": wh_at(i),
            "censored": False, "labelSource": "user",
        })
    return out


def _health(charges, *, efficiency=cm.DEFAULT_EFFICIENCY, now=None, log=None):
    now = now or cm._parse_at(charges[-1]["at"]) + timedelta(hours=1)
    return cm.battery_health(charges[-12:], 2400, efficiency, history=charges, now=now, log=log)


def test_reference_waits_for_enough_charges_and_days():
    few = _charges(6)
    tracking = _health(few)["tracking"]
    assert tracking["status"] == "building"
    assert tracking["needCharges"] == 2
    quick = _charges(10, every_days=1)  # 10 charges in 9 days: not long enough
    assert _health(quick)["tracking"]["status"] == "building"
    assert _health(quick)["tracking"]["needDays"] > 0
    ready = _charges(12)
    tracking = _health(ready)["tracking"]
    assert tracking["status"] == "ready"
    assert abs(tracking["relativePct"] - 100.0) < 0.2


def test_relative_figure_does_not_depend_on_the_charger_efficiency():
    charges = _charges(30)
    low = _health(charges, efficiency=0.85)
    high = _health(charges, efficiency=0.95)
    assert low["estimate"]["sohPct"] != high["estimate"]["sohPct"]
    assert low["tracking"]["relativePct"] == high["tracking"]["relativePct"]


def test_a_wearing_battery_shows_the_loss_against_its_start():
    # 0.5 % less capacity per month over two years (about 10 % in all).
    charges = _charges(240, every_days=3.0, wh_at=lambda i: 26.0 * (1 - 0.10 * i / 239))
    result = _health(charges)
    assert result["tracking"]["status"] == "ready"
    assert 88.5 <= result["tracking"]["relativePct"] <= 92.5
    months = result["tracking"]["monthly"]
    assert months[0]["relativePct"] > months[-1]["relativePct"] + 6


def test_monthly_log_outlives_the_ledger_and_the_reference_never_moves():
    profile = cm.LearnedProfile(wh_per_pct=26.0)
    charges = _charges(320, every_days=2.5, wh_at=lambda i: 26.0 * (1 - 0.08 * i / 319))
    reference = None
    for charge in charges:
        sample = {**charge, "estimatedEndPct": charge["actualEndPct"], "avgPowerW": 420}
        profile, outcome = cm.queue_sample(profile, sample, base_wh_per_pct=26.0,
                                           now=cm._parse_at(charge["at"]))
        assert outcome == "queued"
        log = profile.health_log
        if reference is None and log and log.get("reference"):
            reference = dict(log["reference"])
    assert len(profile.ledger) == cm.MAX_LEDGER_CHARGES
    log = profile.health_log
    assert log["reference"] == reference  # fixed once, from the first months
    assert reference["months"][0] == "2026-01"
    ledger_months = {cm._month_key(cm._parse_at(c["at"])) for c in profile.ledger}
    assert len(log["months"]) > len(ledger_months)  # months older than the ledger stay
    # Survives storage.
    again = cm.LearnedProfile.from_dict(profile.to_dict())
    assert again.health_log == log
    result = cm.battery_health([*again.samples, *again.pending], 2400, history=again.ledger,
                               now=cm._parse_at(charges[-1]["at"]), log=again.health_log)
    assert result["tracking"]["since"].startswith("2026-01")
    assert 90 <= result["tracking"]["relativePct"] <= 94


def test_outliers_are_judged_against_nearby_charges():
    charges = _charges(20)
    charges[9]["energyWh"] = round(charges[9]["energyWh"] * 1.25, 2)  # gauge lag: 125 %
    log = cm.update_health_log(None, charges)
    assert sum(m["dropped"] for m in log["months"]) == 1
    assert abs(cm._pooled(log["months"])["whPerPct"] - 26.0) < 0.01


def test_months_without_charges_give_a_stale_figure_not_nothing():
    charges = _charges(12)
    much_later = cm._parse_at(charges[-1]["at"]) + timedelta(days=200)
    result = _health(charges, now=much_later)
    assert result["estimate"]["stale"] is True
    assert result["estimate"]["confidence"] == "low"
    assert result["tracking"]["status"] == "ready"


def test_absolute_error_includes_the_charger_efficiency():
    result = _health(_charges(20))
    spread = result["spread"]
    assert spread["totalPct"] > spread["uncertaintyPct"]
    assert spread["totalPct"] >= result["estimate"]["sohPct"] * cm.HEALTH_EFFICIENCY_SPREAD


def test_a_stored_log_with_a_partial_oldest_month_is_kept():
    first = _charges(40, every_days=1)
    log = cm.update_health_log(None, first)
    january = next(m for m in log["months"] if m["month"] == "2026-01")
    # The ledger lost the first 20 charges: January there is partial.
    later = cm.update_health_log(log, first[20:], complete=False)
    assert next(m for m in later["months"] if m["month"] == "2026-01") == january


def test_learning_route_hides_the_months_for_free(monkeypatch):
    # The tracking stays (main figure for every plan); the months are the trend.
    from shelly import learning

    class _Ent:
        def allows(self, uid, feature):
            return False

    class _Profile:
        learned = cm.LearnedProfile(ledger=_charges(30)).to_dict()
        consent_enabled = True

    class _Repo:
        def get_personal_profile(self, uid, vid):
            return _Profile()

    service = learning.VehicleLearningMixin.__new__(learning.VehicleLearningMixin)
    service.repository = _Repo()
    service.entitlements = _Ent()
    service.clock = lambda: cm._parse_at(_charges(30)[-1]["at"])
    monkeypatch.setattr(service, "_owned_vehicle",
                        lambda uid, vid: {"nominalCapacityWh": 2400}, raising=False)
    result = service.battery_health("u1", "v1")
    assert result["tracking"]["status"] == "ready"
    assert result["tracking"]["monthly"] == []
