from __future__ import annotations

import hashlib
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

    def __init__(self, repository, session=None, sleeper=time.sleep):
        self.repository = repository
        self.http = session or requests.Session()
        self.sleep = sleeper

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

    def _post(self, binding: DeviceBinding, path: str, payload: dict) -> object:
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
        if not 200 <= response.status_code < 300:
            raise ProviderError("providerRejected", f"Shelly Cloud từ chối yêu cầu ({response.status_code})", response.status_code >= 500)
        try:
            value = response.json()
        except ValueError as exc:
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
        energy = switch.get("aenergy") or {}
        # Never infer an active countdown from a configured duration: that
        # value can remain after expiry. Only a live remaining-time field is
        # acceptable as evidence for an armed safety timer.
        timer = switch.get("timer_remaining")
        if timer is None:
            timer = 0
        temperature = switch.get("temperature") or {}
        settings = snapshot.get("settings") or {}
        return DeviceStatus(
            online=True,
            relay=switch.get("output") is True,
            timer_remaining=max(0, int(float(timer or 0))),
            power_w=float(switch.get("apower") or 0),
            voltage_v=float(switch.get("voltage") or 0),
            current_a=float(switch.get("current") or 0),
            temperature_c=float(temperature["tC"]) if isinstance(temperature, dict) and temperature.get("tC") is not None else None,
            energy_wh=float(energy.get("total") or 0),
            device_id=binding.device_id,
        )

    def turn_on_with_timer(self, binding: DeviceBinding, duration_seconds: int) -> None:
        self._post(binding, "/v2/devices/api/set/switch", {"id": binding.device_id, "channel": 0, "on": True, "toggle_after": int(duration_seconds)})

    def turn_off(self, binding: DeviceBinding) -> None:
        self._post(binding, "/v2/devices/api/set/switch", {"id": binding.device_id, "channel": 0, "on": False})

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
        on_observed = False
        timer_observed = False
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
            if on_status.power_w > 5 or on_status.current_a > .1:
                raise ProviderError("unexpectedLoad", "Có tải điện trong lúc kiểm tra không tải")
            self.sleep(5.5)
        finally:
            try:
                self.turn_off(binding)
            finally:
                off_verified = not self.get_status(binding).relay
        if not off_verified:
            raise ProviderError("relayUnverified", "Không xác minh được relay OFF sau kiểm tra")
        return {"identityVerified": True, "powerMeterVerified": True, "safeBootVerified": True, "noLoadTestVerified": on_observed and timer_observed and off_verified, "initialState": initial_state, "autoOn": auto_on, "relayOffVerified": off_verified}
