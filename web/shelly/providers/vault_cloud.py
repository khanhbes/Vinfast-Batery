from __future__ import annotations

import hashlib
import math
import time
from urllib.parse import urlparse

import requests

from ..models import DeviceBinding, DeviceStatus
from .base import ProviderError


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

    def _profile(self, binding: DeviceBinding) -> tuple[str, str]:
        uid = binding.owner_uid
        if not uid:
            raise ProviderError("ownershipUnavailable", "Không xác minh được chủ sở hữu Shelly")
        profile = self.repository.restore_synced_profile(uid, binding.device_id)
        if not profile or profile.get("revokedAt"):
            raise ProviderError("profileUnavailable", "Cấu hình Shelly chưa được lưu trên máy chủ")
        if str(profile.get("model") or "").upper() != "S3PL-00112EU":
            raise ProviderError("unsupportedDevice", "Thiết bị không phải Shelly Plug S Gen3")
        host = str(profile.get("cloudHost") or "").rstrip("/")
        key = str(profile.get("cloudAuthKey") or "").strip()
        parsed = urlparse(host)
        if parsed.scheme != "https" or not parsed.hostname or not (
            parsed.hostname == "shelly.cloud" or parsed.hostname.endswith(".shelly.cloud")
        ) or parsed.path not in ("", "/") or parsed.query or parsed.fragment or not key:
            raise ProviderError("invalidProviderConfig", "Cấu hình Shelly Cloud không hợp lệ")
        return host, key

    def _post(self, binding: DeviceBinding, path: str, payload: dict, *, command=False) -> object:
        host, key = self._profile(binding)
        fingerprint = hashlib.sha256(key.encode("utf-8")).hexdigest()
        try:
            wait = self.repository.reserve_cloud_request_slot(fingerprint, 1.1)
        except Exception as exc:
            raise ProviderError("cloudRateLimiterUnavailable", "Không xác minh được giới hạn request Shelly Cloud") from exc
        if wait > 0:
            self.sleep(wait)
        try:
            response = self.http.post(f"{host}{path}", params={"auth_key": key}, json=payload, timeout=7)
        except requests.RequestException as exc:
            raise ProviderError("deviceOffline", "Shelly Cloud không phản hồi", True) from exc
        if response.status_code in (401, 403):
            raise ProviderError("needsReauthentication", "Quyền truy cập Shelly Cloud không hợp lệ")
        if response.status_code == 429:
            raise ProviderError("cloudRateLimited", "Shelly Cloud đang giới hạn tần suất", True)
        if response.status_code != 200:
            raise ProviderError("providerRejected", f"Shelly Cloud từ chối yêu cầu ({response.status_code})", response.status_code >= 500)
        try:
            value = response.json()
        except ValueError as exc:
            # Cloud v2 acknowledges switch commands with HTTP 200; a JSON
            # body is not part of that acknowledgement contract. This is only
            # acceptance, never relay/timer verification. Reads remain strict.
            if command:
                return None
            raise ProviderError("malformedProviderResponse", "Shelly Cloud trả dữ liệu không hợp lệ") from exc
        if isinstance(value, dict) and (value.get("isok") is False or value.get("error")):
            raise ProviderError("providerRejected", "Shelly Cloud từ chối yêu cầu")
        return value

    @staticmethod
    def _device(value, device_id: str):
        entries = value if isinstance(value, list) else value.get("devices", []) if isinstance(value, dict) else []
        for entry in entries:
            if isinstance(entry, dict) and str(entry.get("id") or "").lower() == device_id.lower():
                return entry
        if isinstance(value, dict):
            return value
        return None

    def get_snapshot(self, binding: DeviceBinding) -> dict:
        raw = self._post(binding, "/v2/devices/api/get", {"ids": [binding.device_id], "select": ["status", "settings"]})
        device = self._device(raw, binding.device_id)
        if not isinstance(device, dict) or str(device.get("id") or "").lower() != binding.device_id.lower():
            raise ProviderError("deviceNotFound", "Không xác minh được thiết bị Shelly đã liên kết")
        if device.get("online") in (False, 0):
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

    def get_status(self, binding: DeviceBinding) -> DeviceStatus:
        snapshot = self.get_snapshot(binding)
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
        settings = snapshot.get("settings") or {}
        return DeviceStatus(
            online=True,
            relay=switch["output"],
            timer_remaining=timer,
            power_w=meter(switch["apower"], "W"),
            voltage_v=meter(switch["voltage"], "V"),
            current_a=meter(switch["current"], "A"),
            temperature_c=float(temperature["tC"]) if isinstance(temperature, dict) and temperature.get("tC") is not None else None,
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
        remaining = switch.get("timer_remaining")
        if remaining is not None:
            if not finite_number(remaining) or not 0 <= remaining <= 36000:
                raise ProviderError("malformedProviderResponse", "Timer Shelly không hợp lệ")
            return max(0, math.floor(remaining))
        started, duration = switch.get("timer_started_at"), switch.get("timer_duration")
        sys_status = (snapshot.get("status") or {}).get("sys") or {}
        device_now = sys_status.get("unixtime") if isinstance(sys_status, dict) else None
        now = self.clock()
        if not all(finite_number(value) for value in (started, duration, device_now, now)):
            return 0
        if (started < 1577836800 or not 0 < duration <= 36000 or
                abs(device_now - now) > 30 or started > device_now + 2):
            return 0
        # Use the later clock: skew or cached clock data must never prolong
        # the countdown. Expired timestamps resolve to zero, not full duration.
        return max(0, math.floor(min(duration, started + duration - max(now, device_now))))

    def turn_on_with_timer(self, binding: DeviceBinding, duration_seconds: int) -> None:
        self._post(binding, "/v2/devices/api/set/switch", {"id": binding.device_id, "channel": 0, "on": True, "toggle_after": int(duration_seconds)}, command=True)

    def turn_off(self, binding: DeviceBinding) -> None:
        self._post(binding, "/v2/devices/api/set/switch", {"id": binding.device_id, "channel": 0, "on": False}, command=True)

    def revoke(self, binding: DeviceBinding) -> None:
        return None

    def run_no_load_test(self, binding: DeviceBinding) -> dict:
        initial = self.get_status(binding)
        snapshot = self.get_snapshot(binding)
        settings = snapshot.get("settings") or {}
        switch_settings = settings.get("switch:0") if isinstance(settings, dict) else None
        if not isinstance(switch_settings, dict):
            raise ProviderError("safeBootUnverified", "Shelly Cloud không trả cấu hình Safe Boot")
        initial_state = str(switch_settings.get("initial_state") or "").lower()
        auto_on = switch_settings.get("auto_on")
        if initial.relay or initial_state != "off" or auto_on is not False:
            raise ProviderError("safeBootUnverified", "Relay phải OFF, Power-on default OFF và Auto ON tắt")
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
            self.turn_on_with_timer(binding, 5)
            for _ in range(5):
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
            for _ in range(8):
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
                off_verified = not self.get_status(binding).relay
        if not off_verified:
            raise ProviderError("relayUnverified", "Không xác minh được relay OFF sau kiểm tra")
        return {"identityVerified": True, "powerMeterVerified": True, "safeBootVerified": True, "noLoadTestVerified": on_observed and timer_observed and timer_auto_off_observed and off_verified, "initialState": initial_state, "autoOn": auto_on, "relayOffVerified": off_verified}
