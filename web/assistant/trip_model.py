"""Trip battery-use model (Tasks 126-127), shared by BatteryBot and the app.

The scooter reports no live battery data. Battery use per km is a small
regression fitted on the owner's own rides (``trip3.csv``: 77 rides, 444 km,
04/2026, Feliz, Hanoi; leave-one-day-out MAE 0.73 % vs 0.85 % for a flat
km/%, -27 % error on 10-20 km rides)::

    %/km = ref * (1 + speed*(v-20) + speed2*(v-20)^2 + load*(kg-65)/10 + rain)

``v`` is the ride's average speed including stops (km/h), ``kg`` rider +
passenger + cargo. Riding faster than ~20 km/h costs more (x1.10 at 25,
x1.28 at 30 km/h), a second rider ~+19 %, rain ~+6 %. Cold and hills are not
in the data and stay physics priors.

``ref`` (%/km at 20 km/h, solo, dry) comes from, best first: the owner's
trained trip model, km/% learned from odometer readings, or the catalog. The
latter two are averages over mixed riding, which the fit puts at
``1 / REF_TO_MEAN`` x the reference conditions. Training (owner presses
"Huấn luyện") is a ridge regression shrunk towards the prior, promoted only if
cross-validated error does not get worse. Everything is an estimate with a
range, never a promise. The Dart twin is
``app/lib/data/services/trip_energy_model.dart``; both are checked against
``web/tests/fixtures/trip_model_vectors.json``.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

# BMS cuts power before 0 % (same as range_estimator.dart).
RESERVE_PCT = 5.0
# Arriving with at least this much is "comfortable".
COMFORT_PCT = 20.0
# Shape fitted on the owner's 77 rides (relative to the reference %/km).
PRIOR_SPEED = 0.01221
PRIOR_SPEED2 = 0.001614
PRIOR_LOAD_PER_10KG = 0.03077
PRIOR_RAIN = 0.05741
# Reference conditions / mixed riding (%/km at 20 km/h solo dry is 0.882 of
# the distance-weighted average over the owner's rides).
REF_TO_MEAN = 0.882
REF_SPEED_KMH = 20.0
RIDER_KG = 65.0
SECOND_RIDER_KG = 62.0
MAX_CARGO_KG = 60.0
SPEED_PRESETS_KMH = {"slow": 15.0, "normal": 21.0, "fast": 28.0}
SPEED_RANGE_KMH = (8.0, 34.0)
# Router durations are for cars; the owner's real scooter averages (with
# stops) are about three quarters of that in town.
ROUTER_TO_SCOOTER = 0.75
# Not in the owner's data: physics priors.
WEATHER_EXTRA = {"dry": 1.0, "rain": 1.0, "hot": 1.0, "cold": 1.10}
HILLY_FACTOR = 1.12
SHAPE_BAND = (0.6, 2.0)
# Relative ~80 % band: owner's rides >= 5 km had |error| p80 ~ 0.2.
MODEL_SPREAD = 0.18
ODO_SPREAD = 0.18
CATALOG_SPREAD = 0.25
SPREAD_BAND = (0.08, 0.30)
MIN_PAIRS = 2
# A learned km/% outside these bounds (x catalog) is a typo, not a scooter.
KM_PER_PCT_BAND = (0.4, 2.5)
# Training (Task 127).
TRIP_TRAINING_MIN_NEW = 10
TRIP_TRAINING_MIN_SAMPLES = 10
# Prior strength (ridge lambda = noise^2 / prior variance, noise ~1 %):
# reference %/km +-0.1, speed +-0.005/(km/h), speed^2 +-0.0006, load
# +-0.012/10 kg, rain +-0.05 (absolute %/km units).
PRIOR_LAMBDA = (100.0, 40000.0, 2.8e6, 7000.0, 400.0)
# Rides without known conditions (odometer segments) use typical values.
TYPICAL_SPEED_KMH = 20.0
TYPICAL_LOAD_KG = 86.0


@dataclass(frozen=True)
class TripConditions:
    speed: str = "normal"  # slow | normal | fast | auto
    riders: int = 1
    cargo_kg: float = 0.0
    weather: str = "dry"  # dry | rain | hot | cold
    hilly: bool = False
    round_trip: bool = False


@dataclass(frozen=True)
class TripModelParams:
    """Absolute reference %/km plus relative shape coefficients."""
    ref_pct_per_km: float
    speed: float = PRIOR_SPEED
    speed2: float = PRIOR_SPEED2
    load_per_10kg: float = PRIOR_LOAD_PER_10KG
    rain: float = PRIOR_RAIN
    source: str = "catalog"  # model | odo | catalog
    samples: int = 0
    spread: float = CATALOG_SPREAD
    mae: float | None = None

    @property
    def km_per_pct(self) -> float:
        """Mixed-riding km per 1 % (what the catalog and odometer measure)."""
        return REF_TO_MEAN / self.ref_pct_per_km

    def to_dict(self) -> dict:
        return {"refPctPerKm": round(self.ref_pct_per_km, 5), "speed": round(self.speed, 6),
                "speed2": round(self.speed2, 7), "loadPer10Kg": round(self.load_per_10kg, 5),
                "rain": round(self.rain, 5), "source": self.source, "samples": self.samples,
                "spread": round(self.spread, 3), "mae": self.mae}

    @classmethod
    def from_dict(cls, data: dict | None) -> "TripModelParams | None":
        if not isinstance(data, dict):
            return None
        ref = _number(data.get("refPctPerKm"))
        if ref is None or not 0.05 <= ref <= 5:
            return None
        return cls(
            ref_pct_per_km=ref,
            speed=_number(data.get("speed"), PRIOR_SPEED),
            speed2=_number(data.get("speed2"), PRIOR_SPEED2),
            load_per_10kg=_number(data.get("loadPer10Kg"), PRIOR_LOAD_PER_10KG),
            rain=_number(data.get("rain"), PRIOR_RAIN),
            source=str(data.get("source") or "model"),
            samples=int(_number(data.get("samples"), 0) or 0),
            spread=min(SPREAD_BAND[1], max(SPREAD_BAND[0], _number(data.get("spread"), MODEL_SPREAD))),
            mae=_number(data.get("mae")),
        )


def params_from_km_per_pct(km_per_pct: float, source: str) -> TripModelParams:
    """Prior shape on a mixed-riding km/% (catalog or odometer)."""
    spread = ODO_SPREAD if source in ("odo", "personal") else CATALOG_SPREAD
    return TripModelParams(ref_pct_per_km=REF_TO_MEAN / km_per_pct,
                           source="odo" if source in ("odo", "personal") else "catalog",
                           spread=spread)


@dataclass(frozen=True)
class TripPlan:
    distance_km: float
    use_pct: float
    use_low_pct: float
    use_high_pct: float
    arrival_soc: float
    arrival_low_soc: float
    verdict: str  # comfortable | tight | insufficient
    km_per_pct: float
    km_per_pct_source: str  # model | odo | catalog
    factor: float
    start_needed_soc: float
    avg_speed_kmh: float
    payload_kg: float
    suggestions: list[dict] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "distanceKm": round(self.distance_km, 1),
            "usePct": round(self.use_pct, 1),
            "useLowPct": round(self.use_low_pct, 1),
            "useHighPct": round(self.use_high_pct, 1),
            "arrivalSoc": round(self.arrival_soc, 1),
            "arrivalLowSoc": round(self.arrival_low_soc, 1),
            "verdict": self.verdict,
            "kmPerPct": round(self.km_per_pct, 3),
            "kmPerPctSource": self.km_per_pct_source,
            "factor": round(self.factor, 3),
            "startNeededSoc": round(self.start_needed_soc, 1),
            "avgSpeedKmh": round(self.avg_speed_kmh, 1),
            "payloadKg": round(self.payload_kg),
            "suggestions": self.suggestions,
        }


def average_speed(conditions: TripConditions, distance_km: float, duration_min: float | None) -> float:
    """Expected ride average speed incl. stops (km/h)."""
    if conditions.speed in SPEED_PRESETS_KMH:
        return SPEED_PRESETS_KMH[conditions.speed]
    if conditions.speed != "auto" or not duration_min or duration_min <= 0 or distance_km <= 0:
        return SPEED_PRESETS_KMH["normal"]
    value = distance_km / (duration_min / 60) * ROUTER_TO_SCOOTER
    return min(SPEED_RANGE_KMH[1], max(SPEED_RANGE_KMH[0], value))


def payload_kg(conditions: TripConditions) -> float:
    riders = 2 if conditions.riders >= 2 else 1
    cargo = max(0.0, min(MAX_CARGO_KG, float(conditions.cargo_kg or 0)))
    return RIDER_KG + (riders - 1) * SECOND_RIDER_KG + cargo


def shape(params: TripModelParams, *, speed_kmh: float, load_kg: float, rain: bool) -> float:
    v = min(SPEED_RANGE_KMH[1], max(SPEED_RANGE_KMH[0], float(speed_kmh))) - REF_SPEED_KMH
    load = (min(250.0, max(40.0, float(load_kg))) - RIDER_KG) / 10
    value = 1 + params.speed * v + params.speed2 * v * v + params.load_per_10kg * load
    if rain:
        value += params.rain
    return min(SHAPE_BAND[1], max(SHAPE_BAND[0], value))


def condition_factor(conditions: TripConditions, distance_km: float = 0,
                     duration_min: float | None = None,
                     params: TripModelParams | None = None) -> float:
    """Multiplier on the reference %/km for these conditions."""
    params = params or TripModelParams(ref_pct_per_km=1.0)
    factor = shape(params, speed_kmh=average_speed(conditions, distance_km, duration_min),
                   load_kg=payload_kg(conditions), rain=conditions.weather == "rain")
    factor *= WEATHER_EXTRA.get(conditions.weather, 1.0)
    if conditions.hilly:
        factor *= HILLY_FACTOR
    return factor


def catalog_km_per_pct(efficiency_km_per_pct: float | None, soh_pct: float | None) -> float | None:
    if efficiency_km_per_pct is None or efficiency_km_per_pct <= 0:
        return None
    soh = soh_pct if soh_pct is not None and 0 < soh_pct <= 100 else 100.0
    return efficiency_km_per_pct * soh / 100


def learned_km_per_pct(sessions: list[dict], catalog: float | None) -> tuple[float | None, int]:
    """Median km per 1 % between consecutive confirmed charges.

    ``sessions`` items: ``{endedAt, startSoc, actualEndSoc, odoKm}``. Between
    charge N and N+1 the scooter rode ``odo[N+1] - odo[N]`` km and used
    ``actualEnd[N] - start[N+1]`` %.
    """
    rows = sorted((item for item in sessions
                   if item.get("odoKm") is not None and item.get("actualEndSoc") is not None),
                  key=lambda item: str(item.get("endedAt") or ""))
    values = []
    for before, after in zip(rows, rows[1:]):
        km = float(after["odoKm"]) - float(before["odoKm"])
        used = float(before["actualEndSoc"]) - float(after.get("startSoc") or 0)
        if km <= 0 or used < 5:
            continue
        value = km / used
        if catalog and not catalog * KM_PER_PCT_BAND[0] <= value <= catalog * KM_PER_PCT_BAND[1]:
            continue
        values.append(value)
    if len(values) < MIN_PAIRS:
        return None, len(values)
    values.sort()
    middle = len(values) // 2
    median = values[middle] if len(values) % 2 else (values[middle - 1] + values[middle]) / 2
    return median, len(values)


def plan_trip(
    *,
    distance_km: float,
    current_soc: float,
    km_per_pct: float | None = None,
    km_per_pct_source: str = "catalog",
    conditions: TripConditions = TripConditions(),
    duration_min: float | None = None,
    alternative_km: list[float] | None = None,
    model: TripModelParams | None = None,
) -> TripPlan:
    if model is None:
        if not km_per_pct or km_per_pct <= 0:
            raise ValueError("km_per_pct or model required")
        model = params_from_km_per_pct(km_per_pct, km_per_pct_source)
    distance = max(0.0, float(distance_km))
    legs = 2 if conditions.round_trip else 1
    factor = condition_factor(conditions, distance, duration_min, model)

    def use_for(km: float, cond: TripConditions) -> float:
        return km * legs * model.ref_pct_per_km * condition_factor(cond, km, duration_min, model)

    use = distance * legs * model.ref_pct_per_km * factor
    spread = model.spread
    low, high = use * (1 - spread), use * (1 + spread)
    soc = max(0.0, min(100.0, float(current_soc)))
    arrival, arrival_low = soc - use, soc - high
    if arrival_low >= COMFORT_PCT:
        verdict = "comfortable"
    elif arrival_low >= RESERVE_PCT:
        verdict = "tight"
    else:
        verdict = "insufficient"
    needed = high + COMFORT_PCT
    suggestions: list[dict] = []
    if verdict != "comfortable":
        if needed <= 100:
            if needed > soc:
                suggestions.append({"kind": "charge_first",
                                    "targetSoc": min(100, math.ceil(needed / 5) * 5)})
        else:
            stops = math.ceil((high - (100 - COMFORT_PCT)) / (100 - COMFORT_PCT - RESERVE_PCT))
            suggestions.append({"kind": "charge_on_the_way", "stops": max(1, stops)})
        if conditions.round_trip and soc - high / 2 >= RESERVE_PCT:
            suggestions.append({"kind": "charge_at_destination"})
        speed = average_speed(conditions, distance, duration_min)
        # The owner's rides cost least around 15-20 km/h average.
        if speed > SPEED_PRESETS_KMH["normal"] + 0.5:
            eco = TripConditions(**{**conditions.__dict__, "speed": "normal"})
            saved = use - use_for(distance, eco)
            if saved >= 1:
                suggestions.append({"kind": "ride_eco", "savedPct": round(saved, 1)})
    if alternative_km:
        shortest = min(alternative_km)
        if shortest < distance - 0.5:
            saved = (distance - shortest) * legs * model.ref_pct_per_km * factor
            suggestions.append({"kind": "shorter_route", "distanceKm": round(shortest, 1),
                                "savedPct": round(saved, 1)})
    return TripPlan(
        distance_km=distance, use_pct=use, use_low_pct=low, use_high_pct=high,
        arrival_soc=arrival, arrival_low_soc=arrival_low, verdict=verdict,
        km_per_pct=model.km_per_pct, km_per_pct_source=model.source, factor=factor,
        start_needed_soc=min(100.0, needed),
        avg_speed_kmh=average_speed(conditions, distance, duration_min),
        payload_kg=payload_kg(conditions), suggestions=suggestions,
    )


# -- samples & training (Task 127) -------------------------------------------

def normalize_sample(raw: dict) -> dict | None:
    """Validate one ride; ``None`` when it cannot teach the model anything.

    Accepts the app's fields and the owner's CSV columns (``distance_km``,
    ``duration_min``, ``avg_speed_kmh``, ``payload_kg``, ``weather_condition``,
    ``start_soc``, ``end_soc``, ``soc_delta``).
    """
    def pick(*names):
        for name in names:
            if raw.get(name) not in (None, ""):
                return raw.get(name)
        return None

    distance = _number(pick("distanceKm", "distance_km"))
    if distance is None or not 0.3 <= distance <= 300:
        return None
    start, end = _number(pick("startSoc", "start_soc")), _number(pick("endSoc", "end_soc"))
    used = _number(pick("socUsed", "soc_delta"))
    if used is None and start is not None and end is not None:
        used = start - end
    if used is None or not 0 <= used <= 100:
        return None
    if start is not None and not 0 <= start <= 100 or end is not None and not 0 <= end <= 100:
        return None
    per_km = used / distance
    # Dashboard % is whole numbers: a short ride may read 0 or 2 %.
    if not (0.1 <= per_km <= 4.0 or (used <= 2 and distance < 4)):
        return None
    duration = _number(pick("durationMin", "duration_min"))
    if duration is not None and not 1 <= duration <= 1440:
        duration = None
    speed = _number(pick("avgSpeedKmh", "avg_speed_kmh"))
    if speed is None and duration:
        speed = distance / (duration / 60)
    if speed is not None and not 3 <= speed <= 90:
        speed = None
    payload = _number(pick("payloadKg", "payload_kg"))
    if payload is not None and not 40 <= payload <= 250:
        payload = None
    weather = str(pick("weather", "weather_condition") or "").strip().lower()
    rain = weather in ("rain", "rainy", "mưa", "drizzle", "thunderstorm")
    known = speed is not None
    return {
        "distanceKm": round(distance, 3), "socUsed": round(used, 2),
        "startSoc": start, "endSoc": end, "durationMin": duration,
        "avgSpeedKmh": round(speed, 2) if speed is not None else None,
        "payloadKg": payload, "rain": rain, "conditionsKnown": known,
        "tempC": _number(pick("tempC", "ambient_temp_c")),
    }


def _features(sample: dict) -> list[float]:
    d = float(sample["distanceKm"])
    v = sample.get("avgSpeedKmh")
    v = TYPICAL_SPEED_KMH if v is None else min(SPEED_RANGE_KMH[1], max(SPEED_RANGE_KMH[0], float(v)))
    v -= REF_SPEED_KMH
    kg = sample.get("payloadKg")
    load = ((TYPICAL_LOAD_KG if kg is None else float(kg)) - RIDER_KG) / 10
    return [d, d * v, d * v * v, d * load, d * (1.0 if sample.get("rain") else 0.0)]


def predict_use(params: TripModelParams, sample: dict) -> float:
    """% used for one recorded ride under ``params``."""
    a = _absolute(params)
    return sum(x * c for x, c in zip(_features(sample), a))


def _absolute(params: TripModelParams) -> list[float]:
    ref = params.ref_pct_per_km
    return [ref, ref * params.speed, ref * params.speed2, ref * params.load_per_10kg, ref * params.rain]


def _from_absolute(theta: list[float], **extra) -> TripModelParams:
    ref = max(0.05, theta[0])
    return TripModelParams(ref_pct_per_km=ref, speed=theta[1] / ref, speed2=theta[2] / ref,
                           load_per_10kg=theta[3] / ref, rain=theta[4] / ref, **extra)


def _ridge(samples: list[dict], prior: list[float]) -> list[float]:
    n = len(prior)
    a = [[PRIOR_LAMBDA[i] if i == j else 0.0 for j in range(n)] for i in range(n)]
    b = [PRIOR_LAMBDA[i] * prior[i] for i in range(n)]
    for sample in samples:
        x = _features(sample)
        y = float(sample["socUsed"])
        for i in range(n):
            b[i] += x[i] * y
            for j in range(n):
                a[i][j] += x[i] * x[j]
    return _solve(a, b)


def _solve(a: list[list[float]], b: list[float]) -> list[float]:
    """Gaussian elimination with partial pivoting (5x5, no numpy needed)."""
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(m[r][col]))
        m[col], m[pivot] = m[pivot], m[col]
        if abs(m[col][col]) < 1e-12:
            continue
        for r in range(n):
            if r != col:
                f = m[r][col] / m[col][col]
                for c in range(col, n + 1):
                    m[r][c] -= f * m[col][c]
    return [m[i][n] / m[i][i] if abs(m[i][i]) > 1e-12 else 0.0 for i in range(n)]


def trip_training_status(samples: list[dict], trained_ids: set[str] | None = None) -> dict:
    trained_ids = trained_ids or set()
    pending = [item for item in samples if str(item.get("id")) not in trained_ids]
    total = len(samples)
    required = TRIP_TRAINING_MIN_NEW if trained_ids else TRIP_TRAINING_MIN_SAMPLES
    return {"pending": len(pending), "required": required, "trained": total - len(pending),
            "ready": len(pending) >= required, "pendingKm": round(sum(float(i["distanceKm"]) for i in pending), 1)}


def error_stats(pairs: list[tuple[float, float]]) -> dict:
    """MAE, bias and hit rates for (predicted, actual) pairs in %."""
    if not pairs:
        return {"n": 0, "mae": None, "bias": None, "within1": None, "within2": None}
    errors = [predicted - actual for predicted, actual in pairs]
    n = len(errors)
    return {
        "n": n,
        "mae": round(sum(abs(e) for e in errors) / n, 2),
        "bias": round(sum(errors) / n, 2),
        "within1": round(sum(abs(e) <= 1 for e in errors) / n, 3),
        "within2": round(sum(abs(e) <= 2 for e in errors) / n, 3),
    }


def _flat(rows: list[dict]) -> TripModelParams:
    km = sum(float(item["distanceKm"]) for item in rows)
    used = sum(float(item["socUsed"]) for item in rows)
    ref = used / km if km > 0 and used > 0 else 0.8
    return TripModelParams(ref_pct_per_km=ref, speed=0, speed2=0, load_per_10kg=0, rain=0,
                           source="flat")


def train_trip_model(samples: list[dict], current: TripModelParams, *, mode: str = "finetune",
                     trained_ids: set[str] | None = None) -> tuple[TripModelParams, dict]:
    """Fit on every stored ride and report an objective comparison.

    ``finetune`` shrinks towards ``current``; ``retrain`` towards the prior
    shape on ``current``'s mixed-riding km/% (forgets earlier training).

    Evaluation (Task 127): the new model is judged on rides it did not see —
    5 time-ordered folds, each predicted by a fit on the other four. On the
    same rides the report also scores the model in use now and a flat km/%
    baseline. The test set is the new (not yet trained) rides when there are
    at least 5, else every ride (then the model in use may have seen them,
    which favours it; ``currentSawTest`` says so). The new model is used only
    if its error is not worse than the current one's.
    """
    rows = sorted((item for item in samples
                   if item.get("distanceKm") and item.get("socUsed") is not None),
                  key=lambda item: str(item.get("at") or ""))
    if len(rows) < 3:
        return current, {"decision": "no_data", "used": len(rows), "mode": mode}
    trained_ids = trained_ids or set()
    # (slack for an in-sample current model is applied below)
    anchor = current if mode != "retrain" else params_from_km_per_pct(current.km_per_pct, "odo")
    prior = _absolute(anchor)
    theta = _ridge(rows, prior)
    folds = min(5, len(rows))
    out_of_fold: dict[int, tuple[float, float]] = {}
    for fold in range(folds):
        test_idx = [i for i in range(len(rows)) if i * folds // len(rows) == fold]
        train = [rows[i] for i in range(len(rows)) if i not in test_idx]
        fit = _from_absolute(_ridge(train, prior))
        flat = _flat(train)
        for i in test_idx:
            out_of_fold[i] = (predict_use(fit, rows[i]), predict_use(flat, rows[i]))
    fresh = [i for i, item in enumerate(rows) if str(item.get("id")) not in trained_ids]
    test = fresh if len(fresh) >= 5 else list(range(len(rows)))
    current_saw = any(str(rows[i].get("id")) in trained_ids for i in test)

    def actual(i):
        return float(rows[i]["socUsed"])

    current_stats = error_stats([(predict_use(current, rows[i]), actual(i)) for i in test])
    new_stats = error_stats([(out_of_fold[i][0], actual(i)) for i in test])
    flat_stats = error_stats([(out_of_fold[i][1], actual(i)) for i in test])
    rel = sorted(abs(out_of_fold[i][0] - actual(i)) / out_of_fold[i][0] for i in range(len(rows))
                 if float(rows[i]["distanceKm"]) >= 5 and out_of_fold[i][0] > 0)
    spread = rel[min(len(rel) - 1, int(math.ceil(0.8 * len(rel))) - 1)] if len(rel) >= 5 else MODEL_SPREAD
    candidate = _from_absolute(theta, source="model", samples=len(rows),
                               spread=min(SPREAD_BAND[1], max(SPREAD_BAND[0], spread)),
                               mae=new_stats["mae"])
    examples = [{
        "at": str(rows[i].get("at") or "")[:10],
        "km": round(float(rows[i]["distanceKm"]), 1),
        "speedKmh": None if rows[i].get("avgSpeedKmh") is None else round(float(rows[i]["avgSpeedKmh"])),
        "actual": round(actual(i), 1),
        "current": round(predict_use(current, rows[i]), 1),
        "new": round(out_of_fold[i][0], 1),
        "flat": round(out_of_fold[i][1], 1),
    } for i in test[-8:]]
    evaluation = {
        "method": "kiểm tra chéo 5 phần theo thời gian",
        "testSet": "new" if test is fresh else "all",
        "currentSawTest": current_saw,
        "current": current_stats, "new": new_stats, "flat": flat_stats,
        "examples": examples,
    }
    report = {"mode": "retrain" if mode == "retrain" else "finetune", "used": len(rows),
              "beforeMae": current_stats["mae"], "afterMae": new_stats["mae"],
              "kmPerPct": round(candidate.km_per_pct, 3), "evaluation": evaluation}
    # A model scored on rides it was trained on looks better than it is: give
    # the new model that much slack, but it must still beat a flat km/%.
    slack = 0.10 if current_saw else 0.01
    worse = (new_stats["mae"] is not None and current_stats["mae"] is not None
             and (new_stats["mae"] > current_stats["mae"] + slack
                  or (flat_stats["mae"] is not None and new_stats["mae"] >= flat_stats["mae"])))
    if not 0.1 <= candidate.ref_pct_per_km <= 3 or worse:
        return current, {**report, "decision": "rejected_worse", "kmPerPct": round(current.km_per_pct, 3)}
    return candidate, {**report, "decision": "promoted"}


def _number(value, default=None):
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    return number if math.isfinite(number) else default
