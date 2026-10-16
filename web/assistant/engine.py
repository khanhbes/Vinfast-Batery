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

_VN = timezone(timedelta(hours=7))
MAX_MESSAGE = 1000
MAX_HISTORY = 10
MAX_TURNS = 3
# One chat turn (all model rounds) must answer well inside the app's 35 s
# timeout and must not hold an API thread for minutes (Task 125).
CHAT_DEADLINE_SECONDS = 28.0

SCREENS = ["overview", "charge", "history", "settings", "maintenance", "achievements",
           "battery_monitor", "trip_planner", "notifications", "garage", "vehicle_specs",
           "shelly_setup", "assistant_memory", "session_detail"]

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
     "parameters": _obj({"minutes": _s("INTEGER", "Thời lượng 1–600 phút")}, ["minutes"])},
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
]

SERVER_TOOLS = [
    {"name": "get_charger_status", "description": "Đọc trạng thái ổ Shelly và phiên sạc hiện tại của xe đang chọn (relay, W, V, A, timer, mức pin ước tính).",
     "parameters": _obj()},
    {"name": "get_charging_history", "description": "Đọc các phiên sạc gần đây của xe đang chọn (thời gian, thời lượng, điện năng, kết quả).",
     "parameters": _obj({"limit": _s("INTEGER", "Số phiên, tối đa 10")})},
    {"name": "get_charging_habits", "description": "Tóm tắt thói quen sạc của người dùng (giờ hay sạc, thời lượng, mục tiêu, số phiên).",
     "parameters": _obj()},
    {"name": "search_app_help", "description": "Chỉ dùng khi phần HƯỚNG DẪN APP LIÊN QUAN trong ngữ cảnh KHÔNG có câu trả lời: tra thêm hướng dẫn app/xe/Shelly.",
     "parameters": _obj({"query": _s("STRING", "Câu tra cứu")}, ["query"])},
    {"name": "remember", "description": "Ghi nhớ lâu dài một điều hữu ích người dùng tự nói về họ/xe/thói quen/sở thích (vd: 'đi làm 15 km mỗi ngày', 'thích sạc buổi tối'). Không ghi mật khẩu, số tài khoản, thông tin nhạy cảm.",
     "parameters": _obj({"fact": _s("STRING", "Một câu ngắn ở ngôi thứ ba"),
                         "category": _s("STRING", "Nhóm", enum=sorted(CATEGORIES))}, ["fact"])},
    {"name": "forget", "description": "Xóa điều đã nhớ khi người dùng yêu cầu quên.",
     "parameters": _obj({"fact": _s("STRING", "Nội dung cần quên")}, ["fact"])},
]
_CLIENT_NAMES = {item["name"] for item in CLIENT_ACTIONS}
_SERVER_NAMES = {item["name"] for item in SERVER_TOOLS}

PERSONA = """Bạn là BatteryBot, trợ lý trong app VinFast Battery (quản lý pin xe máy điện VinFast và sạc thông minh qua ổ Shelly).
Ngôn ngữ: tiếng Việt, xưng "mình", gọi người dùng là "bạn"; ngắn gọn, thân thiện, rõ ràng. Dùng **đậm** cho con số quan trọng; không dùng bảng.

Nguyên tắc:
1. Chỉ hỗ trợ trong phạm vi app, xe điện, pin, sạc, Shelly, bảo dưỡng. Câu ngoài phạm vi: từ chối nhẹ nhàng và gợi ý việc bạn làm được.
2. Không bịa số liệu. Số liệu cá nhân (trạng thái sạc, lịch sử, thói quen) chỉ lấy từ công cụ get_*. Mức pin trong app là do người dùng nhập, không phải BMS — nói rõ khi cần. Ước tính luôn ghi là ước tính.
3. Mỗi khi người dùng muốn mở/xem một màn hình hoặc thay đổi gì trong app, BẮT BUỘC gọi hàm hành động tương ứng trong cùng lượt trả lời (navigate, start_timed_charging, stop_charging, set_target_soc, update_battery_level, update_odometer, select_vehicle, set_electricity_price, create/edit/cancel_reminder, set_app_setting). Chỉ viết chữ mà không gọi hàm là SAI — app sẽ không làm gì cả. Không nói đã làm xong: app hiện thẻ để người dùng xác nhận; viết một câu ngắn mô tả thao tác đã chuẩn bị.
   Ví dụ: "sạc 30 phút" → gọi start_timed_charging(minutes=30). "mở lịch bảo dưỡng" → gọi navigate(screen="maintenance"). "pin đang 60%" → gọi update_battery_level(percent=60). "dừng sạc" → gọi stop_charging(). "xem phiên sạc hôm qua" → get_charging_history rồi navigate(screen="session_detail", session_id=...).
4. Bật sạc: chỉ khi người dùng muốn; nếu thiếu thời lượng thì hỏi lại, hoặc gợi ý thời lượng từ ước tính. Không thúc giục bật sạc.
5. Khi người dùng kể điều hữu ích lâu dài về họ (quãng đường hằng ngày, giờ hay sạc, nơi sạc, mục đích dùng xe, sở thích cách trả lời...), GỌI remember ngay trong lượt đó và VIẾT LUÔN câu trả lời trong cùng lượt (không cần chờ kết quả remember). Ví dụ: "mình đi làm 12 km mỗi ngày" → remember(fact="Đi làm khoảng 12 km mỗi ngày", category="habit"). Khi họ bảo quên, gọi forget. Không ghi thông tin nhạy cảm.
6. Dựa vào HỒ SƠ và THÓI QUEN để cá nhân hóa lời khuyên (ví dụ gợi ý mức sạc, giờ sạc) nhưng không lặp lại toàn bộ hồ sơ.
7. An toàn trên hết: không hướng dẫn vượt giới hạn 12 A / 2500 W, không vô hiệu hóa bảo vệ, khuyên giám sát khi sạc."""


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
        return {"minutes": minutes} if minutes else None
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
    return None


SCREEN_LABELS = {
    "overview": "Tổng quan", "charge": "Sạc pin", "history": "Lịch sử", "settings": "Cài đặt",
    "maintenance": "Bảo dưỡng xe", "achievements": "Thành tựu", "battery_monitor": "Theo dõi pin",
    "trip_planner": "Lập hành trình", "notifications": "Thông báo", "garage": "Xe của tôi",
    "vehicle_specs": "Thông số xe", "shelly_setup": "Sạc thông minh Shelly",
    "assistant_memory": "BatteryBot đang nhớ gì", "session_detail": "chi tiết phiên sạc",
}


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
            "mode": "hẹn giờ" if item.get("strategy") == "manual_timed" else "AI"}


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
                 live_reader=None, history_reader=None, clock=None):
        self.gemini = gemini
        self.knowledge = knowledge
        self.memory = memory
        self.live_reader = live_reader
        self.history_reader = history_reader
        self.clock = clock or (lambda: datetime.now(_VN))

    # -- prompt -------------------------------------------------------------
    def system_prompt(self, uid: str, message: str, context: dict, facts: list[dict], learning: bool) -> str:
        knowledge = self.knowledge.search(message, limit=4)
        lines = [PERSONA, "", f"Bây giờ: {self.clock().strftime('%H:%M, %A %d/%m/%Y')} (giờ Việt Nam)."]
        vehicle = context.get("vehicle") if isinstance(context.get("vehicle"), dict) else {}
        safe_context = {
            "manHinhDangMo": str(context.get("screen") or "")[:40],
            "xeDangChon": {k: vehicle.get(k) for k in ("name", "model", "batteryPercent", "odoKm", "sohPercent",
                                                     "capacityWh", "kmPerPercent", "targetSoc") if k in vehicle},
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
                sessions = state.setdefault("history", self._history(uid, vehicle_id))
                return {"sessions": sessions[:limit]}
            if name == "get_charging_habits":
                sessions = state.setdefault("history", self._history(uid, vehicle_id))
                return habits_from(sessions)
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
        except Exception as error:  # a tool failure becomes an honest answer
            return {"error": type(error).__name__}
        return {"error": "unknownTool"}

    def _history(self, uid: str, vehicle_id: str | None) -> list[dict]:
        if not self.history_reader:
            return []
        return [summarize_session(item) for item in self.history_reader(uid, vehicle_id, 20)]

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
        return {"reply": reply_text[:4000], "actions": actions, "source": "gemini",
                "memoryChanged": bool(state.get("memoryChanged")), "timingsMs": timings}
