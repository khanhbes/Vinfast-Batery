"""Smart Charge reconciliation worker.

The Shelly device timer remains the primary cutoff. This worker only reconciles
state and sends a best-effort backup OFF; it never sends ON.
"""
from __future__ import annotations

import time
import statistics
import hashlib
import uuid

from shelly.models import utcnow, NONTERMINAL_SESSION_STATES
from shelly.service import TRANSIENT_READ_CODES
from shelly.providers import ProviderError
from shelly.personal_model_registry import PersonalModelRegistry, validate_candidate


def reconcile_once(service, uid: str, *, lease_guard=None):
    # V4 accounts may have independent sessions for multiple vehicles. Never
    # reconcile an arbitrary account-level "first" session or use another
    # vehicle's binding as a fallback.
    sessions = service.repository.active_sessions(uid, strict=True)
    if not sessions:
        return None
    reconciled = []
    for session in sessions:
        if lease_guard is not None:
            lease_guard()
        binding = service.session_binding(uid, session)
        if not binding:
            reconciled.append(service.mark_session_unknown(uid, session, "bindingChanged"))
            continue
        reconciled.append(_reconcile_session(service, uid, session, binding, lease_guard=lease_guard))
    # Legacy callers expect one session; all sessions were still processed.
    return reconciled[0] if reconciled else None


def _reconcile_session(service, uid: str, session, binding, *, lease_guard=None):
    try:
        status = service.provider.get_status(binding)
    except ProviderError as error:
        if lease_guard is not None:
            lease_guard()
        # A busy/rate-limited Cloud read is retried next cycle; it must not turn
        # a verified session into "unknown" (which triggers recovery_off).
        if error.code in TRANSIENT_READ_CODES:
            return session
        return service.mark_session_unknown(uid, session, error.code)
    if lease_guard is not None:
        lease_guard()
    if not service._status_matches_device(status, session.device_id):
        return service.mark_session_unknown(uid, session, "deviceUnverified")
    service._apply_safety(uid, binding, status)
    # Reuse the service terminal path so the last meter reading, lease release,
    # vehicle SOC projection and post-commit notification stay identical for
    # manual stop, app polling, restart recovery and this worker.
    # There is deliberately no compatibility terminal path without readback,
    # and no automatic cloud AI ingestion/training in the hardware watchdog.
    return service._reconcile_with_status(uid, status, session.vehicle_id, session=session)


def run_forever(service, user_ids=None, interval_seconds: int = 60, *, sleeper=time.sleep, health_monitor=None,
                stop_event=None):
    """Reconcile only active sessions; never enumerate every account.

    Collection-group reads are bounded and run once per minute.  The legacy
    ``user_ids`` callback remains supported for tests and local deployments.
    """
    interval_seconds = max(15, min(60, int(interval_seconds)))
    backoff = interval_seconds
    worker_id = str(uuid.uuid4())
    lease_deadline = None
    last_epoch = None

    class WorkerStopping(Exception):
        pass

    def stopping():
        return stop_event is not None and stop_event.is_set()

    def wait(seconds):
        if stop_event is not None:
            stop_event.wait(seconds)
        else:
            sleeper(seconds)

    def lease_guard():
        nonlocal lease_deadline
        if stopping():
            raise WorkerStopping()
        now = service.clock()
        lease_deadline = service.repository.worker_lease_deadline(worker_id, now=now)
        if (lease_deadline - now).total_seconds() <= 60:
            lease_deadline = service.repository.renew_worker_lease(worker_id, now=now)

    # Only this worker instance receives this guard. API OFF/recovery remains
    # available even when the worker cannot acquire/renew its own lease.
    previous_guard = getattr(service, "_worker_lease_guard", None)
    previous_provider_guard = getattr(service.provider, "worker_lease_guard", None)
    service._worker_lease_guard = lease_guard
    service.provider.worker_lease_guard = lease_guard
    if health_monitor:
        health_monitor.mark_unhealthy()
    try:
        while not stopping():
            try:
                epoch = service.repository.claim_worker_lease(worker_id, now=service.clock())
                if epoch is None:
                    raise RuntimeError("workerLeaseBusy")
                if epoch != last_epoch:
                    service.repository.publish_worker_heartbeat(worker_id, healthy=False, now=service.clock())
                    last_epoch = epoch
                lease_guard()
                if user_ids is not None:
                    for uid in set(user_ids()):
                        reconcile_once(service, uid, lease_guard=lease_guard)
                else:
                    db = service.repository.db
                    if db:
                        query = (db.collection_group("smartChargingSessions")
                                 .where("state", "in", sorted(NONTERMINAL_SESSION_STATES))
                                 .limit(100))
                        owners = set()
                        snapshots = list(query.stream())
                        if len(snapshots) >= 100:
                            raise RuntimeError("workerScanCapacityReached")
                        for snapshot in snapshots:
                            parts = snapshot.reference.path.split('/')
                            if len(parts) >= 4 and parts[0] == 'users':
                                owners.add(parts[1])
                        for uid in owners:
                            reconcile_once(service, uid, lease_guard=lease_guard)
                    else:
                        raise RuntimeError("workerDatabaseUnavailable")
                lease_guard()
                service.repository.publish_worker_heartbeat(worker_id, healthy=True, now=service.clock())
                if health_monitor:
                    health_monitor.mark_healthy(lease_remaining_seconds=(lease_deadline - service.clock()).total_seconds())
                backoff = interval_seconds
            except WorkerStopping:
                break
            except Exception as error:
                if health_monitor:
                    health_monitor.mark_unhealthy()
                try:
                    service.repository.publish_worker_heartbeat(worker_id, healthy=False, now=service.clock())
                except Exception:
                    pass  # Never overwrite another worker's heartbeat.
                print(f"[smart-charge-worker] transient error: {type(error).__name__}")
                wait(min(60, backoff))
                backoff = min(60, backoff * 2)
                continue
            wait(interval_seconds)
    finally:
        service._worker_lease_guard = previous_guard
        service.provider.worker_lease_guard = previous_provider_guard
        if health_monitor:
            health_monitor.mark_unhealthy()
        try:
            service.repository.publish_worker_heartbeat(worker_id, healthy=False, now=service.clock())
            service.repository.release_worker_lease(worker_id, now=service.clock())
        except Exception:
            pass  # A lost/stale worker cannot invalidate the new holder.


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
