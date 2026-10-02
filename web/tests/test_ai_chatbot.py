"""Unit & integration tests for AI Chatbot (Phase 1 MVP)."""
from __future__ import annotations

import json
import pytest
from fastapi.testclient import TestClient

from ai_server.chat_schemas import (
    ChatMessage,
    ChatSendRequest,
    ChatSession,
    VehicleContext,
)
from ai_server.chat_memory import ChatMemoryManager
from ai_server.chat_engine import ChatEngine
from ai_server.main import app


# ── 1. Schema Tests ─────────────────────────────────────────────────────────

def test_vehicle_context_aliases():
    """Kiểm tra alias ngắn 'soc', 'soh' được chuẩn hóa về 'currentSoc', 'currentSoh'."""
    ctx = VehicleContext.model_validate({
        "vehicleId": "VF-FELIZ-001",
        "model": "Feliz S",
        "soc": 85.5,
        "soh": 99.0,
        "temperature": 28.5,
        "odoKm": 12500,
    })
    assert ctx.currentSoc == 85.5
    assert ctx.currentSoh == 99.0
    assert ctx.batteryTemp == 28.5
    assert ctx.model == "Feliz S"


def test_chat_send_request_validation():
    """Kiểm tra validate request gửi tin nhắn."""
    req = ChatSendRequest(
        message="Kiểm tra pin giúp tôi",
        vehicleContext=VehicleContext(model="Evo200", soc=60),
    )
    assert req.message == "Kiểm tra pin giúp tôi"
    assert req.vehicleContext.currentSoc == 60
    assert req.stream is True


# ── 2. Memory Manager Tests ────────────────────────────────────────────────

def test_chat_memory_sliding_window():
    """Kiểm tra sliding window giới hạn 20 tin nhắn gần nhất."""
    mem = ChatMemoryManager(max_context_messages=5)
    sid = mem.get_or_create_session("test-session")

    # Thêm 10 tin nhắn
    for i in range(10):
        role = "user" if i % 2 == 0 else "model"
        mem.add_message(sid, role, f"Message {i}")

    all_msgs = mem.get_all_messages(sid)
    context_msgs = mem.get_context_messages(sid)

    assert len(all_msgs) == 10
    assert len(context_msgs) == 5
    assert context_msgs[0].content == "Message 5"
    assert context_msgs[-1].content == "Message 9"


def test_chat_memory_session_lifecycle():
    """Kiểm tra tạo, liệt kê và xóa session."""
    mem = ChatMemoryManager()
    sid = mem.get_or_create_session()
    mem.add_message(sid, "user", "Xin chào BatteryBot!")

    sessions = mem.list_sessions()
    assert len(sessions) >= 1
    found = next((s for s in sessions if s.sessionId == sid), None)
    assert found is not None
    assert "Xin chào" in found.title

    deleted = mem.delete_session(sid)
    assert deleted is True
    assert len(mem.get_all_messages(sid)) == 0


# ── 3. Chat Engine Tests ───────────────────────────────────────────────────

def test_chat_engine_prompt_builder():
    """Kiểm tra inject context xe vào system prompt."""
    engine = ChatEngine()
    ctx = VehicleContext(
        vehicleId="VF-VENTO-99",
        model="Vento S",
        currentSoc=72.0,
        currentSoh=96.5,
        batteryTemp=31.0,
        chargingStatus="charging",
        odoKm=8400,
        estimatedRangeKm=110.0,
    )
    prompt = engine.build_system_prompt(ctx)
    assert "Vento S" in prompt
    assert "72.0%" in prompt
    assert "96.5%" in prompt
    assert "31.0°C" in prompt
    assert "charging" in prompt
    assert "BatteryBot" in prompt


def test_chat_engine_stream_generation():
    """Kiểm tra sinh SSE stream với định dạng chuẩn."""
    engine = ChatEngine()
    req = ChatSendRequest(
        message="Pin của mình còn đi được bao xa?",
        vehicleContext=VehicleContext(model="Theon S", currentSoc=80.0),
    )
    events = list(engine.stream_chat(req))
    assert len(events) >= 3

    # Phải bắt đầu bằng event: message_start
    assert events[0].startswith("event: message_start\n")
    start_data = json.loads(events[0].split("data: ")[1].strip())
    assert "messageId" in start_data
    assert "sessionId" in start_data

    # Phải có các text_delta
    deltas = [e for e in events if e.startswith("event: text_delta\n")]
    assert len(deltas) > 0

    # Phải kết thúc bằng event: message_end
    assert events[-1].startswith("event: message_end\n")
    end_data = json.loads(events[-1].split("data: ")[1].strip())
    assert "messageId" in end_data
    assert "usage" in end_data


# ── 4. FastAPI Endpoint Integration Tests ──────────────────────────────────

def test_api_chat_send_endpoint():
    """Kiểm tra gọi endpoint /v1/chat/send qua TestClient."""
    client = TestClient(app)
    payload = {
        "message": "Hướng dẫn cách sạc xe",
        "vehicleContext": {
            "model": "Klara S",
            "soc": 45.0,
        },
    }
    resp = client.post("/v1/chat/send", json=payload)
    assert resp.status_code == 200
    assert "text/event-stream" in resp.headers["content-type"]
    text = resp.text
    assert "event: message_start" in text
    assert "event: text_delta" in text
    assert "event: message_end" in text


def test_api_chat_sessions_and_feedback():
    """Kiểm tra các endpoints metadata /v1/chat/sessions và feedback."""
    client = TestClient(app)

    # 1. Gửi tin nhắn tạo session
    resp = client.post("/v1/chat/send", json={"message": "Pin hôm nay thế nào?"})
    assert resp.status_code == 200

    # 2. Lấy danh sách session
    sessions_resp = client.get("/v1/chat/sessions")
    assert sessions_resp.status_code == 200
    s_data = sessions_resp.json()
    assert s_data["success"] is True
    assert len(s_data["data"]) >= 1
    session_id = s_data["data"][0]["sessionId"]

    # 3. Lấy chi tiết session
    detail_resp = client.get(f"/v1/chat/sessions/{session_id}")
    assert detail_resp.status_code == 200
    d_data = detail_resp.json()
    assert d_data["success"] is True
    assert len(d_data["data"]) >= 2  # user msg + bot reply

    # 4. Gửi feedback
    fb_resp = client.post(
        "/v1/chat/feedback",
        json={
            "sessionId": session_id,
            "messageId": d_data["data"][-1]["id"] or "msg-123",
            "rating": "like",
        },
    )
    assert fb_resp.status_code == 200
    assert fb_resp.json()["success"] is True

    # 5. Xóa session
    del_resp = client.delete(f"/v1/chat/sessions/{session_id}")
    assert del_resp.status_code == 200
    assert del_resp.json()["data"]["deleted"] is True
