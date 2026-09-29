from __future__ import annotations

import os
import secrets
import hashlib
import uuid
from datetime import timedelta
from functools import wraps
from urllib.parse import quote

import requests

from flask import Blueprint, after_this_request, jsonify, request

from .models import DeviceBinding, NONTERMINAL_SESSION_STATES, utcnow
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
        if message == "DEVICE_ALREADY_OWNED":
            return jsonify({"success": False, "error": {"code": "DEVICE_ALREADY_OWNED", "message": "Thiết bị Shelly đã được liên kết với một tài khoản khác"}}), 409
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
        if not str(body.get("cloudAuthKey") or "").strip():
            return "Cần đăng ký Shelly Cloud để lưu credential trong vault máy chủ."
        host = str(body.get("cloudHost") or "").rstrip("/")
        if not repository._valid_cloud_host(host):
            return "Shelly Cloud phải dùng HTTPS trên miền được hỗ trợ"
        try:
            response = requests.post(
                f"{host}/v2/devices/api/get",
                params={"auth_key": str(body.get("cloudAuthKey") or "")},
                json={"ids": [str(body.get("deviceId") or "")], "select": ["status", "settings"]},
                timeout=7,
            )
        except requests.RequestException:
            return "Không thể xác minh Shelly Cloud từ web server"
        if response.status_code in (401, 403):
            return "Authorization Cloud Key không hợp lệ hoặc đã bị thu hồi"
        if response.status_code == 429:
            return "Shelly Cloud đang giới hạn tần suất; hãy thử lại sau"
        if not 200 <= response.status_code < 300:
            return "Shelly Cloud không xác minh được thiết bị này"
        try:
            result = response.json()
        except ValueError:
            return "Shelly Cloud trả dữ liệu không hợp lệ"
        entries = result if isinstance(result, list) else result.get("devices", []) if isinstance(result, dict) else []
        device_id = str(body.get("deviceId") or "").strip()
        device = next((item for item in entries if isinstance(item, dict) and str(item.get("id") or "").lower() == device_id.lower()), None)
        if not device or device.get("online") in (False, 0):
            return "Không tìm thấy thiết bị đang trực tuyến trong tài khoản Shelly Cloud"
        if str(device.get("code") or "").upper() != "S3PL-00112EU" or str(device.get("type") or "").lower() != "relay":
            return "Thiết bị không phải Shelly Plug S Gen3"
        switch = ((device.get("status") or {}).get("switch:0") or {})
        settings = ((device.get("settings") or {}).get("switch:0") or {})
        meter_present = all(field in switch for field in ("apower", "voltage", "current", "aenergy"))
        safe_boot = str(settings.get("initial_state") or "").lower() == "off" and settings.get("auto_on") is False
        body["verification"] = {
            "cloudVerified": True,
            "powerMeterVerified": meter_present,
            "safeBootVerified": safe_boot,
            "noLoadTestVerified": False,
            "verifiedDeviceId": device_id,
            "verifiedModel": "S3PL-00112EU",
            "verificationFingerprint": hashlib.sha256(
                f"{device_id}|S3PL-00112EU|{str(settings.get('initial_state') or '').lower()}|{settings.get('auto_on')}".encode()
            ).hexdigest(),
            "verifiedAt": utcnow().isoformat(),
        }
        body["model"] = "S3PL-00112EU"
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
            provider="vault_cloud",
            connection_mode="server_cloud",
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
        # Cloud credentials never leave the server vault after enrollment.
        return ok(repository.resolve_synced_profile(uid) if profile else None)

    @bp.post("/api/shelly/devices/<device_id>/safety-test")
    @authenticated
    def safety_test(uid, device_id):
        body = request.get_json(silent=True) or {}
        if body.get("confirmedUnplugged") is not True:
            return jsonify({"success": False, "error": {"code": "confirmationRequired", "message": "Confirme que le véhicule et toute charge sont débranchés"}}), 400
        binding = next((item for item in repository.list_bindings(uid) if item.device_id == device_id and item.revoked_at is None), None)
        if not binding or binding.connection_mode != "server_cloud":
            return jsonify({"success": False, "error": {"code": "deviceNotFound", "message": "Shelly non associé à ce compte"}}), 404
        if repository.current_session(uid, device_id=device_id):
            return jsonify({"success": False, "error": {"code": "activeSessionConflict", "message": "Une session de charge est active"}}), 409
        operation_id = str(body.get("operationId") or "").strip()
        if not operation_id or len(operation_id) > 160:
            return jsonify({"success": False, "error": {"code": "invalidOperationId", "message": "Identifiant de contrôle invalide"}}), 400
        if not repository.claim_device_session(uid, device_id, operation_id):
            return jsonify({"success": False, "error": {"code": "deviceBusy", "message": "Le Shelly est déjà utilisé"}}), 409
        try:
            result = service.provider.run_no_load_test(binding)
            if result.get("noLoadTestVerified") is not True or result.get("relayOffVerified") is not True:
                raise RuntimeError("safetyVerificationFailed")
            evidence = {
                "verifiedDeviceId": device_id,
                "verifiedModel": binding.model,
                "verificationFingerprint": hashlib.sha256(f"{device_id}|{binding.model}|off|false".encode()).hexdigest(),
                "cloudVerified": True,
                "powerMeterVerified": True,
                "safeBootVerified": True,
                "noLoadTestVerified": True,
            }
            binding.power_meter_verified = True
            binding.safe_boot_verified = True
            binding.no_load_test_verified = True
            binding.online = True
            binding.last_verified_at = utcnow()
            repository.save_binding(uid, binding)
            repository.verify_synced_profile(uid, device_id, evidence)
            repository.append_audit(uid, "shelly_safety_test_passed", device_id=device_id, operation_id=operation_id)
            return ok({"verified": True, "result": result})
        except Exception as error:
            repository.append_audit(uid, "shelly_safety_test_failed", device_id=device_id, operation_id=operation_id, code=getattr(error, "code", "verificationFailed"))
            return jsonify({"success": False, "error": {"code": getattr(error, "code", "verificationFailed"), "message": "Shelly safety test did not complete"}}), 503
        finally:
            # A failed safety test may have left the relay uncertain. Only a
            # verified-OFF result releases the operation lease.
            if locals().get("result", {}).get("relayOffVerified") is True:
                repository.release_device_session(uid, device_id, operation_id)

    @bp.post("/api/shelly/profiles/<device_id>/verify")
    @authenticated
    def verify_profile(uid, device_id):
        # Client-reported flags are not safety evidence. Verification is only
        # accepted through the server-side confirmed no-load test endpoint.
        return jsonify({"success": False, "error": {
            "code": "serverSafetyTestRequired",
            "message": "Hãy chạy kiểm tra an toàn trực tiếp qua máy chủ Shelly.",
        }}), 409
        body = request.get_json(silent=True) or {}
        profile = repository.verify_synced_profile(uid, device_id, body)
        if profile is None:
            return jsonify({"success": False, "error": {"code": "profileNotFound", "message": "Không tìm thấy cấu hình Shelly"}}), 404
        return ok(profile)

    def unlink_owned_device(uid, device_id):
        binding = next((item for item in repository.list_bindings(uid)
                        if item.device_id == device_id and item.revoked_at is None), None)
        if binding is None:
            return ok({"revoked": False})
        if repository.current_session(uid, device_id=device_id):
            return jsonify({"success": False, "error": {
                "code": "activeSessionConflict",
                "message": "Hãy dừng phiên sạc và xác minh relay OFF trước khi ngắt liên kết.",
            }}), 409
        try:
            if binding.provider != "vault_cloud" or binding.connection_mode != "server_cloud":
                raise RuntimeError("liveReadbackUnavailable")
            status = service.provider.get_status(binding)
            if status.relay:
                return jsonify({"success": False, "error": {
                    "code": "activeSessionConflict",
                    "message": "Relay vẫn đang bật. Hãy tắt và xác minh lại trước khi ngắt liên kết.",
                }}), 409
        except Exception:
            return jsonify({"success": False, "error": {
                "code": "relayUnverified",
                "message": "Không xác minh được relay OFF; yêu cầu ngắt liên kết đã bị chặn.",
            }}), 409
        repository.revoke_synced_profile(uid, device_id)
        repository.revoke_binding(uid, device_id, utcnow())
        if not repository.release_device_owner(uid, device_id):
            return jsonify({"success": False, "error": {
                "code": "ownershipReleaseFailed",
                "message": "Chưa thể giải phóng quyền sở hữu thiết bị.",
            }}), 503
        return ok({"revoked": True})

    @bp.delete("/api/shelly/profiles/<device_id>")
    @authenticated
    def revoke_profile(uid, device_id):
        return unlink_owned_device(uid, device_id)

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

    @bp.post("/api/shelly/devices/claim")
    @authenticated
    def claim_device(uid):
        body = request.get_json(silent=True) or {}
        device_id = str(body.get("deviceId") or "").strip()
        model = str(body.get("model") or "").strip().upper()
        if not device_id or model != "S3PL-00112EU":
            return jsonify({"success": False, "error": {"code": "unsupportedDevice", "message": "Shelly Plug S Gen3 chưa được xác minh"}}), 400
        if repository.db is None:
            return jsonify({"success": False, "error": {"code": "ownershipUnavailable", "message": "Dịch vụ xác minh quyền sở hữu đang ngoại tuyến"}}), 503
        if not repository.claim_device_owner(uid, device_id):
            return jsonify({"success": False, "error": {"code": "DEVICE_ALREADY_OWNED", "message": "Thiết bị Shelly đã được liên kết với một tài khoản khác"}}), 409
        binding = DeviceBinding(device_id=device_id, display_name="Shelly Plug S Gen3", model=model, generation=3, provider="lan_direct", connection_mode="advanced_direct", online=False, owner_uid=uid)
        repository.save_binding(uid, binding)
        return ok({"claimed": True})

    @bp.post("/api/shelly/devices/<device_id>/authorize")
    @authenticated
    def authorize_device(uid, device_id):
        body = request.get_json(silent=True) or {}
        operation_id = str(body.get("operationId") or "").strip()
        if not operation_id or len(operation_id) > 160:
            return jsonify({"success": False, "error": {"code": "invalidOperationId", "message": "Thiếu mã thao tác"}}), 400
        if not repository.device_owned_by(uid, device_id):
            return jsonify({"success": False, "error": {"code": "DEVICE_ALREADY_OWNED", "message": "Thiết bị không thuộc tài khoản này"}}), 409
        binding = next((item for item in repository.list_bindings(uid) if item.device_id == device_id and item.revoked_at is None), None)
        if binding is None:
            return jsonify({"success": False, "error": {"code": "deviceNotFound", "message": "Shelly chưa được liên kết"}}), 404
        if not repository.claim_device_session(uid, device_id, operation_id):
            return jsonify({"success": False, "error": {
                "code": "deviceBusy",
                "message": "Thiết bị đang được một thao tác khác giữ quyền điều khiển.",
            }}), 409
        repository.append_audit(uid, "shelly_control_authorized", device_id=device_id, operation_id=operation_id)
        return ok({"authorized": True})

    @bp.post("/api/shelly/devices/<device_id>/release-control")
    @authenticated
    def release_device_control(uid, device_id):
        body = request.get_json(silent=True) or {}
        operation_id = str(body.get("operationId") or "").strip()
        if not operation_id or len(operation_id) > 160 or body.get("relayOffVerified") is not True:
            return jsonify({"success": False, "error": {
                "code": "offReadbackRequired",
                "message": "Chỉ giải phóng thao tác sau khi relay OFF đã được đọc lại.",
            }}), 400
        if not repository.device_owned_by(uid, device_id):
            return jsonify({"success": False, "error": {"code": "deviceNotFound", "message": "Shelly không thuộc tài khoản này."}}), 404
        if repository.current_session(uid, device_id=device_id):
            return jsonify({"success": False, "error": {"code": "activeSessionConflict", "message": "Phiên sạc vẫn đang hoạt động."}}), 409
        repository.release_device_session(uid, device_id, operation_id)
        repository.append_audit(uid, "shelly_control_released", device_id=device_id, operation_id=operation_id)
        return ok({"released": True})

    @bp.delete("/api/shelly/device")
    @authenticated
    def revoke(uid):
        binding = service.binding(uid)
        if not binding:
            return ok(None)
        return unlink_owned_device(uid, binding.device_id)

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

    @bp.get("/api/smart-charging/live")
    @authenticated
    def live(uid):
        return execute(lambda: ok(service.live(uid, request.args.get("vehicleId") or None)))

    @bp.get("/api/smart-charging/session/current")
    @authenticated
    def current(uid):
        session = service.current(uid, request.args.get("vehicleId") or None)
        active = bool(session and session.state in NONTERMINAL_SESSION_STATES)
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
        try:
            limit = min(120, max(1, int(request.args.get("limit", "120"))))
        except ValueError:
            return jsonify({"success": False, "error": {"code": "invalidLimit", "message": "limit không hợp lệ"}}), 400
        return ok(repository.telemetry(
            uid,
            session_id,
            after=request.args.get("after") or None,
            limit=limit,
        ))

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

    # ── Connection Code System ──────────────────────────────────────

    from .connection_codes import ConnectionCodeStore
    code_store = ConnectionCodeStore(getattr(repository, 'db', None))

    @bp.get("/api/admin/shelly-devices")
    @developer
    def admin_shelly_devices(uid):
        """List all registered Shelly devices across all users with their pairing codes."""
        return ok(code_store.list_devices())

    @bp.post("/api/admin/shelly-devices")
    @developer
    def admin_save_shelly_device(uid):
        """Save a dedicated Shelly device and automatically generate a pairing code."""
        body = request.get_json(silent=True) or {}
        device_id = str(body.get("deviceId") or "").strip()
        if not device_id:
            return jsonify({"success": False, "error": {"code": "missingDeviceId", "message": "Thiếu Device ID của Shelly"}}), 400

        dev, code_entry = code_store.save_device_and_generate_code(
            device_id=device_id,
            device_name=str(body.get("deviceName") or body.get("displayName") or "Shelly Plug S Gen3"),
            model=str(body.get("model") or "S3PL-00112EU"),
            cloud_host=str(body.get("cloudHost") or "https://shelly-104-eu.shelly.cloud"),
            cloud_auth_key=str(body.get("cloudAuthKey") or ""),
            lan_address=body.get("lanAddress"),
            local_password=body.get("localPassword"),
            note=str(body.get("note") or ""),
            created_by=uid,
            expires_hours=int(body.get("expiresHours") or 720),
            max_redemptions=1,
        )
        return ok({
            "device": dev,
            "code": code_entry.code,
            "codeEntry": code_entry.to_public_dict(),
        })

    @bp.delete("/api/admin/shelly-devices/<device_id>")
    @developer
    def admin_delete_shelly_device(uid, device_id):
        """Delete a Shelly device from inventory and revoke its codes."""
        code_store.delete_device(device_id)
        return ok({"deleted": True})

    @bp.post("/api/admin/shelly-devices/<device_id>/generate-code")
    @developer
    def admin_generate_code_for_device(uid, device_id):
        """Generate a fresh pairing code for an existing device."""
        body = request.get_json(silent=True) or {}
        dev = code_store._devices.get(device_id) or {}
        secrets = code_store.device_secrets(device_id)
        entry = code_store.generate(
            device_id=device_id,
            device_name=str(body.get("deviceName") or dev.get("displayName") or "Shelly"),
            model=str(body.get("model") or dev.get("model") or "S3PL-00112EU"),
            cloud_host=str(body.get("cloudHost") or secrets.get("cloudHost") or dev.get("cloudHost") or "https://shelly-104-eu.shelly.cloud"),
            cloud_auth_key=str(body.get("cloudAuthKey") or secrets.get("cloudAuthKey") or ""),
            lan_address=body.get("lanAddress") or secrets.get("lanAddress") or dev.get("lanAddress"),
            local_password=body.get("localPassword") or secrets.get("localPassword"),
            created_by=uid,
            expires_hours=int(body.get("expiresHours") or 720),
            max_redemptions=1,
            note=str(body.get("note") or dev.get("note") or ""),
        )
        return ok(entry.to_public_dict())

    @bp.get("/api/admin/connection-codes")
    @developer
    def admin_list_codes(uid):
        """List all connection codes (admin only)."""
        return ok([entry.to_public_dict() for entry in code_store.list_all()])

    @bp.post("/api/admin/connection-codes")
    @developer
    def admin_generate_code(uid):
        """Generate a new connection code for a Shelly device."""
        body = request.get_json(silent=True) or {}
        device_id = str(body.get("deviceId") or "").strip()
        if not device_id:
            return jsonify({"success": False, "error": {"code": "missingDeviceId", "message": "Thiếu Device ID"}}), 400
        entry = code_store.generate(
            device_id=device_id,
            device_name=str(body.get("deviceName") or "Shelly Plug S Gen3"),
            model=str(body.get("model") or "S3PL-00112EU"),
            cloud_host=str(body.get("cloudHost") or ""),
            cloud_auth_key=str(body.get("cloudAuthKey") or ""),
            lan_address=body.get("lanAddress"),
            local_password=body.get("localPassword"),
            created_by=uid,
            expires_hours=int(body.get("expiresHours") or 720),
            max_redemptions=1,
            note=str(body.get("note") or ""),
        )
        return ok(entry.to_public_dict())

    @bp.delete("/api/admin/connection-codes/<code>")
    @developer
    def admin_revoke_code(uid, code):
        """Revoke a connection code."""
        if not code_store.revoke(code):
            return jsonify({"success": False, "error": {"code": "codeNotFound", "message": "Mã không tồn tại"}}), 404
        return ok({"revoked": True})

    @bp.post("/api/shelly/redeem-code")
    @authenticated
    def redeem_code(uid):
        """User redeems a connection code to get a Shelly profile."""
        body = request.get_json(silent=True) or {}
        code = str(body.get("code") or "").strip().upper()
        if len(code) != 6:
            return jsonify({"success": False, "error": {"code": "invalidCode", "message": "Mã kết nối không hợp lệ"}}), 400
        entry, error = code_store.redeem_atomic(code, uid)
        if error:
            return jsonify({"success": False, "error": {"code": "redemptionFailed", "message": error}}), 422
        # Save the profile for this user via the existing vault mechanism
        profile_data = entry.to_profile_dict()
        profile_data["source"] = "connection_code"
        cloud_error = verify_web_cloud_profile(profile_data)
        if cloud_error:
            return jsonify({"success": False, "error": {"code": "cloudVerificationFailed", "message": cloud_error}}), 422
        try:
            metadata = repository.save_synced_profile(uid, profile_data, None)
        except (ProfileVaultError, PermissionError, RuntimeError, ValueError) as error:
            return profile_error(error)
        repository.save_binding(uid, DeviceBinding(
            device_id=entry.device_id,
            display_name=entry.device_name,
            model=entry.model,
            generation=3,
            provider="vault_cloud",
            connection_mode="server_cloud",
            online=bool(metadata.get("cloudVerified")),
            shared=True,
            power_meter_verified=bool(metadata.get("powerMeterVerified")),
            safe_boot_verified=bool(metadata.get("safeBootVerified")),
            no_load_test_verified=False,
            last_verified_at=utcnow(),
        ))
        return ok({
            "profile": metadata,
            "deviceId": entry.device_id,
            "deviceName": entry.device_name,
            "model": entry.model,
        })

    return bp
