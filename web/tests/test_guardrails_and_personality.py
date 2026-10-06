"""Tests for AI Chatbot Guardrails & Adaptive Personality (Phase 5B)."""
from __future__ import annotations

import json
from unittest.mock import MagicMock
import pytest

from ai_server.chat_guardrails import (
    ChatGuardrails,
    MAX_SAFE_AMPS,
    MAX_SAFE_WATTS,
    chat_guardrails,
)
from ai_server.personality_adapter import (
    PersonalityAdapter,
    PersonalityStyle,
    personality_adapter,
)
from ai_server.chat_schemas import (
    BehaviorProfile,
    ChatPreferences,
    ChatSendRequest,
    VehicleContext,
)
from ai_server.chat_engine import ChatEngine


# ── 1. Guardrails Electrical Safety Tests ────────────────────────────────────

def test_guardrails_max_amps_sanitized():
    """Kiểm tra phát hiện và che dòng sạc vượt ngưỡng an toàn 12A."""
    text = "Để sạc nhanh, bạn hãy đặt dòng sạc ở mức 16A hoặc 20 Ampe nhé."
    sanitized, violations = chat_guardrails.validate_electrical_safety(text)
    assert len(violations) >= 1
    assert any("GR-ELEC-001" in v for v in violations)
    assert "16A" not in sanitized
    assert "20 Ampe" not in sanitized
    assert f"tối đa an toàn {MAX_SAFE_AMPS:g}A" in sanitized


def test_guardrails_max_watts_sanitized():
    """Kiểm tra phát hiện và che công suất vượt ngưỡng 2500W (hoặc 2.5 kW)."""
    text = "Bộ sạc hỗ trợ công suất lên tới 3500W (tương đương 3.5 kW)."
    sanitized, violations = chat_guardrails.validate_electrical_safety(text)
    assert len(violations) >= 1
    assert any("GR-ELEC-002" in v for v in violations)
    assert "3500W" not in sanitized
    assert "3.5 kW" not in sanitized
    assert "tối đa an toàn 2500W" in sanitized


def test_guardrails_high_temp_charging_warning():
    """Kiểm tra cảnh báo an toàn khi có đề xuất cắm sạc ở nhiệt độ cao > 45°C."""
    text = "Pin xe đang ở mức 48°C, bạn có thể cắm sạc ngay bây giờ."
    sanitized, violations = chat_guardrails.validate_electrical_safety(text)
    assert len(violations) >= 1
    assert any("GR-TEMP-001" in v for v in violations)
    assert "Cảnh báo an toàn" in sanitized


# ── 2. Guardrails Vehicle Spec Hallucination Defense Tests ───────────────────

def test_guardrails_spec_range_hallucination_detected():
    """Kiểm tra phát hiện và bổ sung disclaimer khi LLM bịa quãng đường bất khả thi."""
    # Feliz S có catalog range ~198km, nói 380km là ảo giác
    text = "Chiếc VinFast Feliz S này có thể chạy liên tục tới 380 km chỉ với một lần sạc đầy."
    sanitized, violations = chat_guardrails.validate_vehicle_specs(
        text, vehicle_context={"model": "Feliz S"}
    )
    assert len(violations) >= 1
    assert any("GR-SPEC-001" in v for v in violations)
    assert "Theo công bố chính thức từ VinFast" in sanitized
    assert "198 km" in sanitized


def test_guardrails_normal_range_passes_without_violation():
    """Kiểm tra quãng đường trong ngưỡng catalog hợp lý không bị phạt."""
    text = "Với 80% pin, chiếc Evo200 của bạn đi được khoảng 160 km trong đô thị."
    sanitized, violations = chat_guardrails.validate_vehicle_specs(
        text, vehicle_context={"model": "Evo200"}
    )
    assert len(violations) == 0
    assert sanitized == text


# ── 3. Guardrails PII Auto-Redaction Tests ────────────────────────────────────

def test_guardrails_pii_phone_and_cccd_redacted():
    """Kiểm tra tự động làm mờ số điện thoại và số CCCD/CMND cá nhân."""
    text = (
        "Vui lòng liên hệ chủ xe qua SĐT 0912345678 hoặc +84987654321, "
        "số định danh CCCD: 001200001234."
    )
    res = chat_guardrails.apply_guardrails(text)
    assert res.is_safe is False
    assert len(res.violations) >= 2
    assert "0912345678" not in res.sanitized_text
    assert "+84987654321" not in res.sanitized_text
    assert "001200001234" not in res.sanitized_text
    assert "[Số điện thoại đã ẩn]" in res.sanitized_text
    assert "[Số định danh đã ẩn]" in res.sanitized_text


# ── 4. Adaptive Personality Tests ────────────────────────────────────────────

def test_personality_adapter_default_is_concise():
    """Mặc định khi chưa có feedback là phong cách ngắn gọn."""
    profile = BehaviorProfile(userId="u1")
    style = personality_adapter.determine_style(profile)
    assert style == PersonalityStyle.CONCISE


def test_personality_adapter_prefers_detailed():
    """Khi người dùng chọn preferredResponseLength là detailed."""
    profile = BehaviorProfile(
        userId="u1",
        chatPreferences=ChatPreferences(preferredResponseLength="detailed"),
    )
    style = personality_adapter.determine_style(profile)
    assert style == PersonalityStyle.DETAILED


def test_personality_adapter_switches_to_friendly_on_high_thumbs_up():
    """Khi người dùng tích cực tương tác và đánh giá cao (thumbs up >= 8)."""
    profile = BehaviorProfile(
        userId="u1",
        chatPreferences=ChatPreferences(
            feedbackStats={"totalThumbsUp": 9, "totalThumbsDown": 0}
        ),
    )
    style = personality_adapter.determine_style(profile)
    assert style == PersonalityStyle.FRIENDLY


def test_personality_adapter_falls_back_to_concise_on_high_thumbs_down():
    """Khi có nhiều dislike (thumbs down >= 3 và > thumbs up), tự thu gọn súc tích."""
    profile = BehaviorProfile(
        userId="u1",
        chatPreferences=ChatPreferences(
            preferredResponseLength="detailed",
            feedbackStats={"totalThumbsUp": 1, "totalThumbsDown": 4},
        ),
    )
    style = personality_adapter.determine_style(profile)
    assert style == PersonalityStyle.CONCISE


def test_chat_engine_prompt_incorporates_personality_modifier():
    """Kiểm tra build_system_prompt chứa chỉ dẫn phong cách của PersonalityAdapter."""
    engine = ChatEngine()
    profile = BehaviorProfile(
        userId="u-friendly",
        chatPreferences=ChatPreferences(
            feedbackStats={"totalThumbsUp": 10, "totalThumbsDown": 0}
        ),
    )
    prompt = engine.build_system_prompt(
        ctx=VehicleContext(model="Evo200", currentSoc=70),
        behavior=profile,
    )
    assert "Phong cách phản hồi: THÂN THIỆN & ẤM ÁP" in prompt
    assert "BatteryBot" in prompt


# ── 5. Stream Chat Integration With Guardrails Tests ─────────────────────────

def test_stream_chat_applies_guardrails_and_flags_violations(monkeypatch):
    """Kiểm tra stream_chat chạy guardrails kiểm duyệt và đánh dấu trong usage message_end."""
    engine = ChatEngine()
    # Mock client trả về văn bản chứa vi phạm dòng sạc 16A
    mock_client = MagicMock()
    from google.genai import types

    mock_resp = types.GenerateContentResponse(
        candidates=[
            types.Candidate(
                content=types.Content(
                    role="model",
                    parts=[types.Part.from_text(text="Bạn có thể thử sạc với dòng sạc 18A để tiết kiệm thời gian.")],
                )
            )
        ]
    )
    mock_client.models.generate_content_stream.return_value = [mock_resp]
    engine._client = mock_client
    monkeypatch.setattr("ai_server.chat_engine.DEFAULT_MODEL", "mock-model")

    req = ChatSendRequest(
        message="Có cách nào sạc xe nhanh hơn không?",
        vehicleContext=VehicleContext(model="Feliz S", currentSoc=30),
    )

    events = list(engine.stream_chat(req))
    end_event = next(e for e in events if e.startswith("event: message_end\n"))
    end_data = json.loads(end_event.split("data: ")[1].strip())

    # Guardrails phải phát hiện vi phạm và ghi nhận vào usage
    assert end_data["usage"]["guardrailPassed"] is False
    assert len(end_data["usage"]["violations"]) >= 1
    assert any("GR-ELEC-001" in v for v in end_data["usage"]["violations"])
    sent = "".join(json.loads(e.split("data: ")[1])["delta"] for e in events if e.startswith("event: text_delta"))
    assert "18A" not in sent  # Filter before delivery, not after the user sees it.
