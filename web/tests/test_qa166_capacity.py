"""QA 166 (owner's choice, 18/11/2026): the battery's capacity measured
rather than assumed.

Every charge counts by 1/σ² of its gauge error (learned from the vehicle's
own charges), the energy counted with the charger idle is left out, what more
charges cannot reduce (the wall-to-battery factor, the rating, the meter) is
reported apart, and a new charger or a second battery starts its own epoch. A
simulator with a known battery checks that the result is not biased and that
its stated error is right.

QA 166 (2), from the owner's charges of 18/11/2026: the gauge drifts low
between full charges (14 points), so a charge to the charger's full signal
counts only right after a full one, the scooter shutting off at the gauge's
0 % is a gauge reading, the charger's rated output caps the wall-to-battery
factor, and a QA 164 reference that can no longer be pooled is set again once.
"""
from __future__ import annotations

import math
import random
from datetime import datetime, timedelta, timezone

import pytest

from shelly import charge_model as cm
from shelly import learning
from shelly.repositories import SmartChargeRepository
from tests.test_task126_charge_model import _service, _start_target
from tests.test_task127_learning import _poll as _poll_full
from tests.test_task127_learning import _service as _full_service

START = datetime(2026, 9, 1, 8, 0, tzinfo=timezone.utc)
TRUE_WH = 26.0  # wall Wh per 1 % of the simulated battery
TRUTH = round(TRUE_WH * 100 * cm.DEFAULT_EFFICIENCY / 2400 * 100, 1)  # 97.5 %


def _charge(i, start, end, wh, *, days, label="user", **extra):
    return {"sessionId": f"c{i}", "at": (START + timedelta(days=days)).isoformat(),
            "startPct": float(start), "actualEndPct": float(end),
            "energyWh": round(wh * (end - start), 2), "whPerPct": wh,
            "labelSource": label, "censored": end >= 99 and label != "taper_full", **extra}


def _simulate(seed: int, *, charges: int = 24, full_every: int = 4, jumps: float = 0.0):
    """A battery of TRUE_WH. The gauge is right after a full charge and drifts
    by the owner's measured error for each charge since (whole-% readings);
    ``jumps`` = share of charges where it falls behind by 8-15 points."""
    rng = random.Random(seed)
    out, since_full = [], None
    for i in range(charges):
        full = i % full_every == full_every - 1
        level = ("low" if since_full is None else "high" if since_full == 0
                 else "medium" if since_full < 3 else "low")
        sigma = cm.HEALTH_DRIFT_POINTS[level] / math.sqrt(2)
        start = rng.uniform(10, 40)
        end = 100.0 if full else rng.uniform(60, 90)
        read_start = round(start + rng.gauss(0, sigma))
        read_end = 100 if full else round(end + rng.gauss(0, sigma))
        if not full and rng.random() < jumps:
            read_end -= rng.randint(8, 15)
        energy = TRUE_WH * (end - start)
        gain = max(1, read_end - read_start)
        out.append({"sessionId": f"s{seed}-{i}", "at": (START + timedelta(days=2.5 * i)).isoformat(),
                    "startPct": float(read_start), "actualEndPct": float(read_end),
                    "energyWh": round(energy, 2), "whPerPct": round(energy / gain, 3),
                    "labelSource": "taper_full" if full else "user", "censored": False})
        since_full = 0 if full else (None if since_full is None else since_full + 1)
    return out


def _simulate_drift(seed: int, *, charges: int = 30, full_every: int = 5, synced_full: float = 0.3,
                    per_full: float = cm.HEALTH_FULL_DRIFT_PRIOR):
    """QA 166 (2): the owner's gauge. Right at the charger's full signal, it
    drifts low while riding (``per_full`` points per full discharge). A charge
    stopped midway reads both ends with the same drift; a charge to full ends
    at the true 100 %. ``synced_full``: share of the charges right after a
    full one that go to full too (the guided test)."""
    rng = random.Random(seed)
    out, level, offset, after_full = [], 100.0, 0.0, False
    for i in range(charges):
        start = rng.uniform(10, 40)
        offset -= per_full * (level - start) / 100  # the ride since the last charge
        full = i % full_every == full_every - 1 or (after_full and rng.random() < synced_full)
        end = 100.0 if full else rng.uniform(60, 90)
        read_start = round(start + offset + rng.gauss(0, 0.5))
        read_end = 100 if full else round(end + offset + rng.gauss(0, 0.5))
        energy = TRUE_WH * (end - start)
        gain = max(1, read_end - read_start)
        out.append({"sessionId": f"d{seed}-{i}", "at": (START + timedelta(days=2.5 * i)).isoformat(),
                    "startPct": float(read_start), "actualEndPct": float(read_end),
                    "energyWh": round(energy, 2), "whPerPct": round(energy / gain, 3),
                    "labelSource": "taper_full" if full else "user", "censored": False})
        level, after_full = end, full
        if full:
            offset = 0.0
    return out


def _estimate(charges):
    now = cm._parse_at(charges[-1]["at"]) + timedelta(hours=1)
    return cm.battery_health(charges, 2400, history=charges, now=now)


def _gain_pooled(charges):
    """What a plain pooled Wh per 1 % (by % gained only) would say."""
    used = [c for c in charges if not c["censored"] and c["actualEndPct"] - c["startPct"] >= 20]
    wh = sum(c["energyWh"] for c in used) / sum(c["actualEndPct"] - c["startPct"] for c in used)
    return wh * 100 * cm.DEFAULT_EFFICIENCY / 2400 * 100


# ── The simulated battery ────────────────────────────────────────────────

def test_the_result_is_not_biased_and_its_error_is_right():
    errors, covered = [], 0
    for seed in range(300):
        result = _estimate(_simulate(seed))
        error = result["estimate"]["sohPct"] - TRUTH
        errors.append(error)
        covered += abs(error) <= result["spread"]["uncertaintyPct"]
    bias = sum(errors) / len(errors)
    assert abs(bias) < 0.3
    assert 0.60 <= covered / len(errors) <= 0.76


def test_weighting_by_the_measured_error_beats_a_plain_pool():
    new, plain = [], []
    for seed in range(200):
        charges = _simulate(seed)
        new.append(_estimate(charges)["estimate"]["sohPct"] - TRUTH)
        plain.append(_gain_pooled(charges) - TRUTH)
    rmse = lambda values: math.sqrt(sum(v * v for v in values) / len(values))  # noqa: E731
    assert rmse(new) < rmse(plain) * 0.6


def test_a_gauge_that_jumps_now_and_then_does_not_bias_it():
    errors = [_estimate(_simulate(seed, jumps=0.15))["estimate"]["sohPct"] - TRUTH
              for seed in range(200)]
    assert abs(sum(errors) / len(errors)) < 0.5


def test_a_gauge_that_drifts_between_full_charges_does_not_bias_it():
    """The owner's gauge (QA 166 (2)): charges to full carry their start's
    drift and pull a plain pool low; counted only right after a full one,
    with that drift as their error, they do not."""
    new, plain = [], []
    for seed in range(200):
        charges = _simulate_drift(seed)
        new.append(_estimate(charges)["estimate"]["sohPct"] - TRUTH)
        plain.append(_gain_pooled(charges) - TRUTH)
    assert abs(sum(new) / len(new)) < 0.3
    assert sum(plain) / len(plain) < -1.0
    # Charges to full after the gauge drifted are listed, not counted.
    rows = _estimate(_simulate_drift(3))["charges"]
    drifted = [row for row in rows if row["reason"] == "drift"]
    assert drifted and all(row["trust"] != "high" for row in drifted)
    assert all(row["used"] for row in rows if row["trust"] == "high" and row["endPct"] == 100)


def test_each_vehicle_learns_its_own_gauge_error():
    steady = [_charge(i, 20, 80, TRUE_WH, days=i) for i in range(30)]
    learned = _estimate(steady)["sigmas"]
    # 30 charges that agree: far below the starting 6.8 points (which still
    # counts as 4 charges).
    assert learned["points"]["low"] < 2.5 and learned["charges"]["low"] >= 20
    noisy = [_charge(i, 20, 80, TRUE_WH * (1 + (0.12 if i % 2 else -0.12)), days=i) for i in range(30)]
    assert _estimate(noisy)["sigmas"]["points"]["low"] > 5.0


# ── Measured, not assumed ────────────────────────────────────────────────

def test_idle_energy_is_measured_from_the_curve_and_left_out():
    curve = [{"wh": 0.2, "p": 3.0}, {"wh": 0.4, "p": 2.0},          # charger plugged, scooter not
             {"wh": 7.7, "p": 438.0}, {"wh": 15.0, "p": 440.0},
             {"wh": 15.4, "p": 12.0}, {"wh": 15.6, "p": 10.0}]       # stopped, waiting
    assert cm.idle_energy_wh(curve, 16.0) == pytest.approx(0.2 + 0.2 + 0.2 + 0.4)
    assert cm.idle_energy_wh([], 10.0) is None
    with_tail = [_charge(0, 20, 80, TRUE_WH, days=0, tailWh=round(TRUE_WH * 60 * 0.05, 2))]
    without = [_charge(0, 20, 80, TRUE_WH * 0.95, days=0)]
    assert _estimate(with_tail)["estimate"]["sohPct"] == _estimate(without)["estimate"]["sohPct"]


def test_plateau_power_needs_a_real_curve():
    curve = [{"p": p} for p in (439, 441, 440, 442, 438, 300, 120, 35, 20, 14)]
    assert cm.plateau_power_w(curve) == pytest.approx(440.0, abs=1)
    assert cm.plateau_power_w(curve[:4]) is None


def test_what_more_charges_cannot_reduce_is_reported_apart():
    result = _estimate(_simulate(1))
    soh, spread, systematic = result["estimate"]["sohPct"], result["spread"], result["systematic"]
    assert systematic["factorMeasured"] is False and systematic["nominalSource"] == "catalog"
    assert spread["totalLowPct"] <= soh * cm.HEALTH_FACTOR_LOW / cm.DEFAULT_EFFICIENCY
    assert spread["totalHighPct"] > soh > spread["totalLowPct"]
    # A rating read off the battery and a measured charger narrow it to the measurements.
    charges = _simulate(1)
    now = cm._parse_at(charges[-1]["at"]) + timedelta(hours=1)
    measured = cm.battery_health(charges, 2400, history=charges, now=now, nominal_source="label",
                                 factor={"factor": 0.86, "errorPct": 1.5, "source": "dc"})
    assert measured["systematic"]["factorMeasured"] is True
    assert measured["efficiency"] == pytest.approx(0.86)
    narrow = measured["spread"]["totalHighPct"] - measured["spread"]["totalLowPct"]
    assert narrow < spread["totalHighPct"] - spread["totalLowPct"]
    # The relative figure does not move with any of it.
    assert measured["tracking"]["relativePct"] == result["tracking"]["relativePct"]
    # A factor outside what a charger can be is not a measurement.
    odd = cm.battery_health(charges, 2400, history=charges, now=now, factor={"factor": 1.2})
    assert odd["systematic"]["factorMeasured"] is False


def test_the_chargers_rating_caps_the_factor():
    """QA 166 (2), owner's choice: VinFast rates the Feliz 2025 charger
    400 W and the owner's Shelly reads 444 W at the wall, so the charger is at
    most 90 % efficient and the factor at most 0.873 (x 0.97 x 0.999)."""
    charges = _simulate(1)
    now = cm._parse_at(charges[-1]["at"]) + timedelta(hours=1)
    base = cm.battery_health(charges, 2400, history=charges, now=now)
    rated = cm.battery_health(charges, 2400, history=charges, now=now,
                              charger_rated_w=400, wall_power_w=444)
    systematic = rated["systematic"]
    assert systematic["factorSource"] == "rated" and systematic["factorMeasured"] is False
    assert systematic["factorHigh"] == pytest.approx(0.873, abs=0.0005)
    assert systematic["factorLow"] == cm.HEALTH_FACTOR_LOW
    assert systematic["chargerRatedW"] == 400 and systematic["wallPowerW"] == 444
    assert rated["efficiency"] == pytest.approx((0.81 + 0.873) / 2, abs=0.0005)
    assert rated["estimate"]["sohPct"] == pytest.approx(
        base["estimate"]["sohPct"] * rated["efficiency"] / cm.DEFAULT_EFFICIENCY, abs=0.15)
    assert rated["spread"]["totalHighPct"] < base["spread"]["totalHighPct"]
    assert rated["spread"]["totalLowPct"] == pytest.approx(base["spread"]["totalLowPct"], abs=0.6)
    # The relative figure does not depend on it.
    assert rated["tracking"]["relativePct"] == base["tracking"]["relativePct"]
    # A wall power the rating cannot explain is another charger: no cap.
    for wall in (1100, 380):
        other = cm.battery_health(charges, 2400, history=charges, now=now,
                                  charger_rated_w=400, wall_power_w=wall)
        assert other["systematic"]["factorSource"] is None
        assert other["efficiency"] == cm.DEFAULT_EFFICIENCY
    # A measured factor wins over the rating.
    measured = cm.battery_health(charges, 2400, history=charges, now=now, charger_rated_w=400,
                                 wall_power_w=444, factor={"factor": 0.86, "errorPct": 1.5})
    assert measured["systematic"]["factorMeasured"] is True and measured["efficiency"] == 0.86


def test_the_route_takes_the_rating_from_the_vehicle_then_its_catalog():
    repo = SmartChargeRepository()
    repo._test_catalog_charging["feliz_2025"] = {"maxDcPowerW": 400, "chargeTimeMinutes": 390}
    host = type("Host", (), {"repository": repo})()
    rated = learning.VehicleLearningMixin._charger_rated_w
    assert rated(host, {"chargerRatedW": 360, "catalogId": "feliz_2025"}) == 360
    assert rated(host, {"catalogId": "feliz_2025"}) == 400
    assert rated(host, {"vinfastModelId": "feliz_2025"}) == 400
    assert rated(host, {"catalogId": "evo_200"}) is None
    assert rated(host, {}) is None
    assert rated(host, {"chargerRatedW": "abc"}) is None


# ── Charges to full and the scooter shutting off (QA 166 (2)) ────────────

def test_a_charge_to_full_counts_only_right_after_a_full_one():
    partial = [_charge(i, 20, 80, TRUE_WH, days=i) for i in range(6)]
    # After six partial charges the gauge has drifted: listed, not counted,
    # and not a test (80 % on the owner's 17/11/2026).
    drifted = _charge(10, 27, 100, TRUE_WH * 0.8, days=8, label="taper_full")
    result = _estimate([*partial, drifted])
    row = result["charges"][-1]
    assert not row["used"] and row["reason"] == "drift" and row["kind"] is None
    assert result["test"] is None
    assert result["estimate"]["sohPct"] == pytest.approx(TRUTH, abs=0.2)
    # Right after a full one it counts, its error the drift of one discharge.
    full = _charge(11, 30, 100, TRUE_WH, days=9, label="taper_full")
    synced = _charge(12, 20, 100, TRUE_WH, days=10, label="taper_full")
    result = _estimate([*partial, full, synced])
    row = result["charges"][-1]
    assert row["used"] and row["trust"] == "high" and row["kind"] == "test"
    drop = 100 - 20
    expected = math.hypot(cm.HEALTH_FULL_DRIFT_PRIOR * drop / 100 / drop, cm.HEALTH_CHARGE_FLOOR)
    assert row["sigmaPct"] == pytest.approx(100 * expected * row["sohPct"] / 100, abs=0.1)
    assert result["test"]["sessionId"] == "c12"


def test_the_scooter_shutting_off_is_a_gauge_reading():
    """The owner's scooter shuts off at the gauge's 0 %, and the gauge had
    drifted 14 points (1/11/2026): no error-free anchor."""
    partial = [_charge(i, 20, 80, TRUE_WH, days=i) for i in range(6)]
    shut_off = _charge(10, 0, 100, TRUE_WH * 0.86, days=8, label="taper_full", startSource="cutoff")
    row = _estimate([*partial, shut_off])["charges"][-1]
    assert not row["used"] and row["reason"] == "drift" and row["kind"] is None
    # Right after a full charge it is the best test there is, with the drift
    # of one whole discharge as its error, not none.
    full = _charge(11, 30, 100, TRUE_WH, days=9, label="taper_full")
    deep = _charge(12, 0, 100, TRUE_WH, days=10, label="taper_full", startSource="cutoff")
    row = _estimate([*partial, full, deep])["charges"][-1]
    assert row["used"] and row["kind"] == "full_range"
    assert row["sigmaPct"] > 100 * cm.HEALTH_CHARGE_FLOOR * 4
    # A shut-off reading before a charge stopped midway weighs as any reading.
    midway = _charge(13, 0, 80, TRUE_WH, days=11, startSource="cutoff")
    plain = _charge(13, 0, 80, TRUE_WH, days=11)
    assert (_estimate([*partial, full, midway])["charges"][-1]["sigmaPct"]
            == _estimate([*partial, full, plain])["charges"][-1]["sigmaPct"])


def test_the_gauges_drift_comes_from_the_vehicles_own_log():
    log = [{"sessionId": "a", "driftPct": 14.19, "fulls": 2.77, "sessions": 5,
            "at": "2026-11-17T14:56:13+00:00"},
           {"sessionId": "b", "driftPct": 0.4, "fulls": 0.1, "sessions": 1}]  # too little to say
    drift = cm.gauge_drift(log)
    # The rate leaves out a full charge too soon after another to say much;
    # the latest drift shown is still the latest one measured.
    assert drift["perFullPct"] == pytest.approx(5.12, abs=0.01) and drift["measurements"] == 1
    assert drift["lastPct"] == 0.4 and drift["sessions"] == 1
    assert cm.gauge_drift(log[:1])["lastPct"] == 14.2
    assert cm.gauge_drift([]) is None
    assert cm.full_drift_points(None) == cm.HEALTH_FULL_DRIFT_PRIOR
    partial = [_charge(i, 20, 80, TRUE_WH, days=i) for i in range(6)]
    charges = [*partial, _charge(11, 30, 100, TRUE_WH, days=9, label="taper_full"),
               _charge(12, 20, 100, TRUE_WH, days=10, label="taper_full")]
    now = cm._parse_at(charges[-1]["at"]) + timedelta(hours=1)
    small = cm.battery_health(charges, 2400, history=charges, now=now,
                              drift_log=[{"driftPct": 1.0, "fulls": 1.0}])
    assert small["charges"][-1]["sigmaPct"] < _estimate(charges)["charges"][-1]["sigmaPct"]
    assert small["gaugeDrift"]["perFullPct"] == 1.0
    assert small["sigmas"]["fullDriftPerFull"] == 1.0


def test_one_drift_entry_per_charge():
    """The 100 % typed after the charger's full signal calibrates the same
    charge again: the drift log keeps one entry for it."""
    samples = [_charge(i, 20, 80, TRUE_WH, days=i) for i in range(6)]
    profile = cm.LearnedProfile.from_dict({"whPerPct": TRUE_WH, "powerW": 440, "samples": samples})
    full = _charge(20, 30, 100, TRUE_WH, days=8, label="taper_full")
    now = START + timedelta(days=9)
    once, _ = cm.recalibrate(profile, base_wh_per_pct=TRUE_WH, now=now, full=full, exact=True,
                             sessions_since=5, fulls_since=2.8, days_since=15)
    twice, _ = cm.recalibrate(once, base_wh_per_pct=TRUE_WH, now=now, full=full, exact=True,
                              sessions_since=5, fulls_since=2.8, days_since=15)
    assert [item["sessionId"] for item in twice.drift_log] == ["c20"]


def test_a_full_typed_after_the_chargers_full_signal_stays_measured():
    """1/11/2026: 0 -> 100 % stopped by the charger's full signal, the owner
    then typed 100 % and the charge was left out as censored."""
    service, repo, provider, clock = _full_service()
    session = service.manual_on("owner", 6 * 3600, "qa166-full", vehicle_id="car", current_soc=40)
    _poll_full(service, provider, clock, power=420, minutes=60, wh_per_min=24.5)
    _poll_full(service, provider, clock, power=150, minutes=4)
    _poll_full(service, provider, clock, power=32, minutes=2)
    done = _poll_full(service, provider, clock, power=21, minutes=8)
    assert done.stop_reason == "battery_full"
    clock.advance(minutes=4)
    service.confirm_actual_soc("owner", session.session_id, 100)
    learned = cm.LearnedProfile.from_dict(repo.get_personal_profile("owner", "car").learned)
    entry = next(item for item in learned.ledger if item["sessionId"] == session.session_id)
    assert entry["labelSource"] == "taper_full" and entry["censored"] is False
    assert entry["actualEndPct"] == 100 and entry["endAfterMin"] >= 4
    assert len([item for item in learned.drift_log if item.get("sessionId") == session.session_id]) <= 1


def test_a_scooter_that_shuts_off_above_zero_has_less_than_the_gauge_says():
    charges = [_charge(i, 20, 80, TRUE_WH, days=i) for i in range(10)]
    now = cm._parse_at(charges[-1]["at"])
    plain = cm.battery_health(charges, 2400, history=charges, now=now)
    short = cm.battery_health(charges, 2400, history=charges, now=now, cutoff_pct=8)
    assert short["estimate"]["sohPct"] == pytest.approx(plain["estimate"]["sohPct"] * 0.92, abs=0.1)
    assert short["systematic"]["cutoffPct"] == 8


# ── Epochs ───────────────────────────────────────────────────────────────

def test_a_new_charger_starts_its_own_epoch():
    old = [_charge(i, 20, 80, TRUE_WH, days=i * 2, avgPowerW=440) for i in range(15)]
    # A faster charger: more wall energy per % (lower efficiency), 600 W.
    new = [_charge(20 + i, 20, 80, TRUE_WH * 1.06, days=40 + i * 2, avgPowerW=600) for i in range(6)]
    result = _estimate([*old, *new])
    assert result["charges"][-1]["epoch"] != "e0"
    assert result["estimate"]["sohPct"] == pytest.approx(TRUTH * 1.06, abs=0.3)
    assert result["tracking"]["epochReason"] == "charger"
    reasons = {row["reason"] for row in result["charges"] if not row["used"]}
    assert "epoch" in reasons
    # A cold day (one charge at a lower power) is not a new charger.
    one_off = [*old, _charge(30, 20, 80, TRUE_WH, days=31, avgPowerW=380),
               _charge(31, 20, 80, TRUE_WH, days=32, avgPowerW=440)]
    assert {row["epoch"] for row in _estimate(one_off)["charges"]} == {"e0"}


def test_a_second_battery_starts_its_own_epoch():
    one = [_charge(i, 20, 80, TRUE_WH, days=i * 2) for i in range(10)]
    two = [_charge(20 + i, 20, 80, TRUE_WH * 2, days=30 + i * 2) for i in range(3)]
    result = _estimate([*one, *two])
    assert result["tracking"]["epochReason"] == "battery"
    assert result["estimate"]["sohPct"] == pytest.approx(min(120.0, TRUTH * 2), abs=0.5)


# ── The monthly log ──────────────────────────────────────────────────────

def test_a_version_one_reference_is_computed_again_once():
    charges = [_charge(i, 20, 80, TRUE_WH, days=i * 3) for i in range(30)]
    first = cm.update_health_log(None, charges)
    months = first["references"]["e0"]["months"]
    legacy = {"version": 1, "months": [], "reference": {
        "whPerPct": 25.0, "charges": 8, "effective": 8.0, "scatter": 0.01,
        "from": charges[0]["at"], "to": charges[9]["at"], "months": months,
        "fixedAt": "2026-11-17T00:00:00+00:00"}}
    migrated = cm.update_health_log(legacy, charges)
    reference = migrated["references"]["e0"]
    assert reference["migratedFrom"] == 1 and reference["v"] == cm.HEALTH_LOG_VERSION
    assert reference["whPerPct"] == pytest.approx(TRUE_WH, abs=0.01)
    assert reference["fixedAt"] == "2026-11-17T00:00:00+00:00"
    # Once: the next update keeps it as it is.
    again = cm.update_health_log(migrated, [*charges, _charge(99, 20, 80, TRUE_WH * 0.9, days=100)])
    assert again["references"]["e0"] == reference
    assert "replaced" not in again


def test_a_reference_whose_months_are_gone_is_set_again_once():
    """QA 166 (2), owner's choice: the owner's QA 164 reference (23.70 Wh per
    1 %, fixed 17/11/2026 on a charge whose gauge had drifted 14 points) can
    no longer be pooled the new way: its September left the 12-charge list
    before the ledger began. It is set again once, and kept for the record."""
    charges = [_charge(i, 20, 80, TRUE_WH, days=i * 3) for i in range(30)]
    gone = {"whPerPct": 23.7048, "charges": 13, "effective": 3.36, "scatter": 0.1185,
            "from": "2025-01-05T00:00:00+00:00", "to": "2025-03-20T00:00:00+00:00",
            "months": ["2025-01", "2025-02", "2025-03"], "fixedAt": "2026-11-17T14:56:16+00:00"}
    now = START + timedelta(days=100)
    log = cm.update_health_log({"version": 1, "months": [], "reference": gone}, charges, now=now)
    assert [item["whPerPct"] for item in log["replaced"]] == [23.7048]
    assert log["replaced"][0]["reason"] == "months-missing"
    reference = log["references"]["e0"]
    assert reference["v"] == cm.HEALTH_LOG_VERSION and "migratedFrom" not in reference
    assert reference["whPerPct"] == pytest.approx(TRUE_WH, abs=0.01)
    assert log["reference"] == reference
    # Once: later updates neither move it nor replace it again.
    again = cm.update_health_log(log, [*charges, _charge(99, 20, 80, TRUE_WH * 0.9, days=100)],
                                 now=now + timedelta(days=1))
    assert again["references"]["e0"] == reference
    assert len(again["replaced"]) == 1
    # The relative figure is against the new reference.
    tracking = cm.health_tracking(log, TRUE_WH, 1.0, 2400, cm.DEFAULT_EFFICIENCY)
    assert tracking["relativePct"] == pytest.approx(100.0, abs=0.1)
    # Not enough charges yet for a new one: no reference, the old one kept.
    few = cm.update_health_log({"version": 1, "months": [], "reference": gone}, charges[:2], now=now)
    assert few["references"].get("e0") is None and few["reference"] is None
    assert len(few["replaced"]) == 1
    assert cm.health_tracking(few, TRUE_WH, 1.0, 2400, cm.DEFAULT_EFFICIENCY)["status"] == "building"


def test_the_reference_waits_until_it_is_sure():
    # Every charge right after a full one: sure to 1.5 % after 28 days.
    precise = []
    for i in range(12):
        precise.append(_charge(2 * i, 20, 100, TRUE_WH, days=i * 3, label="taper_full"))
        precise.append(_charge(2 * i + 1, 20, 80, TRUE_WH, days=i * 3 + 1))
    tracking = _estimate(precise)["tracking"]
    assert tracking["status"] == "ready" and tracking["referenceErrorPct"] <= 1.5
    # Noisy charges only: still building after 30 days, but never forever.
    noisy = [_charge(i, 20, 80, TRUE_WH * (1 + (0.1 if i % 2 else -0.1)), days=i * 3) for i in range(11)]
    assert _estimate(noisy)["tracking"]["status"] == "building"
    long = [_charge(i, 20, 80, TRUE_WH * (1 + (0.1 if i % 2 else -0.1)), days=i * 10) for i in range(11)]
    assert _estimate(long)["tracking"]["status"] == "ready"


# ── Where the start % came from ─────────────────────────────────────────

def test_start_provenance_comes_from_the_vehicles_last_reading():
    now = datetime(2026, 11, 18, 9, 0, tzinfo=timezone.utc)
    vehicle = {"currentBattery": 9, "batteryDataSource": "reading_photo",
               "batteryDataUpdatedAt": now - timedelta(minutes=12)}
    assert learning.start_reading_provenance(vehicle, 9, now) == ("reading_photo", 12.0)
    assert learning.start_reading_provenance(vehicle, 30, now) == (None, None)
    assert learning.start_reading_provenance({**vehicle, "batteryCutoff": True, "currentBattery": 0},
                                             0, now)[0] == "cutoff"
    # A cutoff flag left on a higher reading is not a shut-off.
    assert learning.start_reading_provenance({**vehicle, "batteryCutoff": True}, 9, now)[0] == "reading_photo"
    assert learning.start_reading_provenance({**vehicle, "batteryCutoff": True, "currentBattery": 40},
                                             40, now)[0] == "reading_photo"


def test_a_charge_records_its_start_reading_and_its_curve(monkeypatch):
    service, repo, provider, clock = _service(capacity=2400)
    vehicle = {"vehicleId": "car", "ownerUid": "owner", "nominalCapacityWh": 2400}
    monkeypatch.setattr(repo, "vehicle_for_owner",
                        lambda uid, vid: dict(vehicle) if (uid, vid) == ("owner", "car") else None)
    monkeypatch.setattr(repo, "update_vehicle_fields", lambda uid, vid, fields: vehicle.update(fields))
    read_at = (clock.now - timedelta(minutes=6)).isoformat()
    service.add_battery_reading("owner", "car", {"soc": 0, "source": "photo", "cutoff": True,
                                                 "at": read_at}, with_status=False)
    assert vehicle["batteryCutoff"] is True and vehicle["currentBattery"] == 0
    _preview, session = _start_target(service, target=80, start=0)
    assert session.start_soc_source == "cutoff" and session.start_soc_age_min == pytest.approx(6.0)
    provider.status.power_w = 440
    provider.status.energy_wh += 2200
    clock.advance(minutes=290)
    service.current("owner", vehicle_id="car")
    clock.advance(minutes=20)
    service.confirm_actual_soc("owner", session.session_id, 80)
    profile = repo.get_personal_profile("owner", "car")
    entry = cm.LearnedProfile.from_dict(profile.learned).ledger[-1]
    assert entry["startSource"] == "cutoff" and entry["startAgeMin"] == pytest.approx(6.0)
    assert entry["endAfterMin"] >= 20
    # A typed reading without the flag clears it.
    service.add_battery_reading("owner", "car", {"soc": 3, "source": "manual"}, with_status=False)
    assert vehicle["batteryCutoff"] is False
