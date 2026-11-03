"""HTTP surface for Pinova Premium (QA 135)."""
from __future__ import annotations

from html import escape

from flask import Blueprint, Response, jsonify, request

from .entitlements import BillingError


TERMS_PAGE = """<!DOCTYPE html><html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Điều khoản gói Pinova Premium</title>
<style>body{font:16px/1.6 system-ui,sans-serif;max-width:640px;margin:0 auto;padding:24px 16px;color:#16181a;
background:#f6f7f5}h1{font-size:1.5rem}li{margin:6px 0}</style></head><body>
<h1>Điều khoản gói Pinova Premium</h1>
<ol>
<li><strong>Trả trước, không tự gia hạn.</strong> Gói Pro và Ultra mua theo 1 tháng (30 ngày) hoặc 1 năm
(365 ngày). Pinova không tự trừ tiền khi hết hạn; app nhắc bạn trước 3 ngày.</li>
<li><strong>Giá.</strong> Giá hiện trong app trước khi thanh toán là số tiền bạn trả.</li>
<li><strong>Thanh toán.</strong> Bản Pinova tải trực tiếp thanh toán qua ví MoMo; bản trên Google Play hoặc
App Store thanh toán qua cửa hàng đó. Gói bật ngay khi cổng thanh toán xác nhận.</li>
<li><strong>Gia hạn.</strong> Mua tiếp cùng gói thì thời gian mới được cộng vào sau ngày hết hạn hiện tại.</li>
<li><strong>Nâng gói.</strong> Từ Pro lên Ultra: giá trị phần Pro đã trả mà chưa dùng được trừ vào giá Ultra,
Ultra bắt đầu ngay. Phần dư (nếu có) được đổi thành ngày Ultra. Đổi từ Ultra xuống Pro được sau khi Ultra hết hạn.</li>
<li><strong>Mã khuyến mãi.</strong> Mỗi tài khoản dùng một mã một lần; mã có thể giới hạn số lượt và thời hạn.</li>
<li><strong>Hoàn tiền.</strong> Nếu đã bị trừ tiền mà gói chưa bật, hoặc thanh toán nhầm, hãy gửi yêu cầu ở
Cài đặt → Trợ giúp kèm mã đơn (trong Lịch sử thanh toán). Pinova kiểm tra và hoàn tiền qua kênh đã thanh toán
khi yêu cầu hợp lệ; gói của đơn được hoàn sẽ kết thúc.</li>
<li><strong>An toàn luôn miễn phí.</strong> Dừng sạc, các cảnh báo an toàn và tính năng cơ bản không phụ thuộc
gói. Hết gói không ngắt phiên sạc đang chạy.</li>
<li><strong>Xóa tài khoản.</strong> Khi xóa tài khoản, thời gian gói còn lại không được hoàn. Bản ghi giao dịch
(mã đơn, số tiền, thời gian) được giữ theo quy định kế toán.</li>
</ol>
</body></html>"""


def create_billing_blueprint(*, entitlements, promos, auth_resolver, require_admin, audit=None,
                             user_lookup=None, payments=None):
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
        if payments is not None:
            try:
                payments.reconcile_user(uid)
            except Exception:
                pass  # a MoMo hiccup must not hide the plan
        summary = entitlements.summary(uid)
        summary["pendingPromo"] = promos.pending(uid)
        summary["payments"] = payments.channels() if payments is not None else {"momo": False}
        return summary

    def no_payments():
        return fail(503, "paymentUnavailable", "Thanh toán đang tạm đóng. Bạn thử lại sau.")

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

    # -- payments (QA 145) -------------------------------------------------
    @bp.post("/api/billing/quote")
    def quote():
        uid = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        if payments is None:
            return no_payments()
        body = request.get_json(silent=True) or {}
        return run(lambda: payments.quote(uid, body.get("tier"), body.get("period")))

    @bp.post("/api/billing/checkout")
    def checkout():
        uid = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        if payments is None:
            return no_payments()
        body = request.get_json(silent=True) or {}

        def action():
            order = payments.checkout(uid, body.get("tier"), body.get("period"))
            return {"order": order, "plan": me_payload(uid) if order["status"] == "paid" else None}
        return run(action)

    @bp.get("/api/billing/orders")
    def my_orders():
        uid = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        if payments is None:
            return ok({"items": []})
        return run(lambda: {"items": payments.orders(uid)})

    @bp.get("/api/billing/orders/<order_id>")
    def my_order(order_id):
        uid = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        if payments is None:
            return no_payments()

        def action():
            order = payments.status(uid, order_id)
            return {"order": order, "plan": me_payload(uid) if order["status"] == "paid" else None}
        return run(action)

    @bp.post("/api/billing/momo/ipn")
    def momo_ipn():
        """MoMo server-to-server result; the signature is the only auth."""
        if payments is None:
            return fail(503, "paymentUnavailable", "Thanh toán đang tạm đóng.")
        if not payments.ipn(request.get_json(silent=True) or {}):
            return fail(400, "badSignature", "Chữ ký không hợp lệ.")
        return "", 204

    @bp.get("/thanh-toan/ket-qua")
    def momo_return():
        """MoMo's redirectUrl: the app reads the result itself when it is
        back in front; this page only sends the user back."""
        result = str(request.args.get("resultCode") or "")
        done = result == "0"
        title = "Đã thanh toán" if done else "Chưa hoàn tất thanh toán" if result else "Quay lại Pinova"
        note = ("Gói của bạn sẽ bật ngay khi MoMo xác nhận." if done else
                "Bạn có thể thử lại trong app Pinova." if result else "Mở lại app để xem kết quả.")
        page = f"""<!DOCTYPE html><html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Pinova</title>
<style>body{{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
background:#050506;color:#F2F2F0;font-family:system-ui,sans-serif;text-align:center}}
main{{padding:32px;max-width:420px}}p{{color:#9A9EA5;line-height:1.5}}
a{{display:inline-block;margin-top:16px;padding:14px 28px;border-radius:28px;background:#F2F2F0;
color:#050506;text-decoration:none;font-weight:600}}</style></head><body><main>
<h1>{escape(title)}</h1><p>{escape(note)}</p>
<a href="intent:#Intent;package=com.bes.vinbatery;end">Mở lại Pinova</a></main></body></html>"""
        return Response(page, mimetype="text/html", headers={
            "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'",
            "Cache-Control": "no-store"})

    @bp.get("/dieu-khoan-premium")
    def premium_terms():
        """Public terms for paid plans (QA 145; wording for the owner to review)."""
        return Response(TERMS_PAGE, mimetype="text/html", headers={
            "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'",
            "Cache-Control": "public, max-age=3600"})

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
                                                        "periods", "active", "maxUses")})
            return item
        return run(action)

    @bp.get("/api/admin/billing/orders")
    @require_admin
    def admin_orders():
        if payments is None:
            return ok({"items": [], "monthRevenue": 0, "channels": {"momo": False}})
        status = str(request.args.get("status") or "").strip() or None
        return run(lambda: payments.admin_orders(status))

    @bp.post("/api/admin/billing/orders/<order_id>/refund")
    @require_admin
    def admin_refund(order_id):
        if payments is None:
            return no_payments()

        def action():
            order = payments.refund(order_id, actor=actor())
            log("payment_refund", order_id, {"amount": order["amount"], "planRevoked": order.get("planRevoked")})
            return order
        return run(action)

    @bp.post("/api/admin/billing/orders/<order_id>/check")
    @require_admin
    def admin_check(order_id):
        if payments is None:
            return no_payments()
        return run(lambda: payments.check(order_id))

    return bp
