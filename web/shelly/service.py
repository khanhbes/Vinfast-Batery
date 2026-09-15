from __future__ import annotations

import os
import secrets
import time
import uuid
import math
from copy import deepcopy
from datetime import datetime, timedelta

from .models import (
    ChargePreview,
    ChargingSession,
    DeviceBinding,
    EtaCandidate,
    PersonalChargingProfile,
    SmartChargeSafetyEvent,
    SmartChargeSafetyPolicy,
    utcnow,
)
from .providers import ProviderError
from .charging_fusion import fuse_charging_eta
from .personalization import evaluate_training, update_profile
from .personal_model_registry import PersonalModelRegistry


class SmartChargeError(RuntimeError):
    def __init__(self, code: str, message: str, status: int = 400, retryable: bool = False):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status
        self.retryable = retryable


class SmartChargeService:
    def __init__(self, repository, provider, predictor, sleeper=time.sleep, clock=utcnow,
                 model_registry=None, push_notifier=None):
        self.repository = repository
        self.provider = provider
        self.predictor = predictor
        self.sleep = sleeper
        self.clock = clock
        self.model_registry = model_registry or PersonalModelRegistry(
            getattr(repository, "db", None)
        )
        # The ten-hour limit is a hard safety boundary, not merely a default.
        # Clamp deployment configuration so an accidental environment value
        # can never permit a longer device timer or deadline.
        try:
            configured_max = int(os.environ.get("SMART_CHARGE_MAX_MINUTES", "600"))
        except (TypeError, ValueError):
            configured_max = 600
        self.max_minutes = max(1, min(configured_max, 600))
        self.safety_policy = SmartChargeSafetyPolicy()
        self._unsafe_samples: dict[tuple[str, str], int] = {}
        self._last_telemetry_at: dict[str, datetime] = {}
        self._last_checkpoint_at: dict[str, datetime] = {}
        self.push_notifier = push_notifier

    def _emit_push(self, uid, session):
        if self.push_notifier and session.state in {'completed', 'cancelled', 'interrupted', 'failed'}:
            try:
                self.push_notifier(
                    uid,
                    session_id=session.session_id,
                    vehicle_id=getattr(session, 'vehicle_id', None),
                    state=session.state,
                    target_percent=getattr(session, 'target_soc', None),
                )
            except Exception:
                # Notification delivery must never roll back durable charging state.
                pass

    def capabilities(self, uid: str, vehicle_id: str | None = None) -> dict:
        binding = self.binding(uid, vehicle_id)
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

    def binding(self, uid: str, vehicle_id: str | None = None) -> DeviceBinding | None:
        # Migrate the unambiguous V3 single-device shape before resolving a
        # vehicle-scoped request. Ambiguous accounts remain unbound.
        self.repository.migrate_single_vehicle_binding(uid)
        binding = self.repository.get_binding(uid, vehicle_id)
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
        vehicle = self._owned_vehicle(uid, vehicle_id)
        if not 0 <= current < target <= 100:
            raise SmartChargeError("invalidSoc", "Target SOC phải lớn hơn SOC hiện tại và không quá 100%")
        trusted_payload = self._prediction_payload(payload, vehicle)
        if not _optional_float(trusted_payload.get("estimatedCapacityWh")):
            raise SmartChargeError(
                "capacityUnavailable",
                "Xe chưa có dung lượng pin đã được xác minh; hãy cập nhật catalog hoặc dùng Sạc hẹn giờ.",
                409,
            )
        result = self.predictor(trusted_payload)
        global_seconds = int(round(float(
            result.get("predictedDurationSeconds")
            or float(result.get("predictedMinutes") or 0) * 60
        )))
        profile = self.repository.get_personal_profile(uid, vehicle_id)
        model_version = str(result.get("modelVersion") or "unknown")
        if profile and profile.consent_enabled and profile.base_model_version != model_version:
            if profile.base_model_version != "unknown":
                profile.quality_confidence *= 0.70
            profile.base_model_version = model_version
            profile.updated_at = self.clock()
            self.repository.save_personal_profile(profile)
        fusion = fuse_charging_eta(trusted_payload, result, global_seconds, profile)
        candidates = fusion.candidates
        seconds = fusion.duration_seconds
        if seconds <= 0 or seconds > self.max_minutes * 60:
            raise SmartChargeError("unsafeDuration", "ETA phải lớn hơn 0 và không vượt quá 10 giờ")
        minutes = int(round(seconds / 60))
        if minutes <= 0:
            raise SmartChargeError("unsafeDuration", "ETA phải lớn hơn 0 và không vượt quá 10 giờ")
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
            predicted_stop_at=now + timedelta(seconds=seconds),
            model_source=source,
            model_key=str(result.get("modelKey") or "charging_time"),
            model_version=model_version,
            runtime_health=runtime_health,
            confidence=float(result["confidence"]) if result.get("confidence") is not None else None,
            warnings=[str(item) for item in result.get("warnings", [])],
            fallback_reason=(str(result["fallbackReason"]) if result.get("fallbackReason") else None),
            analyzed_at=_datetime(result.get("analyzedAt")) or now,
            ai_charge_eligible=eligible,
            expires_at=now + timedelta(minutes=10),
            eta_candidates=candidates,
            fusion_reason=fusion.reason,
            profile_version=(f"profile-v{profile.profile_version}" if profile and profile.consent_enabled else None),
            adapter_version=(profile.adapter_version if profile and profile.active else None),
            capacity_confidence=_optional_float(payload.get("capacityConfidence")),
            efficiency_confidence=_optional_float(payload.get("efficiencyConfidence")),
            effective_capacity_wh=fusion.effective_capacity_wh,
            personalization_stage=fusion.stage,
            guardrail_clamped=fusion.clamped,
            guardrail_warnings=list(fusion.warnings),
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
        preview = self.repository.get_preview(uid, preview_id)
        now = self.clock()
        if not preview or preview.expires_at <= now:
            raise SmartChargeError("previewExpired", "Dự đoán đã hết hạn; hãy dự đoán lại", 409)
        binding = self.binding(uid, preview.vehicle_id)
        if not binding:
            raise SmartChargeError("notConfigured", "Shelly chưa được kết nối", 409)
        if binding.connection_mode != "server_cloud":
            raise SmartChargeError("wrongConnectionMode", "Thiết bị đang dùng Advanced Direct", 409)
        active = self.repository.current_session(uid, device_id=binding.device_id)
        if active:
            raise SmartChargeError("activeSessionConflict", "Đang có một phiên sạc hoạt động", 409)
        if not preview.ai_charge_eligible:
            raise SmartChargeError(
                "aiPredictionUnavailable",
                "Model AI thật chưa sẵn sàng; chỉ được Bật Sạc với timer thủ công.",
                409,
            )
        vehicle = self._owned_vehicle(uid, preview.vehicle_id)
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
        # Preserve the canonical server-side duration (seconds) from the
        # preview. Reconstructing it from rounded minutes caused the device
        # timer to drift from the ETA shown to the user.
        duration = int(preview.predicted_duration_seconds or 0)
        if duration <= 0 or duration > self.max_minutes * 60:
            raise SmartChargeError(
                "unsafeDuration",
                "ETA phải lớn hơn 0 và không vượt quá 10 giờ",
                400,
            )
        session = ChargingSession(
            session_id=str(uuid.uuid4()),
            device_id=binding.device_id,
            vehicle_id=preview.vehicle_id,
            state="arming",
            start_soc=preview.current_soc,
            target_soc=preview.target_soc,
            # Do not present the starting SOC as an estimate when no trusted
            # capacity is available. Target-SOC mode is blocked by preview;
            # timed charging remains usable with an explicitly unavailable SOC.
            estimated_soc=preview.current_soc if preview.effective_capacity_wh else None,
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
            last_meter_energy_wh=status.energy_wh,
            charging_efficiency=.90,
            capacity_source="personal_calibration" if preview.personalization_stage == "personal" else "vehicle_catalog",
            soc_estimate_source="shelly_energy" if preview.effective_capacity_wh else "unavailable",
            soc_estimate_quality="live" if preview.effective_capacity_wh else "unavailable",
            soc_estimation_version=2,
            eta_candidates=list(preview.eta_candidates),
            fusion_reason=preview.fusion_reason,
            profile_version=preview.profile_version,
            adapter_version=preview.adapter_version,
            owner_uid=uid,
            personalization_stage=preview.personalization_stage,
            base_ai_minutes=_candidate_minutes(preview.eta_candidates, "global_ai"),
            physics_minutes=_candidate_minutes(preview.eta_candidates, "physics"),
            personal_minutes=_candidate_minutes(preview.eta_candidates, "personal"),
            final_minutes=preview.predicted_duration_seconds / 60,
            fusion_weights={item.source: item.weight for item in preview.eta_candidates},
            effective_capacity_wh=preview.effective_capacity_wh,
            nominal_capacity_wh=_optional_float(vehicle.get("nominalCapacityWh")),
            state_of_health=_optional_float(vehicle.get("stateOfHealth")),
            safety_policy_version=self.safety_policy.version,
        )
        if not self.repository.claim_device_session(uid, session.device_id, session.session_id):
            raise SmartChargeError("activeSessionConflict", "Shelly đang được dùng bởi một phiên khác", 409)
        self.repository.save_session(uid, session)
        try:
            self.provider.turn_on_with_timer(binding, duration)
            self.sleep(1)
            verified = None
            for _ in range(10):
                current = self.provider.get_status(binding)
                if current.device_id == binding.device_id and current.relay and current.timer_remaining > 0:
                    if current.temperature_c is not None and current.temperature_c >= self.safety_policy.cutoff_temperature_c:
                        raise ProviderError("overtemperature", f"Shelly quá nhiệt ({current.temperature_c}°C >= {self.safety_policy.cutoff_temperature_c}°C)")
                    if current.power_w > self.safety_policy.cutoff_power_w:
                        raise ProviderError("overpower", f"Công suất vượt ngưỡng ({current.power_w}W > {self.safety_policy.cutoff_power_w}W)")
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
            # ChargeLogs are materialized at terminal state; the runtime
            # session is the single active source during charging.
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
            self.repository.upsert_charge_log(uid, session)
            self.repository.append_audit(uid, "session_start_failed", session_id=session.session_id, error=exc.code)
            self._emit_push(uid, session)
            raise self._provider_error(exc) from exc

    def status(self, uid: str, vehicle_id: str | None = None):
        binding = self.binding(uid, vehicle_id)
        if not binding:
            raise SmartChargeError("notConfigured", "Shelly chưa được kết nối", 404)
        try:
            status = self.provider.get_status(binding)
            self._apply_safety(uid, binding, status)
            self._reconcile_with_status(uid, status, vehicle_id)
            return status
        except ProviderError as exc:
            raise self._provider_error(exc) from exc

    def live(self, uid: str, vehicle_id: str | None = None) -> dict:
        """Single live request for charger status and active session."""
        # Keep status and session reconciliation in one provider read. Calling
        # ``status`` and then ``current_session`` separately caused duplicate
        # Firestore reads on every foreground poll.
        binding = self.binding(uid, vehicle_id)
        if not binding:
            raise SmartChargeError("notConfigured", "Shelly chÆ°a Ä‘Æ°á»£c káº¿t ná»‘i", 404)
        try:
            status = self.provider.get_status(binding)
            self._apply_safety(uid, binding, status)
            session = self._reconcile_with_status(uid, status, vehicle_id)
        except ProviderError as exc:
            raise self._provider_error(exc) from exc
        return {
            "status": status.to_dict() if hasattr(status, "to_dict") else status,
            "session": session.to_dict() if session else None,
            "active": bool(session and session.state in ("arming", "active")),
        }

    def _finalize_session(
        self,
        uid: str,
        session: ChargingSession,
        *,
        state: str,
        stop_reason: str,
        status=None,
        meter_energy_wh: float | None = None,
        user_stop_reason: str | None = None,
    ) -> ChargingSession:
        """Apply every terminal transition through one durable, idempotent path.

        Hardware commands and readback happen before this method.  This method
        only records the observed result, includes the final meter reading,
        releases the device lease through the repository and emits push after
        persistence.  A repeated terminal callback therefore cannot create a
        second history item or move the vehicle SOC backwards.
        """
        if session.state not in ("arming", "active"):
            return session
        now = self.clock()
        # Zero is a valid meter reading, so never use a truthy fallback here.
        final_energy = meter_energy_wh
        if final_energy is None and status is not None:
            final_energy = status.energy_wh
        if final_energy is not None:
            self._ingest_energy(session, final_energy)
        session.state = state
        session.stop_reason = stop_reason
        if user_stop_reason is not None:
            session.user_stop_reason = user_stop_reason
        session.stopped_at = now
        session.updated_at = now
        session.relay_verified = True
        session.version += 1
        self.repository.save_session(uid, session)
        self.repository.upsert_charge_log(uid, session)
        # save_session releases both the in-memory and Firestore device lease.
        self._emit_push(uid, session)
        return session

    def stop(
        self,
        uid: str,
        session_id: str | None = None,
        *,
        expected_version: int | None = None,
        user_stop_reason: str = "none",
        vehicle_id: str | None = None,
    ) -> ChargingSession | None:
        # An explicit session id must resolve that exact session. Using the
        # account-wide first active session breaks when two physical Shellys
        # charge different vehicles concurrently.
        session = (
            self.repository.get_session(uid, session_id)
            if session_id
            else self.repository.current_session(uid, vehicle_id=vehicle_id)
        )
        if session_id and (session is None or session.state not in ("arming", "active")):
            raise SmartChargeError("sessionNotFound", "Không tìm thấy phiên sạc", 404)
        binding = self.binding(
            uid,
            session.vehicle_id if session else vehicle_id,
        )
        if not binding:
            raise SmartChargeError("notConfigured", "Shelly chưa được kết nối", 404)
        if session and expected_version is not None and session.version != expected_version:
            raise SmartChargeError("versionConflict", "Phiên sạc đã thay đổi; hãy đồng bộ lại", 409)
        allowed_reasons = {"need_vehicle", "enough_charge", "safety_concern", "other", "none"}
        if user_stop_reason not in allowed_reasons:
            raise SmartChargeError("invalidStopReason", "Lý do dừng sạc không hợp lệ")
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
            self._finalize_session(
                uid, session, state="cancelled", stop_reason="manual",
                status=verified, user_stop_reason=user_stop_reason,
            )
            self.repository.append_audit(uid, "relay_off_verified", session_id=session.session_id, reason="manual")
        return session

    def personal_profile(self, uid: str, vehicle_id: str) -> PersonalChargingProfile:
        vehicle = self._owned_vehicle(uid, vehicle_id)
        profile = self.repository.get_personal_profile(uid, vehicle_id)
        return profile or PersonalChargingProfile(
            owner_uid=uid,
            vehicle_id=vehicle_id,
            nominal_capacity_wh=_optional_float(vehicle.get("nominalCapacityWh")),
            state_of_health=_optional_float(vehicle.get("stateOfHealth")),
        )

    def update_personal_consent(self, uid: str, vehicle_id: str, enabled: bool) -> PersonalChargingProfile:
        if not vehicle_id.strip():
            raise SmartChargeError("invalidVehicle", "Thiếu vehicleId")
        self._owned_vehicle(uid, vehicle_id)
        profile = self.personal_profile(uid, vehicle_id)
        profile.consent_enabled = bool(enabled)
        profile.updated_at = self.clock()
        if not enabled:
            profile.active = False
        self.repository.save_personal_profile(profile)
        self.repository.append_audit(uid, "personal_ai_consent_changed", vehicle_id=vehicle_id, enabled=enabled)
        return profile

    def delete_personal_profile(self, uid: str, vehicle_id: str) -> None:
        self._owned_vehicle(uid, vehicle_id)
        self.repository.delete_personal_profile(uid, vehicle_id)
        self.repository.append_audit(uid, "personal_ai_deleted", vehicle_id=vehicle_id)

    def privacy_erase_session(self, uid: str, session_id: str, confirmation: str) -> None:
        """Irreversible erase guarded by an explicit session-id confirmation."""
        if not session_id or confirmation.strip() != session_id:
            raise SmartChargeError(
                "eraseConfirmationRequired",
                "Nhập đúng mã phiên để xác nhận xóa vĩnh viễn.",
                400,
            )
        session = self.repository.get_session(uid, session_id)
        # Restored/legacy terminal summaries may only exist in ChargeLogs.
        # The repository performs the authoritative owner + terminal checks
        # against that document, so do not reject those records here.
        if session is not None and session.state in ("arming", "active"):
            raise SmartChargeError(
                "activeSessionProtected",
                "Không thể xóa phiên đang sạc; hãy tắt và xác minh OFF trước.",
                409,
            )
        if not self.repository.erase_session(uid, session_id):
            raise SmartChargeError(
                "sessionNotFound",
                "Không tìm thấy phiên sạc thuộc tài khoản này hoặc phiên vẫn đang hoạt động.",
                404,
            )
        self.repository.append_audit(uid, "smart_charge_privacy_erased", session_id=session_id)

    def hide_session(self, uid: str, session_id: str):
        session = self.repository.get_session(uid, session_id)
        if session is None:
            raise SmartChargeError("sessionNotFound", "Không tìm thấy phiên sạc", 404)
        if session.state in ("arming", "active"):
            raise SmartChargeError(
                "activeSessionProtected",
                "Không thể ẩn phiên đang sạc; hãy tắt và xác minh OFF trước.",
                409,
            )
        hidden = self.repository.hide_session(uid, session_id)
        if hidden is None:
            raise SmartChargeError("hideFailed", "Không thể ẩn phiên sạc", 503)
        self.repository.append_audit(uid, "smart_charge_history_hidden", session_id=session_id)
        return hidden

    def confirm_actual_soc(self, uid: str, session_id: str, actual_soc: float) -> ChargingSession:
        if not 0 <= actual_soc <= 100:
            raise SmartChargeError("invalidSoc", "SOC thực tế phải từ 0–100%")
        session = self.repository.get_session_or_charge_log(uid, session_id)
        if session is None:
            raise SmartChargeError("sessionNotFound", "Không tìm thấy phiên sạc", 404)
        session.actual_end_soc = float(actual_soc)
        gain = session.actual_end_soc - session.start_soc
        if gain > 0 and session.energy_used_wh > 0:
            session.wh_per_soc_percent = round(session.energy_used_wh / gain, 2)
        decision = evaluate_training(session)
        session.training_eligible = decision.eligible
        session.training_state = "pending" if decision.eligible else "skipped"
        session.training_reason = decision.reason
        session.updated_at = self.clock()
        session.version += 1
        self.repository.save_session(uid, session)
        self.repository.upsert_charge_log(uid, session)
        self._update_personal_calibration(uid, session, decision)
        try:
            from ai_server.dataset_manager import upsert_session_record
            session_dict = session.to_dict() if hasattr(session, 'to_dict') else dict(session)
            session_dict['vehicleId'] = session.vehicle_id
            session_dict['userId'] = uid
            upsert_session_record(session_dict, actual_soc=actual_soc)
        except Exception as exc:
            import logging
            logging.getLogger('SmartChargeService').warning('Could not record into dataset file: %s', exc)
        return session


    def ingest_personal_session(self, uid: str, session_id: str) -> dict:
        session = self.repository.get_session_or_charge_log(uid, session_id)
        if session is None:
            raise SmartChargeError("sessionNotFound", "Không tìm thấy phiên sạc", 404)
        self._owned_vehicle(uid, session.vehicle_id)
        decision = evaluate_training(session)
        session.training_eligible = decision.eligible
        session.training_state = "pending" if decision.eligible else "skipped"
        session.training_reason = decision.reason
        if decision.eligible or decision.power_eligible:
            self._update_personal_calibration(uid, session, decision)
        else:
            self.repository.save_session(uid, session)
            self.repository.upsert_charge_log(uid, session)
            self._emit_push(uid, session)
        profile = self.repository.get_personal_profile(uid, session.vehicle_id)
        return {
            "sessionId": session_id,
            "state": session.training_state,
            "reason": session.training_reason,
            "profileVersion": profile.profile_version if profile else None,
        }

    def record_telemetry(self, uid: str, session_id: str, payload: dict) -> dict:
        # Resolve the requested session explicitly. Using the account-wide
        # first active session drops telemetry when two distinct Shellys are
        # charging different vehicles concurrently.
        session = self.repository.get_session(uid, session_id)
        if session is None or session.state not in ("arming", "active"):
            raise SmartChargeError("sessionNotFound", "Không tìm thấy phiên sạc đang hoạt động", 404)
        now = self.clock()
        last = self._last_telemetry_at.get(session_id)
        # Ingest every meter sample in memory so SOC keeps advancing between
        # durable checkpoints. Only retain one compact chart sample per minute.
        sample_due = (
            last is None
            or (now - last).total_seconds() >= 60
            or payload.get("relay") is False
        )
        self._ingest_energy(session, float(payload.get("energyWh") or 0))
        relay_value = payload.get("relay")
        relay_on = True if relay_value is None else bool(relay_value)
        point = {
            "sessionId": session_id,
            "timestamp": now.isoformat(),
            "elapsedSeconds": max(0, int((now - session.created_at).total_seconds())),
            "powerAverageW": float(payload.get("powerW") or 0),
            "powerMinimumW": float(payload.get("powerW") or 0),
            "powerMaximumW": float(payload.get("powerW") or 0),
            "voltageV": float(payload.get("voltageV") or 0),
            "currentA": float(payload.get("currentA") or 0),
            "temperatureC": payload.get("temperatureC"),
            "shellyTemperatureC": payload.get("shellyTemperatureC", payload.get("temperatureC")),
            "batteryTemperatureC": payload.get("batteryTemperatureC"),
            "energyWh": float(payload.get("energyWh") or 0),
            "estimatedSoc": session.estimated_soc,
            "socSource": session.soc_estimate_source or "unavailable",
            "targetSoc": session.target_soc,
            "relay": relay_on,
            "timerRemainingSeconds": int(payload.get("timerRemainingSeconds") or 0),
            "transport": str(payload.get("transport") or session.transport),
            "quality": "good",
            "expireAt": now + timedelta(days=365),
        }
        # Compact samples live on the runtime session and are checkpointed
        # once per minute; counting them avoids a Firestore read/write pair on
        # every status sample.
        count = len(session.telemetry_samples)
        expected = max(1, math.ceil(max(1, point["elapsedSeconds"]) / 30))
        session.telemetry_coverage = min(1.0, count / expected)
        session.shelly_temperature_c = _optional_float(point.get("shellyTemperatureC"))
        session.battery_temperature_c = _optional_float(point.get("batteryTemperatureC"))
        session.average_power_w = _running_average(session.average_power_w, point["powerAverageW"], count)
        session.peak_power_w = max(session.peak_power_w or 0, point["powerMaximumW"])
        session.average_voltage_v = _running_average(session.average_voltage_v, point["voltageV"], count)
        session.average_current_a = _running_average(session.average_current_a, point["currentA"], count)
        if sample_due:
            sample = {
                "t": int(now.timestamp()),
                "elapsed_s": point["elapsedSeconds"],
                "v": point["voltageV"],
                "a": point["currentA"],
                "p": point["powerAverageW"],
                "e_wh": point["energyWh"],
                "temp_shelly": point.get("shellyTemperatureC"),
                "temp_bat": point.get("batteryTemperatureC"),
                "est_soc": point.get("estimatedSoc"),
                "relay": point["relay"],
                "transport": point["transport"],
            }
            session.telemetry_samples = [*session.telemetry_samples[-599:], sample]
            self._last_telemetry_at[session_id] = now
        session.updated_at = now
        if not relay_on:
            near_planned = abs((now - session.effective_stop_at).total_seconds()) <= 120
            self._finalize_session(
                uid, session,
                state="completed" if near_planned else "interrupted",
                stop_reason="planned_timer" if near_planned else "relay_off",
                meter_energy_wh=float(payload.get("energyWh", 0)),
            )
        else:
            self._checkpoint_session(uid, session)
        return {"recorded": sample_due, "coverage": session.telemetry_coverage}

    def _checkpoint_session(self, uid: str, session: ChargingSession, *, force: bool = False) -> bool:
        """Persist one compact runtime snapshot at most once per minute."""
        now = self.clock()
        last = self._last_checkpoint_at.get(session.session_id)
        terminal = session.state not in ("arming", "active")
        if not force and not terminal and last and (now - last).total_seconds() < 60:
            return False
        self.repository.save_session(uid, session)
        self._last_checkpoint_at[session.session_id] = now
        return True


    def _update_personal_calibration(self, uid: str, session: ChargingSession, decision) -> None:
        profile = self.repository.get_personal_profile(uid, session.vehicle_id)
        if profile is None or not profile.consent_enabled or not (
            decision.eligible or decision.power_eligible
        ):
            return
        if self.repository.training_sample_processed(
            uid, session.session_id, session.vehicle_id
        ):
            return
        # Build the next calibration on a copy.  The currently promoted
        # profile remains untouched until the candidate has passed validation.
        calibrated = update_profile(deepcopy(profile), session, decision, self.clock())
        sample = {
            "state": "candidate",
            "eligibleForTargetTraining": decision.eligible,
            "interrupted": session.state != "completed",
            "durationSeconds": max(0, int(((session.stopped_at or session.updated_at) - session.created_at).total_seconds())),
            "predictedMinutes": session.predicted_minutes,
            "socGain": decision.actual_soc_gain,
            "energyWh": session.energy_used_wh,
            "telemetryCoverage": session.telemetry_coverage,
            "qualityScore": decision.quality_score,
            "coveredSocBands": list(decision.covered_bands),
            "targetReached": session.actual_end_soc is not None and session.actual_end_soc >= session.target_soc,
        }
        if decision.eligible:
            rows = self.repository.training_samples(uid, session.vehicle_id)
            # The current sample is not persisted yet, so include it in the
            # held-out validation set explicitly and keep provenance immutable.
            rows = [*rows, {**sample, "sessionId": session.session_id}]
            _candidate_profile, candidate = self.model_registry.build_candidate(
                calibrated,
                uid,
                session.vehicle_id,
                rows,
                session.model_version,
                source_session_id=session.session_id,
            )
            promotion = self.model_registry.promote_or_reject(
                _candidate_profile, candidate
            )
            if promotion.status == "promoted":
                profile = calibrated
                profile.profile_version = promotion.candidate.profile_version
                profile.adapter_version = f"personal-v{profile.profile_version}"
                profile.active = profile.valid_sessions >= 3
                profile.base_model_version = session.model_version
                self.repository.save_personal_profile(profile)
                sample["state"] = "trained"
                sample["trainingDecision"] = "promoted"
                session.training_state = "trained"
                session.training_reason = (
                    "partial_curve" if session.state != "completed" else "completed_curve"
                )
            else:
                sample["state"] = "rejected"
                sample["trainingDecision"] = promotion.reason
                session.training_state = "rejected"
                session.training_reason = promotion.reason
        else:
            # Power/energy-only calibration is allowed without an end-SOC
            # target label, but it must never promote an ETA model.
            self.repository.save_personal_profile(calibrated)
            sample["state"] = "power_only"
            session.training_state = "power_only"
            session.training_reason = "power_and_energy_only"
        self.repository.save_training_sample(uid, session, sample)
        self.repository.save_session(uid, session)
        self.repository.upsert_charge_log(uid, session)
        if decision.eligible and session.training_state == "trained" and profile.valid_sessions >= 5:
            self.repository.enqueue_personal_training(uid, session.vehicle_id, session.session_id)

    def _owned_vehicle(self, uid: str, vehicle_id: str) -> dict:
        vehicle = self.repository.vehicle_for_owner(uid, vehicle_id)
        if vehicle is None:
            raise SmartChargeError("vehicleForbidden", "Xe không thuộc tài khoản này", 403)
        return vehicle

    def _prediction_payload(self, payload: dict, vehicle: dict) -> dict:
        result = dict(payload)
        # Identity and capacity provenance come from the owned vehicle record,
        # never from ownerUid supplied by a client.
        result.pop("ownerUid", None)
        for key in ("nominalCapacityWh", "stateOfHealth", "vinfastModelId"):
            if vehicle.get(key) is not None:
                result[key] = vehicle[key]
        # Onboarding stores placeholder SoH (100%) so the vehicle can be
        # created immediately.  Do not let that unverified value influence
        # physics ETA or personal calibration; legacy records without the
        # provenance flag retain their historical behavior.
        if vehicle.get("hasSohData") is False:
            result.pop("stateOfHealth", None)
        if result.get("estimatedCapacityWh") in (None, 0) and vehicle.get("nominalCapacityWh"):
            result["estimatedCapacityWh"] = vehicle["nominalCapacityWh"]
        return result

    def _ingest_energy(self, session: ChargingSession, meter_energy_wh: float) -> None:
        """Accumulate Shelly's lifetime meter without losing energy on reset."""
        reading = max(0.0, float(meter_energy_wh or 0))
        if session.baseline_energy_wh is None:
            session.baseline_energy_wh = reading
            session.last_meter_energy_wh = reading
            return
        last = (session.last_meter_energy_wh
                if session.last_meter_energy_wh is not None
                else session.baseline_energy_wh)
        if reading >= last:
            session.energy_used_wh = max(0.0, session.energy_used_wh) + reading - last
            session.last_meter_energy_wh = reading
        else:
            threshold = max(25.0, abs(last) * .20)
            if reading < last - threshold:
                session.last_meter_energy_wh = reading
                session.baseline_energy_wh = reading
                session.energy_quality = "meter_reset"
        capacity = session.effective_capacity_wh or session.nominal_capacity_wh
        if capacity is None or capacity <= 0:
            session.estimated_soc = None
            session.estimated_stored_energy_wh = None
            session.soc_estimate_source = "unavailable"
            session.soc_estimate_quality = "unavailable"
            session.soc_estimation_version = 2
            return
        efficiency = min(.98, max(.65, session.charging_efficiency or .90))
        stored = session.energy_used_wh * efficiency
        session.estimated_stored_energy_wh = stored
        session.estimated_soc = min(100.0, max(session.start_soc,
            session.start_soc + stored / capacity * 100))
        session.soc_estimate_source = "shelly_energy"
        session.soc_estimate_quality = "live" if session.energy_quality == "good" else "partial"
        session.soc_estimation_version = 2

    def _apply_safety(self, uid: str, binding: DeviceBinding, status) -> None:
        if not status.relay:
            self._unsafe_samples.pop((uid, binding.device_id), None)
            return
        p = self.safety_policy
        violations: list[tuple[str, float, str]] = []
        if status.current_a >= p.cutoff_current_a:
            violations.append(("over_current", status.current_a, "Dòng điện vượt ngưỡng an toàn"))
        if status.power_w >= p.cutoff_power_w:
            violations.append(("over_power", status.power_w, "Công suất vượt ngưỡng an toàn"))
        if status.temperature_c is not None and status.temperature_c >= p.cutoff_temperature_c:
            violations.append(("over_temperature", status.temperature_c, "Nhiệt độ vượt ngưỡng an toàn"))
        if status.voltage_v and not p.cutoff_voltage_min_v <= status.voltage_v <= p.cutoff_voltage_max_v:
            violations.append(("unsafe_voltage", status.voltage_v, "Điện áp ngoài ngưỡng an toàn"))
        safety_key = (uid, binding.device_id)
        count = self._unsafe_samples.get(safety_key, 0) + 1 if violations else 0
        self._unsafe_samples[safety_key] = count
        # Attach safety events to the session using this physical relay. An
        # account may have multiple vehicles charging concurrently.
        session = self.repository.current_session(uid, device_id=binding.device_id)
        if not session or not violations:
            return
        kind, value, message = violations[0]
        if not session.safety_events or session.safety_events[-1].kind != kind:
            session.safety_events.append(SmartChargeSafetyEvent(kind, "critical", message, value))
            self.repository.save_session(uid, session)
        if count >= p.consecutive_samples:
            self.provider.turn_off(binding)
            readback = self.provider.get_status(binding)
            if readback.relay:
                raise SmartChargeError("relayUnverified", "Không xác minh được OFF an toàn", 503)
            self._finalize_session(
                uid, session, state="interrupted", stop_reason="safety_cutoff",
                status=readback,
            )

    def manual_on(
        self,
        uid: str,
        duration_seconds: int,
        idempotency_key: str,
        vehicle_id: str = "manual",
        current_soc: float = 0,
    ) -> ChargingSession:
        """Manual ON is permitted only with a device-side safety timer."""
        binding = self.binding(uid, vehicle_id if vehicle_id != "manual" else None)
        if not binding:
            raise SmartChargeError("notConfigured", "Shelly chưa được kết nối", 404)
        vehicle = self._owned_vehicle(uid, vehicle_id) if vehicle_id != "manual" else {}
        duration_seconds = int(duration_seconds)
        if duration_seconds < 5 or duration_seconds > self.max_minutes * 60:
            raise SmartChargeError("unsafeDuration", "Safety timer phải từ 5 giây đến 10 giờ")
        if not idempotency_key or len(idempotency_key) > 160:
            raise SmartChargeError("invalidIdempotencyKey", "Thiếu Idempotency-Key")
        existing = self.repository.get_by_idempotency(uid, idempotency_key)
        if existing:
            return existing
        if self.repository.current_session(uid, device_id=binding.device_id):
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
            last_meter_energy_wh=before.energy_wh,
            charging_efficiency=.90,
            capacity_source="vehicle_catalog" if vehicle else None,
            soc_estimate_source="unavailable",
            soc_estimate_quality="unavailable",
            soc_estimation_version=2,
            owner_uid=uid,
            nominal_capacity_wh=_optional_float(vehicle.get("nominalCapacityWh")),
            state_of_health=_optional_float(vehicle.get("stateOfHealth")),
            safety_policy_version=self.safety_policy.version,
        )
        if not self.repository.claim_device_session(uid, session.device_id, session.session_id):
            raise SmartChargeError("activeSessionConflict", "Shelly đang được dùng bởi một phiên khác", 409)
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

    def current(self, uid: str, vehicle_id: str | None = None) -> ChargingSession | None:
        session = self.repository.current_session(uid, vehicle_id=vehicle_id)
        if not session:
            return None
        binding = self.binding(uid, session.vehicle_id)
        if not binding:
            return session
        try:
            status = self.provider.get_status(binding)
        except ProviderError:
            return session
        return self._reconcile_with_status(uid, status, vehicle_id) or self.repository.current_session(uid, vehicle_id=vehicle_id)

    def recover(self, uid: str, vehicle_id: str | None = None) -> ChargingSession | None:
        """Called on server startup/restart. Reads real relay state from Shelly and synchronizes database."""
        session = self.repository.current_session(uid, vehicle_id=vehicle_id)
        if not session:
            return None
        binding = self.binding(uid, session.vehicle_id)
        if not binding:
            return session
        try:
            status = self.provider.get_status(binding)
        except ProviderError:
            return session
        now = self.clock()
        if not status.relay:
            near_planned = abs((now - session.effective_stop_at).total_seconds()) <= 120
            return self._finalize_session(
                uid, session,
                state="completed" if near_planned else "interrupted",
                stop_reason="planned_timer" if near_planned else "relay_off",
                status=status,
            )
        if status.timer_remaining <= 0 and session.state in ("arming", "active"):
            try:
                self.provider.turn_off(binding)
            except ProviderError:
                pass
        if now >= session.absolute_safety_stop_at:
            try:
                self.provider.turn_off(binding)
            except ProviderError:
                pass
        return session


    def _reconcile_with_status(self, uid: str, status, vehicle_id: str | None = None) -> ChargingSession | None:
        session = self.repository.current_session(uid, vehicle_id=vehicle_id)
        if not session:
            return None
        now = self.clock()
        if status.relay:
            self._ingest_energy(session, status.energy_wh)
            session.updated_at = now
            if status.timer_remaining <= 0:
                binding = self.binding(uid, session.vehicle_id)
                try:
                    if binding:
                        self.provider.turn_off(binding)
                except ProviderError:
                    pass
                session.last_error = "timerNotArmed"
                self._finalize_session(
                    uid, session, state="failed", stop_reason="command_failed",
                    status=status,
                )
            else:
                self._checkpoint_session(uid, session)
            return session
        near_planned = abs((now - session.effective_stop_at).total_seconds()) <= 120
        return self._finalize_session(
            uid, session,
            state="completed" if near_planned else "interrupted",
            stop_reason="planned_timer" if near_planned else "relay_off",
            status=status,
        )

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


def _optional_float(value) -> float | None:
    try:
        parsed = float(value)
        return parsed if math.isfinite(parsed) else None
    except (TypeError, ValueError):
        return None


def _candidate_minutes(candidates: list[EtaCandidate], source: str) -> float | None:
    match = next((item for item in candidates if item.source == source and item.available), None)
    return match.duration_seconds / 60 if match else None


def _running_average(previous: float | None, value: float, count: int) -> float:
    if count <= 1 or previous is None:
        return float(value)
    return previous + (float(value) - previous) / count
