from __future__ import annotations

import threading
import hashlib
from urllib.parse import urlparse
from datetime import datetime, timezone, timedelta

from .models import (
    ChargePreview,
    ChargingSession,
    DeviceBinding,
    EtaCandidate,
    PersonalChargingProfile,
    SmartChargeSafetyEvent,
)
from .profile_vault import ProfileVaultError, ShellyProfileVault


class SmartChargeRepository:
    """Firestore-backed repository with deterministic in-memory fallback."""

    def __init__(self, firestore_db=None):
        self.db = firestore_db
        self._lock = threading.RLock()
        self._bindings: dict[str, dict[str, DeviceBinding]] = {}
        self._previews: dict[str, dict[str, ChargePreview]] = {}
        self._sessions: dict[str, dict[str, ChargingSession]] = {}
        self._idempotency: dict[tuple[str, str], str] = {}
        self._consent: dict[str, tuple[str, datetime, bool]] = {}
        self._audits: list[dict] = []
        self._personal_profiles: dict[tuple[str, str], PersonalChargingProfile] = {}
        self._telemetry: dict[tuple[str, str], list[dict]] = {}
        self._vehicle_owners: dict[str, str] = {}
        self._archived_vehicles: set[tuple[str, str]] = set()
        # Include vehicle identity in the in-memory idempotency marker.  A
        # privacy erase for one vehicle must never reset/erase markers for a
        # different vehicle owned by the same account.
        self._processed_training_sessions: set[tuple[str, str, str]] = set()
        self._training_samples: dict[tuple[str, str], dict[str, dict]] = {}
        # Process-local guard for a physical Shelly shared by multiple
        # accounts. Firestore leases below cover multi-process deployments.
        self._device_leases: dict[str, tuple[str, str, datetime]] = {}
        self._last_history_skipped = 0
        self._profile_vault = ShellyProfileVault()
        self._synced_profiles: dict[tuple[str, str], dict] = {}
        self._profile_vault_records: dict[tuple[str, str], dict] = {}

    @property
    def profile_vault_configured(self) -> bool:
        return self._profile_vault.configured

    @property
    def last_history_skipped(self) -> int:
        """Count malformed legacy documents skipped by the last history read."""
        with self._lock:
            return self._last_history_skipped

    def register_vehicle_owner(self, uid: str, vehicle_id: str) -> None:
        """Deterministic test/dev registration; production reads Vehicles."""
        with self._lock:
            self._vehicle_owners[vehicle_id] = uid

    def set_vehicle_archived(self, uid: str, vehicle_id: str, archived: bool = True) -> None:
        with self._lock:
            key = (uid, vehicle_id)
            if archived:
                self._archived_vehicles.add(key)
            else:
                self._archived_vehicles.discard(key)

    def vehicle_for_owner(self, uid: str, vehicle_id: str) -> dict | None:
        if not vehicle_id or vehicle_id == "manual":
            return None
        if self.db:
            snapshot = self.db.collection("Vehicles").document(vehicle_id).get()
            data = snapshot.to_dict() or {} if snapshot.exists else {}
            if (data.get("ownerUid") != uid or data.get("isDeleted") is True or
                    data.get("isArchived") is True or data.get("archivedAt") is not None):
                return None
            result = {"vehicleId": vehicle_id, **data}
            capacity = result.get("nominalCapacityWh") or result.get("batteryCapacityWh") or result.get("batteryCapacity")
            model_id = result.get("vinfastModelId")
            try:
                capacity_value = float(capacity or 0)
            except (TypeError, ValueError):
                capacity_value = 0.0
            if capacity_value <= 0 and model_id:
                spec = self.db.collection("VinFastModelSpecs").document(str(model_id)).get()
                spec_data = spec.to_dict() or {} if spec.exists else {}
                capacity = spec_data.get("nominalCapacityWh")
                try:
                    capacity_value = float(capacity or 0)
                except (TypeError, ValueError):
                    capacity_value = 0.0
            if capacity_value > 0:
                result["nominalCapacityWh"] = capacity_value
            return result
        with self._lock:
            return (
                {"vehicleId": vehicle_id, "ownerUid": uid}
                if self._vehicle_owners.get(vehicle_id) == uid and
                (uid, vehicle_id) not in self._archived_vehicles
                else None
            )

    def save_binding(self, uid: str, binding: DeviceBinding) -> None:
        with self._lock:
            self._bindings.setdefault(uid, {})[binding.device_id] = binding
        if self.db:
            self.db.collection("users").document(uid).collection("shellyDevices").document(binding.device_id).set(binding.to_dict(), merge=True)

    def list_bindings(self, uid: str) -> list[DeviceBinding]:
        with self._lock:
            cached = list(self._bindings.get(uid, {}).values())
        if cached or not self.db:
            return cached
        for snapshot in self.db.collection("users").document(uid).collection("shellyDevices").stream():
            data = snapshot.to_dict() or {}
            binding = DeviceBinding(
                device_id=str(data.get("deviceId") or snapshot.id),
                display_name=str(data.get("displayName") or "Shelly sạc xe"),
                model=str(data.get("model") or "unknown"), generation=int(data.get("generation") or 3),
                provider=str(data.get("provider") or "integrator"),
                connection_mode=str(data.get("connectionMode") or "server_cloud"),
                permissions=list(data.get("permissions") or ["read", "control"]),
                online=bool(data.get("online")), power_meter_verified=bool(data.get("powerMeterVerified")),
                safe_boot_verified=bool(data.get("safeBootVerified")),
                no_load_test_verified=bool(data.get("noLoadTestVerified")),
                last_verified_at=_date(data.get("lastVerifiedAt")),
                revoked_at=_date(data.get("revokedAt")),
                created_at=_date(data.get("createdAt")) or datetime.now(timezone.utc),
                updated_at=_date(data.get("updatedAt")) or datetime.now(timezone.utc),
                vehicle_id=str(data.get("vehicleId")) if data.get("vehicleId") else None,
                shared=bool(data.get("shared")),
            )
            with self._lock:
                self._bindings.setdefault(uid, {})[binding.device_id] = binding
        with self._lock:
            return list(self._bindings.get(uid, {}).values())

    def get_binding(self, uid: str, vehicle_id: str | None = None) -> DeviceBinding | None:
        active = [item for item in self.list_bindings(uid) if item.revoked_at is None]
        if vehicle_id:
            matched = [item for item in active if item.vehicle_id == vehicle_id or item.shared]
            if matched:
                return matched[0]
            # A legacy unscoped binding is usable only while the account has
            # no explicit vehicle bindings. Once any binding is vehicle-bound,
            # never fall through to another vehicle's charger.
            legacy = [item for item in active if item.vehicle_id is None]
            # An unscoped legacy device may only be used transparently while
            # the account still has a single active vehicle. With multiple
            # vehicles, force explicit setup rather than guessing.
            if legacy and not any(item.vehicle_id for item in active) and not self.has_multiple_active_vehicles(uid):
                return legacy[0]
            return None
        return active[0] if active else None

    def has_multiple_active_vehicles(self, uid: str) -> bool:
        if self.db:
            try:
                count = 0
                for snapshot in self.db.collection("Vehicles").where("ownerUid", "==", uid).stream():
                    data = snapshot.to_dict() or {}
                    if data.get("isDeleted") is True or data.get("isArchived") is True or data.get("archivedAt") is not None:
                        continue
                    count += 1
                    if count > 1:
                        return True
                return False
            except Exception:
                # A failed lookup must not weaken isolation; require explicit
                # binding setup until vehicle ownership can be established.
                return True
        with self._lock:
            count = sum(
                1 for vehicle_id, owner in self._vehicle_owners.items()
                if owner == uid and (uid, vehicle_id) not in self._archived_vehicles
            )
        return count > 1

    def migrate_single_vehicle_binding(self, uid: str) -> DeviceBinding | None:
        """Non-destructively bind a legacy single device to a single vehicle.

        V3 accounts stored a Shelly binding without ``vehicle_id``.  We only
        migrate when both sides are unambiguous; otherwise the caller must
        show the device/vehicle selector and no cross-vehicle guess is made.
        """
        active = [item for item in self.list_bindings(uid) if item.revoked_at is None]
        legacy = [item for item in active if item.vehicle_id is None]
        if len(active) != 1 or len(legacy) != 1:
            return None
        vehicle_ids: list[str] = []
        if self.db:
            try:
                snapshots = self.db.collection("Vehicles").where("ownerUid", "==", uid).stream()
                for snapshot in snapshots:
                    data = snapshot.to_dict() or {}
                    if data.get("isDeleted") is True or data.get("isArchived") is True or data.get("archivedAt") is not None:
                        continue
                    vehicle_ids.append(str(snapshot.id))
            except Exception:
                return None
        else:
            with self._lock:
                vehicle_ids = [
                    vehicle_id for vehicle_id, owner in self._vehicle_owners.items()
                    if owner == uid and (uid, vehicle_id) not in self._archived_vehicles
                ]
        if len(vehicle_ids) != 1:
            return None
        binding = legacy[0]
        binding.vehicle_id = vehicle_ids[0]
        binding.updated_at = datetime.now(timezone.utc)
        self.save_binding(uid, binding)
        return binding

    def revoke_binding(self, uid: str, device_id: str, when: datetime) -> None:
        binding = self._bindings.get(uid, {}).get(device_id)
        if binding:
            binding.revoked_at = when
            binding.updated_at = when
            self.save_binding(uid, binding)

    # ── Direct profile sync vault ─────────────────────────────────────
    # The users/{uid}/shellyDevices document deliberately holds metadata only.
    # Raw Cloud/LAN credentials are encrypted in ShellyCredentialVault, which
    # has no client Firestore rule and is available through authenticated API
    # restore only.

    @staticmethod
    def _profile_metadata(profile: dict, *, revision: int, now: datetime) -> dict:
        verification = profile.get("verification") if isinstance(profile.get("verification"), dict) else {}
        return {
            "deviceId": str(profile.get("deviceId") or "").strip(),
            "displayName": str(profile.get("deviceName") or "Shelly sạc xe").strip(),
            "model": str(profile.get("model") or "S3PL-00112EU").strip(),
            "firmware": str(profile.get("firmware") or "").strip(),
            "vehicleId": str(profile.get("vehicleId") or "").strip() or None,
            "connectionMode": "advanced_direct",
            "provider": "direct_cloud_lan",
            "revision": revision,
            "source": str(profile.get("source") or "android").strip() or "android",
            "credentialRef": "vault",
            "hasCredentialVault": True,
            "cloudVerified": verification.get("cloudVerified") is True,
            "lanVerified": verification.get("lanVerified") is True,
            "powerMeterVerified": verification.get("powerMeterVerified") is True,
            "safeBootVerified": verification.get("safeBootVerified") is True,
            "noLoadTestVerified": verification.get("noLoadTestVerified") is True,
            "verificationFingerprint": str(profile.get("verificationFingerprint") or ""),
            "verifiedAt": profile.get("verifiedAt") or now,
            "updatedAt": now,
            "revokedAt": None,
        }

    @staticmethod
    def _profile_secrets(profile: dict) -> dict:
        return {
            "cloudHost": str(profile.get("cloudHost") or "").strip(),
            "cloudAuthKey": str(profile.get("cloudAuthKey") or "").strip(),
            "lanAddress": str(profile.get("lanAddress") or "").strip(),
            "localUsername": str(profile.get("localUsername") or "admin").strip() or "admin",
            "localPassword": str(profile.get("localPassword") or ""),
        }

    @staticmethod
    def _valid_cloud_host(value: str) -> bool:
        parsed = urlparse(value)
        return bool(
            parsed.scheme == "https"
            and parsed.hostname
            and (parsed.hostname == "shelly.cloud" or parsed.hostname.endswith(".shelly.cloud"))
            and parsed.path in ("", "/")
            and not parsed.params
            and not parsed.query
            and not parsed.fragment
        )

    @staticmethod
    def _profile_is_verified(metadata: dict) -> bool:
        return bool(
            metadata.get("cloudVerified")
            and metadata.get("powerMeterVerified")
            and metadata.get("safeBootVerified")
            and metadata.get("noLoadTestVerified")
        )

    def _profile_doc(self, uid: str, device_id: str):
        return self.db.collection("users").document(uid).collection("shellyDevices").document(device_id)

    def list_synced_profiles(self, uid: str, vehicle_id: str | None = None) -> list[dict]:
        values: list[dict] = []
        if self.db:
            for snapshot in self.db.collection("users").document(uid).collection("shellyDevices").stream():
                data = snapshot.to_dict() or {}
                if data.get("connectionMode") != "advanced_direct":
                    continue
                if data.get("revokedAt") is not None:
                    continue
                if vehicle_id and data.get("vehicleId") not in (vehicle_id, None, ""):
                    continue
                value = dict(data)
                value.setdefault("deviceId", snapshot.id)
                values.append(value)
        else:
            with self._lock:
                values = [
                    dict(value) for (owner, _device), value in self._synced_profiles.items()
                    if owner == uid and value.get("revokedAt") is None and
                    (not vehicle_id or value.get("vehicleId") in (vehicle_id, None, ""))
                ]
        values.sort(key=lambda value: (self._profile_is_verified(value), value.get("revision", 0), str(value.get("updatedAt") or "")), reverse=True)
        return values

    def migrate_legacy_profile_secrets(self, uid: str) -> int:
        """Move pre-vault secrets out of legacy device metadata once.

        The migration only runs with a configured vault and never reports the
        secret values. Documents missing a key remain metadata-only.
        """
        if not self.db or not self._profile_vault.configured:
            return 0
        migrated = 0
        for snapshot in self.db.collection("users").document(uid).collection("shellyDevices").stream():
            data = snapshot.to_dict() or {}
            key = str(data.get("cloudAuthKey") or data.get("authKey") or data.get("apiKey") or "").strip()
            host = str(data.get("cloudHost") or data.get("host") or data.get("server") or "").strip()
            if not key or not host:
                if data.get("connectionMode") == "advanced_direct" and not data.get("hasCredentialVault"):
                    snapshot.reference.set({"metadataOnly": True}, merge=True)
                continue
            profile = {
                "deviceId": str(data.get("deviceId") or snapshot.id),
                "deviceName": data.get("displayName") or data.get("deviceName") or data.get("name"),
                "model": data.get("model"), "vehicleId": data.get("vehicleId"),
                "cloudHost": host, "cloudAuthKey": key,
                "lanAddress": data.get("lanAddress") or data.get("ip"),
                "localUsername": data.get("localUsername") or "admin",
                "localPassword": data.get("localPassword") or "",
                "source": "legacy_migration",
                "verification": {
                    "cloudVerified": data.get("cloudVerified") is True,
                    "lanVerified": data.get("lanVerified") is True,
                    "powerMeterVerified": data.get("powerMeterVerified") is True,
                    "safeBootVerified": data.get("safeBootVerified") is True,
                    "noLoadTestVerified": data.get("noLoadTestVerified") is True,
                },
            }
            try:
                self.save_synced_profile(uid, profile, expected_revision=int(data.get("revision") or 0))
                from firebase_admin import firestore as admin_firestore
                snapshot.reference.set({
                    "cloudAuthKey": admin_firestore.DELETE_FIELD,
                    "authKey": admin_firestore.DELETE_FIELD,
                    "apiKey": admin_firestore.DELETE_FIELD,
                    "localPassword": admin_firestore.DELETE_FIELD,
                    "host": admin_firestore.DELETE_FIELD,
                    "server": admin_firestore.DELETE_FIELD,
                    "ip": admin_firestore.DELETE_FIELD,
                    "metadataOnly": False,
                }, merge=True)
                migrated += 1
            except (ProfileVaultError, ValueError, PermissionError, RuntimeError):
                # Leave the document untouched if it cannot be migrated.
                continue
        return migrated

    def save_synced_profile(self, uid: str, profile: dict, expected_revision: int | None = None) -> dict:
        if not self._profile_vault.configured:
            raise ProfileVaultError("Server chưa cấu hình SHELLY_PROFILE_MASTER_KEY")
        device_id = str(profile.get("deviceId") or "").strip()
        secrets = self._profile_secrets(profile)
        if not device_id or not secrets["cloudHost"] or not secrets["cloudAuthKey"]:
            raise ValueError("Thiếu Device ID, Cloud host hoặc Authorization Cloud Key")
        if not self._valid_cloud_host(secrets["cloudHost"]):
            raise ValueError("Cloud host phải dùng HTTPS và thuộc miền shelly.cloud")
        vehicle_id = str(profile.get("vehicleId") or "").strip()
        if vehicle_id and self.vehicle_for_owner(uid, vehicle_id) is None:
            raise PermissionError("Xe không thuộc tài khoản này")
        old: dict = {}
        if self.db:
            snapshot = self._profile_doc(uid, device_id).get()
            old = snapshot.to_dict() or {} if snapshot.exists else {}
        else:
            with self._lock:
                old = dict(self._synced_profiles.get((uid, device_id), {}))
        old_revision = int(old.get("revision") or 0)
        if expected_revision is not None and expected_revision != old_revision:
            raise RuntimeError("profileRevisionConflict")
        now = datetime.now(timezone.utc)
        metadata = self._profile_metadata(profile, revision=old_revision + 1, now=now)
        encrypted = self._profile_vault.encrypt(uid, device_id, secrets)
        vault_data = {
            "ownerUid": uid,
            "deviceId": device_id,
            "revision": metadata["revision"],
            "updatedAt": now,
            **encrypted,
        }
        if self.db:
            self.db.collection("ShellyCredentialVault").document(
                self._profile_vault.document_id(uid, device_id)
            ).set(vault_data, merge=True)
            self._profile_doc(uid, device_id).set(metadata, merge=True)
        with self._lock:
            self._synced_profiles[(uid, device_id)] = dict(metadata)
            self._profile_vault_records[(uid, device_id)] = dict(vault_data)
        self.append_audit(uid, "shelly_profile_saved", device_id=device_id, vehicle_id=vehicle_id, revision=metadata["revision"])
        return metadata

    def restore_synced_profile(self, uid: str, device_id: str) -> dict | None:
        profiles = [item for item in self.list_synced_profiles(uid) if item.get("deviceId") == device_id]
        if not profiles:
            return None
        metadata = profiles[0]
        if self.db:
            snapshot = self.db.collection("ShellyCredentialVault").document(
                self._profile_vault.document_id(uid, device_id)
            ).get()
            if not snapshot.exists:
                return None
            vault = snapshot.to_dict() or {}
        else:
            with self._lock:
                vault = dict(self._profile_vault_records.get((uid, device_id), {}))
            if not vault:
                return None
        if vault.get("ownerUid") != uid:
            return None
        secrets = self._profile_vault.decrypt(uid, device_id, vault)
        self.append_audit(uid, "shelly_profile_restored", device_id=device_id, revision=metadata.get("revision"))
        return {**metadata, **secrets}

    def resolve_synced_profile(self, uid: str, vehicle_id: str | None = None) -> dict | None:
        profiles = self.list_synced_profiles(uid, vehicle_id)
        return profiles[0] if profiles else None

    def verify_synced_profile(self, uid: str, device_id: str, verification: dict) -> dict | None:
        profiles = [item for item in self.list_synced_profiles(uid) if item.get("deviceId") == device_id]
        if not profiles:
            return None
        current = profiles[0]
        revision = int(current.get("revision") or 0) + 1
        now = datetime.now(timezone.utc)
        update = {
            "revision": revision,
            "cloudVerified": verification.get("cloudVerified") is True,
            "lanVerified": verification.get("lanVerified") is True,
            "powerMeterVerified": verification.get("powerMeterVerified") is True,
            "safeBootVerified": verification.get("safeBootVerified") is True,
            "noLoadTestVerified": verification.get("noLoadTestVerified") is True,
            "verificationFingerprint": str(verification.get("verificationFingerprint") or ""),
            "verifiedAt": now,
            "updatedAt": now,
        }
        if self.db:
            self._profile_doc(uid, device_id).set(update, merge=True)
        with self._lock:
            self._synced_profiles[(uid, device_id)] = {**current, **update}
        return {**current, **update}

    def revoke_synced_profile(self, uid: str, device_id: str) -> bool:
        profiles = [item for item in self.list_synced_profiles(uid) if item.get("deviceId") == device_id]
        if not profiles:
            return False
        now = datetime.now(timezone.utc)
        if self.db:
            self._profile_doc(uid, device_id).set({"revokedAt": now, "updatedAt": now}, merge=True)
            self.db.collection("ShellyCredentialVault").document(
                self._profile_vault.document_id(uid, device_id)
            ).delete()
        with self._lock:
            self._synced_profiles.pop((uid, device_id), None)
            self._profile_vault_records.pop((uid, device_id), None)
        self.append_audit(uid, "shelly_profile_revoked", device_id=device_id)
        return True

    def save_preview(self, uid: str, preview: ChargePreview) -> None:
        with self._lock:
            self._previews.setdefault(uid, {})[preview.preview_id] = preview

    def get_preview(self, uid: str, preview_id: str) -> ChargePreview | None:
        with self._lock:
            return self._previews.get(uid, {}).get(preview_id)

    def save_session(self, uid: str, session: ChargingSession) -> None:
        with self._lock:
            self._sessions.setdefault(uid, {})[session.session_id] = session
            self._idempotency[(uid, session.idempotency_key)] = session.session_id
            if session.state not in ("arming", "active"):
                lease = self._device_leases.get(session.device_id)
                if lease and lease[0] == uid and lease[1] == session.session_id:
                    self._device_leases.pop(session.device_id, None)
        if self.db:
            payload = session.to_dict()
            payload["idempotency_key"] = session.idempotency_key
            self.db.collection("users").document(uid).collection("smartChargingSessions").document(session.session_id).set(payload, merge=True)

    def claim_device_session(self, uid: str, device_id: str, session_id: str) -> bool:
        """Atomically reserve a physical Shelly for one active session.

        The in-memory lease protects the normal single-process deployment. A
        short Firestore lease additionally prevents two app/server workers
        from arming the same shared device at the same time.
        """
        now = datetime.now(timezone.utc)
        expires = now.replace(microsecond=0)
        from datetime import timedelta
        expires = expires + timedelta(hours=12)
        with self._lock:
            existing = self._device_leases.get(device_id)
            if existing and existing[2] > now and existing[:2] != (uid, session_id):
                return False
            self._device_leases[device_id] = (uid, session_id, expires)
        if not self.db:
            return True
        ref = self.db.collection("shellyDeviceLocks").document(device_id)
        try:
            snapshot = ref.get()
            data = snapshot.to_dict() or {} if snapshot.exists else {}
            lock_expiry = data.get("expiresAt")
            if hasattr(lock_expiry, "to_datetime"):
                lock_expiry = lock_expiry.to_datetime()
            if isinstance(lock_expiry, datetime) and lock_expiry.tzinfo is None:
                lock_expiry = lock_expiry.replace(tzinfo=timezone.utc)
            if snapshot.exists and lock_expiry and lock_expiry > now and (
                data.get("ownerUid") != uid or data.get("sessionId") != session_id
            ):
                with self._lock:
                    self._device_leases.pop(device_id, None)
                return False
            ref.set({"ownerUid": uid, "sessionId": session_id, "deviceId": device_id,
                     "expiresAt": expires, "updatedAt": now}, merge=True)
            return True
        except Exception:
            # Do not weaken the safety gate when the central lock cannot be
            # read or written. The caller must fail closed.
            with self._lock:
                self._device_leases.pop(device_id, None)
            return False

    def release_device_session(self, uid: str, device_id: str, session_id: str) -> None:
        with self._lock:
            lease = self._device_leases.get(device_id)
            if lease and lease[:2] == (uid, session_id):
                self._device_leases.pop(device_id, None)
        if self.db:
            ref = self.db.collection("shellyDeviceLocks").document(device_id)
            try:
                data = ref.get().to_dict() or {}
                if data.get("ownerUid") == uid and data.get("sessionId") == session_id:
                    ref.delete()
            except Exception:
                pass

    def upsert_charge_log(self, uid: str, session: ChargingSession) -> None:
        """Upsert the same ChargeLogs document while active and when terminal."""
        if not self.db:
            return
        payload = {
            "id": session.session_id,
            "sessionId": session.session_id,
            "vehicleId": session.vehicle_id,
            "ownerUid": uid,
            "startTime": session.created_at,
            "endTime": session.stopped_at if session.state in ("completed", "cancelled", "interrupted", "failed") else None,
            "startBatteryPercent": round(session.start_soc),
            "endBatteryPercent": round(session.estimated_soc if session.estimated_soc is not None else session.target_soc),
            "targetBatteryPercent": round(session.target_soc),
            "source": "shelly_smart_charging",
            "shellyDeviceId": session.device_id,
            "controlTransport": session.transport,
            "plannedStopAt": session.effective_stop_at,
            "actualStopAt": session.stopped_at or session.updated_at,
            "stopReason": session.stop_reason,
            "sessionState": session.state,
            "isActive": session.state in ("arming", "active"),
            "energyWh": session.energy_used_wh,
            "predictionSource": session.prediction_source,
            "predictionConfidence": session.prediction_confidence,
            "predictionModelKey": session.model_key,
            "predictionModelVersion": session.model_version,
            "predictionRuntimeHealth": session.runtime_health,
            "predictionWarnings": session.prediction_warnings,
            "fallbackReason": session.fallback_reason,
            "predictedDurationSeconds": session.predicted_duration_seconds,
            "predictionAnalyzedAt": session.prediction_analyzed_at,
            "socEstimated": True,
            "etaCandidates": [item.to_dict() for item in session.eta_candidates],
            "etaFusionReason": session.fusion_reason,
            "personalProfileVersion": session.profile_version,
            "personalAdapterVersion": session.adapter_version,
            "safetyEvents": [item.to_dict() for item in session.safety_events],
            "safetyPolicyVersion": session.safety_policy_version,
            "actualEndSoc": session.actual_end_soc,
            "trainingEligible": session.training_eligible,
            "telemetryCoverage": session.telemetry_coverage,
            "personalizationStage": session.personalization_stage,
            "baseAiMinutes": session.base_ai_minutes,
            "physicsMinutes": session.physics_minutes,
            "personalMinutes": session.personal_minutes,
            "finalMinutes": session.final_minutes,
            "fusionWeights": session.fusion_weights,
            "effectiveCapacityWh": session.effective_capacity_wh,
            "nominalCapacityWh": session.nominal_capacity_wh,
            "stateOfHealth": session.state_of_health,
            "shellyTemperatureC": session.shelly_temperature_c,
            "batteryTemperatureC": session.battery_temperature_c,
            "averagePowerW": session.average_power_w,
            "peakPowerW": session.peak_power_w,
            "averageVoltageV": session.average_voltage_v,
            "averageCurrentA": session.average_current_a,
            "userStopReason": session.user_stop_reason,
            "personalAiTrainingState": session.training_state,
            "personalAiTrainingReason": session.training_reason,
            "isDeleted": False,
            "updatedAt": datetime.now(timezone.utc),
        }
        self.db.collection("ChargeLogs").document(session.session_id).set(payload, merge=True)

    def get_by_idempotency(self, uid: str, key: str) -> ChargingSession | None:
        with self._lock:
            session_id = self._idempotency.get((uid, key))
            cached = self._sessions.get(uid, {}).get(session_id) if session_id else None
        if cached or not self.db:
            return cached
        matches = self.db.collection("users").document(uid).collection("smartChargingSessions").where("idempotency_key", "==", key).limit(1).stream()
        for snapshot in matches:
            session = _session(snapshot.to_dict() or {})
            self.save_session(uid, session)
            return session
        return None

    def current_session(self, uid: str, vehicle_id: str | None = None, device_id: str | None = None) -> ChargingSession | None:
        active = [s for s in self.history(uid, 100) if s.state in ("arming", "active")]
        if vehicle_id:
            active = [s for s in active if s.vehicle_id == vehicle_id]
        if device_id:
            active = [s for s in active if s.device_id == device_id]
        return active[0] if active else None

    def active_sessions(self, uid: str) -> list[ChargingSession]:
        """Return every active vehicle session, not only the legacy first one."""
        return [s for s in self.history(uid, 100)
                if s.state in ("arming", "active")]

    def get_session(self, uid: str, session_id: str) -> ChargingSession | None:
        with self._lock:
            cached = self._sessions.get(uid, {}).get(session_id)
        if cached or not self.db:
            return cached
        snapshot = (self.db.collection("users").document(uid)
                    .collection("smartChargingSessions").document(session_id).get())
        if not snapshot.exists:
            return None
        session = _session(snapshot.to_dict() or {})
        if session.owner_uid not in (None, uid):
            return None
        with self._lock:
            self._sessions.setdefault(uid, {})[session_id] = session
        return session

    def erase_session(self, uid: str, session_id: str) -> bool:
        """Privacy erase a terminal session and its raw telemetry only."""
        session = self.get_session(uid, session_id)
        log_data: dict = {}
        log = None
        if self.db:
            log = self.db.collection("ChargeLogs").document(session_id)
            snapshot = log.get()
            if snapshot.exists:
                log_data = snapshot.to_dict() or {}
                if log_data.get("ownerUid") != uid:
                    return False
        if session is None and not log_data:
            return False
        state = session.state if session is not None else str(
            log_data.get("sessionState") or log_data.get("status") or ""
        )
        if state in ("arming", "active"):
            return False
        vehicle_id = session.vehicle_id if session is not None else str(
            log_data.get("vehicleId") or ""
        )
        with self._lock:
            self._sessions.get(uid, {}).pop(session_id, None)
            self._telemetry.pop((uid, session_id), None)
            if session is not None:
                self._idempotency.pop((uid, session.idempotency_key), None)
            if vehicle_id:
                self._training_samples.get((uid, vehicle_id), {}).pop(
                    session_id, None
                )
                self._processed_training_sessions.discard(
                    (uid, vehicle_id, session_id)
                )
        if not self.db:
            return True
        nested = (self.db.collection("users").document(uid)
                  .collection("smartChargingSessions").document(session_id))
        nested.delete()
        for child in log.collection("smartChargeTelemetry").stream():
            child.reference.delete()
        for child in log.collection("safetyEvents").stream():
            child.reference.delete()
        (self.db.collection("users").document(uid)
         .collection("chargingTrainingSamples").document(session_id).delete())
        log.delete()
        return True

    def hide_session(self, uid: str, session_id: str) -> ChargingSession | None:
        """Hide a terminal session from normal history without destroying it."""
        session = self.get_session(uid, session_id)
        if session is None or session.state in ("arming", "active"):
            return None
        when = datetime.now(timezone.utc)
        session.hidden_at = when
        session.updated_at = when
        self.save_session(uid, session)
        if self.db:
            self.db.collection("ChargeLogs").document(session_id).set(
                {"hiddenByUserAt": when, "isDeleted": False, "updatedAt": when},
                merge=True,
            )
        return session

    def history(self, uid: str, limit: int = 20) -> list[ChargingSession]:
        with self._lock:
            self._last_history_skipped = 0
        with self._lock:
            values = list(self._sessions.get(uid, {}).values())
        if not values and self.db:
            # ChargeLogs is the canonical durable history. Read it first so
            # terminal summaries restored from older sessions remain visible
            # even when their nested runtime session document is missing.
            values = self._charge_log_history(uid, limit)
        if not values and self.db:
            snapshots = self.db.collection("users").document(uid).collection("smartChargingSessions").order_by("created_at", direction="DESCENDING").limit(limit).stream()
            values = []
            skipped = 0
            for item in snapshots:
                try:
                    values.append(_session(item.to_dict() or {}))
                except (KeyError, TypeError, ValueError):
                    # A malformed legacy document must not hide valid history.
                    skipped += 1
            with self._lock:
                self._last_history_skipped = skipped
            with self._lock:
                for session in values:
                    self._sessions.setdefault(uid, {})[session.session_id] = session
                    self._idempotency[(uid, session.idempotency_key)] = session.session_id
        values = [item for item in values if item.hidden_at is None]
        return sorted(values, key=lambda item: item.created_at, reverse=True)[:limit]

    def _charge_log_history(self, uid: str, limit: int = 100) -> list[ChargingSession]:
        if not self.db:
            return []
        try:
            snapshots = (self.db.collection("ChargeLogs")
                         .where("ownerUid", "==", uid)
                         .where("source", "==", "shelly_smart_charging")
                         .order_by("startTime", direction="DESCENDING")
                         .limit(limit).stream())
            values: list[ChargingSession] = []
            skipped = 0
            for snapshot in snapshots:
                data = snapshot.to_dict() or {}
                # Older ChargeLogs did not persist isDeleted.  Filtering this
                # flag in Python keeps those historical summaries visible;
                # putting it in the Firestore query would silently exclude
                # every legacy document missing the field.
                if data.get("isDeleted") is True or data.get("hiddenByUserAt") is not None:
                    continue
                try:
                    values.append(_session_from_charge_log(data, snapshot.id, uid))
                except (KeyError, TypeError, ValueError):
                    skipped += 1
            with self._lock:
                self._last_history_skipped += skipped
                for session in values:
                    self._sessions.setdefault(uid, {})[session.session_id] = session
                    self._idempotency[(uid, session.idempotency_key)] = session.session_id
            return values
        except Exception:
            # Missing composite index or a temporary Firestore failure should
            # fall back to the nested runtime collection below.
            return []

    def history_page(
        self,
        uid: str,
        limit: int = 20,
        cursor: datetime | None = None,
        strategy: str | None = None,
        vehicle_id: str | None = None,
    ) -> tuple[list[ChargingSession], str | None]:
        limit = min(50, max(1, int(limit)))
        if self.db:
            # Query the canonical ChargeLogs collection. Runtime session
            # documents are retained as a compatibility fallback below.
            query = (self.db.collection("ChargeLogs")
                     .where("ownerUid", "==", uid)
                     .where("source", "==", "shelly_smart_charging")
                     .order_by("startTime", direction="DESCENDING"))
            # Apply filters before the Firestore limit so pagination cannot
            # discard valid records belonging to the requested vehicle or
            # strategy. Composite indexes are declared in firestore.indexes.
            if strategy:
                query = query.where("strategy", "==", strategy)
            if vehicle_id:
                query = query.where("vehicleId", "==", vehicle_id)
            if cursor is not None:
                query = query.where("startTime", "<", cursor)
            # Hidden records must be removed before slicing the page. Reading
            # the filtered query without a server limit avoids short pages when
            # older documents contain hidden_at; the result is still bounded by
            # the requested page below and preserves cursor correctness.
            from_charge_logs = True
            try:
                snapshots = list(query.stream())
            except Exception:
                # Keep V3 deployments working while the new ChargeLogs
                # composite index is being built.
                from_charge_logs = False
                query = (self.db.collection("users").document(uid)
                         .collection("smartChargingSessions")
                         .order_by("created_at", direction="DESCENDING"))
                if strategy:
                    query = query.where("strategy", "==", strategy)
                if vehicle_id:
                    query = query.where("vehicle_id", "==", vehicle_id)
                if cursor is not None:
                    query = query.where("created_at", "<", cursor)
                snapshots = list(query.stream())
            values = []
            skipped = 0
            for item in snapshots:
                try:
                    raw = item.to_dict() or {}
                    if raw.get("isDeleted") is True:
                        continue
                    values.append(
                        _session_from_charge_log(raw, item.id, uid)
                        if from_charge_logs else _session(raw)
                    )
                except (KeyError, TypeError, ValueError):
                    skipped += 1
            # During the V3→V4 migration there can be no canonical ChargeLog
            # yet while the nested runtime collection already contains valid
            # sessions.  Treat an empty canonical result as a compatibility
            # miss (without doing so for a non-empty canonical page), so an
            # empty/temporarily backfilled ChargeLogs collection cannot hide
            # existing charging history.
            if from_charge_logs and not values:
                try:
                    legacy_query = (self.db.collection("users").document(uid)
                                    .collection("smartChargingSessions")
                                    .order_by("created_at", direction="DESCENDING"))
                    if strategy:
                        legacy_query = legacy_query.where("strategy", "==", strategy)
                    if vehicle_id:
                        legacy_query = legacy_query.where("vehicle_id", "==", vehicle_id)
                    if cursor is not None:
                        legacy_query = legacy_query.where("created_at", "<", cursor)
                    for item in legacy_query.stream():
                        try:
                            values.append(_session(item.to_dict() or {}))
                        except (KeyError, TypeError, ValueError):
                            skipped += 1
                except Exception:
                    # Canonical history remains authoritative when the
                    # compatibility collection is unavailable.
                    pass
            with self._lock:
                self._last_history_skipped = skipped
            with self._lock:
                for session in values:
                    self._sessions.setdefault(uid, {})[session.session_id] = session
                    self._idempotency[(uid, session.idempotency_key)] = session.session_id
        else:
            with self._lock:
                values = list(self._sessions.get(uid, {}).values())
            values.sort(key=lambda item: item.created_at, reverse=True)
            if cursor is not None:
                values = [item for item in values if item.created_at < cursor]
            with self._lock:
                self._last_history_skipped = 0
        values = [item for item in values if item.hidden_at is None]
        if strategy:
            values = [item for item in values if item.strategy == strategy]
        if vehicle_id:
            values = [item for item in values if item.vehicle_id == vehicle_id]
        has_more = len(values) > limit
        page = values[:limit]
        next_cursor = page[-1].created_at.isoformat() if has_more and page else None
        return page, next_cursor

    def save_consent(self, state: str, uid: str, expires_at: datetime) -> None:
        with self._lock:
            self._consent[state] = (uid, expires_at, False)

    def consume_consent(self, state: str, now: datetime) -> str | None:
        with self._lock:
            item = self._consent.get(state)
            if not item or item[2] or item[1] <= now:
                return None
            self._consent[state] = (item[0], item[1], True)
            return item[0]

    def append_audit(self, uid: str, event: str, **details) -> None:
        record = {"uid": uid, "event": event, "created_at": datetime.now().astimezone().isoformat(), **details}
        with self._lock:
            self._audits.append(record)
        if self.db:
            self.db.collection("smartChargingAudit").add(record)

    def get_personal_profile(self, uid: str, vehicle_id: str) -> PersonalChargingProfile | None:
        """Profiles are always keyed by owner and vehicle; vehicle id alone is never trusted."""
        key = (uid, vehicle_id)
        with self._lock:
            cached = self._personal_profiles.get(key)
        if cached or not self.db:
            return cached
        snapshot = self.db.collection("AiVehicleProfiles").document(_profile_id(uid, vehicle_id)).get()
        if not snapshot.exists:
            # Non-destructive migration path for profiles written by V2.
            snapshot = (self.db.collection("users").document(uid)
                        .collection("personalChargingProfiles").document(vehicle_id).get())
        if not snapshot.exists:
            return None
        data = snapshot.to_dict() or {}
        if data.get("ownerUid") != uid:
            return None
        profile = _profile(uid, vehicle_id, data)
        with self._lock:
            self._personal_profiles[key] = profile
        return profile

    def save_personal_profile(self, profile: PersonalChargingProfile) -> None:
        key = (profile.owner_uid, profile.vehicle_id)
        with self._lock:
            self._personal_profiles[key] = profile
        if self.db:
            self.db.collection("AiVehicleProfiles").document(
                _profile_id(profile.owner_uid, profile.vehicle_id)
            ).set(profile.to_dict(), merge=True)

    def delete_personal_profile(self, uid: str, vehicle_id: str) -> None:
        with self._lock:
            self._personal_profiles.pop((uid, vehicle_id), None)
            self._training_samples.pop((uid, vehicle_id), None)
            # Training samples are privacy-scoped. Forget processed markers so
            # a future opt-in starts as a genuinely new profile.
            self._processed_training_sessions = {
                item for item in self._processed_training_sessions
                if not (item[0] == uid and item[1] == vehicle_id)
            }
        if self.db:
            root = self.db.collection("users").document(uid)
            self.db.collection("AiVehicleProfiles").document(_profile_id(uid, vehicle_id)).delete()
            root.collection("personalChargingProfiles").document(vehicle_id).delete()
            samples = root.collection("chargingTrainingSamples").where("vehicleId", "==", vehicle_id).stream()
            for sample in samples:
                sample.reference.delete()
            self.db.collection("personalChargingTrainingJobs").document(
                f"{uid}_{vehicle_id}"
            ).delete()

    def save_training_sample(self, uid: str, session: ChargingSession, payload: dict) -> None:
        if not self.db:
            with self._lock:
                self._processed_training_sessions.add((uid, session.vehicle_id, session.session_id))
            return
        value = dict(payload)
        value.update({
            "ownerUid": uid,
            "vehicleId": session.vehicle_id,
            "sessionId": session.session_id,
            "updatedAt": datetime.now(timezone.utc),
        })
        with self._lock:
            self._training_samples.setdefault((uid, session.vehicle_id), {}).setdefault(
                session.session_id, dict(value)
            )
        ref = (self.db.collection("users").document(uid)
               .collection("chargingTrainingSamples").document(session.session_id))
        # Training samples are immutable: duplicate ingestion is a no-op and
        # can never overwrite the original provenance/label.
        try:
            ref.create(value)
        except Exception as error:
            if "already exists" not in str(error).lower() and "already-exists" not in str(error).lower():
                raise
        # Mark only after Firestore accepted the immutable sample (or
        # confirmed it already exists). A transient write failure must remain
        # retryable instead of being mistaken for a processed session.
        with self._lock:
            self._processed_training_sessions.add((uid, session.vehicle_id, session.session_id))

    def training_samples(self, uid: str, vehicle_id: str) -> list[dict]:
        """Return immutable, owner/vehicle-scoped samples for candidate validation."""
        with self._lock:
            cached = list(self._training_samples.get((uid, vehicle_id), {}).values())
        if not self.db:
            return cached
        try:
            snapshots = (self.db.collection("users").document(uid)
                         .collection("chargingTrainingSamples")
                         .where("vehicleId", "==", vehicle_id).stream())
            values = []
            for snapshot in snapshots:
                data = snapshot.to_dict() or {}
                if data.get("ownerUid") != uid or data.get("vehicleId") != vehicle_id:
                    continue
                # Developers can exclude a bad label through Firebase Admin
                # without mutating the immutable raw measurement.
                if data.get("trainingExcluded") is True:
                    continue
                values.append(data)
            with self._lock:
                # Firestore is authoritative here. Rebuild the bucket so an
                # Admin-side trainingExcluded change takes effect without a
                # worker restart.
                bucket: dict[str, dict] = {}
                for value in values:
                    session_id = str(value.get("sessionId") or "")
                    if session_id:
                        bucket[session_id] = value
                self._training_samples[(uid, vehicle_id)] = bucket
                return list(bucket.values())
        except Exception:
            # Training is an optional background task; never block charging on
            # a temporary Firestore read failure.
            return cached

    def review_training_sample(
        self,
        uid: str,
        vehicle_id: str,
        session_id: str,
        *,
        training_excluded: bool,
        developer_note: str,
        duration_seconds_override: float | None,
        predicted_minutes_override: float | None,
        reviewed_by: str | None,
    ) -> dict | None:
        """Apply a tightly scoped developer training override.

        Raw device measurements remain immutable. Overrides are recorded next
        to the sample and only used by the training worker, preserving an
        auditable original record.
        """
        if not self.db:
            return None
        ref = (self.db.collection("users").document(uid)
               .collection("chargingTrainingSamples").document(session_id))
        snapshot = ref.get()
        if not snapshot.exists:
            return None
        data = snapshot.to_dict() or {}
        if data.get("ownerUid") != uid or data.get("vehicleId") != vehicle_id:
            return None
        update = {
            "trainingExcluded": bool(training_excluded),
            "developerNote": developer_note[:500],
            "trainingDurationSecondsOverride": duration_seconds_override,
            "trainingPredictedMinutesOverride": predicted_minutes_override,
            "trainingReviewedAt": datetime.now(timezone.utc),
            "trainingReviewedBy": reviewed_by or uid,
        }
        ref.set(update, merge=True)
        with self._lock:
            self._training_samples.pop((uid, vehicle_id), None)
        return {**data, **update}

    def training_sample_processed(
        self, uid: str, session_id: str, vehicle_id: str | None = None
    ) -> bool:
        with self._lock:
            if vehicle_id and (uid, vehicle_id, session_id) in self._processed_training_sessions:
                return True
        if not self.db:
            return False
        snapshot = (self.db.collection("users").document(uid)
                    .collection("chargingTrainingSamples").document(session_id).get())
        # The immutable sample document is the idempotency marker regardless
        # of whether its candidate was promoted, rejected, or used only for
        # power calibration. This prevents duplicate training after restart.
        processed = snapshot.exists
        if processed:
            with self._lock:
                self._processed_training_sessions.add((uid, vehicle_id or "", session_id))
        return processed

    def enqueue_personal_training(self, uid: str, vehicle_id: str, session_id: str) -> None:
        if not self.db:
            return
        self.db.collection("personalChargingTrainingJobs").document(f"{uid}_{vehicle_id}").set({
            "ownerUid": uid,
            "vehicleId": vehicle_id,
            "triggerSessionId": session_id,
            "state": "pending",
            "updatedAt": datetime.now(timezone.utc),
        }, merge=True)

    def save_telemetry(self, uid: str, session_id: str, point: dict) -> None:
        key = (uid, session_id)
        value = dict(point)
        value["ownerUid"] = uid
        with self._lock:
            self._telemetry.setdefault(key, []).append(value)
        if self.db:
            stamp = str(value.get("timestamp") or datetime.now(timezone.utc).isoformat())
            doc_id = stamp.replace(":", "-").replace(".", "-")
            (self.db.collection("ChargeLogs").document(session_id)
             .collection("smartChargeTelemetry").document(doc_id).set(value, merge=True))

    def telemetry(self, uid: str, session_id: str) -> list[dict]:
        with self._lock:
            cached = list(self._telemetry.get((uid, session_id), []))
        if cached or not self.db:
            return cached
        parent = self.db.collection("ChargeLogs").document(session_id).get()
        parent_data = parent.to_dict() or {}
        if not parent.exists or parent_data.get("ownerUid") != uid:
            return []
        values: list[dict] = []
        # Direct mode persists ten 30-second samples in a five-minute chunk
        # (`points`). Easy/Server and Direct must expose the same point-level
        # contract to charts and reconciliation. Keep supporting the older
        # flat-document format as a compatibility path.
        chunks = parent.reference.collection("smartChargeTelemetry").stream()
        for item in chunks:
            data = item.to_dict() or {}
            if data.get("ownerUid") not in (None, uid):
                continue
            if data.get("sessionId") not in (None, session_id):
                continue
            points = data.get("points")
            if isinstance(points, list):
                for point in points:
                    if not isinstance(point, dict):
                        continue
                    value = dict(point)
                    value.setdefault("ownerUid", uid)
                    value.setdefault("sessionId", session_id)
                    values.append(value)
            elif data:
                values.append(data)
        values.sort(key=lambda value: str(value.get("timestamp") or value.get("startedAt") or ""))
        return values


def _date(value):
    if hasattr(value, "to_datetime"):
        try:
            value = value.to_datetime()
        except Exception:
            return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    return None


def _required_date(data: dict, key: str) -> datetime:
    value = _date(data.get(key))
    if value is None:
        raise ValueError(f"invalid session date: {key}")
    return value


def _session(data: dict) -> ChargingSession:
    return ChargingSession(
        session_id=str(data["session_id"]), device_id=str(data["device_id"]), vehicle_id=str(data["vehicle_id"]),
        state=str(data["state"]), start_soc=float(data["start_soc"]), target_soc=float(data["target_soc"]),
        predicted_minutes=int(data["predicted_minutes"]), prediction_source=str(data.get("prediction_source") or "unknown"),
        predicted_duration_seconds=int(data.get("predicted_duration_seconds") or int(data["predicted_minutes"]) * 60),
        prediction_confidence=data.get("prediction_confidence"), created_at=_required_date(data, "created_at"), updated_at=_required_date(data, "updated_at"),
        ai_stop_at=_required_date(data, "ai_stop_at"), effective_stop_at=_required_date(data, "effective_stop_at"),
        absolute_safety_stop_at=_required_date(data, "absolute_safety_stop_at"), idempotency_key=str(data["idempotency_key"]),
        strategy=str(data.get("strategy") or "ai_target"),
        model_key=str(data.get("model_key") or "charging_time"),
        model_version=str(data.get("model_version") or "unknown"),
        runtime_health=str(data.get("runtime_health") or "unknown"),
        prediction_warnings=list(data.get("prediction_warnings") or []),
        fallback_reason=data.get("fallback_reason"),
        prediction_analyzed_at=_date(data.get("prediction_analyzed_at")),
        estimated_soc=data.get("estimated_soc"), baseline_energy_wh=data.get("baseline_energy_wh"), energy_used_wh=float(data.get("energy_used_wh") or 0),
        energy_quality=str(data.get("energy_quality") or "good"),
        relay_verified=bool(data.get("relay_verified")), timer_verified=bool(data.get("timer_verified")), transport=str(data.get("transport") or "shelly_cloud"),
        stopped_at=_date(data.get("stopped_at")), stop_reason=data.get("stop_reason"), version=int(data.get("version") or 1), last_error=data.get("last_error"),
        eta_candidates=[EtaCandidate(
            source=str(item.get("source") or "unknown"),
            duration_seconds=int(item.get("durationSeconds") or item.get("duration_seconds") or 0),
            weight=float(item.get("weight") or 0), confidence=float(item.get("confidence") or 0),
            available=bool(item.get("available", True)), reason=item.get("reason"),
        ) for item in (data.get("eta_candidates") or []) if isinstance(item, dict)],
        fusion_reason=str(data.get("fusion_reason") or "global_ai_only"),
        profile_version=data.get("profile_version"), adapter_version=data.get("adapter_version"),
        safety_events=[SmartChargeSafetyEvent(
            kind=str(item.get("kind") or "unknown"), severity=str(item.get("severity") or "warning"),
            message=str(item.get("message") or ""), observed_value=item.get("observedValue"),
            created_at=_date(item.get("createdAt")) or datetime.now(timezone.utc),
        ) for item in (data.get("safety_events") or []) if isinstance(item, dict)],
        actual_end_soc=data.get("actual_end_soc"), training_eligible=bool(data.get("training_eligible")),
        telemetry_coverage=float(data.get("telemetry_coverage") or 0),
        owner_uid=data.get("owner_uid"),
        personalization_stage=str(data.get("personalization_stage") or "base"),
        base_ai_minutes=data.get("base_ai_minutes"), physics_minutes=data.get("physics_minutes"),
        personal_minutes=data.get("personal_minutes"), final_minutes=data.get("final_minutes"),
        fusion_weights=dict(data.get("fusion_weights") or {}),
        effective_capacity_wh=data.get("effective_capacity_wh"), nominal_capacity_wh=data.get("nominal_capacity_wh"),
        state_of_health=data.get("state_of_health"), shelly_temperature_c=data.get("shelly_temperature_c"),
        battery_temperature_c=data.get("battery_temperature_c"), average_power_w=data.get("average_power_w"),
        peak_power_w=data.get("peak_power_w"), average_voltage_v=data.get("average_voltage_v"),
        average_current_a=data.get("average_current_a"), user_stop_reason=str(data.get("user_stop_reason") or "none"),
        training_state=str(data.get("personal_ai_training_state") or "pending"),
        training_reason=data.get("personal_ai_training_reason"),
        hidden_at=_date(data.get("hidden_at")),
        safety_policy_version=str(data.get("safety_policy_version") or "v4-default"),
    )


def _session_from_charge_log(data: dict, document_id: str, uid: str) -> ChargingSession:
    """Adapt a canonical ChargeLog/summary into the runtime session contract.

    Older restored logs may contain only the summary fields, while newer logs
    also embed ``smartChargingSession``. Prefer the embedded immutable session
    and fill missing values from the summary without inventing another vehicle.
    """
    embedded = data.get("smartChargingSession")
    if isinstance(embedded, dict):
        normalized = dict(embedded)
        normalized.setdefault("owner_uid", uid)
        normalized.setdefault("vehicle_id", data.get("vehicleId"))
        normalized.setdefault("session_id", data.get("sessionId") or document_id)
        try:
            return _session(normalized)
        except (KeyError, TypeError, ValueError):
            pass
    now = datetime.now(timezone.utc)
    created = _date(data.get("startTime")) or _date(data.get("createdAt")) or now
    updated = _date(data.get("updatedAt")) or _date(data.get("actualStopAt")) or created
    stopped = _date(data.get("actualStopAt")) or _date(data.get("endTime"))
    target = float(data.get("targetBatteryPercent") or data.get("targetSoc") or data.get("startBatteryPercent") or 0)
    start = float(data.get("startBatteryPercent") or data.get("startSoc") or 0)
    duration_seconds = int(data.get("predictedDurationSeconds") or
                           round(float(data.get("finalEtaMinutes") or data.get("predictedMinutes") or 1) * 60))
    duration_seconds = max(1, duration_seconds)
    state_value = str(data.get("sessionState") or data.get("status") or "completed")
    if state_value == "terminal":
        state_value = "completed"
    if state_value not in ("arming", "active", "completed", "cancelled", "interrupted", "failed"):
        state_value = "completed" if stopped else "active"
    planned = _date(data.get("plannedStopAt")) or created + timedelta(seconds=duration_seconds)
    absolute = created + timedelta(hours=10)
    return ChargingSession(
        session_id=str(data.get("sessionId") or document_id),
        device_id=str(data.get("shellyDeviceId") or data.get("deviceId") or "unknown"),
        vehicle_id=str(data.get("vehicleId") or ""), state=state_value,
        start_soc=start, target_soc=target,
        predicted_minutes=max(1, int(round(duration_seconds / 60))),
        predicted_duration_seconds=duration_seconds,
        prediction_source=str(data.get("predictionSource") or "unknown"),
        prediction_confidence=data.get("predictionConfidence"),
        created_at=created, updated_at=updated,
        ai_stop_at=planned, effective_stop_at=planned,
        absolute_safety_stop_at=absolute,
        idempotency_key=f"legacy-log-{data.get('sessionId') or document_id}",
        strategy=str(data.get("strategy") or "ai_target"),
        model_key=str(data.get("modelKey") or "charging_time"),
        model_version=str(data.get("modelVersion") or "unknown"),
        runtime_health=str(data.get("runtimeHealth") or "unknown"),
        prediction_warnings=list(data.get("predictionWarnings") or []),
        fallback_reason=data.get("fallbackReason"),
        prediction_analyzed_at=_date(data.get("predictionAnalyzedAt")),
        estimated_soc=data.get("estimatedEndSoc"),
        baseline_energy_wh=None,
        energy_used_wh=float(data.get("gridEnergyWh") or data.get("energyWh") or 0),
        energy_quality=str(data.get("energyQuality") or "partial"),
        relay_verified=bool(data.get("relayVerified") or data.get("relay_verified")),
        timer_verified=bool(data.get("timerVerified") or data.get("timer_verified")),
        transport=str(data.get("controlTransport") or data.get("transport") or "shelly_cloud"),
        stopped_at=stopped, stop_reason=data.get("stopReason"),
        version=int(data.get("version") or 1),
        eta_candidates=[EtaCandidate(
            source=str(item.get("source") or "unknown"),
            duration_seconds=int(item.get("durationSeconds") or item.get("duration_seconds") or 0),
            weight=float(item.get("weight") or 0), confidence=float(item.get("confidence") or 0),
            available=bool(item.get("available", True)), reason=item.get("reason"),
        ) for item in (data.get("etaCandidates") or []) if isinstance(item, dict)],
        fusion_reason=str(data.get("etaFusionReason") or "global_ai_only"),
        profile_version=data.get("personalProfileVersion"),
        adapter_version=data.get("personalAdapterVersion"),
        actual_end_soc=data.get("actualEndSoc"),
        training_eligible=bool(data.get("trainingEligible")),
        telemetry_coverage=float(data.get("telemetryCoverage") or 0),
        owner_uid=uid,
        personalization_stage=str(data.get("personalizationStage") or "base"),
        base_ai_minutes=data.get("baseAiMinutes"), physics_minutes=data.get("physicsMinutes"),
        personal_minutes=data.get("personalMinutes"), final_minutes=data.get("finalEtaMinutes"),
        fusion_weights=dict(data.get("fusionWeights") or {}),
        effective_capacity_wh=data.get("effectiveCapacityWh"), nominal_capacity_wh=data.get("nominalCapacityWh"),
        state_of_health=data.get("stateOfHealth"), shelly_temperature_c=data.get("shellyTemperatureC"),
        average_power_w=data.get("averagePowerW"), peak_power_w=data.get("peakPowerW"),
        average_voltage_v=data.get("averageVoltageV"), average_current_a=data.get("averageCurrentA"),
        user_stop_reason=str(data.get("userStopReason") or "none"),
        training_state=str(data.get("personalAiTrainingState") or "pending"),
        training_reason=data.get("personalAiTrainingReason"), hidden_at=_date(data.get("hiddenByUserAt")),
        safety_policy_version=str(data.get("safetyPolicyVersion") or "v4-default"),
    )


def _profile(uid: str, vehicle_id: str, data: dict) -> PersonalChargingProfile:
    correction = data.get("correction") if isinstance(data.get("correction"), dict) else {}
    quality = data.get("quality") if isinstance(data.get("quality"), dict) else {}
    return PersonalChargingProfile(
        owner_uid=uid, vehicle_id=vehicle_id,
        consent_enabled=bool(data.get("consentEnabled")),
        valid_sessions=int(data.get("validSessions") or 0),
        power_sessions=int(data.get("powerSessions") or 0),
        eta_bias_ratio=float(data.get("etaBiasRatio") or 0),
        median_power_w=(float(data["medianPowerW"]) if data.get("medianPowerW") is not None else None),
        efficiency=float(data.get("efficiency") or 0.90),
        usable_capacity_wh=(float(data["usableCapacityWh"]) if data.get("usableCapacityWh") is not None else None),
        validation_mape=(float(data["validationMape"]) if data.get("validationMape") is not None else None),
        adapter_version=str(data.get("adapterVersion") or "personal-v0"),
        active=bool(data.get("active")),
        profile_version=int(data.get("profileVersion") or 0),
        base_model_version=str(data.get("baseModelVersion") or "unknown"),
        training_segments=int(data.get("trainingSegments") or 0),
        nominal_capacity_wh=(float(data["nominalCapacityWh"]) if data.get("nominalCapacityWh") is not None else None),
        estimated_effective_capacity_wh=(float(data["estimatedEffectiveCapacityWh"]) if data.get("estimatedEffectiveCapacityWh") is not None else None),
        capacity_confidence=float(data.get("capacityConfidence") or 0),
        state_of_health=(float(data["stateOfHealth"]) if data.get("stateOfHealth") is not None else None),
        global_time_scale=float(correction.get("globalTimeScale") or 1),
        global_time_bias_minutes=float(correction.get("globalTimeBiasMinutes") or 0),
        power_scale=float(correction.get("powerScale") or 1),
        soc_bands=dict(data.get("socBands") or {}),
        quality_confidence=float(quality.get("confidence") or 0),
        last_training_error=quality.get("lastTrainingError"),
        last_trained_at=_date(data.get("lastTrainedAt")),
        updated_at=_date(data.get("updatedAt")) or datetime.now(timezone.utc),
    )


def _profile_id(uid: str, vehicle_id: str) -> str:
    return hashlib.sha256(f"{uid}:{vehicle_id}".encode("utf-8")).hexdigest()
