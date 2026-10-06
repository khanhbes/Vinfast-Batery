"""Tests for AI Chatbot Function Calling & Proactive Suggestions (Phase 3)."""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from ai_server.chat_schemas import (
    ActionConfirmRequest,
    ActionConfirmResponse,
    VehicleContext,
)
from ai_server.chat_tools import (
    ChatToolDispatcher,
    MAX_SAFE_AMPS,
    TOOL_DECLARATIONS,
    chat_tool_dispatcher,
)
from ai_server.suggestion_engine import SuggestionEngine, suggestion_engine
from ai_server.main import app


def test_tool_declarations_structure():
    """Kiểm tra có đủ 9 tool và tuân thủ định dạng function calling."""
    tool_names = [t["name"] for t in TOOL_DECLARATIONS]
    assert len(tool_names) == 9
    assert "start_smart_charging" in tool_names
    assert "stop_smart_charging" in tool_names
    assert "schedule_charging" in tool_names
    assert "get_battery_status" in tool_names
    assert "get_charging_history" in tool_names
    assert "get_trip_summary" in tool_names
    assert "get_maintenance_info" in tool_names
    assert "get_energy_tips" in tool_names
    assert "get_weather_impact" in tool_names


def test_safety_gated_tools_require_confirmation():
    """Kiểm tra các tool điều khiển vật lý bắt buộc Human-in-the-Loop."""
    dispatcher = ChatToolDispatcher()
    assert dispatcher.requires_confirmation("start_smart_charging") is True
    assert dispatcher.requires_confirmation("stop_smart_charging") is True
    assert dispatcher.requires_confirmation("schedule_charging") is True
    assert dispatcher.requires_confirmation("get_battery_status") is False
    assert dispatcher.requires_confirmation("get_trip_summary") is False


def test_start_smart_charging_hardware_safety_limit():
    """Kiểm tra giới hạn dòng sạc an toàn <= 12A / 2500W theo tiêu chuẩn."""
    dispatcher = ChatToolDispatcher()
    card = dispatcher.create_confirmation_card(
        "start_smart_charging",
        {"vehicle_id": "VF-FELIZ-001", "target_soc": 85, "max_amps": 16.0},  # Yêu cầu 16A vượt ngưỡng
        {"model": "Feliz S", "currentSoc": 40},
    )
    assert card["requiresConfirmation"] is True
    assert card["args"]["max_amps"] <= MAX_SAFE_AMPS
    assert card["confirmationCard"]["maxAmps"] <= MAX_SAFE_AMPS


def test_tool_execution_flow_unconfirmed_and_confirmed():
    """Kiểm tra luồng tạo card khi chưa confirm và thực thi khi đã confirm."""
    dispatcher = ChatToolDispatcher()

    # 1. Chưa confirm -> trả về Confirmation Card
    unconfirmed = dispatcher.execute_tool(
        "start_smart_charging",
        {"vehicle_id": "VF-EVO200-01", "target_soc": 80},
        {"currentSoc": 50},
        is_confirmed=False,
    )
    assert unconfirmed.get("requiresConfirmation") is True
    assert "confirmationCard" in unconfirmed

    # 2. Đã confirm -> kích hoạt relay sạc
    confirmed = dispatcher.execute_tool(
        "start_smart_charging",
        {"vehicle_id": "VF-EVO200-01", "target_soc": 80},
        {"currentSoc": 50},
        is_confirmed=True,
    )
    assert confirmed["status"] == "unavailable"
    assert confirmed["code"] == "controlAdapterUnavailable"
    assert "relayState" not in confirmed


def test_read_tools_execution():
    """Kiểm tra các tool đọc thông tin (read tools) thực thi tức thì."""
    dispatcher = ChatToolDispatcher()

    # Battery status
    batt = dispatcher.execute_tool("get_battery_status", {"vehicle_id": "VF01"}, {"currentSoc": 68.0, "currentSoh": 97.5})
    assert batt["status"] == "success"
    assert batt["soc"] == 68.0
    assert "estimatedRemainingKm" not in batt

    # Maintenance info
    maint = dispatcher.execute_tool("get_maintenance_info", {"vehicle_id": "VF01"}, {"odoKm": 4700})
    assert maint["status"] == "unavailable"
    assert "remainingKm" not in maint


def test_suggestion_engine_rules():
    """Kiểm tra SuggestionEngine tạo gợi ý theo Rules R001-R008."""
    engine = SuggestionEngine()

    # R001: SoC < 20% -> HIGH priority
    suggestions_low_soc = engine.generate_suggestions(
        vehicle_context={"currentSoc": 15.0, "chargingStatus": "idle", "model": "Evo200"},
        current_hour=14,
    )
    rule_ids = [s["ruleId"] for s in suggestions_low_soc]
    assert "R001" in rule_ids
    r001 = next(s for s in suggestions_low_soc if s["ruleId"] == "R001")
    assert r001["priority"] == "HIGH"

    # R008: Morning hour (07:00) -> LOW priority greeting
    suggestions_morning = engine.generate_suggestions(
        vehicle_context={"currentSoc": 80.0, "chargingStatus": "idle", "model": "Feliz S"},
        current_hour=7,
    )
    m_rule_ids = [s["ruleId"] for s in suggestions_morning]
    assert "R008" in m_rule_ids


def test_fastapi_action_confirm_and_suggestions_endpoints():
    """Kiểm tra endpoints /v1/chat/action/confirm và /v1/behavior/suggestions trên FastAPI."""
    client = TestClient(app)

    # 1. Action Confirm
    res_confirm = client.post(
        "/v1/chat/action/confirm",
        json={
            "sessionId": "sess-test",
            "callId": "call-123",
            "toolName": "start_smart_charging",
            "args": {"vehicle_id": "VF-TEST", "target_soc": 85},
            "confirmed": True,
        },
    )
    assert res_confirm.status_code == 200
    data_confirm = res_confirm.json()
    assert data_confirm["success"] is True
    assert data_confirm["data"]["success"] is False
    assert data_confirm["data"]["code"] == "actionInvalid"

    # Action Cancel
    res_cancel = client.post(
        "/v1/chat/action/confirm",
        json={
            "sessionId": "sess-test",
            "callId": "call-123",
            "toolName": "start_smart_charging",
            "args": {"vehicle_id": "VF-TEST"},
            "confirmed": False,
        },
    )
    assert res_cancel.status_code == 200
    data_cancel = res_cancel.json()
    assert data_cancel["success"] is True
    assert data_cancel["data"]["success"] is False
    assert data_cancel["data"]["code"] == "actionInvalid"

    # 2. Suggestions endpoint
    res_sugg = client.get(
        "/v1/behavior/suggestions?userId=u100&currentSoc=18&chargingStatus=idle"
    )
    assert res_sugg.status_code == 200
    data_sugg = res_sugg.json()
    assert data_sugg["success"] is True
    assert len(data_sugg["data"]) > 0
    assert any(s["ruleId"] == "R001" for s in data_sugg["data"])


# ── Phase 5A Native Function Calling & Execution Tests ───────────────────────

def test_get_gemini_tools_structure():
    """Kiểm tra get_gemini_tools sinh types.Tool hợp lệ cho Google GenAI SDK."""
    from ai_server.chat_tools import get_gemini_tools
    from google.genai import types

    tools = get_gemini_tools()
    assert len(tools) == 1
    assert isinstance(tools[0], types.Tool)
    assert len(tools[0].function_declarations) == 9
    names = [fd.name for fd in tools[0].function_declarations]
    assert "get_battery_status" in names
    assert "start_smart_charging" in names
    assert "schedule_charging" in names


def test_native_gemini_read_tool_auto_execution_loop(monkeypatch):
    """Kiểm tra Gemini gọi read tool -> auto execute -> inject result -> sinh text trả lời."""
    import json
    from unittest.mock import MagicMock
    from google.genai import types
    from ai_server.chat_engine import ChatEngine
    from ai_server.chat_schemas import ChatSendRequest, VehicleContext

    engine = ChatEngine()
    mock_client = MagicMock()

    # Turn 1: Gemini quyết định gọi get_battery_status
    chunk_turn1 = types.GenerateContentResponse(
        candidates=[
            types.Candidate(
                content=types.Content(
                    role="model",
                    parts=[
                        types.Part(
                            function_call=types.FunctionCall(
                                name="get_battery_status",
                                args={"vehicle_id": "VF-EVO200-001"},
                            )
                        )
                    ],
                )
            )
        ]
    )

    # Turn 2: Sau khi nhận tool_result, Gemini trả về câu trả lời tự nhiên
    chunk_turn2 = types.GenerateContentResponse(
        candidates=[
            types.Candidate(
                content=types.Content(
                    role="model",
                    parts=[types.Part.from_text(text="Pin xe Evo200 của bạn đang ở mức 82.5%.")],
                )
            )
        ]
    )

    mock_client.models.generate_content_stream.side_effect = [
        [chunk_turn1],
        [chunk_turn2],
    ]
    engine._client = mock_client
    monkeypatch.setattr("ai_server.chat_engine.DEFAULT_MODEL", "mock-model")

    req = ChatSendRequest(
        message="Pin của mình hiện tại còn bao nhiêu?",
        vehicleContext=VehicleContext(
            vehicleId="VF-EVO200-001",
            model="Evo200",
            currentSoc=82.5,
            currentSoh=98.0,
            batteryTemp=29.0,
        ),
    )

    events = list(engine.stream_chat(req))
    event_types = [e.split("\n")[0] for e in events]

    assert "event: message_start" in event_types
    assert "event: tool_call" in event_types
    assert "event: tool_result" in event_types
    assert "event: text_delta" in event_types
    assert "event: message_end" in event_types

    # Kiểm tra payload tool_result
    result_event = next(e for e in events if e.startswith("event: tool_result\n"))
    result_data = json.loads(result_event.split("data: ")[1].strip())
    assert result_data["toolName"] == "get_battery_status"
    assert result_data["result"]["soc"] == 82.5
    assert result_data["result"]["temperatureC"] == 29.0

    # Kiểm tra mock_client được gọi 2 lần (turn 1 tool call, turn 2 final answer)
    assert mock_client.models.generate_content_stream.call_count == 2


def test_native_gemini_control_tool_safety_gating(monkeypatch):
    """Kiểm tra Gemini gọi control tool -> chặn auto-execute -> sinh ActionConfirmationCard (HITL)."""
    import json
    from unittest.mock import MagicMock
    from google.genai import types
    from ai_server.chat_engine import ChatEngine
    from ai_server.chat_schemas import ChatSendRequest, VehicleContext

    engine = ChatEngine()
    mock_client = MagicMock()

    # Gemini gọi start_smart_charging
    chunk_turn1 = types.GenerateContentResponse(
        candidates=[
            types.Candidate(
                content=types.Content(
                    role="model",
                    parts=[
                        types.Part(
                            function_call=types.FunctionCall(
                                name="start_smart_charging",
                                args={"vehicle_id": "VF-FELIZ-01", "target_soc": 85, "max_amps": 10.0},
                            )
                        )
                    ],
                )
            )
        ]
    )

    mock_client.models.generate_content_stream.return_value = [chunk_turn1]
    engine._client = mock_client
    monkeypatch.setattr("ai_server.chat_engine.DEFAULT_MODEL", "mock-model")

    req = ChatSendRequest(
        message="Hôm nay hãy sạc giúp mình lên 85% nhé",
        vehicleContext=VehicleContext(
            vehicleId="VF-FELIZ-01",
            model="Feliz S",
            currentSoc=45.0,
        ),
    )

    events = list(engine.stream_chat(req))
    event_types = [e.split("\n")[0] for e in events]

    assert "event: message_start" in event_types
    assert "event: function_call" in event_types
    assert "event: text_delta" in event_types
    assert "event: message_end" in event_types

    # Không được có event tool_call hoặc tool_result vì chưa được user xác nhận
    assert "event: tool_call" not in event_types
    assert "event: tool_result" not in event_types

    # Kiểm tra confirmationCard
    card_event = next(e for e in events if e.startswith("event: function_call\n"))
    card_data = json.loads(card_event.split("data: ")[1].strip())
    assert card_data["toolName"] == "start_smart_charging"
    assert card_data["requiresConfirmation"] is True
    assert card_data["args"]["target_soc"] == 85
    assert card_data["confirmationCard"]["maxAmps"] <= 12.0
