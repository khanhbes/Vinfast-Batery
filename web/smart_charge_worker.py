"""Smart Charge reconciliation worker.

The Shelly device timer remains the primary cutoff. This worker only reconciles
state and sends a best-effort backup OFF; it never sends ON.
"""
from __future__ import annotations

import time
import statistics

from shelly.models import utcnow
from shelly.providers import ProviderError


def reconcile_once(service, uid: str):
    session = service.repository.current_session(uid)
    binding = service.binding(uid)
    if not session or not binding:
        return None
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
    usable = [row for row in rows if float(row.get("predictedMinutes") or 0) > 0 and float(row.get("durationSeconds") or 0) > 0]
    if len(usable) < 5:
        return profile
    usable.sort(key=lambda row: str(row.get("updatedAt") or ""))
    split = max(3, int(len(usable) * 0.8))
    train, validation = usable[:split], usable[split:] or usable[-1:]
    biases = [
        (float(row["durationSeconds"]) / 60 - float(row["predictedMinutes"])) /
        float(row["predictedMinutes"])
        for row in train
    ]
    candidate_bias = max(-0.35, min(0.50, statistics.median(biases)))
    candidate_errors = [
        abs(float(row["durationSeconds"]) / 60 - float(row["predictedMinutes"]) * (1 + candidate_bias)) /
        (float(row["durationSeconds"]) / 60) * 100
        for row in validation
    ]
    candidate_mape = statistics.mean(candidate_errors)
    current_mape = profile.validation_mape if profile.active and profile.validation_mape is not None else float("inf")
    if candidate_mape + 0.25 >= current_mape or candidate_mape > 35:
        profile.last_training_error = "candidate_did_not_improve"
        profile.last_trained_at = utcnow()
        profile.updated_at = profile.last_trained_at
        service.repository.save_personal_profile(profile)
        service.repository.append_audit(uid, "personal_adapter_rejected", vehicle_id=vehicle_id, candidate_mape=candidate_mape)
        return profile
    profile.eta_bias_ratio = candidate_bias
    profile.global_time_scale = 1.0 + candidate_bias
    profile.validation_mape = candidate_mape
    profile.adapter_version = f"personal-v{profile.valid_sessions}-{int(time.time())}"
    profile.active = True
    profile.profile_version += 1
    profile.last_training_error = None
    profile.last_trained_at = utcnow()
    profile.updated_at = profile.last_trained_at
    service.repository.save_personal_profile(profile)
    service.repository.append_audit(uid, "personal_adapter_promoted", vehicle_id=vehicle_id, adapter_version=profile.adapter_version, validation_mape=candidate_mape)
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
            profile = train_personal_adapter_once(service, uid, vehicle_id)
            job.reference.set({
                "state": "completed",
                "adapterVersion": profile.adapter_version if profile else None,
                "profileVersion": profile.profile_version if profile else None,
                "updatedAt": utcnow(),
            }, merge=True)
            processed += 1
        except Exception as error:
            job.reference.set({
                "state": "failed",
                "error": type(error).__name__,
                "updatedAt": utcnow(),
            }, merge=True)
    return processed
