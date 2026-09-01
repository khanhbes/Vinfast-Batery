"""Smart Charge reconciliation worker.

The Shelly device timer remains the primary cutoff. This worker only reconciles
state and sends a best-effort backup OFF; it never sends ON.
"""
from __future__ import annotations

import time
import statistics
import hashlib

from shelly.models import utcnow
from shelly.providers import ProviderError
from shelly.personal_model_registry import PersonalModelRegistry, validate_candidate


def reconcile_once(service, uid: str):
    # V4 accounts may have independent sessions for multiple vehicles. Never
    # reconcile an arbitrary account-level "first" session or use another
    # vehicle's binding as a fallback.
    sessions = service.repository.active_sessions(uid)
    if not sessions:
        return None
    reconciled = []
    for session in sessions:
        binding = service.binding(uid, session.vehicle_id)
        if not binding:
            reconciled.append(session)
            continue
        reconciled.append(_reconcile_session(service, uid, session, binding))
    # Legacy callers expect one session; all sessions were still processed.
    return reconciled[0] if reconciled else None


def _reconcile_session(service, uid: str, session, binding):
    try:
        status = service.provider.get_status(binding)
    except ProviderError:
        return session
    now = utcnow()
    if status.relay and status.timer_remaining <= 0:
        try:
            service.provider.turn_off(binding)
        except ProviderError:
            session.last_error = "relayUnverified"
            service.repository.save_session(uid, session)
            return session
    if not status.relay:
        session.state = "completed" if now >= session.effective_stop_at else "interrupted"
        session.stop_reason = "planned_timer" if session.state == "completed" else "relay_off"
        session.stopped_at = now
        session.updated_at = now
        session.relay_verified = True
        session.version += 1
        service.repository.save_session(uid, session)
        service.repository.upsert_charge_log(uid, session)
        try:
            service.ingest_personal_session(uid, session.session_id)
        except Exception:
            # Terminal state and OFF verification are never rolled back by a
            # training pipeline failure. The job can be retried independently.
            pass
    return session


def run_forever(service, user_ids, interval_seconds: int = 15):
    while True:
        for uid in user_ids():
            reconcile_once(service, uid)
        process_personal_training_jobs_once(service)
        time.sleep(interval_seconds)


def train_personal_adapter_once(service, uid: str, vehicle_id: str):
    """Promote a small residual only when held-out MAPE improves.

    This intentionally does not clone or fine-tune the global Keras model. The
    adapter is an owner/vehicle-scoped duration bias, cheap enough to validate
    after every eligible terminal session.
    """
    profile = service.repository.get_personal_profile(uid, vehicle_id)
    db = service.repository.db
    if not profile or not profile.consent_enabled or not db or profile.valid_sessions < 5:
        return profile
    docs = (db.collection("users").document(uid).collection("chargingTrainingSamples")
            .where("vehicleId", "==", vehicle_id)
            .where("eligibleForTargetTraining", "==", True).stream())
    rows = [doc.to_dict() or {} for doc in docs]
    usable = []
    for raw in rows:
        if raw.get("trainingExcluded") is True:
            continue
        row = dict(raw)
        # Developer corrections change only the training view, never the raw
        # sample recorded at the end of the physical charging session.
        if row.get("trainingDurationSecondsOverride") is not None:
            row["durationSeconds"] = row["trainingDurationSecondsOverride"]
        if row.get("trainingPredictedMinutesOverride") is not None:
            row["predictedMinutes"] = row["trainingPredictedMinutesOverride"]
        if float(row.get("predictedMinutes") or 0) <= 0:
            continue
        if float(row.get("durationSeconds") or 0) <= 0:
            continue
        usable.append(row)
    if len(usable) < 5:
        return profile
    usable.sort(key=lambda row: str(row.get("updatedAt") or ""))
    split = max(3, int(len(usable) * 0.8))
    train, validation = usable[:split], usable[split:] or usable[-1:]
    registry = getattr(service, "personal_model_registry", None)
    if registry is None:
        registry = PersonalModelRegistry(db)
        service.personal_model_registry = registry
    # Candidate is built from the promoted profile and never mutates it until
    # validation succeeds. Use the recent held-out slice for the decision.
    candidate_profile, candidate = registry.build_candidate(
        profile, uid, vehicle_id, train, profile.base_model_version,
    )
    validation_result = validate_candidate(candidate_profile, validation)
    decision = registry.promote_or_reject(candidate_profile, candidate, validation_result)
    profile.last_trained_at = utcnow()
    profile.updated_at = profile.last_trained_at
    if decision.status == "promoted":
        profile.global_time_scale = candidate_profile.global_time_scale
        profile.eta_bias_ratio = candidate_profile.eta_bias_ratio
        profile.validation_mape = validation_result.mape
        profile.adapter_version = f"personal-v{decision.candidate.profile_version}"
        profile.active = True
        profile.profile_version = decision.candidate.profile_version
        profile.last_training_error = None
        service.repository.append_audit(uid, "personal_adapter_promoted", vehicle_id=vehicle_id, adapter_version=profile.adapter_version, validation_mape=validation_result.mape)
    else:
        profile.last_training_error = decision.reason
        service.repository.append_audit(uid, "personal_adapter_rejected", vehicle_id=vehicle_id, candidate_mape=validation_result.mape, reason=decision.reason)
    service.repository.save_personal_profile(profile)
    return profile


def process_personal_training_jobs_once(service, limit: int = 20) -> int:
    """Processes owner/vehicle-scoped pending jobs with explicit outcomes."""
    db = service.repository.db
    if not db:
        return 0
    jobs = (db.collection("personalChargingTrainingJobs")
            .where("state", "==", "pending").limit(limit).stream())
    processed = 0
    for job in jobs:
        data = job.to_dict() or {}
        uid = str(data.get("ownerUid") or "")
        vehicle_id = str(data.get("vehicleId") or "")
        if not uid or not vehicle_id:
            job.reference.set({"state": "failed", "error": "missing_owner_or_vehicle", "updatedAt": utcnow()}, merge=True)
            continue
        job.reference.set({"state": "processing", "updatedAt": utcnow()}, merge=True)
        try:
            before = service.repository.get_personal_profile(uid, vehicle_id)
            before_trained_at = before.last_trained_at if before else None
            before_version = before.profile_version if before else 0
            profile = train_personal_adapter_once(service, uid, vehicle_id)
            job.reference.set({
                "state": "completed",
                "adapterVersion": profile.adapter_version if profile else None,
                "profileVersion": profile.profile_version if profile else None,
                "updatedAt": utcnow(),
            }, merge=True)
            # Only notify after a real training attempt. Jobs completed while
            # fewer than five valid samples exist are ingestion bookkeeping,
            # not a finished fine-tune.
            if profile and profile.last_trained_at != before_trained_at:
                promoted = profile.profile_version > before_version
                _notify_personal_training_result(
                    db,
                    uid=uid,
                    vehicle_id=vehicle_id,
                    training_id=str(data.get("triggerSessionId") or job.id),
                    profile=profile,
                    promoted=promoted,
                )
            processed += 1
        except Exception as error:
            job.reference.set({
                "state": "failed",
                "error": type(error).__name__,
                "updatedAt": utcnow(),
            }, merge=True)
    return processed


def _notify_personal_training_result(
    db, *, uid: str, vehicle_id: str, training_id: str, profile, promoted: bool
) -> None:
    """Write one durable, idempotent Notification Center item per job."""
    notification_key = hashlib.sha256(
        f"personal-ai:{uid}:{vehicle_id}:{training_id}".encode("utf-8")
    ).hexdigest()
    if promoted:
        title = "AI cá nhân đã được cập nhật"
        message = (
            f"Mô hình cho xe {vehicle_id} đã học xong và chuyển sang "
            f"{profile.adapter_version or 'phiên bản mới'}."
        )
        notification_type = "modelUpdated"
        outcome = "promoted"
    else:
        title = "Đã kiểm tra bản fine-tune mới"
        message = (
            "Bản mới chưa cải thiện độ chính xác nên ứng dụng tiếp tục dùng "
            "mô hình cá nhân hiện tại."
        )
        notification_type = "system"
        outcome = "kept_current"
    db.collection("UserNotifications").document(notification_key).set({
        "userId": uid,
        "type": notification_type,
        "title": title,
        "message": message,
        "status": "unread",
        "createdAt": utcnow(),
        "payload": {
            "vehicleId": vehicle_id,
            "adapterVersion": profile.adapter_version,
            "profileVersion": profile.profile_version,
            "outcome": outcome,
        },
        "actionTarget": "/settings/personal-ai",
    }, merge=True)
