"""Gemini API wrapper & context injection engine for BatteryBot."""
from __future__ import annotations

import json
import logging
import os
import uuid
from typing import AsyncGenerator, Generator, List, Optional

try:
    from google import genai
    from google.genai import types
except ImportError:
    genai = None
    types = None

from .behavior_analyzer import behavior_analyzer
from .chat_guardrails import chat_guardrails
from .chat_memory import ChatMemoryManager, memory_manager
from .chat_schemas import BehaviorProfile, ChatMessage, ChatSendRequest, VehicleContext
from .chat_tools import (
    chat_tool_dispatcher,
    get_gemini_tools,
    SAFETY_GATED_TOOLS,
    TOOL_DECLARATIONS,
)
from .personality_adapter import personality_adapter

logger = logging.getLogger("ai_server.chat_engine")

DEFAULT_MODEL = "gemini-2.0-flash"


class ChatEngine:
    """Xử lý hội thoại thông minh với Google Gemini API & inject context xe và hành vi."""

    def __init__(self, memory: Optional[ChatMemoryManager] = None):
        self.memory = memory or memory_manager
        self.api_key = (
            os.environ.get("GEMINI_API_KEY")
            or os.environ.get("GOOGLE_API_KEY")
            or ""
        ).strip()
        self._client = None
        if self.api_key and genai is not None:
            try:
                self._client = genai.Client(api_key=self.api_key)
                logger.info("Initialized Google Gemini client with configured API key.")
            except Exception as e:
                logger.warning("Failed to initialize Google Gemini client: %s", e)

    @property
    def is_configured(self) -> bool:
        return self._client is not None

    def build_system_prompt(
        self,
        ctx: Optional[VehicleContext] = None,
        behavior: Optional[BehaviorProfile] = None,
    ) -> str:
        """Tạo system prompt cá nhân hóa kèm theo thông số xe và hồ sơ hành vi người dùng."""
        model_name = ctx.model if ctx and ctx.model else "VinFast EV (chưa xác định)"
        vid = ctx.vehicleId if ctx and ctx.vehicleId else "N/A"
        soc_str = f"{ctx.currentSoc:.1f}%" if ctx and ctx.currentSoc is not None else "Không có dữ liệu"
        soh_str = f"{ctx.currentSoh:.1f}%" if ctx and ctx.currentSoh is not None else "100%"
        temp_str = f"{ctx.batteryTemp:.1f}°C" if ctx and ctx.batteryTemp is not None else "Bình thường"
        status_str = ctx.chargingStatus if ctx and ctx.chargingStatus else "idle"
        odo_str = f"{ctx.odoKm:,.0f} km" if ctx and ctx.odoKm is not None else "Không có dữ liệu"
        range_str = f"~{ctx.estimatedRangeKm:.1f} km" if ctx and ctx.estimatedRangeKm is not None else "Ước tính theo pin"

        behavior_section = ""
        if behavior:
            cp = behavior.chargingPatterns
            tp = behavior.tripPatterns
            au = behavior.appUsage
            pref = behavior.chatPreferences
            behavior_section = f"""
## Hồ sơ hành vi người dùng:
- Thường sạc lúc: {cp.preferredStartHour}h - {cp.preferredEndHour}h
- Mốc SoC yêu thích: {cp.avgTargetSoc:.0f}%
- Quãng đường hàng ngày: {tp.avgDailyDistanceKm:.1f} km
- Tiêu thụ trung bình: {tp.avgEnergyConsumptionWhPerKm:.1f} Wh/km
- Tab thường dùng: {', '.join(au.mostVisitedTabs) if au.mostVisitedTabs else 'dashboard'}
- Chủ đề hay hỏi: {', '.join(pref.topTopics) if pref.topTopics else 'pin, sạc'}
"""

        personality_section = personality_adapter.get_prompt_modifier(behavior)

        prompt = f"""Bạn là BatteryBot — trợ lý AI thông minh chuyên về pin và sạc xe máy điện VinFast.

## Thông tin xe hiện tại của người dùng:
- Mẫu xe: {model_name} (Mã: {vid})
- Mức pin hiện tại (SoC): {soc_str}
- Tình trạng chai pin (SoH): {soh_str}
- Nhiệt độ pin: {temp_str}
- Trạng thái sạc: {status_str}
- Quãng đường đã đi (ODO): {odo_str}
- Quãng đường còn lại ước tính: {range_str}
{behavior_section}
{personality_section}
## Quy tắc trả lời:
1. Luôn trả lời ngắn gọn, thân thiện, xưng là "BatteryBot" hoặc "mình" và gọi người dùng là "bạn".
2. Sử dụng tiếng Việt chuẩn, hỗ trợ định dạng Markdown (in đậm, danh sách) để dễ đọc trên màn hình điện thoại.
3. Luôn bám sát dữ liệu xe và thói quen thực tế của người dùng ở trên để cá nhân hóa câu trả lời.
4. Tiêu chuẩn an toàn phần cứng: Luôn nhắc nhở an toàn sạc không quá 12A / 2500W, khuyến khích sạc đến 80-90% để bảo vệ tuổi thọ pin LFP.
5. Nếu người dùng hỏi điều không liên quan đến xe hoặc vượt quá thông tin bạn biết, hãy giải thích rõ ràng và hướng dẫn họ liên hệ tổng đài hoặc tra cứu sổ tay.
"""
        return prompt

    def _format_history_for_gemini(
        self, history: List[ChatMessage]
    ) -> List[types.Content]:
        """Chuyển đổi danh sách tin nhắn thành cấu trúc Content của Gemini SDK."""
        if not types:
            return []
        contents = []
        for msg in history:
            role = "model" if msg.role in ("assistant", "model", "bot") else "user"
            content_str = msg.content if msg.content and msg.content.strip() else "..."
            contents.append(
                types.Content(
                    role=role,
                    parts=[types.Part.from_text(text=content_str)],
                )
            )
        return contents

    def _generate_fallback_response(
        self,
        user_msg: str,
        ctx: Optional[VehicleContext] = None,
        behavior: Optional[BehaviorProfile] = None,
    ) -> str:
        """Phản hồi thông minh dự phòng khi chưa cấu hình API Key hoặc mất kết nối ngoại vi."""
        soc_val = ctx.currentSoc if ctx and ctx.currentSoc is not None else 75.0
        model_name = (ctx.model if ctx and ctx.model else None) or "xe VinFast"
        msg_lower = user_msg.lower()

        personal_tip = ""
        if behavior:
            cp = behavior.chargingPatterns
            tp = behavior.tripPatterns
            personal_tip = (
                f"\n\n💡 *Gợi ý cá nhân hóa*: Bạn thường cắm sạc khoảng **{cp.preferredStartHour}h** "
                f"đến mức **{cp.avgTargetSoc:.0f}%**. Với nhu cầu ~{tp.avgDailyDistanceKm:.1f} km/ngày, "
                f"lượng pin hiện tại hoàn toàn đủ cho lộ trình sắp tới!"
            )

        if any(w in msg_lower for w in ["pin", "soc", "phần trăm", "còn bao nhiêu"]):
            range_est = int(soc_val * 1.8)
            return (
                f"Hiện tại pin chiếc **{model_name}** của bạn đang ở mức **{soc_val:.0f}%**.\n\n"
                f"- Quãng đường ước tính di chuyển còn lại: **~{range_est} km** (ở tốc độ đô thị tiêu chuẩn).\n"
                f"- Để duy trì độ bền cho cell pin LFP, bạn nên cắm sạc khi pin xuống dưới 20% và sạc đến khoảng 80-90% nhé! 🔋"
                f"{personal_tip}"
            )
        elif any(w in msg_lower for w in ["sạc", "shelly", "bật", "hẹn giờ"]):
            return (
                f"Để sạc chiếc **{model_name}** an toàn:\n\n"
                f"1. Kiểm tra ổ cắm thông minh **Shelly Plug S Gen3** đã được cấp nguồn.\n"
                f"2. Công suất sạc tiêu chuẩn sẽ được giới hạn an toàn dưới **10A / 2200W**.\n"
                f"3. Bạn có thể thiết lập **Target SoC** (Mức pin ngắt tự động) trong tab **Sạc pin** để hệ thống tự ngắt relay khi đầy."
                f"{personal_tip}"
            )
        elif any(w in msg_lower for w in ["soh", "chai pin", "sức khỏe"]):
            soh_val = ctx.currentSoh if ctx and ctx.currentSoh is not None else 98.0
            return (
                f"Sức khỏe pin (SoH) xe bạn hiện đạt **{soh_val:.1f}%**.\n\n"
                f"Đây là chỉ số rất tốt! Bộ pin LFP của VinFast có tuổi thọ lên tới hơn 2,000 chu kỳ sạc xả nếu tránh để pin cạn kiệt 0% thường xuyên."
                f"{personal_tip}"
            )
        elif any(w in msg_lower for w in ["bảo dưỡng", "bảo trì", "odo", "bảo hành"]):
            res = chat_tool_dispatcher.execute_tool("get_maintenance_info", {}, ctx.model_dump() if ctx else None)
            rem = res.get("remainingKm", 500)
            next_odo = res.get("nextMaintenanceOdoKm", 5000)
            items = ", ".join(res.get("items", []))
            return (
                f"Thông tin bảo dưỡng định kỳ cho xe **{model_name}**:\n\n"
                f"- Quãng đường còn lại trước kỳ bảo dưỡng: **{rem} km** (Mốc: {next_odo:,} km).\n"
                f"- Các hạng mục kiểm tra khuyến nghị: {items}.\n"
                f"- Trạng thái chung: **{res.get('statusLabel', 'Bình thường')}**."
                f"{personal_tip}"
            )
        elif any(w in msg_lower for w in ["chuyến đi", "tiêu hao", "tiêu thụ", "lộ trình", "hành trình"]):
            res = chat_tool_dispatcher.execute_tool("get_trip_summary", {}, ctx.model_dump() if ctx else None)
            return (
                f"Tóm tắt hành trình 7 ngày gần đây của xe **{model_name}**:\n\n"
                f"- Tổng quãng đường đã chạy: **{res.get('totalKm', 115.4):.1f} km** ({res.get('totalTripsCount', 14)} chuyến).\n"
                f"- Mức tiêu thụ trung bình: **{res.get('avgConsumptionWhPerKm', 31.8):.1f} Wh/km**.\n"
                f"- Lượng CO₂ đã tiết kiệm: **{res.get('savedCo2Kg', 18.2):.1f} kg** so với xe xăng."
                f"{personal_tip}"
            )
        else:
            return (
                f"Chào bạn! BatteryBot đã nhận được câu hỏi: *\"{user_msg}\"*.\n\n"
                f"Chiếc **{model_name}** của bạn đang ở mức **{soc_val:.0f}% pin**.\n"
                f"Bạn có thể hỏi mình về: mức pin còn lại, quãng đường đi được, hướng dẫn sạc an toàn hay mẹo kéo dài tuổi thọ pin nhé!"
                f"{personal_tip}"
            )

    def _detect_action_intent(
        self, text: str, ctx: Optional[VehicleContext]
    ) -> Optional[Dict[str, Any]]:
        """Nhận diện ý định gọi các công cụ điều khiển vật lý (start/stop/schedule charging)."""
        import re

        text_lower = text.lower()
        v_id = ctx.vehicleId if ctx and ctx.vehicleId else "VF-EVO200"

        # Bật sạc
        if any(w in text_lower for w in ["bật sạc", "start charge", "kích hoạt sạc", "sạc pin ngay", "bật relay"]):
            m = re.search(r"(\d{2})\s*%", text)
            soc = int(m.group(1)) if m else 80
            return {
                "toolName": "start_smart_charging",
                "args": {"vehicle_id": v_id, "target_soc": soc, "max_amps": 10.0},
            }

        # Dừng / Ngắt sạc
        if any(w in text_lower for w in ["dừng sạc", "tắt sạc", "ngắt sạc", "stop charge", "ngắt relay"]):
            return {
                "toolName": "stop_smart_charging",
                "args": {"vehicle_id": v_id},
            }

        # Hẹn giờ sạc
        if any(w in text_lower for w in ["hẹn giờ sạc", "đặt lịch sạc", "hẹn sạc"]):
            m = re.search(r"(\d{1,2}[:h]\d{0,2})", text_lower)
            time_str = "22:00"
            if m:
                raw_time = m.group(1).replace("h", ":")
                if ":" not in raw_time:
                    raw_time += ":00"
                elif raw_time.endswith(":"):
                    raw_time += "00"
                time_str = raw_time
            return {
                "toolName": "schedule_charging",
                "args": {"vehicle_id": v_id, "start_time": time_str, "target_soc": 80},
            }

        return None

    def _build_rich_card(
        self,
        tool_name: str,
        tool_result: Dict[str, Any],
        vehicle_context: Optional[Dict[str, Any]],
    ) -> Optional[Dict[str, Any]]:
        """Tạo rich card payload theo kết quả của tool đã thực thi."""
        if tool_name == "get_battery_status":
            v_id = tool_result.get("vehicleId") or (vehicle_context.get("vehicleId") if vehicle_context else "VF-FELIZ")
            soc = float(tool_result.get("soc", 75.0))
            soh = float(tool_result.get("soh", 98.0))
            voltage = float(tool_result.get("voltage", 72.0))
            temp = float(tool_result.get("temperature", 28.5))
            est_range = float(tool_result.get("estimatedRangeKm", 85.0))
            status = str(tool_result.get("chargingStatus", "idle"))
            return {
                "cardType": "battery_status",
                "title": "Trạng thái Pin & Xe",
                "data": {
                    "vehicleId": v_id,
                    "soc": soc,
                    "soh": soh,
                    "voltage": voltage,
                    "temperature": temp,
                    "chargingStatus": status,
                    "estimatedRangeKm": est_range,
                },
            }
        elif tool_name in ("get_charging_history", "check_battery_health"):
            cur_soc = float(vehicle_context.get("soc", 75.0) if vehicle_context else 75.0)
            target_soc = float(vehicle_context.get("targetSoc", 85.0) if vehicle_context else 85.0)
            return {
                "cardType": "charging_progress",
                "title": "Tiến độ Sạc Thông Minh",
                "data": {
                    "currentSoc": cur_soc,
                    "targetSoc": target_soc,
                    "chargingPowerW": float(tool_result.get("chargingPowerW", 1850.0) or 1850.0),
                    "currentAmps": float(tool_result.get("currentAmps", 8.4) or 8.4),
                    "remainingMinutes": int(tool_result.get("remainingMinutes", 35) or 35),
                    "status": "charging" if (vehicle_context and vehicle_context.get("chargingStatus") == "charging") else "ready",
                },
            }
        elif tool_name in ("get_trip_summary", "estimate_range"):
            return {
                "cardType": "trip_summary",
                "title": "Tóm tắt Chuyến đi & Hiệu suất",
                "data": {
                    "distanceKm": float(tool_result.get("distanceKm", 24.5) or 24.5),
                    "energyUsedWh": float(tool_result.get("energyUsedWh", 735.0) or 735.0),
                    "efficiencyWhKm": float(tool_result.get("efficiencyWhKm", 30.0) or 30.0),
                    "co2SavedKg": float(tool_result.get("co2SavedKg", 2.1) or 2.1),
                    "durationMinutes": int(tool_result.get("durationMinutes", 42) or 42),
                },
            }
        return None

    def _detect_rich_card_intent(
        self,
        user_message: str,
        vehicle_context: Optional[Dict[str, Any]],
    ) -> Optional[Dict[str, Any]]:
        """Phát hiện ý định hiển thị thẻ trực quan từ nội dung tin nhắn người dùng."""
        msg_lower = user_message.lower()
        v_ctx = vehicle_context or {}
        if any(k in msg_lower for k in ["pin", "dung lượng", "soc", "soh", "bms", "nhiệt độ"]):
            soc_val = v_ctx.get("currentSoc") if v_ctx.get("currentSoc") is not None else v_ctx.get("soc", 75.0)
            soh_val = v_ctx.get("currentSoh") if v_ctx.get("currentSoh") is not None else v_ctx.get("soh", 98.0)
            temp_val = v_ctx.get("batteryTemp") if v_ctx.get("batteryTemp") is not None else v_ctx.get("temperature", 28.5)
            range_val = v_ctx.get("estimatedRangeKm") if v_ctx.get("estimatedRangeKm") is not None else 85.0
            return {
                "cardType": "battery_status",
                "title": "Trạng thái Pin & Xe",
                "data": {
                    "vehicleId": v_ctx.get("vehicleId", "VF-FELIZ-01"),
                    "soc": float(soc_val if soc_val is not None else 75.0),
                    "soh": float(soh_val if soh_val is not None else 98.0),
                    "voltage": float(v_ctx.get("voltage", 72.0) or 72.0),
                    "temperature": float(temp_val if temp_val is not None else 28.5),
                    "chargingStatus": str(v_ctx.get("chargingStatus", "idle")),
                    "estimatedRangeKm": float(range_val if range_val is not None else 85.0),
                },
            }
        elif any(k in msg_lower for k in ["sạc", "tiến độ sạc", "công suất sạc", "khi nào đầy"]):
            soc_val = v_ctx.get("currentSoc") if v_ctx.get("currentSoc") is not None else v_ctx.get("soc", 75.0)
            target_val = v_ctx.get("targetSoc", 85.0)
            return {
                "cardType": "charging_progress",
                "title": "Tiến độ Sạc Thông Minh",
                "data": {
                    "currentSoc": float(soc_val if soc_val is not None else 75.0),
                    "targetSoc": float(target_val if target_val is not None else 85.0),
                    "chargingPowerW": 1850.0,
                    "currentAmps": 8.4,
                    "remainingMinutes": 35,
                    "status": "charging" if v_ctx.get("chargingStatus") == "charging" else "ready",
                },
            }
        elif any(k in msg_lower for k in ["chuyến đi", "quãng đường", "tiêu hao", "tiết kiệm", "co2", "km"]):
            return {
                "cardType": "trip_summary",
                "title": "Tóm tắt Chuyến đi",
                "data": {
                    "distanceKm": 24.5,
                    "energyUsedWh": 735.0,
                    "efficiencyWhKm": 30.0,
                    "co2SavedKg": 2.1,
                    "durationMinutes": 42,
                },
            }
        return None

    def stream_chat(
        self, req: ChatSendRequest
    ) -> Generator[str, None, None]:
        """Tạo generator SSE stream cho câu trả lời của chatbot."""
        session_id = self.memory.get_or_create_session(req.sessionId)
        message_id = f"msg-{uuid.uuid4().hex[:12]}"
        emitted_rich_cards: List[Dict[str, Any]] = []

        # 1. Lưu tin nhắn của user vào bộ nhớ
        self.memory.add_message(
            session_id=session_id,
            role="user",
            content=req.message,
        )

        # 2. Emit event: message_start
        yield f"event: message_start\ndata: {json.dumps({'messageId': message_id, 'sessionId': session_id})}\n\n"

        # Lấy behavior profile nếu có
        behavior = req.behaviorProfile
        if not behavior and req.userId:
            behavior = behavior_analyzer.get_or_create_profile(req.userId)

        full_reply = ""
        system_instruction = self.build_system_prompt(req.vehicleContext, behavior)

        if self.is_configured and genai and types:
            try:
                context_msgs = self.memory.get_context_messages(session_id)
                gemini_contents = self._format_history_for_gemini(context_msgs)

                model_name = req.model or DEFAULT_MODEL
                gemini_tools = get_gemini_tools()
                config = types.GenerateContentConfig(
                    system_instruction=system_instruction,
                    temperature=0.7,
                    tools=gemini_tools if gemini_tools else None,
                )

                max_tool_turns = 3
                tool_turn = 0
                action_card_emitted = False

                while tool_turn < max_tool_turns and not action_card_emitted:
                    tool_turn += 1
                    response_stream = self._client.models.generate_content_stream(
                        model=model_name,
                        contents=gemini_contents,
                        config=config,
                    )

                    turn_function_calls = []
                    turn_text = ""

                    for chunk in response_stream:
                        if hasattr(chunk, "function_calls") and chunk.function_calls:
                            for fc in chunk.function_calls:
                                turn_function_calls.append(fc)

                        text_delta = chunk.text or ""
                        if text_delta:
                            turn_text += text_delta
                            full_reply += text_delta
                            payload = {"delta": text_delta, "messageId": message_id}
                            yield f"event: text_delta\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"

                    if not turn_function_calls:
                        break

                    for fc in turn_function_calls:
                        tool_name = fc.name
                        tool_args = fc.args or {}
                        call_id = getattr(fc, "id", None) or f"call-{uuid.uuid4().hex[:8]}"

                        if chat_tool_dispatcher.requires_confirmation(tool_name):
                            # Control tool: Safety-Gated (≤ 12A / 2500W) -> ActionConfirmationCard
                            card_payload = chat_tool_dispatcher.create_confirmation_card(
                                tool_name=tool_name,
                                args=tool_args,
                                vehicle_context=req.vehicleContext.model_dump() if req.vehicleContext else None,
                            )
                            yield f"event: function_call\ndata: {json.dumps(card_payload, ensure_ascii=False)}\n\n"
                            action_card_emitted = True

                            if not turn_text:
                                if tool_name == "start_smart_charging":
                                    guide_msg = (
                                        "Mình đã chuẩn bị lệnh điều khiển sạc thông minh cho xe. "
                                        "Vui lòng kiểm tra mốc pin mục tiêu và bấm **Xác nhận sạc** trên thẻ bên dưới nhé! ⚡"
                                    )
                                elif tool_name == "stop_smart_charging":
                                    guide_msg = (
                                        "Mình đã tạo lệnh ngắt nguồn sạc khẩn cấp. "
                                        "Vui lòng kiểm tra và bấm **Xác nhận** trên thẻ bên dưới để ngắt relay an toàn."
                                    )
                                else:
                                    guide_msg = (
                                        "Mình đã chuẩn bị lịch sạc tự động cho bạn. "
                                        "Vui lòng xem chi tiết trên thẻ và bấm **Xác nhận** để kích hoạt."
                                    )
                                full_reply += guide_msg
                                yield f"event: text_delta\ndata: {json.dumps({'delta': guide_msg, 'messageId': message_id}, ensure_ascii=False)}\n\n"
                            break
                        else:
                            # Read tool: Auto-execute & inject result back into Gemini context
                            yield f"event: tool_call\ndata: {json.dumps({'callId': call_id, 'toolName': tool_name, 'status': 'executing'}, ensure_ascii=False)}\n\n"

                            tool_result = chat_tool_dispatcher.execute_tool(
                                tool_name=tool_name,
                                args=tool_args,
                                vehicle_context=req.vehicleContext.model_dump() if req.vehicleContext else None,
                                is_confirmed=True,
                            )

                            yield f"event: tool_result\ndata: {json.dumps({'callId': call_id, 'toolName': tool_name, 'result': tool_result}, ensure_ascii=False)}\n\n"

                            # Rich Card Payload Generation
                            rc = self._build_rich_card(
                                tool_name,
                                tool_result,
                                req.vehicleContext.model_dump() if req.vehicleContext else None,
                            )
                            if rc:
                                emitted_rich_cards.append(rc)
                                yield f"event: rich_card\ndata: {json.dumps(rc, ensure_ascii=False)}\n\n"

                            gemini_contents.append(
                                types.Content(
                                    role="model",
                                    parts=[types.Part.from_function_call(name=tool_name, args=tool_args)],
                                )
                            )
                            gemini_contents.append(
                                types.Content(
                                    role="user",
                                    parts=[types.Part.from_function_response(name=tool_name, response=tool_result)],
                                )
                            )

                # Nếu Gemini không gọi tool nhưng người dùng hỏi về pin/sạc/chuyến đi
                if not emitted_rich_cards and not action_card_emitted:
                    rc_intent = self._detect_rich_card_intent(
                        req.message,
                        req.vehicleContext.model_dump() if req.vehicleContext else None,
                    )
                    if rc_intent:
                        emitted_rich_cards.append(rc_intent)
                        yield f"event: rich_card\ndata: {json.dumps(rc_intent, ensure_ascii=False)}\n\n"

            except Exception as e:
                logger.error("Error during Gemini stream: %s. Falling back to local responder.", e)
                action_intent = self._detect_action_intent(req.message, req.vehicleContext)
                if action_intent:
                    card_payload = chat_tool_dispatcher.create_confirmation_card(
                        tool_name=action_intent["toolName"],
                        args=action_intent["args"],
                        vehicle_context=req.vehicleContext.model_dump() if req.vehicleContext else None,
                    )
                    yield f"event: function_call\ndata: {json.dumps(card_payload, ensure_ascii=False)}\n\n"
                    tool_name = action_intent["toolName"]
                    if tool_name == "start_smart_charging":
                        fallback = (
                            "Mình đã chuẩn bị lệnh điều khiển sạc thông minh cho xe. "
                            "Vui lòng kiểm tra mốc pin mục tiêu và bấm **Xác nhận sạc** trên thẻ bên dưới nhé! ⚡"
                        )
                    elif tool_name == "stop_smart_charging":
                        fallback = (
                            "Mình đã tạo lệnh ngắt nguồn sạc khẩn cấp. "
                            "Vui lòng kiểm tra và bấm **Xác nhận** trên thẻ bên dưới để ngắt relay an toàn."
                        )
                    else:
                        fallback = (
                            "Mình đã chuẩn bị lịch sạc tự động cho bạn. "
                            "Vui lòng xem chi tiết trên thẻ và bấm **Xác nhận** để kích hoạt."
                        )
                else:
                    fallback = self._generate_fallback_response(
                        req.message, req.vehicleContext, behavior
                    )
                    # Gợi ý rich card nếu fallback có ý định phù hợp
                    rc_intent = self._detect_rich_card_intent(
                        req.message,
                        req.vehicleContext.model_dump() if req.vehicleContext else None,
                    )
                    if rc_intent:
                        emitted_rich_cards.append(rc_intent)
                        yield f"event: rich_card\ndata: {json.dumps(rc_intent, ensure_ascii=False)}\n\n"

                words = fallback.split(" ")
                for i, w in enumerate(words):
                    delta = w + (" " if i < len(words) - 1 else "")
                    full_reply += delta
                    payload = {"delta": delta, "messageId": message_id}
                    yield f"event: text_delta\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"
        else:
            action_intent = self._detect_action_intent(req.message, req.vehicleContext)
            if action_intent:
                card_payload = chat_tool_dispatcher.create_confirmation_card(
                    tool_name=action_intent["toolName"],
                    args=action_intent["args"],
                    vehicle_context=req.vehicleContext.model_dump() if req.vehicleContext else None,
                )
                yield f"event: function_call\ndata: {json.dumps(card_payload, ensure_ascii=False)}\n\n"
                tool_name = action_intent["toolName"]
                if tool_name == "start_smart_charging":
                    fallback = (
                        "Mình đã chuẩn bị lệnh điều khiển sạc thông minh cho xe. "
                        "Vui lòng kiểm tra mốc pin mục tiêu và bấm **Xác nhận sạc** trên thẻ bên dưới nhé! ⚡"
                    )
                elif tool_name == "stop_smart_charging":
                    fallback = (
                        "Mình đã tạo lệnh ngắt nguồn sạc khẩn cấp. "
                        "Vui lòng kiểm tra và bấm **Xác nhận** trên thẻ bên dưới để ngắt relay an toàn."
                    )
                else:
                    fallback = (
                        "Mình đã chuẩn bị lịch sạc tự động cho bạn. "
                        "Vui lòng xem chi tiết trên thẻ và bấm **Xác nhận** để kích hoạt."
                    )
            else:
                fallback = self._generate_fallback_response(
                    req.message, req.vehicleContext, behavior
                )
                # Gợi ý rich card nếu offline fallback có ý định phù hợp
                rc_intent = self._detect_rich_card_intent(
                    req.message,
                    req.vehicleContext.model_dump() if req.vehicleContext else None,
                )
                if rc_intent:
                    emitted_rich_cards.append(rc_intent)
                    yield f"event: rich_card\ndata: {json.dumps(rc_intent, ensure_ascii=False)}\n\n"

            words = fallback.split(" ")
            for i, w in enumerate(words):
                delta = w + (" " if i < len(words) - 1 else "")
                full_reply += delta
                payload = {"delta": delta, "messageId": message_id}
                yield f"event: text_delta\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"

        # 3. Áp dụng Guardrails kiểm duyệt an toàn, thông số xe và PII
        v_ctx_dict = req.vehicleContext.model_dump() if req.vehicleContext else None
        guardrail_res = chat_guardrails.apply_guardrails(full_reply, v_ctx_dict)
        if not guardrail_res.is_safe:
            logger.warning(
                "Guardrails detected violations in session %s: %s",
                session_id,
                guardrail_res.violations,
            )
            if behavior and hasattr(behavior, "guardrailViolationCount"):
                behavior.guardrailViolationCount += len(guardrail_res.violations)

            if guardrail_res.sanitized_text != full_reply:
                if guardrail_res.sanitized_text.startswith(full_reply):
                    addition = guardrail_res.sanitized_text[len(full_reply):]
                    full_reply = guardrail_res.sanitized_text
                    yield f"event: text_delta\ndata: {json.dumps({'delta': addition, 'messageId': message_id}, ensure_ascii=False)}\n\n"
                else:
                    full_reply = guardrail_res.sanitized_text

        # 4. Lưu câu trả lời hoàn chỉnh (đã qua guardrails) vào bộ nhớ
        self.memory.add_message(
            session_id=session_id,
            role="model",
            content=full_reply,
            message_id=message_id,
            rich_cards=emitted_rich_cards if emitted_rich_cards else None,
        )

        # 5. Emit event: message_end
        end_payload = {
            "messageId": message_id,
            "sessionId": session_id,
            "richCards": emitted_rich_cards,
            "usage": {
                "chars": len(full_reply),
                "model": req.model or DEFAULT_MODEL,
                "guardrailPassed": guardrail_res.is_safe,
                "violations": guardrail_res.violations,
            },
        }
        yield f"event: message_end\ndata: {json.dumps(end_payload, ensure_ascii=False)}\n\n"

    def confirm_action(
        self,
        call_id: str,
        tool_name: str,
        args: Dict[str, Any],
        confirmed: bool = True,
        vehicle_context: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Thực thi action sau khi nhận được sự đồng thuận (hoặc hủy) từ người dùng."""
        if not confirmed:
            return {
                "success": False,
                "toolName": tool_name,
                "callId": call_id,
                "result": {"status": "cancelled"},
                "message": "Đã hủy thao tác theo yêu cầu của bạn.",
            }

        result = chat_tool_dispatcher.execute_tool(
            tool_name=tool_name,
            args=args,
            vehicle_context=vehicle_context,
            is_confirmed=True,
        )
        return {
            "success": result.get("status") == "success",
            "toolName": tool_name,
            "callId": call_id,
            "result": result,
            "message": result.get("message", "Thực hiện thành công."),
        }


# Global engine instance
chat_engine = ChatEngine()
