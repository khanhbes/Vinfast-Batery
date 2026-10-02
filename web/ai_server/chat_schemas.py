"""Pydantic schemas for the AI Chatbot (contracts & validation)."""
from __future__ import annotations

from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field, model_validator


class VehicleContext(BaseModel):
    """Snapshot context xe/pin để inject vào chatbot prompt."""
    vehicleId: Optional[str] = None
    model: Optional[str] = None
    currentSoc: Optional[float] = Field(default=None, ge=0, le=100)
    currentSoh: Optional[float] = Field(default=None, ge=0, le=100)
    batteryTemp: Optional[float] = None
    chargingStatus: Optional[str] = "idle"  # idle | charging | error | full
    chargingPower: Optional[float] = None
    targetSoc: Optional[float] = Field(default=None, ge=0, le=100)
    odoKm: Optional[float] = Field(default=None, ge=0)
    estimatedRangeKm: Optional[float] = None

    @model_validator(mode="before")
    @classmethod
    def _normalize_aliases(cls, values: Any) -> Any:
        if isinstance(values, dict):
            # Cho phép alias ngắn 'soc' thay cho 'currentSoc'
            if "soc" in values and "currentSoc" not in values:
                values["currentSoc"] = values["soc"]
            if "soh" in values and "currentSoh" not in values:
                values["currentSoh"] = values["soh"]
            if "temperature" in values and "batteryTemp" not in values:
                values["batteryTemp"] = values["temperature"]
        return values


class ChargingPatterns(BaseModel):
    preferredStartHour: int = 22
    preferredEndHour: int = 6
    avgTargetSoc: float = 80.0
    avgSessionsPerWeek: float = 4.0
    preferNightCharging: bool = True
    avgChargeDurationMinutes: int = 180
    lastChargingEvent: Optional[str] = None


class TripPatterns(BaseModel):
    avgDailyDistanceKm: float = 18.5
    avgEnergyConsumptionWhPerKm: float = 32.0
    frequentRoutes: List[Dict[str, Any]] = Field(default_factory=list)
    peakUsageHours: List[int] = Field(default_factory=lambda: [7, 8, 17, 18])
    totalTrips: int = 0


class AppUsagePatterns(BaseModel):
    avgSessionMinutes: float = 3.5
    mostVisitedTabs: List[str] = Field(default_factory=lambda: ["dashboard", "smart_charging"])
    preferredTheme: str = "dark"
    appOpenHours: List[int] = Field(default_factory=lambda: [7, 12, 18, 22])
    totalSessions: int = 0


class ChatPreferences(BaseModel):
    topTopics: List[str] = Field(default_factory=lambda: ["charging_schedule", "battery_health"])
    feedbackStats: Dict[str, Any] = Field(default_factory=lambda: {"totalThumbsUp": 0, "totalThumbsDown": 0})
    preferredResponseLength: str = "concise"
    languagePreference: str = "vi"


class PersonalInsights(BaseModel):
    batteryHealthTrend: str = "stable"
    chargingEfficiencyScore: float = 0.85
    estimatedMonthlyCostVND: int = 150000
    nextMaintenanceOdoKm: int = 10000
    currentOdoKm: int = 0


class BehaviorProfile(BaseModel):
    """Hồ sơ học hành vi người dùng (Behavior Profile Schema)."""
    schemaVersion: str = "behavior-profile/v1"
    userId: str = ""
    vehicleId: Optional[str] = None
    updatedAt: str = ""
    syncedAt: Optional[str] = None
    chargingPatterns: ChargingPatterns = Field(default_factory=ChargingPatterns)
    tripPatterns: TripPatterns = Field(default_factory=TripPatterns)
    appUsage: AppUsagePatterns = Field(default_factory=AppUsagePatterns)
    chatPreferences: ChatPreferences = Field(default_factory=ChatPreferences)
    personalInsights: PersonalInsights = Field(default_factory=PersonalInsights)


class BehaviorSyncRequest(BaseModel):
    """Request đồng bộ behavior profile từ Mobile lên Backend."""
    userId: str
    profile: BehaviorProfile


class ChatMessage(BaseModel):
    """Một tin nhắn trong phiên trò chuyện."""
    id: Optional[str] = None
    role: str = "user"  # 'user' | 'model' | 'assistant' | 'system'
    content: str
    timestamp: Optional[str] = None
    action: Optional[str] = None
    userFeedback: Optional[str] = None  # 'like' | 'dislike'


class ChatSendRequest(BaseModel):
    """Request gửi tin nhắn tới chatbot."""
    sessionId: Optional[str] = None
    userId: Optional[str] = None
    message: str = Field(..., min_length=1)
    vehicleContext: Optional[VehicleContext] = None
    behaviorProfile: Optional[BehaviorProfile] = None
    model: Optional[str] = "gemini-2.0-flash"
    stream: bool = True
    history: Optional[List[ChatMessage]] = None


class StreamChunk(BaseModel):
    """Dữ liệu trả về theo từng đoạn SSE stream."""
    delta: str = ""
    done: bool = False
    messageId: Optional[str] = None
    sessionId: Optional[str] = None
    error: Optional[str] = None
    usage: Optional[Dict[str, Any]] = None


class ChatSession(BaseModel):
    """Metadata về một phiên trò chuyện."""
    sessionId: str
    userId: Optional[str] = None
    title: str = "Cuộc trò chuyện mới"
    createdAt: str
    updatedAt: str
    messageCount: int = 0
    lastMessage: Optional[str] = None


class ChatFeedbackRequest(BaseModel):
    """Phản hồi đánh giá tin nhắn từ người dùng."""
    messageId: str
    sessionId: str
    userId: Optional[str] = None
    rating: str  # 'like' | 'dislike' | 'up' | 'down'
    comment: Optional[str] = None


class ActionConfirmRequest(BaseModel):
    """Yêu cầu xác nhận thực thi function call từ mobile."""
    sessionId: str
    callId: str
    toolName: str
    args: Dict[str, Any] = Field(default_factory=dict)
    confirmed: bool = True
    userId: Optional[str] = None


class ActionConfirmResponse(BaseModel):
    """Kết quả sau khi xác nhận thực thi tool."""
    success: bool
    toolName: str
    callId: str
    result: Dict[str, Any]
    message: str


class ProactiveSuggestionItem(BaseModel):
    """Một gợi ý proactive cho người dùng."""
    ruleId: str
    title: str
    message: str
    priority: str  # 'HIGH' | 'MEDIUM' | 'LOW'
    action: Optional[str] = None
    suggestedAt: str

