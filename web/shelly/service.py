from __future__ import annotations

import os
import secrets
import time
import uuid
from datetime import datetime, timedelta

from .models import ChargePreview, ChargingSession, DeviceBinding, utcnow
from .providers import ProviderError


class SmartChargeError(RuntimeError):
    def __init__(self, code: str, message: str, status: int = 400, retryable: bool = False):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status
        self.retryable = retryable


class SmartChargeService:
    def __init__(self, repository, provider, predictor, sleeper=time.sleep, clock=utcnow):
        self.repository = repository
        self.provider = provider
        self.predictor = predictor
        self.sleep = sleeper
        self.clock = clock
        self.max_minutes = int(os.environ.get("SMART_CHARGE_MAX_MINUTES", "360"))

    def capabilities(self, uid: str) -> dict:
        binding = self.binding(uid)
        status = bool(getattr(self.provider, "supports_status", False))
        manual_off = bool(getattr(self.provider, "supports_manual_off", False))
        manual_on = bool(getattr(self.provider, "supports_manual_on", False))
        timer = bool(getattr(self.provider, "supports_device_timer", False))
        power = bool(binding and binding.power_meter_verified)
        safe_boot = bool(binding and binding.safe_boot_verified)
        no_load = bool(binding and binding.no_load_test_verified)
        return {
            "canReadStatus": status,
            "canManualOn": manual_on and timer,
            "canManualOff": manual_off,
            "supportsDeviceTimer": timer,
            "canReadPower": power,
            "canConfigureSafeBoot": False,
            "cloudAvailable": binding is not None and status,
            "lanAvailable": False,
            "safeBootVerified": safe_boot,
            "noLoadTestVerified": no_load,
            "readyForControl": bool(
                binding and status and manual_off and manual_on and timer and power and safe_boot and no_load
            ),
            "provider": self.provider.name,
        }

    def binding(self, uid: str) -> DeviceBinding | None:
        binding = self.repository.get_binding(uid)
        if binding is None and self.provider.name == "legacy":
            device_id = os.environ.get("SHELLY_LEGACY_DEVICE_ID", "").strip()
            if device_id:
                binding = DeviceBinding(
                    device_id=device_id,
                    display_name=os.environ.get("SHELLY_LEGACY_DEVICE_NAME", "Shelly sạc xe"),
                    model="S3PL-00112EU",
                    generation=3,
                    provider="legacy",
                    online=True,
                    power_meter_verified=True,
                )
                self.repository.save_binding(uid, binding)
        return binding

    def create_preview(self, uid: str, payload: dict) -> ChargePreview:
        vehicle_id = str(payload.get("vehicleId") or "").strip()
        current = float(payload.get("currentSoc", -1))
        target = float(payload.get("targetSoc", -1))
        if not vehicle_id:
            raise SmartChargeError("invalidPreview", "Thiếu vehicleId")
        if not 0 <= current < target <= 100:
            raise SmartChargeError("invalidSoc", "Target SOC phải lớn hơn SOC hiện tại và không quá 100%")
        result = self.predictor(payload)
        seconds = int(round(float(
            result.get("predictedDurationSeconds")
            or float(result.get("predictedMinutes") or 0) * 60
        )))
        minutes = int(round(seconds / 60))
        if minutes <= 0 or minutes > self.max_minutes:
            raise SmartChargeError("unsafeDuration", "ETA phải lớn hơn 0 và không vượt quá 6 giờ")
        now = self.clock()
        source = str(result.get("modelSource") or "physics_fallback")
        runtime_health = str(result.get("runtimeHealth") or ("loaded" if source == "ai_model" else "fallback"))
        eligible = bool(result.get("aiChargeEligible", source == "ai_model" and runtime_health == "loaded"))
        preview = ChargePreview(
            preview_id=secrets.token_urlsafe(24),
            vehicle_id=vehicle_id,
            current_soc=current,
            target_soc=target,
            predicted_minutes=minutes,
            predicted_duration_seconds=seconds,
            predicted_stop_at=now + timedelta(minutes=minutes),
            model_source=source,
            model_key=str(result.get("modelKey") or "charging_time"),
            model_version=str(result.get("modelVersion") or "unknown"),
            runtime_health=runtime_health,
            confidence=float(result["confidence"]) if result.get("confidence") is not None else None,
            warnings=[str(item) for item in result.get("warnings", [])],
            fallback_reason=(str(result["fallbackReason"]) if result.get("fallbackReason") else None),
            analyzed_at=_datetime(result.get("analyzedAt")) or now,
            ai_charge_eligible=eligible,
            expires_at=now + timedelta(minutes=10),
        )
        self.repository.save_preview(uid, preview)
        self.repository.append_audit(uid, "preview_created", preview_id=preview.preview_id)
        return preview

    def start(self, uid: str, preview_id: str, idempotency_key: str) -> ChargingSession:
        if not idempotency_key or len(idempotency_key) > 160:
            raise SmartChargeError("invalidIdempotencyKey", "Thiếu Idempotency-Key")
        existing = self.repository.get_by_idempotency(uid, idempotency_key)
        if existing:
            return existing
        binding = self.binding(uid)
        if not binding:
            raise SmartChargeError("notConfigured", "Shelly chưa được kết nối", 409)
        if binding.connection_mode != "server_cloud":
            raise SmartChargeError("wrongConnectionMode", "Thiết bị đang dùng Advanced Direct", 409)
        active = self.repository.current_session(uid)
        if active:
            raise SmartChargeError("activeSessionConflict", "Đang có một phiên sạc hoạt động", 409)
        preview = self.repository.get_preview(uid, preview_id)
        now = self.clock()
        if not preview or preview.expires_at <= now:
            raise SmartChargeError("previewExpired", "Dự đoán đã hết hạn; hãy dự đoán lại", 409)
        if not preview.ai_charge_eligible:
            raise SmartChargeError(
                "aiPredictionUnavailable",
                "Model AI thật chưa sẵn sàng; chỉ được Bật Sạc với timer thủ công.",
                409,
            )
        if not self.provider.supports_device_timer:
            raise SmartChargeError(
                "providerTimerUnsupported",
                "Provider chưa được xác minh hỗ trợ timer trên Shelly",
                503,
            )
        try:
            status = self.provider.get_status(binding)
        except ProviderError as exc:
            raise self._provider_error(exc) from exc
        if not status.online:
            raise SmartChargeError("deviceOffline", "Shelly đang Offline", 409, True)
        duration = preview.predicted_minutes * 60
        session = ChargingSession(
            session_id=str(uuid.uuid4()),
            device_id=binding.device_id,
            vehicle_id=preview.vehicle_id,
            state="arming",
            start_soc=preview.current_soc,
            target_soc=preview.target_soc,
            estimated_soc=preview.current_soc,
            predicted_minutes=preview.predicted_minutes,
            predicted_duration_seconds=preview.predicted_duration_seconds,
            prediction_source=preview.model_source,
            prediction_confidence=preview.confidence,
            strategy="ai_target",
            model_key=preview.model_key,
            model_version=preview.model_version,
            runtime_health=preview.runtime_health,
            prediction_warnings=list(preview.warnings),
            fallback_reason=preview.fallback_reason,
            prediction_analyzed_at=preview.analyzed_at,
            created_at=now,
            updated_at=now,
            ai_stop_at=preview.predicted_stop_at,
            effective_stop_at=preview.predicted_stop_at,
            absolute_safety_stop_at=now + timedelta(minutes=self.max_minutes),
            idempotency_key=idempotency_key,
            baseline_energy_wh=status.energy_wh,
        )
        self.repository.save_session(uid, session)
        try:
            self.provider.turn_on_with_timer(binding, duration)
            self.sleep(1)
            verified = None
            for _ in range(10):
                current = self.provider.get_status(binding)
                if current.device_id == binding.device_id and current.relay and current.timer_remaining > 0:
                    if current.temperature_c is not None and current.temperature_c >= 80:
                        raise ProviderError("overtemperature", "Shelly quá nhiệt")
                    if current.power_w > 2500:
                        raise ProviderError("overpower", "Công suất vượt 2500W")
                    verified = current
                    break
                self.sleep(1)
            if not verified:
                raise ProviderError("timerNotArmed", "Không xác minh được timer trên Shelly")
            session.state = "active"
            session.relay_verified = True
            session.timer_verified = True
            session.updated_at = self.clock()
            session.version += 1
            self.repository.save_session(uid, session)
            self.repository.append_audit(uid, "session_started", session_id=session.session_id, device_id=binding.device_id)
            return session
        except ProviderError as exc:
            try:
                self.provider.turn_off(binding)
            except ProviderError:
                pass
            session.state = "failed"
            session.stop_reason = "command_failed"
            session.last_error = exc.code
            session.stopped_at = self.clock()
            session.updated_at = session.stopped_at
            session.version += 1
            self.repository.save_session(uid, session)
            self.repository.append_audit(uid, "session_start_failed", session_id=session.session_id, error=exc.code)
            raise self._provider_error(exc) from exc

    def status(self, uid: str):
        binding = self.binding(uid)
        if not binding:
            raise SmartChargeError("notConfigured", "Shelly chưa được kết nối", 404)
        try:
            status = self.provider.get_status(binding)
            self._reconcile_with_status(uid, status)
            return status
        except ProviderError as exc:
            raise self._provider_error(exc) from exc

    def stop(self, uid: str, session_id: str | None = None) -> ChargingSession | None:
        binding = self.binding(uid)
        if not binding:
            raise SmartChargeError("notConfigured", "Shelly chưa được kết nối", 404)
        session = self.repository.current_session(uid)
        if session_id and session and session.session_id != session_id:
            raise SmartChargeError("sessionNotFound", "Không tìm thấy phiên sạc", 404)
        try:
            self.provider.turn_off(binding)
            verified = None
            for _ in range(3):
                status = self.provider.get_status(binding)
                if not status.relay:
                    verified = status
                    break
                self.sleep(1)
            if not verified:
                raise ProviderError("relayUnverified", "Không xác minh được relay OFF")
        except ProviderError as exc:
            raise self._provider_error(exc) from exc
        if session:
            now = self.clock()
            session.state = "cancelled"
            session.stop_reason = "manual"
            session.stopped_at = now
            session.updated_at = now
            session.relay_verified = True
            session.energy_used_wh = max(0, verified.energy_wh - (session.baseline_energy_wh or verified.energy_wh))
            session.version += 1
            self.repository.save_session(uid, session)
            self.repository.upsert_charge_log(uid, session)
            self.repository.append_audit(uid, "relay_off_verified", session_id=session.session_id, reason="manual")
        return session

    def manual_on(
        self,
        uid: str,
        duration_seconds: int,
        idempotency_key: str,
        vehicle_id: str = "manual",
        current_soc: float = 0,
    ) -> ChargingSession:
        """Manual ON is permitted only with a device-side safety timer."""
        binding = self.binding(uid)
        if not binding:
            raise SmartChargeError("notConfigured", "Shelly chưa được kết nối", 404)
        duration_seconds = int(duration_seconds)
        if duration_seconds < 5 or duration_seconds > self.max_minutes * 60:
            raise SmartChargeError("unsafeDuration", "Safety timer phải từ 5 giây đến 6 giờ")
        if not idempotency_key or len(idempotency_key) > 160:
            raise SmartChargeError("invalidIdempotencyKey", "Thiếu Idempotency-Key")
        existing = self.repository.get_by_idempotency(uid, idempotency_key)
        if existing:
            return existing
        if self.repository.current_session(uid):
            raise SmartChargeError("activeSessionConflict", "Đang có một phiên sạc hoạt động", 409)
        if not self.provider.supports_device_timer:
            raise SmartChargeError("providerTimerUnsupported", "Provider chưa hỗ trợ timer trên thiết bị", 503)
        now = self.clock()
        try:
            before = self.provider.get_status(binding)
        except ProviderError as exc:
            raise self._provider_error(exc) from exc
        session = ChargingSession(
            session_id=str(uuid.uuid4()),
            device_id=binding.device_id,
            vehicle_id=vehicle_id or "manual",
            state="arming",
            strategy="manual_timed",
            start_soc=max(0, min(100, float(current_soc))),
            target_soc=max(0, min(100, float(current_soc))),
            predicted_minutes=max(1, int(round(duration_seconds / 60))),
            predicted_duration_seconds=duration_seconds,
            prediction_source="manual_timer",
            prediction_confidence=None,
            model_key="none",
            model_version="manual",
            runtime_health="not_applicable",
            created_at=now,
            updated_at=now,
            ai_stop_at=now + timedelta(seconds=duration_seconds),
            effective_stop_at=now + timedelta(seconds=duration_seconds),
            absolute_safety_stop_at=now + timedelta(minutes=self.max_minutes),
            idempotency_key=idempotency_key,
            estimated_soc=max(0, min(100, float(current_soc))),
            baseline_energy_wh=before.energy_wh,
        )
        self.repository.save_session(uid, session)
        try:
            self.provider.turn_on_with_timer(binding, duration_seconds)
            self.sleep(1)
            status = self.provider.get_status(binding)
            if not status.relay or status.timer_remaining <= 0:
                raise ProviderError("timerNotArmed", "Không xác minh được safety timer")
            session.state = "active"
            session.relay_verified = True
            session.timer_verified = True
            session.updated_at = self.clock()
            session.version += 1
            self.repository.save_session(uid, session)
            self.repository.append_audit(uid, "manual_on_verified", session_id=session.session_id, device_id=binding.device_id, duration_seconds=duration_seconds)
            return session
        except ProviderError as exc:
            try:
                self.provider.turn_off(binding)
            except ProviderError:
                pass
            session.state = "failed"
            session.stop_reason = "command_failed"
            session.last_error = exc.code
            session.stopped_at = self.clock()
            session.updated_at = session.stopped_at
            session.version += 1
            self.repository.save_session(uid, session)
            self.repository.upsert_charge_log(uid, session)
            raise self._provider_error(exc) from exc

    def current(self, uid: str) -> ChargingSession | None:
        session = self.repository.current_session(uid)
        if not session:
            return None
        binding = self.binding(uid)
        if not binding:
            return session
        try:
            status = self.provider.get_status(binding)
        except ProviderError:
            return session
        return self._reconcile_with_status(uid, status) or self.repository.current_session(uid)

    def _reconcile_with_status(self, uid: str, status) -> ChargingSession | None:
        session = self.repository.current_session(uid)
        if not session:
            return None
        now = self.clock()
        if status.relay:
            if status.timer_remaining <= 0:
                binding = self.binding(uid)
                try:
                    if binding:
                        self.provider.turn_off(binding)
                except ProviderError:
                    pass
                session.state = "failed"
                session.stop_reason = "command_failed"
                session.last_error = "timerNotArmed"
                session.stopped_at = now
                session.updated_at = now
                session.version += 1
                self.repository.save_session(uid, session)
                self.repository.upsert_charge_log(uid, session)
            return session
        near_planned = abs((now - session.effective_stop_at).total_seconds()) <= 120
        session.state = "completed" if near_planned else "interrupted"
        session.stop_reason = "planned_timer" if near_planned else "relay_off"
        session.stopped_at = now
        session.updated_at = now
        session.relay_verified = True
        session.energy_used_wh = max(0, status.energy_wh - (session.baseline_energy_wh or status.energy_wh))
        session.version += 1
        self.repository.save_session(uid, session)
        self.repository.upsert_charge_log(uid, session)
        return session

    def _provider_error(self, exc: ProviderError) -> SmartChargeError:
        status = 401 if exc.code == "needsReauthentication" else 503
        return SmartChargeError(exc.code, exc.message, status, exc.retryable)


def _datetime(value) -> datetime | None:
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    return None
