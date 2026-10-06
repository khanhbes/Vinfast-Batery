"""Gemini API wrapper & context injection engine for BatteryBot."""
from __future__ import annotations

import json
import logging
import os
import uuid
import threading
import time
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

DEFAULT_MODEL = os.environ.get("GEMINI_CHAT_MODEL", "").strip()


class ChatEngine:
    """Xử lý hội thoại thông minh với Google Gemini API & inject context xe và hành vi."""

    def __init__(self, memory: Optional[ChatMemoryManager] = None):
        self.memory = memory or memory_manager
        self.api_key = (
            os.environ.get("GEMINI_API_KEY")
            or os.environ.get("GOOGLE_API_KEY")
            or ""
        ).strip()
        self._pending_actions = {}
        self._action_lock = threading.RLock()
        self._client = None
        if self.api_key and genai is not None:
            try:
                self._client = genai.Client(api_key=self.api_key, http_options=types.HttpOptions(timeout=20000))
                logger.info("Initialized Google Gemini client with configured API key.")
            except Exception as e:
                logger.warning("Failed to initialize Google Gemini client: %s", type(e).__name__)

    @property
    def is_configured(self) -> bool:
        return self._client is not None and bool(DEFAULT_MODEL)

    def build_system_prompt(
        self,
        ctx: Optional[VehicleContext] = None,
        behavior: Optional[BehaviorProfile] = None,
    ) -> str:
        """Tạo system prompt cá nhân hóa kèm theo thông số xe và hồ sơ hành vi người dùng."""
        model_name = ctx.model if ctx and ctx.model else "VinFast EV (chưa xác định)"
        vid = ctx.vehicleId if ctx and ctx.vehicleId else "N/A"
        soc_str = f"{ctx.currentSoc:.1f}%" if ctx and ctx.currentSoc is not None else "Không có dữ liệu"
        soh_str = f"{ctx.currentSoh:.1f}%" if ctx and ctx.currentSoh is not None else "Không có dữ liệu"
        temp_str = f"{ctx.batteryTemp:.1f}°C" if ctx and ctx.batteryTemp is not None else "Không có dữ liệu"
        status_str = ctx.chargingStatus if ctx and ctx.chargingStatus else "Chưa có dữ liệu"
        odo_str = f"{ctx.odoKm:,.0f} km" if ctx and ctx.odoKm is not None else "Không có dữ liệu"
        range_str = f"~{ctx.estimatedRangeKm:.1f} km" if ctx and ctx.estimatedRangeKm is not None else "Không có dữ liệu"

        behavior_section = ""
        if behavior:
            cp = behavior.chargingPatterns
            tp = behavior.tripPatterns
            au = behavior.appUsage
            pref = behavior.chatPreferences
            observed = []
            if cp.lastChargingEvent:
                observed += [f"- Thường sạc lúc: {cp.preferredStartHour}h - {cp.preferredEndHour}h",
                             f"- Mốc SoC yêu thích: {cp.avgTargetSoc:.0f}%"]
            if tp.totalTrips > 0:
                observed += [f"- Quãng đường hàng ngày: {tp.avgDailyDistanceKm:.1f} km",
                             f"- Tiêu thụ trung bình: {tp.avgEnergyConsumptionWhPerKm:.1f} Wh/km"]
            if au.totalSessions > 0:
                observed.append(f"- Tab thường dùng: {', '.join(au.mostVisitedTabs)}")
            if observed:
                behavior_section = "\n## Hồ sơ hành vi người dùng:\n" + "\n".join(observed) + "\n"


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
4. Không tự suy ra mức pin, quãng đường, chi phí hoặc trạng thái relay. Dữ liệu trên do app cung cấp, không phải readback trực tiếp hay đo BMS mới. Không đưa mã xe nội bộ vào câu trả lời.
5. Giới hạn hệ thống là 12A / 2500W, không phải khuyến nghị dùng dòng tối đa. Tuân thủ hướng dẫn xe/bộ sạc. Chưa xác minh thao tác thì không nói đã bật, tắt hoặc hẹn giờ thành công. Dùng ít emoji.
6. Nếu người dùng hỏi điều không liên quan đến xe hoặc vượt quá thông tin bạn biết, hãy giải thích rõ ràng và hướng dẫn họ liên hệ tổng đài hoặc tra cứu sổ tay.
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
        model_name = ctx.model if ctx and ctx.model else "xe"
        lower = user_msg.lower()
        if any(w in lower for w in ["soh", "chai pin", "sức khỏe"]):
            if ctx and ctx.currentSoh is not None:
                return f"Theo dữ liệu bạn đang xem, sức khỏe pin {model_name} là **{ctx.currentSoh:g}%**. Chưa có readback BMS mới."
            return "Mình chưa có số đo sức khỏe pin. Bạn hãy kiểm tra nguồn dữ liệu ở Tổng quan."
        if any(w in lower for w in ["pin", "soc", "phần trăm", "còn bao nhiêu"]):
            if ctx and ctx.currentSoc is not None:
                return f"Theo dữ liệu bạn đang xem, pin {model_name} là **{ctx.currentSoc:g}%**. Đây không phải xác nhận BMS trực tiếp."
            return "Mình chưa có mức pin đã cập nhật. Mở Tổng quan để kiểm tra hoặc chọn xe trước."
        if any(w in lower for w in ["sạc", "shelly", "bật", "tắt"]):
            return "Mở Sạc pin để kiểm tra kết nối Shelly và thao tác. Mình không xác nhận bật/tắt khi chưa có readback thiết bị."
        if any(w in lower for w in ["chuyến đi", "lịch sử", "bảo dưỡng", "odo"]):
            return "Mình chưa có dữ liệu đã xác minh cho mục này. Bạn có thể xem lịch sử hoặc thông tin xe trong app."
        return "Mình có thể hướng dẫn xem pin, lịch sử và kết nối Shelly. Bạn muốn xem mục nào?"

    def _detect_action_intent(
        self, text: str, ctx: Optional[VehicleContext]
    ) -> Optional[Dict[str, Any]]:
        """Nhận diện ý định gọi các công cụ điều khiển vật lý (start/stop/schedule charging)."""
        import re

        text_lower = text.lower()
        v_id = ctx.vehicleId if ctx else None
        if not v_id:
            return None

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

    def _build_rich_card(self, tool_name, tool_result, vehicle_context=None):
        import math
        def valid(values):
            return all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) for v in values)
        if tool_result.get("status") != "success":
            return None
        if tool_name == "get_battery_status":
            fields = {"soc": "soc", "soh": "soh", "voltage": "voltage",
                      "temperature": "temperatureC", "estimatedRangeKm": "estimatedRemainingKm"}
            data = {out: tool_result.get(key) for out, key in fields.items()}
            if not valid(data.values()):
                return None
            data.update(chargingStatus=tool_result.get("chargingStatus", "unknown"),
                        source=tool_result.get("source", "app_context"))
            return {"cardType": "battery_status", "title": "Dữ liệu pin đang xem", "data": data}
        if tool_name == "get_trip_summary":
            keys = ["distanceKm", "energyUsedWh", "efficiencyWhKm", "co2SavedKg", "durationMinutes"]
            data = {k: tool_result.get(k) for k in keys}
            if valid(data.values()):
                return {"cardType": "trip_summary", "title": "Chuyến đi đã ghi nhận", "data": data}
        return None

    def _detect_rich_card_intent(self, user_message, vehicle_context):
        if any(w in user_message.lower() for w in ["pin", "soc", "soh"]):
            result = chat_tool_dispatcher.execute_tool("get_battery_status", {}, vehicle_context)
            return self._build_rich_card("get_battery_status", result, vehicle_context)
        return None

    def _create_confirmation_card(self, *, user_id, session_id, tool_name, args, vehicle_context):
        if not vehicle_context or not vehicle_context.get("vehicleId") or args.get("vehicle_id") != vehicle_context["vehicleId"]:
            raise ValueError("vehicleContextMismatch")
        card = chat_tool_dispatcher.create_confirmation_card(tool_name, args, vehicle_context)
        with self._action_lock:
            now = time.monotonic()
            self._pending_actions = {k: v for k, v in self._pending_actions.items() if v["expires"] > now}
            if len(self._pending_actions) >= 1000:
                raise ValueError("actionCapacityReached")
            self._pending_actions[card["callId"]] = {
                "userId": user_id, "sessionId": session_id, "toolName": tool_name,
                "args": card["args"], "expires": now + 300, "result": None}
        card["confirmationCard"]["safetyNote"] = "Chỉ báo thành công sau khi máy chủ xác minh thiết bị. Bạn có thể thao tác tại Sạc pin."
        card["confirmationCard"]["estimatedTime"] = "Chưa có thời gian đã xác minh"
        return card

    def stream_chat(
        self, req: ChatSendRequest
    ) -> Generator[str, None, None]:
        """Tạo generator SSE stream cho câu trả lời của chatbot."""
        session_id = self.memory.get_or_create_session(req.sessionId, req.userId)
        req.message, _ = chat_guardrails.sanitize_pii(req.message)
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

                model_name = DEFAULT_MODEL
                gemini_tools = get_gemini_tools()
                config = types.GenerateContentConfig(
                    system_instruction=system_instruction,
                    temperature=0.7,
                    max_output_tokens=1024,
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
                            # Buffer generated text until guardrails have checked it.

                    if not turn_function_calls:
                        break

                    for fc in turn_function_calls:
                        tool_name = fc.name
                        tool_args = fc.args or {}
                        call_id = getattr(fc, "id", None) or f"call-{uuid.uuid4().hex[:8]}"

                        if chat_tool_dispatcher.requires_confirmation(tool_name):
                            # Control tool: Safety-Gated (≤ 12A / 2500W) -> ActionConfirmationCard
                            card_payload = self._create_confirmation_card(
                        user_id=req.userId, session_id=session_id,
                                tool_name=tool_name,
                                args=tool_args,
                                vehicle_context=req.vehicleContext.model_dump() if req.vehicleContext else None,
                            )
                            yield f"event: function_call\ndata: {json.dumps(card_payload, ensure_ascii=False)}\n\n"
                            action_card_emitted = True

                            # A model's claimed success is not hardware evidence.
                            # Replace generated prose whenever it requests control.
                            if tool_name == "start_smart_charging":
                                full_reply = "Chưa bật sạc. Điều khiển từ chat chưa sẵn sàng; hãy mở Sạc pin để thao tác."
                            elif tool_name == "stop_smart_charging":
                                full_reply = "Chưa dừng sạc. Hãy dùng nút Dừng sạc tại màn hình Sạc pin và kiểm tra trạng thái thiết bị."
                            else:
                                full_reply = "Chưa tạo lịch sạc. Hãy mở Sạc pin để kiểm tra tính năng này."
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
                logger.warning("Gemini stream failed: %s", type(e).__name__)
                # Discard partial model output; never concatenate it with fallback.
                full_reply = ""
                action_intent = self._detect_action_intent(req.message, req.vehicleContext)
                if action_intent:
                    card_payload = self._create_confirmation_card(
                        user_id=req.userId, session_id=session_id,
                        tool_name=action_intent["toolName"],
                        args=action_intent["args"],
                        vehicle_context=req.vehicleContext.model_dump() if req.vehicleContext else None,
                    )
                    yield f"event: function_call\ndata: {json.dumps(card_payload, ensure_ascii=False)}\n\n"
                    tool_name = action_intent["toolName"]
                    if tool_name == "start_smart_charging":
                        fallback = (
                            "Chưa bật sạc. Điều khiển từ chat chưa sẵn sàng; hãy mở Sạc pin để thao tác."
                        )
                    elif tool_name == "stop_smart_charging":
                        fallback = (
                            "Chưa dừng sạc. Hãy dùng nút Dừng sạc tại màn hình Sạc pin và kiểm tra trạng thái thiết bị."
                        )
                    else:
                        fallback = (
                            "Chưa tạo lịch sạc. Hãy mở Sạc pin để kiểm tra tính năng này."
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
                    # Emit only after sanitization.
        else:
            action_intent = self._detect_action_intent(req.message, req.vehicleContext)
            if action_intent:
                card_payload = self._create_confirmation_card(
                        user_id=req.userId, session_id=session_id,
                    tool_name=action_intent["toolName"],
                    args=action_intent["args"],
                    vehicle_context=req.vehicleContext.model_dump() if req.vehicleContext else None,
                )
                yield f"event: function_call\ndata: {json.dumps(card_payload, ensure_ascii=False)}\n\n"
                tool_name = action_intent["toolName"]
                if tool_name == "start_smart_charging":
                    fallback = (
                        "Chưa bật sạc. Điều khiển từ chat chưa sẵn sàng; hãy mở Sạc pin để thao tác."
                    )
                elif tool_name == "stop_smart_charging":
                    fallback = (
                        "Chưa dừng sạc. Hãy dùng nút Dừng sạc tại màn hình Sạc pin và kiểm tra trạng thái thiết bị."
                    )
                else:
                    fallback = (
                        "Chưa tạo lịch sạc. Hãy mở Sạc pin để kiểm tra tính năng này."
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
                # Emit only after sanitization.

        # 3. Áp dụng Guardrails kiểm duyệt an toàn, thông số xe và PII
        v_ctx_dict = req.vehicleContext.model_dump() if req.vehicleContext else None
        guardrail_res = chat_guardrails.apply_guardrails(full_reply, v_ctx_dict)
        full_reply = guardrail_res.sanitized_text
        yield f"event: text_delta\ndata: {json.dumps({'delta': full_reply, 'messageId': message_id}, ensure_ascii=False)}\n\n"

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
                "model": DEFAULT_MODEL if self.is_configured else "offline-guidance",
                "guardrailPassed": guardrail_res.is_safe,
                "violations": guardrail_res.violations,
            },
        }
        yield f"event: message_end\ndata: {json.dumps(end_payload, ensure_ascii=False)}\n\n"

    def confirm_action(self, call_id, tool_name, args, confirmed=True,
                       vehicle_context=None, user_id=None, session_id=None):
        # Bind confirmation to the server-issued card, account, session and args.
        # Hold the lock until the receipt is written; a replay never executes twice.
        with self._action_lock:
            pending = self._pending_actions.get(call_id)
            if (not pending or pending["expires"] <= time.monotonic()
                    or pending["userId"] != user_id or pending["sessionId"] != session_id
                    or pending["toolName"] != tool_name or pending["args"] != args):
                return {"success": False, "code": "actionInvalid", "callId": call_id,
                        "message": "Yêu cầu không còn hợp lệ. Hãy mở Sạc pin để kiểm tra."}
            if pending["result"] is not None:
                return pending["result"]
            if not confirmed:
                response = {"success": True, "callId": call_id, "result": {"status": "cancelled"},
                            "message": "Đã hủy yêu cầu."}
            else:
                result = chat_tool_dispatcher.execute_tool(tool_name, pending["args"], vehicle_context, is_confirmed=True)
                response = {"success": result.get("status") == "success", "callId": call_id,
                            "toolName": tool_name, "result": result,
                            "message": result.get("message", "Chưa xác minh được thao tác.")}
            pending["result"] = response
            return response


# Global engine instance
chat_engine = ChatEngine()
