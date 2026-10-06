"""Unit tests for Phase 2: Behavior Learning & Profile Personalization."""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from ai_server.behavior_analyzer import BehaviorAnalyzer, behavior_analyzer
from ai_server.chat_engine import ChatEngine
from ai_server.chat_schemas import (
    BehaviorProfile,
    BehaviorSyncRequest,
    ChargingPatterns,
    ChatSendRequest,
    TripPatterns,
    VehicleContext,
)
from ai_server.main import app


def test_behavior_analyzer_defaults_and_events():
    """Kiểm tra khởi tạo profile mặc định và cập nhật qua các sự kiện hành vi."""
    analyzer = BehaviorAnalyzer()
    uid = "test-user-001"
    profile = analyzer.get_or_create_profile(uid, "VF-FELIZ-123")

    assert profile.userId == uid
    assert profile.vehicleId == "VF-FELIZ-123"
    assert profile.chargingPatterns.avgTargetSoc == 80.0

    # 1. Ghi nhận sự kiện sạc lúc 23h với mục tiêu 85%
    p1 = analyzer.record_charging_event(uid, start_hour=23, target_soc=85.0)
    assert p1.chargingPatterns.preferredStartHour == int(22 * 0.7 + 23 * 0.3)
    assert p1.chargingPatterns.avgTargetSoc == round(80.0 * 0.7 + 85.0 * 0.3, 1)

    # 2. Ghi nhận chuyến đi 25km tiêu thụ 30 Wh/km
    p2 = analyzer.record_trip_event(uid, distance_km=25.0, energy_wh_per_km=30.0)
    assert p2.tripPatterns.totalTrips == 1
    assert p2.tripPatterns.avgDailyDistanceKm == round(18.5 * 0.8 + 25.0 * 0.2, 1)

    # 3. Ghi nhận mở tab smart_charging
    p3 = analyzer.record_app_usage(uid, tab_name="smart_charging", session_minutes=5.0)
    assert p3.appUsage.totalSessions == 1
    assert "smart_charging" in p3.appUsage.mostVisitedTabs

    # 4. Ghi nhận tương tác chat và feedback 'like'
    p4 = analyzer.record_chat_interaction(uid, topic="pin_soh", feedback_rating="like")
    assert "pin_soh" in p4.chatPreferences.topTopics
    assert p4.chatPreferences.feedbackStats["totalThumbsUp"] == 1


def test_chat_engine_prompt_personalization():
    """Kiểm tra prompt được cá nhân hóa sâu theo hồ sơ hành vi người dùng."""
    engine = ChatEngine()
    ctx = VehicleContext(model="Evo200", currentSoc=70.0)
    profile = BehaviorProfile(
        userId="user-vip",
        chargingPatterns=ChargingPatterns(
            preferredStartHour=23,
            preferredEndHour=7,
            avgTargetSoc=85.0,
            lastChargingEvent='2026-10-06T00:00:00+00:00',
        ),
        tripPatterns=TripPatterns(
            avgDailyDistanceKm=24.5,
            avgEnergyConsumptionWhPerKm=31.5,
            totalTrips=3,
        ),
    )

    prompt = engine.build_system_prompt(ctx, profile)
    assert "Hồ sơ hành vi người dùng:" in prompt
    assert "Thường sạc lúc: 23h - 7h" in prompt
    assert "Mốc SoC yêu thích: 85%" in prompt
    assert "Quãng đường hàng ngày: 24.5 km" in prompt
    assert "Tiêu thụ trung bình: 31.5 Wh/km" in prompt


def test_chat_engine_fallback_with_behavior():
    """Kiểm tra phản hồi dự phòng thông minh có gợi ý cá nhân hóa."""
    engine = ChatEngine()
    ctx = VehicleContext(model="Feliz S", currentSoc=65.0)
    profile = BehaviorProfile(
        userId="user-local",
        chargingPatterns=ChargingPatterns(preferredStartHour=22, avgTargetSoc=80.0),
        tripPatterns=TripPatterns(avgDailyDistanceKm=15.0),
    )

    req = ChatSendRequest(
        message="Pin mình còn đủ đi làm không?",
        vehicleContext=ctx,
        behaviorProfile=profile,
    )
    chunks = list(engine.stream_chat(req))
    full_text = "".join(
        c.split("data: ")[1].split("\n")[0]
        for c in chunks
        if c.startswith("event: text_delta")
    )
    import json
    reply = "".join(json.loads(c.split("data: ")[1])["delta"] for c in chunks if c.startswith("event: text_delta"))
    assert "65%" in reply
    assert "18.5" not in reply  # Default behavior is not observed range.


def test_fastapi_behavior_sync_and_profile():
    """Kiểm tra API /v1/behavior/sync và /v1/behavior/profile."""
    client = TestClient(app)
    uid = "sync-user-99"

    # Sync profile
    sync_payload = {
        "userId": uid,
        "profile": {
            "userId": uid,
            "vehicleId": "VF-KLARA-01",
            "chargingPatterns": {
                "preferredStartHour": 21,
                "preferredEndHour": 5,
                "avgTargetSoc": 90.0,
            },
            "tripPatterns": {
                "avgDailyDistanceKm": 35.0,
                "avgEnergyConsumptionWhPerKm": 34.0,
            },
        },
    }
    resp = client.post("/v1/behavior/sync", json=sync_payload)
    assert resp.status_code == 200
    res_data = resp.json()
    assert res_data["success"] is True
    assert res_data["data"]["chargingPatterns"]["avgTargetSoc"] == 90.0

    # Get profile
    get_resp = client.get(f"/v1/behavior/profile?userId={uid}")
    assert get_resp.status_code == 200
    get_data = get_resp.json()
    assert get_data["success"] is True
    assert get_data["data"]["chargingPatterns"]["preferredStartHour"] == 21
    assert get_data["data"]["vehicleId"] == "VF-KLARA-01"
