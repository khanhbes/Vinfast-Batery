"""Encrypted persistence for user-owned Direct Shelly credentials.

Firestore device documents intentionally remain readable metadata.  This
module keeps connection secrets in a backend-only collection encrypted at
rest, so changing phones never requires copying a Cloud key through a public
Firestore document.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


class ProfileVaultError(ValueError):
    pass


class ShellyProfileVault:
    key_version = "v1"

    def __init__(self, key: str | None = None):
        raw = (key or os.environ.get("SHELLY_PROFILE_MASTER_KEY", "")).strip()
        if not raw:
            # Development/test only. Production is required to set the key;
            # callers can inspect ``configured`` and refuse secret writes.
            self._key = None
            return
        try:
            decoded = base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4))
        except (ValueError, TypeError) as exc:
            raise ProfileVaultError("SHELLY_PROFILE_MASTER_KEY phải là base64 URL-safe") from exc
        if len(decoded) != 32:
            raise ProfileVaultError("SHELLY_PROFILE_MASTER_KEY phải giải mã thành 32 bytes")
        self._key = decoded

    @property
    def configured(self) -> bool:
        return self._key is not None

    @staticmethod
    def document_id(uid: str, device_id: str) -> str:
        return hashlib.sha256(f"{uid}:{device_id}".encode("utf-8")).hexdigest()

    def encrypt(self, uid: str, device_id: str, payload: dict) -> dict:
        if not self._key:
            raise ProfileVaultError("Vault cấu hình Shelly chưa được cấu hình trên server")
        nonce = os.urandom(12)
        aad = f"{uid}:{device_id}:{self.key_version}".encode("utf-8")
        encrypted = AESGCM(self._key).encrypt(
            nonce, json.dumps(payload, separators=(",", ":")).encode("utf-8"), aad
        )
        return {
            "keyVersion": self.key_version,
            "nonce": base64.urlsafe_b64encode(nonce).decode("ascii"),
            "ciphertext": base64.urlsafe_b64encode(encrypted).decode("ascii"),
        }

    def decrypt(self, uid: str, device_id: str, record: dict) -> dict:
        if not self._key:
            raise ProfileVaultError("Vault cấu hình Shelly chưa được cấu hình trên server")
        if record.get("keyVersion") != self.key_version:
            raise ProfileVaultError("Phiên bản khóa vault Shelly không được hỗ trợ")
        try:
            nonce = base64.urlsafe_b64decode(str(record["nonce"]))
            ciphertext = base64.urlsafe_b64decode(str(record["ciphertext"]))
            aad = f"{uid}:{device_id}:{self.key_version}".encode("utf-8")
            value = AESGCM(self._key).decrypt(nonce, ciphertext, aad)
            decoded = json.loads(value.decode("utf-8"))
        except Exception as exc:  # Never include encrypted content in errors.
            raise ProfileVaultError("Không thể giải mã cấu hình Shelly") from exc
        if not isinstance(decoded, dict):
            raise ProfileVaultError("Dữ liệu vault Shelly không hợp lệ")
        return decoded
