from __future__ import annotations

import hashlib
import math
import re
import os
import threading
import time
from datetime import datetime, timezone
from urllib.parse import urlparse

import requests

from ..models import DeviceBinding, DeviceStatus
from .base import ProviderError
from ..safety_fingerprint import FINGERPRINT_VERSION, cloud_safety_fingerprint
from ..cloud_dispatch import CloudAdmissionError, retry_after_seconds


NO_LOAD_TIMER_SECONDS = 20
PROFILE_READ_CACHE_SECONDS = 60
IDLE_STATUS_CACHE_SECONDS = 10
NO_LOAD_ON_OBSERVE_SECONDS = 12
NO_LOAD_OFF_GRACE_SECONDS = 10
# Task 122: an ON request reuses the readiness read when it is this fresh;
# older contexts are re-read once before the command (never a second ON).
ON_CONTEXT_REFRESH_SECONDS = 6


def _run_parallel(jobs: dict) -> dict:
    """Start independent reads together; callers inspect each future."""
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=len(jobs)) as pool:
        futures = {name: pool.submit(job) for name, job in jobs.items()}
    return futures


class VaultCloudControlProvider:
    """Per-account Shelly Cloud provider. Credentials are resolved from the server vault."""

    name = "vault_cloud"
    supports_status = True
    supports_manual_off = True
    supports_manual_on = True
    supports_device_timer = True

    def __init__(self, repository, session=None, sleeper=time.sleep, clock=time.time):
        self.repository = repository
        self.http = session or requests.Session()
        self.sleep = sleeper
        self.clock = clock

    def _profile(self, binding: DeviceBinding, *, fresh: bool = True, profile: dict | None = None) -> tuple[str, str]:
        uid = binding.owner_uid
        if not uid:
            raise ProviderError("ownershipUnavailable", "Không xác minh được chủ sở hữu Shelly")
        # One fresh vault read can serve every check made at the same moment
        # (Task 123: an ON used to decrypt the same document ~10 times).
        if profile is None:
            profile = self._restore_profile(binding, fresh=fresh)
        if not profile or profile.get("revokedAt"):
            raise ProviderError("profileUnavailable", "Cấu hình Shelly chưa được lưu trên máy chủ")
        if str(profile.get("model") or "").upper() != "S3PL-00112EU":
            raise ProviderError("unsupportedDevice", "Thiết bị không phải Shelly Plug S Gen3")
        host = str(profile.get("cloudHost") or "").rstrip("/")
        key = str(profile.get("cloudAuthKey") or "").strip()
        parsed = urlparse(host)
        if parsed.scheme != "https" or not parsed.hostname or not (
            parsed.hostname == "shelly.cloud" or parsed.hostname.endswith(".shelly.cloud")
        ) or parsed.username or parsed.password or parsed.netloc != parsed.hostname or parsed.path not in ("", "/") or parsed.query or parsed.fragment or not key:
            raise ProviderError("invalidProviderConfig", "Cấu hình Shelly Cloud không hợp lệ")
        return host, key

    def _restore_profile(self, binding, *, fresh: bool = True):
        # Status reads may reuse a profile decrypted within the last minute;
        # commands, ON and live safety checks always read fresh (Task108).
        try:
            restore = self.repository.restore_synced_profile
            try:
                profile = restore(binding.owner_uid, binding.device_id, audit=False,
                                  max_age_seconds=0 if fresh else PROFILE_READ_CACHE_SECONDS)
            except TypeError:
                profile = restore(binding.owner_uid, binding.device_id)  # legacy test doubles
        except Exception as error:
            raise ProviderError("profileUnavailable", "Chưa đọc được cấu hình Shelly. Hãy thử lại.", True) from error
        if not isinstance(profile, dict):
            raise ProviderError("profileUnavailable", "Chưa đọc được cấu hình Shelly. Hãy thử lại.", True)
        return profile

    def _post(self, binding: DeviceBinding, path: str, payload: dict, *, command=False,
              safety_context=None, expected_credentials=None, profile=None) -> object:
        is_on = path == "/v2/devices/api/set/switch" and payload.get("on") is True
        if command:
            self._forget_status(binding)
        if is_on and isinstance(safety_context, dict) and safety_context.get("credentials"):
            # Routing only: the admitted slot below re-reads the vault fresh
            # and rejects any change before the command is sent.
            host, key = safety_context["credentials"]
        else:
            host, key = self._profile(binding, fresh=command or is_on or expected_credentials is not None,
                                      profile=profile)
        if is_on and safety_context is None:
            raise ProviderError("safetyVerificationRequired", "Cần kiểm tra an toàn bộ sạc trước khi bật")
        fingerprint = hashlib.sha256(key.encode("utf-8")).hexdigest()
        guard = getattr(self, "worker_lease_guard", None)
        def send():
            if guard:
                guard()
            # These checks remain inside the admitted operation, after queueing:
            # one fresh vault read, shared by the credential and safety checks.
            if expected_credentials is not None or is_on:
                fresh_profile = self._restore_profile(binding)
                current = self._profile(binding, profile=fresh_profile)
                if current != (host, key) or (expected_credentials is not None and current != expected_credentials):
                    raise ProviderError("verificationChanged", "Cấu hình đã thay đổi; hãy kiểm tra lại")
                if is_on:
                    self._assert_safety_context(binding, safety_context, profile=fresh_profile)
            try:
                response = self.http.post(f"{host}{path}", params={"auth_key": key}, json=payload, timeout=7)
            except requests.RequestException as exc:
                raise ProviderError("deviceOffline", "Shelly Cloud không phản hồi", True) from exc
            if command:
                # Sanitized diagnostics only: no key, host or device identifiers.
                try:
                    body = response.json()
                    summary = {"isok": body.get("isok"), "hasError": bool(body.get("error") or body.get("errors"))} if isinstance(body, dict) else {"type": type(body).__name__}
                    if isinstance(body, dict):
                        # Error codes only (Task 123: an OFF got HTTP 400 and
                        # the cause was invisible). Never values or ids.
                        raw = body.get("errors") or body.get("error")
                        codes = (sorted(str(k)[:40] for k in raw)[:5] if isinstance(raw, dict)
                                 else [str(raw)[:40]] if isinstance(raw, str) else [])
                        if codes:
                            summary["errorCodes"] = [re.sub(r"[^A-Za-z0-9_.-]", "_", c) for c in codes]
                except ValueError:
                    summary = {"nonJson": True}
                print(f"[shelly-cloud] command on={payload.get('on')} toggle_after={payload.get('toggle_after')} "
                      f"http={response.status_code} {summary}", flush=True)
            if response.status_code in (401, 403):
                raise ProviderError("needsReauthentication", "Quyền truy cập Shelly Cloud không hợp lệ", status_code=response.status_code)
            if response.status_code == 429:
                delay = retry_after_seconds(getattr(response, "headers", {}).get("Retry-After"))
                self.repository.defer_cloud_requests(fingerprint, delay)
                raise ProviderError("cloudRateLimited", "Shelly Cloud đang giới hạn tần suất", True,
                                    status_code=429, retry_after_seconds=delay)
            if response.status_code != 200:
                raise ProviderError("providerRejected", "Shelly Cloud chưa thực hiện được yêu cầu", response.status_code >= 500,
                                    status_code=response.status_code)
            try:
                value = response.json()
            except ValueError as exc:
                if command:
                    return None  # Acceptance only, never verified relay success.
                raise ProviderError("malformedProviderResponse", "Shelly Cloud trả dữ liệu không hợp lệ") from exc
            if isinstance(value, dict) and (value.get("isok") is False or value.get("error")):
                raise ProviderError("providerRejected", "Shelly Cloud từ chối yêu cầu")
            return value
        try:
            budget = getattr(self, "_admission_budget", None)
            kwargs = {"admission_budget": budget} if budget is not None else {}
            return self.repository.run_cloud_request(fingerprint, send,
                priority_off=path == "/v2/devices/api/set/switch" and payload.get("on") is False,
                sleeper=self.sleep, guard=guard, **kwargs)
        except ProviderError:
            raise
        except CloudAdmissionError as error:
            code = "cloudQueueBusy" if str(error) == "cloudQueueBusy" else "cloudRateLimiterUnavailable"
            raise ProviderError(code, "Kết nối bộ sạc đang bận. Hãy thử lại.", True) from error
        except Exception as error:
            # Includes datastore/worker fencing failures; never fallback to HTTP.
            raise ProviderError("cloudRateLimiterUnavailable", "Chưa thể xác minh kết nối bộ sạc. Hãy thử lại.", True) from error

    @staticmethod
    def _device(value, device_id: str):
        entries = value if isinstance(value, list) else value.get("devices", []) if isinstance(value, dict) else []
        for entry in entries:
            if isinstance(entry, dict) and str(entry.get("id") or "").lower() == device_id.lower():
                return entry
        if isinstance(value, dict):
            return value
        return None

    def get_snapshot(self, binding: DeviceBinding, *, expected_credentials=None, profile=None) -> dict:
        # Keep legacy read/OFF compatible; G2 is mandatory for new ON evidence.
        kwargs = {"expected_credentials": expected_credentials} if expected_credentials is not None else {}
        if profile is not None:
            kwargs["profile"] = profile
        raw = self._post(binding, "/v2/devices/api/get", {"ids": [binding.device_id], "select": ["status", "settings"]}, **kwargs)
        device = self._device(raw, binding.device_id)
        if not isinstance(device, dict) or str(device.get("id") or "").lower() != binding.device_id.lower():
            raise ProviderError("deviceNotFound", "Không xác minh được thiết bị Shelly đã liên kết")
        online = device.get("online")
        if online is not True and not (type(online) is int and online == 1):
            raise ProviderError("deviceOffline", "Shelly đang ngoại tuyến", True)
        if str(device.get("code") or "").upper() != "S3PL-00112EU" or str(device.get("type") or "").lower() != "relay":
            raise ProviderError("unsupportedDevice", "Thiết bị không phải Shelly Plug S Gen3")
        return device

    @staticmethod
    def _switch(snapshot: dict) -> dict:
        status = snapshot.get("status") or {}
        switch = status.get("switch:0") if isinstance(status, dict) else None
        if not isinstance(switch, dict):
            raise ProviderError("malformedProviderResponse", "Thiếu dữ liệu switch:0 từ Shelly")
        return switch

    def _status_cache_state(self):
        # Idle (relay OFF) status shared by live/status reads for a few seconds;
        # ON states and every command bypass/clear it (Task108). Lazy so
        # subclasses that skip __init__ still work.
        state = self.__dict__.get("_status_cache_state_value")
        if state is None:
            state = self.__dict__["_status_cache_state_value"] = ({}, threading.Lock())
        return state

    def get_status(self, binding: DeviceBinding, *, max_age_seconds: float = 0) -> DeviceStatus:
        key = str(binding.device_id).lower()
        if max_age_seconds > 0:
            cache, lock = self._status_cache_state()
            with lock:
                cached = cache.get(key)
            if cached and time.monotonic() - cached[0] <= max_age_seconds and cached[1].relay is False:
                return cached[1]
        snapshot = self.get_snapshot(binding)
        status = self._status_from_snapshot(binding, snapshot)
        cache, lock = self._status_cache_state()
        with lock:
            if status.relay is False:
                cache[key] = (time.monotonic(), status)
            else:
                cache.pop(key, None)
        return status

    def _forget_status(self, binding: DeviceBinding) -> None:
        cache, lock = self._status_cache_state()
        with lock:
            cache.pop(str(binding.device_id).lower(), None)

    def _status_from_snapshot(self, binding: DeviceBinding, snapshot: dict) -> DeviceStatus:
        switch = self._switch(snapshot)
        if not all(field in switch for field in ("apower", "voltage", "current", "aenergy")):
            raise ProviderError("unsupportedDevice", "Thiếu trường đo điện năng của Shelly")
        if not isinstance(switch.get("output"), bool):
            raise ProviderError("malformedProviderResponse", "Không xác minh được trạng thái relay")
        energy = switch.get("aenergy")
        if not isinstance(energy, dict) or "total" not in energy:
            raise ProviderError("malformedProviderResponse", "Thiếu số đo điện năng")
        def meter(value, field):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
                raise ProviderError("malformedProviderResponse", f"Số đo {field} không hợp lệ")
            return float(value)
        timer = self._timer_remaining(snapshot, switch)
        temperature = switch.get("temperature") or {}
        return DeviceStatus(
            online=True,
            relay=switch["output"],
            timer_remaining=timer,
            power_w=meter(switch["apower"], "W"),
            voltage_v=meter(switch["voltage"], "V"),
            current_a=meter(switch["current"], "A"),
            temperature_c=meter(temperature["tC"], "°C") if isinstance(temperature, dict) and temperature.get("tC") is not None else None,
            energy_wh=meter(energy["total"], "Wh"),
            device_id=binding.device_id,
        )

    def _timer_remaining(self, snapshot: dict, switch: dict) -> int:
        # Gen2+ RPC reports an actual triggered timer using its UTC start and
        # duration, not necessarily timer_remaining. A configured auto_off
        # delay alone is never proof that a device timer is running.
        def finite_number(value):
            return (not isinstance(value, bool) and isinstance(value, (int, float))
                    and math.isfinite(value))

        if switch.get("output") is not True:
            return 0
        sys_diag = (snapshot.get("status") or {}).get("sys") or {}
        device_diag = sys_diag.get("unixtime") if isinstance(sys_diag, dict) else None
        skew = (round(device_diag - self.clock(), 1) if finite_number(device_diag) and finite_number(self.clock()) else None)
        # Sanitized diagnostics (Task108): field presence and clock skew only.
        print(f"[shelly-cloud] timer-fields remaining={'timer_remaining' in switch} "
              f"started={'timer_started_at' in switch} duration={switch.get('timer_duration')} "
              f"deviceClockSkew={skew}", flush=True)
        remaining = switch.get("timer_remaining")
        if remaining is not None:
            if not finite_number(remaining) or not 0 <= remaining <= 36000:
                raise ProviderError("malformedProviderResponse", "Timer Shelly không hợp lệ")
            return max(0, math.floor(remaining))
        started, duration = switch.get("timer_started_at"), switch.get("timer_duration")
        sys_status = (snapshot.get("status") or {}).get("sys") or {}
        device_now = sys_status.get("unixtime") if isinstance(sys_status, dict) else None
        now = self.clock()
        if not all(finite_number(value) for value in (started, duration, now)):
            return 0
        if started < 1577836800 or not 0 < duration <= 36000:
            return 0
        if finite_number(device_now) and abs(device_now - now) <= 30:
            if started > device_now + 2:
                return 0
            reference = max(now, device_now)
        else:
            # Shelly Cloud may serve a cached sys.unixtime minutes old (Task108:
            # ~1500s). Fall back to the server clock, accepting only a timer
            # that started recently and not in the future.
            if started > now + 30 or started < now - duration - 30:
                return 0
            reference = now
        # Use the later clock: skew or cached clock data must never prolong
        # the countdown. Expired timestamps resolve to zero, not full duration.
        return max(0, math.floor(min(duration, started + duration - reference)))

    def _assert_safety_context(self, binding, context, *, profile=None):
        age = self.clock() - context["observedAt"]
        if not math.isfinite(age) or not 0 <= age <= 10:
            raise ProviderError("safetySnapshotStale", "Kiểm tra kết nối đã hết hạn; hãy thử lại", True)
        if os.environ.get("AZURE_STAGING_HARDWARE_DISABLED", "0") == "1":
            raise ProviderError("workerUnavailable", "Giám sát sạc chưa sẵn sàng", True)
        # Independent fresh reads (Firestore is ~0.2 s away): run them together
        # instead of one after another. Every check below still applies.
        now = datetime.now(timezone.utc)
        jobs = {
            "worker": lambda: self.repository.worker_health_ready(now),
            "owned": lambda: self.repository.device_owned_by(binding.owner_uid, binding.device_id),
        }
        if profile is None:
            jobs["profile"] = lambda: self._restore_profile(binding)
        results = _run_parallel(jobs)
        if profile is None:
            profile = results["profile"].result()
        host, key = self._profile(binding, profile=profile)
        if (host, key) != context["credentials"]:
            raise ProviderError("verificationChanged", "Cấu hình đã thay đổi; hãy kiểm tra lại")
        try:
            worker_ready = results["worker"].result()
        except Exception:
            worker_ready = False
        if not worker_ready:
            raise ProviderError("workerUnavailable", "Giám sát sạc chưa sẵn sàng", True)
        try:
            owned = results["owned"].result()
        except Exception as error:
            raise ProviderError("ownershipUnavailable", "Chưa xác minh được quyền điều khiển Shelly", True) from error
        if owned is not True:
            raise ProviderError("ownershipUnavailable", "Chưa xác minh được quyền điều khiển Shelly")
        if not profile or profile.get("revokedAt") or profile.get("revision") != context["revision"]:
            raise ProviderError("verificationChanged", "Liên kết đã thay đổi; hãy kiểm tra lại")
        if context["requireHistory"]:
            if (type(profile.get("verificationFingerprintVersion")) is not int
                    or profile["verificationFingerprintVersion"] != FINGERPRINT_VERSION
                    or profile.get("verificationFingerprint") != context["fingerprint"]
                    or not all(profile.get(field) is True for field in (
                        "cloudVerified", "powerMeterVerified", "safeBootVerified", "noLoadTestVerified",
                        "onObserved", "timerObserved", "timerAutoOffObserved", "relayOffVerified"))
                    or str(profile.get("verifiedDeviceId") or "").lower() != binding.device_id.lower()
                    or profile.get("verifiedModel") != "S3PL-00112EU"):
                raise ProviderError("safetyVerificationRequired", "Cần kiểm tra lại an toàn bộ sạc")

    def _live_safety_context(self, binding, *, require_history=True, verify=True, relay_on=False):
        profile = self._restore_profile(binding)
        credentials = self._profile(binding, profile=profile)
        snapshot = (self.get_snapshot(binding, expected_credentials=credentials, profile=profile)
                    if verify else self.get_snapshot(binding, profile=profile))
        status = self._status_from_snapshot(binding, snapshot)
        fingerprint = cloud_safety_fingerprint(binding.device_id, *credentials, snapshot)
        if relay_on:
            # Only for re-arming the auto-off of a running session (QA 135).
            if status.relay is not True:
                raise ProviderError("relayNotOn", "Bộ sạc không còn bật")
        elif status.relay is not False:
            raise ProviderError("relayAlreadyOn", "Bộ sạc đang bật; hãy kiểm tra phiên hiện tại")
        if (not 190 <= status.voltage_v <= 255 or not 0 <= status.current_a <= 12
                or not 0 <= status.power_w <= 2500 or status.energy_wh < 0
                or (status.temperature_c is not None and status.temperature_c > 75)):
            raise ProviderError("unsafeMeasurements", "Số đo bộ sạc ngoài ngưỡng an toàn")
        revision = profile.get("revision") if isinstance(profile, dict) else None
        if type(revision) is not int or revision < 1:
            raise ProviderError("verificationChanged", "Chưa xác minh được phiên bản liên kết")
        context = {"credentials": credentials, "revision": revision, "fingerprint": fingerprint,
                   "observedAt": self.clock(), "requireHistory": require_history, "status": status}
        if verify:
            self._assert_safety_context(binding, context)
        return context

    def verify_control_readiness(self, binding: DeviceBinding) -> None:
        # Display readiness right after a status read in the same request: wait
        # longer for the shared Cloud slot instead of reporting cloudQueueBusy
        # (Task108). ON still re-runs the full live check itself.
        previous_budget = getattr(self, "_admission_budget", None)
        self._admission_budget = 12.0
        try:
            self._live_safety_context(binding)
        finally:
            self._admission_budget = previous_budget

    def _send_verified_on(self, binding, duration_seconds, context):
        if type(duration_seconds) is not int or not 5 <= duration_seconds <= 36000:
            raise ProviderError("unsafeDuration", "Thời gian sạc phải từ 5 giây đến 10 giờ")
        self._post(binding, "/v2/devices/api/set/switch", {"id": binding.device_id, "channel": 0, "on": True, "toggle_after": duration_seconds}, command=True, safety_context=context)

    def prepare_on(self, binding: DeviceBinding) -> dict:
        """The single fresh live safety read for one ON request (Task 122).

        The service checks its status for the readiness gate and passes the
        context to [turn_on_with_context]. Credentials, revision, ownership,
        worker health and the 10 s age limit are still re-checked inside the
        admitted Cloud slot right before the command.
        """
        previous_budget = getattr(self, "_admission_budget", None)
        self._admission_budget = 12.0
        try:
            # Task 123: the measured thresholds (V/A/W/°C, relay OFF) are
            # checked here; credentials/revision/fingerprint/history, worker
            # and ownership are checked fresh inside the admitted ON slot
            # (they used to be read twice more here, ~3 s from East Asia).
            return self._live_safety_context(binding, verify=False)
        finally:
            self._admission_budget = previous_budget

    def turn_on_with_context(self, binding: DeviceBinding, duration_seconds: int, context: dict) -> None:
        if not isinstance(context, dict) or "observedAt" not in context:
            raise ProviderError("safetyVerificationRequired", "Cần kiểm tra an toàn bộ sạc trước khi bật")
        age = self.clock() - context["observedAt"]
        if not math.isfinite(age) or age < 0 or age > ON_CONTEXT_REFRESH_SECONDS:
            # Re-read rather than let the admitted check reject a slow request.
            context = self._live_safety_context(binding)
        self._send_verified_on(binding, duration_seconds, context)

    def extend_timer(self, binding: DeviceBinding, duration_seconds: int) -> None:
        """Re-arm the auto-off of an outlet that is ON for a running session
        (QA 135: the owner raised the target). Same live checks as ON:
        measurements, worker health, ownership, credentials and the verified
        safety history, except that the relay must already be ON; the
        command keeps it ON and sets a new ``toggle_after``."""
        if type(duration_seconds) is not int or not 5 <= duration_seconds <= 36000:
            raise ProviderError("unsafeDuration", "Thời gian sạc phải từ 5 giây đến 10 giờ")
        previous_budget = getattr(self, "_admission_budget", None)
        self._admission_budget = 12.0
        try:
            context = self._live_safety_context(binding, relay_on=True)
            self._post(binding, "/v2/devices/api/set/switch",
                       {"id": binding.device_id, "channel": 0, "on": True, "toggle_after": duration_seconds},
                       command=True, safety_context=context)
        finally:
            self._admission_budget = previous_budget

    def turn_on_with_timer(self, binding: DeviceBinding, duration_seconds: int) -> None:
        # A second live check under the device lock protects every caller,
        # including chat/API. No cached readiness boolean grants this command.
        self._send_verified_on(binding, duration_seconds, self._live_safety_context(binding))

    def confirm_relay_off(self, binding: DeviceBinding) -> bool:
        """Fresh readback for lock recovery; waits longer to be admitted."""
        previous_budget = getattr(self, "_admission_budget", None)
        self._admission_budget = 12.0
        try:
            return self.get_status(binding).relay is False
        except Exception:
            return False
        finally:
            self._admission_budget = previous_budget

    def turn_off(self, binding: DeviceBinding) -> None:
        self._post(binding, "/v2/devices/api/set/switch", {"id": binding.device_id, "channel": 0, "on": False}, command=True)

    def revoke(self, binding: DeviceBinding) -> None:
        return None

    def run_no_load_test(self, binding: DeviceBinding) -> dict:
        # The user-confirmed test issues ~10 sequential Cloud calls; let each
        # wait longer for admission behind concurrent status reads (Task108).
        # Admission failures happen before a request is sent, so no command
        # is ever duplicated; spacing/one-in-flight/OFF priority are unchanged.
        previous_budget = getattr(self, "_admission_budget", None)
        self._admission_budget = 12.0
        try:
            return self._run_no_load_test(binding)
        finally:
            self._admission_budget = previous_budget

    def _run_no_load_test(self, binding: DeviceBinding) -> dict:
        # Only this explicit, backend-confirmed test can start without history.
        context = self._live_safety_context(binding, require_history=False)
        initial = context["status"]
        if not 190 <= initial.voltage_v <= 255:
            raise ProviderError("unsafeVoltage", "Điện áp ngoài ngưỡng an toàn")
        if not 0 <= initial.power_w <= 5 or not 0 <= initial.current_a <= .1:
            raise ProviderError("unexpectedLoad", "Có tải điện trong lúc kiểm tra không tải")
        on_observed = False
        timer_observed = False
        timer_auto_off_observed = False
        off_verified = False
        on_status = None
        try:
            # 20s device timer: Cloud status from Azure East Asia to the EU
            # Shelly cloud can lag several seconds, so a 5s timer could expire
            # before ON+timer is ever observable (Task108). Still no load.
            on_sent_at = self.clock()
            self._send_verified_on(binding, NO_LOAD_TIMER_SECONDS, context)
            for _ in range(12):
                if self.clock() - on_sent_at > NO_LOAD_ON_OBSERVE_SECONDS:
                    break
                self.sleep(1.1)
                status = self.get_status(binding)
                if status.relay and status.timer_remaining > 0:
                    on_observed, timer_observed, on_status = True, True, status
                    break
            if not on_observed:
                raise ProviderError("timerNotArmed", "Không xác minh được relay ON và timer")
            if (not 0 <= on_status.power_w <= 5 or not 0 <= on_status.current_a <= .1 or
                    not 190 <= on_status.voltage_v <= 255):
                raise ProviderError("unexpectedLoad", "Có tải điện trong lúc kiểm tra không tải")
            # A manual cleanup OFF is not evidence that the device timer works.
            # Observe the device turn itself OFF before sending cleanup OFF.
            for _ in range(30):
                if self.clock() - on_sent_at > NO_LOAD_TIMER_SECONDS + NO_LOAD_OFF_GRACE_SECONDS:
                    break
                self.sleep(1.1)
                if not self.get_status(binding).relay:
                    timer_auto_off_observed = True
                    break
            if not timer_auto_off_observed:
                raise ProviderError("timerAutoOffUnverified", "Không xác minh được timer tự tắt relay")
        finally:
            try:
                self.turn_off(binding)
            finally:
                off_verified = self.get_status(binding).relay is False
        if not off_verified:
            raise ProviderError("relayUnverified", "Không xác minh được relay OFF sau kiểm tra")
        # Config/credential changes during the test invalidate its result.
        final_context = self._live_safety_context(binding, require_history=False)
        if (final_context["fingerprint"] != context["fingerprint"]
                or final_context["revision"] != context["revision"]):
            raise ProviderError("verificationChanged", "Cấu hình đã thay đổi trong lúc kiểm tra")
        return {"identityVerified": True, "powerMeterVerified": True, "safeBootVerified": True, "noLoadTestVerified": on_observed and timer_observed and timer_auto_off_observed and off_verified, "initialState": "off", "autoOn": False, "relayOffVerified": off_verified,
                "verificationFingerprint": context["fingerprint"], "verificationFingerprintVersion": FINGERPRINT_VERSION,
                "profileRevision": context["revision"], "onObserved": on_observed, "timerObserved": timer_observed,
                "timerAutoOffObserved": timer_auto_off_observed}
