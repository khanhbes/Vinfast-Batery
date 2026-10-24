"""HTTP surface for Pinova Premium (QA 135)."""
from __future__ import annotations

from flask import Blueprint, jsonify, request

from .entitlements import BillingError


def create_billing_blueprint(*, entitlements, promos, auth_resolver, require_admin, audit=None,
                             user_lookup=None):
    bp = Blueprint("billing", __name__)

    def fail(status, code, message):
        return jsonify({"success": False, "code": code, "userMessage": message,
                        "error": {"code": code, "message": message, "userMessage": message}}), status

    def ok(data):
        return jsonify({"success": True, "data": data})

    def user():
        uid, _email, _role = auth_resolver()
        return uid

    def run(action):
        try:
            return ok(action())
        except BillingError as error:
            return fail(error.status, error.code, error.message)

    def actor():
        return getattr(request, "_uid", "") or ""

    def log(action, entity_id, details):
        if audit:
            audit(action, "billing", entity_id, actor(), getattr(request, "_email", "") or "", details)

    def me_payload(uid):
        summary = entitlements.summary(uid)
        summary["pendingPromo"] = promos.pending(uid)
        return summary

    @bp.get("/api/billing/me")
    def me():
        uid = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        return run(lambda: me_payload(uid))

    @bp.post("/api/billing/trial")
    def trial():
        uid = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")

        def action():
            entitlements.start_trial(uid)
            return me_payload(uid)
        return run(action)

    @bp.post("/api/billing/promo")
    def redeem_promo():
        uid = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        body = request.get_json(silent=True) or {}
        return run(lambda: promos.redeem(uid, body.get("code")))

    @bp.delete("/api/billing/promo")
    def clear_promo():
        uid = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")

        def action():
            promos.clear_pending(uid)
            return {"cleared": True}
        return run(action)

    # -- admin ------------------------------------------------------------
    @bp.get("/api/admin/billing/stats")
    @require_admin
    def stats():
        return run(lambda: {"counts": entitlements.tier_counts(), "enforced": entitlements.enforced})

    @bp.get("/api/admin/billing/user")
    @require_admin
    def find_user():
        query = str(request.args.get("q") or "").strip()
        if not query:
            return fail(400, "missingQuery", "Nhập email hoặc UID.")
        found = user_lookup(query) if user_lookup else {"uid": query, "email": None}
        if not found:
            return fail(404, "userNotFound", "Không tìm thấy tài khoản.")
        uid = found["uid"]
        return run(lambda: {"user": found, "plan": entitlements.summary(uid),
                            "history": entitlements.history(uid), "pendingPromo": promos.pending(uid)})

    @bp.post("/api/admin/billing/grant")
    @require_admin
    def grant():
        body = request.get_json(silent=True) or {}
        uid = str(body.get("uid") or "").strip()
        if not uid:
            return fail(400, "missingUid", "Thiếu UID.")

        def action():
            result = entitlements.grant(uid, body.get("tier"), period=body.get("period"),
                                        days=body.get("days"), actor=actor())
            log("billing_grant", uid, {"tier": result["tier"], "period": body.get("period"),
                                       "days": body.get("days"), "expiresAt": result["expiresAt"]})
            return result
        return run(action)

    @bp.post("/api/admin/billing/revoke")
    @require_admin
    def revoke():
        body = request.get_json(silent=True) or {}
        uid = str(body.get("uid") or "").strip()
        if not uid:
            return fail(400, "missingUid", "Thiếu UID.")

        def action():
            result = entitlements.revoke(uid, actor=actor())
            log("billing_revoke", uid, {})
            return result
        return run(action)

    @bp.get("/api/admin/promos")
    @require_admin
    def list_promos():
        return run(lambda: {"items": promos.list()})

    @bp.post("/api/admin/promos")
    @require_admin
    def create_promo():
        body = request.get_json(silent=True) or {}

        def action():
            item = promos.create(body, actor=actor())
            log("promo_create", item["code"], {"percentOff": item["percentOff"], "validTo": item["validTo"],
                                               "tiers": item["tiers"], "periods": item["periods"]})
            return item
        return run(action)

    @bp.patch("/api/admin/promos/<code>")
    @require_admin
    def update_promo(code):
        body = request.get_json(silent=True) or {}

        def action():
            item = promos.update(code, body, actor=actor())
            log("promo_update", item["code"], {k: body[k] for k in body
                                               if k in ("percentOff", "validTo", "validFrom", "tiers",
                                                        "periods", "active")})
            return item
        return run(action)

    return bp
