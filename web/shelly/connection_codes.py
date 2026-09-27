"""Connection code system for Shelly device pairing.

Admin generates a short alphanumeric code linked to a Shelly device profile.
Users who cannot discover the device via LAN or Cloud can redeem the code
to receive a ready-made ShellyConnectionProfile.
"""
from __future__ import annotations

import secrets
import string
import hashlib
import threading
from datetime import datetime, timezone, timedelta
from dataclasses import dataclass, field, asdict
from typing import Any


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _iso(value: datetime | None) -> str | None:
    return value.astimezone(timezone.utc).isoformat() if value else None


def _generate_code(length: int = 6) -> str:
    """Generate a short uppercase alphanumeric code (no ambiguous chars)."""
    alphabet = string.ascii_uppercase.replace("O", "").replace("I", "")
    alphabet += string.digits.replace("0", "").replace("1", "")
    return "".join(secrets.choice(alphabet) for _ in range(length))


@dataclass
class ShellyConnectionCode:
    """A pairing code that maps to a Shelly device config."""
    code: str
    device_id: str
    device_name: str
    model: str
    cloud_host: str
    cloud_auth_key: str
    lan_address: str | None = None
    local_password: str | None = None
    created_by: str = ""
    created_at: datetime = field(default_factory=_utcnow)
    expires_at: datetime | None = None
    max_redemptions: int = 1
    redemption_count: int = 0
    is_revoked: bool = False
    note: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "code": self.code,
            "deviceId": self.device_id,
            "deviceName": self.device_name,
            "model": self.model,
            "cloudHost": self.cloud_host,
            "cloudAuthKey": self.cloud_auth_key,
            "lanAddress": self.lan_address,
            "localPassword": self.local_password,
            "createdBy": self.created_by,
            "createdAt": _iso(self.created_at),
            "expiresAt": _iso(self.expires_at),
            "maxRedemptions": self.max_redemptions,
            "redemptionCount": self.redemption_count,
            "isRevoked": self.is_revoked,
            "note": self.note,
        }

    def to_public_dict(self) -> dict[str, Any]:
        """Safe representation without secrets — for admin list views."""
        return {
            "code": self.code,
            "deviceId": self.device_id,
            "deviceName": self.device_name,
            "model": self.model,
            "cloudHost": self.cloud_host,
            "hasCloudAuthKey": bool(self.cloud_auth_key),
            "lanAddress": self.lan_address,
            "hasLocalPassword": bool(self.local_password),
            "createdBy": self.created_by,
            "createdAt": _iso(self.created_at),
            "expiresAt": _iso(self.expires_at),
            "maxRedemptions": self.max_redemptions,
            "redemptionCount": self.redemption_count,
            "isRevoked": self.is_revoked,
            "note": self.note,
            "isExpired": self.is_expired,
            "isUsable": self.is_usable,
        }

    @property
    def is_expired(self) -> bool:
        if self.expires_at is None:
            return False
        return _utcnow() > self.expires_at

    @property
    def is_usable(self) -> bool:
        return (
            not self.is_revoked
            and not self.is_expired
            and self.redemption_count < self.max_redemptions
        )

    def to_profile_dict(self) -> dict[str, Any]:
        """Returns a ShellyConnectionProfile-compatible dict for the mobile app."""
        return {
            "cloudHost": self.cloud_host,
            "cloudAuthKey": self.cloud_auth_key,
            "deviceId": self.device_id,
            "deviceName": self.device_name,
            "model": self.model,
            "lanAddress": self.lan_address,
            "localUsername": "admin",
            "localPassword": self.local_password,
        }

    @staticmethod
    def from_dict(data: dict) -> ShellyConnectionCode:
        from datetime import datetime
        def _parse_dt(val):
            if val is None:
                return None
            if isinstance(val, datetime):
                return val
            try:
                return datetime.fromisoformat(str(val).replace("Z", "+00:00"))
            except (ValueError, TypeError):
                return None

        return ShellyConnectionCode(
            code=str(data.get("code") or ""),
            device_id=str(data.get("deviceId") or ""),
            device_name=str(data.get("deviceName") or "Shelly"),
            model=str(data.get("model") or ""),
            cloud_host=str(data.get("cloudHost") or ""),
            cloud_auth_key=str(data.get("cloudAuthKey") or ""),
            lan_address=data.get("lanAddress"),
            local_password=data.get("localPassword"),
            created_by=str(data.get("createdBy") or ""),
            created_at=_parse_dt(data.get("createdAt")) or _utcnow(),
            expires_at=_parse_dt(data.get("expiresAt")),
            max_redemptions=1,
            redemption_count=int(data.get("redemptionCount") or 0),
            is_revoked=bool(data.get("isRevoked")),
            note=str(data.get("note") or ""),
        )


class ConnectionCodeStore:
    """In-memory + Firestore store for connection codes."""

    def __init__(self, firestore_db=None):
        self.db = firestore_db
        from .profile_vault import ShellyProfileVault
        self._vault = ShellyProfileVault()
        self._codes: dict[str, ShellyConnectionCode] = {}
        self._devices: dict[str, dict] = {}
        self._redemptions: list[dict] = []
        self._lock = threading.RLock()

    @staticmethod
    def _admin_vault_uid() -> str:
        return "__shelly_admin_inventory__"

    def _persist_secrets(self, device_id: str, cloud_host: str, cloud_auth_key: str,
                         lan_address: str | None, local_password: str | None) -> None:
        if not self.db:
            return
        if not self._vault.configured:
            raise ValueError("Shelly profile vault must be configured before storing pairing credentials")
        uid = self._admin_vault_uid()
        encrypted = self._vault.encrypt(uid, device_id, {
            "cloudHost": cloud_host,
            "cloudAuthKey": cloud_auth_key,
            "lanAddress": lan_address or "",
            "localPassword": local_password or "",
        })
        self.db.collection("ShellyCredentialVault").document(
            self._vault.document_id(uid, device_id)
        ).set({"ownerUid": uid, "deviceId": device_id, **encrypted}, merge=True)

    def _scrub_legacy_secrets(self, reference, data: dict, device_id: str) -> dict:
        cloud_key = str(data.get("cloudAuthKey") or "")
        local_password = str(data.get("localPassword") or "")
        if not cloud_key and not local_password:
            return data
        if self._vault.configured:
            self._persist_secrets(
                device_id,
                str(data.get("cloudHost") or ""),
                cloud_key,
                data.get("lanAddress"),
                local_password or None,
            )
        # Remove any legacy plaintext even if migration is unavailable. A
        # missing vault must fail pairing closed rather than expose secrets.
        from firebase_admin import firestore as admin_firestore
        reference.set({
            "hasCloudAuthKey": bool(cloud_key or data.get("hasCloudAuthKey")),
            "hasLocalPassword": bool(local_password or data.get("hasLocalPassword")),
            "cloudAuthKey": admin_firestore.DELETE_FIELD,
            "localPassword": admin_firestore.DELETE_FIELD,
        }, merge=True)
        return {**data, "hasCloudAuthKey": bool(cloud_key or data.get("hasCloudAuthKey")),
                "hasLocalPassword": bool(local_password or data.get("hasLocalPassword")),
                "cloudAuthKey": "", "localPassword": None}

    def _hydrate_secrets(self, entry: ShellyConnectionCode) -> ShellyConnectionCode:
        if entry.cloud_auth_key or not self.db or not self._vault.configured:
            return entry
        secrets = self.device_secrets(entry.device_id)
        entry.cloud_host = str(secrets.get("cloudHost") or entry.cloud_host)
        entry.cloud_auth_key = str(secrets.get("cloudAuthKey") or "")
        entry.lan_address = str(secrets.get("lanAddress") or "") or None
        entry.local_password = str(secrets.get("localPassword") or "") or None
        return entry

    def device_secrets(self, device_id: str) -> dict:
        if not self.db:
            entry = next((item for item in sorted(
                self._codes.values(), key=lambda item: item.created_at, reverse=True
            ) if item.device_id == device_id), None)
            return ({"cloudHost": entry.cloud_host, "cloudAuthKey": entry.cloud_auth_key,
                     "lanAddress": entry.lan_address, "localPassword": entry.local_password}
                    if entry else {})
        if not self._vault.configured:
            return {}
        uid = self._admin_vault_uid()
        snapshot = self.db.collection("ShellyCredentialVault").document(
            self._vault.document_id(uid, device_id)
        ).get()
        if not snapshot.exists:
            return {}
        record = snapshot.to_dict() or {}
        if record.get("ownerUid") != uid:
            return {}
        try:
            return self._vault.decrypt(uid, device_id, record)
        except Exception:
            return {}

    @property
    def _collection(self):
        if not self.db:
            return None
        return self.db.collection("shellyConnectionCodes")

    @property
    def _inventory_collection(self):
        if not self.db:
            return None
        return self.db.collection("shellyInventory")

    def save_device(
        self,
        *,
        device_id: str,
        device_name: str,
        model: str,
        cloud_host: str,
        cloud_auth_key: str = "",
        lan_address: str | None = None,
        local_password: str | None = None,
        note: str = "",
        created_by: str = "",
    ) -> dict:
        device_id = str(device_id or "").strip()
        record = {
            "deviceId": device_id,
            "displayName": str(device_name or "").strip() or "Shelly",
            "model": str(model or "").strip() or "S3PL-00112EU",
            "cloudHost": str(cloud_host or "").strip(),
            "hasCloudAuthKey": bool(str(cloud_auth_key or "").strip()),
            "lanAddress": str(lan_address).strip() if lan_address else None,
            "hasLocalPassword": bool(str(local_password or "").strip()),
            "note": str(note or "").strip(),
            "createdBy": str(created_by or ""),
            "updatedAt": _iso(_utcnow()),
            "online": True,
        }
        self._persist_secrets(
            device_id, record["cloudHost"], str(cloud_auth_key or "").strip(),
            record["lanAddress"], str(local_password).strip() if local_password else None,
        )
        self._devices[device_id] = record
        if self._inventory_collection is not None:
            self._inventory_collection.document(device_id).set(record)
        return record

    def save_device_and_generate_code(
        self,
        *,
        device_id: str,
        device_name: str,
        model: str,
        cloud_host: str,
        cloud_auth_key: str = "",
        lan_address: str | None = None,
        local_password: str | None = None,
        note: str = "",
        created_by: str = "",
        expires_hours: int = 720,
        max_redemptions: int = 1,
    ) -> tuple[dict, ShellyConnectionCode]:
        dev = self.save_device(
            device_id=device_id,
            device_name=device_name,
            model=model,
            cloud_host=cloud_host,
            cloud_auth_key=cloud_auth_key,
            lan_address=lan_address,
            local_password=local_password,
            note=note,
            created_by=created_by,
        )
        code_entry = self.generate(
            device_id=device_id,
            device_name=device_name,
            model=model,
            cloud_host=cloud_host,
            cloud_auth_key=cloud_auth_key,
            lan_address=lan_address,
            local_password=local_password,
            created_by=created_by,
            expires_hours=expires_hours,
            max_redemptions=max_redemptions,
            note=note,
        )
        return dev, code_entry

    def delete_device(self, device_id: str) -> bool:
        device_id = str(device_id or "").strip()
        removed = self._devices.pop(device_id, None)
        if self._inventory_collection is not None:
            self._inventory_collection.document(device_id).delete()
            if self._vault.configured:
                uid = self._admin_vault_uid()
                self.db.collection("ShellyCredentialVault").document(
                    self._vault.document_id(uid, device_id)
                ).delete()
        # Revoke active codes for this device
        for code_entry in list(self._codes.values()):
            if code_entry.device_id == device_id and not code_entry.is_revoked:
                code_entry.is_revoked = True
                if self._collection is not None:
                    try:
                        self._collection.document(code_entry.code).update({"isRevoked": True})
                    except Exception:
                        pass
        return removed is not None or bool(self._inventory_collection)

    def generate(
        self,
        *,
        device_id: str,
        device_name: str,
        model: str,
        cloud_host: str,
        cloud_auth_key: str,
        lan_address: str | None = None,
        local_password: str | None = None,
        created_by: str,
        expires_hours: int | None = 720,  # 30 days
        expires_at: datetime | None = None,
        max_redemptions: int = 1,
        note: str = "",
    ) -> ShellyConnectionCode:
        code = _generate_code(6)
        # Ensure uniqueness
        attempts = 0
        while code in self._codes and attempts < 20:
            code = _generate_code(6)
            attempts += 1

        exp = expires_at
        if exp is None and expires_hours is not None:
            exp = _utcnow() + timedelta(hours=expires_hours)

        entry = ShellyConnectionCode(
            code=code,
            device_id=device_id,
            device_name=device_name,
            model=model,
            cloud_host=cloud_host,
            cloud_auth_key=cloud_auth_key,
            lan_address=lan_address,
            local_password=local_password,
            created_by=created_by,
            expires_at=exp,
            max_redemptions=max_redemptions,
            note=note,
        )
        self._codes[code] = entry
        if self._collection is not None:
            self._persist_secrets(device_id, entry.cloud_host, entry.cloud_auth_key,
                                  entry.lan_address, entry.local_password)
            safe_entry = entry.to_dict()
            safe_entry.pop("cloudAuthKey", None)
            safe_entry.pop("localPassword", None)
            self._collection.document(code).set(safe_entry)
        return entry

    def list_all(self) -> list[ShellyConnectionCode]:
        if self.db and not self._codes:
            for snapshot in self._collection.stream():
                data = snapshot.to_dict() or {}
                data = self._scrub_legacy_secrets(snapshot.reference, data, str(data.get("deviceId") or ""))
                entry = self._hydrate_secrets(ShellyConnectionCode.from_dict(data))
                self._codes[entry.code] = entry
        return sorted(self._codes.values(), key=lambda c: c.created_at, reverse=True)

    def get(self, code: str) -> ShellyConnectionCode | None:
        normalized = code.strip().upper()
        if normalized in self._codes:
            return self._codes[normalized]
        if self._collection is not None:
            doc = self._collection.document(normalized).get()
            if doc.exists:
                data = doc.to_dict() or {}
                data = self._scrub_legacy_secrets(doc.reference, data, str(data.get("deviceId") or ""))
                entry = self._hydrate_secrets(ShellyConnectionCode.from_dict(data))
                self._codes[normalized] = entry
                return entry
        return None

    def redeem(self, code: str, uid: str) -> tuple[ShellyConnectionCode | None, str | None]:
        """Attempt to redeem a code. Returns (entry, error_message)."""
        entry = self.get(code.strip().upper())
        if entry is None:
            return None, "Mã kết nối không tồn tại"
        if entry.is_revoked:
            return None, "Mã kết nối đã bị thu hồi"
        if entry.is_expired:
            return None, "Mã kết nối đã hết hạn"
        if entry.redemption_count >= entry.max_redemptions:
            return None, "Mã kết nối đã sử dụng hết số lần cho phép"

        entry.redemption_count += 1
        self._codes[entry.code] = entry
        self._redemptions.append({
            "code": entry.code,
            "uid": uid,
            "redeemedAt": _iso(_utcnow()),
        })

        if self._collection is not None:
            self._collection.document(entry.code).update({
                "redemptionCount": entry.redemption_count,
            })
            self.db.collection("shellyCodeRedemptions").add({
                "code": entry.code,
                "uid": uid,
                "redeemedAt": _utcnow(),
            })

        return entry, None

    def redeem_atomic(self, code: str, uid: str) -> tuple[ShellyConnectionCode | None, str | None]:
        """Single-use redemption with transaction-backed retry for the same account."""
        normalized = str(code or "").strip().upper()
        if len(normalized) != 6:
            return None, "Mã kết nối phải có đúng 6 ký tự"
        cached = self.get(normalized)
        if cached is None:
            return None, "Mã kết nối không tồn tại"
        if self._collection is None:
            with self._lock:
                prior = next((item for item in self._redemptions if item["code"] == normalized), None)
                if prior:
                    return (cached, None) if prior["uid"] == uid else (None, "Mã kết nối đã được sử dụng")
                if cached.is_revoked or cached.is_expired:
                    return None, "Mã kết nối không còn hiệu lực"
                cached.max_redemptions = 1
                cached.redemption_count = 1
                self._codes[normalized] = cached
                self._redemptions.append({"code": normalized, "uid": uid, "redeemedAt": _iso(_utcnow())})
                return cached, None
        try:
            from google.cloud import firestore
            code_ref = self._collection.document(normalized)
            receipt_ref = self.db.collection("shellyCodeRedemptions").document(
                hashlib.sha256(f"{normalized}|{uid}".encode("utf-8")).hexdigest()
            )
            transaction = self.db.transaction()

            @firestore.transactional
            def redeem_in_transaction(txn):
                code_snapshot = code_ref.get(transaction=txn)
                receipt_snapshot = receipt_ref.get(transaction=txn)
                data = code_snapshot.to_dict() or {} if code_snapshot.exists else None
                if data is None:
                    return "missing"
                if receipt_snapshot.exists:
                    return "replay" if (receipt_snapshot.to_dict() or {}).get("uid") == uid else "used"
                expires = data.get("expiresAt")
                if isinstance(expires, str):
                    try:
                        expires = datetime.fromisoformat(expires.replace("Z", "+00:00"))
                    except ValueError:
                        expires = None
                if data.get("isRevoked") or (expires is not None and expires < _utcnow()):
                    return "unavailable"
                if int(data.get("redemptionCount") or 0) >= 1:
                    return "used"
                txn.update(code_ref, {"redemptionCount": 1, "maxRedemptions": 1, "redeemedByUid": uid, "redeemedAt": _utcnow()})
                txn.set(receipt_ref, {"code": normalized, "uid": uid, "redeemedAt": _utcnow()})
                return "ok"

            outcome = redeem_in_transaction(transaction)
            if outcome not in ("ok", "replay"):
                return None, "Mã kết nối đã được sử dụng hoặc không còn hiệu lực"
            cached.redemption_count = 1
            cached.max_redemptions = 1
            self._codes[normalized] = cached
            return cached, None
        except Exception:
            return None, "Không thể xác minh mã kết nối lúc này"

    def revoke(self, code: str) -> bool:
        entry = self.get(code.strip().upper())
        if entry is None:
            return False
        entry.is_revoked = True
        self._codes[entry.code] = entry
        if self._collection is not None:
            self._collection.document(entry.code).update({"isRevoked": True})
        return True

    def list_devices(self) -> list[dict]:
        """List all known Shelly devices with their latest pairing codes."""
        if self._inventory_collection is not None:
            try:
                for doc in self._inventory_collection.stream():
                    data = doc.to_dict() or {}
                    dev_id = str(data.get("deviceId") or doc.id)
                    data = self._scrub_legacy_secrets(doc.reference, data, dev_id)
                    if dev_id and dev_id not in self._devices:
                        self._devices[dev_id] = data
            except Exception:
                pass

        # Stream codes to populate in-memory map
        self.list_all()

        devices: dict[str, dict] = {}

        # 1. Add all devices from inventory / in-memory store
        for dev_id, data in self._devices.items():
            devices[dev_id] = {
                "deviceId": dev_id,
                "displayName": str(data.get("displayName") or "Shelly"),
                "model": str(data.get("model") or "S3PL-00112EU"),
                "cloudHost": str(data.get("cloudHost") or ""),
                "hasCloudAuthKey": bool(data.get("hasCloudAuthKey") or data.get("cloudAuthKey")),
                "lanAddress": data.get("lanAddress"),
                "hasLocalPassword": bool(data.get("hasLocalPassword") or data.get("localPassword")),
                "note": str(data.get("note") or ""),
                "online": bool(data.get("online", True)),
                "updatedAt": data.get("updatedAt"),
                "source": "inventory",
            }

        # 2. Add devices from user bindings
        if self.db:
            try:
                for user_doc in self.db.collection("users").stream():
                    uid = user_doc.id
                    for dev_doc in self.db.collection("users").document(uid).collection("shellyDevices").stream():
                        data = dev_doc.to_dict() or {}
                        dev_id = str(data.get("deviceId") or dev_doc.id)
                        if dev_id not in devices:
                            devices[dev_id] = {
                                "deviceId": dev_id,
                                "displayName": str(data.get("displayName") or "Shelly"),
                                "model": str(data.get("model") or "unknown"),
                                "provider": str(data.get("provider") or ""),
                                "online": bool(data.get("online")),
                                "powerMeterVerified": bool(data.get("powerMeterVerified")),
                                "ownerUid": uid,
                                "connectionMode": str(data.get("connectionMode") or ""),
                                "vehicleId": data.get("vehicleId"),
                                "source": "binding",
                            }
            except Exception:
                pass

        # 3. Add devices from generated codes
        for code_entry in self._codes.values():
            dev_id = code_entry.device_id
            if dev_id not in devices:
                devices[dev_id] = {
                    "deviceId": dev_id,
                    "displayName": code_entry.device_name,
                    "model": code_entry.model,
                    "cloudHost": code_entry.cloud_host,
                    "hasCloudAuthKey": bool(code_entry.cloud_auth_key),
                    "lanAddress": code_entry.lan_address,
                    "hasLocalPassword": bool(code_entry.local_password),
                    "note": code_entry.note,
                    "online": True,
                    "source": "code",
                }

        # 4. Attach active code and code history to each device
        for dev_id, dev_info in devices.items():
            device_codes = [c for c in self._codes.values() if c.device_id == dev_id]
            device_codes.sort(key=lambda c: c.created_at, reverse=True)
            active_code = next((c for c in device_codes if c.is_usable), None)
            latest_code = device_codes[0] if device_codes else None

            code_to_show = active_code or latest_code
            dev_info["latestCode"] = code_to_show.code if code_to_show else None
            dev_info["activeCodeEntry"] = code_to_show.to_public_dict() if code_to_show else None
            dev_info["allCodes"] = [c.code for c in device_codes]
            dev_info["totalCodesCount"] = len(device_codes)
            dev_info["hasUsableCode"] = active_code is not None

        return list(devices.values())
