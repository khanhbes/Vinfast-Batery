from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import math

from .models import ChargingSession, PersonalChargingProfile


SOC_BANDS = ((0, 20), (20, 40), (40, 60), (60, 80), (80, 90), (90, 100))


@dataclass(frozen=True)
class TrainingDecision:
    eligible: bool
    reason: str
    quality_score: float
    actual_soc_gain: float
    covered_bands: tuple[str, ...] = ()
    power_eligible: bool = False


def evaluate_training(session: ChargingSession) -> TrainingDecision:
    duration = max(0, int(((session.stopped_at or session.updated_at) - session.created_at).total_seconds()))
    if duration < 1200:
        return TrainingDecision(False, "duration_too_short", 0.2, 0.0)
    if session.energy_used_wh <= 0 or session.energy_quality != "good":
        return TrainingDecision(False, "energy_invalid", 0.3, 0.0)
    if session.telemetry_coverage < 0.70:
        return TrainingDecision(False, "telemetry_incomplete", session.telemetry_coverage, 0.0)
    end_soc = session.actual_end_soc
    if end_soc is None:
        return TrainingDecision(
            False, "actual_soc_required", session.telemetry_coverage, 0.0,
            power_eligible=True,
        )
    gain = float(end_soc) - session.start_soc
    if gain < 10:
        return TrainingDecision(False, "soc_gain_too_small", 0.3, gain, power_eligible=True)
    quality = min(1.0, 0.45 * session.telemetry_coverage + 0.25 + min(0.30, gain / 100))
    bands = tuple(_covered_bands(session.start_soc, float(end_soc)))
    return TrainingDecision(True, "eligible", quality, gain, bands, True)


def update_profile(profile: PersonalChargingProfile, session: ChargingSession, decision: TrainingDecision, now: datetime) -> PersonalChargingProfile:
    """Incrementally learn only the SOC interval actually observed."""
    if not decision.eligible and not decision.power_eligible:
        return profile
    duration_seconds = max(1, int(((session.stopped_at or session.updated_at) - session.created_at).total_seconds()))
    observed_power = session.energy_used_wh / (duration_seconds / 3600)
    profile.power_sessions += 1
    profile.median_power_w = observed_power if profile.median_power_w is None else profile.median_power_w * 0.75 + observed_power * 0.25
    profile.power_scale = profile.power_scale * 0.8 + 1.0 * 0.2
    profile.profile_version += 1
    profile.adapter_version = f"personal-v{profile.profile_version}"
    profile.last_trained_at = now
    profile.updated_at = now
    profile.last_training_error = None
    if not decision.eligible:
        return profile

    profile.valid_sessions += 1
    profile.training_segments += len(decision.covered_bands)

    covered_fraction = decision.actual_soc_gain / max(1.0, session.target_soc - session.start_soc)
    predicted_segment_minutes = max(1.0, session.predicted_minutes * min(1.0, covered_fraction))
    actual_minutes = duration_seconds / 60
    scale = actual_minutes / predicted_segment_minutes
    scale = min(1.50, max(0.65, scale))
    profile.global_time_scale = profile.global_time_scale * 0.75 + scale * 0.25
    profile.eta_bias_ratio = profile.global_time_scale - 1.0
    error_pct = abs(actual_minutes - predicted_segment_minutes) / predicted_segment_minutes * 100
    profile.validation_mape = error_pct if profile.validation_mape is None else profile.validation_mape * 0.75 + error_pct * 0.25

    raw_capacity = session.energy_used_wh * profile.efficiency / (decision.actual_soc_gain / 100)
    nominal = session.nominal_capacity_wh or profile.nominal_capacity_wh
    if nominal and nominal > 0:
        raw_capacity = min(nominal * 1.05, max(nominal * 0.50, raw_capacity))
    if math.isfinite(raw_capacity) and raw_capacity > 0:
        profile.estimated_effective_capacity_wh = raw_capacity if profile.estimated_effective_capacity_wh is None else profile.estimated_effective_capacity_wh * 0.80 + raw_capacity * 0.20
        profile.usable_capacity_wh = profile.estimated_effective_capacity_wh
        profile.capacity_confidence = min(0.98, profile.capacity_confidence * 0.8 + decision.quality_score * 0.2)
        if nominal and nominal > 0:
            profile.state_of_health = min(105.0, max(50.0, profile.estimated_effective_capacity_wh / nominal * 100))

    minutes_per_percent = actual_minutes / decision.actual_soc_gain
    wh_per_percent = session.energy_used_wh / decision.actual_soc_gain
    for key in decision.covered_bands:
        old = dict(profile.soc_bands.get(key) or {})
        samples = int(old.get("samples", 0)) + 1
        alpha = min(0.35, 1 / samples)
        profile.soc_bands[key] = {
            "samples": samples,
            "minutesPerPercent": _ema(old.get("minutesPerPercent"), minutes_per_percent, alpha),
            "whPerPercent": _ema(old.get("whPerPercent"), wh_per_percent, alpha),
            "averagePowerW": _ema(old.get("averagePowerW"), observed_power, alpha),
            "quality": _ema(old.get("quality"), decision.quality_score, alpha),
        }
    profile.quality_confidence = min(0.98, profile.quality_confidence * 0.8 + decision.quality_score * 0.2)
    profile.active = profile.valid_sessions >= 3
    return profile


def _covered_bands(start_soc: float, end_soc: float):
    for lower, upper in SOC_BANDS:
        if min(end_soc, upper) > max(start_soc, lower):
            yield f"{lower}_{upper}"


def _ema(old, value: float, alpha: float) -> float:
    return value if old is None else float(old) * (1 - alpha) + value * alpha
