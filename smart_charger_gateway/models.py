from datetime import datetime
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


class ChargingSessionRequest(BaseModel):
    vehicle_id: str = Field(min_length=1)
    start_soc: float = Field(ge=0, le=100)
    target_soc: float = Field(ge=0, le=100)
    predicted_minutes: int = Field(ge=1, le=720)
    started_at: datetime
    predicted_full_at: datetime
    charging_mode: Literal["standard", "fast"] = "standard"
    prediction_source: str | None = None
    prediction_confidence: float | None = None

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
