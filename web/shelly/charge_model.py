"""One charging model for preview, live SoC, target cutoff and learning.

The scooter has no BMS link, so the only measurement is the Shelly meter
(wall energy and power). The model therefore works in *wall* units:

* ``wh_per_pct``: wall Wh needed for 1 % of battery. It folds charger
  efficiency and real capacity into one number and is learned directly from
  the battery % the user reads on the scooter after a charge.
* ``power_w``: wall power during the constant-current phase.
* ``taper_start_pct``/``taper_power_ratio``: the slower tail near full.

SoC from energy is linear in wall Wh (``start + Wh / wh_per_pct``); only the
time estimate uses the taper. Every value here is an estimate for display and
for the server-side target cutoff, never a permission to switch ON (Task 126).
The Dart twin is ``app/lib/data/services/charge_estimator.dart``; both are
checked against ``tests/fixtures/charge_model_vectors.json``.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from datetime import datetime, timezone

DEFAULT_EFFICIENCY = 0.90
DEFAULT_POWER_W = 400.0
DEFAULT_TAPER_START_PCT = 95.0
DEFAULT_TAPER_POWER_RATIO = 0.75
# Learned values outside these bands are measurement errors, not batteries.
WH_PER_PCT_BAND = (0.6, 1.6)  # x the catalog default
POWER_BAND_W = (60.0, 2450.0)
# Shelly timer for a target charge: generous ceiling over the estimate. The
# server cuts at the target; the device timer only bounds a server outage.
# Owner's measured charges (Task 126, charging_merged.csv) ran up to 1.24x the
# estimate (hot days, lower power): x1.25 left only 9 % headroom and could end
# a healthy charge early, so the ceiling is x1.5 + 20 min (<= 10 h).
CEILING_FACTOR = 1.5
CEILING_EXTRA_SECONDS = 1200
# Below this wall power for this long, the scooter charger has stopped
# (battery full or not plugged in): switch the outlet off.
IDLE_POWER_W = 15.0
IDLE_CUTOFF_SECONDS = 180
# Full-battery signature (owner's observation, Task 127): the scooter charger
# draws ~400 W, then near full falls to ~30 W, ~20 W and lower while it
# balances. After real charging (peak >= FULL_MIN_PEAK_W), wall power staying
# below FULL_TAIL_W for FULL_HOLD_SECONDS means the battery is full; a reading
# back above FULL_REARM_W (charger resumed) restarts the wait.
FULL_MIN_PEAK_W = 150.0
FULL_TAIL_W = 40.0
FULL_REARM_W = 60.0
FULL_HOLD_SECONDS = 300
FULL_MIN_CHARGE_SECONDS = 600
MIN_CONFIRMED_GAIN_PCT = 10.0
MAX_PROFILE_SAMPLES = 12
MAX_PENDING_SAMPLES = 24
HALF_LIFE_DAYS = 90.0
# QA 146: one charge counts by the % it gained (a long charge is less hurt by a
# gauge error of a few %). The catalog value counts like a short charge, so it only
# matters at the start.
# QA 148: a charge that ended at 100 % counts far less, with or without the
# full-battery signal: the gauge resets there, so its Wh/% says how far the gauge
# had drifted (the owner's two 0 -> 100: 26.15 and 22.84). One such charge cannot
# move the catalog value (15 < 20); two can (_robust_wh). Learning 22.84 from one
# would miss the owner's partial charges by 9.7 % on average.
PRIOR_GAIN_PCT = 20.0
FULL_CHARGE_WEIGHT = 0.15
# A target of 100 % ends on the charger's own full signal, never on energy.
FULL_TARGET_PCT = 100.0
# "Đang học" (QA 146): the vehicle's own charges cover at least one full cycle.
LEARNING_MIN_CHARGES = 5
LEARNING_MIN_GAIN_PCT = 100.0
# The scooter's gauge seems to fall behind the energy after some charges and catch
# up on the next one. Recorded on every charge; it moves a cutoff only after a
# training selected that layer (QA 147, charge_ai).
MAX_GAUGE_OFFSET_PCT = 15.0
MAX_LEDGER_CHARGES = 200
GAUGE_RESET_END_PCT = 99.0
SHADOW_MIN_CHARGES = 5
# New labelled charges needed before the app suggests training (Task 127).
# QA 158: how far the gauge is from its last anchor (a charge that reached
# full). On the owner's charges the two after a full one were within about
# 0.5 %, the later ones about 5 %: they teach Wh per 1 % far less.
TRUST_WEIGHT = {"high": 1.0, "medium": 0.35, "low": 0.1}
# Completed charges and energy (in full batteries) since the anchor. The
# energy limits are recalibrated from measured drift (``calibrate_trust``).
TRUST_LIMITS = {"highSessions": 1, "highFulls": 1.5, "mediumSessions": 3, "mediumFulls": 2.5}
TRUST_MIN_SCORED = 3
MAX_DRIFT_LOG = 40
MAX_CROSS_LOG = 60
MAX_WH_HISTORY = 3
DRIFT_CALIBRATION_MIN = 5
# A full-charge recalibration moves Wh per 1 % at most halfway when the
# change is bigger than this.
RECALIBRATE_MAX_STEP = 0.03
# No clean charge for this long: the value in use is kept.
CLEAN_DATA_DAYS = 60
# A battery that wears: Wh per 1 % of clean charges, recent vs before.
TREND_WINDOW_DAYS = 90
TREND_MIN_CHARGES = 3
TREND_DROP = 0.03
FAST_HALF_LIFE_DAYS = 45.0
FIRST_TRAINING_MIN_SAMPLES = 2
TRAINING_MIN_NEW_SAMPLES = 3


@dataclass(frozen=True)
class ChargeParams:
    wh_per_pct: float
    power_w: float
    taper_start_pct: float = DEFAULT_TAPER_START_PCT
    taper_power_ratio: float = DEFAULT_TAPER_POWER_RATIO
    source: str = "vehicle"  # vehicle | personal
    samples: int = 0
    soc_mae: float | None = None
    power_source: str = "default"  # live | personal | vehicle | default


@dataclass(frozen=True)
class ChargeEstimate:
    seconds: int
    low_seconds: int
    high_seconds: int
    energy_wh: float
    params: ChargeParams


@dataclass
class LearnedProfile:
    """Per-vehicle learned values, stored on the personal profile."""
    wh_per_pct: float | None = None
    power_w: float | None = None
    taper_start_pct: float | None = None
    taper_power_ratio: float | None = None
    samples: list[dict] = field(default_factory=list)
    soc_mae: float | None = None
    version: int = 0
    # Task 127: labelled charges collected since the last training. They do
    # not change the estimate until the owner presses "Huấn luyện".
    pending: list[dict] = field(default_factory=list)
    trained_at: str | None = None
    # Energy-based % minus the gauge after the newest labelled charge.
    gauge_offset_pct: float = 0.0
    gauge_offset_at: str | None = None
    # QA 147: every labelled charge, for the small model. ``samples`` stays the
    # short window that the Wh/% fit and battery_health read.
    ledger: list[dict] = field(default_factory=list)
    layer: str = "base"  # base | offset | ai (charge_ai)
    ai_model: dict | None = None
    layer_mae: float | None = None
    # QA 158: the gauge's drift measured at each exact full charge, the trust
    # limits fitted to it, the last Wh per 1 % values (to go back), what the
    # gauge and the odometer said at each plug-in, and a wearing battery.
    drift_log: list[dict] = field(default_factory=list)
    trust_calibration: dict | None = None
    wh_history: list[dict] = field(default_factory=list)
    cross_log: list[dict] = field(default_factory=list)
    trend: dict | None = None
    # QA 164: battery health by month for the battery's whole life (the
    # ledger keeps 200 charges) and the fixed reference from the first
    # months the app followed this battery.
    health_log: dict | None = None

    def to_dict(self) -> dict:
        return {
            "whPerPct": self.wh_per_pct,
            "powerW": self.power_w,
            "taperStartPct": self.taper_start_pct,
            "taperPowerRatio": self.taper_power_ratio,
            "samples": self.samples[-MAX_PROFILE_SAMPLES:],
            "socMae": self.soc_mae,
            "version": self.version,
            "pending": self.pending[-MAX_PENDING_SAMPLES:],
            "trainedAt": self.trained_at,
            "gaugeOffsetPct": self.gauge_offset_pct,
            "gaugeOffsetAt": self.gauge_offset_at,
            "ledger": self.ledger[-MAX_LEDGER_CHARGES:],
            "layer": self.layer,
            "aiModel": self.ai_model,
            "layerMae": self.layer_mae,
            "driftLog": self.drift_log[-MAX_DRIFT_LOG:],
            "trustCalibration": self.trust_calibration,
            "whHistory": self.wh_history[-MAX_WH_HISTORY:],
            "crossLog": self.cross_log[-MAX_CROSS_LOG:],
            "trend": self.trend,
            "healthLog": self.health_log,
        }

    @classmethod
    def from_dict(cls, data: dict | None) -> "LearnedProfile":
        data = data if isinstance(data, dict) else {}
        return cls(
            wh_per_pct=_positive(data.get("whPerPct")),
            power_w=_positive(data.get("powerW")),
            taper_start_pct=_positive(data.get("taperStartPct")),
            taper_power_ratio=_positive(data.get("taperPowerRatio")),
            samples=[dict(item) for item in (data.get("samples") or []) if isinstance(item, dict)],
            soc_mae=_positive(data.get("socMae"), allow_zero=True),
            version=int(data.get("version") or 0),
            pending=[dict(item) for item in (data.get("pending") or []) if isinstance(item, dict)],
            trained_at=str(data["trainedAt"]) if data.get("trainedAt") else None,
            gauge_offset_pct=_finite(data.get("gaugeOffsetPct")),
            gauge_offset_at=str(data["gaugeOffsetAt"]) if data.get("gaugeOffsetAt") else None,
            ledger=[dict(item) for item in (data.get("ledger") or []) if isinstance(item, dict)],
            layer=str(data.get("layer") or "base"),
            ai_model=dict(data["aiModel"]) if isinstance(data.get("aiModel"), dict) else None,
            layer_mae=_positive(data.get("layerMae"), allow_zero=True),
            drift_log=_dicts(data.get("driftLog")),
            trust_calibration=(dict(data["trustCalibration"])
                               if isinstance(data.get("trustCalibration"), dict) else None),
            wh_history=_dicts(data.get("whHistory")),
            cross_log=_dicts(data.get("crossLog")),
            trend=dict(data["trend"]) if isinstance(data.get("trend"), dict) else None,
            health_log=dict(data["healthLog"]) if isinstance(data.get("healthLog"), dict) else None,
        )


def default_wh_per_pct(capacity_wh: float | None, soh_pct: float | None = None) -> float | None:
    capacity = _positive(capacity_wh)
    if capacity is None:
        return None
    soh = _positive(soh_pct)
    if soh is not None:
        capacity *= min(1.0, max(0.5, soh / 100))
    return capacity / 100 / DEFAULT_EFFICIENCY


def params_for(
    *,
    capacity_wh: float | None,
    soh_pct: float | None = None,
    learned: LearnedProfile | None = None,
    live_power_w: float | None = None,
    spec_power_w: float | None = None,
) -> ChargeParams | None:
    """Best available parameters; ``None`` when no capacity is known."""
    base = default_wh_per_pct(capacity_wh, soh_pct)
    learned = learned or LearnedProfile()
    wh = learned.wh_per_pct if learned.wh_per_pct else base
    if wh is None:
        return None
    if base is not None and learned.wh_per_pct:
        low, high = WH_PER_PCT_BAND
        wh = min(base * high, max(base * low, wh))
    power, power_source = None, "default"
    for value, name in ((live_power_w, "live"), (learned.power_w, "personal"),
                        (spec_power_w, "vehicle")):
        number = _positive(value)
        if number is not None and POWER_BAND_W[0] <= number <= POWER_BAND_W[1]:
            power, power_source = number, name
            break
    return ChargeParams(
        wh_per_pct=wh,
        power_w=power or DEFAULT_POWER_W,
        taper_start_pct=learned.taper_start_pct or DEFAULT_TAPER_START_PCT,
        taper_power_ratio=learned.taper_power_ratio or DEFAULT_TAPER_POWER_RATIO,
        source="personal" if learned.wh_per_pct else "vehicle",
        samples=len(learned.samples),
        soc_mae=honest_mae(learned),
        power_source=power_source,
    )


def energy_needed_wh(params: ChargeParams, start_pct: float, target_pct: float) -> float:
    return max(0.0, (_clamp_pct(target_pct) - _clamp_pct(start_pct)) * params.wh_per_pct)


def estimate(params: ChargeParams, start_pct: float, target_pct: float) -> ChargeEstimate:
    start, target = _clamp_pct(start_pct), _clamp_pct(target_pct)
    taper = min(100.0, max(0.0, params.taper_start_pct))
    fast_pct = max(0.0, min(target, taper) - start)
    slow_pct = max(0.0, target - max(start, taper))
    ratio = min(1.0, max(0.2, params.taper_power_ratio))
    hours = (fast_pct * params.wh_per_pct / params.power_w
             + slow_pct * params.wh_per_pct / (params.power_w * ratio))
    seconds = max(0, int(round(hours * 3600)))
    # Uncertainty: personal SoC error (in %) converted to time, or +-15 %.
    if params.soc_mae is not None and params.samples >= 2:
        spread = max(0.05, min(0.4, (params.soc_mae + 1) / max(1.0, target - start)))
    else:
        spread = 0.15
    return ChargeEstimate(
        seconds=seconds,
        low_seconds=int(seconds * (1 - spread)),
        high_seconds=int(math.ceil(seconds * (1 + spread))),
        energy_wh=(target - start) * params.wh_per_pct if target > start else 0.0,
        params=params,
    )


def soc_after(params: ChargeParams, start_pct: float, energy_wh: float) -> float:
    return min(100.0, max(_clamp_pct(start_pct),
                          _clamp_pct(start_pct) + max(0.0, energy_wh) / params.wh_per_pct))


def ceiling_seconds(predicted_seconds: int, max_minutes: int) -> int:
    ceiling = int(math.ceil(predicted_seconds * CEILING_FACTOR + CEILING_EXTRA_SECONDS))
    return max(1, min(max_minutes * 60, ceiling))


def target_reached(energy_used_wh: float, target_energy_wh: float, power_w: float,
                   lead_seconds: float) -> bool:
    """True once the target energy is (about to be) delivered.

    ``lead_seconds`` covers the poll interval and the Cloud OFF latency, so the
    outlet switches off within about half a poll of the exact target.
    """
    lead_wh = max(0.0, power_w) * max(0.0, lead_seconds) / 3600
    return energy_used_wh + lead_wh >= target_energy_wh


def wh_per_pct_sample(energy_wh: float, start_pct: float, actual_end_pct: float) -> float | None:
    gain = actual_end_pct - start_pct
    if gain < MIN_CONFIRMED_GAIN_PCT or energy_wh <= 0:
        return None
    return energy_wh / gain


def full_tail_update(tail_since: datetime | None, *, peak_w: float, power_w: float,
                     now: datetime) -> tuple[datetime | None, bool]:
    """Track the near-full power tail; returns (tail_since, battery_full).

    Pure so the server and tests share it. The scooter charger must have
    really charged first (peak >= FULL_MIN_PEAK_W): an outlet that never
    drew power is the idle cutoff's case, not a full battery.
    """
    if peak_w < FULL_MIN_PEAK_W or power_w >= FULL_REARM_W:
        return None, False
    if power_w >= FULL_TAIL_W:
        # 40-60 W: neither clearly charging nor in the tail; keep waiting.
        return tail_since, False
    since = tail_since or now
    return since, (now - since).total_seconds() >= FULL_HOLD_SECONDS


def queue_sample(
    profile: LearnedProfile,
    sample: dict,
    *,
    base_wh_per_pct: float | None,
    now: datetime | None = None,
) -> tuple[LearnedProfile, str]:
    """Store one labelled charge for the next training; the estimate is not
    changed (Task 127: data is collected silently, the owner trains).

    ``sample`` = {sessionId, energyWh, startPct, actualEndPct, estimatedEndPct,
    avgPowerW, at(ISO), taperStartPct?, taperPowerRatio?, labelSource?}.
    ``labelSource="taper_full"`` = the server saw the full-battery power tail,
    so a 100 % end is exact rather than censored.
    """
    now = now or datetime.now(timezone.utc)
    value = wh_per_pct_sample(float(sample.get("energyWh") or 0),
                              float(sample.get("startPct") or 0),
                              float(sample.get("actualEndPct") or 0))
    if value is None:
        return profile, "soc_gain_too_small"
    if base_wh_per_pct:
        low, high = WH_PER_PCT_BAND
        if not base_wh_per_pct * low <= value <= base_wh_per_pct * high:
            return profile, "outlier"
    label = str(sample.get("labelSource") or "user")
    censored = float(sample.get("actualEndPct") or 0) >= 99 and label != "taper_full"
    entry = {
        "sessionId": str(sample.get("sessionId") or ""),
        "whPerPct": round(value, 3),
        "energyWh": round(float(sample.get("energyWh") or 0), 2),
        "startPct": float(sample.get("startPct") or 0),
        "actualEndPct": float(sample.get("actualEndPct") or 0),
        "estimatedEndPct": _positive(sample.get("estimatedEndPct"), allow_zero=True),
        "avgPowerW": _positive(sample.get("avgPowerW")),
        "taperStartPct": _positive(sample.get("taperStartPct")),
        "taperPowerRatio": _positive(sample.get("taperPowerRatio")),
        "censored": censored,
        "labelSource": label,
        "at": str(sample.get("at") or now.isoformat()),
    }
    if sample.get("trust") in TRUST_WEIGHT:
        entry["trust"] = sample["trust"]
    if sample.get("shadowOffsetPct") is not None and sample.get("shadowWhPerPct"):
        entry["shadowOffsetPct"] = round(float(sample["shadowOffsetPct"]), 2)
        entry["shadowWhPerPct"] = round(float(sample["shadowWhPerPct"]), 3)
    temperature = _positive(sample.get("batteryTempC"))
    # QA 157: a one-digit reading is a lost digit ("6" of 26 or 36 was
    # stored on 08/11/2026), not a battery that just charged at 6 °C.
    if temperature is not None and temperature < 10:
        temperature = None
    if temperature is not None:
        entry["batteryTempC"] = temperature
    # QA 166: what battery health weighs a charge by, measured (where the
    # start % came from and how old it was, when the end % was typed, energy
    # counted with the charger idle, the charger's steady power).
    if sample.get("startSource"):
        entry["startSource"] = str(sample["startSource"])[:40]
    for key in ("startAgeMin", "endAfterMin", "tailWh", "plateauW"):
        number = _positive(sample.get(key), allow_zero=True)
        if number is not None:
            entry[key] = round(float(number), 2)
    sid = entry["sessionId"]
    # A user reading replaces an automatic one for the same charge.
    pending = [item for item in profile.pending if item.get("sessionId") != sid]
    samples = [item for item in profile.samples if item.get("sessionId") != sid]
    ledger = [item for item in profile.ledger if item.get("sessionId") != sid]
    queued = LearnedProfile(**{**profile.__dict__, "samples": samples,
                               "pending": [*pending, entry][-MAX_PENDING_SAMPLES:],
                               "ledger": [*ledger, entry][-MAX_LEDGER_CHARGES:]})
    # QA 164: the battery's health by month outlives the 200-charge ledger.
    try:
        queued.health_log = update_health_log(
            profile.health_log, unique_charges(queued),
            complete=len(queued.ledger) < MAX_LEDGER_CHARGES, now=now,
            full_drift=full_drift_points(profile.drift_log))
    except (TypeError, ValueError, ZeroDivisionError):
        pass  # never lose a charge over the log
    return queued, "queued"


HEALTH_TEST_MAX_START_PCT = 30.0
HEALTH_RECENT_SAMPLES = 10
# QA 152: how the estimate moved over the months, from the long ledger.
HEALTH_TREND_POINTS = 40
HEALTH_BASELINE_CHARGES = 6
HEALTH_BASELINE_MIN_CHARGES = 12
HEALTH_BASELINE_MIN_DAYS = 60
# QA 162: which charges the capacity left is computed from.
HEALTH_MIN_GAIN_PCT = 20.0
HEALTH_WINDOW_DAYS = 120
HEALTH_WINDOW_CHARGES = 20
# A charge this far (in % of the result) from the others' gain-weighted median,
# and beyond 3 of their robust deviations, is left out: the gauge falls behind
# and catches up (85 % then 121 % on the owner's ledger, QA 162). A charge
# whose own error is under a third of this is judged by its error instead.
HEALTH_OUTLIER_FLOOR_PCT = 6.0
# QA 162: outliers are a minority; past this share the spread is the data.
HEALTH_MAX_DROPPED_SHARE = 0.25
# Months kept in the health log (ten years of the battery's life, QA 164).
HEALTH_LOG_MONTHS = 120
HEALTH_LOG_VERSION = 2
# Charges on each side a charge is compared with.
HEALTH_NEIGHBOURS = 10
# With no counted charge in the window, the latest months still say something.
HEALTH_STALE_CHARGES = 6
# QA 166 (owner's choice, 18/11/2026): measured instead of assumed.
# Every charge counts by 1/σ², σ = how far its gauge reading may be off, in %
# points, by how long since the gauge was last right (the QA 158 trust).
# Starting values from the owner's ledger (12 charges, 6/9-9/11/2026): the
# charge right after a full one 0.2 (QA 157 measured 0.5; the larger is kept),
# the 2nd-3rd 3.8, later ones 6.8. Every vehicle moves them to its own as its
# charges come, the starting value counting as HEALTH_PRIOR_CHARGES charges.
HEALTH_DRIFT_POINTS = {"high": 0.5, "medium": 3.8, "low": 6.8}
HEALTH_PRIOR_CHARGES = 4.0
# One whole-% reading: uniform within ±0.5, so 0.29 points.
HEALTH_READ_POINTS = 0.29
# The least error of one charge however long and well read: the owner's two
# charges right after a full one agreed within 0.3 %.
HEALTH_CHARGE_FLOOR = 0.005
HEALTH_OUTLIER_SIGMAS = 3.0
# Not reduced by more charges. Wall Wh to rated Wh = charger efficiency
# (0.85-0.93) x rated over charging cell voltage (LFP 3.2 / about 3.32 V, 0.96)
# x Coulomb efficiency (about 0.995) = 0.81-0.89. The owner kept 0.90 until a
# measurement: the absolute figure's range reaches down to 0.81.
HEALTH_FACTOR_LOW = 0.81
HEALTH_FACTOR_HIGH = 0.90
# VinFast publishes "2,4 kWh" (rounded) until the battery label gives it.
HEALTH_NOMINAL_PCT = 2.0
# The Shelly meter: a reseller's figure, Shelly publishes none for this plug.
HEALTH_METER_PCT = 1.0
# The reference is fixed once its own error is this small over this long, or
# after HEALTH_REFERENCE_FALLBACK_DAYS with enough charges, whatever its error
# (it then stays in the relative figure's error).
HEALTH_REFERENCE_MAX_ERROR_PCT = 1.5
HEALTH_REFERENCE_MIN_CHARGES = 3
HEALTH_REFERENCE_DAYS = 28
HEALTH_REFERENCE_FALLBACK_DAYS = 90
HEALTH_REFERENCE_FALLBACK_CHARGES = 8
# A new charger, outlet or a second battery: the charging power moved this
# much on this many charges in a row, or Wh per 1 % this many times on two.
HEALTH_EPOCH_POWER_CHANGE = 0.08
HEALTH_EPOCH_RUN = 3
HEALTH_EPOCH_WH_FACTOR = 1.6
HEALTH_EPOCH_WH_RUN = 2
# A start % read this soon before plugging in was read after the ride.
HEALTH_FRESH_START_MIN = 15.0
# A start saved as "the scooter just shut off" at or under this %.
HEALTH_CUTOFF_MAX_PCT = 5.0
# QA 166 (2), from the owner's charges of 18/11/2026: the gauge drifts low
# between full charges (14.19 points after 2.77 full charges' worth, measured
# by QA 158 at the charger's full signal of 17/11). A charge stopped midway
# reads both ends with the same drift, which cancels; a charge to the
# charger's full signal ends at the true 100 % and keeps its start's drift
# (13.6 and 14.0 points on 1/11 and 17/11). It counts only right after a full
# charge, with this many points of drift per full discharge since then until
# the vehicle's own drift log says otherwise (14.19 / 2.77 = 5.1). The scooter
# shutting off at the gauge's 0 % follows the same gauge: not a true empty.
HEALTH_FULL_DRIFT_PRIOR = 5.0
HEALTH_DRIFT_MIN_FULLS = 0.3
# QA 166 (2), owner's choice: the charger's rated output over the wall power
# the Shelly measures caps its efficiency; times the most an LFP cell gives
# back at its rated voltage (3.2 V over at least 3.30 V while charging, 0.97)
# and the best Coulomb efficiency (0.999) it caps the wall-to-battery factor.
# VinFast rates the Feliz 2025 / Evo Grand charger 400 W (TSKT 07/2025); the
# owner's Shelly reads 444 W: at most 0.873. The figure is then the middle of
# HEALTH_FACTOR_LOW and that cap. Only when the two plausibly belong together
# (a faster charger than the rated one is another charger).
HEALTH_RATED_VOLTAGE_RATIO = 0.97
HEALTH_RATED_COULOMB = 0.999
HEALTH_RATED_RATIO_MIN = 0.75
HEALTH_RATED_RATIO_MAX = 1.0
# QA 164 log, version 1 (pooled by % gained x trust): its error formula.
_LEGACY_SCATTER_PCT = 3.0
_LEGACY_READING_PCT = 1.5


def _implied_capacity(wh_per_pct: float, efficiency: float) -> float:
    """Usable capacity the battery stored: wall Wh per % x 100 x efficiency."""
    return wh_per_pct * 100 * efficiency


def idle_energy_wh(curve: list[dict] | None, total_wh: float | None) -> float | None:
    """QA 166: energy the meter counted while the scooter charger drew under
    IDLE_POWER_W (before the scooter was plugged in, or after it stopped): it
    did not go into the battery. From the server's 1-minute curve; ``None``
    without one."""
    points = [(_positive(item.get("wh"), allow_zero=True), _positive(item.get("p"), allow_zero=True))
              for item in (curve or []) if isinstance(item, dict)]
    points = [(wh, p) for wh, p in points if wh is not None and p is not None]
    if len(points) < 2:
        return None
    idle = points[0][0] if points[0][1] < IDLE_POWER_W else 0.0
    for (wh0, p0), (wh1, p1) in zip(points, points[1:]):
        if p0 < IDLE_POWER_W and p1 < IDLE_POWER_W:
            idle += max(0.0, wh1 - wh0)
    total = _positive(total_wh, allow_zero=True)
    if total is not None and points[-1][1] < IDLE_POWER_W:
        idle += max(0.0, total - points[-1][0])
    return round(idle, 2)


def plateau_power_w(curve: list[dict] | None) -> float | None:
    """QA 166: the charger's steady wall power (median of the first half of
    the charging samples, as ``learn_taper``); a new charger shows here."""
    powers = [float(item["p"]) for item in (curve or [])
              if isinstance(item, dict) and _positive(item.get("p")) and float(item["p"]) > IDLE_POWER_W]
    if len(powers) < 8:
        return None
    middle = _median(powers[: max(3, len(powers) // 2)])
    return round(middle, 1) if middle else None


def battery_health(samples: list[dict], nominal_capacity_wh: float | None,
                   efficiency: float = DEFAULT_EFFICIENCY, *,
                   history: list[dict] | None = None,
                   now: datetime | None = None,
                   log: dict | None = None,
                   cutoff_pct: float | None = None,
                   factor: dict | None = None,
                   nominal_source: str | None = None,
                   charger_rated_w: float | None = None,
                   wall_power_w: float | None = None,
                   drift_log: list[dict] | None = None) -> dict:
    """% of the nominal capacity the battery still holds (QA 135).

    The scooter reports no cell data: each charge gives wall Wh per 1 % of
    the gauge (the Shelly meter over the % the owner read), and the capacity
    is that x 100 x ``efficiency``.

    QA 162/164: ``tracking`` is the main figure, the capacity against the
    first months the app followed this battery (``log``, the stored monthly
    log, merged with these charges), so the efficiency cancels out. With no
    counted charge in the window the latest months give a ``stale`` estimate.

    QA 166 (owner's choice): measured instead of assumed.
    * Every charge counts by 1/σ²: σ is how far its gauge reading may be off
      for how long since the gauge was last right, learned from this
      vehicle's own charges (``health_sigmas``), plus a whole-% reading.
    * QA 166 (2): the gauge drifts low between full charges. A charge to the
      charger's full signal keeps its start's drift, so it counts only right
      after a full charge (else ``reason="drift"``), with the drift this
      vehicle measured per full discharge (``drift_log``). The scooter
      shutting off at the gauge's 0 % is a gauge reading like any other.
    * Energy the meter counted with the charger idle (``tailWh``) is left out.
    * ``spread.uncertaintyPct`` is the measured error only; what more charges
      cannot reduce is apart in ``systematic`` and in ``totalLowPct`` /
      ``totalHighPct``: the wall-to-battery factor (a measured ``factor``; else
      capped by the charger's rated output over the measured wall power,
      ``charger_rated_w`` / ``wall_power_w``; else 0.90 within 0.81-0.90), the
      rating (``nominal_source`` "label" when read off the battery) and the
      meter.
    * ``cutoff_pct``: the gauge % at which the scooter shuts off (0 on the
      owner's); above 0 the gauge's range is that much short of the battery.
    * A new charger, outlet or second battery starts an epoch with its own
      reference (``_health_epochs``).
    """
    nominal = _positive(nominal_capacity_wh)
    result: dict = {"nominalCapacityWh": nominal, "efficiency": efficiency,
                    "estimate": None, "test": None, "trend": [],
                    "spread": None, "baseline": None, "charges": [], "tracking": None,
                    "systematic": None, "sigmas": None, "gaugeDrift": None}
    if nominal is None:
        return result
    measured = _measured_factor(factor)
    rated = None if measured is not None else _rated_factor(charger_rated_w, wall_power_w)
    if measured is not None:
        efficiency = measured["factor"]
        result["efficiency"] = efficiency
    elif rated is not None:
        efficiency = rated["factor"]
        result["efficiency"] = efficiency
    drift = gauge_drift(drift_log)
    full_drift = drift["perFullPct"] if drift else HEALTH_FULL_DRIFT_PRIOR
    result["gaugeDrift"] = drift
    cutoff = _cutoff_pct(cutoff_pct)
    usable = (100.0 - cutoff) / 100.0

    def soh(capacity: float) -> float:
        return round(min(120.0, max(0.0, capacity * usable / nominal * 100)), 1)

    exact = sorted(
        [item for item in samples
         if not item.get("censored") and _positive(item.get("whPerPct"))],
        key=lambda item: str(item.get("at") or ""))
    # Every distinct charge (the long ledger too).
    merged: dict[str, dict] = {}
    for index, item in enumerate([*(history or []), *samples]):
        merged[str(item.get("sessionId") or f"_{index}")] = item
    charges = sorted(merged.values(), key=lambda item: str(item.get("at") or ""))
    trusts = _health_trusts(charges)
    stored_epochs = log.get("epochs") if isinstance(log, dict) else None
    epoch_ids, _ = _health_epochs(charges, stored_epochs)
    rows = _charge_rows(charges, trusts, efficiency, soh, epoch_ids)
    learned = health_sigmas(rows, full_drift=full_drift)
    _apply_weights(rows, learned["points"], full_drift=full_drift)
    epoch = rows[-1]["epoch"] if rows else "e0"
    _window(rows, now=now, epoch=epoch)
    _drop_far(rows)
    result["charges"] = [row["public"] for row in rows[-HEALTH_WINDOW_CHARGES:]]
    result["sigmas"] = {"points": {key: round(value, 2) for key, value in learned["points"].items()},
                        "charges": learned["counts"], "fullDriftPerFull": round(full_drift, 2)}
    health_log = update_health_log(log, charges, complete=len(history or []) < MAX_LEDGER_CHARGES,
                                   now=now, full_drift=full_drift)
    used = [row for row in rows if row["weight"] > 0]
    pooled_wh = None
    current_error = None
    nominal_pct = 0.0 if nominal_source == "label" else HEALTH_NOMINAL_PCT
    if used:
        pool = _pool(used)
        pooled_wh = pool["whPerPct"]
        capacity = _implied_capacity(pooled_wh, efficiency)
        middle = soh(capacity)
        random = middle * pool["relError"]
        weight = sum(row["weight"] for row in used)
        scatter = math.sqrt(sum(row["weight"] * (row["soh"] - middle) ** 2 for row in used) / weight)
        current_error = pool["relError"] * 100
        result["estimate"] = {
            "sohPct": middle, "capacityWh": round(capacity * usable),
            "samples": len(used), "effectiveCharges": round(pool["effective"], 1),
            "confidence": _confidence(random, pool["effective"]),
            "method": "pooled-iv",
        }
        result["spread"] = _spread(middle, random, scatter, efficiency, measured, nominal_pct, rated)
    else:
        months = [bucket for bucket in health_log["months"] if (bucket.get("epoch") or "e0") == epoch]
        recent: list[dict] = []
        for bucket in reversed(months):
            recent.insert(0, bucket)
            if sum(int(b.get("charges") or 0) for b in recent) >= HEALTH_STALE_CHARGES:
                break
        stale = _pooled(recent) if recent else None
        if stale:
            # QA 164: nothing counted lately (no Shelly charge for months): the
            # latest months still say where the battery stood, marked stale.
            pooled_wh = stale["whPerPct"]
            capacity = _implied_capacity(pooled_wh, efficiency)
            middle = soh(capacity)
            random = middle * stale["errorPct"] / 100
            current_error = stale["errorPct"]
            result["estimate"] = {
                "sohPct": middle, "capacityWh": round(capacity * usable),
                "samples": stale["charges"], "effectiveCharges": round(stale["effective"], 1),
                "confidence": "low", "method": "monthly-log", "stale": True, "asOf": stale["to"],
            }
            result["spread"] = _spread(middle, random, (stale.get("scatterPct") or 0.0) * middle / 100,
                                       efficiency, measured, nominal_pct, rated)
    result["systematic"] = {
        "factor": round(efficiency, 3),
        "factorLow": measured["factor"] if measured else HEALTH_FACTOR_LOW,
        "factorHigh": (measured["factor"] if measured
                       else rated["high"] if rated else HEALTH_FACTOR_HIGH),
        "factorMeasured": measured is not None,
        "factorErrorPct": measured["errorPct"] if measured else None,
        "factorSource": (measured["source"] if measured
                         else "rated" if rated else None),
        "chargerRatedW": rated["ratedW"] if rated else None,
        "wallPowerW": rated["wallW"] if rated else None,
        "nominalPct": nominal_pct,
        "nominalSource": "label" if nominal_source == "label" else "catalog",
        "meterPct": HEALTH_METER_PCT,
        "cutoffPct": cutoff,
    }
    result["tracking"] = health_tracking(health_log, pooled_wh, current_error, nominal, efficiency,
                                         epoch=epoch, usable=usable)
    if exact:
        seen = {str(item.get("sessionId") or "") for item in exact}
        long = sorted(
            [*exact, *[item for item in (history or [])
                       if not item.get("censored") and _positive(item.get("whPerPct"))
                       and str(item.get("sessionId") or "") not in seen]],
            key=lambda item: str(item.get("at") or ""))
        result["trend"] = [
            {"at": item.get("at"),
             "sohPct": soh(_implied_capacity(float(item["whPerPct"]), efficiency)),
             "trust": trusts.get(str(item.get("sessionId") or ""), "low")}
            for item in long[-(HEALTH_TREND_POINTS if history else 12):]
        ]
        result["baseline"] = _health_baseline(long, soh, efficiency)
    # QA 166: a test from 0 % counts (``startPct or 100`` read 0 as 100).
    # QA 166 (2): only right after a full charge; later the gauge has drifted
    # and the test reads low (80 % on 17/11/2026 with 14 points of drift).
    tests = [item for item in exact
             if item.get("labelSource") == "taper_full"
             and item.get("startPct") is not None
             and float(item["startPct"]) <= HEALTH_TEST_MAX_START_PCT
             and trusts.get(str(item.get("sessionId") or "")) == "high"
             and _positive(item.get("energyWh"))]
    if tests:
        last = tests[-1]
        start = float(last["startPct"])
        energy = _net_energy(last)
        capacity = energy * efficiency / (100 - start) * 100
        result["test"] = {"sohPct": soh(capacity), "capacityWh": round(capacity * usable),
                          "startPct": start, "energyWh": round(energy),
                          "at": last.get("at"), "sessionId": last.get("sessionId"),
                          "kind": ("full_range" if _cutoff_start(last) else "test")}
    return result


def _net_energy(item: dict) -> float:
    """Wall energy of a charge without what the meter counted while idle."""
    energy = _positive(item.get("energyWh")) or 0.0
    tail = _positive(item.get("tailWh"), allow_zero=True) or 0.0
    return energy - tail if tail < energy else energy


def _cutoff_start(item: dict) -> bool:
    return (item.get("startSource") == "cutoff"
            and float(item.get("startPct") or 0) <= HEALTH_CUTOFF_MAX_PCT)


def _cutoff_pct(value) -> float:
    number = _positive(value, allow_zero=True)
    return float(number) if number is not None and number <= 20 else 0.0


def _measured_factor(factor) -> dict | None:
    """A measured wall-to-battery factor (DC readings at the charger output
    against the Shelly power, QA 166). Out of range is not a measurement."""
    if not isinstance(factor, dict):
        return None
    value = _positive(factor.get("factor"))
    if value is None or not 0.7 <= value <= 0.98:
        return None
    error = _positive(factor.get("errorPct"))
    return {"factor": value, "errorPct": min(10.0, max(0.5, error or 2.0)),
            "source": str(factor.get("source") or "measured")[:40]}


def _rated_factor(rated_w, wall_w) -> dict | None:
    """QA 166 (2): the cap on the wall-to-battery factor from the charger's
    rated output and the wall power the Shelly measured, and the figure used
    (the middle of HEALTH_FACTOR_LOW and the cap). ``None`` when either is
    missing or the two do not belong together."""
    rated, wall = _positive(rated_w), _positive(wall_w)
    if rated is None or wall is None:
        return None
    ratio = rated / wall
    if not HEALTH_RATED_RATIO_MIN <= ratio <= HEALTH_RATED_RATIO_MAX:
        return None
    high = round(min(HEALTH_FACTOR_HIGH, ratio * HEALTH_RATED_VOLTAGE_RATIO * HEALTH_RATED_COULOMB), 3)
    if high <= HEALTH_FACTOR_LOW:
        return None
    return {"factor": (HEALTH_FACTOR_LOW + high) / 2, "high": high,
            "ratedW": round(rated, 1), "wallW": round(wall, 1)}


def _drift_rates(drift_log: list[dict] | None) -> list[float]:
    """Points of gauge drift per full charge's worth since the last full one,
    from each drift measured at the charger's full signal (QA 158)."""
    rates = []
    for item in drift_log or []:
        if not isinstance(item, dict) or item.get("driftPct") is None:
            continue
        try:
            drift, fulls = abs(float(item["driftPct"])), float(item.get("fulls") or 0)
        except (TypeError, ValueError):
            continue
        if fulls >= HEALTH_DRIFT_MIN_FULLS:
            rates.append(drift / fulls)
    return rates


def full_drift_points(drift_log: list[dict] | None) -> float:
    """Points of drift per full discharge a charge to full carries (QA 166 (2))."""
    drift = gauge_drift(drift_log)
    return drift["perFullPct"] if drift else HEALTH_FULL_DRIFT_PRIOR


def gauge_drift(drift_log: list[dict] | None) -> dict | None:
    """QA 166 (2): how far this vehicle's gauge drifts between full charges,
    as measured, for battery health and for develop mode."""
    rates = _drift_rates(drift_log)
    if not rates:
        return None
    last = next(item for item in reversed(drift_log or [])
                if isinstance(item, dict) and item.get("driftPct") is not None)
    return {"lastPct": round(abs(float(last["driftPct"])), 1),
            "sessions": last.get("sessions"), "fulls": last.get("fulls"),
            "at": last.get("at"), "perFullPct": round(_median(rates), 2),
            "measurements": len(rates)}


def _confidence(random_pct: float, effective: float) -> str:
    if random_pct <= 2.5 and effective >= 3:
        return "high"
    if random_pct <= 4 and effective >= 1.5:
        return "medium"
    return "low"


def _spread(middle: float, random: float, scatter: float, efficiency: float,
            measured: dict | None, nominal_pct: float, rated: dict | None = None) -> dict:
    """The measured error, and the range with what more charges cannot
    reduce: the wall-to-battery factor (down to HEALTH_FACTOR_LOW until it is
    measured, up to the charger's rated cap when there is one), the rating
    and the meter."""
    other = math.sqrt(random ** 2 + (middle * nominal_pct / 100) ** 2
                      + (middle * HEALTH_METER_PCT / 100) ** 2)
    if measured is not None:
        other = math.hypot(other, middle * measured["errorPct"] / 100)
        low_ratio = high_ratio = 1.0
    else:
        high = rated["high"] if rated else HEALTH_FACTOR_HIGH
        low_ratio = HEALTH_FACTOR_LOW / efficiency
        high_ratio = max(1.0, high / efficiency)
    total_low = middle * low_ratio - other
    total_high = middle * high_ratio + other
    return {
        # Typical distance of one charge from the result, in SoH points.
        "perChargePct": round(scatter, 1),
        # How far the result itself may be off, from the charges alone.
        "uncertaintyPct": round(random, 1),
        "lowPct": round(middle - random, 1),
        "highPct": round(middle + random, 1),
        "totalLowPct": round(total_low, 1),
        "totalHighPct": round(total_high, 1),
        # One figure for older apps: half the whole range.
        "totalPct": round((total_high - total_low) / 2, 1),
    }


def _health_anchor(item: dict) -> bool:
    """A charge that ended full: the gauge is right again after it."""
    return (item.get("labelSource") == "taper_full"
            or float(item.get("actualEndPct") or 0) >= GAUGE_RESET_END_PCT)


def _health_trusts(charges: list[dict]) -> dict[str, str]:
    """How far the gauge could be trusted at each charge (QA 158 levels): the
    stored level when there is one, else from its place after the last full
    charge (the first one after it high, the next two medium, then low; low
    before any full charge)."""
    trusts: dict[str, str] = {}
    since_full: int | None = None
    for item in charges:
        stored = item.get("trust")
        if stored in TRUST_WEIGHT:
            level = stored
        elif since_full is None:
            level = "low"
        elif since_full < TRUST_LIMITS["highSessions"]:
            level = "high"
        elif since_full < TRUST_LIMITS["mediumSessions"]:
            level = "medium"
        else:
            level = "low"
        trusts[str(item.get("sessionId") or "")] = level
        if _health_anchor(item):
            since_full = 0
        elif since_full is not None:
            since_full += 1
    return trusts


def _charge_rows(charges: list[dict], trusts: dict[str, str], efficiency: float,
                 soh, epoch_ids: list[str]) -> list[dict]:
    """Each charge with its Wh per 1 %, kind and why it is (not) counted."""
    rows: list[dict] = []
    for item, epoch in zip(charges, epoch_ids):
        start = float(item.get("startPct") or 0)
        energy = _positive(item.get("energyWh"))
        stored = _positive(item.get("whPerPct"))
        if item.get("actualEndPct") is None and stored and energy:
            end = start + energy / stored  # an older record without its end %
        else:
            end = float(item.get("actualEndPct") or 0)
        gain = end - start
        net = _net_energy(item) if energy else 0.0
        trust = trusts.get(str(item.get("sessionId") or ""), "low")
        full_end = item.get("labelSource") == "taper_full"
        cutoff_start = _cutoff_start(item)
        # QA 166 (2): a charge to the charger's full signal keeps the drift
        # its start % had; only right after a full charge is that small.
        synced = trust == "high"
        test = full_end and synced and start <= HEALTH_TEST_MAX_START_PCT
        age = _positive(item.get("startAgeMin"), allow_zero=True)
        kind = (None if not (full_end and synced)
                else "full_range" if cutoff_start
                else "standard" if age is not None and age <= HEALTH_FRESH_START_MIN
                else "test" if test else None)
        per_pct = net / gain if net > 0 and gain > 0 else None
        value = soh(_implied_capacity(per_pct, efficiency)) if per_pct else None
        if item.get("censored") and not full_end:
            reason = "censored"
        elif value is None or gain < HEALTH_MIN_GAIN_PCT:
            reason = "short"
        elif full_end and not synced:
            reason = "drift"
        else:
            reason = None
        rows.append({
            "weight": 0.0, "sigma": None, "gain": gain, "energyWh": net, "r": per_pct,
            "soh": value, "at": _parse_at(item.get("at")), "trust": trust, "epoch": epoch,
            "start": start, "cutoffStart": cutoff_start, "fullEnd": full_end, "kind": kind,
            "public": {"at": item.get("at"), "startPct": start, "endPct": end,
                       "sohPct": value, "trust": trust, "test": test, "kind": kind,
                       "epoch": epoch, "used": reason is None, "reason": reason},
        })
    return rows


def _charge_points(row: dict, sigmas: dict, full_drift: float = HEALTH_FULL_DRIFT_PRIOR) -> float:
    """How far this charge's gauge readings may be off, in % points. QA 166
    (2): a charge to the charger's full signal (counted only right after a
    full charge) carries the drift of its start, which grows with the
    discharge since the gauge was right; a start at the scooter's shut-off is
    a gauge reading like any other."""
    if row["fullEnd"]:
        drop = max(0.0, 100.0 - float(row.get("start") or 0.0))
        return max(HEALTH_READ_POINTS, full_drift * drop / 100)
    return sigmas.get(row["trust"], sigmas["low"])


def _apply_weights(rows: list[dict], sigmas: dict, *,
                   full_drift: float = HEALTH_FULL_DRIFT_PRIOR) -> None:
    for row in rows:
        if not row["public"]["used"] or not row["r"] or row["gain"] <= 0:
            row["weight"], row["sigma"] = 0.0, None
            continue
        points = _charge_points(row, sigmas, full_drift)
        sigma = math.sqrt((points / row["gain"]) ** 2 + HEALTH_CHARGE_FLOOR ** 2)
        row["sigma"], row["weight"] = sigma, 1.0 / sigma ** 2
        row["public"]["sigmaPct"] = round(sigma * (row["soh"] or 0), 1)


def health_sigmas(rows: list[dict], *, full_drift: float = HEALTH_FULL_DRIFT_PRIOR) -> dict:
    """QA 166: this vehicle's gauge error by trust level, in % points. Each
    charge is compared with the charges around it (so a battery that wears is
    not taken for noise); the starting values count as HEALTH_PRIOR_CHARGES
    charges and a charge far off counts at most 3 σ. Charges to the charger's
    full signal have their own error (their start's drift) and teach nothing
    here."""
    sigmas = dict(HEALTH_DRIFT_POINTS)
    counts = {key: 0 for key in sigmas}
    eligible = [row for row in rows if row["public"]["used"] and row["r"]]
    floor = HEALTH_READ_POINTS * math.sqrt(2)
    for _ in range(2):
        _apply_weights(eligible, sigmas, full_drift=full_drift)
        sums = {key: 0.0 for key in sigmas}
        counts = {key: 0 for key in sigmas}
        for index, row in enumerate(eligible):
            if row["fullEnd"]:
                continue
            near = [other for other in eligible[max(0, index - HEALTH_NEIGHBOURS): index + HEALTH_NEIGHBOURS + 1]
                    if other is not row and other["epoch"] == row["epoch"]]
            weight = sum(other["weight"] for other in near)
            if len(near) < 2 or weight <= 0:
                continue
            centre = sum(other["weight"] * other["r"] for other in near) / weight
            level = row["trust"] if row["trust"] in sigmas else "low"
            cap = 3 * sigmas[level]
            points = max(-cap, min(cap, (row["r"] / centre - 1) * row["gain"]))
            sums[level] += points * points
            counts[level] += 1
        sigmas = {key: max(floor, math.sqrt(
            (HEALTH_PRIOR_CHARGES * HEALTH_DRIFT_POINTS[key] ** 2 + sums[key])
            / (HEALTH_PRIOR_CHARGES + counts[key]))) for key in sigmas}
    return {"points": sigmas, "counts": counts}


def _leave(row: dict, reason: str, *, dropped: bool = False) -> None:
    if dropped:
        row["dropped"] = row["weight"]
    row["public"].update(used=False, reason=reason)
    row["weight"] = 0.0


def _window(rows: list[dict], *, now: datetime | None, epoch: str) -> None:
    """Only the latest charges of the current epoch count (QA 162)."""
    dated = [row["at"] for row in rows if row["at"] is not None]
    latest = now or max(dated, default=None)
    eligible = []
    for row in rows:
        if row["weight"] <= 0:
            continue
        if row["epoch"] != epoch:
            _leave(row, "epoch")
            continue
        age = (latest - row["at"]).total_seconds() / 86400 if latest and row["at"] else 0.0
        if age > HEALTH_WINDOW_DAYS:
            _leave(row, "old")
            continue
        eligible.append(row)
    for row in eligible[:-HEALTH_WINDOW_CHARGES]:
        _leave(row, "old")


def _robust_far(group: list[dict]) -> set[int]:
    """The charges of ``group`` far from its gain-weighted median by more than
    3 robust deviations (and HEALTH_OUTLIER_FLOOR_PCT), the QA 162 rule, for
    charges that are not precise themselves. Outliers are a minority: when
    more than HEALTH_MAX_DROPPED_SHARE of the group would leave (a gauge that
    falls behind and catches up in turns), the spread is the data and none
    leaves by this rule."""
    members = [row for row in group if row["weight"] > 0]
    if len(members) < 3:
        return set()
    middle = _weighted_median([(row["r"], row["gain"]) for row in members])
    deviation = _weighted_median([(abs(row["r"] / middle - 1), row["gain"]) for row in members])
    limit = max(3 * 1.4826 * deviation, HEALTH_OUTLIER_FLOOR_PCT / 100)
    far = {id(row) for row in members
           if row["sigma"] * 100 * 3 >= HEALTH_OUTLIER_FLOOR_PCT and abs(row["r"] / middle - 1) > limit}
    share = sum(row["gain"] for row in members if id(row) in far) / sum(row["gain"] for row in members)
    return far if share <= HEALTH_MAX_DROPPED_SHARE else set()


def _sigma_far(row: dict, group: list[dict]) -> bool:
    """More than HEALTH_OUTLIER_SIGMAS of its own and the others' error away
    from the others."""
    others = [other for other in group if other is not row and other["weight"] > 0]
    if len(others) < 2:
        return False
    weight = sum(other["weight"] for other in others)
    centre = sum(other["weight"] * other["r"] for other in others) / weight
    distance = abs(row["r"] / centre - 1) / math.sqrt(row["sigma"] ** 2 + 1 / weight)
    return distance > HEALTH_OUTLIER_SIGMAS


def _drop_far(rows: list[dict]) -> None:
    eligible = [row for row in rows if row["weight"] > 0]
    if len(eligible) < 3:
        return
    robust = _robust_far(eligible)
    flags = [id(row) in robust or _sigma_far(row, eligible) for row in eligible]
    for row, far in zip(eligible, flags):
        if far:
            _leave(row, "outlier", dropped=True)


def _drop_outliers_nearby(rows: list[dict]) -> None:
    """QA 164: over a battery's life the capacity moves, so a charge is
    compared with the charges around it (not with every charge ever)."""
    eligible = [row for row in rows if row["weight"] > 0]
    flags = []
    for index, row in enumerate(eligible):
        near = [other for other in eligible[max(0, index - HEALTH_NEIGHBOURS): index + HEALTH_NEIGHBOURS + 1]
                if other["epoch"] == row["epoch"]]
        flags.append(len(near) >= 3 and (id(row) in _robust_far(near) or _sigma_far(row, near)))
    for row, far in zip(eligible, flags):
        if far:
            _leave(row, "outlier", dropped=True)


def _pool(rows: list[dict]) -> dict:
    """Wh per 1 % of the charges by 1/σ², its relative error (widened when
    the charges disagree more than their σ say, Birge ratio)."""
    weight = sum(row["weight"] for row in rows)
    centre = sum(row["weight"] * row["r"] for row in rows) / weight
    chi2 = sum(row["weight"] * (row["r"] / centre - 1) ** 2 for row in rows)
    n = len(rows)
    birge = math.sqrt(chi2 / (n - 1)) if n >= 2 else 1.0
    return {"whPerPct": centre, "relError": max(1.0, birge) / math.sqrt(weight),
            "effective": weight ** 2 / sum(row["weight"] ** 2 for row in rows),
            "charges": n, "birge": birge}


def _health_epochs(charges: list[dict], stored: list | None = None) -> tuple[list[str], list[dict]]:
    """QA 166: a new charger, outlet or a second battery changes Wh per 1 %
    at the wall for reasons that are not the battery wearing. The charging
    power moving more than HEALTH_EPOCH_POWER_CHANGE on HEALTH_EPOCH_RUN
    charges in a row, or Wh per 1 % HEALTH_EPOCH_WH_FACTOR times on
    HEALTH_EPOCH_WH_RUN, starts an epoch at the first of them. ``stored``
    epochs (the log's) keep their place. Returns the epoch of each charge and
    the epochs."""
    known = sorted([dict(item) for item in (stored or [])
                    if isinstance(item, dict) and item.get("id") and item.get("from")],
                   key=lambda item: str(item["from"]))
    epochs = list(known)
    scratch: dict[str, dict] = {}
    ids: list[str] = []
    current: dict | None = None
    power_run: list[tuple[int, int, float]] = []
    wh_run: list[tuple[int, int, float]] = []
    for index, item in enumerate(charges):
        at = str(item.get("at") or "")
        fixed = [epoch for epoch in known if str(epoch["from"]) <= at]
        if fixed and (current is None or str(fixed[-1]["from"]) > str(current["from"])):
            current, power_run, wh_run = fixed[-1], [], []
        if current is None:
            current = next((epoch for epoch in epochs if epoch["id"] == "e0"), None)
            if current is None:
                current = {"id": "e0", "from": at, "reason": "start", "plateauW": None, "whPerPct": None}
                epochs.insert(0, current)
        ids.append(current["id"])
        power = _positive(item.get("plateauW")) or _positive(item.get("avgPowerW"))
        gain = _gain(item)
        energy = _positive(item.get("energyWh"))
        per_pct = (energy / gain if energy and gain >= HEALTH_MIN_GAIN_PCT
                   and not (item.get("censored") and item.get("labelSource") != "taper_full") else None)
        state = scratch.setdefault(current["id"], {"powers": [], "whs": []})
        if current.get("plateauW") is None and power:
            state["powers"].append(power)
            if len(state["powers"]) >= 3:
                current["plateauW"] = round(_median(state["powers"]), 1)
        if current.get("whPerPct") is None and per_pct:
            state["whs"].append(per_pct)
            if len(state["whs"]) >= 3:
                current["whPerPct"] = round(_median(state["whs"]), 3)
        reference_power, reference_wh = current.get("plateauW"), current.get("whPerPct")
        if power and reference_power:
            moved = (0 if abs(power / reference_power - 1) <= HEALTH_EPOCH_POWER_CHANGE
                     else 1 if power > reference_power else -1)
            power_run = ([*power_run, (index, moved, power)]
                         if moved and (not power_run or power_run[-1][1] == moved)
                         else [(index, moved, power)] if moved else [])
        if per_pct and reference_wh:
            ratio = per_pct / reference_wh
            jumped = (1 if ratio > HEALTH_EPOCH_WH_FACTOR else -1 if ratio < 1 / HEALTH_EPOCH_WH_FACTOR else 0)
            wh_run = ([*wh_run, (index, jumped, per_pct)]
                      if jumped and (not wh_run or wh_run[-1][1] == jumped)
                      else [(index, jumped, per_pct)] if jumped else [])
        trigger = None
        if len(power_run) >= HEALTH_EPOCH_RUN:
            trigger = ("charger", power_run[0][0], [p for _, _, p in power_run], None)
        elif len(wh_run) >= HEALTH_EPOCH_WH_RUN:
            trigger = ("battery", wh_run[0][0], None, [w for _, _, w in wh_run])
        if trigger is not None:
            reason, first, powers, whs = trigger
            began = str(charges[first].get("at") or "")
            new = {"id": f"e{began[:10]}", "from": began, "reason": reason,
                   "plateauW": round(_median(powers), 1) if powers else None,
                   "whPerPct": round(_median(whs), 3) if whs else None}
            if any(epoch["id"] == new["id"] for epoch in epochs):
                new["id"] = f"{new['id']}-{len(epochs)}"
            epochs.append(new)
            for later in range(first, index + 1):
                ids[later] = new["id"]
            current, power_run, wh_run = new, [], []
    return ids, epochs


def _month_key(at: datetime | None) -> str | None:
    return None if at is None else at.astimezone(timezone.utc).strftime("%Y-%m")


def _bucket(rows: list[dict]) -> dict | None:
    """One month of one epoch: what pools exactly across months (version 2):
    the weights, their mean Wh per 1 % and its spread inside the month."""
    used = [row for row in rows if row["weight"] > 0]
    if not used:
        return None
    weight = sum(row["weight"] for row in used)
    mean = sum(row["weight"] * row["r"] for row in used) / weight
    ats = [row["at"] for row in used if row["at"] is not None]
    return {
        "v": HEALTH_LOG_VERSION,
        "sumW": round(weight, 4),
        "sumW2": round(sum(row["weight"] ** 2 for row in used), 4),
        "mean": round(mean, 5),
        "chi2": round(sum(row["weight"] * (row["r"] / mean - 1) ** 2 for row in used), 5),
        "charges": len(used),
        "dropped": sum(1 for row in rows if row.get("dropped")),
        "firstAt": min(ats).isoformat() if ats else None,
        "lastAt": max(ats).isoformat() if ats else None,
    }


def _pooled(buckets: list[dict]) -> dict | None:
    """Several buckets as one: Wh per 1 %, charges, effective charges, its
    error in % of itself and the span in days. Version-1 buckets (QA 164)
    pool only with each other."""
    buckets = [bucket for bucket in buckets if isinstance(bucket, dict)]
    current = [bucket for bucket in buckets
               if bucket.get("v") == HEALTH_LOG_VERSION and float(bucket.get("sumW") or 0) > 0
               and _positive(bucket.get("mean"))]
    if current:
        weight = sum(float(bucket["sumW"]) for bucket in current)
        mean = sum(float(bucket["sumW"]) * float(bucket["mean"]) for bucket in current) / weight
        chi2 = sum(float(bucket.get("chi2") or 0)
                   + float(bucket["sumW"]) * (float(bucket["mean"]) / mean - 1) ** 2 for bucket in current)
        charges = int(sum(int(bucket.get("charges") or 0) for bucket in current))
        birge = math.sqrt(chi2 / (charges - 1)) if charges >= 2 else 1.0
        squares = sum(float(bucket.get("sumW2") or 0) for bucket in current)
        pooled = {"whPerPct": mean, "charges": charges,
                  "effective": weight ** 2 / squares if squares else 0.0,
                  "errorPct": 100 * max(1.0, birge) / math.sqrt(weight),
                  "scatterPct": 100 * math.sqrt(chi2 / weight),
                  "sumW": weight, "birge": birge}
        return {**pooled, **_span(current)}
    legacy = [bucket for bucket in buckets
              if bucket.get("v") is None and float(bucket.get("sumWG") or 0) > 0
              and float(bucket.get("sumW") or 0) > 0]
    if not legacy:
        return None
    total = {key: sum(float(bucket.get(key) or 0) for bucket in legacy)
             for key in ("sumW", "sumW2", "sumWE", "sumWG", "sumWV", "sumWV2")}
    wh = total["sumWE"] / total["sumWG"]
    mean = total["sumWV"] / total["sumW"]
    variance = max(0.0, total["sumWV2"] / total["sumW"] - mean * mean)
    scatter = math.sqrt(variance) / mean if mean else 0.0
    effective = total["sumW"] ** 2 / total["sumW2"] if total["sumW2"] else 0.0
    pooled = {"whPerPct": wh, "charges": int(sum(int(bucket.get("charges") or 0) for bucket in legacy)),
              "effective": effective, "errorPct": _legacy_error_pct(scatter, effective),
              "scatterPct": scatter * 100, "sumW": None, "birge": 1.0}
    return {**pooled, **_span(legacy)}


def _span(buckets: list[dict]) -> dict:
    firsts = [at for at in (_parse_at(bucket.get("firstAt")) for bucket in buckets) if at]
    lasts = [at for at in (_parse_at(bucket.get("lastAt")) for bucket in buckets) if at]
    span = (max(lasts) - min(firsts)).total_seconds() / 86400 if firsts and lasts else 0.0
    return {"from": min(firsts).isoformat() if firsts else None,
            "to": max(lasts).isoformat() if lasts else None, "days": span}


def _legacy_error_pct(scatter: float, effective: float) -> float:
    """QA 164's error of a version-1 reference, in % of itself."""
    per_charge = max(scatter * 100, _LEGACY_SCATTER_PCT)
    return math.sqrt((per_charge / math.sqrt(max(effective, 1.0))) ** 2 + _LEGACY_READING_PCT ** 2)


def _reference_ready(pooled: dict) -> bool:
    if pooled["charges"] < HEALTH_REFERENCE_MIN_CHARGES or pooled["days"] < HEALTH_REFERENCE_DAYS:
        return False
    return (pooled["errorPct"] <= HEALTH_REFERENCE_MAX_ERROR_PCT
            or (pooled["days"] >= HEALTH_REFERENCE_FALLBACK_DAYS
                and pooled["charges"] >= HEALTH_REFERENCE_FALLBACK_CHARGES))


def _reference_from(pooled: dict, buckets: list[dict], now: datetime | None) -> dict:
    return {"v": HEALTH_LOG_VERSION, "whPerPct": round(pooled["whPerPct"], 4),
            "charges": pooled["charges"], "effective": round(pooled["effective"], 2),
            "errorPct": round(pooled["errorPct"], 2), "from": pooled["from"], "to": pooled["to"],
            "months": [bucket["month"] for bucket in buckets],
            "fixedAt": (now or datetime.now(timezone.utc)).isoformat()}


def _migrated_reference(legacy: dict, kept: list[dict], now: datetime | None) -> dict | None:
    """QA 166: a QA 164 reference is computed once again by the new weights
    from the very months it was fixed on, when the log still holds them all.
    QA 166 (2, owner's choice): otherwise ``None``, and the reference is set
    again once by the usual rule (the owner's had been pulled to 88.9 % by one
    charge whose gauge had drifted 14 points, and its September could no
    longer be pooled)."""
    if legacy.get("v") == HEALTH_LOG_VERSION:
        return legacy
    months = [str(month) for month in (legacy.get("months") or [])]
    buckets = [bucket for bucket in kept if bucket.get("v") == HEALTH_LOG_VERSION
               and (bucket.get("epoch") or "e0") == "e0" and bucket.get("month") in months]
    pooled = _pooled(buckets) if months and len(buckets) == len(set(months)) else None
    if pooled is None:
        return None
    reference = _reference_from(pooled, buckets, now)
    reference.update(fixedAt=legacy.get("fixedAt") or reference["fixedAt"], migratedFrom=1,
                     migratedAt=(now or datetime.now(timezone.utc)).isoformat())
    return reference


def update_health_log(log: dict | None, charges: list[dict], *,
                      complete: bool = True, now: datetime | None = None,
                      full_drift: float = HEALTH_FULL_DRIFT_PRIOR) -> dict:
    """QA 164: the monthly log of battery health, rebuilt for every month the
    charges cover and kept for the months they no longer do. ``complete`` is
    False when the oldest charges have already left the list: the oldest
    month there is then partial, and a stored one is kept. A reference is
    set once per epoch and never replaced.

    QA 166 (version 2): months are per epoch and pool by 1/σ²; a version-1
    reference is computed again once from its own months (``migratedFrom``),
    or, when those months can no longer be pooled, set again once by the
    usual rule (the old one is kept in ``replaced``)."""
    stored = dict(log) if isinstance(log, dict) else {}
    keyed: dict[tuple[str, str], dict] = {}
    for bucket in stored.get("months") or []:
        if isinstance(bucket, dict) and bucket.get("month"):
            keyed[(str(bucket["month"]), str(bucket.get("epoch") or "e0"))] = dict(bucket)
    ordered = sorted(charges, key=lambda item: str(item.get("at") or ""))
    trusts = _health_trusts(ordered)
    epoch_ids, epochs = _health_epochs(ordered, stored.get("epochs"))
    typical = _median([float(item["energyWh"]) / _gain(item) for item in ordered
                       if _positive(item.get("energyWh")) and _gain(item) >= HEALTH_MIN_GAIN_PCT])
    scale = _implied_capacity(typical, DEFAULT_EFFICIENCY) if typical else None
    rows: list[dict] = []
    if ordered and scale:
        rows = _charge_rows(ordered, trusts, DEFAULT_EFFICIENCY,
                            lambda capacity: capacity / scale * 100, epoch_ids)
        _apply_weights(rows, health_sigmas(rows, full_drift=full_drift)["points"],
                       full_drift=full_drift)
        _drop_outliers_nearby(rows)
    grouped: dict[tuple[str, str], list[dict]] = {}
    for row in rows:
        month = _month_key(row["at"])
        if month:
            grouped.setdefault((month, row["epoch"]), []).append(row)
    oldest = min((key[0] for key in grouped), default=None)
    for key, month_rows in grouped.items():
        if key[0] == oldest and not complete and key in keyed:
            continue
        bucket = _bucket(month_rows)
        if bucket is None:
            keyed.pop(key, None)
        else:
            keyed[key] = {"month": key[0], "epoch": key[1], **bucket}
    kept = [keyed[key] for key in sorted(keyed)][-HEALTH_LOG_MONTHS:]
    references = {str(key): dict(value) for key, value in (stored.get("references") or {}).items()
                  if isinstance(value, dict)}
    replaced = [dict(item) for item in (stored.get("replaced") or []) if isinstance(item, dict)]
    legacy = stored.get("reference") if isinstance(stored.get("reference"), dict) else None
    if legacy is not None and "e0" not in references:
        migrated = _migrated_reference(legacy, kept, now)
        if migrated is not None:
            references["e0"] = migrated
        else:
            # Set again once by the usual rule below; the old one is kept here.
            replaced.append({**legacy, "reason": "months-missing",
                             "replacedAt": (now or datetime.now(timezone.utc)).isoformat()})
    for epoch in [item["id"] for item in epochs] or ["e0"]:
        if epoch in references:
            continue
        running: list[dict] = []
        for bucket in kept:
            if (bucket.get("epoch") or "e0") != epoch or bucket.get("v") != HEALTH_LOG_VERSION:
                continue
            running.append(bucket)
            pooled = _pooled(running)
            if pooled and _reference_ready(pooled):
                references[epoch] = _reference_from(pooled, running, now)
                break
    result = {"version": HEALTH_LOG_VERSION, "months": kept, "reference": references.get("e0"),
              "references": references, "epochs": epochs}
    if replaced:
        result["replaced"] = replaced[-10:]
    return result


def _reference_error_pct(reference: dict) -> float:
    if reference.get("v") == HEALTH_LOG_VERSION and reference.get("errorPct") is not None:
        return float(reference["errorPct"])
    return _legacy_error_pct(float(reference.get("scatter") or 0), float(reference.get("effective") or 1))


def _reference_need(pooled: dict | None) -> tuple[int, int]:
    """Charges and days still needed before the reference is fixed, by the
    nearer of the two ways (its error small enough after 28 days, or 8
    charges after 90 days), at this vehicle's own pace of charging."""
    if not pooled:
        return HEALTH_REFERENCE_MIN_CHARGES, HEALTH_REFERENCE_DAYS
    charges, days = pooled["charges"], pooled["days"]
    weight = pooled.get("sumW") or 0.0
    typical = weight / charges if charges else 0.0
    target = (100 * max(1.0, pooled.get("birge") or 1.0) / HEALTH_REFERENCE_MAX_ERROR_PCT) ** 2
    by_error = (math.ceil(max(0.0, target - weight) / typical) if typical > 0
                else HEALTH_REFERENCE_FALLBACK_CHARGES)
    charges_a = max(HEALTH_REFERENCE_MIN_CHARGES - charges, by_error, 0)
    days_a = max(0, math.ceil(HEALTH_REFERENCE_DAYS - days))
    charges_b = max(HEALTH_REFERENCE_FALLBACK_CHARGES - charges, HEALTH_REFERENCE_MIN_CHARGES - charges, 0)
    days_b = max(0, math.ceil(HEALTH_REFERENCE_FALLBACK_DAYS - days))
    pace = charges / days if days > 0 else 0.0
    def wait(more: int, span: int) -> float:
        return max(span, more / pace if pace > 0 else more * 7.0)
    return (charges_a, days_a) if wait(charges_a, days_a) <= wait(charges_b, days_b) else (charges_b, days_b)


def health_tracking(log: dict, current_wh_per_pct: float | None, current_error_pct: float | None,
                    nominal: float, efficiency: float, *, epoch: str = "e0",
                    usable: float = 1.0) -> dict:
    """The battery against its own start, and its months (QA 164), in the
    current epoch (QA 166)."""
    references = log.get("references") or {}
    reference = references.get(epoch) or (log.get("reference") if epoch == "e0" else None)
    months = [bucket for bucket in (log.get("months") or []) if (bucket.get("epoch") or "e0") == epoch]
    info = next((item for item in (log.get("epochs") or []) if item.get("id") == epoch), None)
    base = {"epoch": epoch,
            "epochReason": info.get("reason") if info and epoch != "e0" else None,
            "epochFrom": info.get("from") if info and epoch != "e0" else None}
    if not reference:
        pooled = _pooled(months)
        need_charges, need_days = _reference_need(pooled)
        return {"status": "building", "needCharges": need_charges, "needDays": need_days,
                "charges": pooled["charges"] if pooled else 0, "monthly": [], **base}
    base_wh = float(reference["whPerPct"])
    base_error = _reference_error_pct(reference)
    result = {"status": "ready", "since": reference.get("from"), "until": reference.get("to"),
              "referenceCharges": reference.get("charges"),
              "referenceCapacityPct": round(_implied_capacity(base_wh, efficiency) / nominal * 100, 1),
              "referenceErrorPct": round(base_error, 2),
              "relativePct": None, "uncertaintyPct": None, "lowPct": None, "highPct": None, **base}
    if current_wh_per_pct:
        relative = current_wh_per_pct / base_wh * 100 * usable
        error = relative * math.hypot(current_error_pct or base_error, base_error) / 100
        result.update(relativePct=round(relative, 1), uncertaintyPct=round(error, 1),
                      lowPct=round(relative - error, 1), highPct=round(relative + error, 1))
    monthly = []
    for bucket in months[-60:]:
        pooled = _pooled([bucket])
        if not pooled:
            continue
        monthly.append({"month": bucket["month"], "charges": pooled["charges"],
                        "relativePct": round(pooled["whPerPct"] / base_wh * 100, 1),
                        "sohPct": round(_implied_capacity(pooled["whPerPct"], efficiency) / nominal * 100, 1)})
    result["monthly"] = monthly
    return result


def _health_baseline(charges: list[dict], soh, efficiency: float) -> dict | None:
    """First charges against the latest ones; ``None`` until there are enough
    charges over enough days for the difference to mean anything."""
    if len(charges) < HEALTH_BASELINE_MIN_CHARGES:
        return None

    def when(item):
        try:
            parsed = datetime.fromisoformat(str(item.get("at")).replace("Z", "+00:00"))
        except (TypeError, ValueError):
            return None
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)

    first_at, last_at = when(charges[0]), when(charges[-1])
    if first_at is None or last_at is None:
        return None
    days = (last_at - first_at).total_seconds() / 86400
    if days < HEALTH_BASELINE_MIN_DAYS:
        return None
    k = HEALTH_BASELINE_CHARGES

    def middle(items):
        return soh(_implied_capacity(_median([float(item["whPerPct"]) for item in items]), efficiency))

    first, latest = middle(charges[:k]), middle(charges[-k:])
    return {"firstPct": first, "latestPct": latest, "changePct": round(latest - first, 1),
            "since": charges[0].get("at"), "days": int(round(days)), "charges": len(charges)}


def training_status(profile: LearnedProfile) -> dict:
    """How much new data is waiting and whether training is worth offering."""
    required = TRAINING_MIN_NEW_SAMPLES if profile.wh_per_pct else FIRST_TRAINING_MIN_SAMPLES
    pending = len(profile.pending)
    return {
        "pending": pending,
        "required": required,
        "ready": pending >= required,
        "trained": len(profile.samples),
        "mae": honest_mae(profile),
        "trainedAt": profile.trained_at,
        "version": profile.version,
        "learning": learning_progress(profile),
        "shadow": shadow_report(profile),
    }


def honest_mae(profile: LearnedProfile) -> float | None:
    """The error to show: the stored one, or the model's error on the charges
    it now holds when that is worse (QA 146: a rejected training kept "0.55"
    while the model missed the newest charges by 5.81)."""
    if profile.layer != "base" and profile.layer_mae is not None:
        return profile.layer_mae  # measured on charges that layer had not seen
    stored = profile.soc_mae
    charges = [*profile.samples, *profile.pending]
    if not profile.wh_per_pct or not any(_scored(item) for item in charges):
        return stored
    live = round(_mae_with(charges, profile.wh_per_pct), 2)
    return live if stored is None else max(stored, live)


def unique_charges(profile: LearnedProfile) -> list[dict]:
    merged: dict[str, dict] = {}
    for index, item in enumerate([*profile.ledger, *profile.samples, *profile.pending]):
        merged[str(item.get("sessionId") or f"_{index}")] = item
    return list(merged.values())


def learning_progress(profile: LearnedProfile) -> dict:
    """How far the vehicle's own charges are from a full cycle ("Đang học")."""
    charges = unique_charges(profile)
    gain = sum(_gain(item) for item in charges)
    return {
        "charges": len(charges),
        "needCharges": LEARNING_MIN_CHARGES,
        "gainPct": round(gain, 1),
        "needGainPct": LEARNING_MIN_GAIN_PCT,
        "done": len(charges) >= LEARNING_MIN_CHARGES and gain >= LEARNING_MIN_GAIN_PCT,
    }


def gauge_offset_after(start_pct: float, energy_wh: float, wh_per_pct: float,
                       actual_end_pct: float) -> float:
    """What the gauge owes after this charge. It is settled on the next charge,
    so it is not added up (owner's 7 charges: mean error about 2 %, 3.3 % without
    it). Only 7 charges: a single shortfall just moves the error to the charge after
    the catch-up, and a steady drift doubles it, so it moves a cutoff only after real
    charges proved it, at each training again. A full battery settles it at once."""
    if actual_end_pct >= GAUGE_RESET_END_PCT:
        return 0.0
    offset = start_pct + energy_wh / wh_per_pct - actual_end_pct
    return round(min(MAX_GAUGE_OFFSET_PCT, max(-MAX_GAUGE_OFFSET_PCT, offset)), 2)


def shadow_report(profile: LearnedProfile) -> dict:
    """Would carrying the gauge offset predict the end % better, charge by charge
    as it really ran? A charge that reached 100 % ends on the charger's signal,
    so the estimate had nothing to get right there and it is not scored."""
    plain, carried = [], []
    for item in unique_charges(profile):
        wh = _positive(item.get("shadowWhPerPct"))
        if wh is None or item.get("shadowOffsetPct") is None:
            continue
        actual = float(item["actualEndPct"])
        if actual >= GAUGE_RESET_END_PCT:
            continue
        end = float(item["startPct"]) + float(item["energyWh"]) / wh
        plain.append((min(100.0, end), actual))
        carried.append((min(100.0, end + float(item["shadowOffsetPct"])), actual))
    return {
        "n": len(plain),
        "need": SHADOW_MIN_CHARGES,
        "ready": len(plain) >= SHADOW_MIN_CHARGES,
        "offsetPct": profile.gauge_offset_pct,
        "plain": _stats_rmse(plain),
        "withOffset": _stats_rmse(carried),
    }


def _stats_rmse(pairs: list[tuple[float, float]]) -> dict:
    result = _stats(pairs)
    result["rmse"] = (round(math.sqrt(sum((p - a) ** 2 for p, a in pairs) / len(pairs)), 2)
                      if pairs else None)
    return result


def train(
    profile: LearnedProfile,
    *,
    base_wh_per_pct: float | None,
    now: datetime | None = None,
    mode: str = "finetune",
    step_limit: bool = False,
) -> tuple[LearnedProfile, dict]:
    """Fit the profile on stored + pending charges (owner pressed train).

    ``finetune``: recency-weighted, so the value follows a battery that wears
    and needs fewer Wh per %, and kept only if not worse than the current
    estimate on the data. ``retrain``: no recency weight and power/taper are
    re-learned from all stored charges; the same guard refuses a clearly worse
    result. Pending charges always move into the stored set so the data is
    never lost.
    """
    now = now or datetime.now(timezone.utc)
    retrain = mode == "retrain"
    merged: dict[str, dict] = {}
    for index, item in enumerate([*profile.samples, *profile.pending]):
        merged[str(item.get("sessionId") or f"_{index}")] = item
    # By the charge's date: correcting an old charge's % must not push out a newer one.
    samples = sorted(merged.values(), key=lambda item: str(item.get("at") or ""))[-MAX_PROFILE_SAMPLES:]
    # QA 158: charges stored before trust existed get the trust their place
    # since the last full charge gives them.
    stamp_trust([*samples, *profile.ledger], profile.trust_calibration)
    weigh_now = None if retrain else now
    half_life = (FAST_HALF_LIFE_DAYS if (profile.trend or {}).get("fastFollow")
                 else HALF_LIFE_DAYS)
    if (not retrain and profile.wh_per_pct
            and not _recent_clean(unique_charges(profile) + samples, now)):
        # Only charges far from a full one lately: they would teach the
        # gauge's drift, not the battery. Keep the value in use.
        kept = LearnedProfile(**{**profile.__dict__, "samples": samples, "pending": [],
                                 "trained_at": now.isoformat()})
        return kept, {"mode": mode, "used": len(samples), "added": len(profile.pending),
                      "beforeMae": profile.soc_mae, "afterMae": profile.soc_mae,
                      "whPerPct": profile.wh_per_pct, "decision": "kept_no_clean_data"}
    candidate_wh = _robust_wh(samples, base_wh_per_pct, weigh_now, half_life)
    step_limited = False
    if step_limit and profile.wh_per_pct and candidate_wh:
        if abs(candidate_wh / profile.wh_per_pct - 1) > RECALIBRATE_MAX_STEP:
            candidate_wh = (candidate_wh + profile.wh_per_pct) / 2
            step_limited = True
    tapers = [(item.get("taperStartPct"), item.get("taperPowerRatio")) for item in samples
              if item.get("taperStartPct") and item.get("taperPowerRatio")]
    if retrain:
        taper_start = _median([a for a, _ in tapers])
        taper_ratio = _median([b for _, b in tapers])
    else:
        taper_start, taper_ratio = tapers[-1] if tapers else (None, None)
    candidate = LearnedProfile(
        wh_per_pct=round(candidate_wh, 3) if candidate_wh else None,
        power_w=_median([item.get("avgPowerW") for item in samples if item.get("avgPowerW")]) or profile.power_w,
        taper_start_pct=_positive(taper_start) or profile.taper_start_pct,
        taper_power_ratio=_positive(taper_ratio) or profile.taper_power_ratio,
        samples=samples,
        version=profile.version + 1,
        pending=[],
        trained_at=now.isoformat(),
        gauge_offset_pct=profile.gauge_offset_pct,
        gauge_offset_at=profile.gauge_offset_at,
        ledger=profile.ledger,
        layer=profile.layer,
        ai_model=profile.ai_model,
        layer_mae=profile.layer_mae,
        drift_log=profile.drift_log,
        trust_calibration=profile.trust_calibration,
        wh_history=_with_history(profile, candidate_wh, now, mode),
        cross_log=profile.cross_log,
        trend=profile.trend,
        health_log=profile.health_log,
    )
    candidate.soc_mae = _loo_mae(samples, base_wh_per_pct, weigh_now, half_life)
    evaluation = _evaluate(samples, profile, base_wh_per_pct, weigh_now, half_life)
    after = evaluation["new"]["mae"]
    before = evaluation["current"]["mae"]
    report = {"mode": "retrain" if retrain else "finetune", "used": len(samples),
              "added": len(profile.pending), "beforeMae": before,
              "afterMae": after, "whPerPct": candidate.wh_per_pct,
              "evaluation": evaluation, "stepLimited": step_limited}
    # Before anything was learned, the value to beat is the catalog's (QA 148).
    reference = before if profile.wh_per_pct else evaluation["base"]["mae"]
    if reference is not None and after is not None and after > reference + 0.5:
        # Keep the proven estimate; the new charges stay stored for later.
        kept = LearnedProfile(**{**profile.__dict__, "samples": samples, "pending": [],
                                 "trained_at": now.isoformat(),
                                 "soc_mae": (_round2(_mae_with(samples, profile.wh_per_pct))
                                             if profile.wh_per_pct else None)})
        return kept, {**report, "decision": "rejected_worse", "whPerPct": profile.wh_per_pct,
                      "afterMae": _round2(reference)}
    return candidate, {**report, "decision": "promoted" if candidate.wh_per_pct else "no_data"}


def _evaluate(samples: list[dict], profile: LearnedProfile, base: float | None,
              now: datetime | None, half_life: float = HALF_LIFE_DAYS) -> dict:
    """Objective comparison on labelled charges (Task 127).

    Each charge's end % is predicted from its energy by: the model in use now,
    the new model fitted WITHOUT that charge (leave-one-out) and the catalog
    default. New (pending) charges are the test set when there are any, so the
    model in use has not seen them; otherwise every stored charge is used.
    Charges that ended at 100 % are listed but not scored (QA 148): the charger
    ended them, so the estimate had nothing to get right, and scoring them favoured
    a Wh/% too low for every other charge.
    """
    pending_ids = {str(item.get("sessionId")) for item in profile.pending}
    # QA 158: judged on charges near a full one when there are enough.
    scored = _scoring_set(samples)
    fresh = [item for item in scored if str(item.get("sessionId")) in pending_ids]
    test = fresh or scored
    rows = []
    pairs = {"current": [], "new": [], "base": []}
    for item in samples:
        others = [other for other in samples if other is not item]
        loo_wh = _robust_wh(others, base, now, half_life) if others else None
        actual = float(item["actualEndPct"])
        predicted = {
            "current": _predicted_end(item, profile.wh_per_pct) if profile.wh_per_pct else None,
            "new": _predicted_end(item, loo_wh) if loo_wh else None,
            "base": _predicted_end(item, base) if base else None,
        }
        if item in test:
            for key, value in predicted.items():
                if value is not None:
                    pairs[key].append((value, actual))
        rows.append({
            "at": str(item.get("at") or "")[:10],
            "startPct": float(item.get("startPct") or 0),
            "actual": actual,
            "energyWh": round(float(item.get("energyWh") or 0)),
            "labelSource": item.get("labelSource") or "user",
            "censored": bool(item.get("censored")),
            "tested": item in test,
            **{key: (None if value is None else round(value, 1)) for key, value in predicted.items()},
        })
    return {
        "method": "bỏ-một-ra trên từng lần sạc",
        "testSet": "new" if fresh else "all",
        "currentSawTest": not fresh,
        "current": _stats(pairs["current"]),
        "new": _stats(pairs["new"]),
        "base": _stats(pairs["base"]),
        "examples": rows[-12:],
        "cleanOnly": len(scored) < sum(1 for item in samples if _scored(item)),
    }


def _stats(pairs: list[tuple[float, float]]) -> dict:
    if not pairs:
        return {"n": 0, "mae": None, "bias": None, "within1": None, "within2": None}
    errors = [predicted - actual for predicted, actual in pairs]
    n = len(errors)
    return {"n": n, "mae": round(sum(abs(e) for e in errors) / n, 2),
            "bias": round(sum(errors) / n, 2),
            "within1": round(sum(abs(e) <= 1 for e in errors) / n, 3),
            "within2": round(sum(abs(e) <= 2 for e in errors) / n, 3)}


def learn(
    profile: LearnedProfile,
    sample: dict,
    *,
    base_wh_per_pct: float | None,
    now: datetime | None = None,
) -> tuple[LearnedProfile, str]:
    """Queue one sample and fine-tune at once (bootstrap script and tests).

    The candidate is promoted only when it is not worse than the current
    profile on the stored samples (small tolerance), so one bad reading
    cannot degrade the model.
    """
    queued, decision = queue_sample(profile, sample, base_wh_per_pct=base_wh_per_pct, now=now)
    if decision != "queued":
        return profile, decision
    trained, report = train(queued, base_wh_per_pct=base_wh_per_pct, now=now)
    return trained, report["decision"]


def learn_taper(curve: list[dict], start_pct: float, wh_per_pct: float) -> tuple[float, float] | None:
    """(taper start %, tail power ratio) from a server curve, if it shows one.

    ``curve`` items carry cumulative session energy ``wh`` and power ``p``.
    """
    points = [(float(item.get("wh") or 0), float(item.get("p") or 0)) for item in curve
              if item.get("p") is not None and float(item.get("p") or 0) > IDLE_POWER_W]
    if len(points) < 8:
        return None
    head = [p for _, p in points[: max(3, len(points) // 2)]]
    cc = _median(head)
    if not cc:
        return None
    for index, (wh, power) in enumerate(points):
        tail = [p for _, p in points[index:]]
        if power < cc * 0.85 and len(tail) >= 3 and max(tail) < cc * 0.9:
            soc = start_pct + wh / wh_per_pct
            ratio = (_median(tail) or cc) / cc
            if 50 <= soc <= 99.5:
                return round(soc, 1), round(min(0.95, max(0.2, ratio)), 3)
            return None
    return None


def _gain(item: dict) -> float:
    return max(0.0, float(item.get("actualEndPct") or 0) - float(item.get("startPct") or 0))


def _scored(item: dict) -> bool:
    """A charge the estimate decided: it did not end at 100 %."""
    return not item.get("censored") and float(item.get("actualEndPct") or 0) < GAUGE_RESET_END_PCT


def _robust_wh(samples: list[dict], base: float | None, now: datetime | None,
               half_life: float = HALF_LIFE_DAYS) -> float | None:
    """Median weighted by % gained and recency, starting from the catalog value.

    QA 146: this used to clamp to the lowest charge that ended at 100 %, so one
    such charge (0 -> 100 at 22.84 Wh/%) decided the whole model and made every
    later training look worse. A median needs several charges to agree, which
    separates a battery that wears from one odd gauge reading.
    """
    pairs = [(float(item["whPerPct"]),
              _gain(item) * _weight(item, now, half_life)
              * (1.0 if _scored(item) else FULL_CHARGE_WEIGHT)
              # QA 158: a charge far from a full one teaches the gauge's drift.
              * TRUST_WEIGHT[trust_of(item)])
             for item in samples]
    if base:
        # The catalog fades with the vehicle's own charges: one full charge cannot
        # move it, a second one that agrees can, whatever % they started from.
        # QA 158: trust weighs the charges against each other, not against
        # the catalog: with no clean charge yet, the catalog keeps its pull.
        top = max((TRUST_WEIGHT[trust_of(item)] for item in samples), default=1.0)
        pairs.append((base, PRIOR_GAIN_PCT / max(1, len(samples)) * top))
    return _weighted_median(pairs)


def _loo_mae(samples: list[dict], base: float | None, now: datetime | None,
             half_life: float = HALF_LIFE_DAYS) -> float | None:
    errors = []
    scoring = _scoring_set(samples)
    for index, item in enumerate(samples):
        if not any(item is other for other in scoring):
            continue
        others = samples[:index] + samples[index + 1:]
        wh = _robust_wh(others, base, now, half_life)
        if wh:
            errors.append(abs(_predicted_end(item, wh) - float(item["actualEndPct"])))
    return round(sum(errors) / len(errors), 2) if errors else None


def _mae_with(samples: list[dict], wh: float) -> float:
    errors = [abs(_predicted_end(item, wh) - float(item["actualEndPct"]))
              for item in _scoring_set(samples)]
    return sum(errors) / len(errors) if errors else 0.0


def _predicted_end(item: dict, wh: float) -> float:
    return min(100.0, float(item["startPct"]) + float(item["energyWh"]) / wh)


def _weight(item: dict, now: datetime | None, half_life: float = HALF_LIFE_DAYS) -> float:
    if now is None:
        return 1.0  # retrain: every stored charge weighs the same
    try:
        at = datetime.fromisoformat(str(item.get("at")).replace("Z", "+00:00"))
        if at.tzinfo is None:
            at = at.replace(tzinfo=timezone.utc)
        age_days = max(0.0, (now - at).total_seconds() / 86400)
    except (TypeError, ValueError):
        age_days = 0.0
    return 0.5 ** (age_days / half_life)


def trust_of(item: dict) -> str:
    """The stored trust of a labelled charge; one stored before QA 158 and not
    yet stamped counts as clean, as it did before."""
    value = item.get("trust")
    return value if value in TRUST_WEIGHT else "high"


def trust_level(sessions_since: int, fulls_since: float | None, *, anchored: bool,
                limits: dict | None = None) -> str:
    """QA 158: how far the gauge can have drifted, from the charges and the
    energy since the last full one. Never ``high`` without a full one yet."""
    allowed = {**TRUST_LIMITS, **{key: value for key, value in (limits or {}).items()
                                  if key in TRUST_LIMITS and isinstance(value, (int, float))}}
    def within(sessions_key: str, fulls_key: str) -> bool:
        return (sessions_since <= allowed[sessions_key]
                and (fulls_since is None or fulls_since <= allowed[fulls_key]))
    level = ("high" if within("highSessions", "highFulls")
             else "medium" if within("mediumSessions", "mediumFulls") else "low")
    if not anchored and level == "high":
        level = "medium"
    return level


def stamp_trust(rows: list[dict], limits: dict | None = None) -> None:
    """Give labelled charges without a trust the one their place in the
    charge order gives them (charges stored before QA 158). Every list holding
    a copy of a charge gets the same value."""
    order: dict[str, str] = {}
    anchored = False
    partial = 0
    seen: set[str] = set()
    for item in sorted(rows, key=lambda row: str(row.get("at") or "")):
        sid = str(item.get("sessionId") or id(item))
        if sid in seen:
            continue
        seen.add(sid)
        order[sid] = item.get("trust") if item.get("trust") in TRUST_WEIGHT else trust_level(
            partial, None, anchored=anchored, limits=limits)
        if float(item.get("actualEndPct") or 0) >= GAUGE_RESET_END_PCT:
            anchored, partial = True, 0
        else:
            partial += 1
    for item in rows:
        if item.get("trust") not in TRUST_WEIGHT:
            sid = str(item.get("sessionId") or id(item))
            if sid in order:
                item["trust"] = order[sid]


def _scoring_set(samples: list[dict]) -> list[dict]:
    """Charges an estimate is judged on: the clean ones near a full charge when
    there are enough of them, otherwise every charge the estimate decided."""
    scored = [item for item in samples if _scored(item)]
    clean = [item for item in scored if trust_of(item) == "high"]
    return clean if len(clean) >= TRUST_MIN_SCORED else scored


def _recent_clean(rows: list[dict], now: datetime) -> bool:
    """A clean charge lately, or never one (nothing to compare): learning goes on."""
    clean = [item for item in rows if _scored(item) and item.get("trust") == "high"]
    if not clean:
        return True
    for item in clean:
        at = _parse_at(item.get("at"))
        if at is not None and (now - at).days <= CLEAN_DATA_DAYS:
            return True
    return False


def _parse_at(value) -> datetime | None:
    try:
        at = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    return at if at.tzinfo else at.replace(tzinfo=timezone.utc)


def _with_history(profile: LearnedProfile, new_wh: float | None, now: datetime,
                  reason: str) -> list[dict]:
    """The last Wh per 1 % values, to see and to go back to (QA 158)."""
    old = profile.wh_per_pct
    history = list(profile.wh_history)
    if old and new_wh and abs(new_wh - old) >= 0.001:
        history.append({"at": now.isoformat(), "whPerPct": round(old, 3), "reason": reason})
    return history[-MAX_WH_HISTORY:]


def calibrate_trust(drift_log: list[dict], now: datetime) -> dict | None:
    """Energy limits of the trust levels from the drift measured at full
    charges: about 1.5 % of drift is still ``high``, 3 % ``medium``."""
    rates = _drift_rates(drift_log)
    if len(rates) < DRIFT_CALIBRATION_MIN:
        return None
    rate = _median(rates)
    if not rate or rate <= 0:
        return None
    high = min(3.0, max(0.7, 1.5 / rate))
    medium = min(5.0, max(high + 0.5, 3.0 / rate))
    return {"highFulls": round(high, 2), "mediumFulls": round(medium, 2),
            "driftPctPerFull": round(rate, 2), "n": len(rates), "at": now.isoformat()}


def wh_trend(rows: list[dict], now: datetime) -> dict | None:
    """Wh per 1 % of clean charges in the last 90 days against the 90 before.
    A drop beyond 3 % is a battery that wears: learning follows it faster."""
    recent, prior = [], []
    for item in rows:
        if not _scored(item) or trust_of(item) != "high" or not item.get("whPerPct"):
            continue
        at = _parse_at(item.get("at"))
        if at is None:
            continue
        age = (now - at).days
        if age <= TREND_WINDOW_DAYS:
            recent.append(float(item["whPerPct"]))
        elif age <= 2 * TREND_WINDOW_DAYS:
            prior.append(float(item["whPerPct"]))
    if len(recent) < TREND_MIN_CHARGES or len(prior) < TREND_MIN_CHARGES:
        return None
    drop = 1 - _median(recent) / _median(prior)
    return {"whDropPct": round(drop * 100, 1), "fastFollow": drop > TREND_DROP,
            "recent": len(recent), "prior": len(prior), "at": now.isoformat()}


def recalibrate(profile: LearnedProfile, *, base_wh_per_pct: float | None, now: datetime,
                full: dict, exact: bool, sessions_since: int, fulls_since: float | None,
                days_since: float | None) -> tuple[LearnedProfile, dict]:
    """QA 158: the deep calibration at each charge that reached full, the
    moment the gauge is right. Measures how far it had drifted, refits Wh per
    1 % on clean charges (at most halfway when it moves more than 3 %), fits
    the trust limits to the measured drift and checks for a wearing battery.
    ``full`` is the charge just queued; ``exact`` = the charger's full signal
    ended it (a % typed after a timed charge that ran on is not a measure)."""
    wh = profile.wh_per_pct or base_wh_per_pct
    drift = None
    log = list(profile.drift_log)
    if exact and wh and full.get("energyWh"):
        drift = round(100.0 - (float(full.get("startPct") or 0) + float(full["energyWh"]) / wh), 2)
        # QA 166 (2): one entry per charge (the 100 % typed after the
        # charger's full signal calibrates the same charge again); battery
        # health reads this log.
        if full.get("sessionId"):
            log = [item for item in log if item.get("sessionId") != full.get("sessionId")]
        log.append({"at": str(full.get("at") or now.isoformat()), "sessionId": full.get("sessionId"),
                    "driftPct": drift, "sessions": sessions_since,
                    "fulls": round(fulls_since, 2) if fulls_since is not None else None,
                    "days": round(days_since, 1) if days_since is not None else None})
    working = LearnedProfile(**{**profile.__dict__, "drift_log": log[-MAX_DRIFT_LOG:]})
    updated, report = train(working, base_wh_per_pct=base_wh_per_pct, now=now,
                            mode="finetune", step_limit=True)
    calibration = calibrate_trust(updated.drift_log, now) or profile.trust_calibration
    trend = wh_trend(unique_charges(updated), now)
    updated = LearnedProfile(**{**updated.__dict__, "trust_calibration": calibration, "trend": trend})
    return updated, {**report, "reason": "full_charge", "driftPct": drift,
                     "trustCalibration": calibration, "trend": trend}


def _dicts(value) -> list[dict]:
    return [dict(item) for item in (value or []) if isinstance(item, dict)]


def _weighted_median(pairs: list[tuple[float, float]]) -> float | None:
    pairs = sorted((v, w) for v, w in pairs if w > 0 and math.isfinite(v))
    if not pairs:
        return None
    total = sum(w for _, w in pairs)
    running = 0.0
    for value, weight in pairs:
        running += weight
        if running >= total / 2:
            return value
    return pairs[-1][0]


def _round2(value: float | None) -> float | None:
    return None if value is None else round(value, 2)


def _median(values) -> float | None:
    numbers = sorted(float(v) for v in values if v is not None and math.isfinite(float(v)))
    if not numbers:
        return None
    middle = len(numbers) // 2
    return numbers[middle] if len(numbers) % 2 else (numbers[middle - 1] + numbers[middle]) / 2


def _finite(value) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return 0.0
    return number if math.isfinite(number) else 0.0


def _clamp_pct(value) -> float:
    try:
        return min(100.0, max(0.0, float(value)))
    except (TypeError, ValueError):
        return 0.0


def _positive(value, *, allow_zero: bool = False) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(number) or number < 0 or (number == 0 and not allow_zero):
        return None
    return number
