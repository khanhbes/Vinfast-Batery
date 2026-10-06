"""User behavior aggregation & profiling engine."""
from __future__ import annotations

import logging
import threading
from datetime import datetime, timezone
from typing import Dict, List, Optional

from .chat_schemas import (
    AppUsagePatterns,
    BehaviorProfile,
    ChargingPatterns,
    ChatPreferences,
    PersonalInsights,
    TripPatterns,
)

logger = logging.getLogger("ai_server.behavior_analyzer")


class BehaviorAnalyzer:
    """Thu thập, tổng hợp và học thói quen người dùng để cá nhân hóa AI."""

    def __init__(self):
        self._lock = threading.RLock()
        self._profiles: Dict[str, BehaviorProfile] = {}

    def get_or_create_profile(
        self, user_id: str, vehicle_id: Optional[str] = None
    ) -> BehaviorProfile:
        """Lấy profile hiện có hoặc khởi tạo profile mới với giá trị mặc định chuẩn."""
        with self._lock:
            uid = user_id or "anonymous"
            if uid not in self._profiles:
                now_iso = datetime.now(timezone.utc).isoformat()
                self._profiles[uid] = BehaviorProfile(
                    schemaVersion="behavior-profile/v1",
                    userId=uid,
                    vehicleId=vehicle_id,
                    updatedAt=now_iso,
                    syncedAt=now_iso,
                    chargingPatterns=ChargingPatterns(),
                    tripPatterns=TripPatterns(),
                    appUsage=AppUsagePatterns(),
                    chatPreferences=ChatPreferences(),
                    personalInsights=PersonalInsights(),
                )
            elif vehicle_id and not self._profiles[uid].vehicleId:
                self._profiles[uid].vehicleId = vehicle_id
            return self._profiles[uid]

    def update_profile(self, user_id: str, profile: BehaviorProfile) -> BehaviorProfile:
        """Cập nhật toàn bộ profile từ nguồn đồng bộ."""
        with self._lock:
            uid = user_id or profile.userId or "anonymous"
            profile.userId = uid
            profile.updatedAt = datetime.now(timezone.utc).isoformat()
            self._profiles[uid] = profile
            return profile

    def record_charging_event(
        self,
        user_id: str,
        start_hour: int,
        target_soc: float,
        duration_min: int = 180,
        night_charging: bool = True,
        event_time: Optional[str] = None,
    ) -> BehaviorProfile:
        """Ghi nhận phiên sạc pin và cập nhật thói quen sạc."""
        with self._lock:
            p = self.get_or_create_profile(user_id)
            cp = p.chargingPatterns
            now_iso = event_time or datetime.now(timezone.utc).isoformat()

            # Moving average cho targetSoc và preferredStartHour
            cp.avgTargetSoc = round((cp.avgTargetSoc * 0.7) + (target_soc * 0.3), 1)
            cp.preferredStartHour = int((cp.preferredStartHour * 0.7) + (start_hour * 0.3))
            cp.avgChargeDurationMinutes = int(
                (cp.avgChargeDurationMinutes * 0.7) + (duration_min * 0.3)
            )
            cp.preferNightCharging = night_charging
            cp.lastChargingEvent = now_iso
            p.updatedAt = now_iso
            return p

    def record_trip_event(
        self,
        user_id: str,
        distance_km: float,
        energy_wh_per_km: float = 32.0,
    ) -> BehaviorProfile:
        """Ghi nhận chuyến đi và cập nhật chỉ số tiêu thụ năng lượng."""
        with self._lock:
            p = self.get_or_create_profile(user_id)
            tp = p.tripPatterns
            tp.totalTrips += 1
            tp.avgDailyDistanceKm = round(
                (tp.avgDailyDistanceKm * 0.8) + (distance_km * 0.2), 1
            )
            tp.avgEnergyConsumptionWhPerKm = round(
                (tp.avgEnergyConsumptionWhPerKm * 0.8) + (energy_wh_per_km * 0.2), 1
            )
            p.updatedAt = datetime.now(timezone.utc).isoformat()
            return p

    def record_app_usage(
        self,
        user_id: str,
        tab_name: str,
        session_minutes: float = 2.0,
    ) -> BehaviorProfile:
        """Ghi nhận tab được dùng và thời lượng phiên dùng app."""
        with self._lock:
            p = self.get_or_create_profile(user_id)
            au = p.appUsage
            au.totalSessions += 1
            au.avgSessionMinutes = round(
                (au.avgSessionMinutes * 0.85) + (session_minutes * 0.15), 1
            )
            if tab_name and tab_name not in au.mostVisitedTabs:
                au.mostVisitedTabs.insert(0, tab_name)
                au.mostVisitedTabs = au.mostVisitedTabs[:5]
            p.updatedAt = datetime.now(timezone.utc).isoformat()
            return p

    def record_chat_interaction(
        self,
        user_id: str,
        topic: Optional[str] = None,
        feedback_rating: Optional[str] = None,
    ) -> BehaviorProfile:
        """Ghi nhận tương tác chatbot và điểm đánh giá phản hồi 👍/👎."""
        with self._lock:
            p = self.get_or_create_profile(user_id)
            cp = p.chatPreferences

            if topic and topic not in cp.topTopics:
                cp.topTopics.insert(0, topic)
                cp.topTopics = cp.topTopics[:5]

            if feedback_rating == "like":
                cp.feedbackStats["totalThumbsUp"] = (
                    cp.feedbackStats.get("totalThumbsUp", 0) + 1
                )
            elif feedback_rating == "dislike":
                cp.feedbackStats["totalThumbsDown"] = (
                    cp.feedbackStats.get("totalThumbsDown", 0) + 1
                )

            p.updatedAt = datetime.now(timezone.utc).isoformat()
            return p


    def replace_feedback(self, user_id: str, previous: Optional[str], rating: str) -> None:
        """One message contributes one vote, even after an alias/reversal/retry."""
        aliases = {'up': 'like', 'down': 'dislike'}
        previous = aliases.get(previous, previous) if previous is not None else None
        rating = aliases.get(rating, rating)
        with self._lock:
            if previous == rating:
                return
            profile = self.get_or_create_profile(user_id)
            stats = profile.chatPreferences.feedbackStats
            keys = {'like': 'totalThumbsUp', 'dislike': 'totalThumbsDown'}
            if previous in keys:
                stats[keys[previous]] = max(0, stats.get(keys[previous], 0) - 1)
            if rating in keys:
                stats[keys[rating]] = stats.get(keys[rating], 0) + 1
            profile.updatedAt = datetime.now(timezone.utc).isoformat()


# Global analyzer singleton
behavior_analyzer = BehaviorAnalyzer()
