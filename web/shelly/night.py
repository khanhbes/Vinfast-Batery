"""Sạc đêm an toàn (QA 135, Ultra).

The owner arms a plan at bedtime (current %, target 80–90 %, wake-up
time) and confirms it once the way they switch charging ON. The worker
starts the charge late enough that it ends just before waking (fewer hours
at a high charge, the cheap night tariff), through the normal ON path:
live safety checks, the Shelly auto-off ceiling and readback. A night
session also has stricter limits than the general 75 °C / 2450 W: the
outlet cuts at 60 °C, at a power well above what this scooter learned, or
when the charge runs far past its prediction, and every phone of the
account gets an urgent alert.

Plans live in the top-level ``nightPlans/{uid}__{vehicleId}`` collection
(server only; a single-field ``state`` index is enough for the worker).
"""
from __future__ import annotations

import re
import threading
from datetime import datetime, time, timedelta, timezone

NIGHT_STRATEGY = "night_target"
TARGET_MIN, TARGET_MAX, TARGET_DEFAULT = 80, 90, 85
FINISH_LEAD = timedelta(minutes=20)      # done this long before waking
MISSED_AFTER = timedelta(minutes=30)     # a start later than this is skipped
START_NOW_WITHIN = timedelta(minutes=2)
RETRY_CODES = {"workerUnavailable", "cloudQueueBusy", "deviceOffline", "safetySnapshotStale"}
NIGHT_MAX_TEMPERATURE_C = 60.0
NIGHT_POWER_FACTOR = 1.25
NIGHT_OVERTIME_FACTOR = 1.3
NIGHT_OVERTIME_EXTRA = timedelta(minutes=15)
VN = timezone(timedelta(hours=7))
COLLECTION = "nightPlans"
_TIME = re.compile(r"^([01]?\d|2[0-3]):([0-5]\d)$")


def parse_wake(value) -> time | None:
    match = _TIME.match(str(value or "").strip())
    return time(int(match.group(1)), int(match.group(2))) if match else None


def schedule(now: datetime, wake: time, seconds_needed: int) -> tuple[datetime, datetime]:
    """(start_at, finish_by) in UTC: finish ``FINISH_LEAD`` before the next
    wake-up; start as late as that allows, or now when the night is too
    short (the charge then ends after waking, and the app says so)."""
    local_now = now.astimezone(VN)
    wake_at = local_now.replace(hour=wake.hour, minute=wake.minute, second=0, microsecond=0)
    if wake_at <= local_now + FINISH_LEAD:
        wake_at += timedelta(days=1)
    finish_by = wake_at - FINISH_LEAD
    start_at = max(local_now, finish_by - timedelta(seconds=seconds_needed))
    return start_at.astimezone(timezone.utc), finish_by.astimezone(timezone.utc)


def night_violation(session, status, now: datetime) -> tuple[str, float, str] | None:
    """The stricter night limits (checked on top of the general policy)."""
    if getattr(session, "strategy", None) != NIGHT_STRATEGY or status.relay is not True:
        return None
    if status.temperature_c is not None and status.temperature_c > NIGHT_MAX_TEMPERATURE_C:
        return ("night_temperature", status.temperature_c,
                f"Ổ sạc nóng hơn {NIGHT_MAX_TEMPERATURE_C:.0f}°C khi sạc đêm")
    # Only against a power this scooter really showed (3+ learned charges),
    # never a default guess, and not during the first minutes' inrush.
    learned = float(getattr(session, "average_power_w", 0) or 0)
    if (learned > 0 and getattr(session, "personalization_stage", None) == "personalized"
            and now - session.created_at > timedelta(minutes=5)
            and float(status.power_w or 0) > max(learned * NIGHT_POWER_FACTOR, learned + 150)):
        return ("night_power", float(status.power_w), "Công suất cao bất thường khi sạc đêm")
    predicted = int(getattr(session, "predicted_duration_seconds", 0) or 0)
    if predicted > 0 and now > (session.created_at + timedelta(seconds=predicted * NIGHT_OVERTIME_FACTOR)
                                + NIGHT_OVERTIME_EXTRA):
        return ("night_overtime", float(predicted), "Sạc đêm kéo dài quá dự đoán")
    return None


class NightPlanStore:
    def __init__(self, db=None):
        self.db = db
        self._local: dict[str, dict] = {}
        self._lock = threading.Lock()

    @staticmethod
    def key(uid: str, vehicle_id: str) -> str:
        return f"{uid}__{vehicle_id}"[:1400]

    def get(self, uid: str, vehicle_id: str) -> dict | None:
        key = self.key(uid, vehicle_id)
        if self.db is None:
            with self._lock:
                item = self._local.get(key)
                return dict(item) if item else None
        snapshot = self.db.collection(COLLECTION).document(key).get()
        return (snapshot.to_dict() or {}) if snapshot.exists else None

    def put(self, plan: dict) -> None:
        key = self.key(plan["uid"], plan["vehicleId"])
        if self.db is None:
            with self._lock:
                self._local[key] = dict(plan)
        else:
            self.db.collection(COLLECTION).document(key).set(plan)

    def armed(self, limit: int = 50) -> list[dict]:
        if self.db is None:
            with self._lock:
                return [dict(p) for p in self._local.values() if p.get("state") == "armed"]
        query = self.db.collection(COLLECTION).where("state", "==", "armed").limit(limit)
        return [s.to_dict() or {} for s in query.stream()]


def _utc(value) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def public(plan: dict | None) -> dict | None:
    if not plan:
        return None
    out = {k: v for k, v in plan.items() if k != "uid"}
    for key in ("startAt", "finishBy", "createdAt", "updatedAt"):
        value = _utc(plan.get(key))
        out[key] = value.isoformat().replace("+00:00", "Z") if value else None
    return out


class NightChargingMixin:
    """Mixed into SmartChargeService (needs repository, clock, start,
    create_preview, require_feature, binding)."""

    night_alert = None  # callable(uid, title, body): urgent push to every phone

    @property
    def night_plans(self) -> NightPlanStore:
        store = getattr(self, "_night_store", None)
        if store is None:
            store = self._night_store = NightPlanStore(getattr(self.repository, "db", None))
        return store

    def night_plan(self, uid: str, vehicle_id: str) -> dict | None:
        self._owned_vehicle(uid, vehicle_id)
        return public(self.night_plans.get(uid, vehicle_id))

    def arm_night_plan(self, uid: str, vehicle_id: str, body: dict) -> dict:
        from .service import SmartChargeError
        self.require_feature(uid, "night_charging")
        if body.get("confirmed") is not True:
            raise SmartChargeError("confirmationRequired", "Cần xác nhận hẹn sạc đêm.")
        wake = parse_wake(body.get("wakeAt"))
        if wake is None:
            raise SmartChargeError("invalidNightPlan", "Giờ thức dậy không hợp lệ (HH:MM).")
        try:
            target = int(round(float(body.get("targetSoc", TARGET_DEFAULT))))
            current = float(body.get("currentSoc"))
        except (TypeError, ValueError):
            raise SmartChargeError("invalidNightPlan", "Cần % pin hiện tại và mục tiêu.") from None
        if not TARGET_MIN <= target <= TARGET_MAX:
            raise SmartChargeError("invalidNightPlan",
                                   f"Sạc đêm giới hạn {TARGET_MIN}–{TARGET_MAX}% để pin bền và an toàn.")
        if not 0 <= current <= target - 5:
            raise SmartChargeError("invalidNightPlan", "Pin hiện tại phải thấp hơn mục tiêu ít nhất 5%.")
        binding = self.binding(uid, vehicle_id)
        if not binding:
            raise SmartChargeError("notConfigured", "Xe chưa liên kết ổ sạc Shelly.", 409)
        # Same model as the Charge tab; no ON yet.
        preview = self._night_preview(uid, vehicle_id, current, target)
        now = self.clock()
        start_at, finish_by = schedule(now, wake, int(preview.predicted_duration_seconds))
        plan_id = f"{vehicle_id}-{start_at.astimezone(VN).strftime('%Y%m%d%H%M')}"
        plan = {
            "uid": uid, "vehicleId": vehicle_id, "planId": plan_id, "state": "armed",
            "currentSoc": current, "targetSoc": target, "wakeAt": wake.strftime("%H:%M"),
            "startAt": start_at, "finishBy": finish_by,
            "predictedMinutes": preview.predicted_minutes, "createdAt": now, "updatedAt": now,
            # The night is too short: it will end after waking.
            "endsLate": start_at + timedelta(seconds=int(preview.predicted_duration_seconds)) > finish_by,
        }
        self.night_plans.put(plan)
        self.repository.append_audit(uid, "night_plan_armed", vehicle_id=vehicle_id,
                                     start_at=start_at.isoformat(), target=target)
        if start_at - now <= START_NOW_WITHIN:
            plan = self._start_night_plan(plan)
        return public(plan)

    def cancel_night_plan(self, uid: str, vehicle_id: str) -> dict | None:
        plan = self.night_plans.get(uid, vehicle_id)
        if plan and plan.get("state") == "armed":
            plan.update(state="cancelled", updatedAt=self.clock())
            self.night_plans.put(plan)
            self.repository.append_audit(uid, "night_plan_cancelled", vehicle_id=vehicle_id)
        return public(plan)

    def run_due_night_plans(self) -> int:
        """Worker: start every plan whose time has come (skip stale ones)."""
        now = self.clock()
        started = 0
        for plan in self.night_plans.armed():
            start_at = _utc(plan.get("startAt"))
            if start_at is None or start_at > now:
                continue
            if now - start_at > MISSED_AFTER:
                plan.update(state="missed", updatedAt=now)
                self.night_plans.put(plan)
                self._night_alert(plan["uid"], "Chưa bật được sạc đêm",
                                  "Máy chủ không bật kịp phiên sạc đêm. Xe chưa được sạc.")
                continue
            if self._start_night_plan(plan).get("state") == "started":
                started += 1
        return started

    def _night_preview(self, uid: str, vehicle_id: str, current: float, target: float):
        """The charge-model preview (the worker has no other predictor)."""
        vehicle = self._owned_vehicle(uid, vehicle_id)
        payload = self._prediction_payload({}, vehicle)
        preview = self._charge_model_preview(uid, vehicle_id, payload, current, target)
        self.repository.save_preview(uid, preview)
        return preview

    def _start_night_plan(self, plan: dict) -> dict:
        from .service import SmartChargeError
        uid, vehicle_id = plan["uid"], plan["vehicleId"]
        now = self.clock()
        try:
            preview = self._night_preview(uid, vehicle_id, float(plan["currentSoc"]),
                                          float(plan["targetSoc"]))
            session = self.start(uid, preview.preview_id, f"night-{plan['planId']}",
                                 strategy=NIGHT_STRATEGY)
            plan.update(state="started", sessionId=session.session_id, updatedAt=now)
        except SmartChargeError as error:
            if error.retryable or error.code in RETRY_CODES:
                # Busy Cloud slot, worker restarting: try again next loop
                # until the plan is too late (then "missed" + alert).
                plan.update(lastError=error.code, updatedAt=now)
                self.night_plans.put(plan)
                return plan
            plan.update(state="failed", error=error.code, updatedAt=now)
            self._night_alert(uid, "Không bật được sạc đêm", error.message)
        self.night_plans.put(plan)
        self.repository.append_audit(uid, "night_plan_" + plan["state"], vehicle_id=vehicle_id,
                                     session_id=plan.get("sessionId"))
        return plan

    def _night_alert(self, uid: str, title: str, body: str) -> None:
        alert = self.night_alert
        if alert is None:
            return
        try:
            alert(uid, title=title, body=body)
        except Exception:
            pass  # the plan state is the record; the app shows it on open
