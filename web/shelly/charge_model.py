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
# New labelled charges needed before the app suggests training (Task 127).
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
        soc_mae=learned.soc_mae,
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
    sid = entry["sessionId"]
    # A user reading replaces an automatic one for the same charge.
    pending = [item for item in profile.pending if item.get("sessionId") != sid]
    samples = [item for item in profile.samples if item.get("sessionId") != sid]
    queued = LearnedProfile(**{**profile.__dict__, "samples": samples,
                               "pending": [*pending, entry][-MAX_PENDING_SAMPLES:]})
    return queued, "queued"


def training_status(profile: LearnedProfile) -> dict:
    """How much new data is waiting and whether training is worth offering."""
    required = TRAINING_MIN_NEW_SAMPLES if profile.wh_per_pct else FIRST_TRAINING_MIN_SAMPLES
    pending = len(profile.pending)
    return {
        "pending": pending,
        "required": required,
        "ready": pending >= required,
        "trained": len(profile.samples),
        "mae": profile.soc_mae,
        "trainedAt": profile.trained_at,
        "version": profile.version,
    }


def train(
    profile: LearnedProfile,
    *,
    base_wh_per_pct: float | None,
    now: datetime | None = None,
    mode: str = "finetune",
) -> tuple[LearnedProfile, dict]:
    """Fit the profile on stored + pending charges (owner pressed train).

    ``finetune``: recency-weighted and kept only if not worse than the current
    estimate on the data. ``retrain``: every stored charge weighs the same and
    power/taper are re-learned from all of them; the same guard refuses a
    clearly worse result. Pending charges always move into the stored set so
    the data is never lost.
    """
    now = now or datetime.now(timezone.utc)
    retrain = mode == "retrain"
    merged: dict[str, dict] = {}
    for index, item in enumerate([*profile.samples, *profile.pending]):
        merged[str(item.get("sessionId") or f"_{index}")] = item
    samples = list(merged.values())[-MAX_PROFILE_SAMPLES:]
    weigh_now = None if retrain else now
    candidate_wh = _robust_wh(samples, base_wh_per_pct, weigh_now)
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
    )
    candidate.soc_mae = _loo_mae(samples, base_wh_per_pct, weigh_now)
    evaluation = _evaluate(samples, profile, base_wh_per_pct, weigh_now)
    after = evaluation["new"]["mae"]
    before = evaluation["current"]["mae"]
    report = {"mode": "retrain" if retrain else "finetune", "used": len(samples),
              "added": len(profile.pending), "beforeMae": before,
              "afterMae": after, "whPerPct": candidate.wh_per_pct,
              "evaluation": evaluation}
    if (before is not None and after is not None and profile.wh_per_pct
            and after > before + 0.5):
        # Keep the proven estimate; the new charges stay stored for later.
        kept = LearnedProfile(**{**profile.__dict__, "samples": samples, "pending": [],
                                 "trained_at": now.isoformat()})
        return kept, {**report, "decision": "rejected_worse", "whPerPct": profile.wh_per_pct,
                      "afterMae": _round2(before)}
    return candidate, {**report, "decision": "promoted" if candidate.wh_per_pct else "no_data"}


def _evaluate(samples: list[dict], profile: LearnedProfile, base: float | None,
              now: datetime | None) -> dict:
    """Objective comparison on labelled charges (Task 127).

    Each charge's end % is predicted from its energy by: the model in use now,
    the new model fitted WITHOUT that charge (leave-one-out) and the catalog
    default. New (pending) charges are the test set when there are any, so the
    model in use has not seen them; otherwise every stored charge is used.
    Charges that ended at 100 % without the full-battery signal only bound the
    value and are listed but not scored.
    """
    pending_ids = {str(item.get("sessionId")) for item in profile.pending}
    scored = [item for item in samples if not item.get("censored")]
    fresh = [item for item in scored if str(item.get("sessionId")) in pending_ids]
    test = fresh or scored
    rows = []
    pairs = {"current": [], "new": [], "base": []}
    for item in samples:
        others = [other for other in samples if other is not item]
        loo_wh = _robust_wh(others, base, now) if others else None
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


def _robust_wh(samples: list[dict], base: float | None, now: datetime | None) -> float | None:
    """Recency-weighted median, shrunk towards the catalog default.

    Samples ending at 100 % are censored: the battery may have filled before
    the session ended, so they only bound the value from above.
    """
    exact = [item for item in samples if not item.get("censored")]
    pairs = [(float(item["whPerPct"]), _weight(item, now)) for item in exact]
    if base:
        pairs.append((base, 0.5))  # prior worth half a fresh sample
    value = _weighted_median(pairs)
    for item in samples:
        if item.get("censored") and value is not None:
            value = min(value, float(item["whPerPct"]))
    if value is None:
        bounds = [float(item["whPerPct"]) for item in samples if item.get("censored")]
        value = min(bounds) if bounds else None
    return value


def _loo_mae(samples: list[dict], base: float | None, now: datetime | None) -> float | None:
    errors = []
    for index, item in enumerate(samples):
        if item.get("censored"):
            continue
        others = samples[:index] + samples[index + 1:]
        wh = _robust_wh(others, base, now)
        if wh:
            errors.append(abs(_predicted_end(item, wh) - float(item["actualEndPct"])))
    return round(sum(errors) / len(errors), 2) if errors else None


def _mae_with(samples: list[dict], wh: float) -> float:
    errors = [abs(_predicted_end(item, wh) - float(item["actualEndPct"]))
              for item in samples if not item.get("censored")]
    return sum(errors) / len(errors) if errors else 0.0


def _predicted_end(item: dict, wh: float) -> float:
    return min(100.0, float(item["startPct"]) + float(item["energyWh"]) / wh)


def _weight(item: dict, now: datetime | None) -> float:
    if now is None:
        return 1.0  # retrain: every stored charge weighs the same
    try:
        at = datetime.fromisoformat(str(item.get("at")).replace("Z", "+00:00"))
        if at.tzinfo is None:
            at = at.replace(tzinfo=timezone.utc)
        age_days = max(0.0, (now - at).total_seconds() / 86400)
    except (TypeError, ValueError):
        age_days = 0.0
    return 0.5 ** (age_days / HALF_LIFE_DAYS)


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
