"""Layers on top of the learned Wh/% (QA 147): gauge offset, then a small model.

``charge_model`` answers "how many Wh per %". The scooter's gauge sometimes falls
behind the energy after a charge and catches up on the next one (owner's charges,
QA 146), which no single Wh/% can explain. Three layers predict the end %:

* ``base``: start + Wh / Wh-per-%.
* ``offset``: base + what the gauge still owed after the previous charge.
* ``ai``: base + a small ridge regression on what is known before a charge starts.

Every layer is an estimate. The owner's training selects one, and only a layer
that beat the simpler one on charges it had not seen. The model never decides
ON/OFF safety, the device timer stays, and a charge to 100 % still ends on the
charger's own full signal. Once a small model exists it is only fine-tuned.
``battery_health`` reads none of this.
"""

from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone

from . import charge_model
from .charge_model import LearnedProfile

# Project rule for personal AI (AGENTS 3.4): 30 validated samples over 14 days,
# at least 20 test samples, RMSE not worse by 3 %, bias not up. MAE must improve by
# 5 %, not the rule's 2 %: in simulation 2 % let the model win on pure noise in 7 of
# 80 runs, 5 % in none of them, and it still found a real pattern in 66 of 80.
AI_MIN_CHARGES = 30
AI_MIN_DAYS = 14.0
AI_MIN_TEST = 20
OFFSET_MIN_TEST = charge_model.SHADOW_MIN_CHARGES
WALK_MIN_TRAIN = 10
MAE_RATIO = 0.95
RMSE_RATIO = 1.03
BIAS_SLACK = 0.1
FINETUNE_MIN_UNSEEN = 3
FINETUNE_TOLERANCE = 0.2
DEMOTE_MARGIN = 0.5
# Few samples, few features, strong pull: towards zero for the first fit, towards
# the current weights when fine-tuning.
RIDGE_FIRST = 3.0
RIDGE_FINETUNE = 6.0
FEATURES = ("bias", "start", "gain", "offset", "partial", "gap")
MAX_CORRECTION_PCT = charge_model.MAX_GAUGE_OFFSET_PCT
MAX_CORRECTION_SHARE = 0.5
FULL_SUGGEST_AFTER = 5
FULL_END_PCT = charge_model.GAUGE_RESET_END_PCT


def _at(item: dict) -> datetime | None:
    try:
        parsed = datetime.fromisoformat(str(item.get("at")).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def charges(profile: LearnedProfile) -> list[dict]:
    """Every labelled charge once, oldest first."""
    dated = [(at, item) for item in charge_model.unique_charges(profile)
             if (at := _at(item)) is not None and item.get("energyWh")]
    return [item for _, item in sorted(dated, key=lambda pair: pair[0])]


def _vector(context: dict) -> list[float]:
    values = {
        "bias": 1.0,
        "start": context["start"] / 100,
        "gain": context["gain"] / 100,
        "offset": context["offset"] / MAX_CORRECTION_PCT,
        "partial": min(context["partial"], 10) / 10,
        "gap": min(context["gap"], 7.0) / 7,
    }
    return [values[name] for name in FEATURES]


def timeline(rows: list[dict], base: float | None) -> list[dict]:
    """Replay the charges in order: each one sees only what came before it."""
    steps: list[dict] = []
    offset, partial, previous = 0.0, 0, None
    for index, item in enumerate(rows):
        at = _at(item)
        wh = charge_model._robust_wh(rows[:index], base, at)
        if not wh:
            continue
        start, energy = float(item["startPct"]), float(item["energyWh"])
        actual = float(item["actualEndPct"])
        power = charge_model._positive(item.get("avgPowerW"))
        began = at - timedelta(hours=energy / power) if power else at
        gain = energy / wh
        steps.append({
            "item": item, "at": at, "actual": actual, "plain": start + gain,
            "residual": actual - (start + gain), "offset": offset,
            "scored": actual < FULL_END_PCT and not item.get("censored"),
            "x": _vector({"start": start, "gain": gain, "offset": offset, "partial": partial,
                          "gap": max(0.0, (began - previous).total_seconds() / 86400) if previous else 7.0}),
        })
        full = actual >= FULL_END_PCT
        partial = 0 if full else partial + 1
        offset = 0.0 if full else charge_model.gauge_offset_after(start, energy, wh, actual)
        previous = at
    return steps


def ridge(rows: list[list[float]], targets: list[float], *, weights: list[float] | None = None,
          prior: list[float] | None = None, strength: float = RIDGE_FIRST) -> list[float]:
    """Weighted ridge regression pulled towards ``prior`` (zeros by default)."""
    size = len(FEATURES)
    prior = prior or [0.0] * size
    weights = weights or [1.0] * len(rows)
    matrix = [[strength if a == b else 0.0 for b in range(size)] for a in range(size)]
    vector = [0.0] * size
    for x, y, weight in zip(rows, targets, weights):
        left = y - sum(p * v for p, v in zip(prior, x))
        for a in range(size):
            vector[a] += weight * x[a] * left
            for b in range(size):
                matrix[a][b] += weight * x[a] * x[b]
    return [p + d for p, d in zip(prior, _solve(matrix, vector))]


def _solve(matrix: list[list[float]], vector: list[float]) -> list[float]:
    size = len(vector)
    grid = [row[:] + [vector[index]] for index, row in enumerate(matrix)]
    for column in range(size):
        pivot = max(range(column, size), key=lambda row: abs(grid[row][column]))
        grid[column], grid[pivot] = grid[pivot], grid[column]
        if abs(grid[column][column]) < 1e-12:
            continue
        for row in range(size):
            if row == column:
                continue
            factor = grid[row][column] / grid[column][column]
            for index in range(column, size + 1):
                grid[row][index] -= factor * grid[column][index]
    return [grid[row][size] / grid[row][row] if abs(grid[row][row]) >= 1e-12 else 0.0
            for row in range(size)]


def _predict(weights: list[float], x: list[float]) -> float:
    value = sum(w * v for w, v in zip(weights, x))
    return min(MAX_CORRECTION_PCT, max(-MAX_CORRECTION_PCT, value))


def _stats(pairs: list[tuple[float, float]]) -> dict:
    result = charge_model._stats(pairs)
    result["rmse"] = (round(math.sqrt(sum((p - a) ** 2 for p, a in pairs) / len(pairs)), 2)
                      if pairs else None)
    return result


def _pairs(steps: list[dict], extra) -> list[tuple[float, float]]:
    return [(min(100.0, step["plain"] + extra(step)), step["actual"]) for step in steps]


def _beats(candidate: dict, baseline: dict, min_n: int) -> bool:
    if candidate["n"] < min_n or candidate["mae"] is None or baseline["mae"] is None:
        return False
    return (candidate["mae"] <= baseline["mae"] * MAE_RATIO
            and candidate["rmse"] <= baseline["rmse"] * RMSE_RATIO
            and abs(candidate["bias"]) <= abs(baseline["bias"]) + BIAS_SLACK)


def _walk_forward(scored: list[dict]) -> list[tuple[dict, float]]:
    """Each test charge is predicted by a model fitted only on earlier charges."""
    result = []
    for index in range(WALK_MIN_TRAIN, len(scored)):
        seen = scored[:index]
        weights = ridge([s["x"] for s in seen], [s["residual"] for s in seen])
        result.append((scored[index], _predict(weights, scored[index]["x"])))
    return result


def _finetune(model: dict, profile: LearnedProfile, scored: list[dict], simple: str, simple_extra,
              simple_mae: float | None, report: dict, now: datetime) -> tuple[str, float | None]:
    """Fine-tune on the charges the model has not seen, and judge it on those alone
    (QA 148): judged on what it was just fitted to, a new fit always looked better
    and a bad model was never paused. The ``model`` dict is updated in place."""
    fitted_at = _at({"at": model.get("at")})
    start = next((index for index, step in enumerate(scored)
                  if fitted_at is None or step["at"] > fitted_at), len(scored))
    unseen = scored[start:]
    if len(unseen) < FINETUNE_MIN_UNSEEN:
        report["aiDecision"] = "kept"
        if profile.layer == "ai":
            return "ai", profile.layer_mae
        return simple, simple_mae
    old = list(model.get("weights") or [])
    ages = [charge_model._weight(step["item"], now) for step in scored]

    def fit(count: int) -> list[float]:
        return ridge([s["x"] for s in scored[:count]], [s["residual"] for s in scored[:count]],
                     weights=ages[:count], prior=old, strength=RIDGE_FINETUNE)

    old_stats = _stats(_pairs(unseen, lambda step: _predict(old, step["x"])))
    new_stats = _stats([(min(100.0, step["plain"] + _predict(fit(start + offset), step["x"])), step["actual"])
                        for offset, step in enumerate(unseen)])
    simple_stats = _stats(_pairs(unseen, simple_extra))
    keep_new = new_stats["mae"] <= old_stats["mae"] + FINETUNE_TOLERANCE
    stats = new_stats if keep_new else old_stats
    report.update({"ai": stats, "aiBaseline": simple_stats, "aiDecision": "finetuned" if keep_new else "kept"})
    if keep_new:
        model.update({"weights": [round(value, 5) for value in fit(len(scored))], "charges": len(scored),
                      "at": now.isoformat(), "version": int(model.get("version") or 1) + 1})
    if stats["mae"] > simple_stats["mae"] + DEMOTE_MARGIN:
        report["aiDecision"] = "paused_worse"  # weights stay; the next training tries again
        return simple, simple_mae
    return "ai", stats["mae"]


def _span_days(rows: list[dict]) -> float:
    dates = [at for item in rows if (at := _at(item)) is not None]
    return (max(dates) - min(dates)).total_seconds() / 86400 if len(dates) >= 2 else 0.0


def select_layer(profile: LearnedProfile, *, base: float | None,
                 now: datetime | None = None) -> tuple[LearnedProfile, dict]:
    """Choose the layer for this training; a small model is only fine-tuned."""
    now = now or datetime.now(timezone.utc)
    rows = charges(profile)
    steps = timeline(rows, base)
    scored = [step for step in steps if step["scored"]]
    shadow = charge_model.shadow_report(profile)
    offset_wins = _beats(shadow["withOffset"], shadow["plain"], OFFSET_MIN_TEST)
    simple = "offset" if offset_wins else "base"
    simple_extra = (lambda step: step["offset"]) if offset_wins else (lambda step: 0.0)
    report: dict = {"selected": simple, "charges": len(rows), "scored": len(scored),
                    "days": round(_span_days(rows), 1), "offset": shadow["withOffset"],
                    "base": shadow["plain"], "ai": None, "aiDecision": "waiting_for_data"}
    model = dict(profile.ai_model) if profile.ai_model else None
    layer_mae = shadow["withOffset"]["mae"] if offset_wins else None
    selected = simple
    if model:
        selected, layer_mae = _finetune(model, profile, scored, simple, simple_extra, layer_mae, report, now)
    elif len(scored) >= AI_MIN_CHARGES and _span_days(rows) >= AI_MIN_DAYS:
        tested = _walk_forward(scored)
        ai_stats = _stats([(min(100.0, step["plain"] + value), step["actual"]) for step, value in tested])
        simple_stats = _stats(_pairs([step for step, _ in tested], simple_extra))
        report.update({"ai": ai_stats, "aiBaseline": simple_stats, "aiDecision": "rejected_not_better"})
        if _beats(ai_stats, simple_stats, AI_MIN_TEST):
            weights = ridge([s["x"] for s in scored], [s["residual"] for s in scored])
            model = {"features": list(FEATURES), "weights": [round(value, 5) for value in weights],
                     "charges": len(scored), "at": now.isoformat(), "version": 1}
            selected, layer_mae = "ai", ai_stats["mae"]
            report["aiDecision"] = "promoted"
    report["selected"] = selected
    updated = LearnedProfile(**{**profile.__dict__, "layer": selected, "ai_model": model, "layer_mae": layer_mae})
    return updated, report


def correction(profile: LearnedProfile | None, start_pct: float, target_pct: float,
               now: datetime | None = None) -> float:
    """% to add to the plain estimate for a charge about to start. Only what
    training selected, bounded, and 0 for a charge to full (the charger ends it)."""
    if profile is None or profile.layer == "base" or target_pct >= FULL_END_PCT:
        return 0.0
    gain = max(0.0, target_pct - start_pct)
    if profile.layer == "offset":
        value = profile.gauge_offset_pct
    else:
        weights = list((profile.ai_model or {}).get("weights") or [])
        if len(weights) != len(FEATURES):
            return 0.0
        value = _predict(weights, _vector({
            "start": start_pct, "gain": gain, "offset": profile.gauge_offset_pct,
            "partial": charges_since_full(profile), "gap": _gap_days(profile, now)}))
    limit = min(MAX_CORRECTION_PCT, gain * MAX_CORRECTION_SHARE)
    return round(min(limit, max(-limit, value)), 2)


def _gap_days(profile: LearnedProfile, now: datetime | None) -> float:
    rows = charges(profile)
    last = _at(rows[-1]) if rows else None
    if last is None:
        return 7.0
    return max(0.0, ((now or datetime.now(timezone.utc)) - last).total_seconds() / 86400)


def charges_since_full(profile: LearnedProfile) -> int:
    """Labelled charges since the last one that reached 100 %."""
    count = 0
    for item in reversed(charges(profile)):
        if float(item.get("actualEndPct") or 0) >= FULL_END_PCT:
            break
        count += 1
    return count


def status(profile: LearnedProfile) -> dict:
    """What the app shows: the layer in use, the way to the small model, and
    whether to suggest a full charge."""
    rows = charges(profile)
    scored = sum(1 for item in rows
                 if float(item.get("actualEndPct") or 0) < FULL_END_PCT and not item.get("censored"))
    partial = charges_since_full(profile)
    return {
        "layer": profile.layer,
        "aiCharges": scored,
        "aiNeedCharges": AI_MIN_CHARGES,
        "aiDays": round(_span_days(rows), 1),
        "aiNeedDays": AI_MIN_DAYS,
        "chargesSinceFull": partial,
        "suggestFull": bool(rows) and partial >= FULL_SUGGEST_AFTER,
    }
