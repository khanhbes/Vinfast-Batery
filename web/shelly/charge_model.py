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
            complete=len(queued.ledger) < MAX_LEDGER_CHARGES, now=now)
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
# QA 162: which charges the capacity left is computed from, and how.
HEALTH_MIN_GAIN_PCT = 20.0
HEALTH_WINDOW_DAYS = 120
HEALTH_WINDOW_CHARGES = 20
HEALTH_HALF_LIFE_DAYS = 180
HEALTH_TEST_FRESH_DAYS = 90
HEALTH_TEST_BOOST = 2.0
HEALTH_OUTLIER_FLOOR_PCT = 6.0
# The gauge is read in whole %: the result is never surer than this.
HEALTH_READING_FLOOR_PCT = 1.5
# The least scatter assumed for one charge (owner's charges right after a
# full one: 98.9 and 98.3; a few charges later: up to ±4).
HEALTH_CHARGE_SCATTER_PCT = 3.0
# Above this share of the weight left out as outliers, they widen the error.
HEALTH_MAX_DROPPED_SHARE = 0.25
# QA 164 (owner's choice): the main figure is the capacity against the first
# months the app followed this battery, which does not depend on the charger
# efficiency assumed for the absolute figure. The reference is fixed once it
# has this many counted charges over this many days, and never moves again.
HEALTH_REFERENCE_CHARGES = 8
HEALTH_REFERENCE_DAYS = 28
# Months kept in the health log (ten years of the battery's life).
HEALTH_LOG_MONTHS = 120
# Charges on each side a charge is compared with to call it an outlier.
HEALTH_NEIGHBOURS = 10
# The charger efficiency is assumed at 90 %; real ones sit about 87-93 %, so
# the absolute figure may be this much off on top of its measured error.
HEALTH_EFFICIENCY_SPREAD = 0.033
# With no counted charge in the window, the latest months still say something.
HEALTH_STALE_CHARGES = 6


def _implied_capacity(wh_per_pct: float, efficiency: float) -> float:
    """Usable capacity the battery stored: wall Wh per % × 100 × efficiency."""
    return wh_per_pct * 100 * efficiency


def battery_health(samples: list[dict], nominal_capacity_wh: float | None,
                   efficiency: float = DEFAULT_EFFICIENCY, *,
                   history: list[dict] | None = None,
                   now: datetime | None = None,
                   log: dict | None = None) -> dict:
    """% of the nominal capacity the battery still holds (QA 135).

    ``estimate``: from every charge with a confirmed end % (median of the
    recent ones; more charges, more confidence). ``test``: the owner's
    guided test, a charge started at ≤ 30 % that ran until the server saw
    the full-battery power tail, so it measures most of the capacity at once.
    Always an estimate: the scooter reports no cell data.

    QA 152, all additions beside ``estimate`` (which is computed as before):
    ``spread`` says how far single charges sit from each other (the gauge is
    read in whole %, so one charge alone can be several % off) and how sure
    the median therefore is. ``baseline`` compares the latest charges with
    the first ones in ``history`` (the long ledger): a change over months
    does not depend on the assumed charger efficiency, which the absolute
    number does. ``trend`` uses ``history`` too when it reaches further back.

    QA 162 (owner's choice): ``estimate`` is no longer the median of the
    last ten charges. On the owner's ledger single charges gave 85 % to
    121 %: the gauge falls behind and catches up between full charges. Each
    charge that gained at least 20 % now counts by % gained × how far the
    gauge could be trusted (the first charge after a full one most) × how
    recent it is; the guided test counts double for 90 days; charges far
    from the others are left out; the result is the pooled Wh/% of the rest.
    ``uncertaintyPct`` comes from their scatter and the whole-% reading.
    ``charges`` lists the latest ones with why each was or was not used.

    QA 164 (owner's choice): ``tracking`` is the main figure, the capacity
    against the first months the app followed this battery (``log``, the
    stored monthly log, merged with these charges), so the assumed charger
    efficiency cancels out. ``spread.totalPct`` adds that efficiency's own
    doubt to the absolute figure. With no counted charge in the window the
    latest months give a ``stale`` estimate instead of nothing.
    """
    nominal = _positive(nominal_capacity_wh)
    result: dict = {"nominalCapacityWh": nominal, "efficiency": efficiency,
                    "estimate": None, "test": None, "trend": [],
                    "spread": None, "baseline": None, "charges": [], "tracking": None}
    if nominal is None:
        return result

    def soh(capacity: float) -> float:
        return round(min(120.0, max(0.0, capacity / nominal * 100)), 1)

    exact = sorted(
        [item for item in samples
         if not item.get("censored") and _positive(item.get("whPerPct"))],
        key=lambda item: str(item.get("at") or ""))
    # QA 162: every distinct charge (the long ledger too), each with how far
    # the gauge could be trusted when it was read.
    merged: dict[str, dict] = {}
    for index, item in enumerate([*(history or []), *samples]):
        merged[str(item.get("sessionId") or f"_{index}")] = item
    charges = sorted(merged.values(), key=lambda item: str(item.get("at") or ""))
    trusts = _health_trusts(charges)
    rows = _health_rows(charges, trusts, efficiency, soh, now=now)
    result["charges"] = [row["public"] for row in rows[-HEALTH_WINDOW_CHARGES:]]
    used = [row for row in rows if row["public"]["used"]]
    health_log = update_health_log(log, charges, complete=len(history or []) < MAX_LEDGER_CHARGES,
                                   now=now)
    pooled_wh = None
    if used:
        weight = sum(row["weight"] for row in used)
        pooled = (sum(row["weight"] * row["energyWh"] for row in used)
                  / sum(row["weight"] * row["gain"] for row in used))
        pooled_wh = pooled
        capacity = _implied_capacity(pooled, efficiency)
        middle = soh(capacity)
        effective = weight ** 2 / sum(row["weight"] ** 2 for row in used)
        scatter = math.sqrt(sum(row["weight"] * (row["soh"] - middle) ** 2 for row in used) / weight)
        # Many charges far from the rest: the gauge is not settled, and the
        # result is not as sure as the ones left make it look.
        dropped = [row for row in rows if row.get("dropped")]
        dropped_weight = sum(row["dropped"] for row in dropped)
        if dropped_weight > HEALTH_MAX_DROPPED_SHARE * (weight + dropped_weight):
            scatter = math.sqrt(
                (sum(row["weight"] * (row["soh"] - middle) ** 2 for row in used)
                 + sum(row["dropped"] * (row["soh"] - middle) ** 2 for row in dropped))
                / (weight + dropped_weight))
        # A few charges that happen to agree say little: one charge alone is
        # never taken as closer than HEALTH_CHARGE_SCATTER_PCT.
        per_charge = max(scatter, HEALTH_CHARGE_SCATTER_PCT)
        uncertainty = math.sqrt((per_charge / math.sqrt(effective)) ** 2
                                + HEALTH_READING_FLOOR_PCT ** 2)
        result["estimate"] = {
            "sohPct": middle, "capacityWh": round(capacity),
            "samples": len(used), "effectiveCharges": round(effective, 1),
            "confidence": ("high" if uncertainty <= 2.5 and effective >= 3
                           else "medium" if uncertainty <= 4 and effective >= 1.5
                           else "low"),
            "method": "pooled-trust",
        }
        result["spread"] = {
            # Typical distance of one charge from the result, in SoH points.
            "perChargePct": round(scatter, 1),
            # How far the result itself may be off.
            "uncertaintyPct": round(uncertainty, 1),
            "lowPct": round(middle - uncertainty, 1),
            "highPct": round(middle + uncertainty, 1),
            # QA 164: with the charger efficiency's own doubt (87-93 %).
            "totalPct": round(math.hypot(uncertainty, middle * HEALTH_EFFICIENCY_SPREAD), 1),
        }
    elif health_log["months"]:
        # QA 164: nothing counted lately (no Shelly charge for months): the
        # latest months still say where the battery stood, marked stale.
        recent: list[dict] = []
        for bucket in reversed(health_log["months"]):
            recent.insert(0, bucket)
            if sum(int(b.get("charges") or 0) for b in recent) >= HEALTH_STALE_CHARGES:
                break
        stale = _pooled(recent)
        if stale:
            pooled_wh = stale["whPerPct"]
            middle = soh(_implied_capacity(pooled_wh, efficiency))
            uncertainty = _relative_error_pct(stale["scatter"], stale["effective"])
            result["estimate"] = {
                "sohPct": middle, "capacityWh": round(_implied_capacity(pooled_wh, efficiency)),
                "samples": stale["charges"], "effectiveCharges": round(stale["effective"], 1),
                "confidence": "low", "method": "monthly-log", "stale": True, "asOf": stale["to"],
            }
            result["spread"] = {
                "perChargePct": round(stale["scatter"] * 100, 1),
                "uncertaintyPct": round(uncertainty, 1),
                "lowPct": round(middle - uncertainty, 1),
                "highPct": round(middle + uncertainty, 1),
                "totalPct": round(math.hypot(uncertainty, middle * HEALTH_EFFICIENCY_SPREAD), 1),
            }
    current_error = None
    if result["spread"] and result["estimate"]:
        current_error = result["spread"]["uncertaintyPct"] / max(result["estimate"]["sohPct"], 1) * 100
    result["tracking"] = health_tracking(health_log, pooled_wh, current_error, nominal, efficiency)
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
    tests = [item for item in exact
             if item.get("labelSource") == "taper_full"
             and float(item.get("startPct") or 100) <= HEALTH_TEST_MAX_START_PCT
             and _positive(item.get("energyWh"))]
    if tests:
        last = tests[-1]
        start = float(last["startPct"])
        capacity = float(last["energyWh"]) * efficiency / (100 - start) * 100
        result["test"] = {"sohPct": soh(capacity), "capacityWh": round(capacity),
                          "startPct": start, "energyWh": round(float(last["energyWh"])),
                          "at": last.get("at"), "sessionId": last.get("sessionId")}
    return result


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


def _health_rows(charges: list[dict], trusts: dict[str, str], efficiency: float,
                 soh, *, now: datetime | None, window: bool = True) -> list[dict]:
    """Each charge with its weight and why it is (not) part of the estimate."""
    dated = [_parse_at(item.get("at")) for item in charges]
    latest = now or max((at for at in dated if at is not None), default=None)
    rows: list[dict] = []
    for item, at in zip(charges, dated):
        start = float(item.get("startPct") or 0)
        energy = _positive(item.get("energyWh"))
        stored = _positive(item.get("whPerPct"))
        if item.get("actualEndPct") is None and stored and energy:
            end = start + energy / stored  # an older record without its end %
        else:
            end = float(item.get("actualEndPct") or 0)
        gain = end - start
        test = (item.get("labelSource") == "taper_full"
                and start <= HEALTH_TEST_MAX_START_PCT)
        trust = "high" if test else trusts.get(str(item.get("sessionId") or ""), "low")
        age = (latest - at).total_seconds() / 86400 if latest and at else 0.0
        value = (soh(_implied_capacity(energy / gain, efficiency))
                 if energy and gain > 0 else None)
        if item.get("censored") and item.get("labelSource") != "taper_full":
            reason = "censored"
        elif value is None or gain < HEALTH_MIN_GAIN_PCT:
            reason = "short"
        elif window and age > HEALTH_WINDOW_DAYS:
            reason = "old"
        else:
            reason = None
        weight = 0.0
        if reason is None:
            weight = gain * TRUST_WEIGHT[trust]
            if window:
                weight *= 0.5 ** (max(0.0, age) / HEALTH_HALF_LIFE_DAYS)
            if test and (age <= HEALTH_TEST_FRESH_DAYS or not window):
                weight *= HEALTH_TEST_BOOST
        rows.append({
            "weight": weight, "gain": gain, "energyWh": energy or 0.0, "soh": value, "at": at,
            "public": {"at": item.get("at"), "startPct": start, "endPct": end,
                       "sohPct": value, "trust": trust, "test": test,
                       "used": reason is None, "reason": reason},
        })
    if not window:
        _drop_outliers_nearby(rows)
        return rows
    # Only the latest charges count, then the ones far from the rest leave.
    eligible = [row for row in rows if row["public"]["used"]]
    for row in eligible[:-HEALTH_WINDOW_CHARGES]:
        row["public"].update(used=False, reason="old")
        row["weight"] = 0.0
    eligible = eligible[-HEALTH_WINDOW_CHARGES:]
    if len(eligible) >= 3:
        middle = _weighted_median([(row["soh"], row["weight"]) for row in eligible])
        mad = _weighted_median([(abs(row["soh"] - middle), row["weight"]) for row in eligible])
        limit = max(3 * 1.4826 * mad, HEALTH_OUTLIER_FLOOR_PCT)
        for row in eligible:
            if abs(row["soh"] - middle) > limit:
                row["public"].update(used=False, reason="outlier")
                row["dropped"] = row["weight"]
                row["weight"] = 0.0
    return rows


def _drop_outliers_nearby(rows: list[dict]) -> None:
    """QA 164: over a battery's life the capacity moves, so a charge is
    compared with the charges around it (not with every charge ever)."""
    eligible = [row for row in rows if row["public"]["used"]]
    flags = []
    for index, row in enumerate(eligible):
        near = eligible[max(0, index - HEALTH_NEIGHBOURS): index + HEALTH_NEIGHBOURS + 1]
        if len(near) < 3:
            flags.append(False)
            continue
        middle = _weighted_median([(item["soh"], item["weight"]) for item in near])
        mad = _weighted_median([(abs(item["soh"] - middle), item["weight"]) for item in near])
        flags.append(abs(row["soh"] - middle) > max(3 * 1.4826 * mad, HEALTH_OUTLIER_FLOOR_PCT))
    for row, far in zip(eligible, flags):
        if far:
            row["public"].update(used=False, reason="outlier")
            row["dropped"] = row["weight"]
            row["weight"] = 0.0


def _month_key(at: datetime | None) -> str | None:
    return None if at is None else at.astimezone(timezone.utc).strftime("%Y-%m")


def _bucket(rows: list[dict]) -> dict | None:
    """Sums that pool across months: Wh/% = sumWE / sumWG, and the scatter of
    single charges in Wh/% (efficiency-free) from sumWV and sumWV2."""
    used = [row for row in rows if row["weight"] > 0]
    if not used:
        return None
    values = [(row["weight"], row["energyWh"] / row["gain"]) for row in used]
    ats = [row["at"] for row in used if row["at"] is not None]
    return {
        "sumW": round(sum(w for w, _ in values), 4),
        "sumW2": round(sum(w * w for w, _ in values), 4),
        "sumWE": round(sum(row["weight"] * row["energyWh"] for row in used), 3),
        "sumWG": round(sum(row["weight"] * row["gain"] for row in used), 4),
        "sumWV": round(sum(w * v for w, v in values), 4),
        "sumWV2": round(sum(w * v * v for w, v in values), 4),
        "charges": len(used),
        "dropped": sum(1 for row in rows if row.get("dropped")),
        "firstAt": min(ats).isoformat() if ats else None,
        "lastAt": max(ats).isoformat() if ats else None,
    }


def _pooled(buckets: list[dict]) -> dict | None:
    """Several buckets as one: Wh/%, charges, effective charges, the relative
    scatter of one charge (0.03 = 3 %) and the span in days."""
    buckets = [b for b in buckets if b and float(b.get("sumWG") or 0) > 0 and float(b.get("sumW") or 0) > 0]
    if not buckets:
        return None
    total = {key: sum(float(b.get(key) or 0) for b in buckets)
             for key in ("sumW", "sumW2", "sumWE", "sumWG", "sumWV", "sumWV2")}
    wh = total["sumWE"] / total["sumWG"]
    mean = total["sumWV"] / total["sumW"]
    variance = max(0.0, total["sumWV2"] / total["sumW"] - mean * mean)
    firsts = [at for at in (_parse_at(b.get("firstAt")) for b in buckets) if at]
    lasts = [at for at in (_parse_at(b.get("lastAt")) for b in buckets) if at]
    span = (max(lasts) - min(firsts)).total_seconds() / 86400 if firsts and lasts else 0.0
    return {"whPerPct": wh, "charges": int(sum(int(b.get("charges") or 0) for b in buckets)),
            "effective": total["sumW"] ** 2 / total["sumW2"] if total["sumW2"] else 0.0,
            "scatter": math.sqrt(variance) / mean if mean else 0.0,
            "from": min(firsts).isoformat() if firsts else None,
            "to": max(lasts).isoformat() if lasts else None, "days": span}


def update_health_log(log: dict | None, charges: list[dict], *,
                      complete: bool = True, now: datetime | None = None) -> dict:
    """QA 164: the monthly log of battery health, rebuilt for every month the
    charges cover and kept for the months they no longer do. ``complete`` is
    False when the oldest charges have already left the list: the oldest
    month there is then partial, and a stored one is kept. The reference is
    set once (enough counted charges over enough days) and never replaced."""
    stored = dict(log) if isinstance(log, dict) else {}
    months = {str(m.get("month")): dict(m) for m in (stored.get("months") or [])
              if isinstance(m, dict) and m.get("month")}
    ordered = sorted(charges, key=lambda item: str(item.get("at") or ""))
    trusts = _health_trusts(ordered)
    typical = _median([float(item["energyWh"]) / _gain(item) for item in ordered
                       if _positive(item.get("energyWh")) and _gain(item) >= HEALTH_MIN_GAIN_PCT])
    scale = _implied_capacity(typical, DEFAULT_EFFICIENCY) if typical else None
    rows = (_health_rows(ordered, trusts, DEFAULT_EFFICIENCY,
                         lambda capacity: capacity / scale * 100, now=None, window=False)
            if ordered and scale else [])
    grouped: dict[str, list[dict]] = {}
    for row in rows:
        key = _month_key(row["at"])
        if key:
            grouped.setdefault(key, []).append(row)
    oldest = min(grouped) if grouped else None
    for key, month_rows in grouped.items():
        if key == oldest and not complete and key in months:
            continue
        bucket = _bucket(month_rows)
        if bucket is None:
            months.pop(key, None)
        else:
            months[key] = {"month": key, **bucket}
    kept = [months[key] for key in sorted(months)][-HEALTH_LOG_MONTHS:]
    reference = stored.get("reference") if isinstance(stored.get("reference"), dict) else None
    if reference is None:
        running: list[dict] = []
        for bucket in kept:
            running.append(bucket)
            pooled = _pooled(running)
            if (pooled and pooled["charges"] >= HEALTH_REFERENCE_CHARGES
                    and pooled["days"] >= HEALTH_REFERENCE_DAYS):
                reference = {"whPerPct": round(pooled["whPerPct"], 4),
                             "charges": pooled["charges"],
                             "effective": round(pooled["effective"], 2),
                             "scatter": round(pooled["scatter"], 4),
                             "from": pooled["from"], "to": pooled["to"],
                             "months": [b["month"] for b in running],
                             "fixedAt": (now or datetime.now(timezone.utc)).isoformat()}
                break
    return {"version": 1, "months": kept, "reference": reference}


def _relative_error_pct(scatter: float, effective: float) -> float:
    """How far a pooled Wh/% may be off, in % of itself."""
    per_charge = max(scatter * 100, HEALTH_CHARGE_SCATTER_PCT)
    return math.sqrt((per_charge / math.sqrt(max(effective, 1.0))) ** 2 + HEALTH_READING_FLOOR_PCT ** 2)


def health_tracking(log: dict, current_wh_per_pct: float | None, current_error_pct: float | None,
                    nominal: float, efficiency: float) -> dict:
    """The battery against its own start, and its months (QA 164)."""
    reference = log.get("reference")
    months = log.get("months") or []
    if not reference:
        pooled = _pooled(months)
        charges = pooled["charges"] if pooled else 0
        days = pooled["days"] if pooled else 0.0
        return {"status": "building",
                "needCharges": max(0, HEALTH_REFERENCE_CHARGES - charges),
                "needDays": max(0, int(math.ceil(HEALTH_REFERENCE_DAYS - days))),
                "charges": charges, "monthly": []}
    base = float(reference["whPerPct"])
    base_error = _relative_error_pct(float(reference.get("scatter") or 0),
                                     float(reference.get("effective") or 1))
    result = {"status": "ready", "since": reference.get("from"), "until": reference.get("to"),
              "referenceCharges": reference.get("charges"),
              "referenceCapacityPct": round(_implied_capacity(base, efficiency) / nominal * 100, 1),
              "relativePct": None, "uncertaintyPct": None, "lowPct": None, "highPct": None}
    if current_wh_per_pct:
        relative = current_wh_per_pct / base * 100
        error = math.sqrt((current_error_pct or HEALTH_CHARGE_SCATTER_PCT) ** 2 + base_error ** 2)
        result.update(relativePct=round(relative, 1), uncertaintyPct=round(error, 1),
                      lowPct=round(relative - error, 1), highPct=round(relative + error, 1))
    monthly = []
    for bucket in months[-60:]:
        pooled = _pooled([bucket])
        if not pooled:
            continue
        monthly.append({"month": bucket["month"], "charges": pooled["charges"],
                        "relativePct": round(pooled["whPerPct"] / base * 100, 1),
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
    rates = [abs(float(item["driftPct"])) / float(item["fulls"]) for item in drift_log
             if item.get("driftPct") is not None and float(item.get("fulls") or 0) >= 0.3]
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
