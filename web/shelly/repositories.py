from __future__ import annotations

import threading
import hashlib
from datetime import datetime, timezone

from .models import (
    ChargePreview,
    ChargingSession,
    DeviceBinding,
    EtaCandidate,
    PersonalChargingProfile,
    SmartChargeSafetyEvent,
)


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
        self._processed_training_sessions: set[tuple[str, str]] = set()

    def register_vehicle_owner(self, uid: str, vehicle_id: str) -> None:
        """Deterministic test/dev registration; production reads Vehicles."""
        with self._lock:
            self._vehicle_owners[vehicle_id] = uid

    def vehicle_for_owner(self, uid: str, vehicle_id: str) -> dict | None:
        if not vehicle_id or vehicle_id == "manual":
            return None
        if self.db:
            snapshot = self.db.collection("Vehicles").document(vehicle_id).get()
            data = snapshot.to_dict() or {} if snapshot.exists else {}
            if data.get("ownerUid") != uid or data.get("isDeleted") is True:
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
            return {"vehicleId": vehicle_id, "ownerUid": uid} if self._vehicle_owners.get(vehicle_id) == uid else None

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

    def current_session(self, uid: str) -> ChargingSession | None:
        active = [s for s in self.history(uid) if s.state in ("arming", "active")]
        return active[0] if active else None

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

    def history_page(
        self,
        uid: str,
        limit: int = 20,
        cursor: datetime | None = None,
        strategy: str | None = None,
    ) -> tuple[list[ChargingSession], str | None]:
        limit = min(50, max(1, int(limit)))
        if self.db:
            query = (self.db.collection("users").document(uid)
                     .collection("smartChargingSessions")
                     .order_by("created_at", direction="DESCENDING"))
            if cursor is not None:
                query = query.where("created_at", "<", cursor)
            snapshots = list(query.limit(limit + 1).stream())
            values = [_session(item.to_dict() or {}) for item in snapshots]
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
        if strategy:
            values = [item for item in values if item.strategy == strategy]
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
            # Training samples are privacy-scoped. Forget processed markers so
            # a future opt-in starts as a genuinely new profile.
            self._processed_training_sessions = {
                item for item in self._processed_training_sessions if item[0] != uid
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
        with self._lock:
            self._processed_training_sessions.add((uid, session.session_id))
        if not self.db:
            return
        value = dict(payload)
        value.update({
            "ownerUid": uid,
            "vehicleId": session.vehicle_id,
            "sessionId": session.session_id,
            "updatedAt": datetime.now(timezone.utc),
        })
        (self.db.collection("users").document(uid).collection("chargingTrainingSamples")
         .document(session.session_id).set(value, merge=True))

    def training_sample_processed(self, uid: str, session_id: str) -> bool:
        with self._lock:
            if (uid, session_id) in self._processed_training_sessions:
                return True
        if not self.db:
            return False
        snapshot = (self.db.collection("users").document(uid)
                    .collection("chargingTrainingSamples").document(session_id).get())
        processed = snapshot.exists and (snapshot.to_dict() or {}).get("state") == "trained"
        if processed:
            with self._lock:
                self._processed_training_sessions.add((uid, session_id))
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
        if not parent.exists or (parent.to_dict() or {}).get("ownerUid") != uid:
            return []
        return [item.to_dict() or {} for item in parent.reference.collection("smartChargeTelemetry").order_by("timestamp").stream()]


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
