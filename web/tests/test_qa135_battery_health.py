"""QA 135 — % pin chai: estimate from confirmed charges + the guided test."""
import pytest

from billing.entitlements import EntitlementService
from shelly import charge_model
from shelly.service import SmartChargeError
from tests.test_task126_charge_model import _service, _start_target


def _sample(i, wh_per_pct, *, start=20.0, energy=None, label="user", censored=False):
    return {"sessionId": f"s{i}", "whPerPct": wh_per_pct, "startPct": start,
            "energyWh": energy if energy is not None else wh_per_pct * 60, "labelSource": label,
            "censored": censored, "at": f"2026-10-{10 + i:02d}T10:00:00+00:00"}


def test_estimate_is_the_recent_median_with_confidence():
    # Nominal 2340 Wh; 26 Wh/% x 100 x 0.9 = 2340 Wh -> 100 %.
    samples = [_sample(i, w) for i, w in enumerate([26.0, 23.4, 23.4, 23.4])]
    health = charge_model.battery_health(samples, 2340)
    assert health["estimate"]["sohPct"] == pytest.approx(90.0)
    assert health["estimate"]["capacityWh"] == 2106
    assert health["estimate"]["confidence"] == "medium"
    assert [p["sohPct"] for p in health["trend"]] == [100.0, 90.0, 90.0, 90.0]
    assert health["test"] is None
    few = charge_model.battery_health(samples[:1], 2340)
    assert few["estimate"]["confidence"] == "low"
    many = charge_model.battery_health([_sample(i, 23.4) for i in range(8)], 2340)
    assert many["estimate"]["confidence"] == "high"


def test_censored_charges_and_missing_capacity_are_not_guessed():
    censored = [_sample(1, 30.0, censored=True)]
    assert charge_model.battery_health(censored, 2340)["estimate"] is None
    assert charge_model.battery_health([_sample(1, 26.0)], None)["estimate"] is None


def test_guided_test_needs_a_low_start_and_the_full_battery_signal():
    # 20 % -> full: 1872 Wh at the wall x 0.9 / 80 % = 2106 Wh -> 90 %.
    test = _sample(5, 23.4, start=20, energy=1872, label="taper_full")
    high_start = _sample(6, 23.4, start=50, energy=1170, label="taper_full")
    user_read = _sample(7, 23.4, start=20, energy=1872, label="user")
    health = charge_model.battery_health([test, high_start, user_read], 2340)
    assert health["test"]["sohPct"] == pytest.approx(90.0)
    assert health["test"]["startPct"] == 20 and health["test"]["sessionId"] == "s5"
    assert charge_model.battery_health([high_start, user_read], 2340)["test"] is None


def test_service_uses_the_owners_confirmed_charges_and_is_pro():
    service, _repo, provider, clock = _service()
    _preview, session = _start_target(service)
    provider.status.power_w = 440
    provider.status.energy_wh += 1600  # past 80 % at 26 Wh per %
    clock.advance(minutes=200)
    service.current("owner", vehicle_id="car")
    service.confirm_actual_soc("owner", session.session_id, 80)
    health = service.battery_health("owner", "car")
    assert health["estimate"]["samples"] == 1 and health["estimate"]["confidence"] == "low"
    assert health["nominalCapacityWh"] == 2340
    assert health["testMaxStartPct"] == 30
    service.entitlements = EntitlementService(enforced=True)
    with pytest.raises(SmartChargeError) as caught:
        service.battery_health("owner", "car")
    assert caught.value.code == "premiumRequired"
