"""QA 162 (owner's choice): the capacity left is pooled from the charges
that gained enough, weighted by how far the gauge could be trusted and how
recent they are; the guided test counts more; outliers leave; the error is
honest; every charge says why it was used or not."""
from datetime import datetime, timedelta, timezone

from billing.entitlements import EntitlementService
from shelly import charge_model
from tests.test_task126_charge_model import _service, _start_target

NOW = datetime(2026, 11, 16, tzinfo=timezone.utc)
FULL = 2400 / 0.9 / 100  # Wh at the wall per % for 100 % of 2400 Wh


def _c(i, start, end, wh, days=0.0, label="user", **extra):
    censored = end >= 99 and label != "taper_full"
    return {"sessionId": f"s{i}", "startPct": start, "actualEndPct": end,
            "whPerPct": wh, "energyWh": wh * (end - start), "labelSource": label,
            "censored": censored, "at": (NOW + timedelta(days=days)).isoformat(), **extra}


def _health(charges, **kwargs):
    return charge_model.battery_health(charges, 2400, now=NOW, **kwargs)


def test_a_short_charge_is_listed_but_not_used():
    health = _health([_c(0, 20, 35, FULL)])
    assert health["estimate"] is None
    assert health["charges"][0]["reason"] == "short" and not health["charges"][0]["used"]


def test_the_charge_right_after_a_full_one_counts_most():
    charges = [
        _c(0, 10, 100, FULL, -10),            # full: the gauge is right again
        _c(1, 20, 80, FULL, -9),              # first after it: high
        _c(2, 20, 80, FULL * 0.95, -8),       # medium
        _c(3, 20, 80, FULL * 0.95, -7),       # medium
        _c(4, 20, 80, FULL * 0.90, -6),       # low
    ]
    health = _health(charges)
    trusts = [row["trust"] for row in health["charges"]]
    assert trusts[1:] == ["high", "medium", "medium", "low"]
    assert health["charges"][0]["reason"] == "censored"
    # Closer to the trusted charge than a plain average (96.25) would be.
    assert health["estimate"]["sohPct"] > 97


def test_a_gauge_that_falls_behind_and_catches_up_does_not_move_the_result():
    steady = [_c(i, 10, 70, FULL * 0.99, -20 + i) for i in range(5)]
    # The owner's 26/10 and 31/10: 85 % then 121 %.
    pair = [_c(5, 9, 47, FULL * 0.855, -10), _c(6, 8, 58, FULL * 1.215, -5)]
    health = _health([*steady, *pair])
    assert abs(health["estimate"]["sohPct"] - 99.0) <= 0.5
    reasons = {row["startPct"]: row["reason"] for row in health["charges"]}
    assert reasons[9] == "outlier" and reasons[8] == "outlier"


def test_the_guided_test_is_merged_and_counts_more_while_recent():
    others = [_c(i, 20, 70, FULL, -3 + i * 0.1) for i in range(4)]
    as_test = _health([*others, _c(9, 20, 100, FULL * 0.95, 0, label="taper_full")])
    as_charge = _health([*others, _c(9, 20, 80, FULL * 0.95, 0)])
    assert as_test["test"] is not None
    assert as_test["estimate"]["sohPct"] < as_charge["estimate"]["sohPct"] < 100
    # 100 days later (the others charged since): no more double weight.
    later = NOW + timedelta(days=100)
    recent = [_c(10 + i, 20, 70, FULL, 99 + i * 0.1) for i in range(4)]
    old_test = charge_model.battery_health(
        [_c(9, 20, 100, FULL * 0.95, 0, label="taper_full"), *recent], 2400, now=later)
    fresh_test = charge_model.battery_health(
        [*recent, _c(9, 20, 100, FULL * 0.95, 99.5, label="taper_full")], 2400, now=later)
    assert old_test["estimate"]["sohPct"] > fresh_test["estimate"]["sohPct"]


def test_the_error_says_how_sure_it_is():
    one = _health([_c(0, 20, 80, FULL)])
    assert one["estimate"]["confidence"] == "low"
    assert one["spread"]["uncertaintyPct"] >= 3
    many = _health([_c(i, 20, 80, FULL, -i) for i in range(8)])
    assert many["estimate"]["confidence"] == "high"
    assert many["spread"]["uncertaintyPct"] < one["spread"]["uncertaintyPct"]
    # Never surer than the whole-% reading.
    assert many["spread"]["uncertaintyPct"] >= charge_model.HEALTH_READING_FLOOR_PCT
    # Charges that disagree a lot (a third left out) widen it.
    torn = _health([*[_c(i, 20, 80, FULL, -i) for i in range(5)],
                    *[_c(10 + i, 20, 80, FULL * 0.86, -i - 0.5) for i in range(3)]])
    assert torn["spread"]["uncertaintyPct"] > many["spread"]["uncertaintyPct"]


def test_above_the_rating_is_kept_as_measured():
    health = _health([_c(i, 20, 80, FULL * 1.03, -i) for i in range(4)])
    assert health["estimate"]["sohPct"] == 103.0
    assert health["spread"]["lowPct"] < 103.0 < health["spread"]["highPct"]


def test_free_gets_the_estimate_without_the_charge_list():
    service, _repo, provider, clock = _service()
    _preview, session = _start_target(service)
    provider.status.power_w = 440
    provider.status.energy_wh += 1600
    clock.advance(minutes=200)
    service.current("owner", vehicle_id="car")
    service.confirm_actual_soc("owner", session.session_id, 80)
    full = service.battery_health("owner", "car")
    assert full["charges"] and full["charges"][-1]["used"] is True
    service.entitlements = EntitlementService(enforced=True)
    free = service.battery_health("owner", "car")
    assert free["estimate"] is not None and free["charges"] == []
