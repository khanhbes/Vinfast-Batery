from __future__ import annotations

from dataclasses import dataclass
import math

from .models import EtaCandidate, PersonalChargingProfile


@dataclass(frozen=True)
class FusionResult:
    duration_seconds: int
    candidates: list[EtaCandidate]
    reason: str
    effective_capacity_wh: float | None
    stage: str
    clamped: bool = False
    warnings: tuple[str, ...] = ()


def fuse_charging_eta(
    payload: dict,
    prediction: dict,
    global_seconds: int,
    profile: PersonalChargingProfile | None,
) -> FusionResult:
    """Fuse base AI, physics and owner+vehicle calibration deterministically.

    Every candidate is confidence weighted. Physics also supplies the plausible
    bounds used to prevent one unhealthy model from arming an unsafe timer.
    """
    stage = profile.personalization_stage if profile and profile.consent_enabled else "base"
    current = _number(payload.get("currentSoc"), 0)
    target = _number(payload.get("targetSoc"), 0)
    nominal = _positive(payload.get("nominalCapacityWh") or payload.get("estimatedCapacityWh"))
    soh = _number(payload.get("stateOfHealth", payload.get("batteryHealth", 100)), 100)
    soh = min(110.0, max(50.0, soh))
    calibrated_capacity = profile.estimated_effective_capacity_wh if profile else None
    effective_capacity = calibrated_capacity or (nominal * soh / 100 if nominal else None)
    power = _positive(payload.get("actualPowerW") or payload.get("chargerPowerW"))
    if power is None and profile and profile.consent_enabled:
        power = profile.median_power_w
    efficiency = _number(payload.get("chargingEfficiency"), profile.efficiency if profile else 0.90)
    efficiency = min(0.98, max(0.65, efficiency))

    base_conf = _confidence(prediction.get("confidence"), 0.75)
    physics_seconds = _physics_seconds(current, target, effective_capacity, power, efficiency)
    personal_seconds = None
    personal_conf = 0.0
    if profile and profile.consent_enabled and profile.valid_sessions > 0:
        personal_seconds = max(60, int(round(
            global_seconds * profile.global_time_scale
            + profile.global_time_bias_minutes * 60
        )))
        sample_factor = min(1.0, profile.valid_sessions / 10)
        mape_factor = max(0.10, 1 - (profile.validation_mape or 40) / 100)
        personal_conf = min(0.98, sample_factor * mape_factor * max(0.35, profile.quality_confidence or 0.35))

    base_weights = {
        "base": (0.45, 0.55, 0.0),
        "calibrating": (0.40, 0.40, 0.20),
        "personalized": (0.30, 0.30, 0.40),
    }[stage]
    raw = [
        ["global_ai", global_seconds, base_weights[0] * base_conf, base_conf, prediction.get("modelVersion")],
    ]
    if physics_seconds:
        capacity_conf = _confidence(payload.get("capacityConfidence"), profile.capacity_confidence if profile else 0.55)
        power_conf = 0.82 if payload.get("actualPowerW") else (0.72 if profile and profile.power_sessions >= 3 else 0.50)
        physics_conf = math.sqrt(max(0.01, capacity_conf * power_conf))
        raw.append(["physics", physics_seconds, base_weights[1] * physics_conf, physics_conf, "capacity_power_taper_v3"])
    if personal_seconds and base_weights[2] > 0:
        raw.append(["personal", personal_seconds, base_weights[2] * personal_conf, personal_conf, profile.adapter_version])

    warnings: list[str] = []
    if physics_seconds:
        for item in raw:
            deviation = abs(item[1] - physics_seconds) / max(physics_seconds, 1)
            if item[0] != "physics" and deviation > 0.45:
                item[2] *= 0.25
                warnings.append(f"{item[0]}_deviates_from_physics")
    total = sum(max(0.0, float(item[2])) for item in raw)
    if total <= 0:
        raw[0][2] = 1.0
        total = 1.0
    candidates = [
        EtaCandidate(
            source=str(source), duration_seconds=int(seconds), weight=float(weight) / total,
            confidence=float(confidence) * 100, reason=str(reason) if reason else None,
        )
        for source, seconds, weight, confidence, reason in raw
    ]
    fused = int(round(sum(item.duration_seconds * item.weight for item in candidates)))
    clamped = False
    if physics_seconds:
        lower = max(60, int(physics_seconds * 0.60))
        upper = int(physics_seconds * 1.60)
        bounded = min(upper, max(lower, fused))
        clamped = bounded != fused
        fused = bounded
        if clamped:
            warnings.append("fusion_clamped_to_physical_bounds")
    reason = f"{stage}_confidence_weighted"
    return FusionResult(fused, candidates, reason, effective_capacity, stage, clamped, tuple(warnings))


def _physics_seconds(current: float, target: float, capacity: float | None, power: float | None, efficiency: float) -> int | None:
    if not capacity or not power or target <= current:
        return None
    seconds = 0.0
    bands = ((0.0, 80.0, 1.0), (80.0, 90.0, 0.82), (90.0, 100.0, 0.65))
    for lower, upper, power_factor in bands:
        start = max(current, lower)
        end = min(target, upper)
        if end <= start:
            continue
        battery_wh = capacity * (end - start) / 100
        seconds += battery_wh / (power * power_factor * efficiency) * 3600
    return max(60, int(round(seconds)))


def _number(value, fallback: float) -> float:
    try:
        parsed = float(value)
        return parsed if math.isfinite(parsed) else fallback
    except (TypeError, ValueError):
        return fallback


def _positive(value) -> float | None:
    parsed = _number(value, 0)
    return parsed if parsed > 0 else None


def _confidence(value, fallback: float) -> float:
    parsed = _number(value, fallback)
    if parsed > 1:
        parsed /= 100
    return min(1.0, max(0.05, parsed))
