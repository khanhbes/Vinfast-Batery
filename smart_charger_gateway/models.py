from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Literal

from pydantic import BaseModel, Field, model_validator


class ChargerStatus(BaseModel):
    online: bool
    relay: bool
    power_w: float = 0.0
    voltage_v: float = 0.0
    current_a: float = 0.0
    frequency_hz: float = 0.0
    temperature_c: float | None = None
    energy_wh: float = 0.0


class ChargerCommandResponse(BaseModel):
    success: bool
    relay: bool
    previous_state: bool | None = None


class ChargingStrategy(str, Enum):
    TARGET_SOC = "target_soc"
    DEADLINE = "deadline"
    SMART_COMBINED = "smart_combined"


class ChargingSessionState(str, Enum):
    STARTING = "starting"
    ACTIVE = "active"
    STOPPING = "stopping"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    INTERRUPTED = "interrupted"
    FAILED = "failed"


class ChargingStopReason(str, Enum):
    TARGET_SOC = "target_soc"
    DEADLINE = "deadline"
    SMART_COMBINED = "smart_combined"
    ABSOLUTE_SAFETY = "absolute_safety"
    MANUAL = "manual"
    RELAY_OFF = "relay_off"
    GATEWAY_RESTART_EXPIRED = "gateway_restart_expired"
    COMMAND_FAILED = "command_failed"
    OVER_TEMPERATURE = "over_temperature"
    BATTERY_OVER_TEMPERATURE = "battery_over_temperature"
    OVER_VOLTAGE = "over_voltage"
    UNDER_VOLTAGE = "under_voltage"
    OVER_CURRENT = "over_current"
    OVER_POWER = "over_power"
    TELEMETRY_STALE = "telemetry_stale"
    UNEXPECTED_RELAY_STATE = "unexpected_relay_state"


TERMINAL_SESSION_STATES = {
    ChargingSessionState.COMPLETED,
    ChargingSessionState.CANCELLED,
    ChargingSessionState.INTERRUPTED,
    ChargingSessionState.FAILED,
}


class ChargingSessionRequest(BaseModel):
    """Step 8 monitor-only request. Kept wire-compatible."""

    vehicle_id: str = Field(min_length=1)
    start_soc: float = Field(ge=0, le=100)
    target_soc: float = Field(ge=0, le=100)
    predicted_minutes: int = Field(ge=1, le=720)
    started_at: datetime
    predicted_full_at: datetime
    charging_mode: Literal["standard", "fast"] = "standard"
    prediction_source: str | None = None
    prediction_confidence: float | None = Field(default=None, ge=0, le=100)

    @model_validator(mode="after")
    def validate_session(self) -> "ChargingSessionRequest":
        if self.target_soc <= self.start_soc:
            raise ValueError("target_soc must be greater than start_soc")
        if self.predicted_full_at <= self.started_at:
            raise ValueError("predicted_full_at must be after started_at")
        return self


class ChargingSessionResponse(BaseModel):
    success: bool = True
    session_id: str
    mode: Literal["monitor_only"] = "monitor_only"
    received_at: datetime


class AutomaticChargingSessionRequest(BaseModel):
    vehicle_id: str = Field(min_length=1)
    start_soc: float = Field(ge=0, le=100)
    target_soc: float = Field(gt=0, le=100)
    predicted_minutes: int = Field(ge=1, le=1440)
    strategy: ChargingStrategy = ChargingStrategy.SMART_COMBINED
    hard_deadline_at: datetime
    predicted_full_at: datetime | None = None
    charging_mode: Literal["standard", "fast"] = "standard"
    prediction_source: str = Field(default="unknown", min_length=1)
    prediction_confidence: float | None = Field(default=None, ge=0, le=100)
    estimated_capacity_wh: float | None = Field(default=None, gt=0)
    acknowledge_estimated_soc: bool = False

    @model_validator(mode="after")
    def validate_request(self) -> "AutomaticChargingSessionRequest":
        if self.target_soc <= self.start_soc:
            raise ValueError("target_soc must be greater than start_soc")
        return self


class ChargingSessionPatchRequest(BaseModel):
    expected_version: int = Field(ge=1)
    hard_deadline_at: datetime | None = None
    target_soc: float | None = Field(default=None, gt=0, le=100)
    predicted_minutes: int | None = Field(default=None, ge=1, le=1440)
    acknowledge_extension: bool = False


class ChargingSessionStopRequest(BaseModel):
    expected_version: int | None = Field(default=None, ge=1)
    user_stop_reason: Literal[
        "need_vehicle", "enough_charge", "safety_concern", "other", "none"
    ] = "none"


class SafetyEvent(BaseModel):
    event_id: str
    type: str
    severity: Literal["warning", "critical"]
    observed_value: float | None = None
    threshold: float | None = None
    timestamp: datetime
    relay_before: bool
    relay_after: bool | None = None
    off_verified: bool = False


class SmartChargingSession(BaseModel):
    session_id: str
    idempotency_key: str
    vehicle_id: str
    state: ChargingSessionState
    strategy: ChargingStrategy
    start_soc: float
    target_soc: float
    predicted_minutes: int
    charging_mode: str = "standard"
    prediction_source: str
    prediction_confidence: float | None = None
    estimated_capacity_wh: float | None = None
    created_at: datetime
    updated_at: datetime
    started_at: datetime | None = None
    ai_stop_at: datetime
    hard_deadline_at: datetime
    effective_stop_at: datetime
    absolute_safety_stop_at: datetime
    stopped_at: datetime | None = None
    stop_reason: ChargingStopReason | None = None
    relay_verified: bool = False
    baseline_energy_wh: float | None = None
    last_meter_energy_wh: float | None = None
    energy_used_wh: float = 0.0
    energy_quality: Literal["good", "meter_reset"] = "good"
    estimated_soc: float | None = None
    shadow_mode: bool = True
    would_have_turned_off_at: datetime | None = None
    version: int = 1
    last_error: str | None = None
    command_failures: int = 0
    shelly_temperature_c: float | None = None
    battery_temperature_c: float | None = None
    safety_events: list[SafetyEvent] = Field(default_factory=list)
    user_stop_reason: str = "none"


class CurrentChargingSessionResponse(BaseModel):
    active: bool
    session: SmartChargingSession | None = None


class ChargingSessionHistoryResponse(BaseModel):
    sessions: list[SmartChargingSession]


class ErrorBody(BaseModel):
    code: str
    message: str
    retryable: bool = False
    session_id: str | None = None


class ErrorResponse(BaseModel):
    error: ErrorBody
