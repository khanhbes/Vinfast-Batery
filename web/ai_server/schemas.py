"""Pydantic schemas for the AI server (input/output contracts)."""
from __future__ import annotations

from typing import List, Optional, Any, Dict
from pydantic import BaseModel, Field, field_validator


class PredictRequest(BaseModel):
    """Input contract — giữ nguyên để app/web không đổi payload."""
    currentBattery: float = Field(..., ge=0, le=100)
    temperature: float
    voltage: float
    current: float
    odometer: float = Field(..., ge=0)
    timeOfDay: int = Field(..., ge=0, le=23)
    dayOfWeek: int = Field(..., ge=0, le=6)
    avgSpeed: float = Field(..., ge=0)
    elevationGain: float = 0.0
    weatherCondition: str = "normal"

    @field_validator("weatherCondition")
    @classmethod
    def _wc(cls, v: str) -> str:
        allowed = {"normal", "rain", "hot", "cold", "sunny", "cloudy"}
        v = (v or "normal").lower()
        return v if v in allowed else "normal"


class PredictResponse(BaseModel):
    predictedSOC: float
    confidence: float
    timeSeries: List[float]
    batteryHealth: float
    recommendations: List[str]
    timestamp: str
    modelVersion: str


class ModelVersionInfo(BaseModel):
    version: str
    path: str
    active: bool
    uploadedAt: str
    note: Optional[str] = None
    sizeBytes: int = 0


class ModelStatus(BaseModel):
    isLoaded: bool
    activeVersion: Optional[str]
    modelFile: Optional[str]
    lastLoadAt: Optional[str]
    lastError: Optional[str]
    availableVersions: int


class UploadResult(BaseModel):
    version: str
    activated: bool
    note: Optional[str] = None
    smokeTest: Dict[str, Any]
