from __future__ import annotations

import logging
import os
import threading
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Callable
from uuid import uuid4

from models import (
    AutomaticChargingSessionRequest,
    ChargingSessionPatchRequest,
    ChargingSessionState,
    ChargingStopReason,
    ChargingStrategy,
    SmartChargingSession,
    SafetyEvent,
    TERMINAL_SESSION_STATES,
    MAX_SMART_CHARGE_MINUTES,
)
from safety_monitor import SafetyMonitor
from shelly import ShellyClient, ShellyUnavailableError
from smart_session_store import SmartSessionStore

logger = logging.getLogger("SmartChargerGateway")


def env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class SmartChargingConfig:
    enabled: bool = True
    automatic_cutoff: bool = False
    shadow_mode: bool = True
    max_session_minutes: int | None = None
    readback_attempts: int = 3

    @classmethod
    def from_env(cls) -> "SmartChargingConfig":
        raw_max = os.getenv(
            "SMART_CHARGE_MAX_SESSION_MINUTES",
            os.getenv("SMART_CHARGER_MAX_SESSION_MINUTES", ""),
        ).strip()
        configured = int(raw_max) if raw_max.isdigit() and int(raw_max) > 0 else None
        # Configuration may tighten this limit, but can never widen the
        # ten-hour safety invariant shared with the Cloud-first service.
        max_minutes = (
            min(configured, MAX_SMART_CHARGE_MINUTES)
            if configured is not None
            else None
        )
        return cls(
            enabled=env_bool("ENABLE_SMART_CHARGING", True),
            automatic_cutoff=env_bool("ENABLE_AUTOMATIC_CUTOFF", False),
            shadow_mode=env_bool("SMART_CHARGER_SHADOW_MODE", True),
            max_session_minutes=max_minutes,
        )


class GatewayError(RuntimeError):
    def __init__(
        self,
        code: str,
        message: str,
        *,
        status_code: int = 400,
        retryable: bool = False,
        session_id: str | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.retryable = retryable
        self.session_id = session_id


class SmartChargingController:
    def __init__(
        self,
        store: SmartSessionStore,
        shelly: ShellyClient,
        config: SmartChargingConfig,
        clock: Callable[[], datetime] | None = None,
        safety_monitor: SafetyMonitor | None = None,
    ) -> None:
        self.store = store
        self.shelly = shelly
        self.config = config
        self._clock = clock or (lambda: datetime.now(timezone.utc))
        self._command_lock = threading.RLock()
        self.safety_monitor = safety_monitor or SafetyMonitor()
        self._last_status_at: datetime | None = None

    def now(self) -> datetime:
        value = self._clock()
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)

    @staticmethod
    def _utc(value: datetime) -> datetime:
        if value.tzinfo is None:
            raise GatewayError("INVALID_TIMESTAMP", "Thời gian phải có múi giờ.")
        return value.astimezone(timezone.utc)

    def _validate_config(self) -> None:
        if not self.config.enabled:
            raise GatewayError("FEATURE_DISABLED", "Sạc thông minh đang bị tắt.", status_code=503)
        if self.config.max_session_minutes is None:
            raise GatewayError(
                "SAFETY_LIMIT_NOT_CONFIGURED",
                "Chưa cấu hình giới hạn thời gian sạc an toàn.",
                status_code=503,
            )

    def _planned_times(
        self, request: AutomaticChargingSessionRequest, now: datetime
    ) -> tuple[datetime, datetime, datetime, datetime]:
        deadline = self._utc(request.hard_deadline_at)
        if deadline <= now:
            raise GatewayError("INVALID_TIMESTAMP", "Hạn dừng phải ở tương lai.")
        ai_stop = now + timedelta(minutes=request.predicted_minutes)
        if request.predicted_full_at is not None:
            supplied = self._utc(request.predicted_full_at)
            if supplied > now:
                ai_stop = supplied
        absolute = now + timedelta(minutes=self.config.max_session_minutes or 0)
        if request.strategy == ChargingStrategy.TARGET_SOC:
            effective = min(ai_stop, deadline)
        elif request.strategy == ChargingStrategy.DEADLINE:
            effective = deadline
        else:
            effective = min(ai_stop, deadline)
        return ai_stop, deadline, min(effective, absolute), absolute

    def start(
        self, request: AutomaticChargingSessionRequest, idempotency_key: str
    ) -> SmartChargingSession:
        key = idempotency_key.strip()
        if not key:
            raise GatewayError("IDEMPOTENCY_KEY_REQUIRED", "Thiếu Idempotency-Key.")
        with self._command_lock:
            existing = self.store.get_by_idempotency_key(key)
            if existing is not None:
                return existing
            self._validate_config()
            if not request.acknowledge_estimated_soc:
                raise GatewayError(
                    "ESTIMATED_SOC_ACK_REQUIRED",
                    "Cần xác nhận SOC là giá trị ước tính trước khi bắt đầu.",
                )
            active = self.store.current()
            if active is not None:
                raise GatewayError(
                    "ACTIVE_SESSION_EXISTS",
                    "Đã có một phiên sạc đang hoạt động.",
                    status_code=409,
                    session_id=active.session_id,
                )
            try:
                before = self.shelly.get_status()
            except ShellyUnavailableError as exc:
                raise GatewayError(
                    "SHELLY_UNAVAILABLE",
                    "Gateway không liên lạc được với Shelly.",
                    status_code=503,
                    retryable=True,
                ) from exc
            if not before.online:
                raise GatewayError("SHELLY_OFFLINE", "Shelly đang offline.", status_code=503, retryable=True)
            self._last_status_at = self.now()

            now = self.now()
            ai_stop, deadline, effective, absolute = self._planned_times(request, now)
            effective_shadow = self.config.shadow_mode or not self.config.automatic_cutoff
            hardware_timeout_seconds = max(60, int((effective - now).total_seconds()) + 60)
            session = SmartChargingSession(
                session_id=str(uuid4()),
                idempotency_key=key,
                vehicle_id=request.vehicle_id,
                state=ChargingSessionState.STARTING,
                strategy=request.strategy,
                start_soc=request.start_soc,
                target_soc=request.target_soc,
                predicted_minutes=request.predicted_minutes,
                charging_mode=request.charging_mode,
                prediction_source=request.prediction_source,
                prediction_confidence=request.prediction_confidence,
                estimated_capacity_wh=request.estimated_capacity_wh,
                created_at=now,
                updated_at=now,
                ai_stop_at=ai_stop,
                hard_deadline_at=deadline,
                effective_stop_at=effective,
                absolute_safety_stop_at=absolute,
                baseline_energy_wh=before.energy_wh,
                last_meter_energy_wh=before.energy_wh,
                shadow_mode=effective_shadow,
                hardware_timeout_seconds=hardware_timeout_seconds,
            )
            self.store.create(session)
            try:
                command = self.shelly.set_relay(True, auto_off_delay_seconds=hardware_timeout_seconds)
                readback = self.shelly.get_status()
                if not command.success or not readback.relay:
                    raise ShellyUnavailableError("Relay ON readback failed")
            except ShellyUnavailableError as exc:
                try:
                    self.shelly.set_relay(False)
                except ShellyUnavailableError:
                    pass
                failed = session.model_copy(update={
                    "state": ChargingSessionState.FAILED,
                    "stop_reason": ChargingStopReason.COMMAND_FAILED,
                    "last_error": "Không xác minh được relay đã bật.",
                    "command_failures": session.command_failures + 1,
                    "updated_at": self.now(),
                    "version": session.version + 1,
                })
                self.store.save(failed)
                raise GatewayError(
                    "RELAY_VERIFICATION_FAILED",
                    failed.last_error or "Không thể bật relay.",
                    status_code=503,
                    retryable=True,
                    session_id=failed.session_id,
                ) from exc
            active_session = session.model_copy(update={
                "state": ChargingSessionState.ACTIVE,
                "started_at": self.now(),
                "relay_verified": True,
                "hardware_timeout_seconds": hardware_timeout_seconds,
                "updated_at": self.now(),
                "version": session.version + 1,
            })
            return self.store.save(active_session)


    def get(self, session_id: str) -> SmartChargingSession:
        session = self.store.get(session_id)
        if session is None:
            raise GatewayError("SESSION_NOT_FOUND", "Không tìm thấy phiên sạc.", status_code=404)
        return session

    def stop(
        self,
        session_id: str,
        *,
        reason: ChargingStopReason = ChargingStopReason.MANUAL,
        expected_version: int | None = None,
        user_stop_reason: str = "none",
    ) -> SmartChargingSession:
        with self._command_lock:
            session = self.get(session_id)
            if session.state in TERMINAL_SESSION_STATES:
                return session
            if expected_version is not None and session.version != expected_version:
                raise GatewayError(
                    "VERSION_CONFLICT",
                    "Phiên đã thay đổi; hãy tải lại trạng thái.",
                    status_code=409,
                    session_id=session_id,
                )
            stopping = session.model_copy(update={
                "state": ChargingSessionState.STOPPING,
                "updated_at": self.now(),
                "version": session.version + 1,
            })
            self.store.save(stopping)
            verified_off = False
            try:
                command = self.shelly.set_relay(False)
            except ShellyUnavailableError:
                command = None
            if command is not None:
                for _ in range(max(1, self.config.readback_attempts)):
                    try:
                        status = self.shelly.get_status()
                    except ShellyUnavailableError:
                        continue
                    if command.success and not status.relay:
                        verified_off = True
                        break
            now = self.now()
            if not verified_off:
                failed = stopping.model_copy(update={
                    "state": ChargingSessionState.FAILED,
                    "stop_reason": ChargingStopReason.COMMAND_FAILED,
                    "last_error": "Đã gửi lệnh OFF nhưng chưa xác minh được relay.",
                    "command_failures": stopping.command_failures + 1,
                    "updated_at": now,
                    "version": stopping.version + 1,
                })
                self.store.save(failed)
                raise GatewayError(
                    "RELAY_VERIFICATION_FAILED",
                    failed.last_error or "Không xác minh được relay OFF.",
                    status_code=503,
                    retryable=True,
                    session_id=session_id,
                )
            terminal_state = (
                ChargingSessionState.CANCELLED
                if reason == ChargingStopReason.MANUAL
                else ChargingSessionState.COMPLETED
            )
            gain = (stopping.actual_end_soc - stopping.start_soc) if stopping.actual_end_soc is not None else None
            wh_per_soc = round(stopping.energy_used_wh / gain, 2) if (gain is not None and gain > 0) else None
            duration_s = max(0, int((now - (stopping.started_at or stopping.created_at)).total_seconds()))
            training_eligible = (
                terminal_state == ChargingSessionState.COMPLETED
                and stopping.energy_quality == "good"
                and stopping.energy_used_wh > 0
                and duration_s >= 1200
                and (gain is not None and gain >= 10.0)
            )
            completed = stopping.model_copy(update={
                "state": terminal_state,
                "stop_reason": reason,
                "stopped_at": now,
                "relay_verified": True,
                "updated_at": now,
                "version": stopping.version + 1,
                "user_stop_reason": user_stop_reason,
                "wh_per_soc_percent": wh_per_soc,
                "training_eligible": training_eligible,
            })
            return self.store.save(completed)


    def patch(
        self, session_id: str, request: ChargingSessionPatchRequest
    ) -> SmartChargingSession:
        with self._command_lock:
            session = self.get(session_id)
            if session.state in TERMINAL_SESSION_STATES:
                raise GatewayError("SESSION_TERMINAL", "Không thể sửa phiên đã kết thúc.", status_code=409)
            if session.version != request.expected_version:
                raise GatewayError("VERSION_CONFLICT", "Phiên đã thay đổi; hãy tải lại trạng thái.", status_code=409)
            now = self.now()
            deadline = session.hard_deadline_at
            if request.hard_deadline_at is not None:
                candidate = self._utc(request.hard_deadline_at)
                if candidate <= now:
                    raise GatewayError("INVALID_TIMESTAMP", "Hạn dừng phải ở tương lai.")
                if candidate > deadline and not request.acknowledge_extension:
                    raise GatewayError("EXTENSION_ACK_REQUIRED", "Cần xác nhận khi gia hạn phiên sạc.")
                deadline = candidate
            target = request.target_soc if request.target_soc is not None else session.target_soc
            if target <= session.start_soc:
                raise GatewayError("INVALID_SOC", "SOC mục tiêu phải lớn hơn SOC hiện tại.")
            minutes = request.predicted_minutes or session.predicted_minutes
            ai_stop = session.started_at + timedelta(minutes=minutes) if session.started_at else now + timedelta(minutes=minutes)
            if session.strategy == ChargingStrategy.TARGET_SOC:
                effective = min(ai_stop, deadline)
            elif session.strategy == ChargingStrategy.DEADLINE:
                effective = deadline
            else:
                effective = min(ai_stop, deadline)
            effective = min(effective, session.absolute_safety_stop_at)
            updated = session.model_copy(update={
                "hard_deadline_at": deadline,
                "target_soc": target,
                "predicted_minutes": minutes,
                "ai_stop_at": ai_stop,
                "effective_stop_at": effective,
                "updated_at": now,
                "version": session.version + 1,
            })
            return self.store.save(updated)

    def _update_energy(
        self, session: SmartChargingSession, energy_wh: float
    ) -> SmartChargingSession:
        baseline = session.baseline_energy_wh
        if baseline is None:
            return session.model_copy(update={
                "baseline_energy_wh": energy_wh,
                "last_meter_energy_wh": energy_wh,
            })
        quality = session.energy_quality
        previous = session.last_meter_energy_wh if session.last_meter_energy_wh is not None else baseline
        reset_threshold = max(25.0, abs(previous) * 0.20)
        if energy_wh < previous - reset_threshold:
            used = 0.0
            quality = "meter_reset"
            baseline = energy_wh
        elif energy_wh < previous:
            # Shelly may report a few Wh of counter jitter; do not classify it
            # as a lifetime-meter reset or inflate the session delta.
            used = session.energy_used_wh
        else:
            used = max(session.energy_used_wh, max(0.0, energy_wh - baseline))
        estimated_soc = None
        if session.estimated_capacity_wh:
            estimated_soc = min(100.0, session.start_soc + used / session.estimated_capacity_wh * 100)
        return session.model_copy(update={
            "energy_used_wh": used,
            "energy_quality": quality,
            "baseline_energy_wh": baseline,
            "last_meter_energy_wh": energy_wh,
            "estimated_soc": estimated_soc,
        })

    def _due_reason(self, session: SmartChargingSession, now: datetime) -> ChargingStopReason | None:
        if now >= session.absolute_safety_stop_at:
            return ChargingStopReason.ABSOLUTE_SAFETY
        if now < session.effective_stop_at:
            return None
        if now >= session.hard_deadline_at and session.hard_deadline_at <= session.ai_stop_at:
            return ChargingStopReason.DEADLINE
        if session.strategy == ChargingStrategy.TARGET_SOC:
            return ChargingStopReason.TARGET_SOC
        if session.strategy == ChargingStrategy.DEADLINE:
            return ChargingStopReason.DEADLINE
        return ChargingStopReason.SMART_COMBINED

    def tick(self) -> SmartChargingSession | None:
        with self._command_lock:
            session = self.store.current()
            if session is None or session.state != ChargingSessionState.ACTIVE:
                return session
            try:
                status = self.shelly.get_status()
            except ShellyUnavailableError:
                violation = self.safety_monitor.stale(self._last_status_at, self.now())
                if violation is not None:
                    return self._safety_stop(session, violation)
                return session
            now = self.now()
            self._last_status_at = now
            session = self._update_energy(session, status.energy_wh)
            
            # Record telemetry sample for fine-tuning
            sample = {
                "t": int(now.timestamp()),
                "elapsed_s": int((now - (session.started_at or session.created_at)).total_seconds()),
                "v": round(status.voltage_v, 2),
                "a": round(status.current_a, 2),
                "p": round(status.power_w, 2),
                "e_wh": round(session.energy_used_wh, 2),
                "temp_shelly": status.temperature_c,
                "temp_bat": session.battery_temperature_c,
                "est_soc": round(session.estimated_soc, 1) if session.estimated_soc is not None else None,
            }
            samples = [*session.telemetry_samples[-999:], sample]

            if not status.relay:
                interrupted = session.model_copy(update={
                    "state": ChargingSessionState.INTERRUPTED,
                    "stop_reason": ChargingStopReason.RELAY_OFF,
                    "stopped_at": now,
                    "relay_verified": True,
                    "shelly_temperature_c": status.temperature_c,
                    "telemetry_samples": samples,
                    "updated_at": now,
                    "version": session.version + 1,
                })
                return self.store.save(interrupted)
            violation = self.safety_monitor.evaluate(status, battery_temperature_c=session.battery_temperature_c)
            if violation is not None:
                return self._safety_stop(session, violation)
            reason = self._due_reason(session, now)
            if reason is not None:
                if session.shadow_mode:
                    if session.would_have_turned_off_at is None:
                        session = session.model_copy(update={
                            "would_have_turned_off_at": now,
                            "shelly_temperature_c": status.temperature_c,
                            "telemetry_samples": samples,
                            "updated_at": now,
                            "version": session.version + 1,
                        })
                        return self.store.save(session)
                    return session
                return self.stop(session.session_id, reason=reason)
            updated = session.model_copy(update={
                "shelly_temperature_c": status.temperature_c,
                "telemetry_samples": samples,
                "updated_at": now,
                "version": session.version + 1,
            })

            return self.store.save(updated)

    def _safety_stop(self, session: SmartChargingSession, violation) -> SmartChargingSession:
        now = self.now()
        try:
            reason = ChargingStopReason(violation.kind)
        except ValueError:
            reason = ChargingStopReason.COMMAND_FAILED
        event = SafetyEvent(
            event_id=str(uuid4()),
            type=violation.kind,
            severity="critical",
            observed_value=violation.observed_value,
            threshold=violation.threshold,
            timestamp=now,
            relay_before=True,
        )
        events = [*session.safety_events, event]
        verified = False
        relay_after = None
        try:
            command = self.shelly.set_relay(False)
            for _ in range(max(1, self.config.readback_attempts)):
                status = self.shelly.get_status()
                relay_after = status.relay
                if command.success and not status.relay:
                    verified = True
                    break
        except ShellyUnavailableError:
            verified = False
        events[-1] = event.model_copy(update={
            "relay_after": relay_after,
            "off_verified": verified,
        })
        terminal = session.model_copy(update={
            "state": ChargingSessionState.INTERRUPTED if verified else ChargingSessionState.FAILED,
            "stop_reason": reason,
            "stopped_at": now,
            "relay_verified": verified,
            "last_error": None if verified else "Không xác minh được OFF sau sự kiện an toàn.",
            "safety_events": events,
            "updated_at": now,
            "version": session.version + 1,
        })
        self.store.save(terminal)
        if not verified:
            raise GatewayError(
                "RELAY_VERIFICATION_FAILED",
                terminal.last_error or "Không xác minh được OFF an toàn.",
                status_code=503,
                retryable=True,
                session_id=session.session_id,
            )
        return terminal

    def recover(self) -> SmartChargingSession | None:
        """Restore without ever issuing ON after a gateway restart."""
        with self._command_lock:
            session = self.store.current()
            if session is None:
                return None
            try:
                status = self.shelly.get_status()
            except ShellyUnavailableError:
                return session
            if not status.relay:
                now = self.now()
                if session.state == ChargingSessionState.STOPPING:
                    return self.store.save(session.model_copy(update={
                        "state": ChargingSessionState.CANCELLED,
                        "stop_reason": ChargingStopReason.MANUAL,
                        "stopped_at": now,
                        "relay_verified": True,
                        "updated_at": now,
                        "version": session.version + 1,
                    }))
                return self.store.save(session.model_copy(update={
                    "state": ChargingSessionState.INTERRUPTED,
                    "stop_reason": ChargingStopReason.RELAY_OFF,
                    "stopped_at": now,
                    "relay_verified": True,
                    "updated_at": now,
                    "version": session.version + 1,
                }))
            if session.state == ChargingSessionState.STARTING:
                now = self.now()
                session = self.store.save(session.model_copy(update={
                    "state": ChargingSessionState.ACTIVE,
                    "started_at": session.started_at or now,
                    "relay_verified": True,
                    "updated_at": now,
                    "version": session.version + 1,
                }))
            if self.now() >= session.effective_stop_at and not session.shadow_mode:
                return self.stop(session.session_id, reason=ChargingStopReason.GATEWAY_RESTART_EXPIRED)
            return session


def default_database_path() -> Path:
    raw = os.getenv("SMART_CHARGER_DB_PATH", "").strip()
    return Path(raw) if raw else Path(__file__).resolve().parent / "state" / "smart_charging.sqlite3"


def build_smart_controller(shelly: ShellyClient | None = None) -> SmartChargingController:
    return SmartChargingController(
        SmartSessionStore(default_database_path()),
        shelly or ShellyClient(),
        SmartChargingConfig.from_env(),
    )
