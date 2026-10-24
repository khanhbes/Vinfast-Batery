"""HTTP surface for support tickets (QA 135)."""
from __future__ import annotations

from flask import Blueprint, jsonify, request

from .tickets import SupportError


def create_support_blueprint(*, service, auth_resolver, require_admin, tier_of=None, audit=None):
    bp = Blueprint("support", __name__)

    def fail(status, code, message):
        return jsonify({"success": False, "code": code, "userMessage": message,
                        "error": {"code": code, "message": message, "userMessage": message}}), status

    def run(action):
        try:
            return jsonify({"success": True, "data": action()})
        except SupportError as error:
            return fail(error.status, error.code, error.message)

    def user():
        return auth_resolver()

    @bp.post("/api/support/tickets")
    def create():
        uid, email, _role = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        body = request.get_json(silent=True) or {}
        tier = "free"
        if tier_of is not None:
            try:
                tier = tier_of(uid)
            except Exception:
                tier = "free"
        return run(lambda: service.create(uid, email, body, tier=tier))

    @bp.get("/api/support/tickets")
    def mine():
        uid, _email, _role = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        return run(lambda: {"items": service.mine(uid)})

    @bp.get("/api/support/tickets/<ticket_id>")
    def get_mine(ticket_id):
        uid, _email, _role = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        return run(lambda: service.get_mine(uid, ticket_id))

    @bp.post("/api/support/tickets/<ticket_id>/replies")
    def reply(ticket_id):
        uid, _email, _role = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        body = request.get_json(silent=True) or {}
        return run(lambda: service.user_reply(uid, ticket_id, body.get("text")))

    # -- admin ------------------------------------------------------------
    @bp.get("/api/admin/support")
    @require_admin
    def admin_list():
        status = request.args.get("status") or None
        return run(lambda: {"items": service.admin_list(status), "unread": service.unread_count(),
                            "emailConfigured": bool(service.mailer and service.mailer.configured)})

    @bp.get("/api/admin/support/<ticket_id>")
    @require_admin
    def admin_get(ticket_id):
        return run(lambda: service.admin_get(ticket_id))

    @bp.post("/api/admin/support/<ticket_id>/reply")
    @require_admin
    def admin_reply(ticket_id):
        body = request.get_json(silent=True) or {}
        actor = getattr(request, "_uid", "") or ""

        def action():
            result = service.admin_reply(ticket_id, body.get("text"), body.get("status"), actor=actor)
            if audit:
                audit("support_reply", "supportTickets", ticket_id, actor,
                      getattr(request, "_email", "") or "",
                      {"status": result["status"], "length": len(str(body.get("text") or ""))})
            return result
        return run(action)

    return bp
