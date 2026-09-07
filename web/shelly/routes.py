from __future__ import annotations

import os
import secrets
from datetime import timedelta
from functools import wraps
from urllib.parse import quote

import requests

from flask import Blueprint, after_this_request, jsonify, request

from .models import DeviceBinding, utcnow
from .profile_vault import ProfileVaultError
from .service import SmartChargeError


def create_blueprint(service, repository, auth_resolver, trust_verifier=None):
    bp = Blueprint("shelly_cloud_first", __name__)

    def authenticated(handler):
        @wraps(handler)
        def wrapped(*args, **kwargs):
            uid, _email, _role = auth_resolver()
            if not uid:
                return jsonify({"success": False, "error": {"code": "unauthorized", "message": "Cần đăng nhập"}}), 401
            return handler(uid, *args, **kwargs)
        return wrapped

    def developer(handler):
        """Admin-only developer tools; local Developer Mode is not authority."""
        @wraps(handler)
        def wrapped(*args, **kwargs):
            admin_key = request.headers.get("X-Admin-Key", "").strip()
            dev_key = os.environ.get("DEV_ADMIN_KEY", "").strip()
            if admin_key and dev_key and admin_key == dev_key:
                return handler("dev-admin", *args, **kwargs)
            uid, _email, role = auth_resolver()
            if not uid:
                return jsonify({"success": False, "error": {"code": "unauthorized", "message": "Cần đăng nhập"}}), 401
            if role != "admin" and os.environ.get("FLASK_ENV") != "development":
                return jsonify({"success": False, "error": {"code": "developerRequired", "message": "Cần quyền developer để sửa dữ liệu fine-tune"}}), 403
            return handler(uid, *args, **kwargs)
        return wrapped

    def ok(data=None, **extra):
        return jsonify({"success": True, "data": data, **extra})

    def execute(action):
        try:
            return action()
        except SmartChargeError as exc:
            return jsonify({
                "success": False,
                "error": {"code": exc.code, "message": exc.message, "retryable": exc.retryable},
            }), exc.status

    def profile_error(error):
        message = str(error)
        if isinstance(error, PermissionError):
            return jsonify({"success": False, "error": {"code": "vehicleForbidden", "message": message}}), 403
        if isinstance(error, RuntimeError) and message == "profileRevisionConflict":
            return jsonify({"success": False, "error": {"code": "profileRevisionConflict", "message": "Cấu hình đã được cập nhật trên thiết bị khác. Hãy quét lại."}}), 409
        if isinstance(error, ProfileVaultError):
            return jsonify({"success": False, "error": {"code": "profileVaultUnavailable", "message": message}}), 503
        return jsonify({"success": False, "error": {"code": "invalidProfile", "message": message or "Cấu hình Shelly không hợp lệ"}}), 400

    def no_store():
        @after_this_request
        def add_no_store(response):
            response.headers["Cache-Control"] = "no-store, private"
            response.headers["Pragma"] = "no-cache"
            return response

    def verify_web_cloud_profile(body):
        """Validate web-entered credentials before they reach the vault."""
        if body.get("source") != "web":
            return None
        host = str(body.get("cloudHost") or "").rstrip("/")
        try:
            response = requests.post(
                f"{host}/v2/devices/api/get",
                params={"auth_key": str(body.get("cloudAuthKey") or "")},
                json={"ids": [str(body.get("deviceId") or "")], "select": ["status"]},
                timeout=5,
            )
        except requests.RequestException:
            return "Không thể xác minh Shelly Cloud từ web server"
        if response.status_code in (401, 403):
            return "Authorization Cloud Key không hợp lệ hoặc đã bị thu hồi"
        if response.status_code == 429:
            return "Shelly Cloud đang giới hạn tần suất; hãy thử lại sau"
        if not 200 <= response.status_code < 300:
            return "Shelly Cloud không xác minh được thiết bị này"
        verification = body.get("verification") if isinstance(body.get("verification"), dict) else {}
        body["verification"] = {**verification, "cloudVerified": True}
        return None

    @bp.post("/api/shelly/consent/start")
    @authenticated
    def consent_start(uid):
        if service.provider.name == "fake":
            devices = service.provider.list_devices(uid)
            if devices:
                repository.save_binding(uid, devices[0])
                return ok({"completed": True, "binding": devices[0].to_dict()})
        if service.provider.name == "legacy":
            binding = service.binding(uid)
            if binding:
                return ok({"completed": True, "binding": binding.to_dict(), "pilot": True})
        tag = os.environ.get("SHELLY_INTEGRATOR_TAG", "").strip()
        callback = os.environ.get("SHELLY_CONSENT_CALLBACK_URL", "").strip()
        if not tag or not callback:
            return jsonify({
                "success": False,
                "error": {"code": "integratorNotConfigured", "message": "Easy Connect đang chờ Shelly Integrator license."},
            }), 503
        state = secrets.token_urlsafe(32)
        repository.save_consent(state, uid, utcnow() + timedelta(minutes=10))
        callback_url = f"{callback}?state={quote(state)}"
        url = f"https://my.shelly.cloud/integrator.html?itg={quote(tag)}&cb={quote(callback_url, safe='')}"
        return ok({"authorizationUrl": url, "expiresIn": 600})

    @bp.get("/api/shelly/profiles")
    @authenticated
    def profiles(uid):
        repository.migrate_legacy_profile_secrets(uid)
        return ok({"items": repository.list_synced_profiles(uid, request.args.get("vehicleId") or None)})

    @bp.post("/api/shelly/profiles/resolve")
    @authenticated
    def resolve_profile(uid):
        body = request.get_json(silent=True) or {}
        repository.migrate_legacy_profile_secrets(uid)
        profile = repository.resolve_synced_profile(uid, str(body.get("vehicleId") or "").strip() or None)
        return ok({"profile": profile} if profile else None)

    @bp.put("/api/shelly/profiles/<device_id>")
    @authenticated
    def save_profile(uid, device_id):
        body = request.get_json(silent=True) or {}
        body["deviceId"] = device_id
        cloud_error = verify_web_cloud_profile(body)
        if cloud_error:
            return jsonify({"success": False, "error": {"code": "cloudVerificationFailed", "message": cloud_error}}), 422
        expected = body.get("expectedRevision")
        try:
            metadata = repository.save_synced_profile(
                uid, body, int(expected) if expected is not None else None
            )
        except (ProfileVaultError, PermissionError, RuntimeError, ValueError) as error:
            return profile_error(error)
        # Direct profiles are also bindings so the rest of the account sees
        # the chosen device, but never contain credential fields.
        repository.save_binding(uid, DeviceBinding(
            device_id=device_id,
            display_name=str(metadata.get("displayName") or "Shelly sạc xe"),
            model=str(metadata.get("model") or "S3PL-00112EU"),
            generation=3,
            provider="direct_cloud_lan",
            connection_mode="advanced_direct",
            online=bool(metadata.get("cloudVerified")),
            power_meter_verified=bool(metadata.get("powerMeterVerified")),
            safe_boot_verified=bool(metadata.get("safeBootVerified")),
            no_load_test_verified=bool(metadata.get("noLoadTestVerified")),
            last_verified_at=metadata.get("verifiedAt"),
            vehicle_id=metadata.get("vehicleId"),
        ))
        return ok(metadata)

    @bp.post("/api/shelly/profiles/<device_id>/restore")
    @authenticated
    def restore_profile(uid, device_id):
        no_store()
        try:
            profile = repository.restore_synced_profile(uid, device_id)
        except ProfileVaultError as error:
            return profile_error(error)
        return ok(profile)

    @bp.post("/api/shelly/profiles/<device_id>/verify")
    @authenticated
    def verify_profile(uid, device_id):
        body = request.get_json(silent=True) or {}
        profile = repository.verify_synced_profile(uid, device_id, body)
        if profile is None:
            return jsonify({"success": False, "error": {"code": "profileNotFound", "message": "Không tìm thấy cấu hình Shelly"}}), 404
        return ok(profile)

    @bp.delete("/api/shelly/profiles/<device_id>")
    @authenticated
    def revoke_profile(uid, device_id):
        if not repository.revoke_synced_profile(uid, device_id):
            return ok({"revoked": False})
        repository.revoke_binding(uid, device_id, utcnow())
        return ok({"revoked": True})

    @bp.post("/api/shelly/consent/callback")
    def consent_callback():
        state = request.args.get("state", "")
        payload = request.get_json(silent=True) or {}
        trust = request.headers.get("SCL-Trust", "")
        if not trust_verifier or not trust_verifier(trust, payload):
            return jsonify({"success": False, "error": {"code": "invalidConsent", "message": "Callback không hợp lệ"}}), 401
        uid = repository.consume_consent(state, utcnow())
        if not uid:
            return jsonify({"success": False, "error": {"code": "consentExpired", "message": "Consent đã hết hạn hoặc đã dùng"}}), 409
        device_id = str(payload.get("deviceId") or "")
        if payload.get("action") == "remove":
            repository.revoke_binding(uid, device_id, utcnow())
            return ok({"revoked": True})
        access = str(payload.get("accessGroups") or "00")
        if access != "01":
            return jsonify({"success": False, "error": {"code": "controlPermissionMissing", "message": "Cần cấp quyền Control"}}), 403
        binding = DeviceBinding(
            device_id=device_id,
            display_name=((payload.get("name") or ["Shelly sạc xe"])[0]),
            model=str(payload.get("deviceCode") or "unknown"),
            generation=3,
            provider="integrator",
            permissions=["read", "control"],
            online=True,
            power_meter_verified=False,
            host=str(payload.get("host") or ""),
        )
        repository.save_binding(uid, binding)
        return ok(binding.to_dict())

    @bp.get("/api/shelly/devices")
    @authenticated
    def devices(uid):
        return ok([item.to_dict() for item in repository.list_bindings(uid)])

    @bp.get("/api/shelly/device")
    @authenticated
    def device(uid):
        # Vehicle-scoped lookup is important when one account owns multiple
        # Shelly devices.  Keep the unscoped form for legacy callers, but
        # never silently return another vehicle's explicit binding.
        binding = service.binding(uid, request.args.get("vehicleId") or None)
        return ok(binding.to_dict() if binding else None)

    @bp.get("/api/shelly/capabilities")
    @authenticated
    def capabilities(uid):
        return ok(service.capabilities(uid, request.args.get("vehicleId") or None))

    @bp.post("/api/shelly/devices/<device_id>/select")
    @authenticated
    def select_device(uid, device_id):
        body = request.get_json(silent=True) or {}
        vehicle_id = str(body.get("vehicleId") or request.args.get("vehicleId") or "").strip() or None
        shared = bool(body.get("shared", False))
        if vehicle_id and repository.vehicle_for_owner(uid, vehicle_id) is None:
            return jsonify({
                "success": False,
                "error": {
                    "code": "vehicleForbidden",
                    "message": "Xe không thuộc tài khoản này",
                },
            }), 403
        match = next((item for item in repository.list_bindings(uid) if item.device_id == device_id and item.revoked_at is None), None)
        if not match:
            return jsonify({"success": False, "error": {"code": "deviceNotFound", "message": "Thiết bị không thuộc tài khoản này"}}), 404
        # V4 keeps multiple physical devices and explicit vehicle bindings.
        match.vehicle_id = vehicle_id
        match.shared = shared
        repository.save_binding(uid, match)
        repository.append_audit(uid, "device_selected", device_id=device_id)
        return ok(match.to_dict())

    @bp.delete("/api/shelly/device")
    @authenticated
    def revoke(uid):
        binding = service.binding(uid)
        if not binding:
            return ok(None)
        service.provider.revoke(binding)
        repository.revoke_binding(uid, binding.device_id, utcnow())
        return ok({"revoked": True})

    @bp.post("/api/smart-charging/preview")
    @authenticated
    def preview(uid):
        return execute(lambda: ok(service.create_preview(uid, request.get_json(silent=True) or {}).to_dict()))

    @bp.post("/api/smart-charging/sessions")
    @authenticated
    def start(uid):
        body = request.get_json(silent=True) or {}
        key = request.headers.get("Idempotency-Key", "")
        return execute(lambda: ok(service.start(uid, str(body.get("previewId") or ""), key).to_dict()))

    @bp.get("/api/smart-charging/status")
    @authenticated
    def status(uid):
        return execute(lambda: ok(service.status(uid, request.args.get("vehicleId") or None).to_dict()))

    @bp.get("/api/smart-charging/session/current")
    @authenticated
    def current(uid):
        session = service.current(uid, request.args.get("vehicleId") or None)
        active = bool(session and session.state in ("arming", "active"))
        return ok(session.to_dict() if session else None, active=active)

    @bp.get("/api/smart-charging/sessions/active")
    @authenticated
    def active_sessions(uid):
        return ok([item.to_dict() for item in repository.active_sessions(uid)])

    @bp.get("/api/smart-charging/sessions")
    @authenticated
    def history(uid):
        limit = min(50, max(1, int(request.args.get("limit", "20"))))
        vehicle_id = request.args.get("vehicleId") or None
        strategy = request.args.get("strategy") or None
        # Apply all filters inside the repository before limiting. The old
        # limit*3 client-side approximation could hide valid records when a
        # user had many sessions on another vehicle.
        items, _ = repository.history_page(uid, limit, None, strategy, vehicle_id)
        return ok([item.to_dict() for item in items])

    @bp.get("/api/smart-charging/history")
    @authenticated
    def history_page(uid):
        limit = min(50, max(1, int(request.args.get("limit", "20"))))
        cursor_raw = request.args.get("cursor", "").strip()
        cursor = None
        if cursor_raw:
            try:
                from datetime import datetime
                cursor = datetime.fromisoformat(cursor_raw.replace("Z", "+00:00"))
            except ValueError:
                return jsonify({"success": False, "error": {"code": "invalidCursor", "message": "Cursor không hợp lệ"}}), 400
        strategy = request.args.get("strategy") or None
        vehicle_id = request.args.get("vehicleId") or None
        items, next_cursor = repository.history_page(uid, limit, cursor, strategy, vehicle_id)
        return ok(
            {"items": [item.to_dict() for item in items], "nextCursor": next_cursor},
            diagnostics={"skippedLegacyDocuments": repository.last_history_skipped},
        )

    @bp.post("/api/smart-charging/off")
    @authenticated
    def off(uid):
        body = request.get_json(silent=True) or {}
        def action():
            session = service.stop(
                uid,
                expected_version=body.get("expectedVersion"),
                user_stop_reason=str(body.get("userStopReason") or "none"),
                vehicle_id=str(body.get("vehicleId") or request.args.get("vehicleId") or "").strip() or None,
            )
            return ok(session.to_dict() if session else None)
        return execute(action)

    @bp.post("/api/smart-charging/on")
    @authenticated
    def on(uid):
        body = request.get_json(silent=True) or {}
        key = request.headers.get("Idempotency-Key", "")
        return execute(lambda: ok(service.manual_on(
            uid,
            int(body.get("durationSeconds") or 0),
            key,
            str(body.get("vehicleId") or "manual"),
            float(body.get("currentSoc") or 0),
        ).to_dict()))

    @bp.post("/api/smart-charging/session/<session_id>/stop")
    @authenticated
    def stop(uid, session_id):
        body = request.get_json(silent=True) or {}
        return execute(lambda: ok(service.stop(
            uid,
            session_id,
            expected_version=body.get("expectedVersion"),
            user_stop_reason=str(body.get("userStopReason") or "none"),
        ).to_dict()))

    @bp.get("/api/smart-charging/personal-profile/<vehicle_id>")
    @authenticated
    def personal_profile(uid, vehicle_id):
        return execute(lambda: ok(service.personal_profile(uid, vehicle_id).to_dict(public=True)))

    @bp.put("/api/smart-charging/personal-profile/<vehicle_id>")
    @authenticated
    def update_personal_profile(uid, vehicle_id):
        body = request.get_json(silent=True) or {}
        return execute(lambda: ok(service.update_personal_consent(
            uid, vehicle_id, bool(body.get("consentEnabled")),
        ).to_dict(public=True)))

    @bp.delete("/api/smart-charging/personal-profile/<vehicle_id>")
    @authenticated
    def delete_personal_profile(uid, vehicle_id):
        def action():
            service.delete_personal_profile(uid, vehicle_id)
            return ok({"deleted": True})
        return execute(action)

    @bp.patch("/api/smart-charging/sessions/<session_id>/actual-soc")
    @authenticated
    def actual_soc(uid, session_id):
        body = request.get_json(silent=True) or {}
        return execute(lambda: ok(service.confirm_actual_soc(
            uid, session_id, float(body.get("actualSoc")),
        ).to_dict()))

    @bp.get("/api/smart-charging/sessions/<session_id>/telemetry")
    @authenticated
    def telemetry(uid, session_id):
        # Repository verifies the ChargeLog owner before returning Firestore data.
        return ok(repository.telemetry(uid, session_id))

    @bp.delete("/api/smart-charging/sessions/<session_id>/privacy-erase")
    @authenticated
    def privacy_erase(uid, session_id):
        body = request.get_json(silent=True) or {}
        def action():
            service.privacy_erase_session(
                uid, session_id, str(body.get("confirmation") or "")
            )
            return ok({"erased": True})
        return execute(action)

    @bp.post("/api/smart-charging/sessions/<session_id>/hide")
    @authenticated
    def hide_session(uid, session_id):
        return execute(lambda: ok(service.hide_session(uid, session_id).to_dict()))

    @bp.post("/api/smart-charging/sessions/<session_id>/telemetry")
    @authenticated
    def record_telemetry(uid, session_id):
        return execute(lambda: ok(service.record_telemetry(
            uid, session_id, request.get_json(silent=True) or {},
        )))

    @bp.post("/api/smart-charging/personal/ingest-session")
    @authenticated
    def ingest_personal_session(uid):
        body = request.get_json(silent=True) or {}
        return execute(lambda: ok(service.ingest_personal_session(
            uid, str(body.get("sessionId") or ""),
        )))

    @bp.get("/api/smart-charging/training-samples")
    @authenticated
    def get_training_samples(uid):
        vehicle_id = str(request.args.get("vehicleId") or "").strip()
        samples = []
        if vehicle_id:
            try:
                samples = repository.training_samples(uid, vehicle_id)
            except Exception as ex:
                print(f"Error reading personal training samples from repo: {ex}")
        if not samples:
            try:
                from ai_server.dataset_manager import load_dataset
                records = load_dataset()
                samples = [
                    {
                        "sessionId": r.get("session_id"),
                        "vehicleId": r.get("vehicle_id", vehicle_id),
                        "startSoc": r.get("start_soc"),
                        "targetSoc": r.get("target_soc", 100.0),
                        "actualSoc": r.get("actual_end_soc", 100.0),
                        "durationSeconds": r.get("duration_seconds"),
                        "gridEnergyWh": r.get("energy_wh"),
                        "ambientTemp": r.get("ambient_temp_c"),
                        "trainingExcluded": r.get("training_excluded", False),
                        "eligibleForTargetTraining": r.get("training_eligible", True),
                        "developerNote": r.get("developer_note", ""),
                        "updatedAt": r.get("updated_at") or r.get("confirmed_at") or r.get("created_at"),
                    }
                    for r in records
                    if not vehicle_id or r.get("vehicle_id") == vehicle_id
                ]
            except Exception as ex:
                print(f"Error falling back to dataset_manager: {ex}")
        return ok({"items": samples})

    @bp.get("/api/smart-charging/developer/training-access")
    @developer
    def developer_training_access(uid):
        return ok({"canEditTrainingData": True})

    @bp.patch("/api/smart-charging/developer/training-samples/<session_id>")
    @developer
    def review_training_sample(uid, session_id):
        body = request.get_json(silent=True) or {}
        vehicle_id = str(body.get("vehicleId") or "").strip()
        if not vehicle_id:
            return jsonify({"success": False, "error": {"code": "invalidVehicle", "message": "Thiếu vehicleId"}}), 400
        note = str(body.get("developerNote") or "").strip()
        if len(note) > 500:
            return jsonify({"success": False, "error": {"code": "noteTooLong", "message": "Ghi chú tối đa 500 ký tự"}}), 400

        def optional_number(key, minimum, maximum):
            value = body.get(key)
            if value is None or value == "":
                return None
            try:
                number = float(value)
            except (TypeError, ValueError) as exc:
                raise SmartChargeError(
                    "invalidTrainingOverride", f"{key} phải là số hợp lệ", 400
                ) from exc
            if not minimum <= number <= maximum:
                raise SmartChargeError("invalidTrainingOverride", f"{key} phải từ {minimum} đến {maximum}", 400)
            return number

        def action():
            updated = repository.review_training_sample(
                uid,
                vehicle_id,
                session_id,
                training_excluded=bool(body.get("trainingExcluded", False)),
                developer_note=note,
                duration_seconds_override=optional_number("durationSecondsOverride", 60, 36000),
                predicted_minutes_override=optional_number("predictedMinutesOverride", 1, 600),
                reviewed_by=uid,
            )
            if updated is None:
                raise SmartChargeError("trainingSampleNotFound", "Không tìm thấy mẫu thuộc xe/tài khoản này", 404)
            repository.append_audit(
                uid,
                "personal_training_sample_reviewed",
                vehicle_id=vehicle_id,
                session_id=session_id,
                training_excluded=bool(body.get("trainingExcluded", False)),
                override_duration=updated.get("trainingDurationSecondsOverride"),
                override_prediction=updated.get("trainingPredictedMinutesOverride"),
            )
            return ok(updated)
        return execute(action)

    return bp
