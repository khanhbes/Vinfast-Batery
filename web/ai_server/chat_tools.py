"""Tool definitions and dispatcher for AI Chatbot Function Calling.

Supports 9 tools per AI_CHATBOT_PERSONALIZATION.md:
- Read tools: get_battery_status, get_charging_history, get_trip_summary,
  get_maintenance_info, get_energy_tips, get_weather_impact
- Control tools (Safety-Gated / Human-in-the-Loop):
  start_smart_charging, stop_smart_charging, schedule_charging
"""

from __future__ import annotations

import logging
import uuid
from typing import Any, Dict, List, Optional

try:
    from google.genai import types
except ImportError:
    types = None

logger = logging.getLogger(__name__)

# Max allowable current per AGENTS.md hardware watchdog: ≤ 12A / 2500W
MAX_SAFE_AMPS = 12.0
MAX_SAFE_WATTS = 2500.0

SAFETY_GATED_TOOLS = {
    "start_smart_charging",
    "stop_smart_charging",
    "schedule_charging",
}

# Declarations for LLM / Gemini Function Calling
TOOL_DECLARATIONS = [
    {
        "name": "get_battery_status",
        "description": "Lấy thông tin trạng thái pin thời gian thực: % SoC, % SoH chai pin, nhiệt độ, điện áp và trạng thái sạc của xe.",
        "parameters": {
            "type": "object",
            "properties": {
                "vehicle_id": {
                    "type": "string",
                    "description": "ID hoặc biển số của xe (ví dụ: VF-EVO200-001)",
                }
            },
            "required": ["vehicle_id"],
        },
    },
    {
        "name": "get_charging_history",
        "description": "Xem tóm tắt lịch sử các lần sạc pin gần đây: số lần sạc, tổng điện năng nạp (Wh), chi phí ước tính.",
        "parameters": {
            "type": "object",
            "properties": {
                "vehicle_id": {
                    "type": "string",
                    "description": "ID của xe",
                },
                "days": {
                    "type": "integer",
                    "description": "Số ngày muốn xem lại (mặc định 7 ngày)",
                    "default": 7,
                },
            },
            "required": ["vehicle_id"],
        },
    },
    {
        "name": "start_smart_charging",
        "description": "Kích hoạt bật bộ sạc thông minh Shelly để nạp pin xe đến mốc SoC mục tiêu (bắt buộc xác nhận từ người dùng).",
        "parameters": {
            "type": "object",
            "properties": {
                "vehicle_id": {
                    "type": "string",
                    "description": "ID của xe cần sạc",
                },
                "target_soc": {
                    "type": "integer",
                    "description": "Mức phần trăm pin mong muốn dừng (ví dụ: 80 hoặc 90)",
                    "default": 80,
                },
                "max_amps": {
                    "type": "number",
                    "description": "Dòng sạc tối đa (A, an toàn <= 12A)",
                    "default": 10.0,
                },
            },
            "required": ["vehicle_id"],
        },
    },
    {
        "name": "stop_smart_charging",
        "description": "Ngắt relay bộ sạc thông minh Shelly ngay lập tức (bắt buộc xác nhận từ người dùng).",
        "parameters": {
            "type": "object",
            "properties": {
                "vehicle_id": {
                    "type": "string",
                    "description": "ID của xe đang sạc",
                }
            },
            "required": ["vehicle_id"],
        },
    },
    {
        "name": "schedule_charging",
        "description": "Hẹn giờ tự động bật sạc trong tương lai vào khung giờ ưu tiên (bắt buộc xác nhận từ người dùng).",
        "parameters": {
            "type": "object",
            "properties": {
                "vehicle_id": {
                    "type": "string",
                    "description": "ID của xe",
                },
                "start_time": {
                    "type": "string",
                    "description": "Thời gian bắt đầu sạc (định dạng HH:mm, ví dụ: 23:00)",
                },
                "target_soc": {
                    "type": "integer",
                    "description": "Mức pin mục tiêu (%)",
                    "default": 80,
                },
            },
            "required": ["vehicle_id", "start_time"],
        },
    },
    {
        "name": "get_trip_summary",
        "description": "Tóm tắt quãng đường và mức tiêu hao năng lượng xe đã di chuyển trong N ngày gần nhất.",
        "parameters": {
            "type": "object",
            "properties": {
                "vehicle_id": {
                    "type": "string",
                    "description": "ID của xe",
                },
                "days": {
                    "type": "integer",
                    "description": "Số ngày (mặc định 7)",
                    "default": 7,
                },
            },
            "required": ["vehicle_id"],
        },
    },
    {
        "name": "get_maintenance_info",
        "description": "Kiểm tra lịch bảo dưỡng định kỳ và các mốc ODO cần bảo trì tiếp theo.",
        "parameters": {
            "type": "object",
            "properties": {
                "vehicle_id": {
                    "type": "string",
                    "description": "ID của xe",
                }
            },
            "required": ["vehicle_id"],
        },
    },
    {
        "name": "get_energy_tips",
        "description": "Nhận các lời khuyên tiết kiệm điện và bảo vệ tuổi thọ pin LFP dựa trên thói quen lái xe.",
        "parameters": {
            "type": "object",
            "properties": {
                "vehicle_id": {
                    "type": "string",
                    "description": "ID của xe",
                }
            },
            "required": ["vehicle_id"],
        },
    },
    {
        "name": "get_weather_impact",
        "description": "Dự báo tác động của nhiệt độ môi trường đến hiệu suất và quãng đường di chuyển của xe điện.",
        "parameters": {
            "type": "object",
            "properties": {
                "location": {
                    "type": "string",
                    "description": "Khu vực hoặc thành phố (ví dụ: Hà Nội, TP.HCM)",
                    "default": "Hà Nội",
                }
            },
        },
    },
]


def get_gemini_tools() -> List[Any]:
    """Chuyển đổi TOOL_DECLARATIONS thành list[types.Tool] cho Google GenAI SDK."""
    if types is None:
        return []
    try:
        decls = [types.FunctionDeclaration(**d) for d in TOOL_DECLARATIONS]
        return [types.Tool(function_declarations=decls)]
    except Exception as e:
        logger.warning("Failed to construct Gemini types.Tool declarations: %s", e)
        return []


class ChatToolDispatcher:
    """Dispatches tool execution and builds ActionConfirmationCard for safety-gated operations."""

    def __init__(self, gateway_client: Optional[Any] = None) -> None:
        self.gateway_client = gateway_client

    def requires_confirmation(self, tool_name: str) -> bool:
        """Kiểm tra tool có cần Human-in-the-Loop hay không."""
        return tool_name in SAFETY_GATED_TOOLS

    def create_confirmation_card(
        self, tool_name: str, args: Dict[str, Any], vehicle_context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Tạo thẻ xác nhận ActionConfirmationCard chuẩn bị gửi về Flutter."""
        call_id = f"call-{uuid.uuid4().hex[:8]}"
        v_name = (
            (vehicle_context.get("model") if vehicle_context else None)
            or "xe của bạn"
        )

        if tool_name == "start_smart_charging":
            target_soc = int(args.get("target_soc", 80))
            max_amps = min(float(args.get("max_amps", 10.0)), MAX_SAFE_AMPS)
            import math
            if not 1 <= target_soc <= 100 or not math.isfinite(max_amps) or max_amps <= 0:
                raise ValueError('invalidActionArguments')
            max_amps = min(max_amps, 2500.0 / 255.0)

            return {
                "callId": call_id,
                "toolName": tool_name,
                "args": {"vehicle_id": args.get("vehicle_id"), "target_soc": target_soc, "max_amps": max_amps},
                "requiresConfirmation": True,
                "confirmationCard": {
                    "title": "Bật sạc thông minh",
                    "description": f"Yêu cầu sạc {v_name} đến {target_soc}%. Chưa thực hiện thao tác.",
                    "estimatedTime": "Chưa có ước tính đã xác minh",
                    "safetyNote": "Điều khiển từ chat chưa sẵn sàng. Mở Sạc pin để thao tác an toàn.",
                    "actions": ["confirm", "cancel"],
                    "targetSoc": target_soc,
                    "maxAmps": max_amps,
                },
            }

        elif tool_name == "stop_smart_charging":
            return {
                "callId": call_id,
                "toolName": tool_name,
                "args": {"vehicle_id": args.get("vehicle_id")},
                "requiresConfirmation": True,
                "confirmationCard": {
                    "title": "Dừng sạc pin",
                    "description": f"Yêu cầu dừng sạc {v_name}. Chưa thực hiện thao tác.",
                    "estimatedTime": "Chưa xác minh thiết bị",
                    "safetyNote": "Điều khiển từ chat chưa sẵn sàng. Mở Sạc pin để dừng và kiểm tra thiết bị.",
                    "actions": ["confirm", "cancel"],
                },
            }

        elif tool_name == "schedule_charging":
            start_time = str(args.get("start_time", "22:00"))
            target_soc = int(args.get("target_soc", 80))
            return {
                "callId": call_id,
                "toolName": tool_name,
                "args": {"vehicle_id": args.get("vehicle_id"), "start_time": start_time, "target_soc": target_soc},
                "requiresConfirmation": True,
                "confirmationCard": {
                    "title": "Hẹn giờ sạc ban đêm",
                    "description": f"Yêu cầu sạc {v_name} lúc {start_time} đến {target_soc}%. Chưa tạo lịch.",
                    "estimatedTime": f"Bắt đầu: {start_time}",
                    "safetyNote": "Chưa tạo lịch sạc. Mở Sạc pin để kiểm tra tính năng này.",
                    "actions": ["confirm", "cancel"],
                    "startTime": start_time,
                    "targetSoc": target_soc,
                },
            }

        # Fallback card
        return {
            "callId": call_id,
            "toolName": tool_name,
            "args": args,
            "requiresConfirmation": True,
            "confirmationCard": {
                "title": f"Thực hiện: {tool_name}",
                "description": f"Xác nhận hành động cho thiết bị {args.get('vehicle_id', '')}",
                "estimatedTime": "1-2 phút",
                "safetyNote": "Hành động yêu cầu xác nhận của chủ xe.",
                "actions": ["confirm", "cancel"],
            },
        }

    def execute_tool(
        self,
        tool_name: str,
        args: Dict[str, Any],
        vehicle_context: Optional[Dict[str, Any]] = None,
        is_confirmed: bool = False,
    ) -> Dict[str, Any]:
        """Thực thi tool. Nếu tool yêu cầu xác nhận và chưa confirm, trả về confirmation payload."""
        if self.requires_confirmation(tool_name) and not is_confirmed:
            return self.create_confirmation_card(tool_name, args, vehicle_context)

        v_ctx = vehicle_context or {}
        v_ctx = dict(v_ctx)
        for alias, key in [('soc', 'currentSoc'), ('soh', 'currentSoh'), ('temperature', 'batteryTemp')]:
            if key not in v_ctx and alias in v_ctx:
                v_ctx[key] = v_ctx[alias]
        vehicle_id = args.get("vehicle_id") or v_ctx.get("vehicleId")
        if tool_name in SAFETY_GATED_TOOLS:
            # Never simulate physical success. The trusted charging adapter must
            # enforce membership, device lease, safety gate and relay readback.
            return {"status": "unavailable", "code": "controlAdapterUnavailable",
                    "message": "Điều khiển từ chat chưa sẵn sàng. Mở Sạc pin để kiểm tra và thao tác."}
        if tool_name == "get_battery_status":
            import math
            fields = {"soc": "currentSoc", "soh": "currentSoh", "voltage": "voltage",
                      "temperatureC": "batteryTemp", "estimatedRemainingKm": "estimatedRangeKm"}
            values = {out: v_ctx.get(key) for out, key in fields.items()}
            values = {k: v for k, v in values.items()
                      if isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)}
            return {"status": "success" if values else "unavailable", "source": "app_context",
                    "vehicleId": vehicle_id, "chargingStatus": v_ctx.get("chargingStatus", "unknown"), **values}
        if tool_name == "get_energy_tips":
            return {"status": "success", "source": "general_guidance", "tips": [
                "Dùng bộ sạc phù hợp với xe và làm theo hướng dẫn nhà sản xuất.",
                "Kiểm tra dây, ổ cắm và giữ khu vực sạc khô thoáng.",
                "Khi có cảnh báo bất thường, dừng thao tác và kiểm tra thiết bị."]}
        return {"status": "unavailable", "code": "dataUnavailable",
                "message": "Chưa có dữ liệu đã xác minh cho mục này. Hãy mở màn hình tương ứng trong app."}


# Global dispatcher instance
chat_tool_dispatcher = ChatToolDispatcher()
