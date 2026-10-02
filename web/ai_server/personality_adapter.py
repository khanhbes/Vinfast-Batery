"""Adaptive Personality Engine for AI Chatbot (Phase 5B).

Dynamically adjusts the AI system prompt tone and verbosity based on:
1. Cumulative user feedback (thumbs up / thumbs down ratio)
2. Declared preferences in Behavior Profile (preferred response length)
3. Interaction patterns and sentiment
"""

from __future__ import annotations

import logging
from enum import Enum
from typing import Any, Dict, Optional

logger = logging.getLogger("ai_server.personality_adapter")


class PersonalityStyle(str, Enum):
    CONCISE = "concise"
    DETAILED = "detailed"
    FRIENDLY = "friendly"
    PROFESSIONAL = "professional"


STYLE_PROMPT_MODIFIERS: Dict[PersonalityStyle, str] = {
    PersonalityStyle.CONCISE: """
## Phong cách phản hồi: NGẮN GỌN (Concise)
- Người dùng yêu thích câu trả lời ngắn gọn, đi thẳng vào trọng tâm.
- Giới hạn trong 1–3 câu súc tích, nêu bật số liệu chính, tránh giải thích lan man dài dòng.
- Định dạng bullet point ngắn nếu có nhiều thông số.
""",
    PersonalityStyle.DETAILED: """
## Phong cách phản hồi: CHI TIẾT & CHUYÊN SÂU (Detailed)
- Người dùng quan tâm sâu sắc tới cơ chế kỹ thuật và giải thích khoa học.
- Hãy phân tích cụ thể các thông số pin LFP, nguyên nhân ảnh hưởng tuổi thọ cell pin và hướng dẫn từng bước.
- Cung cấp số liệu định lượng (Wh/km, chu kỳ sạc, nhiệt độ lý tưởng).
""",
    PersonalityStyle.FRIENDLY: """
## Phong cách phản hồi: THÂN THIỆN & ẤM ÁP (Friendly)
- Tương tác với giọng điệu vui tươi, gần gũi, xưng hô "mình" hoặc "BatteryBot" và gọi người dùng là "bạn".
- Sử dụng các emoji sinh động (⚡, 🔋, 🛵, ✨) tạo cảm giác như một người bạn đồng hành tin cậy trên mọi nẻo đường.
- Động viên người dùng khi pin khỏe hoặc hành trình tiết kiệm điện.
""",
    PersonalityStyle.PROFESSIONAL: """
## Phong cách phản hồi: CHUẨN MỰC & CHUYÊN NGHIỆP (Professional)
- Sử dụng văn phong chuẩn mực kỹ thuật, chính xác, trang trọng.
- Tập trung vào quy chuẩn an toàn điện áp, bảo hành chính hãng và quy trình vận hành xe điện VinFast.
""",
}


class PersonalityAdapter:
    """Tự động điều chỉnh phong cách và giọng văn của BatteryBot theo hành vi người dùng."""

    def determine_style(self, behavior_profile: Optional[Any] = None) -> PersonalityStyle:
        """Xác định phong cách tối ưu dựa trên hồ sơ hành vi và thống kê phản hồi."""
        if not behavior_profile:
            return PersonalityStyle.CONCISE

        pref = getattr(behavior_profile, "chatPreferences", None)
        if not pref and isinstance(behavior_profile, dict):
            pref = behavior_profile.get("chatPreferences", {})

        feedback_stats = getattr(pref, "feedbackStats", {}) if hasattr(pref, "feedbackStats") else (pref.get("feedbackStats", {}) if isinstance(pref, dict) else {})
        preferred_len = getattr(pref, "preferredResponseLength", "concise") if hasattr(pref, "preferredResponseLength") else (pref.get("preferredResponseLength", "concise") if isinstance(pref, dict) else "concise")

        thumbs_up = int(feedback_stats.get("totalThumbsUp", 0))
        thumbs_down = int(feedback_stats.get("totalThumbsDown", 0))
        total_feedback = thumbs_up + thumbs_down

        # 1. Nếu có nhiều phản hồi không hài lòng (dislike), ưu tiên phong cách súc tích tránh làm phiền
        if thumbs_down >= 3 and thumbs_down > thumbs_up:
            return PersonalityStyle.CONCISE

        # 2. Nếu người dùng chọn rõ ràng là muốn chi tiết
        if preferred_len == "detailed":
            return PersonalityStyle.DETAILED

        # 3. Nếu người dùng tương tác tích cực và đánh giá cao (nhiều thumbs up)
        if thumbs_up >= 8:
            return PersonalityStyle.FRIENDLY
        elif thumbs_up >= 4 and preferred_len == "detailed":
            return PersonalityStyle.DETAILED

        # 4. Mặc định là súc tích (phù hợp nhất với màn hình di động)
        return PersonalityStyle.CONCISE

    def get_prompt_modifier(self, behavior_profile: Optional[Any] = None) -> str:
        """Tạo đoạn văn bản chỉ dẫn phong cách để đưa vào System Prompt."""
        style = self.determine_style(behavior_profile)
        return STYLE_PROMPT_MODIFIERS.get(style, STYLE_PROMPT_MODIFIERS[PersonalityStyle.CONCISE])


# Global singleton instance
personality_adapter = PersonalityAdapter()
