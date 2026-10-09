"""Versioned server evidence. Never persist credentials or raw Cloud payloads."""
from __future__ import annotations

import hashlib
import json
from urllib.parse import urlparse

FINGERPRINT_VERSION = 1


def cloud_safety_fingerprint(device_id: str, host: str, key: str, snapshot: dict) -> str:
    from .providers.base import ProviderError
    if (str(snapshot.get("id") or "").lower() != device_id.lower()
            or snapshot.get("code") != "S3PL-00112EU"
            or snapshot.get("gen") != "G2" or snapshot.get("type") != "relay"):
        raise ProviderError("unsupportedDevice", "Chưa xác minh được đúng Shelly Plug S Gen3")
    settings = snapshot.get("settings")
    switch = settings.get("switch:0") if isinstance(settings, dict) else None
    if (not isinstance(switch, dict) or switch.get("initial_state") != "off"
            or switch.get("auto_on") is not False):
        raise ProviderError("safeBootUnverified", "Hãy đặt Power-on default OFF và tắt Auto ON")
    parsed = urlparse(host)
    canonical = {
        "version": FINGERPRINT_VERSION,
        "deviceId": device_id.lower(), "model": "S3PL-00112EU",
        "cloudProtocolGeneration": "G2", "hardwareGeneration": 3,
        "cloudHost": "https://" + str(parsed.hostname or "").lower(),
        # Digest is an internal ingredient only, not returned separately.
        "credentialDigest": hashlib.sha256(key.encode("utf-8")).hexdigest(),
        "switchConfig": switch,
    }
    try:
        encoded = json.dumps(canonical, sort_keys=True, separators=(",", ":"),
                             ensure_ascii=True, allow_nan=False).encode("utf-8")
    except (ValueError, TypeError) as error:
        raise ProviderError("safeBootUnverified", "Cấu hình an toàn không hợp lệ") from error
    return hashlib.sha256(encoded).hexdigest()
