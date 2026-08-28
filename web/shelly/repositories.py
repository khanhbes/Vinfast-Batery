from __future__ import annotations

import threading
from datetime import datetime, timezone

from .models import ChargePreview, ChargingSession, DeviceBinding


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
            )
            with self._lock:
                self._bindings.setdefault(uid, {})[binding.device_id] = binding
        with self._lock:
            return list(self._bindings.get(uid, {}).values())

    def get_binding(self, uid: str) -> DeviceBinding | None:
        active = [item for item in self.list_bindings(uid) if item.revoked_at is None]
        return active[0] if active else None

    def revoke_binding(self, uid: str, device_id: str, when: datetime) -> None:
        binding = self._bindings.get(uid, {}).get(device_id)
        if binding:
            binding.revoked_at = when
            binding.updated_at = when
            self.save_binding(uid, binding)

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
        if self.db:
            payload = session.to_dict()
            payload["idempotency_key"] = session.idempotency_key
            self.db.collection("users").document(uid).collection("smartChargingSessions").document(session.session_id).set(payload, merge=True)

    def upsert_charge_log(self, uid: str, session: ChargingSession) -> None:
        """Write one terminal ChargeLogs document per Smart Charge session."""
        if not self.db or session.state not in ("completed", "cancelled", "interrupted", "failed"):
            return
        payload = {
            "id": session.session_id,
            "sessionId": session.session_id,
            "vehicleId": session.vehicle_id,
            "ownerUid": uid,
            "startTime": session.created_at,
            "endTime": session.stopped_at or session.updated_at,
            "startBatteryPercent": round(session.start_soc),
            "endBatteryPercent": round(session.estimated_soc if session.estimated_soc is not None else session.target_soc),
            "targetBatteryPercent": round(session.target_soc),
            "source": "shelly_smart_charging",
            "shellyDeviceId": session.device_id,
            "controlTransport": session.transport,
            "plannedStopAt": session.effective_stop_at,
            "actualStopAt": session.stopped_at or session.updated_at,
            "stopReason": session.stop_reason,
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

    def current_session(self, uid: str) -> ChargingSession | None:
        active = [s for s in self.history(uid) if s.state in ("arming", "active")]
        return active[0] if active else None

    def history(self, uid: str, limit: int = 20) -> list[ChargingSession]:
        with self._lock:
            values = list(self._sessions.get(uid, {}).values())
        if not values and self.db:
            snapshots = self.db.collection("users").document(uid).collection("smartChargingSessions").order_by("created_at", direction="DESCENDING").limit(limit).stream()
            values = [_session(item.to_dict() or {}) for item in snapshots]
            with self._lock:
                for session in values:
                    self._sessions.setdefault(uid, {})[session.session_id] = session
                    self._idempotency[(uid, session.idempotency_key)] = session.session_id
        return sorted(values, key=lambda item: item.created_at, reverse=True)[:limit]

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


def _date(value):
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    return None


def _session(data: dict) -> ChargingSession:
    return ChargingSession(
        session_id=str(data["session_id"]), device_id=str(data["device_id"]), vehicle_id=str(data["vehicle_id"]),
        state=str(data["state"]), start_soc=float(data["start_soc"]), target_soc=float(data["target_soc"]),
        predicted_minutes=int(data["predicted_minutes"]), prediction_source=str(data.get("prediction_source") or "unknown"),
        predicted_duration_seconds=int(data.get("predicted_duration_seconds") or int(data["predicted_minutes"]) * 60),
        prediction_confidence=data.get("prediction_confidence"), created_at=_date(data["created_at"]), updated_at=_date(data["updated_at"]),
        ai_stop_at=_date(data["ai_stop_at"]), effective_stop_at=_date(data["effective_stop_at"]),
        absolute_safety_stop_at=_date(data["absolute_safety_stop_at"]), idempotency_key=str(data["idempotency_key"]),
        strategy=str(data.get("strategy") or "ai_target"),
        model_key=str(data.get("model_key") or "charging_time"),
        model_version=str(data.get("model_version") or "unknown"),
        runtime_health=str(data.get("runtime_health") or "unknown"),
        prediction_warnings=list(data.get("prediction_warnings") or []),
        fallback_reason=data.get("fallback_reason"),
        prediction_analyzed_at=_date(data.get("prediction_analyzed_at")),
        estimated_soc=data.get("estimated_soc"), baseline_energy_wh=data.get("baseline_energy_wh"), energy_used_wh=float(data.get("energy_used_wh") or 0),
        relay_verified=bool(data.get("relay_verified")), timer_verified=bool(data.get("timer_verified")), transport=str(data.get("transport") or "shelly_cloud"),
        stopped_at=_date(data.get("stopped_at")), stop_reason=data.get("stop_reason"), version=int(data.get("version") or 1), last_error=data.get("last_error"),
    )
