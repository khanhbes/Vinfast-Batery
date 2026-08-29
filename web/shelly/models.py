from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def iso(value: datetime | None) -> str | None:
    return value.astimezone(timezone.utc).isoformat() if value else None


@dataclass
class DeviceStatus:
    online: bool
    relay: bool
    timer_remaining: int = 0
    power_w: float = 0
    voltage_v: float = 0
    current_a: float = 0
    temperature_c: float | None = None
    energy_wh: float = 0
    device_id: str = ""
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class EtaCandidate:
    source: str
    duration_seconds: int
    weight: float
    confidence: float
    available: bool = True
    reason: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "source": self.source,
            "durationSeconds": self.duration_seconds,
            "weight": round(self.weight, 4),
            "confidence": round(self.confidence, 2),
            "available": self.available,
            "reason": self.reason,
        }


@dataclass
class PersonalChargingProfile:
    owner_uid: str
    vehicle_id: str
    consent_enabled: bool = False
    valid_sessions: int = 0
    power_sessions: int = 0
    eta_bias_ratio: float = 0.0
    median_power_w: float | None = None
    efficiency: float = 0.90
    usable_capacity_wh: float | None = None
    validation_mape: float | None = None
    adapter_version: str = "personal-v0"
    active: bool = False
    updated_at: datetime = field(default_factory=utcnow)

    def to_dict(self, *, public: bool = False) -> dict[str, Any]:
        value = {
            "vehicleId": self.vehicle_id,
            "consentEnabled": self.consent_enabled,
            "validSessions": self.valid_sessions,
            "powerSessions": self.power_sessions,
            "etaBiasRatio": self.eta_bias_ratio,
            "medianPowerW": self.median_power_w,
            "efficiency": self.efficiency,
            "usableCapacityWh": self.usable_capacity_wh,
            "validationMape": self.validation_mape,
            "adapterVersion": self.adapter_version,
            "active": self.active,
            "updatedAt": iso(self.updated_at),
        }
        if not public:
            value["ownerUid"] = self.owner_uid
        return value


@dataclass(frozen=True)
class SmartChargeSafetyPolicy:
    warning_current_a: float = 10.5
    warning_power_w: float = 2300
    warning_temperature_c: float = 65
    warning_voltage_min_v: float = 200
    warning_voltage_max_v: float = 250
    cutoff_current_a: float = 11.5
    cutoff_power_w: float = 2450
    cutoff_temperature_c: float = 75
    cutoff_voltage_min_v: float = 190
    cutoff_voltage_max_v: float = 255
    consecutive_samples: int = 2


@dataclass
class SmartChargeSafetyEvent:
    kind: str
    severity: str
    message: str
    observed_value: float | None
    created_at: datetime = field(default_factory=utcnow)

    def to_dict(self) -> dict[str, Any]:
        return {
            "kind": self.kind,
            "severity": self.severity,
            "message": self.message,
            "observedValue": self.observed_value,
            "createdAt": iso(self.created_at),
        }


@dataclass
class DeviceBinding:
    device_id: str
    display_name: str
    model: str
    generation: int
    provider: str
    connection_mode: str = "server_cloud"
    permissions: list[str] = field(default_factory=lambda: ["read", "control"])
    online: bool = False
    power_meter_verified: bool = False
    safe_boot_verified: bool = False
    no_load_test_verified: bool = False
    last_verified_at: datetime | None = None
    host: str | None = None
    revoked_at: datetime | None = None
    created_at: datetime = field(default_factory=utcnow)
    updated_at: datetime = field(default_factory=utcnow)

    def to_dict(self) -> dict[str, Any]:
        return {
            "deviceId": self.device_id,
            "displayName": self.display_name,
            "model": self.model,
            "generation": self.generation,
            "provider": self.provider,
            "connectionMode": self.connection_mode,
            "permissions": self.permissions,
            "online": self.online,
            "powerMeterVerified": self.power_meter_verified,
            "safeBootVerified": self.safe_boot_verified,
            "noLoadTestVerified": self.no_load_test_verified,
            "lastVerifiedAt": iso(self.last_verified_at),
            "revokedAt": iso(self.revoked_at),
            "createdAt": iso(self.created_at),
            "updatedAt": iso(self.updated_at),
        }


@dataclass
class ChargePreview:
    preview_id: str
    vehicle_id: str
    current_soc: float
    target_soc: float
    predicted_minutes: int
    predicted_duration_seconds: int
    predicted_stop_at: datetime
    model_source: str
    model_key: str
    model_version: str
    runtime_health: str
    confidence: float | None
    warnings: list[str]
    fallback_reason: str | None
    analyzed_at: datetime
    ai_charge_eligible: bool
    expires_at: datetime
    eta_candidates: list[EtaCandidate] = field(default_factory=list)
    fusion_reason: str = "global_ai_only"
    profile_version: str | None = None
    adapter_version: str | None = None
    capacity_confidence: float | None = None
    efficiency_confidence: float | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "previewId": self.preview_id,
            "vehicleId": self.vehicle_id,
            "currentSoc": self.current_soc,
            "targetSoc": self.target_soc,
            "predictedMinutes": self.predicted_minutes,
            "predictedDurationSeconds": self.predicted_duration_seconds,
            "predictedStopAt": iso(self.predicted_stop_at),
            "modelSource": self.model_source,
            "modelKey": self.model_key,
            "modelVersion": self.model_version,
            "runtimeHealth": self.runtime_health,
            "confidence": self.confidence,
            "warnings": self.warnings,
            "fallbackReason": self.fallback_reason,
            "analyzedAt": iso(self.analyzed_at),
            "aiChargeEligible": self.ai_charge_eligible,
            "socIsEstimated": True,
            "expiresAt": iso(self.expires_at),
            "etaCandidates": [item.to_dict() for item in self.eta_candidates],
            "fusionReason": self.fusion_reason,
            "profileVersion": self.profile_version,
            "adapterVersion": self.adapter_version,
            "capacityConfidence": self.capacity_confidence,
            "efficiencyConfidence": self.efficiency_confidence,
        }


@dataclass
class ChargingSession:
    session_id: str
    device_id: str
    vehicle_id: str
    state: str
    start_soc: float
    target_soc: float
    predicted_minutes: int
    predicted_duration_seconds: int
    prediction_source: str
    prediction_confidence: float | None
    created_at: datetime
    updated_at: datetime
    ai_stop_at: datetime
    effective_stop_at: datetime
    absolute_safety_stop_at: datetime
    idempotency_key: str
    strategy: str = "ai_target"
    model_key: str = "charging_time"
    model_version: str = "unknown"
    runtime_health: str = "unknown"
    prediction_warnings: list[str] = field(default_factory=list)
    fallback_reason: str | None = None
    prediction_analyzed_at: datetime | None = None
    estimated_soc: float | None = None
    baseline_energy_wh: float | None = None
    energy_used_wh: float = 0
    relay_verified: bool = False
    timer_verified: bool = False
    transport: str = "shelly_cloud"
    stopped_at: datetime | None = None
    stop_reason: str | None = None
    version: int = 1
    last_error: str | None = None
    eta_candidates: list[EtaCandidate] = field(default_factory=list)
    fusion_reason: str = "global_ai_only"
    profile_version: str | None = None
    adapter_version: str | None = None
    safety_events: list[SmartChargeSafetyEvent] = field(default_factory=list)
    actual_end_soc: float | None = None
    training_eligible: bool = False
    telemetry_coverage: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        return {
            "session_id": self.session_id,
            "device_id": self.device_id,
            "vehicle_id": self.vehicle_id,
            "state": self.state,
            "strategy": self.strategy,
            "start_soc": self.start_soc,
            "target_soc": self.target_soc,
            "estimated_soc": self.estimated_soc,
            "predicted_minutes": self.predicted_minutes,
            "predicted_duration_seconds": self.predicted_duration_seconds,
            "prediction_source": self.prediction_source,
            "prediction_confidence": self.prediction_confidence,
            "model_key": self.model_key,
            "model_version": self.model_version,
            "runtime_health": self.runtime_health,
            "prediction_warnings": self.prediction_warnings,
            "fallback_reason": self.fallback_reason,
            "prediction_analyzed_at": iso(self.prediction_analyzed_at),
            "soc_estimated": True,
            "created_at": iso(self.created_at),
            "updated_at": iso(self.updated_at),
            "started_at": iso(self.created_at),
            "ai_stop_at": iso(self.ai_stop_at),
            "hard_deadline_at": iso(self.absolute_safety_stop_at),
            "effective_stop_at": iso(self.effective_stop_at),
            "absolute_safety_stop_at": iso(self.absolute_safety_stop_at),
            "stopped_at": iso(self.stopped_at),
            "stop_reason": self.stop_reason,
            "relay_verified": self.relay_verified,
            "timer_verified": self.timer_verified,
            "baseline_energy_wh": self.baseline_energy_wh,
            "energy_used_wh": self.energy_used_wh,
            "energy_quality": "good",
            "shadow_mode": False,
            "transport": self.transport,
            "version": self.version,
            "last_error": self.last_error,
            "eta_candidates": [item.to_dict() for item in self.eta_candidates],
            "fusion_reason": self.fusion_reason,
            "profile_version": self.profile_version,
            "adapter_version": self.adapter_version,
            "safety_events": [item.to_dict() for item in self.safety_events],
            "actual_end_soc": self.actual_end_soc,
            "training_eligible": self.training_eligible,
            "telemetry_coverage": self.telemetry_coverage,
        }
