from __future__ import annotations

import os
import secrets
from datetime import timedelta
from functools import wraps
from urllib.parse import quote

from flask import Blueprint, jsonify, request

from .models import DeviceBinding, utcnow
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
        binding = service.binding(uid)
        return ok(binding.to_dict() if binding else None)

    @bp.get("/api/shelly/capabilities")
    @authenticated
    def capabilities(uid):
        return ok(service.capabilities(uid))

    @bp.post("/api/shelly/devices/<device_id>/select")
    @authenticated
    def select_device(uid, device_id):
        match = next((item for item in repository.list_bindings(uid) if item.device_id == device_id and item.revoked_at is None), None)
        if not match:
            return jsonify({"success": False, "error": {"code": "deviceNotFound", "message": "Thiết bị không thuộc tài khoản này"}}), 404
        # Single-device v1: revoke the other bindings; never moves ownership.
        for item in repository.list_bindings(uid):
            if item.device_id != device_id and item.revoked_at is None:
                repository.revoke_binding(uid, item.device_id, utcnow())
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
        return execute(lambda: ok(service.status(uid).to_dict()))

    @bp.get("/api/smart-charging/session/current")
    @authenticated
    def current(uid):
        session = service.current(uid)
        active = bool(session and session.state in ("arming", "active"))
        return ok(session.to_dict() if session else None, active=active)

    @bp.get("/api/smart-charging/sessions")
    @authenticated
    def history(uid):
        limit = min(50, max(1, int(request.args.get("limit", "20"))))
        return ok([item.to_dict() for item in repository.history(uid, limit)])

    @bp.post("/api/smart-charging/off")
    @authenticated
    def off(uid):
        def action():
            session = service.stop(uid)
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
        return execute(lambda: ok(service.stop(uid, session_id).to_dict()))

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

    @bp.post("/api/smart-charging/sessions/<session_id>/telemetry")
    @authenticated
    def record_telemetry(uid, session_id):
        return execute(lambda: ok(service.record_telemetry(
            uid, session_id, request.get_json(silent=True) or {},
        )))

    return bp
