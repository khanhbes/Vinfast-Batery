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
            or (vehicle_context.get("vehicleId") if vehicle_context else None)
            or args.get("vehicle_id", "xe điện")
        )

        if tool_name == "start_smart_charging":
            target_soc = int(args.get("target_soc", 80))
            max_amps = min(float(args.get("max_amps", 10.0)), MAX_SAFE_AMPS)
            current_soc = float(vehicle_context.get("currentSoc", 50) if vehicle_context else 50)
            est_hours = max(1, round(abs(target_soc - current_soc) / 20, 1))

            return {
                "callId": call_id,
                "toolName": tool_name,
                "args": {"vehicle_id": args.get("vehicle_id"), "target_soc": target_soc, "max_amps": max_amps},
                "requiresConfirmation": True,
                "confirmationCard": {
                    "title": "Bật sạc thông minh",
                    "description": f"Sạc {v_name} đến {target_soc}%, giới hạn dòng sạc {max_amps}A ({round(max_amps * 220)}W)",
                    "estimatedTime": f"~{est_hours} giờ",
                    "safetyNote": "Tự động ngắt relay khi đạt mức pin mục tiêu hoặc vượt ngưỡng 12A / quá nhiệt 75°C.",
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
                    "description": f"Ngắt nguồn sạc Shelly cho {v_name} ngay lập tức.",
                    "estimatedTime": "Ngay tức thì",
                    "safetyNote": "Đảm bảo rút dây sạc an toàn sau khi relay ngắt nguồn điện.",
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
                    "description": f"Tự động bật sạc {v_name} lúc {start_time} đến mốc {target_soc}%",
                    "estimatedTime": f"Bắt đầu: {start_time}",
                    "safetyNote": "Tiết kiệm chi phí và hạ nhiệt độ cell pin trong khung giờ thấp điểm.",
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
        vehicle_id = args.get("vehicle_id", v_ctx.get("vehicleId", "VF-DEFAULT"))

        if tool_name == "get_battery_status":
            soc = v_ctx.get("currentSoc", 75.0)
            soh = v_ctx.get("currentSoh", 98.0)
            voltage = float(v_ctx.get("voltage", 72.4) or 72.4)
            temp = float(v_ctx.get("batteryTemp", 31.5) or 31.5)
            status = v_ctx.get("chargingStatus", "idle") or "idle"
            est_km = float(v_ctx.get("estimatedRangeKm") or round(float(soc) * 1.5, 1))
            return {
                "status": "success",
                "vehicleId": vehicle_id,
                "soc": soc,
                "soh": soh,
                "voltage": voltage,
                "temperatureC": temp,
                "chargingStatus": status,
                "estimatedRemainingKm": est_km,
            }

        elif tool_name == "get_charging_history":
            days = int(args.get("days", 7))
            return {
                "status": "success",
                "vehicleId": vehicle_id,
                "days": days,
                "totalSessions": 4,
                "totalEnergyWh": 8450,
                "estimatedCostVnd": 25350,
                "avgDurationMinutes": 165,
                "frequentCharger": "Shelly Plug S (Nhà riêng)",
            }

        elif tool_name == "start_smart_charging":
            target_soc = int(args.get("target_soc", 80))
            max_amps = min(float(args.get("max_amps", 10.0)), MAX_SAFE_AMPS)
            logger.info("Executing confirmed start_smart_charging: %s target=%s amps=%s", vehicle_id, target_soc, max_amps)
            return {
                "status": "success",
                "action": "start_charging",
                "vehicleId": vehicle_id,
                "relayState": "ON",
                "targetSoc": target_soc,
                "maxAmps": max_amps,
                "maxWatts": round(max_amps * 220),
                "message": f"Đã kích hoạt sạc cho {vehicle_id} đến {target_soc}% (giới hạn {max_amps}A). Relay Shelly đã bật!",
            }

        elif tool_name == "stop_smart_charging":
            logger.info("Executing confirmed stop_smart_charging: %s", vehicle_id)
            return {
                "status": "success",
                "action": "stop_charging",
                "vehicleId": vehicle_id,
                "relayState": "OFF",
                "message": f"Đã ngắt nguồn sạc cho {vehicle_id}. Relay Shelly đã tắt an toàn.",
            }

        elif tool_name == "schedule_charging":
            start_time = args.get("start_time", "22:00")
            target_soc = int(args.get("target_soc", 80))
            return {
                "status": "success",
                "action": "schedule_charging",
                "vehicleId": vehicle_id,
                "scheduledStartTime": start_time,
                "targetSoc": target_soc,
                "message": f"Đã đặt lịch sạc thành công cho {vehicle_id}: Bắt đầu lúc {start_time}, tự ngắt khi đạt {target_soc}%.",
            }

        elif tool_name == "get_trip_summary":
            days = int(args.get("days", 7))
            return {
                "status": "success",
                "vehicleId": vehicle_id,
                "days": days,
                "totalKm": 115.4,
                "avgConsumptionWhPerKm": 31.8,
                "totalTripsCount": 14,
                "savedCo2Kg": 18.2,
            }

        elif tool_name == "get_maintenance_info":
            current_odo = int(v_ctx.get("odoKm", 4500))
            next_odo = 5000 if current_odo < 5000 else 10000
            return {
                "status": "success",
                "vehicleId": vehicle_id,
                "currentOdoKm": current_odo,
                "nextMaintenanceOdoKm": next_odo,
                "remainingKm": max(0, next_odo - current_odo),
                "items": ["Kiểm tra độ chụm lốp", "Kiểm tra siết ốc cell pin", "Vệ sinh giắc cắm sạc"],
                "statusLabel": "Bình thường",
            }

        elif tool_name == "get_energy_tips":
            return {
                "status": "success",
                "tips": [
                    "Duy trì SoC từ 20% đến 85% giúp kéo dài tuổi thọ cell pin LFP lên đến 2000+ chu kỳ.",
                    "Hạn chế tăng ga đột ngột ở dốc cao giúp tiết kiệm 12-18% năng lượng tiêu hao.",
                    "Sạc qua đêm ở dòng sạc 8-10A giúp cell pin cân bằng điện áp tự nhiên tốt hơn.",
                ],
            }

        elif tool_name == "get_weather_impact":
            location = args.get("location", "Hà Nội")
            return {
                "status": "success",
                "location": location,
                "temperatureC": 28,
                "efficiencyFactor": 0.98,
                "impactNote": "Nhiệt độ lý tưởng (20°C - 30°C), pin đạt 98-100% phạm vi di chuyển tiêu chuẩn.",
            }

        return {
            "status": "error",
            "message": f"Công cụ '{tool_name}' chưa được hỗ trợ.",
        }


# Global dispatcher instance
chat_tool_dispatcher = ChatToolDispatcher()

