"""Proactive Suggestion Engine for AI Chatbot (Rules R001 - R008).

Evaluates user behavior profile, vehicle state, and current context to generate
proactive, context-aware suggestions with rate-limiting and priority levels.
"""

from __future__ import annotations

from datetime import datetime, timezone
import logging
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class SuggestionEngine:
    """Evaluates rules R001-R008 to produce proactive recommendations."""

    def generate_suggestions(
        self,
        vehicle_context: Optional[Dict[str, Any]] = None,
        behavior_profile: Optional[Dict[str, Any]] = None,
        current_hour: Optional[int] = None,
    ) -> List[Dict[str, Any]]:
        """Sinh danh sách gợi ý chủ động dựa trên trạng thái xe và hồ sơ hành vi."""
        suggestions: List[Dict[str, Any]] = []
        now = datetime.now(timezone.utc)
        current_hour = current_hour if current_hour is not None else datetime.now().hour

        v_ctx = vehicle_context or {}
        b_prof = behavior_profile or {}

        charging_patterns = b_prof.get("chargingPatterns", {})
        trip_patterns = b_prof.get("tripPatterns", {})
        personal_insights = b_prof.get("personalInsights", {})

        soc = float(v_ctx.get("currentSoc", 50.0))
        soh = float(v_ctx.get("currentSoh", 98.0))
        odo = int(v_ctx.get("odoKm", 0))
        charging_status = str(v_ctx.get("chargingStatus", "idle")).lower()
        v_name = v_ctx.get("model") or v_ctx.get("vehicleId") or "xe"

        # Rule R001: SoC < 20% và không có sạc đang chạy -> HIGH
        if soc < 20.0 and charging_status not in ("charging", "active"):
            suggestions.append({
                "ruleId": "R001",
                "title": "Cảnh báo mức pin thấp",
                "message": f"Pin {v_name} hiện chỉ còn {int(soc)}%. Bạn có muốn hẹn giờ sạc ngay tối nay không?",
                "priority": "HIGH",
                "action": "start_smart_charging",
                "suggestedAt": now.isoformat(),
            })

        # Rule R002: Chưa sạc > 3 ngày và SoC < 40% -> HIGH
        last_charge_str = charging_patterns.get("lastChargingEvent")
        days_since_last_charge = 0
        if last_charge_str:
            try:
                last_dt = datetime.fromisoformat(last_charge_str.replace("Z", "+00:00"))
                days_since_last_charge = (now - last_dt).days
            except Exception:
                pass
        if days_since_last_charge >= 3 and soc < 40.0:
            suggestions.append({
                "ruleId": "R002",
                "title": "Nhắc nhở sạc định kỳ",
                "message": f"Đã {days_since_last_charge} ngày xe chưa được nạp điện và pin đang ở mức {int(soc)}%. Nên sạc sớm để bảo vệ cell pin!",
                "priority": "HIGH",
                "action": "start_smart_charging",
                "suggestedAt": now.isoformat(),
            })

        # Rule R003: ODO sắp chạm mốc bảo dưỡng (< 500km) -> MEDIUM
        next_maint = int(personal_insights.get("nextMaintenanceOdoKm", 5000))
        if next_maint > odo and (next_maint - odo) <= 500:
            remaining = next_maint - odo
            suggestions.append({
                "ruleId": "R003",
                "title": "Sắp đến kỳ bảo dưỡng",
                "message": f"Còn khoảng {remaining} km nữa là đến mốc bảo dưỡng {next_maint} km. Hãy lên lịch kiểm tra phanh và cell pin nhé!",
                "priority": "MEDIUM",
                "action": "get_maintenance_info",
                "suggestedAt": now.isoformat(),
            })

        # Rule R004: SoH giảm nhanh hoặc < 95% -> MEDIUM
        trend = personal_insights.get("batteryHealthTrend", "stable")
        if trend == "degrading" or (soh > 0 and soh < 94.0):
            suggestions.append({
                "ruleId": "R004",
                "title": "Theo dõi độ chai pin (SoH)",
                "message": f"Độ bền pin {v_name} đang ở mức {soh}%. Bạn có muốn xem báo cáo chi tiết về tình trạng cell pin không?",
                "priority": "MEDIUM",
                "action": "get_battery_status",
                "suggestedAt": now.isoformat(),
            })

        # Rule R005: Thói quen sạc > 90% thường xuyên -> LOW
        target_pref = float(charging_patterns.get("avgTargetSoc", 80.0))
        if target_pref >= 95.0:
            suggestions.append({
                "ruleId": "R005",
                "title": "Mẹo kéo dài tuổi thọ pin",
                "message": "Cài đặt mốc sạc dừng ở 80%–85% giúp tăng thêm 20% chu kỳ vòng đời cho khối pin xe điện.",
                "priority": "LOW",
                "action": "get_energy_tips",
                "suggestedAt": now.isoformat(),
            })

        # Rule R006: Tiêu thụ Wh/km tăng cao (> 36 Wh/km) -> LOW
        avg_wh = float(trip_patterns.get("avgEnergyConsumptionWhPerKm", 32.0))
        if avg_wh > 36.0:
            suggestions.append({
                "ruleId": "R006",
                "title": "Tối ưu hóa năng lượng di chuyển",
                "message": f"Mức tiêu hao trung bình gần đây là {avg_wh} Wh/km (hơi cao). Bạn nên kiểm tra lại áp suất lốp xe.",
                "priority": "LOW",
                "action": "get_energy_tips",
                "suggestedAt": now.isoformat(),
            })

        # Rule R007: Lộ trình hàng ngày đều đặn -> LOW
        daily_km = float(trip_patterns.get("avgDailyDistanceKm", 18.5))
        if daily_km >= 25.0:
            suggestions.append({
                "ruleId": "R007",
                "title": "Kế hoạch sạc cho lộ trình dài",
                "message": f"Quãng đường trung bình của bạn là ~{daily_km} km/ngày. Pin hiện tại đủ đáp ứng khoảng {round(soc * 1.5)} km.",
                "priority": "LOW",
                "action": "get_trip_summary",
                "suggestedAt": now.isoformat(),
            })

        # Rule R008: Sáng mở app (06:00 - 08:30) -> LOW
        if 6 <= current_hour <= 8:
            est_km = round(soc * 1.5)
            suggestions.append({
                "ruleId": "R008",
                "title": "Chào buổi sáng!",
                "message": f"Chào buổi sáng! Pin {v_name} đang ở mức {int(soc)}%, đủ cho hành trình khoảng {est_km} km hôm nay.",
                "priority": "LOW",
                "action": "get_battery_status",
                "suggestedAt": now.isoformat(),
            })

        # Sort by priority: HIGH -> MEDIUM -> LOW
        priority_weights = {"HIGH": 3, "MEDIUM": 2, "LOW": 1}
        suggestions.sort(key=lambda s: priority_weights.get(s["priority"], 0), reverse=True)
        return suggestions


suggestion_engine = SuggestionEngine()
