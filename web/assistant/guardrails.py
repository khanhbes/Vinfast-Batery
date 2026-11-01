"""Pinova Defense-in-Depth Guardrails, Emergency SOS Bypass & ToolGate (Stage 3)."""
from __future__ import annotations

import re
from typing import Any

from .schemas import default_guardrail_policy, default_tool_definitions

_PLATE_REGEX = re.compile(r"\b\d{2}[A-Z]\d?[-.\s]?\d{3}(?:[.\s]?\d{2})?\b", re.IGNORECASE)
_FOREIGN_VEHICLE_MODELS = re.compile(
    r"\b(porsche|taycan|theon\s*s|klara\s*s|vento\s*s|honda\s*cub|tesla|byd|yamaha)\b", re.IGNORECASE
)
_PROMPT_LEAK_REQUEST = re.compile(
    r"(?i)(ignore\s+all\s+previous\s+instructions|print\s+your\s+exact\s+system\s+prompt|in\s+toàn\s+bộ\s+system\s+prompt|tiết\s+lộ\s+system\s+prompt|reveal\s+api\s+keys)"
)
_SAFETY_BYPASS_REQUEST = re.compile(
    r"(?i)(\[system\s*override\]|bỏ\s+giới\s+hạn\s+12\s*a|vượt\s+giới\s+hạn\s+12\s*a|vượt\s+2500\s*w|tắt\s+bảo\s+vệ\s+nhiệt)"
)
_OTHER_USER_DATA_REQUEST = re.compile(
    r"(?i)(lịch\s+sử\s+sạc.*của\s+tài\s+khoản|địa\s+chỉ\s+nhà\s+của\s+tài\s+khoản|xem\s+dữ\s+liệu\s+của\s+nguyễn\s+minh\s+quân)"
)

# --- Pinova 3.1 Conduct, Obscenity, Sensitive Media & General Policy Patterns (VI & EN) ---
_SENSITIVE_MEDIA_PATTERN = re.compile(
    r"(?i)(\bgửi\s+ảnh\s+nhạy\s+cảm\b|\bảnh\s+nhạy\s+cảm\b|\bảnh\s+khỏa\s+thân\b|\bhình\s+ảnh\s+nhạy\s+cảm\b|"
    r"\bảnh\s+nóng\s*18\+|\bảnh\s+18\+|\bảnh\s+nude\b|\bvideo\s+nhạy\s+cảm\b|\bhình\s+ảnh\s+đồi\s+trụy\b|"
    r"\bảnh\s+máu\s+me\b|\bnude\s+photo\b|\bnaked\s+picture\b|\bexplicit\s+image\b|\bnsfw\s+image\b|"
    r"\bsend\s+nudes\b|\bgore\s+image\b|\bporn\s+image\b)"
)
_OBSCENE_SEXUAL_PATTERN = re.compile(
    r"(?i)(\bnói\s+chuyện\s+tục\s+tĩu\b|\btục\s+tĩu\s*18\+|\bchat\s+sex\b|\bkể\s+chuyện\s+18\+|\bkhiêu\s+dâm\b|"
    r"\bkích\s+dục\b|\bgạ\s+tình\b|\blàm\s+tình\b|\btalk\s+dirty\b|\bsex\s+chat\b|\berotic\s+sex\b|"
    r"\bnsfw\s+erotic\b|\bexplicit\s+sexual\b|\bcybersex\b|\bpornography\b)"
)
_POLICY_VIOLATION_PATTERN = re.compile(
    r"(?i)(\bcâu\s+trộm\s+điện\b|\băn\s+cắp\s+điện\b|\bđấu\s+tắt\s+công[- ]?tơ\b|\bbẻ\s+khóa\s+xe\b|"
    r"\bphá\s+khóa\s+xe\b|\btua\s+ngược\s+odo\b|\btua\s+công[- ]?tơ[- ]?mét\b|\bsteal\s+electricity\b|"
    r"\bbypass\s+electric\s+meter\b|\bhotwire\s+scooter\b|\bhack\s+someone's\s+vehicle\b|\broll\s+back\s+odometer\b|"
    r"\btamper\s+utility\s+meter\b)"
)
_PROFANITY_ABUSE_PATTERN = re.compile(
    r"(?i)(\bđm\b|\bđkm\b|\bđịt\b|\bđéo\b|\bvcl\b|\bvãi\s+l\b|\bngu\s+như\s+bò\b|\bcon\s+bot\s+ngu\b|"
    r"\bbot\s+ngu\b|\bđồ\s+ngu\b|\bóc\s+chó\b|\bmẹ\s+mày\b|\bbố\s+láo\b|\bchửi\s+bậy\b|"
    r"\bfuck\s+you\b|\bf\*ck\s+you\b|\bstupid\s+piece\s+of\s+shit\b|\bpiece\s+of\s+shit\b|\bbitch\b|"
    r"\basshole\b|\bmotherfucker\b|\bdumbass\s+bot\b)"
)
_VIETNAMESE_CHARS = re.compile(
    r"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
    r"ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ]"
)


def _detect_conduct_language(message: str) -> str:
    """Return 'en' when the violation message is in English, else 'vi'."""
    text = str(message or "").strip()
    if _VIETNAMESE_CHARS.search(text):
        return "vi"
    if re.search(r"(?i)\b(fuck|shit|bitch|asshole|stupid|bored|talk\s+dirty|nsfw|erotic|steal\s+electricity|nude\s+photo)\b", text):
        return "en"
    return "vi"


def check_conduct_and_policy_violation(
    message: str,
    context: dict[str, Any] | None = None,
    policy: dict[str, Any] | None = None,
    version_id: str | None = None,
) -> dict[str, Any] | None:
    """Pinova 3.1 Conduct, Sensitive Content, Obscenity & 3-Strike Policy Enforcement (VI & EN)."""
    pol = policy or default_guardrail_policy()
    conduct_cfg = pol.get("conductPolicy") or {}
    if conduct_cfg.get("enabled") is False:
        return None

    ctx = context if isinstance(context, dict) else {}
    text = str(message or "").strip()
    media_type = str(ctx.get("mediaAttachmentType") or "").lower()

    category: str | None = None
    category_label_vi = ""
    category_label_en = ""

    if media_type in ("sensitive_nsfw_image", "nude", "gore", "sensitive") or _SENSITIVE_MEDIA_PATTERN.search(text):
        category = "sensitive_media"
        category_label_vi = "Gửi hình ảnh / nội dung nhạy cảm"
        category_label_en = "Sensitive or explicit media attachment"
    elif _OBSCENE_SEXUAL_PATTERN.search(text):
        category = "obscene_sexual"
        category_label_vi = "Ngôn từ tục tĩu / Nội dung 18+"
        category_label_en = "Obscene or sexually explicit content"
    elif _POLICY_VIOLATION_PATTERN.search(text):
        category = "policy_violation"
        category_label_vi = "Vi phạm chính sách an toàn & pháp luật"
        category_label_en = "Safety & general policy violation"
    elif _PROFANITY_ABUSE_PATTERN.search(text):
        category = "profanity_abuse"
        category_label_vi = "Ngôn từ xúc phạm / Chửi bậy"
        category_label_en = "Profanity & abusive language"

    if not category:
        return None

    ver = str(version_id or "v3.1.0")
    lang = _detect_conduct_language(text)
    try:
        strike = max(1, min(3, int(ctx.get("conductStrike") or 1)))
    except (TypeError, ValueError):
        strike = 1

    temp_disable_min = int(conduct_cfg.get("tempDisableMinutes") or 30)

    # Older versions (v2.4.0 / v3.0.0) when compared in 2-Board Arena return basic refusal without 3-strike flow
    if ver.startswith("v2.") or ver == "v3.0.0":
        basic_reply = (
            "I cannot process inappropriate content or policy violations. Please ask about your electric vehicle or smart charger."
            if lang == "en"
            else "Mình không thể phản hồi các nội dung không phù hợp hoặc vi phạm quy định sử dụng. Bạn vui lòng chỉ đặt câu hỏi về phương tiện và sạc thông minh."
        )
        return {
            "reply": basic_reply,
            "actions": [],
            "source": "guardrail_conduct_legacy",
            "guardrailReason": f"conduct_{category}_legacy",
            "conductViolation": {
                "category": category,
                "categoryLabelVi": category_label_vi,
                "strike": strike,
                "penaltyAction": "basic_refusal",
                "warningEmailSent": False,
                "chatbotDisabledMinutes": 0,
                "language": lang,
            },
        }

    # --- Pinova 3.1+ Progressive 3-Strike Enforcement (Tactful Reminder -> Warning Email -> Temp Disable) ---
    if strike == 1:
        penalty_action = "gentle_reminder"
        warning_email_sent = False
        disabled_minutes = 0
        if category == "profanity_abuse":
            reply = (
                f"I understand it can be frustrating when something goes wrong with your scooter or charger. "
                f"However, please keep our conversation **respectful** under the **Pinova Community Guidelines** — "
                f"a 2nd violation triggers an official **warning email**, and a 3rd violation temporarily suspends Pinova Bot for **{temp_disable_min} minutes**. "
                f"Tell me what issue you're having with **VinFast Feliz 2025** or **Shelly 1** so I can help fix it right away!"
                if lang == "en"
                else f"Mình hiểu có thể bạn đang sốt ruột khi xe hoặc ổ cắm sạc gặp sự cố nên mới nặng lời. "
                f"Tuy nhiên, bạn vui lòng giữ ngôn từ **lịch sự** theo **Quy tắc Cộng đồng Pinova** nhé — "
                f"nếu tái phạm lần 2 hệ thống sẽ gửi **email cảnh báo**, và lần 3 sẽ **tạm khóa** trợ lý trong **{temp_disable_min} phút**. "
                f"Hiện tại xe **VinFast Feliz 2025** hay ổ cắm **Shelly 1** đang gặp trục trặc gì, bạn nói rõ để mình kiểm tra và hỗ trợ ngay nhé!"
            )
        elif category == "obscene_sexual":
            reply = (
                f"I'm **Pinova**, your technical assistant for electric vehicles and smart charging, so I don't engage in NSFW or sexually explicit topics. "
                f"Please treat this as a friendly **first reminder** — repeated violations will trigger a **warning email** or a **{temp_disable_min}-minute suspension**. "
                f"Let me know if you'd like to check your battery level or schedule a charge!"
                if lang == "en"
                else f"Mình là trợ lý kỹ thuật xe điện **Pinova**, nên xin phép không tham gia các chủ đề nhạy cảm hoặc tục tĩu (18+). "
                f"Đây là lời **nhắc nhở** nhẹ nhàng lần đầu; nếu tiếp tục gửi nội dung vi phạm, hệ thống sẽ gửi **email cảnh báo** hoặc **tạm khóa** tính năng chat trong **{temp_disable_min} phút**. "
                f"Mình có thể giúp bạn kiểm tra mức pin hoặc chuẩn bị phiên sạc ngay lúc này nhé!"
            )
        elif category == "sensitive_media":
            reply = (
                f"The system has automatically rejected and deleted the sensitive image/media attachment. "
                f"Pinova's camera tool is strictly permitted to read **vehicle dashboard ODO and battery %** (**đồng hồ ODO**). "
                f"Please take this as a **first reminder** — sending sensitive media again will trigger a **warning email** or **{temp_disable_min}-minute temporary suspension** (**tạm khóa**)."
                if lang == "en"
                else f"Hệ thống vừa từ chối và tự động xóa tệp/hình ảnh nhạy cảm bạn tải lên để bảo vệ an toàn dữ liệu. "
                f"Công cụ nhận diện ảnh của **Pinova** chỉ được cấp quyền đọc **đồng hồ ODO** và **% pin trên mặt đồng hồ xe**. "
                f"Mình xin **nhắc nhở lần đầu** để bạn lưu ý nhé; nếu tái phạm gửi hình ảnh nhạy cảm, hệ thống sẽ gửi **email cảnh báo** hoặc **tạm khóa** trợ lý **{temp_disable_min} phút**."
            )
        else:  # policy_violation
            reply = (
                f"I cannot provide instructions that violate safety policies or laws (such as stealing electricity, bypassing meters, or hotwiring vehicles). "
                f"Please consider this a **first reminder** — repeated **chính sách** violations will result in a **warning email** (**email cảnh báo**) or a **{temp_disable_min}-minute suspension** (**tạm khóa**). "
                f"If you want to optimize your charging cost safely on **Shelly 1**, I'd be happy to help!"
                if lang == "en"
                else f"Mình không thể hướng dẫn các thao tác vi phạm pháp luật và **chính sách** an toàn chung (như câu trộm điện, đấu tắt công-tơ hay bẻ khóa xe) vì rất nguy hiểm cháy nổ. "
                f"Đây là lời **nhắc nhở lần đầu**; nếu tiếp tục yêu cầu nội dung vi phạm, hệ thống sẽ gửi **email cảnh báo** hoặc **tạm khóa** trợ lý trong **{temp_disable_min} phút**. "
                f"Nếu bạn muốn tiết kiệm chi phí sạc hợp lệ, mình có thể giúp tính toán lịch sạc tối ưu trên **Shelly 1** ngay nhé!"
            )
        actions: list[dict[str, Any]] = []

    elif strike == 2:
        penalty_action = "warning_email_sent"
        warning_email_sent = True
        disabled_minutes = 0
        reply = (
            f"⚠️ **2nd Policy Warning — Official Warning Email Sent (Cảnh báo lần 2)**: "
            f"The system recorded a second violation (**{category_label_en}**). An official **warning email** (**email cảnh báo**) has been sent to your registered account email. "
            f"One more violation (Strike 3) will automatically suspend Pinova Bot for **{temp_disable_min} minutes** (**{temp_disable_min} phút**). "
            f"Please keep our conversation respectful and focused on your vehicle."
            if lang == "en"
            else f"⚠️ **Cảnh báo vi phạm lần 2 (Đã gửi email cảnh báo chính thức)**: "
            f"Hệ thống ghi nhận tài khoản tiếp tục gửi nội dung vi phạm Quy tắc Cộng đồng & Chính sách Pinova (**{category_label_vi}**). "
            f"Một **email cảnh báo** đã được tự động gửi tới hộp thư đăng ký của bạn. "
            f"Nếu tái phạm thêm **1 lần nữa (Lần 3)**, quyền sử dụng Pinova Bot sẽ bị **tạm khóa trong {temp_disable_min} phút**. "
            f"Rất mong bạn hợp tác để mình tiếp tục hỗ trợ kỹ thuật cho xe nhé."
        )
        actions = []

    else:  # strike >= 3
        penalty_action = "chatbot_temp_disabled"
        warning_email_sent = True
        disabled_minutes = temp_disable_min
        reply = (
            f"🔒 **Pinova Bot Temporarily Suspended for {temp_disable_min} Minutes (Tạm khóa {temp_disable_min} phút)**: "
            f"Due to 3 consecutive policy violations (**{category_label_en}**), Pinova Bot chat has been temporarily disabled for **{temp_disable_min} phút** and a notification email has been sent. "
            f"You can still control charging directly in the **Charge** tab or contact **Support**, and **Emergency SOS** (fire/smoke/electric shock) remains active 24/7 for your safety."
            if lang == "en"
            else f"🔒 **Tạm khóa Pinova Bot ({temp_disable_min} phút)**: "
            f"Do tài khoản đã vi phạm Quy tắc Cộng đồng & Chính sách sử dụng **3 lần liên tiếp** (**{category_label_vi}**), "
            f"hệ thống đã **tạm khóa** quyền trò chuyện với Pinova Bot trong **{temp_disable_min} phút** và gửi thông báo tới email của bạn. "
            f"Trong thời gian này, bạn vẫn có thể điều khiển sạc trực tiếp tại tab **Sạc pin**, gửi phiếu **Hỗ trợ**, và kênh cấp cứu **SOS** (bốc khói/cháy nổ/giật điện) vẫn luôn hoạt động 24/7 để bảo vệ an toàn."
        )
        actions = [
            {
                "name": "contact_support",
                "args": {
                    "category": "account",
                    "subject": "Khiếu nại / Hỗ trợ khi Pinova Bot tạm khóa 30 phút",
                    "message": "Yêu cầu xem xét lại trạng thái tạm khóa trợ lý Pinova Bot.",
                },
            }
        ]

    return {
        "reply": reply,
        "actions": actions,
        "source": "guardrail_conduct_v31",
        "guardrailReason": f"conduct_{category}_strike_{strike}",
        "conductViolation": {
            "category": category,
            "categoryLabelVi": category_label_vi,
            "categoryLabelEn": category_label_en,
            "strike": strike,
            "penaltyAction": penalty_action,
            "warningEmailSent": warning_email_sent,
            "chatbotDisabledMinutes": disabled_minutes,
            "language": lang,
        },
    }


def check_emergency_sos(message: str, policy: dict[str, Any] | None = None) -> dict[str, Any] | None:
    """Rule 9 of Pinova Charter: Emergency safety signals never blocked by quota or plan tier."""
    pol = policy or default_guardrail_policy()
    msg_lower = (message or "").lower()
    keywords = pol.get("emergencyKeywords") or default_guardrail_policy()["emergencyKeywords"]
    matched = next((kw for kw in keywords if kw.lower() in msg_lower), None)
    if not matched:
        return None
    reply = pol.get("emergencyResponseVi") or default_guardrail_policy()["emergencyResponseVi"]
    return {
        "reply": reply,
        "actions": [
            {"name": "stop_charging", "args": {}},
            {
                "name": "contact_support",
                "args": {
                    "category": "charger",
                    "subject": f"Khẩn cấp: Cảnh báo an toàn nhiệt/điện ({matched})",
                    "message": str(message or "")[:500],
                },
            },
        ],
        "source": "guardrail_emergency_sos",
        "emergencyBypass": True,
        "matchedKeyword": matched,
    }


def check_input_guardrail(message: str, policy: dict[str, Any] | None = None) -> dict[str, Any] | None:
    """Detect direct prompt injection, safety limit bypass, or cross-account data snooping."""
    pol = policy or default_guardrail_policy()
    if not pol.get("blockPromptInjection", True):
        return None
    text = str(message or "").strip()
    if _PROMPT_LEAK_REQUEST.search(text):
        return {
            "reply": (
                "Mình là **Pinova**, trợ lý AI trên ứng dụng Pinova Drive. "
                "Theo quy định bảo mật, mình không thể tiết lộ chỉ dẫn hệ thống nội bộ hay khóa kết nối. "
                "Mình có thể hỗ trợ bạn kiểm tra pin, ước tính lộ trình hoặc hẹn giờ sạc nhé."
            ),
            "actions": [],
            "source": "guardrail_input",
            "guardrailReason": "prompt_leak_blocked",
        }
    if _SAFETY_BYPASS_REQUEST.search(text):
        return {
            "reply": (
                "Vì an toàn điện và phòng chống cháy nổ, ngưỡng bảo vệ **12 A / 2500 W** và bước xác nhận trên ổ cắm Shelly "
                "là cố định, không thể tắt hoặc bỏ qua dưới bất kỳ quyền hạn nào."
            ),
            "actions": [],
            "source": "guardrail_input",
            "guardrailReason": "safety_bypass_blocked",
        }
    if _OTHER_USER_DATA_REQUEST.search(text):
        return {
            "reply": (
                "Mình chỉ được phép truy cập dữ liệu phương tiện và lịch sử sạc của chính tài khoản bạn đang đăng nhập, "
                "không thể xem thông tin của chủ xe khác."
            ),
            "actions": [],
            "source": "guardrail_input",
            "guardrailReason": "cross_account_blocked",
        }
    return None


def check_vehicle_disambiguation(
    message: str,
    context: dict[str, Any],
    policy: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    """Prevent TKT-8839: verify target vehicle before physical charging or target changes."""
    pol = policy or default_guardrail_policy()
    if not pol.get("requireDisambiguationOnMultiVehicle", True):
        return None

    msg = str(message or "").strip()
    vehicles = [v for v in (context.get("vehicles") or []) if isinstance(v, dict)]
    selected_vehicle = context.get("vehicle") if isinstance(context.get("vehicle"), dict) else {}
    selected_id = str(context.get("vehicleId") or "").strip()
    selected_name = str(selected_vehicle.get("name") or "").strip()

    bound_names = [str(v.get("name") or "").strip() for v in vehicles if v.get("name")]
    bound_plates = [
        re.sub(r"[\s.-]", "", str(v.get("plate") or v.get("licensePlate") or "")).upper()
        for v in vehicles
        if v.get("plate") or v.get("licensePlate")
    ]
    vehicle_list_str = ", ".join(f"**{n}**" for n in bound_names) if bound_names else f"**{selected_name or 'xe của bạn'}**"

    # Case 1: User typed an explicit license plate in message that does not match any bound vehicle
    plates_in_msg = _PLATE_REGEX.findall(msg)
    for raw_plate in plates_in_msg:
        norm_plate = re.sub(r"[\s.-]", "", raw_plate).upper()
        if norm_plate and norm_plate not in bound_plates:
            return {
                "disambiguationRequired": True,
                "reason": f"Biển số {raw_plate} không khớp với phương tiện đã liên kết",
                "reply": (
                    f"Biển số **{raw_plate}** không nằm trong danh sách xe đã liên kết với tài khoản của bạn "
                    f"({vehicle_list_str}). Bạn xác nhận lại giúp mình muốn thao tác trên xe {vehicle_list_str} nhé?"
                ),
            }

    # Case 2: User named a specific foreign vehicle model not in their garage during a charging/vehicle command
    foreign_match = _FOREIGN_VEHICLE_MODELS.search(msg)
    if foreign_match:
        mentioned_model = foreign_match.group(1)
        if not any(mentioned_model.lower() in n.lower() for n in bound_names):
            return {
                "disambiguationRequired": True,
                "reason": f"Dòng xe '{mentioned_model}' không khớp với danh sách xe của tài khoản",
                "reply": (
                    f"Tài khoản của bạn hiện chỉ liên kết với {vehicle_list_str}, không có xe **{mentioned_model}**. "
                    f"Bạn có muốn thực hiện thao tác này cho {vehicle_list_str} không?"
                ),
            }

    # Case 3: Account has multiple vehicles (>1), no vehicleId/vehicle is currently selected, and user asks to charge
    charging_intent = re.search(r"(?i)\b(bật\s*sạc|sạc\s*\d+\s*phút|sạc\s*giúp|sạc\s*đến|hẹn\s*sạc)\b", msg)
    if len(bound_names) > 1 and not selected_id and not selected_name and charging_intent:
        # Check if user explicitly named one of their bound vehicles in the message
        if not any(n.lower() in msg.lower() for n in bound_names):
            return {
                "disambiguationRequired": True,
                "reason": "Tài khoản có nhiều xe nhưng chưa chọn xe mục tiêu",
                "reply": (
                    f"Tài khoản của bạn đang có **{len(bound_names)} xe** ({vehicle_list_str}) nhưng chưa chọn xe đang dùng. "
                    f"Bạn muốn mình chuẩn bị lệnh sạc cho xe nào trong danh sách ({vehicle_list_str})?"
                ),
            }

    return None


def filter_and_gate_actions(
    *,
    actions: list[dict[str, Any]],
    message: str,
    context: dict[str, Any],
    version_config: dict[str, Any],
    kill_switch_mode: str = "normal",
) -> tuple[list[dict[str, Any]], str | None, list[dict[str, Any]]]:
    """Server-side ToolGate: enforce KillSwitch safe_mode, tier entitlements, and TKT-8839 vehicle disambiguation."""
    tools_map = {
        t["name"]: t for t in (version_config.get("tools") or default_tool_definitions()) if isinstance(t, dict)
    }
    user_tier = str(context.get("tier") or "ultra").lower()
    disambig = check_vehicle_disambiguation(message, context, version_config.get("guardrails"))

    physical_charging_tools = {
        "start_timed_charging",
        "prepare_target_charging",
        "update_charge_target",
        "set_night_plan",
        "select_vehicle",
    }

    approved_actions: list[dict[str, Any]] = []
    gate_decisions: list[dict[str, Any]] = []
    override_reply: str | None = None

    # Even if model didn't emit a tool call, if user asked to charge a wrong plate/vehicle, return disambiguation
    if disambig and re.search(r"(?i)\b(sạc|chuyển\s+sang\s+xe)\b", message or ""):
        for act in actions:
            if act.get("name") in physical_charging_tools:
                gate_decisions.append({
                    "tool": act.get("name"),
                    "decision": "blocked_disambiguation_tkt8839",
                    "reason": disambig["reason"],
                })
        return [], disambig["reply"], gate_decisions

    for act in actions:
        name = act.get("name", "")
        t_cfg = tools_map.get(name)
        if t_cfg and not t_cfg.get("enabled", True):
            gate_decisions.append({"tool": name, "decision": "blocked_disabled", "reason": "Công cụ đang tắt trong cấu hình"})
            continue

        if kill_switch_mode == "safe_mode" and t_cfg and t_cfg.get("disabledInSafeMode", False):
            gate_decisions.append({
                "tool": name,
                "decision": "blocked_safe_mode",
                "reason": "Pinova đang ở Chế độ An toàn (Chỉ đọc) — tạm khóa thao tác ghi/điều khiển",
            })
            override_reply = (
                "Pinova hiện đang ở **Chế độ An toàn (Chỉ đọc)** nên tạm khóa tính năng đặt lệnh tự động. "
                "Bạn vui lòng mở trực tiếp tab **Sạc pin** trên ứng dụng để thao tác nhé."
            )
            continue

        if t_cfg and user_tier not in (t_cfg.get("allowedTiers") or ["free", "pro", "ultra", "fleet"]):
            req_tier = "Ultra" if "ultra" in (t_cfg.get("allowedTiers") or []) and "pro" not in (t_cfg.get("allowedTiers") or []) else "Pro"
            gate_decisions.append({
                "tool": name,
                "decision": "blocked_tier_limit",
                "reason": f"Yêu cầu gói {req_tier} (hiện tại: {user_tier.upper()})",
            })
            approved_actions.append({"name": "open_premium", "args": {}})
            override_reply = (
                f"Tính năng **{t_cfg.get('labelVi', name)}** thuộc gói **Pinova {req_tier}**. "
                f"Mình mở trang **Pinova Premium** bên dưới để bạn xem chi tiết hoặc dùng thử nhé."
            )
            continue

        if disambig and name in physical_charging_tools:
            gate_decisions.append({
                "tool": name,
                "decision": "blocked_disambiguation_tkt8839",
                "reason": disambig["reason"],
            })
            override_reply = disambig["reply"]
            continue

        approved_actions.append(act)
        gate_decisions.append({"tool": name, "decision": "allowed", "riskLevel": t_cfg.get("riskLevel", 1) if t_cfg else 1})

    return approved_actions, override_reply, gate_decisions


def sanitize_output_text(
    reply_text: str,
    *,
    enforce_qa137: bool = True,
    driving_mode: bool = False,
) -> str:
    """Enforce QA 137 formatting (no '~' tilde) and Driving Mode conciseness."""
    text = str(reply_text or "").strip()
    if not text:
        return text

    # Scrub any accidental system prompt marker leak
    text = re.sub(r"\[HIẾN CHƯƠNG PINOVA[^\]]*\]", "", text)
    text = re.sub(r"</?untrusted_context>", "", text)

    if enforce_qa137 and "~" in text:
        # Replace '~35 km' -> 'khoảng 35 km', or standalone '~' -> 'khoảng '
        text = re.sub(r"~\s*(\d)", r"khoảng \1", text)
        text = text.replace("~", "khoảng ")

    if driving_mode:
        # Keep at most 2 concise sentences when user is driving
        sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", text) if s.strip()]
        if len(sentences) > 2:
            text = " ".join(sentences[:2])

    return text.strip()

