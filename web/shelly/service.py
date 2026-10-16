from __future__ import annotations

import os
import secrets
import threading
import sys
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
    NONTERMINAL_SESSION_STATES,
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


IDLE_STATUS_CACHE_SECONDS = 10
# A failed *read* with these codes says nothing about the relay: the shared
# Cloud slot was busy or rate limited. Marking the session unknown made the
# next reconcile run recovery_off and cut a healthy charge (Task108).
TRANSIENT_READ_CODES = frozenset({"cloudQueueBusy", "cloudRateLimited", "cloudRateLimiterUnavailable"})
# Task 122: OFF was accepted but Cloud status has not shown it yet. The
# session stays "stopping" with the user's reason; reconcile finishes it as a
# manual stop instead of sending a second OFF / recording recovery_off.
OFF_PENDING_READBACK = "offPendingReadback"
OFF_READBACK_GRACE_SECONDS = 25
# An ON command (claim → set → readback) is in flight for at most ~20 s; a
# status poll must not finalize that session from a pre-ON relay reading.
COMMAND_IN_FLIGHT_GRACE_SECONDS = 60
MEMBERSHIP_CACHE_SECONDS = 60
# A relay seen OFF this close to (or after) the planned stop is a normal
# timer completion; earlier than that it was switched off before the plan.
PLANNED_STOP_TOLERANCE_SECONDS = 20


class _StageTimer:
    """Milliseconds per command stage, recorded in the audit (Task 123)."""

    def __init__(self):
        self._start = self._last = time.perf_counter()
        self._marks: dict[str, int] = {}

    def mark(self, name: str) -> None:
        now = time.perf_counter()
        self._marks[name] = int((now - self._last) * 1000)
        self._last = now

    def result(self) -> dict:
        return {**self._marks, "total": int((self._last - self._start) * 1000)}


def _parallel(jobs: dict) -> dict:
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=len(jobs)) as pool:
        return {name: pool.submit(job) for name, job in jobs.items()}
CAPABILITIES_CACHE_SECONDS = 30


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
        self._membership_cache: dict[tuple[str, str], tuple[datetime, bool]] = {}
        self.push_notifier = push_notifier

    def _code_refresh_required(self, uid: str, device_id: str) -> bool:
        """Display hint for /live: cached 60 s (two Firestore reads per poll
        before Task 125); a legacy binding without membership is not an error."""
        key = (uid, device_id)
        now = self.clock()
        cached = self._membership_cache.get(key)
        if cached and (now - cached[0]).total_seconds() < MEMBERSHIP_CACHE_SECONDS:
            return cached[1]
        try:
            value = bool(self.repository.device_membership(uid, device_id).get("codeRefreshRequired"))
        except Exception:
            return cached[1] if cached else False
        self._membership_cache[key] = (now, value)
        return value

    def _emit_state_push(self, uid, session):
        """Background data-only push after a verified ON (Task 123): other
        phones of the account refresh at once instead of at the next poll."""
        notifier = self.push_notifier
        if not notifier:
            return
        kwargs = dict(session_id=session.session_id, vehicle_id=getattr(session, "vehicle_id", None),
                      state=session.state, silent=True)

        def deliver():
            try:
                notifier(uid, **kwargs)
            except TypeError:
                pass  # notifier without silent support (worker/tests)
            except Exception:
                pass  # a hint only; polling still converges

        threading.Thread(target=deliver, name="smart-charge-state-push", daemon=True).start()

    def _emit_push(self, uid, session):
        if self.push_notifier and session.state in {'completed', 'cancelled', 'interrupted', 'failed'}:
            notifier = self.push_notifier
            kwargs = dict(
                session_id=session.session_id,
                vehicle_id=getattr(session, 'vehicle_id', None),
                state=session.state,
                target_percent=getattr(session, 'target_soc', None),
            )

            def deliver():
                try:
                    notifier(uid, **kwargs)
                except Exception:
                    # Notification delivery must never roll back durable charging state.
                    pass

            # Task 123: FCM token reads + send (~1 s) ran before the OFF
            # response. The session is already durable; deliver in background.
            threading.Thread(target=deliver, name="smart-charge-push", daemon=True).start()

    def invalidate_capabilities(self) -> None:
        self.__dict__["_capabilities_cache"] = {}

    def capabilities(self, uid: str, vehicle_id: str | None = None, *, max_age_seconds: float = 0,
                     verify_live: bool = True) -> dict:
        """Display readiness. Polling may reuse a result for ``max_age_seconds``;
        every mutating request clears the cache and ON re-verifies live anyway."""
        cache = self.__dict__.setdefault("_capabilities_cache", {})
        key = (uid, vehicle_id, verify_live)
        if max_age_seconds > 0:
            cached = cache.get(key)
            if cached and time.monotonic() - cached[0] <= max_age_seconds:
                return dict(cached[1])
        value = self._capabilities_uncached(uid, vehicle_id, verify_live=verify_live)
        cache[key] = (time.monotonic(), dict(value))
        return value

    def _capabilities_uncached(self, uid: str, vehicle_id: str | None = None, *,
                               verify_live: bool = True) -> dict:
        binding = self.binding(uid, vehicle_id)
        status = bool(getattr(self.provider, "supports_status", False))
        manual_off = bool(getattr(self.provider, "supports_manual_off", False))
        manual_on = bool(getattr(self.provider, "supports_manual_on", False))
        timer = bool(getattr(self.provider, "supports_device_timer", False))
        power = bool(binding and binding.power_meter_verified)
        safe_boot = bool(binding and binding.safe_boot_verified)
        no_load = bool(binding and binding.no_load_test_verified)
        staging_disabled = os.environ.get("AZURE_STAGING_HARDWARE_DISABLED", "0") == "1"
        blocked_code = "STAGING_HARDWARE_DISABLED" if staging_disabled else None
        cached_ready = getattr(self.repository, "worker_health_ready_cached", None)
        worker_ready = (cached_ready(self.clock()) if cached_ready else
                        self.repository.worker_health_ready(self.clock()))
        if binding and not staging_disabled:
            try:
                shared_session = self.repository.shared_device_session(uid, binding.device_id)
                if shared_session and shared_session.state in NONTERMINAL_SESSION_STATES:
                    blocked_code = (
                        "relayUnverified" if shared_session.state in {"unknown", "stopping", "onUnverified"}
                        else "activeSessionConflict"
                    )
            except (PermissionError, RuntimeError):
                blocked_code = "deviceCoordinationUnavailable"
        if blocked_code is None and not worker_ready:
            blocked_code = "workerUnavailable"
        if blocked_code is None and binding and power and safe_boot and no_load and verify_live:
            verifier = getattr(self.provider, "verify_control_readiness", None)
            if verifier is None:
                blocked_code = "safetyVerificationRequired"
            else:
                try:
                    verifier(binding)
                except ProviderError as error:
                    blocked_code = error.code
        can_start = not staging_disabled and blocked_code is None
        if blocked_code and binding:
            # Sanitized diagnostics (Task108): code only, no ids or credentials.
            print(f"[smart-charge] capabilities blocked code={blocked_code} "
                  f"power={power} safeBoot={safe_boot} noLoad={no_load} worker={worker_ready}", flush=True)
        return {
            "canReadStatus": status,
            "canManualOn": manual_on and timer and can_start,
            "canManualOff": manual_off,
            "supportsDeviceTimer": timer,
            "canReadPower": power,
            "canConfigureSafeBoot": False,
            "cloudAvailable": binding is not None and status,
            "lanAvailable": False,
            "safeBootVerified": safe_boot,
            "noLoadTestVerified": no_load,
            "readyForControl": bool(
                can_start and binding and status and manual_off and manual_on and timer and power and safe_boot and no_load
            ),
            "controlBlockedCode": blocked_code,
            "workerReady": worker_ready,
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

    def _require_ready_to_energize(self, binding: DeviceBinding, status, *,
                                   live_context_verified: bool = False,
                                   worker_checked: bool = False) -> None:
        """Server-side gate: a client readiness flag cannot authorize ON.

        [live_context_verified] means [status] came from the provider's full
        live safety context (prepare_on), so the separate readiness read is
        skipped; the ON command re-checks that context inside its slot.
        """
        if not worker_checked:
            self.require_worker_ready()
        if binding.model != "S3PL-00112EU" or binding.generation != 3:
            raise SmartChargeError("unsupportedDevice", "Bộ sạc chưa được hỗ trợ", 409)
        if not (binding.power_meter_verified and binding.safe_boot_verified and binding.no_load_test_verified):
            raise SmartChargeError("safetyVerificationRequired", "Cần kiểm tra an toàn bộ sạc trước khi bật", 409)
        if not self._status_matches_device(status, binding.device_id):
            raise SmartChargeError("deviceUnverified", "Chưa xác minh được đúng bộ sạc", 409)
        if status.relay is not False:
            raise SmartChargeError("relayAlreadyOn", "Bộ sạc đang bật; hãy kiểm tra phiên hiện tại", 409)
        if not 190 <= status.voltage_v <= 255:
            raise SmartChargeError("unsafeVoltage", "Điện áp bộ sạc ngoài ngưỡng an toàn", 409)
        if live_context_verified:
            return
        verifier = getattr(self.provider, "verify_control_readiness", None)
        if verifier is None:
            raise SmartChargeError("safetyVerificationRequired", "Cần kiểm tra lại an toàn bộ sạc", 409)
        try:
            verifier(binding)
        except ProviderError as error:
            raise self._provider_error(error) from error

    def _prepare_energize(self, binding: DeviceBinding):
        """One fresh device read for the readiness gate and the ON command.

        Providers with `prepare_on` (vault Cloud) return a live safety
        context whose status is reused; others keep the legacy two reads.
        Returns (status, context-or-None).
        """
        preparer = getattr(self.provider, "prepare_on", None)
        try:
            if preparer is None:
                status = self.provider.get_status(binding)
                self._require_ready_to_energize(binding, status)
                return status, None
            # One worker check (it was read twice) alongside the device read.
            jobs = _parallel({"worker": self.require_worker_ready,
                              "context": lambda: preparer(binding)})
            jobs["worker"].result()
            context = jobs["context"].result()
        except ProviderError as exc:
            raise self._provider_error(exc) from exc
        status = context["status"]
        self._require_ready_to_energize(binding, status, live_context_verified=True,
                                        worker_checked=True)
        return status, context

    def _send_on(self, binding: DeviceBinding, duration_seconds: int, context) -> None:
        sender = getattr(self.provider, "turn_on_with_context", None)
        if context is not None and sender is not None:
            sender(binding, duration_seconds, context)
        else:
            self.provider.turn_on_with_timer(binding, duration_seconds)

    def _read_until(self, binding: DeviceBinding, accept, attempts: int):
        """Readback that tolerates Cloud lag and transient read errors.

        Returns the first status satisfying [accept] or None. Commands are
        never resent here; only status is read again.
        """
        for attempt in range(attempts):
            last = attempt == attempts - 1
            try:
                current = self.provider.get_status(binding)
            except ProviderError as error:
                if error.code in TRANSIENT_READ_CODES and not last:
                    self.sleep(1)
                    continue
                raise
            if accept(current):
                return current
            if not last:
                self.sleep(1)
        return None

    def require_worker_ready(self) -> None:
        if os.environ.get("AZURE_STAGING_HARDWARE_DISABLED", "0") == "1":
            raise SmartChargeError("STAGING_HARDWARE_DISABLED", "Điều khiển đang bị khóa trong môi trường kiểm thử", 503)
        if not self.repository.worker_health_ready(self.clock()):
            raise SmartChargeError("workerUnavailable", "Giám sát sạc chưa sẵn sàng. Hãy thử lại sau.", 503, True)

    def _status_matches_device(self, status, device_id: str) -> bool:
        observed = getattr(status, "device_id", None)
        return bool(
            isinstance(observed, str) and observed.strip() and device_id
            and self.repository._device_owner_doc_id(observed) == self.repository._device_owner_doc_id(device_id)
            and getattr(status, "online", None) is True
            and type(getattr(status, "relay", None)) is bool
        )

    def session_binding(self, uid: str, session: ChargingSession) -> DeviceBinding | None:
        """Resolve the immutable session device, never a vehicle's new binding."""
        if not session.device_id or session.owner_uid not in (None, uid):
            return None
        key = self.repository._device_owner_doc_id(session.device_id)
        matches = [b for b in self.repository.list_bindings(uid)
                   if b.revoked_at is None and self.repository._device_owner_doc_id(b.device_id) == key]
        exact = [b for b in matches if b.vehicle_id == session.vehicle_id]
        candidates = exact or matches
        return candidates[0] if len(candidates) == 1 else None

    def _defer_terminal_writes(self) -> bool:
        """Only with the real datastore; in-memory tests stay synchronous."""
        return bool(getattr(self.repository, "db", None))

    def _anchor_stop_to_device_timer(self, session: ChargingSession, status, *, manual: bool = False) -> None:
        """Planned stop = when the verified Shelly timer actually ends.

        The session is created before the Cloud ON round trips, so a stop time
        taken from creation fired a backup OFF (and an "interrupted" label)
        seconds before the hardware timer would. Only ever moves later, never
        past the absolute safety deadline.
        """
        remaining = int(status.timer_remaining or 0)
        if remaining <= 0:
            return
        device_stop = min(self.clock() + timedelta(seconds=remaining), session.absolute_safety_stop_at)
        if device_stop > session.effective_stop_at:
            session.effective_stop_at = device_stop
            if manual:
                session.ai_stop_at = device_stop

    def _relay_off_outcome(self, session: ChargingSession, now) -> tuple[str, str]:
        """Timer completion vs. an OFF that came before the plan."""
        if now >= session.effective_stop_at - timedelta(seconds=PLANNED_STOP_TOLERANCE_SECONDS):
            return "completed", "planned_timer"
        return "interrupted", "relay_off"

    def mark_session_unknown(self, uid: str, session: ChargingSession, code: str) -> ChargingSession:
        if session.state not in NONTERMINAL_SESSION_STATES:
            return session
        session.state = "unknown"
        session.relay_verified = False
        session.last_error = code
        session.updated_at = self.clock()
        session.version += 1
        self.repository.save_session(uid, session)
        return session

    def _backup_stop_session(self, uid: str, session: ChargingSession, *,
                             state: str, stop_reason: str) -> ChargingSession:
        binding = self.session_binding(uid, session)
        if binding is None:
            return self.mark_session_unknown(uid, session, "bindingChanged")
        session.state = "stopping"
        session.relay_verified = False
        session.updated_at = self.clock()
        session.version += 1
        self.repository.save_session(uid, session)
        try:
            lease_guard = getattr(self, "_worker_lease_guard", None)
            if lease_guard is not None:
                lease_guard()
            self.provider.turn_off(binding)
            readback = self.provider.get_status(binding)
        except ProviderError as error:
            return self.mark_session_unknown(uid, session, error.code)
        return self._finalize_session(uid, session, state=state,
                                      stop_reason=stop_reason, status=readback)

    def release_control(self, uid: str, device_id: str, operation_id: str) -> None:
        bindings = [b for b in self.repository.list_bindings(uid)
                    if b.revoked_at is None and self.repository._device_owner_doc_id(b.device_id) == self.repository._device_owner_doc_id(device_id)]
        if len(bindings) != 1:
            raise SmartChargeError("deviceNotFound", "Chưa xác minh được đúng liên kết Shelly", 404)
        try:
            status = self.provider.get_status(bindings[0])
        except ProviderError as error:
            raise self._provider_error(error) from error
        if not self._status_matches_device(status, device_id) or status.relay is not False:
            raise SmartChargeError("offReadbackRequired", "Chưa đọc lại được Shelly đã tắt. Quyền điều khiển vẫn được giữ.", 503, True)
        try:
            released = self.repository.release_lan_operation_after_off(uid, device_id, operation_id)
        except Exception as error:
            raise SmartChargeError("controlReleaseUnavailable", "Chưa xác minh được quyền điều khiển. Hãy thử lại.", 503, True) from error
        if not released:
            raise SmartChargeError("activeSessionConflict", "Quyền điều khiển vẫn được giữ cho thao tác đang hoạt động.", 409)
        self.repository.append_audit(uid, "shelly_control_released", operation_id=operation_id)

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
        status, on_context = self._prepare_energize(binding)
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
            self._send_on(binding, duration, on_context)
            verified = self._read_until(
                binding,
                lambda current: (self._status_matches_device(current, binding.device_id)
                                 and current.relay is True and current.timer_remaining > 0),
                10,
            )
            if verified is not None:
                if verified.temperature_c is not None and verified.temperature_c >= self.safety_policy.cutoff_temperature_c:
                    raise ProviderError("overtemperature", f"Shelly quá nhiệt ({verified.temperature_c}°C >= {self.safety_policy.cutoff_temperature_c}°C)")
                if verified.power_w > self.safety_policy.cutoff_power_w:
                    raise ProviderError("overpower", f"Công suất vượt ngưỡng ({verified.power_w}W > {self.safety_policy.cutoff_power_w}W)")

            if not verified:
                raise ProviderError("timerNotArmed", "Không xác minh được timer trên Shelly")
            self._anchor_stop_to_device_timer(session, verified)
            session.state = "active"
            session.relay_verified = True
            session.timer_verified = True
            session.updated_at = self.clock()
            session.version += 1
            self._commit_started_session(uid, session, binding)
            # ChargeLogs are materialized at terminal state; the runtime
            # session is the single active source during charging.
            self.repository.append_audit(uid, "session_started", session_id=session.session_id, device_id=binding.device_id)
            self._emit_state_push(uid, session)
            return session
        except ProviderError as exc:
            off_verified = False
            try:
                self.provider.turn_off(binding)
                off_status = self.provider.get_status(binding)
                off_verified = self._status_matches_device(off_status, binding.device_id) and off_status.relay is False
            except ProviderError:
                pass
            session.state = "failed" if off_verified else "unknown"
            session.relay_verified = off_verified
            session.stop_reason = "command_failed"
            session.last_error = exc.code
            session.stopped_at = self.clock() if off_verified else None
            session.updated_at = self.clock()
            session.version += 1
            self.repository.save_session(uid, session)
            if off_verified:
                self.repository.upsert_charge_log(uid, session)
            self.repository.append_audit(uid, "session_start_failed", session_id=session.session_id, error=exc.code)
            if off_verified:
                self._emit_push(uid, session)
            raise self._provider_error(exc) from exc

    def _read_status(self, binding):
        """Polling read: may reuse a seconds-old idle (relay OFF) status."""
        try:
            return self.provider.get_status(binding, max_age_seconds=IDLE_STATUS_CACHE_SECONDS)
        except TypeError:
            return self.provider.get_status(binding)  # providers without a cache

    def status(self, uid: str, vehicle_id: str | None = None):
        binding = self.binding(uid, vehicle_id)
        if not binding:
            raise SmartChargeError("notConfigured", "Shelly chưa được kết nối", 404)
        try:
            status = self._read_status(binding)
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
            raise SmartChargeError("notConfigured", "Shelly chưa được kết nối", 404)
        try:
            status = self._read_status(binding)
            # One active-session query per poll, shared by the safety check
            # and reconcile (two queries while charging before Task 125).
            sessions = self.repository.active_sessions(uid)
            self._apply_safety(uid, binding, status, sessions)
            mine = [s for s in sessions if not vehicle_id or s.vehicle_id == vehicle_id]
            session = (self._reconcile_with_status(uid, status, vehicle_id, session=mine[0])
                       if mine else None)
        except ProviderError as exc:
            raise self._provider_error(exc) from exc
        try:
            # Light readiness only: no extra live Cloud check inside a poll that
            # must answer within the app timeout. ON re-verifies live anyway.
            capabilities = self.capabilities(uid, vehicle_id, max_age_seconds=CAPABILITIES_CACHE_SECONDS,
                                             verify_live=False)
        except Exception:
            capabilities = None  # live status stays usable; app keeps its last capabilities
        return {
            "status": {**(status.to_dict() if hasattr(status, "to_dict") else status),
                       "codeRefreshRequired": self._code_refresh_required(uid, binding.device_id)},
            "session": session.to_dict() if session else None,
            "active": bool(session and session.state in NONTERMINAL_SESSION_STATES),
            "capabilities": capabilities,
            "binding": {"deviceId": binding.device_id, "connectionMode": binding.connection_mode,
                        "provider": binding.provider, "displayName": binding.display_name},
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
        if session.state not in NONTERMINAL_SESSION_STATES:
            return session
        # Telemetry and an old relay value are not proof of OFF. Never make a
        # session terminal (which releases the device lease) without a fresh
        # readback of the immutable device attached to this session.
        if status is None:
            binding = self.session_binding(uid, session)
            if binding is None:
                return self.mark_session_unknown(uid, session, "bindingChanged")
            try:
                status = self.provider.get_status(binding)
            except ProviderError:
                return self.mark_session_unknown(uid, session, "relayUnverified")
        if not self._status_matches_device(status, session.device_id) or status.relay is not False:
            return self.mark_session_unknown(uid, session, "relayUnverified")
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
        try:
            self.repository.save_session(uid, session)
        except RuntimeError as error:
            # Another path (deferred stop write, live poll, worker) closed it
            # first with the same verified OFF: report the stored result.
            if str(error) != "sessionAlreadyTerminal":
                raise
            stored = self.repository.get_session(uid, session.session_id)
            if stored is None or stored.state in NONTERMINAL_SESSION_STATES:
                raise
            return stored
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
        expected_device_id: str | None = None,
    ) -> ChargingSession | None:
        # An explicit session id must resolve that exact session. Using the
        # account-wide first active session breaks when two physical Shellys
        # charge different vehicles concurrently.
        session = (
            self.repository.get_session(uid, session_id)
            if session_id
            else self.repository.current_session(uid, vehicle_id=vehicle_id)
        )
        if session_id and (session is None or session.state not in NONTERMINAL_SESSION_STATES):
            raise SmartChargeError("sessionNotFound", "Không tìm thấy phiên sạc", 404)
        binding = (self.session_binding(uid, session)
                   if session else self.binding(uid, vehicle_id))
        if not binding:
            raise SmartChargeError("notConfigured", "Shelly chưa được kết nối", 404)
        if expected_device_id is not None and (not isinstance(expected_device_id, str) or
                not expected_device_id.strip() or
                self.repository._device_owner_doc_id(expected_device_id) != self.repository._device_owner_doc_id(binding.device_id)):
            raise SmartChargeError("bindingChanged", "Liên kết đã thay đổi; hãy xác nhận yêu cầu mới", 409)
        if session and binding.device_id != session.device_id:
            raise SmartChargeError("bindingChanged", "Liên kết bộ sạc đã thay đổi; không thể điều khiển sai thiết bị", 409)
        if session and expected_version is not None and session.version != expected_version:
            raise SmartChargeError("versionConflict", "Phiên sạc đã thay đổi; hãy đồng bộ lại", 409)
        allowed_reasons = {"need_vehicle", "enough_charge", "safety_concern", "other", "none"}
        if user_stop_reason not in allowed_reasons:
            raise SmartChargeError("invalidStopReason", "Lý do dừng sạc không hợp lệ")
        timer = _StageTimer()
        if session:
            session.state = "stopping"
            session.relay_verified = False
            session.updated_at = self.clock()
            session.version += 1
            self.repository.save_session(uid, session)
        timer.mark("mark_stopping")
        try:
            self.provider.turn_off(binding)
            timer.mark("off")
            observed = []

            def off_seen(current):
                observed.append(current)
                return self._status_matches_device(current, binding.device_id) and current.relay is False

            try:
                verified = self._read_until(binding, off_seen, 5)
            except ProviderError:
                verified = None
            # Only plain Cloud lag (the right online device still reporting
            # ON) becomes a pending stop. Offline, wrong-device or unreadable
            # replies keep the strict path below.
            lagging = bool(observed) and self._status_matches_device(observed[-1], binding.device_id)                 and observed[-1].relay is True
            if not verified and session and lagging:
                # OFF was accepted; never send it again from here. Reconcile
                # (live poll / worker) completes the manual stop on readback.
                session.state = "stopping"
                session.relay_verified = False
                session.last_error = OFF_PENDING_READBACK
                session.user_stop_reason = user_stop_reason
                session.updated_at = self.clock()
                session.version += 1
                self.repository.save_session(uid, session)
                self.repository.append_audit(uid, "relay_off_sent_pending_readback",
                                             session_id=session.session_id, reason="manual")
                return session
            if not verified:
                raise ProviderError("relayUnverified", "Không xác minh được relay OFF")
            timer.mark("readback")
        except ProviderError as exc:
            if session:
                session.state = "unknown"
                session.relay_verified = False
                session.last_error = exc.code
                session.updated_at = self.clock()
                session.version += 1
                self.repository.save_session(uid, session)
            raise self._provider_error(exc) from exc
        if session and self._defer_terminal_writes():
            # Task 123: OFF is verified by our own readback. The durable
            # terminal write (session, ChargeLog, lock release, push; ~2.8 s
            # to nam5) runs after the response. If it fails or the process
            # stops, the session stays "stopping" and the next /live or
            # worker reconcile closes it as cancelled/manual on relay OFF.
            reply = deepcopy(session)
            reply.state, reply.stop_reason = "cancelled", "manual"
            reply.user_stop_reason = user_stop_reason
            reply.relay_verified = True
            reply.stopped_at = reply.updated_at = self.clock()
            timings = timer.result()

            def finish_terminal():
                try:
                    self._finalize_session(
                        uid, session, state="cancelled", stop_reason="manual",
                        status=verified, user_stop_reason=user_stop_reason,
                    )
                except RuntimeError:
                    pass  # already closed by a concurrent reconcile
                except Exception as error:  # reconcile will finish it
                    print(f"[smart-charge] deferred stop write failed ({type(error).__name__})",
                          file=sys.stderr, flush=True)
                try:
                    self.repository.append_audit(uid, "relay_off_verified", session_id=session.session_id,
                                                 reason="manual", timings_ms=timings)
                except Exception:
                    pass

            threading.Thread(target=finish_terminal, name="smart-charge-stop", daemon=True).start()
            return reply
        if session:
            try:
                self._finalize_session(
                    uid, session, state="cancelled", stop_reason="manual",
                    status=verified, user_stop_reason=user_stop_reason,
                )
            except RuntimeError:
                # A live poll or the worker saw the same OFF first and already
                # closed the session (it is "stopping", so as a manual stop).
                # OFF is verified by our own readback: report that session.
                current = self.repository.get_session(uid, session.session_id)
                if current is None or current.state in NONTERMINAL_SESSION_STATES:
                    raise
                session = current
            timer.mark("finalize")
            self.repository.append_audit(uid, "relay_off_verified", session_id=session.session_id, reason="manual",
                                         timings_ms=timer.result())
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
        if session is not None and session.state in NONTERMINAL_SESSION_STATES:
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
        if session.state in NONTERMINAL_SESSION_STATES:
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
        if session is None or session.state not in NONTERMINAL_SESSION_STATES:
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
            state, stop_reason = (("cancelled", "manual") if session.state == "stopping"
                                  else self._relay_off_outcome(session, now))
            self._finalize_session(
                uid, session,
                state=state,
                stop_reason=stop_reason,
                meter_energy_wh=float(payload.get("energyWh", 0)),
            )
        else:
            self._checkpoint_session(uid, session)
        return {"recorded": sample_due, "coverage": session.telemetry_coverage}

    def _checkpoint_session(self, uid: str, session: ChargingSession, *, force: bool = False) -> bool:
        """Persist one compact runtime snapshot at most once per minute."""
        now = self.clock()
        last = self._last_checkpoint_at.get(session.session_id)
        terminal = session.state not in NONTERMINAL_SESSION_STATES
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

    def _apply_safety(self, uid: str, binding: DeviceBinding, status,
                      sessions: list[ChargingSession] | None = None) -> None:
        if not self._status_matches_device(status, binding.device_id):
            return
        if status.relay is False:
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
        if not violations:
            return
        if sessions is None:
            session = self.repository.current_session(uid, device_id=binding.device_id)
        else:
            session = next((s for s in sessions if s.device_id == binding.device_id), None)
        if not session:
            return
        kind, value, message = violations[0]
        if not session.safety_events or session.safety_events[-1].kind != kind:
            session.safety_events.append(SmartChargeSafetyEvent(kind, "critical", message, value))
            self.repository.save_session(uid, session)
        if count >= p.consecutive_samples:
            self._backup_stop_session(uid, session, state="interrupted", stop_reason="safety_cutoff")
            if session.state in NONTERMINAL_SESSION_STATES:
                raise SmartChargeError("relayUnverified", "Không xác minh được OFF an toàn", 503)

    def manual_on(
        self,
        uid: str,
        duration_seconds: int,
        idempotency_key: str,
        vehicle_id: str = "manual",
        current_soc: float = 0,
        *,
        expected_device_id: str | None = None,
        target_soc: float | None = None,
    ) -> ChargingSession:
        """Manual ON is permitted only with a device-side safety timer.

        [target_soc] is display/estimate context only (Task 122): the device
        timer alone decides when the relay switches off.
        """
        timer = _StageTimer()
        duration_seconds = int(duration_seconds)
        if duration_seconds < 5 or duration_seconds > self.max_minutes * 60:
            raise SmartChargeError("unsafeDuration", "Safety timer phải từ 5 giây đến 10 giờ")
        if not idempotency_key or len(idempotency_key) > 160:
            raise SmartChargeError("invalidIdempotencyKey", "Thiếu Idempotency-Key")
        # Independent reads (Firestore nam5 is ~0.2 s away) run together; the
        # decisions below keep their original order and meaning (Task 123).
        # Active sessions are read per account and filtered by device after
        # the binding is known, so the binding read joins the same round.
        checks = _parallel({
            "binding": lambda: self.binding(uid, vehicle_id if vehicle_id != "manual" else None),
            "vehicle": (lambda: self._owned_vehicle(uid, vehicle_id)) if vehicle_id != "manual" else (lambda: {}),
            "existing": lambda: self.repository.get_by_idempotency(uid, idempotency_key),
            "active": lambda: self.repository.active_sessions(uid),
        })
        binding = checks["binding"].result()
        if not binding:
            raise SmartChargeError("notConfigured", "Shelly chưa được kết nối", 404)
        if expected_device_id is not None and (not isinstance(expected_device_id, str) or
                not expected_device_id.strip() or
                self.repository._device_owner_doc_id(expected_device_id) != self.repository._device_owner_doc_id(binding.device_id)):
            raise SmartChargeError("bindingChanged", "Liên kết đã thay đổi; hãy xác nhận yêu cầu mới", 409)
        vehicle = checks["vehicle"].result()
        existing = checks["existing"].result()
        if existing:
            return existing
        if any(active.device_id == binding.device_id for active in checks["active"].result()):
            raise SmartChargeError("activeSessionConflict", "Đang có một phiên sạc hoạt động", 409)
        if not self.provider.supports_device_timer:
            raise SmartChargeError("providerTimerUnsupported", "Provider chưa hỗ trợ timer trên thiết bị", 503)
        timer.mark("checks")
        now = self.clock()
        before, on_context = self._prepare_energize(binding)
        timer.mark("prepare")
        session = ChargingSession(
            session_id=str(uuid.uuid4()),
            device_id=binding.device_id,
            vehicle_id=vehicle_id or "manual",
            state="arming",
            strategy="manual_timed",
            start_soc=max(0, min(100, float(current_soc))),
            target_soc=_display_target_soc(current_soc, target_soc),
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
            soc_estimate_source=("shelly_energy"
                                 if _optional_float(vehicle.get("nominalCapacityWh")) else "unavailable"),
            soc_estimate_quality=("live"
                                  if _optional_float(vehicle.get("nominalCapacityWh")) else "unavailable"),
            soc_estimation_version=2,
            owner_uid=uid,
            nominal_capacity_wh=_optional_float(vehicle.get("nominalCapacityWh")),
            state_of_health=_optional_float(vehicle.get("stateOfHealth")),
            safety_policy_version=self.safety_policy.version,
        )
        # Device lock + new session row in one transaction (was two).
        if not self.repository.claim_device_and_create_session(uid, session):
            raise SmartChargeError("activeSessionConflict", "Shelly đang được dùng bởi một phiên khác", 409)
        timer.mark("claim")
        try:
            self._send_on(binding, duration_seconds, on_context)
            timer.mark("on")
            # The dispatch gate already spaces the readback >=1.1s after ON.
            # Cloud status from East Asia can lag a few seconds: read again
            # (never resend ON) before declaring the timer unverified.
            status = self._read_until(
                binding,
                lambda current: (self._status_matches_device(current, binding.device_id)
                                 and current.relay is True and current.timer_remaining > 0),
                4,
            )
            if status is None:
                raise ProviderError("timerNotArmed", "Không xác minh được safety timer")
            timer.mark("readback")
            self._anchor_stop_to_device_timer(session, status, manual=True)
            session.state = "active"
            session.relay_verified = True
            session.timer_verified = True
            session.updated_at = self.clock()
            session.version += 1
            self._commit_started_session(uid, session, binding)
            timer.mark("save")
            self.repository.append_audit(uid, "manual_on_verified", session_id=session.session_id,
                                         device_id=binding.device_id, duration_seconds=duration_seconds,
                                         timings_ms=timer.result())
            self._emit_state_push(uid, session)
            return session
        except ProviderError as exc:
            off_verified = False
            try:
                self.provider.turn_off(binding)
                off_status = self.provider.get_status(binding)
                off_verified = self._status_matches_device(off_status, binding.device_id) and off_status.relay is False
            except ProviderError:
                pass
            session.state = "failed" if off_verified else "unknown"
            session.relay_verified = off_verified
            session.stop_reason = "command_failed"
            session.last_error = exc.code
            session.stopped_at = self.clock() if off_verified else None
            session.updated_at = self.clock()
            session.version += 1
            self.repository.save_session(uid, session)
            if off_verified:
                self.repository.upsert_charge_log(uid, session)
            raise self._provider_error(exc) from exc

    def current(self, uid: str, vehicle_id: str | None = None) -> ChargingSession | None:
        session = self.repository.current_session(uid, vehicle_id=vehicle_id)
        if not session:
            return None
        binding = self.session_binding(uid, session)
        if not binding:
            return self.mark_session_unknown(uid, session, "bindingChanged")
        try:
            status = self.provider.get_status(binding)
        except ProviderError as error:
            if error.code in TRANSIENT_READ_CODES:
                return session
            return self.mark_session_unknown(uid, session, error.code)
        return self._reconcile_with_status(uid, status, vehicle_id, session=session)

    def recover(self, uid: str, vehicle_id: str | None = None) -> ChargingSession | None:
        """Called on server startup/restart. Reads real relay state from Shelly and synchronizes database."""
        session = self.repository.current_session(uid, vehicle_id=vehicle_id)
        if not session:
            return None
        binding = self.session_binding(uid, session)
        if not binding:
            return self.mark_session_unknown(uid, session, "bindingChanged")
        try:
            status = self.provider.get_status(binding)
        except ProviderError as error:
            if error.code in TRANSIENT_READ_CODES:
                return session
            return self.mark_session_unknown(uid, session, error.code)
        self._apply_safety(uid, binding, status)
        return self._reconcile_with_status(uid, status, vehicle_id, session=session)


    def _commit_started_session(self, uid: str, session: ChargingSession, binding) -> None:
        """Save the verified ON. If the row changed meanwhile (another reader
        finalized it), never leave the relay energized without a session."""
        try:
            self.repository.save_session(uid, session)
        except RuntimeError as exc:
            try:
                self.provider.turn_off(binding)
            except ProviderError:
                pass
            self.repository.append_audit(uid, "start_commit_conflict", session_id=session.session_id,
                                         device_id=binding.device_id, error=str(exc)[:60])
            raise SmartChargeError("sessionChangedElsewhere",
                                   "Phiên sạc vừa thay đổi ở nơi khác nên ổ đã được tắt để an toàn. Hãy thử lại.",
                                   409, True) from exc

    def _reconcile_with_status(self, uid: str, status, vehicle_id: str | None = None,
                               *, session: ChargingSession | None = None) -> ChargingSession | None:
        session = session or self.repository.current_session(uid, vehicle_id=vehicle_id)
        if not session:
            return None
        if session.state not in NONTERMINAL_SESSION_STATES:
            return session
        now = self.clock()
        if (session.state in {"arming", "starting"}
                and (now - session.created_at).total_seconds() < COMMAND_IN_FLIGHT_GRACE_SECONDS):
            # manual_on/start own this session until they save it (Task 125):
            # /live or the worker reading OFF here would cut a verified ON.
            return session
        if not self._status_matches_device(status, session.device_id):
            return self.mark_session_unknown(uid, session, "deviceUnverified")
        if status.relay is True:
            # Measured before updated_at moves: how long an accepted OFF has
            # been waiting for Cloud status to catch up.
            pending_off_age = (now - session.updated_at).total_seconds()
            self._ingest_energy(session, status.energy_wh)
            session.updated_at = now
            if now >= session.absolute_safety_stop_at or now >= session.effective_stop_at:
                return self._backup_stop_session(uid, session, state="interrupted", stop_reason="deadline_cutoff")
            if session.state == "stopping" and session.last_error == OFF_PENDING_READBACK:
                if pending_off_age < OFF_READBACK_GRACE_SECONDS:
                    # Shelly Cloud status can lag behind an accepted OFF.
                    return session
                session.last_error = None
                return self._backup_stop_session(uid, session, state="cancelled", stop_reason="manual")
            if session.state in {"stopping", "unknown"}:
                return self._backup_stop_session(uid, session, state="interrupted", stop_reason="recovery_off")
            if status.timer_remaining <= 0:
                session.last_error = "timerNotArmed"
                return self._backup_stop_session(uid, session, state="failed", stop_reason="command_failed")
            else:
                self._checkpoint_session(uid, session)
            return session
        if session.state == "stopping":
            # Only stop() moves a session to "stopping": relay OFF here is the
            # user's OFF (verified or still awaiting its own readback).
            if session.last_error == OFF_PENDING_READBACK:
                session.last_error = None
            return self._finalize_session(uid, session, state="cancelled",
                                          stop_reason="manual", status=status)
        state, stop_reason = self._relay_off_outcome(session, now)
        return self._finalize_session(uid, session, state=state,
                                      stop_reason=stop_reason, status=status)

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


def _display_target_soc(current_soc, target_soc) -> float:
    start = max(0.0, min(100.0, float(current_soc)))
    target = _optional_float(target_soc)
    if target is None:
        return start
    return max(start, min(100.0, target))


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
