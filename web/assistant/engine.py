"""BatteryBot engine: one chat turn = prompt + Gemini + server tools.

Server tools (read data, search help, remember/forget) run here. Client
actions (navigate, charge, edit data/settings, reminders) are returned to the
phone, which validates them again and executes them behind its own
confirmation tiers and the existing verified charging path. The model can
never energize a relay by itself.
"""
from __future__ import annotations

import json
import re
import time
from concurrent.futures import ThreadPoolExecutor
import statistics
from collections import Counter
from datetime import datetime, timedelta, timezone

from .gemini import GeminiClient, GeminiUnavailable
from .knowledge import KnowledgeBase
from .memory import CATEGORIES, AssistantMemory
from .trip_model import TripConditions, TripModelParams, catalog_km_per_pct, learned_km_per_pct, plan_trip

_VN = timezone(timedelta(hours=7))
MAX_MESSAGE = 1000
MAX_HISTORY = 10
MAX_TURNS = 3
# One chat turn (all model rounds) must answer well inside the app's 35 s
# timeout and must not hold an API thread for minutes (Task 125).
CHAT_DEADLINE_SECONDS = 28.0

SCREENS = ["overview", "charge", "history", "settings", "maintenance", "achievements",
           "battery_monitor", "trip_planner", "notifications", "garage", "vehicle_specs",
           "shelly_setup", "assistant_memory", "session_detail",
           # QA 135
           "premium", "help", "night_charging", "battery_health"]
SUPPORT_CATEGORIES = ["charging", "shelly", "scan", "battery", "billing", "account", "app", "other"]
PREMIUM_FEATURES = ["target_charging", "target_edit", "battery_health", "appearance", "history_export",
                    "learning_train", "trip_estimate", "night_charging", "offpeak_schedule",
                    "share_vehicle", "monthly_report"]

# The app content is Vietnamese only (Task 125: English option hidden).
APP_SETTINGS = {"push_notifications": ("on", "off")}

_SENSITIVE = re.compile(
    r"(cloud\s*key|auth[_ -]?key|api[_ -]?key|password|mat khau|mật khẩu|bearer\s+[a-z0-9._-]{16,}|\b[A-Za-z0-9_-]{32,}\b)",
    re.IGNORECASE)


def _s(type_, description, **extra):
    return {"type": type_, "description": description, **extra}


def _obj(properties=None, required=None):
    schema = {"type": "OBJECT", "properties": properties or {}}
    if required:
        schema["required"] = required
    return schema


CLIENT_ACTIONS = [
    {"name": "navigate", "description": "Mở một màn hình trong app cho người dùng. Dùng khi người dùng muốn xem/đi tới một chỗ.",
     "parameters": _obj({"screen": _s("STRING", "Màn hình cần mở", enum=SCREENS),
                         "session_id": _s("STRING", "Chỉ khi screen=session_detail: id phiên sạc lấy từ get_charging_history")},
                        ["screen"])},
    {"name": "start_timed_charging", "description": "Đề xuất bật sạc hẹn giờ cho xe đang chọn. Người dùng phải vuốt xác nhận trên điện thoại; app tự kiểm tra an toàn.",
     "parameters": _obj({"minutes": _s("INTEGER", "Thời lượng 1–600 phút"),
                         "target_percent": _s("INTEGER", "Mức pin người dùng muốn đạt khi hết giờ (vd 'sạc từ 11 đến 85%'), nếu họ có nói")},
                        ["minutes"])},
    {"name": "stop_charging", "description": "Đề xuất dừng phiên sạc đang chạy của xe đang chọn (người dùng bấm xác nhận).",
     "parameters": _obj()},
    {"name": "set_target_soc", "description": "Đặt mức pin muốn sạc tới trên màn Sạc pin.",
     "parameters": _obj({"percent": _s("INTEGER", "50–100")}, ["percent"])},
    {"name": "update_battery_level", "description": "Cập nhật mức pin hiện tại của xe theo con số người dùng nói (theo đồng hồ xe).",
     "parameters": _obj({"percent": _s("INTEGER", "0–100")}, ["percent"])},
    {"name": "update_odometer", "description": "Cập nhật số ODO (km) của xe đang chọn.",
     "parameters": _obj({"km": _s("INTEGER", "Số km trên đồng hồ")}, ["km"])},
    {"name": "select_vehicle", "description": "Đổi xe đang chọn theo tên xe trong danh sách xe của người dùng.",
     "parameters": _obj({"vehicle_name": _s("STRING", "Tên xe đúng như trong danh sách")}, ["vehicle_name"])},
    {"name": "set_electricity_price", "description": "Đặt giá điện dùng để tính chi phí sạc.",
     "parameters": _obj({"vnd_per_kwh": _s("INTEGER", "Đồng/kWh, 500–10000")}, ["vnd_per_kwh"])},
    {"name": "create_reminder", "description": "Tạo lịch nhắc bảo dưỡng hoặc bảo hành.",
     "parameters": _obj({"kind": _s("STRING", "Loại", enum=["maintenance", "warranty"]),
                         "date": _s("STRING", "Ngày YYYY-MM-DD"),
                         "note": _s("STRING", "Ghi chú ngắn")}, ["kind", "date"])},
    {"name": "edit_reminder", "description": "Đổi ngày một lịch nhắc bảo dưỡng/bảo hành đã có.",
     "parameters": _obj({"target": _s("STRING", "Loại + ngày hiện tại của lịch, vd 'bảo dưỡng 2026-11-20'. Hỏi lại người dùng nếu chưa biết ngày"),
                         "new_date": _s("STRING", "Ngày mới YYYY-MM-DD")}, ["target", "new_date"])},
    {"name": "cancel_reminder", "description": "Hủy một lịch nhắc bảo dưỡng/bảo hành.",
     "parameters": _obj({"target": _s("STRING", "Loại + ngày của lịch cần hủy, vd 'bảo hành 2027-01-05'")}, ["target"])},
    {"name": "set_app_setting", "description": "Bật/tắt thông báo đẩy của app (value on/off). App chỉ có tiếng Việt, không đổi được ngôn ngữ.",
     "parameters": _obj({"setting": _s("STRING", "Cài đặt", enum=sorted(APP_SETTINGS)),
                         "value": _s("STRING", "on hoặc off", enum=["on", "off"])}, ["setting", "value"])},
    {"name": "prepare_target_charging", "description": "Chuẩn bị sạc ĐẾN một mức pin (máy chủ tự ngắt khi ước tính đạt mức đó): mở tab Sạc với mục tiêu đã điền. Người dùng tự vuốt để bật; không bật sạc ngay.",
     "parameters": _obj({"percent": _s("INTEGER", "Mức pin muốn sạc tới, 50–100")}, ["percent"])},
    # -- QA 135 --------------------------------------------------------------
    {"name": "open_premium", "description": "Mở màn Pinova Premium (xem gói Pro/Ultra, dùng thử, nhập mã). Dùng khi người dùng hỏi về gói, giá, nâng cấp, hoặc tính năng họ muốn thuộc gói cao hơn.",
     "parameters": _obj({"feature": _s("STRING", "Tính năng người dùng muốn, nếu có", enum=PREMIUM_FEATURES)})},
    {"name": "start_trial", "description": "Đề xuất mở dùng thử Ultra 7 ngày miễn phí (một lần mỗi tài khoản). Người dùng bấm xác nhận trên thẻ.",
     "parameters": _obj()},
    {"name": "apply_promo_code", "description": "Kiểm tra và áp mã khuyến mãi người dùng đọc cho bạn (người dùng bấm xác nhận).",
     "parameters": _obj({"code": _s("STRING", "Mã khuyến mãi, 4–16 chữ/số")}, ["code"])},
    {"name": "contact_support", "description": "Soạn sẵn yêu cầu gửi đội hỗ trợ Pinova (có đính kèm kết quả tự kiểm tra). Người dùng xem lại rồi bấm Gửi. Dùng khi bạn không giải quyết được hoặc người dùng muốn liên hệ.",
     "parameters": _obj({"category": _s("STRING", "Nhóm vấn đề", enum=SUPPORT_CATEGORIES),
                         "subject": _s("STRING", "Tiêu đề ngắn"),
                         "message": _s("STRING", "Mô tả vấn đề theo lời người dùng")}, ["subject", "message"])},
    {"name": "update_charge_target", "description": "Đổi mục tiêu % của phiên đang sạc đến % (vd 80% lên 90%). Mở hộp đổi mục tiêu; tăng mục tiêu người dùng phải vuốt xác nhận vì sạc lâu hơn.",
     "parameters": _obj({"percent": _s("INTEGER", "Mục tiêu mới, 1–100")}, ["percent"])},
    {"name": "set_night_plan", "description": "Mở Sạc đêm an toàn (gói Ultra) với giờ thức dậy và mục tiêu 80–90% điền sẵn; người dùng tự vuốt để hẹn.",
     "parameters": _obj({"wake_at": _s("STRING", "Giờ thức dậy HH:MM"),
                         "target_percent": _s("INTEGER", "80–90, mặc định 85")})},
    {"name": "plan_trip", "description": "Mở màn Lộ trình với điểm đến/quãng đường và điều kiện đã điền để người dùng xem bản đồ và gợi ý.",
     "parameters": _obj({"destination": _s("STRING", "Tên điểm đến người dùng nói"),
                         "distance_km": _s("NUMBER", "Quãng đường km nếu người dùng nói số km"),
                         "round_trip": _s("BOOLEAN", "Đi rồi về"),
                         "passengers": _s("INTEGER", "1 hoặc 2 người"),
                         "speed": _s("STRING", "Tốc độ", enum=["slow", "normal", "fast"]),
                         "weather": _s("STRING", "Thời tiết", enum=["dry", "rain", "hot", "cold"])})},
]

_TRIP_ARGS = {
    "destination": _s("STRING", "Điểm đến (tên địa điểm ở Việt Nam)"),
    "origin": _s("STRING", "Điểm đi (tên địa điểm). Hỏi người dùng nếu chưa biết và không có distance_km"),
    "distance_km": _s("NUMBER", "Quãng đường một chiều, km, nếu người dùng nói số km"),
    "round_trip": _s("BOOLEAN", "Đi rồi về"),
    "passengers": _s("INTEGER", "Số người trên xe, 1 hoặc 2"),
    "cargo_kg": _s("NUMBER", "Hàng mang theo, kg"),
    "speed": _s("STRING", "Tốc độ", enum=["slow", "normal", "fast"]),
    "weather": _s("STRING", "Thời tiết", enum=["dry", "rain", "hot", "cold"]),
    "hilly": _s("BOOLEAN", "Đường dốc nhiều"),
}

SERVER_TOOLS = [
    {"name": "get_charger_status", "description": "Đọc trạng thái ổ Shelly và phiên sạc hiện tại của xe đang chọn (relay, W, V, A, timer, mức pin ước tính).",
     "parameters": _obj()},
    {"name": "get_charging_history", "description": "Đọc các phiên sạc gần đây của xe đang chọn (thời gian, thời lượng, điện năng, kết quả).",
     "parameters": _obj({"limit": _s("INTEGER", "Số phiên, tối đa 10")})},
    {"name": "get_charging_habits", "description": "Tóm tắt thói quen sạc của người dùng (giờ hay sạc, thời lượng, mục tiêu, số phiên).",
     "parameters": _obj()},
    {"name": "get_charging_summary", "description": "Tổng kết một tháng của xe đang chọn: tổng điện nạp (kWh), số phiên, tổng thời gian sạc — đúng như tab Lịch sử. Dùng cho 'tháng này sạc bao nhiêu', 'tháng 9 tốn bao nhiêu điện'.",
     "parameters": _obj({"month": _s("STRING", "Tháng dạng YYYY-MM; bỏ trống = tháng này")})},
    {"name": "search_app_help", "description": "Chỉ dùng khi phần HƯỚNG DẪN APP LIÊN QUAN trong ngữ cảnh KHÔNG có câu trả lời: tra thêm hướng dẫn app/xe/Shelly.",
     "parameters": _obj({"query": _s("STRING", "Câu tra cứu")}, ["query"])},
    {"name": "remember", "description": "Ghi nhớ lâu dài một điều hữu ích người dùng tự nói về họ/xe/thói quen/sở thích (vd: 'đi làm 15 km mỗi ngày', 'thích sạc buổi tối'). Không ghi mật khẩu, số tài khoản, thông tin nhạy cảm.",
     "parameters": _obj({"fact": _s("STRING", "Một câu ngắn ở ngôi thứ ba"),
                         "category": _s("STRING", "Nhóm", enum=sorted(CATEGORIES))}, ["fact"])},
    {"name": "forget", "description": "Xóa điều đã nhớ khi người dùng yêu cầu quên.",
     "parameters": _obj({"fact": _s("STRING", "Nội dung cần quên")}, ["fact"])},
    {"name": "estimate_trip", "description": "Ước tính pin hao cho một chuyến đi (tìm đường thật trên OpenStreetMap), % pin khi tới nơi, kết luận đủ/sát/không đủ và gợi ý (sạc trước đến X%, chạy chậm, tuyến ngắn hơn). Dùng cho mọi câu hỏi kiểu 'đi X được không', 'đi X hết bao nhiêu pin'.",
     "parameters": _obj(_TRIP_ARGS)},
    {"name": "get_subscription", "description": "Đọc gói hiện tại của người dùng (Free/Pro/Ultra, dùng thử, ngày hết hạn, quyền lợi, mã khuyến mãi đang giữ).",
     "parameters": _obj()},
    {"name": "get_battery_health", "description": "Đọc % pin chai của xe đang chọn (ước tính từ các lần sạc có % thật và bài kiểm tra pin). Gói Pro trở lên.",
     "parameters": _obj()},
    {"name": "get_night_plan", "description": "Đọc lịch sạc đêm của xe đang chọn (đã hẹn, đang sạc, giờ bắt đầu).",
     "parameters": _obj()},
    {"name": "estimate_charge", "description": "Ước tính thời gian sạc từ mức pin hiện tại (hoặc from_soc) đến to_soc theo mô hình đã học từ chính xe này.",
     "parameters": _obj({"to_soc": _s("INTEGER", "Mức pin muốn sạc tới, 1–100"),
                         "from_soc": _s("INTEGER", "Mức pin bắt đầu nếu khác pin hiện tại")}, ["to_soc"])},
]
_CLIENT_NAMES = {item["name"] for item in CLIENT_ACTIONS}
_SERVER_NAMES = {item["name"] for item in SERVER_TOOLS}

PERSONA = """Bạn là Pinova Bot, trợ lý trong app Pinova (quản lý pin xe máy điện VinFast và sạc thông minh qua ổ Shelly).
Ngôn ngữ: tiếng Việt, xưng "mình", gọi người dùng là "bạn"; ngắn gọn, thân thiện, rõ ràng. Dùng **đậm** cho con số quan trọng; không dùng bảng.

Nguyên tắc:
1. Chỉ hỗ trợ trong phạm vi app, xe điện, pin, sạc, Shelly, bảo dưỡng. Câu ngoài phạm vi: từ chối nhẹ nhàng và gợi ý việc bạn làm được.
2. Không bịa số liệu. Số liệu cá nhân (trạng thái sạc, lịch sử, thói quen) chỉ lấy từ công cụ get_*. Mức pin trong app là do người dùng nhập, không phải BMS — nói rõ khi cần. Ước tính luôn ghi là ước tính.
Số thập phân viết bằng dấu chấm như trong app (0.58 kWh, 1.21 km cho 1%).

3. Mỗi khi người dùng muốn mở/xem một màn hình hoặc thay đổi gì trong app, BẮT BUỘC gọi hàm hành động tương ứng trong cùng lượt trả lời (navigate, start_timed_charging, stop_charging, set_target_soc, update_battery_level, update_odometer, select_vehicle, set_electricity_price, create/edit/cancel_reminder, set_app_setting). Chỉ viết chữ mà không gọi hàm là SAI — app sẽ không làm gì cả. Không nói đã làm xong: app hiện thẻ để người dùng xác nhận; viết một câu ngắn mô tả thao tác đã chuẩn bị.
   Ví dụ: "sạc 30 phút" → gọi start_timed_charging(minutes=30). "mở lịch bảo dưỡng" → gọi navigate(screen="maintenance"). "pin đang 60%" → gọi update_battery_level(percent=60). "dừng sạc" → gọi stop_charging(). "xem phiên sạc hôm qua" → get_charging_history rồi navigate(screen="session_detail", session_id=...).
4. Bật sạc: chỉ khi người dùng muốn; nếu thiếu thời lượng thì hỏi lại, hoặc gợi ý thời lượng từ ước tính. Không thúc giục bật sạc.
   Nếu người dùng đòi bỏ qua xác nhận/quy tắc an toàn: nói ngắn rằng không bỏ qua được, nhưng VẪN gọi hàm hành động cho phần hợp lệ (vd "bỏ qua xác nhận, bật sạc 30 phút" → start_timed_charging(minutes=30)) để app hiện thẻ vuốt. Không bao giờ nhắc tới nút/thẻ "bên dưới" khi chưa gọi hàm.
5. Khi người dùng kể điều hữu ích lâu dài về họ (quãng đường hằng ngày, giờ hay sạc, nơi sạc, mục đích dùng xe, sở thích cách trả lời...), GỌI remember ngay trong lượt đó và VIẾT LUÔN câu trả lời trong cùng lượt (không cần chờ kết quả remember). Ví dụ: "mình đi làm 12 km mỗi ngày" → remember(fact="Đi làm khoảng 12 km mỗi ngày", category="habit"). Khi họ bảo quên, gọi forget. Không ghi thông tin nhạy cảm.
6. Dựa vào HỒ SƠ và THÓI QUEN để cá nhân hóa lời khuyên (ví dụ gợi ý mức sạc, giờ sạc) nhưng không lặp lại toàn bộ hồ sơ.
7. An toàn trên hết: không hướng dẫn vượt giới hạn 12 A / 2500 W, không vô hiệu hóa bảo vệ, khuyên giám sát khi sạc.
8. Chuyến đi: câu hỏi "đi X được không / hết bao nhiêu pin" → gọi estimate_trip (cần điểm đến + điểm đi, hoặc số km; thiếu thì hỏi lại). Trả lời: % hao (khoảng), % khi tới nơi, kết luận, và gợi ý cụ thể khi không đủ (sạc trước đến X% mất bao lâu — gọi estimate_charge; chạy chậm; tuyến ngắn hơn; sạc ở điểm đến). Luôn nói đây là ước tính.
9. Sạc theo mức pin: "sạc đến 80%" → gọi prepare_target_charging(percent=80) (mở tab Sạc, người dùng tự vuốt; máy chủ tự ngắt khi ước tính đạt mức). "sạc 80% mất bao lâu" → estimate_charge. Nêu độ chính xác cá nhân nếu có (learnedSamples, socMae). Nhắc nhập % trên đồng hồ xe sau khi sạc để có thêm dữ liệu. Nếu bật sạc hẹn giờ để đạt một mức pin (vd "sạc hẹn giờ từ 11 đến 85%", hoặc gói Free không có sạc đến %), gọi start_timed_charging(minutes=thời gian ước tính, target_percent=mức đó).
10. App học thế nào: % người dùng nhập (tay, Pinova Bot, ảnh đồng hồ), lúc app tự nhận biết pin đầy và các chuyến đi chỉ được XẾP HÀNG; mô hình chỉ đổi khi người dùng bấm Huấn luyện ở Cài đặt → AI cá nhân (app báo khi đủ dữ liệu: 3 lần sạc hoặc 10 chuyến mới). Không nói app "học ngay" hay tự học.
11. Tổng kết theo tháng (kWh, số phiên, thời gian) → gọi get_charging_summary; chi phí theo giá điện xem ở tab Lịch sử.
12. Gói Pinova Premium: Free (an toàn, hẹn giờ, quét đồng hồ, trợ giúp, 1 xe, lịch sử 30 ngày, 10 tin/ngày); Pro 29.000đ/tháng hoặc 249.000đ/năm (sạc đến % tự ngắt, đổi mục tiêu khi đang sạc, lộ trình, % pin chai, giao diện, 2 xe, lịch sử đầy đủ + CSV, 30 tin/ngày); Ultra 49.000đ/tháng hoặc 449.000đ/năm (thêm sạc đêm an toàn, AI cá nhân, giao diện Aurora, chi phí nâng cao, xe không giới hạn, 100 tin/ngày). Dùng thử Ultra 7 ngày. Chưa có thanh toán trong app. Hỏi về gói → get_subscription rồi trả lời; muốn xem/nâng cấp → open_premium; "dùng thử" → start_trial; đọc mã → apply_promo_code. Khi công cụ trả premiumRequired, giải thích ngắn và gọi open_premium.
13. Trợ giúp: lỗi bạn không xử lý được hoặc người dùng muốn hỏi đội hỗ trợ → contact_support với tiêu đề và mô tả theo lời người dùng; mở màn tự kiểm tra lỗi → navigate(screen="help").
14. Đang sạc đến % mà muốn đổi mục tiêu ("sạc lên 90% luôn") → update_charge_target. Sạc đêm ("tối nay sạc để 6 giờ sáng đầy") → get_night_plan nếu cần, rồi set_night_plan. Không bao giờ tự bật sạc.
15. % pin chai, pin còn tốt không → get_battery_health; nêu đây là ước tính, gợi ý bài kiểm tra (đi xuống ≤ 30% rồi sạc đầy) và navigate(screen="battery_health")."""


def _clamp_int(value, low, high):
    try:
        number = int(round(float(value)))
    except (TypeError, ValueError):
        return None
    return number if low <= number <= high else None


def _valid_date(value) -> str | None:
    try:
        day = datetime.strptime(str(value), "%Y-%m-%d").date()
    except ValueError:
        return None
    today = datetime.now(_VN).date()
    return day.isoformat() if today - timedelta(days=1) <= day <= today + timedelta(days=3650) else None


def validate_action(name: str, args: dict, context: dict) -> dict | None:
    """Clamp/verify model arguments; the phone validates again."""
    args = args if isinstance(args, dict) else {}
    if name == "navigate":
        screen = args.get("screen")
        if screen not in SCREENS:
            return None
        out = {"screen": screen}
        if screen == "session_detail":
            session_id = str(args.get("session_id") or "")
            if not re.fullmatch(r"[A-Za-z0-9_-]{6,80}", session_id):
                return {"screen": "history"}
            out["session_id"] = session_id
        return out
    if name == "start_timed_charging":
        minutes = _clamp_int(args.get("minutes"), 1, 600)
        if not minutes:
            return None
        # QA 135: the % the user aimed for is kept as the session's target
        # (display only; the Shelly timer still owns the cutoff).
        target = _clamp_int(args.get("target_percent"), 1, 100)
        return {"minutes": minutes, "target_percent": target} if target else {"minutes": minutes}
    if name == "stop_charging":
        return {}
    if name == "set_target_soc":
        percent = _clamp_int(args.get("percent"), 50, 100)
        return {"percent": percent} if percent else None
    if name == "update_battery_level":
        percent = _clamp_int(args.get("percent"), 0, 100)
        return {"percent": percent} if percent is not None else None
    if name == "update_odometer":
        km = _clamp_int(args.get("km"), 0, 500000)
        return {"km": km} if km is not None else None
    if name == "select_vehicle":
        wanted = str(args.get("vehicle_name") or "").strip()
        names = [str(v.get("name") or "") for v in (context.get("vehicles") or []) if isinstance(v, dict)]
        match = next((n for n in names if n.lower() == wanted.lower()), None) or \
            next((n for n in names if wanted and wanted.lower() in n.lower()), None)
        return {"vehicle_name": match} if match else None
    if name == "set_electricity_price":
        price = _clamp_int(args.get("vnd_per_kwh"), 500, 10000)
        return {"vnd_per_kwh": price} if price else None
    if name == "create_reminder":
        kind = args.get("kind") if args.get("kind") in ("maintenance", "warranty") else None
        day = _valid_date(args.get("date"))
        if not kind or not day:
            return None
        return {"kind": kind, "date": day, "note": str(args.get("note") or "")[:120]}
    if name == "edit_reminder":
        day = _valid_date(args.get("new_date"))
        target = str(args.get("target") or "")[:120]
        return {"target": target, "new_date": day} if day and target else None
    if name == "cancel_reminder":
        target = str(args.get("target") or "")[:120]
        return {"target": target} if target else None
    if name == "set_app_setting":
        setting, value = args.get("setting"), str(args.get("value") or "").lower()
        return {"setting": setting, "value": value} if value in APP_SETTINGS.get(setting, ()) else None
    if name == "prepare_target_charging":
        percent = _clamp_int(args.get("percent"), 50, 100)
        return {"percent": percent} if percent else None
    if name == "open_premium":
        feature = args.get("feature")
        return {"feature": feature} if feature in PREMIUM_FEATURES else {}
    if name == "start_trial":
        return {}
    if name == "apply_promo_code":
        code = re.sub(r"[\s-]", "", str(args.get("code") or "")).upper()
        return {"code": code} if re.fullmatch(r"[A-Z0-9]{4,16}", code) else None
    if name == "contact_support":
        subject = re.sub(r"\s+", " ", str(args.get("subject") or "")).strip()[:120]
        message = str(args.get("message") or "").strip()[:2000]
        if len(subject) < 3 or len(message) < 10 or _SENSITIVE.search(message):
            return None
        category = args.get("category") if args.get("category") in SUPPORT_CATEGORIES else "other"
        return {"category": category, "subject": subject, "message": message}
    if name == "update_charge_target":
        percent = _clamp_int(args.get("percent"), 1, 100)
        return {"percent": percent} if percent else None
    if name == "set_night_plan":
        out = {}
        wake = str(args.get("wake_at") or "").strip()
        if re.fullmatch(r"([01]?\d|2[0-3]):[0-5]\d", wake):
            out["wake_at"] = wake
        target = _clamp_int(args.get("target_percent"), 80, 90)
        if target:
            out["target_percent"] = target
        return out
    if name == "plan_trip":
        out = {}
        destination = str(args.get("destination") or "").strip()[:120]
        if destination:
            out["destination"] = destination
        km = _clamp_float(args.get("distance_km"), 0.1, 1000)
        if km is not None:
            out["distance_km"] = round(km, 1)
        out.update(trip_conditions(args).__dict__)
        return out
    return None


def _clamp_float(value, low, high):
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if low <= number <= high and number == number else None


def trip_conditions(args: dict) -> TripConditions:
    """Model arguments -> trip conditions, clamped to what the app offers."""
    speed = args.get("speed") if args.get("speed") in ("slow", "normal", "fast") else "normal"
    weather = args.get("weather") if args.get("weather") in ("dry", "rain", "hot", "cold") else "dry"
    riders = 2 if _clamp_int(args.get("passengers"), 1, 2) == 2 else 1
    cargo = _clamp_float(args.get("cargo_kg"), 0, 60) or 0.0
    return TripConditions(speed=speed, riders=riders, cargo_kg=cargo, weather=weather,
                          hilly=args.get("hilly") is True, round_trip=args.get("round_trip") is True)


SCREEN_LABELS = {
    "overview": "Tổng quan", "charge": "Sạc pin", "history": "Lịch sử", "settings": "Cài đặt",
    "maintenance": "Bảo dưỡng xe", "achievements": "Thành tựu", "battery_monitor": "Theo dõi pin",
    "trip_planner": "Lập hành trình", "notifications": "Thông báo", "garage": "Xe của tôi",
    "vehicle_specs": "Thông số xe", "shelly_setup": "Sạc thông minh Shelly",
    "assistant_memory": "Pinova Bot đang nhớ gì", "session_detail": "chi tiết phiên sạc",
    "premium": "Pinova Premium", "help": "Trợ giúp & khắc phục sự cố",
    "night_charging": "Sạc đêm an toàn", "battery_health": "% pin chai",
}

_VERDICT_TEXT = {"comfortable": "đủ pin, thoải mái", "tight": "đi được nhưng sát",
                 "insufficient": "không đủ pin"}


def _describe_setting(args: dict) -> str:
    value = args.get("value")
    return ("Mình đã chuẩn bị **bật thông báo đẩy**. Bạn xác nhận nhé." if value == "on"
            else "Mình đã chuẩn bị **tắt thông báo đẩy**. Bạn xác nhận nhé.")


def describe_action(action: dict) -> str:
    """Specific fallback sentence when the model returned only a call."""
    name, args = action["name"], action["args"]
    if name == "navigate":
        return f"Mình mở **{SCREEN_LABELS.get(args['screen'], 'màn hình')}** cho bạn."
    return {
        "start_timed_charging": f"Mình đã chuẩn bị sạc hẹn giờ **{args.get('minutes')} phút**. Bạn vuốt để xác nhận nhé.",
        "stop_charging": "Mình đã chuẩn bị lệnh dừng sạc. Bạn bấm xác nhận nhé.",
        "set_target_soc": f"Đặt mục tiêu sạc **{args.get('percent')}%** — bạn xác nhận nhé.",
        "update_battery_level": f"Cập nhật mức pin thành **{args.get('percent')}%** — bạn xác nhận nhé.",
        "update_odometer": f"Cập nhật ODO thành **{args.get('km')} km** — bạn xác nhận nhé.",
        "select_vehicle": f"Chuyển sang xe **{args.get('vehicle_name')}** — bạn xác nhận nhé.",
        "set_electricity_price": f"Đặt giá điện **{args.get('vnd_per_kwh')} đ/kWh** — bạn xác nhận nhé.",
        "create_reminder": f"Mình đã chuẩn bị lịch nhắc ngày **{args.get('date')}**. Bạn kiểm tra rồi xác nhận nhé.",
        "edit_reminder": f"Mình đã chuẩn bị đổi lịch sang **{args.get('new_date')}**. Bạn xác nhận nhé.",
        "cancel_reminder": "Mình đã chuẩn bị hủy lịch nhắc. Bạn xác nhận nhé.",
        "set_app_setting": _describe_setting(args),
        "prepare_target_charging": f"Mình mở tab Sạc với mục tiêu **{args.get('percent')}%**. Bạn kiểm tra dự đoán rồi vuốt để sạc; máy chủ sẽ tự ngắt khi ước tính đạt mức này.",
        "plan_trip": "Mình mở **Lộ trình** với thông tin bạn vừa nói.",
        "open_premium": "Mình mở **Pinova Premium** để bạn xem các gói.",
        "start_trial": "Mình đã chuẩn bị mở **dùng thử Ultra 7 ngày**. Bạn bấm xác nhận nhé.",
        "apply_promo_code": f"Mình đã chuẩn bị áp mã **{args.get('code')}**. Bạn bấm xác nhận nhé.",
        "contact_support": "Mình đã soạn sẵn yêu cầu gửi đội hỗ trợ. Bạn xem lại rồi bấm **Gửi** nhé.",
        "update_charge_target": f"Mình mở hộp đổi mục tiêu sang **{args.get('percent')}%**. Bạn xác nhận ở đó nhé.",
        "set_night_plan": "Mình mở **Sạc đêm an toàn** với thông tin bạn vừa nói. Bạn vuốt để hẹn nhé.",
    }.get(name, "Mình đã chuẩn bị thao tác, bạn kiểm tra rồi xác nhận nhé.")


def summarize_session(item: dict) -> dict:
    def when(value):
        try:
            return datetime.fromisoformat(str(value).replace("Z", "+00:00")).astimezone(_VN)
        except ValueError:
            return None
    start, stop = when(item.get("created_at")), when(item.get("stopped_at"))
    minutes = round((stop - start).total_seconds() / 60) if start and stop else item.get("predicted_minutes")
    return {"id": item.get("session_id"), "start": start.strftime("%d/%m %H:%M") if start else None,
            "minutes": minutes, "energyWh": round(float(item.get("energy_used_wh") or 0)),
            "startSoc": item.get("start_soc"), "targetSoc": item.get("target_soc"),
            "result": item.get("state"), "stopReason": item.get("stop_reason"),
            "estimatedEndSoc": item.get("estimated_soc"), "confirmedEndSoc": item.get("actual_end_soc"),
            "mode": ("hẹn giờ" if item.get("strategy") == "manual_timed"
                     else "sạc đến mục tiêu" if item.get("stop_mode") == "target" else "theo dự đoán")}


def habits_from(sessions: list[dict]) -> dict:
    done = [s for s in sessions if s.get("result") in ("completed", "cancelled", "interrupted")]
    if not done:
        return {"sessions": 0, "note": "Chưa có phiên sạc nào để rút ra thói quen."}
    hours = [int(s["start"].split()[1].split(":")[0]) for s in done if s.get("start")]
    minutes = [s["minutes"] for s in done if isinstance(s.get("minutes"), (int, float)) and s["minutes"] > 0]
    targets = [s["targetSoc"] for s in done if isinstance(s.get("targetSoc"), (int, float))]
    common_hour = Counter(hours).most_common(1)[0][0] if hours else None
    return {"sessions": len(done),
            "usualStartHour": common_hour,
            "medianMinutes": round(statistics.median(minutes)) if minutes else None,
            "usualTargetSoc": round(statistics.median(targets)) if targets else None,
            "manualStops": sum(1 for s in done if s.get("stopReason") == "manual"),
            "lastSession": done[0].get("start")}


class AssistantEngine:
    def __init__(self, *, gemini: GeminiClient, knowledge: KnowledgeBase, memory: AssistantMemory,
                 live_reader=None, history_reader=None, clock=None, router=None, charge_estimator=None,
                 trip_params_reader=None, entitlements=None, health_reader=None,
                 night_reader=None):
        self.gemini = gemini
        self.knowledge = knowledge
        self.memory = memory
        self.live_reader = live_reader
        self.history_reader = history_reader
        self.clock = clock or (lambda: datetime.now(_VN))
        # Task 126: OSM place search/route and the learned charge model.
        self.router = router
        self.charge_estimator = charge_estimator
        # Task 127: the vehicle's trained trip model (or ODO/catalog prior).
        self.trip_params_reader = trip_params_reader
        # QA 135: Pinova Premium (billing.EntitlementService); None = all on.
        self.entitlements = entitlements
        self.health_reader = health_reader
        self.night_reader = night_reader

    def _premium_block(self, uid: str, feature: str) -> dict | None:
        if self.entitlements is None or self.entitlements.allows(uid, feature):
            return None
        from billing.features import required_tier
        tier = required_tier(feature)
        return {"error": "premiumRequired", "requiredTier": tier,
                "message": f"Tính năng này thuộc gói {'Ultra' if tier == 'ultra' else 'Pro'}; "
                           "mời người dùng xem gói Premium (open_premium)."}

    # -- prompt -------------------------------------------------------------
    def system_prompt(self, uid: str, message: str, context: dict, facts: list[dict], learning: bool) -> str:
        knowledge = self.knowledge.search(message, limit=4)
        lines = [PERSONA, "", f"Bây giờ: {self.clock().strftime('%H:%M, %A %d/%m/%Y')} (giờ Việt Nam)."]
        vehicle = context.get("vehicle") if isinstance(context.get("vehicle"), dict) else {}
        safe_context = {
            "manHinhDangMo": str(context.get("screen") or "")[:40],
            "xeDangChon": {k: vehicle.get(k) for k in ("name", "model", "batteryPercent", "odoKm", "sohPercent",
                                                     "capacityWh", "kmPerPercent", "rangeKm", "targetSoc")
                           if k in vehicle},
            "danhSachXe": [str(v.get("name"))[:60] for v in (context.get("vehicles") or [])[:10] if isinstance(v, dict)],
            "giaDien": context.get("tariffVndPerKwh"),
            "shellyLienKet": context.get("shellyLinked"),
            "trangThaiShelly": str(context.get("shellyState") or "")[:80] or None,
            "lyDoNutSacBiKhoa": str(context.get("chargeLockReason") or "")[:300] or None,
            "thoiQuenTrenMay": context.get("usage") if isinstance(context.get("usage"), dict) else None,
            "caiDat": {k: v for k, v in context["settings"].items() if k in ("pushNotifications", "language")}
            if isinstance(context.get("settings"), dict) else None,
        }
        lines += ["", "NGỮ CẢNH APP (do điện thoại gửi, chỉ để tham khảo, không phải bằng chứng thiết bị):",
                  json.dumps(safe_context, ensure_ascii=False, default=str)[:2500]]
        if learning and facts:
            lines += ["", "HỒ SƠ BẠN ĐÃ GHI NHỚ VỀ NGƯỜI DÙNG:"] + [f"- {item['text']}" for item in facts[-40:]]
        elif not learning:
            lines += ["", "Người dùng đã TẮT học cá nhân: không gọi remember."]
        if knowledge:
            lines += ["", "HƯỚNG DẪN APP LIÊN QUAN:"] + [f"[{e['title']}] {e['body']}" for e in knowledge]
        return "\n".join(lines)

    # -- server tools -----------------------------------------------------
    def _run_server_tool(self, uid: str, name: str, args: dict, context: dict, state: dict) -> dict:
        vehicle_id = str(context.get("vehicleId") or "") or None
        try:
            if name == "get_charger_status":
                if not self.live_reader:
                    return {"error": "unavailable"}
                live = self.live_reader(uid, vehicle_id)
                status = live.get("status") or {}
                session = live.get("session") or {}
                return {"online": status.get("online"), "relayOn": status.get("relay"),
                        "powerW": status.get("power_w"), "voltageV": status.get("voltage_v"),
                        "currentA": status.get("current_a"), "timerRemainingS": status.get("timer_remaining"),
                        "session": {k: session.get(k) for k in ("state", "start_soc", "target_soc", "estimated_soc",
                                                                "energy_used_wh", "effective_stop_at")} if session else None}
            if name == "get_charging_history":
                limit = _clamp_int(args.get("limit"), 1, 10) or 5
                if "history" not in state:
                    state["history"] = self._history(uid, vehicle_id, state)
                return {"sessions": state["history"][:limit]}
            if name == "get_charging_habits":
                if "history" not in state:
                    state["history"] = self._history(uid, vehicle_id, state)
                return habits_from(state["history"])
            if name == "get_charging_summary":
                return self._month_summary(uid, vehicle_id, str(args.get("month") or ""))
            if name == "search_app_help":
                return {"results": [{"title": e["title"], "body": e["body"]}
                                    for e in self.knowledge.search(str(args.get("query") or ""), limit=3)]}
            if name == "remember":
                fact = self.memory.remember(uid, str(args.get("fact") or ""), str(args.get("category") or "other"))
                if fact:
                    state["memoryChanged"] = True
                return {"saved": bool(fact)}
            if name == "forget":
                removed = self.memory.forget_matching(uid, str(args.get("fact") or ""))
                if removed:
                    state["memoryChanged"] = True
                return {"removed": removed}
            if name == "estimate_trip":
                return self._premium_block(uid, "trip_estimate") or self._estimate_trip(uid, args, context, state)
            if name == "estimate_charge":
                return self._estimate_charge(uid, args, context, state)
            if name == "get_subscription":
                if self.entitlements is None:
                    return {"tier": "unknown", "note": "Máy chủ chưa bật Premium: mọi tính năng đang mở."}
                plan = self.entitlements.summary(uid)
                return {k: plan.get(k) for k in ("tier", "status", "expiresAt", "trialAvailable",
                                                 "features", "limits")}
            if name == "get_battery_health":
                if not self.health_reader or not vehicle_id:
                    return {"error": "unavailable"}
                blocked = self._premium_block(uid, "battery_health")
                return blocked or self.health_reader(uid, vehicle_id)
            if name == "get_night_plan":
                if not self.night_reader or not vehicle_id:
                    return {"error": "unavailable"}
                return {"plan": self.night_reader(uid, vehicle_id)}
        except Exception as error:  # a tool failure becomes an honest answer
            return {"error": type(error).__name__}
        return {"error": "unknownTool"}

    def _month_summary(self, uid: str, vehicle_id: str | None, month: str) -> dict:
        """The History tab's month card (QA 129: the bot could not answer
        "tổng tháng này" although the tab showed it)."""
        if not self.history_reader:
            return {"error": "unavailable"}
        now = self.clock().astimezone(_VN)
        match = re.fullmatch(r"(\d{4})-(\d{1,2})", month.strip())
        year, number = (int(match.group(1)), int(match.group(2))) if match else (now.year, now.month)
        if not 1 <= number <= 12:
            year, number = now.year, now.month
        energy = 0.0
        seconds = 0.0
        sessions = 0
        for item in self.history_reader(uid, vehicle_id, 50):
            if item.get("state") not in ("completed", "cancelled", "interrupted", "failed"):
                continue
            try:
                start = datetime.fromisoformat(str(item.get("created_at")).replace("Z", "+00:00")).astimezone(_VN)
            except ValueError:
                continue
            if (start.year, start.month) != (year, number):
                continue
            sessions += 1
            energy += max(0.0, float(item.get("energy_used_wh") or 0))
            try:
                stop = datetime.fromisoformat(str(item.get("stopped_at")).replace("Z", "+00:00"))
                seconds += max(0.0, (stop - start).total_seconds())
            except ValueError:
                pass
        hours, minutes = divmod(round(seconds / 60), 60)
        return {"month": f"{number:02d}/{year}", "sessions": sessions,
                "energyKwh": round(energy / 1000, 2), "energyWh": round(energy),
                "chargingTime": f"{hours} giờ {minutes} phút" if hours else f"{minutes} phút",
                "costNote": "Chi phí theo giá điện bạn đặt xem ở tab Lịch sử."}

    def _raw_history(self, uid: str, vehicle_id: str | None, state: dict) -> list[dict]:
        if "rawHistory" not in state:
            state["rawHistory"] = list(self.history_reader(uid, vehicle_id, 20)) if self.history_reader else []
        return state["rawHistory"]

    def _history(self, uid: str, vehicle_id: str | None, state: dict | None = None) -> list[dict]:
        if not self.history_reader:
            return []
        raw = self._raw_history(uid, vehicle_id, state) if state is not None else self.history_reader(uid, vehicle_id, 20)
        return [summarize_session(item) for item in raw]

    def _estimate_trip(self, uid: str, args: dict, context: dict, state: dict) -> dict:
        vehicle = context.get("vehicle") if isinstance(context.get("vehicle"), dict) else {}
        soc = _clamp_float(vehicle.get("batteryPercent"), 0, 100)
        if soc is None:
            return {"error": "batteryUnknown", "hint": "Hỏi mức pin hiện tại trên đồng hồ xe rồi gọi update_battery_level."}
        catalog = catalog_km_per_pct(_clamp_float(vehicle.get("kmPerPercent"), 0.05, 10),
                                     _clamp_float(vehicle.get("sohPercent"), 1, 100))
        vehicle_id = str(context.get("vehicleId") or "") or None
        readings = [{"endedAt": item.get("stopped_at"), "startSoc": item.get("start_soc"),
                     "actualEndSoc": item.get("actual_end_soc"), "odoKm": item.get("end_odo_km")}
                    for item in self._raw_history(uid, vehicle_id, state)]
        learned, pairs = learned_km_per_pct(readings, catalog)
        km_per_pct = learned or catalog
        model = None
        if self.trip_params_reader is not None and vehicle_id:
            try:
                model = TripModelParams.from_dict(self.trip_params_reader(uid, vehicle_id))
            except Exception:
                model = None
            if model is not None and model.source != "model" and learned:
                model = None  # this chat's ODO pairs are fresher than the prior
        if not km_per_pct and model is None:
            return {"error": "efficiencyUnknown", "hint": "Xe chưa có định mức km/%; người dùng cần chọn đúng dòng xe."}
        km = _clamp_float(args.get("distance_km"), 0.1, 1000)
        duration, alternatives, names = None, [], {}
        if km is None:
            destination = str(args.get("destination") or "").strip()
            origin = str(args.get("origin") or "").strip()
            if not destination:
                return {"error": "destinationRequired"}
            if not origin:
                return {"error": "originRequired", "hint": "Hỏi người dùng đi từ đâu hoặc quãng đường bao nhiêu km."}
            if self.router is None:
                return {"error": "routingUnavailable", "hint": "Hỏi quãng đường (km) để ước tính."}
            start, end = self.router.geocode(origin), self.router.geocode(destination)
            if start is None or end is None:
                return {"error": "placeNotFound", "which": "origin" if start is None else "destination"}
            routes = self.router.routes(start, end)
            if not routes:
                return {"error": "routeNotFound"}
            km, duration = routes[0]["km"], routes[0]["minutes"]
            alternatives = [item["km"] for item in routes[1:]]
            names = {"origin": start["name"], "destination": end["name"]}
        plan = plan_trip(distance_km=km, current_soc=soc, km_per_pct=km_per_pct,
                         km_per_pct_source="personal" if learned else "catalog",
                         conditions=trip_conditions(args), duration_min=duration,
                         alternative_km=alternatives, model=model)
        result = {**plan.to_dict(), **names, "batteryPercent": soc, "learnedPairs": pairs,
                  "verdictText": _VERDICT_TEXT[plan.verdict], "isEstimate": True,
                  # Arrival range best..worst: the model mixed arrivalSoc and
                  # arrivalLowSoc into "53-57 %" (QA 128).
                  "arrivalHighSoc": round(soc - plan.use_low_pct, 1),
                  "arrivalRangeText": f"{max(0, round(soc - plan.use_high_pct))}–"
                                      f"{max(0, round(soc - plan.use_low_pct))}%"}
        if duration is not None:
            result["carMinutes"] = round(duration)
        state["card"] = {"cardType": "trip_plan",
                         "title": f"Đi {names.get('destination', '').split(',')[0] or f'{km:.1f} km'}",
                         "data": result}
        return result

    def _estimate_charge(self, uid: str, args: dict, context: dict, state: dict) -> dict:
        if self.charge_estimator is None:
            return {"error": "unavailable"}
        vehicle = context.get("vehicle") if isinstance(context.get("vehicle"), dict) else {}
        target = _clamp_int(args.get("to_soc"), 1, 100)
        start = _clamp_int(args.get("from_soc"), 0, 99)
        if start is None:
            start = _clamp_int(vehicle.get("batteryPercent"), 0, 99)
        if target is None:
            return {"error": "targetRequired"}
        if start is None:
            return {"error": "batteryUnknown", "hint": "Hỏi mức pin hiện tại trên đồng hồ xe."}
        vehicle_id = str(context.get("vehicleId") or "")
        if not vehicle_id:
            return {"error": "vehicleRequired"}
        powers = [float(item["average_power_w"]) for item in self._raw_history(uid, vehicle_id, state)[:10]
                  if isinstance(item.get("average_power_w"), (int, float)) and item["average_power_w"] >= 60]
        history_power = statistics.median(powers) if powers else None
        return {**self.charge_estimator(uid, vehicle_id, float(start), float(target), history_power),
                "isEstimate": True}

    # -- chat ---------------------------------------------------------------
    @staticmethod
    def precheck(message) -> dict | None:
        """Answer that needs no model call (empty or contains a secret)."""
        message = str(message or "").strip()[:MAX_MESSAGE]
        if not message:
            return {"reply": "Bạn muốn hỏi gì về xe, pin hay sạc?", "actions": [], "source": "assistant"}
        if _SENSITIVE.search(message):
            return {"reply": "Đừng gửi mật khẩu hoặc khóa truy cập trong chat nhé. Hãy nhập ở màn hình thiết lập tương ứng.",
                    "actions": [], "source": "assistant", "sensitive": True}
        return None

    def chat(self, uid: str, message: str, history: list[dict] | None, context: dict | None) -> dict:
        message = str(message or "").strip()[:MAX_MESSAGE]
        context = context if isinstance(context, dict) else {}
        early = self.precheck(message)
        if early:
            return early
        started = time.perf_counter()
        timings: dict[str, int] = {}
        # Settings and facts are independent Firestore reads: fetch together.
        with ThreadPoolExecutor(max_workers=2) as pool:
            settings_job = pool.submit(self.memory.settings, uid)
            facts_job = pool.submit(self.memory.facts, uid)
        learning = settings_job.result()["learningEnabled"]
        try:
            facts = facts_job.result() if learning else []
        except Exception:
            facts = []
        timings["profile"] = int((time.perf_counter() - started) * 1000)
        system = self.system_prompt(uid, message, context, facts, learning)
        contents = []
        for turn in (history or [])[-MAX_HISTORY:]:
            if not isinstance(turn, dict):
                continue
            text = str(turn.get("text") or "").strip()[:MAX_MESSAGE]
            # A refused secret must not reach the model on the next turn.
            if text and not _SENSITIVE.search(text):
                contents.append({"role": "model" if turn.get("role") in ("assistant", "model", "bot") else "user",
                                 "parts": [{"text": text}]})
        contents.append({"role": "user", "parts": [{"text": message}]})
        tools = CLIENT_ACTIONS + [tool for tool in SERVER_TOOLS
                                  if learning or tool["name"] not in ("remember",)]
        state: dict = {}
        reply_text, actions = "", []
        for turn in range(MAX_TURNS):
            left = CHAT_DEADLINE_SECONDS - (time.perf_counter() - started)
            if left < 2.0:
                break
            before = time.perf_counter()
            last_round = turn == MAX_TURNS - 1
            parts = self.gemini.generate(system=system, contents=contents, tools=tools, temperature=0.2,
                                         tool_mode="NONE" if last_round else "AUTO", timeout=left)
            timings[f"model{turn + 1}"] = int((time.perf_counter() - before) * 1000)
            text = "".join(str(p.get("text") or "") for p in parts if "text" in p).strip()
            calls = [p["functionCall"] for p in parts if isinstance(p.get("functionCall"), dict)]
            if text:
                reply_text = text
            server_calls = [c for c in calls if c.get("name") in _SERVER_NAMES]
            for call in calls:
                if call.get("name") in _CLIENT_NAMES and len(actions) < 2:
                    args = validate_action(call["name"], call.get("args") or {}, context)
                    if args is not None:
                        actions.append({"name": call["name"], "args": args})
            if not server_calls:
                break
            memory_only = all(c.get("name") in ("remember", "forget") for c in server_calls)
            if memory_only and text:
                # The answer is already written: save the memory and stop
                # instead of a second model round trip (~2 s).
                for call in server_calls:
                    self._run_server_tool(uid, call["name"], call.get("args") or {}, context, state)
                break
            if actions and not any(c.get("name") in ("remember", "forget") for c in server_calls):
                break
            if actions:
                # Persist a memory change requested in the same turn as an action.
                for call in server_calls:
                    if call.get("name") in ("remember", "forget"):
                        self._run_server_tool(uid, call["name"], call.get("args") or {}, context, state)
                break
            # Echo the model turn verbatim: Gemini 3 requires each functionCall
            # part's thoughtSignature to come back with the tool results.
            contents.append({"role": "model", "parts": [p for p in parts if "functionCall" in p or "text" in p]})
            responses = []
            for c in server_calls:
                response = {"name": c["name"], "response": self._run_server_tool(
                    uid, c["name"], c.get("args") or {}, context, state)}
                if c.get("id"):
                    response["id"] = c["id"]  # Gemini 3 pairs results by call id
                responses.append({"functionResponse": response})
            contents.append({"role": "user", "parts": responses})
        if not reply_text:
            if actions:
                reply_text = " ".join(describe_action(a) for a in actions)
            elif state.get("memoryChanged"):
                reply_text = "Mình đã ghi nhớ điều này để lần sau tư vấn sát hơn cho bạn."
            else:
                reply_text = "Mình chưa có câu trả lời phù hợp. Bạn nói rõ hơn được không?"
        timings["total"] = int((time.perf_counter() - started) * 1000)
        result = {"reply": reply_text[:4000], "actions": actions, "source": "gemini",
                  "memoryChanged": bool(state.get("memoryChanged")), "timingsMs": timings}
        if state.get("card"):
            result["card"] = state["card"]
        return result
