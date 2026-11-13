"""QA 152: battery health says how sure it is and how it moved over time."""
from datetime import datetime, timedelta, timezone

from shelly import charge_model

NOW = datetime(2026, 11, 13, tzinfo=timezone.utc)


def _charge(i: int, wh: float, days: float, **extra) -> dict:
    return {"sessionId": f"s{i}", "whPerPct": wh, "energyWh": wh * 50, "startPct": 20,
            "actualEndPct": 70, "censored": False, "labelSource": "user",
            "at": (NOW + timedelta(days=days)).isoformat(), **extra}


def test_the_estimate_itself_is_computed_as_before():
    samples = [_charge(i, 26.5, -i) for i in range(7)]
    plain = charge_model.battery_health(samples, 2400)
    with_history = charge_model.battery_health(samples, 2400, history=samples)
    assert plain["estimate"] == with_history["estimate"]
    assert plain["estimate"]["sohPct"] == 99.4


def test_spread_tells_tight_readings_from_scattered_ones():
    tight = charge_model.battery_health([_charge(i, 26.5 + 0.05 * (i % 3), -i) for i in range(8)], 2400)
    loose = charge_model.battery_health(
        [_charge(i, wh, -i) for i, wh in enumerate([22.7, 26.6, 26.7, 24.0, 26.7, 26.5, 23.8, 26.6])], 2400)
    assert tight["spread"]["perChargePct"] < 1 and tight["spread"]["uncertaintyPct"] < 0.5
    assert loose["spread"]["perChargePct"] > tight["spread"]["perChargePct"]
    assert loose["spread"]["lowPct"] < 90 < loose["spread"]["highPct"]
    assert charge_model.battery_health([], 2400)["spread"] is None


def test_baseline_needs_enough_charges_over_enough_days():
    few = [_charge(i, 26.5, -i * 10) for i in range(8)]
    assert charge_model.battery_health(few[-5:], 2400, history=few)["baseline"] is None
    quick = [_charge(i, 26.5, -i) for i in range(20)]
    assert charge_model.battery_health(quick[:10], 2400, history=quick)["baseline"] is None


def test_baseline_follows_a_battery_that_wears():
    # 30 charges over 300 days, each needing a little less energy per %.
    ledger = [_charge(i, 26.6 * (1 - 0.004 * i), -300 + i * 10) for i in range(30)]
    result = charge_model.battery_health(ledger[-10:], 2400, history=ledger)
    baseline = result["baseline"]
    assert baseline["charges"] == 30 and baseline["days"] == 290
    assert baseline["changePct"] < -8 and baseline["latestPct"] < baseline["firstPct"]
    assert len(result["trend"]) == 30
    # Without the ledger the old short trend is what comes back.
    assert len(charge_model.battery_health(ledger[-10:], 2400)["trend"]) == 10


def test_censored_and_duplicate_ledger_rows_are_left_out():
    samples = [_charge(i, 26.5, -i) for i in range(6)]
    ledger = [*samples, _charge(50, 20.0, -100, censored=True)]
    result = charge_model.battery_health(samples, 2400, history=ledger)
    assert len(result["trend"]) == 6
