from __future__ import annotations

import os
import time
from urllib.parse import urlparse

import requests

from ..models import DeviceBinding, DeviceStatus
from ..rate_limiter import PerDeviceRateLimiter
from .base import ProviderError


def _allowed_host(raw: str) -> str:
    value = raw.strip().rstrip("/")
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.hostname or not (
        parsed.hostname == "shelly.cloud" or parsed.hostname.endswith(".shelly.cloud")
    ):
        raise ProviderError("invalidProviderConfig", "SHELLY_LEGACY_HOST không hợp lệ")
    if parsed.path not in ("", "/") or parsed.query or parsed.fragment:
        raise ProviderError("invalidProviderConfig", "Shelly host không được chứa path/query")
    return value


def _find_switch(value):
    if isinstance(value, dict):
        direct = value.get("switch:0")
        if isinstance(direct, dict):
            return direct
        if isinstance(value.get("output"), bool):
            return value
        for child in value.values():
            found = _find_switch(child)
            if found is not None:
                return found
    if isinstance(value, list):
        for child in value:
            found = _find_switch(child)
            if found is not None:
                return found
    return None


class LegacyCloudControlProvider:
    """Single-account pilot provider; secrets remain server-side in env vars."""

    name = "legacy"
    supports_status = True
    supports_manual_off = True
    supports_manual_on = True
    supports_device_timer = True

    def __init__(self, host: str | None = None, auth_key: str | None = None, session=None, limiter=None):
        self.host = _allowed_host(host or os.environ.get("SHELLY_LEGACY_HOST", ""))
        self._auth_key = (auth_key or os.environ.get("SHELLY_LEGACY_AUTH_KEY", "")).strip()
        if not self._auth_key:
            raise ProviderError("invalidProviderConfig", "Thiếu SHELLY_LEGACY_AUTH_KEY")
        self._http = session or requests.Session()
        self._limiter = limiter or PerDeviceRateLimiter()

    def _post(self, binding: DeviceBinding, path: str, payload: dict) -> dict:
        def send():
            try:
                response = self._http.post(
                    f"{self.host}{path}",
                    params={"auth_key": self._auth_key},
                    json=payload,
                    timeout=5,
                )
            except requests.RequestException as exc:
                raise ProviderError("deviceOffline", "Shelly Cloud không phản hồi", True) from exc
            if response.status_code in (401, 403):
                raise ProviderError("needsReauthentication", "Shelly Cloud key đã hết hiệu lực")
            if response.status_code == 429:
                raise ProviderError("cloudRateLimited", "Shelly Cloud đang giới hạn request", True)
            if not 200 <= response.status_code < 300:
                raise ProviderError("deviceOffline", "Shelly Cloud không điều khiển được thiết bị", True)
            try:
                data = response.json()
            except ValueError as exc:
                raise ProviderError("malformedProviderResponse", "Shelly Cloud trả dữ liệu lỗi") from exc
            if isinstance(data, dict) and (data.get("isok") is False or data.get("error")):
                raise ProviderError("providerRejected", "Shelly Cloud từ chối yêu cầu")
            # Cloud Control v2 get returns a top-level list of Device State
            # objects. Preserve it under a neutral key for the recursive
            # switch parser; control commands commonly return an object.
            return {"devices": data} if isinstance(data, list) else data

        return self._limiter.run(binding.device_id, send)

    def list_devices(self, uid: str) -> list[DeviceBinding]:
        return []

    def get_status(self, binding: DeviceBinding) -> DeviceStatus:
        data = self._post(binding, "/v2/devices/api/get", {
            "ids": [binding.device_id],
            "select": ["status", "settings"],
        })
        switch = _find_switch(data)
        if not switch:
            devices = data.get("devices") if isinstance(data, dict) else None
            if isinstance(devices, list) and any(item.get("online") in (0, False) for item in devices if isinstance(item, dict)):
                raise ProviderError("deviceOffline", "Shelly đang offline trên Cloud", True)
            raise ProviderError("malformedProviderResponse", "Không có switch:0 trong status")
        energy = switch.get("aenergy") or {}
        temperature = switch.get("temperature")
        timer_remaining = switch.get("timer_remaining")
        if timer_remaining is None and switch.get("timer_started_at") is not None and switch.get("timer_duration") is not None:
            timer_remaining = max(0, float(switch["timer_duration"]) - (time.time() - float(switch["timer_started_at"])))
        return DeviceStatus(
            online=True,
            relay=bool(switch.get("output")),
            timer_remaining=max(0, int(float(timer_remaining or 0))),
            power_w=float(switch.get("apower") or 0),
            voltage_v=float(switch.get("voltage") or 0),
            current_a=float(switch.get("current") or 0),
            temperature_c=float(temperature.get("tC")) if isinstance(temperature, dict) and temperature.get("tC") is not None else None,
            energy_wh=float(energy.get("total") or 0),
            device_id=binding.device_id,
        )

    def turn_on_with_timer(self, binding: DeviceBinding, duration_seconds: int) -> None:
        self._post(binding, "/v2/devices/api/set/switch", {
            "id": binding.device_id,
            "channel": 0,
            "on": True,
            "toggle_after": duration_seconds,
        })

    def turn_off(self, binding: DeviceBinding) -> None:
        self._post(binding, "/v2/devices/api/set/switch", {
            "id": binding.device_id,
            "channel": 0,
            "on": False,
        })

    def revoke(self, binding: DeviceBinding) -> None:
        return None
