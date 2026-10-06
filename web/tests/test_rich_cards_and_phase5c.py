"""Tests cho Phase 5C: Rich Media Cards & UX Polish trong AI Chatbot.

Bao gồm:
- Rich Card Builder từ Tool Execution Result (BatteryStatus, ChargingProgress, TripSummary).
- Rich Card Intent Detection cho Offline/Fallback Mode.
- SSE stream event: rich_card emission & end_payload inclusion.
- Lưu trữ rich_cards trong ChatMemory.
"""

import json
from unittest.mock import MagicMock, patch

import pytest
from ai_server.chat_engine import ChatEngine
from ai_server.chat_schemas import (
    ChatMessage,
    ChatSendRequest,
    RichCardData,
    VehicleContext,
)


@pytest.fixture
def test_engine():
    engine = ChatEngine()
    engine.client = None
    return engine


def test_rich_card_schema_and_chat_message_integration():
    """Kiểm tra schema RichCardData và ChatMessage có richCards."""
    card = RichCardData(
        cardType="battery_status",
        title="Trạng thái Pin & Xe",
        data={"soc": 82.5, "voltage": 72.4},
    )
    assert card.cardType == "battery_status"
    assert card.data["soc"] == 82.5

    msg = ChatMessage(
        role="model",
        content="Pin xe đang ở mức 82%",
        richCards=[card],
    )
    assert msg.richCards is not None
    assert len(msg.richCards) == 1
    assert msg.richCards[0].cardType == "battery_status"


def test_build_rich_card_battery_status(test_engine):
    """Kiểm tra _build_rich_card tạo thẻ battery_status đầy đủ thông số."""
    tool_result = {
        "vehicleId": "VF-FELIZ-S",
        "soc": 68.0,
        "soh": 97.5,
        "voltage": 71.8,
        "status": "success",
        "temperatureC": 29.0,
        "estimatedRemainingKm": 78.0,
        "chargingStatus": "idle",
    }
    card = test_engine._build_rich_card("get_battery_status", tool_result, None)
    assert card is not None
    assert card["cardType"] == "battery_status"
    assert card["title"] == "Dữ liệu pin đang xem"
    assert "vehicleId" not in card["data"]
    assert card["data"]["soc"] == 68.0
    assert card["data"]["temperature"] == 29.0
    assert card["data"]["estimatedRangeKm"] == 78.0


def test_build_rich_card_charging_progress(test_engine):
    """Kiểm tra _build_rich_card tạo thẻ charging_progress với watchdog ≤12A."""
    tool_result = {
        "chargingPowerW": 2100.0,
        "currentAmps": 9.5,
        "remainingMinutes": 40,
    }
    v_ctx = {"soc": 45.0, "targetSoc": 90.0, "chargingStatus": "charging"}
    card = test_engine._build_rich_card("get_charging_history", tool_result, v_ctx)
    assert card is None  # No live relay/timer evidence; history is not active charging.


def test_build_rich_card_trip_summary(test_engine):
    """Kiểm tra _build_rich_card tạo thẻ trip_summary với quãng đường và CO2."""
    tool_result = {
        "status": "success",
        "distanceKm": 32.4,
        "energyUsedWh": 972.0,
        "efficiencyWhKm": 30.0,
        "co2SavedKg": 2.8,
        "durationMinutes": 55,
    }
    card = test_engine._build_rich_card("get_trip_summary", tool_result, None)
    assert card is not None
    assert card["cardType"] == "trip_summary"
    assert card["data"]["distanceKm"] == 32.4
    assert card["data"]["efficiencyWhKm"] == 30.0
    assert card["data"]["co2SavedKg"] == 2.8


def test_detect_rich_card_intent_battery(test_engine):
    """Kiểm tra nhận diện intent tạo battery_status card qua từ khóa."""
    v_ctx = {
        "vehicleId": "VF-EVO200",
        "soc": 88.0,
        "soh": 99.0,
        "voltage": 73.0,
        "temperature": 27.0,
        "estimatedRangeKm": 180.0,
    }
    card = test_engine._detect_rich_card_intent("Xe mình còn bao nhiêu % pin vậy bot?", v_ctx)
    assert card is not None
    assert card["cardType"] == "battery_status"
    assert card["data"]["soc"] == 88.0
    assert card["data"]["estimatedRangeKm"] == 180.0


def test_detect_rich_card_intent_charging(test_engine):
    """Kiểm tra nhận diện intent tạo charging_progress card."""
    v_ctx = {"soc": 60.0, "targetSoc": 85.0, "chargingStatus": "charging"}
    card = test_engine._detect_rich_card_intent("Xem tiến độ sạc của xe", v_ctx)
    assert card is None  # No verified measurements, never fabricate a card.


def test_detect_rich_card_intent_trip(test_engine):
    """Kiểm tra nhận diện intent tạo trip_summary card."""
    card = test_engine._detect_rich_card_intent("Hôm nay mình đi quãng đường hết bao nhiêu km?", None)
    assert card is None  # No verified measurements, never fabricate a card.


def test_stream_chat_emits_rich_card_event(test_engine):
    """Kiểm tra stream_chat phát event: rich_card và đính kèm vào message_end."""
    req = ChatSendRequest(
        message="Kiểm tra pin của xe giúp mình",
        vehicleContext=VehicleContext(
            vehicleId="VF-FELIZ-S",
            soc=72.0,
            soh=98.0,
            voltage=72.0,
            temperature=28.0,
            estimatedRangeKm=80.0,
        ),
        stream=True,
    )

    events = list(test_engine.stream_chat(req))
    rich_card_events = [e for e in events if "event: rich_card" in e]
    end_events = [e for e in events if "event: message_end" in e]

    assert len(rich_card_events) >= 1
    # Verify rich_card payload
    card_line = rich_card_events[0].split("data: ")[1].strip()
    card_data = json.loads(card_line)
    assert card_data["cardType"] == "battery_status"
    assert card_data["data"]["soc"] == 72.0

    # Verify message_end includes richCards
    assert len(end_events) == 1
    end_line = end_events[0].split("data: ")[1].strip()
    end_data = json.loads(end_line)
    assert "richCards" in end_data
    assert len(end_data["richCards"]) >= 1
    assert end_data["richCards"][0]["cardType"] == "battery_status"
