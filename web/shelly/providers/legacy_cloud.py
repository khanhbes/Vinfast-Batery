from __future__ import annotations

import os
import time
import hashlib
from urllib.parse import urlparse

import requests

from ..models import DeviceBinding, DeviceStatus
from ..rate_limiter import PerDeviceRateLimiter
from .base import ProviderError
from .vault_cloud import VaultCloudControlProvider


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


class LegacyCloudControlProvider(VaultCloudControlProvider):
    """Single-account pilot provider; secrets remain server-side in env vars."""

    name = "legacy"
    supports_status = True
    supports_manual_off = True
    # Env-backed legacy credentials have no cross-worker authorization/limiter
    # contract. Retain read/OFF recovery, never energize through this adapter.
    supports_manual_on = False
    supports_device_timer = True

    def __init__(self, host: str | None = None, auth_key: str | None = None, session=None, limiter=None):
        self.host = _allowed_host(host or os.environ.get("SHELLY_LEGACY_HOST", ""))
        self._auth_key = (auth_key or os.environ.get("SHELLY_LEGACY_AUTH_KEY", "")).strip()
        if not self._auth_key:
            raise ProviderError("invalidProviderConfig", "Thiếu SHELLY_LEGACY_AUTH_KEY")
        self._http = session or requests.Session()
        self._limiter = limiter or PerDeviceRateLimiter(interval_seconds=1.1)
        self.clock = time.time
        self._rate_key = hashlib.sha256(f"{self.host}|{self._auth_key}".encode()).hexdigest()

    def _post(self, binding: DeviceBinding, path: str, payload: dict) -> dict:
        def send():
            guard = getattr(self, "worker_lease_guard", None)
            if guard is not None:
                guard()
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
            if response.status_code != 200:
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

        return self._limiter.run(self._rate_key, send)

    def list_devices(self, uid: str) -> list[DeviceBinding]:
        return []

    def get_status(self, binding: DeviceBinding) -> DeviceStatus:
        # Exactly the same identity/relay/meter/timer checks as the vault path;
        # never synthesize OFF or zero readings from an incomplete payload.
        return super().get_status(binding)

    def turn_on_with_timer(self, binding: DeviceBinding, duration_seconds: int) -> None:
        raise ProviderError("legacyEnrollmentRequired", "Hãy kết nối Shelly qua mã quản trị trước khi bật sạc")

    def verify_control_readiness(self, binding: DeviceBinding) -> None:
        raise ProviderError("legacyEnrollmentRequired", "Hãy kết nối Shelly qua mã quản trị trước khi bật sạc")

    def turn_off(self, binding: DeviceBinding) -> None:
        self._post(binding, "/v2/devices/api/set/switch", {
            "id": binding.device_id,
            "channel": 0,
            "on": False,
        })

    def revoke(self, binding: DeviceBinding) -> None:
        return None
