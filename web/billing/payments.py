"""Paying for Pro/Ultra (QA 145).

The server prices every order; the app only shows the quote. Plans are
prepaid: buying the plan that is running adds a period after its end, and
moving Pro → Ultra turns what is left of the paid Pro into money off Ultra
(any credit above the price becomes extra Ultra days). Moving down waits for
the running plan to end.

``paymentOrders/{orderId}`` holds the order and ``users/{uid}/paymentOrders``
a copy for the account's own list; no Firestore rule matches either, so only
this server reads or writes them. An order is fulfilled once: a create-once
marker guards the IPN, the status check and the admin page running at the
same time, and ``EntitlementService.apply_purchase`` ignores an order it has
already applied.
"""
from __future__ import annotations

import os
import secrets
import threading
from datetime import datetime, timedelta, timezone

from . import features
from .entitlements import BillingError, _iso, _utc
from .momo import MomoError

ORDER_MINUTES = 15
ORDERS_PER_HOUR = 10
MIN_AMOUNT = 1000
QUERY_AFTER_SECONDS = 10
# MoMo result codes that end an order without payment.
FINAL_FAILURES = {1001, 1002, 1003, 1004, 1005, 1006, 1007, 1017, 1026, 1080, 1081}
PENDING_CODES = {1000, 7000, 7002, 9000}
COLLECTION = "paymentOrders"
_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def payments_enabled(env=None) -> bool:
    env = os.environ if env is None else env
    return str(env.get("PAYMENTS_ENABLED", "false")).strip().lower() in ("1", "true", "yes", "on")


def _thousand(value: float) -> int:
    return int(value) // 1000 * 1000


class PaymentService:
    def __init__(self, *, entitlements, promos, momo=None, db=None, clock=None, enabled=None,
                 public_base_url: str | None = None, audit=None):
        self.entitlements = entitlements
        self.promos = promos
        self.momo = momo
        self.db = db
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        self.enabled = payments_enabled() if enabled is None else bool(enabled)
        base = public_base_url if public_base_url is not None else os.environ.get("PAYMENT_PUBLIC_BASE_URL", "")
        self.public_base_url = str(base or "").rstrip("/")
        self.audit = audit
        self._orders: dict[str, dict] = {}
        self._claims: set[str] = set()
        self._lock = threading.Lock()

    @property
    def momo_ready(self) -> bool:
        return bool(self.enabled and self.momo is not None and self.public_base_url)

    def channels(self) -> dict:
        return {"momo": self.momo_ready, "sandbox": bool(self.momo is not None and self.momo.sandbox)}

    # -- storage ----------------------------------------------------------
    def _ref(self, order_id: str):
        return self.db.collection(COLLECTION).document(order_id)

    def _user_ref(self, uid: str, order_id: str):
        return self.db.collection("users").document(uid).collection(COLLECTION).document(order_id)

    def _get(self, order_id: str) -> dict | None:
        if self.db is None:
            with self._lock:
                item = self._orders.get(order_id)
                return dict(item) if item else None
        snapshot = self._ref(order_id).get()
        return (snapshot.to_dict() or {}) if snapshot.exists else None

    def _put(self, order: dict) -> None:
        if self.db is None:
            with self._lock:
                self._orders[order["orderId"]] = dict(order)
            return
        self._ref(order["orderId"]).set(order)
        self._user_ref(order["uid"], order["orderId"]).set(self._summary_fields(order))

    def _update(self, order: dict, changes: dict) -> dict:
        order = {**order, **changes, "updatedAt": self.clock()}
        self._put(order)
        return order

    @staticmethod
    def _summary_fields(order: dict) -> dict:
        keys = ("orderId", "uid", "tier", "period", "days", "base", "promoCode", "percentOff",
                "credit", "extraDays", "amount", "status", "channel", "method", "transId",
                "createdAt", "updatedAt", "paidAt", "refundedAt", "expiresAt")
        return {k: order.get(k) for k in keys if k in order}

    def _user_orders(self, uid: str, limit: int = 20) -> list[dict]:
        if self.db is None:
            with self._lock:
                rows = [dict(o) for o in self._orders.values() if o.get("uid") == uid]
        else:
            query = (self.db.collection("users").document(uid).collection(COLLECTION)
                     .order_by("createdAt", direction="DESCENDING").limit(limit))
            rows = [s.to_dict() or {} for s in query.stream()]
        rows.sort(key=lambda r: _utc(r.get("createdAt")) or datetime.min.replace(tzinfo=timezone.utc),
                  reverse=True)
        return rows[:limit]

    def _claim(self, order_id: str) -> bool:
        """Create-once marker: only one caller fulfils an order."""
        if self.db is None:
            with self._lock:
                if order_id in self._claims:
                    return False
                self._claims.add(order_id)
                return True
        try:
            self._ref(order_id).collection("events").document("fulfilled").create({"at": self.clock()})
            return True
        except Exception as error:
            if type(error).__name__ in ("AlreadyExists", "Conflict"):
                return False
            raise

    def _claimed_at(self, order_id: str):
        if self.db is None:
            return None
        snapshot = self._ref(order_id).collection("events").document("fulfilled").get()
        return _utc((snapshot.to_dict() or {}).get("at")) if snapshot.exists else None

    def _log(self, action: str, order_id: str, details: dict) -> None:
        if self.audit:
            try:
                self.audit(action, "billing", order_id, "momo", "", details)
            except Exception:
                pass

    # -- pricing ----------------------------------------------------------
    def _promo_for(self, uid: str, tier: str, period: str) -> dict | None:
        quote = self.promos.pending(uid)
        if not quote or tier not in (quote.get("tiers") or []) or period not in (quote.get("periods") or []):
            return None
        code = quote.get("code")
        data = self.promos._get(code)
        if not data or self.promos.public(data)["state"] != "active":
            return None
        try:
            self.promos.check_usable(uid, code, data)
        except BillingError:
            return None
        return {"code": code, "percentOff": int(data.get("percentOff") or 0)}

    def quote(self, uid: str, tier, period) -> dict:
        tier = str(tier or "").lower()
        period = str(period or "").lower()
        if tier not in features.PAID_TIERS:
            raise BillingError("invalidTier", "Gói phải là Pro hoặc Ultra.")
        if period not in features.PERIODS:
            raise BillingError("invalidPeriod", "Kỳ hạn phải là tháng hoặc năm.")
        now = self.clock()
        base = features.PRICES[tier][period]
        period_days = features.PERIOD_DAYS[period]
        current = self.entitlements.state(uid, fresh=True)
        running = current["tier"] != "free" and current["status"] == "active"
        expires = _utc(current.get("expiresAt"))
        if running and features.RANK[tier] < features.RANK[current["tier"]]:
            day = expires.astimezone(timezone(timedelta(hours=7))).strftime("%d/%m/%Y") if expires else ""
            raise BillingError("downgradeLater",
                               f"Gói {current['tier'].capitalize()} còn hạn tới {day}. "
                               f"Bạn đổi sang {tier.capitalize()} được sau ngày đó.", 409)
        promo = self._promo_for(uid, tier, period)
        price = features.discounted(base, promo["percentOff"]) if promo else base
        credit = 0
        kind = "new"
        if running and current["tier"] == tier:
            kind = "extend"
        elif running and current["tier"] != tier:
            kind = "upgrade"
            paid = self.entitlements.paid_state(uid)
            span_end, span_start = paid["expiresAt"], paid["paidFrom"]
            if (paid["source"] in ("momo", "store") and paid["paidAmount"] > 0 and span_end and span_start
                    and span_end > now and span_end > span_start):
                left = (span_end - now).total_seconds() / (span_end - span_start).total_seconds()
                credit = _thousand(paid["paidAmount"] * min(1.0, left))
        amount = price - credit
        extra_days = 0
        if amount < 0:
            extra_days = int(-amount // (base / period_days))
            amount = 0
        amount = _thousand(amount)
        if amount < MIN_AMOUNT:
            amount = 0
        days = period_days + extra_days
        start = max(now, expires) if kind == "extend" and expires else now
        return {
            "tier": tier, "period": period, "kind": kind, "base": base,
            "promoCode": promo["code"] if promo else None,
            "percentOff": promo["percentOff"] if promo else 0,
            "afterPromo": price, "credit": credit, "extraDays": extra_days, "days": days,
            "amount": amount, "free": amount == 0,
            "startsAt": _iso(start), "newExpiresAt": _iso(start + timedelta(days=days)),
            "channels": self.channels(),
        }

    # -- orders -----------------------------------------------------------
    def _new_id(self) -> str:
        now = self.clock().astimezone(timezone(timedelta(hours=7)))
        return "PNV" + now.strftime("%y%m%d%H%M%S") + "".join(secrets.choice(_ALPHABET) for _ in range(6))

    def checkout(self, uid: str, tier, period) -> dict:
        quote = self.quote(uid, tier, period)
        now = self.clock()
        recent = self._user_orders(uid, limit=ORDERS_PER_HOUR + 5)
        if not quote["free"]:
            if not self.momo_ready:
                raise BillingError("paymentUnavailable", "Thanh toán đang tạm đóng. Bạn thử lại sau.", 503)
            for order in recent:
                if (order.get("status") == "pending" and order.get("tier") == quote["tier"]
                        and order.get("period") == quote["period"] and order.get("amount") == quote["amount"]
                        and order.get("promoCode") == quote["promoCode"]
                        and (_utc(order.get("expiresAt")) or now) > now + timedelta(minutes=2)):
                    full = self._get(order["orderId"]) or order
                    return self.public(full, links=True)
        hour_ago = now - timedelta(hours=1)
        if sum(1 for o in recent if (_utc(o.get("createdAt")) or now) > hour_ago) >= ORDERS_PER_HOUR:
            raise BillingError("tooManyOrders", "Bạn đã tạo nhiều đơn thanh toán. Thử lại sau 1 giờ.", 429)
        order_id = self._new_id()
        order = {
            "orderId": order_id, "uid": uid, "tier": quote["tier"], "period": quote["period"],
            "kind": quote["kind"], "days": quote["days"], "base": quote["base"],
            "promoCode": quote["promoCode"], "percentOff": quote["percentOff"],
            "credit": quote["credit"], "extraDays": quote["extraDays"], "amount": quote["amount"],
            "status": "pending", "channel": "momo", "method": "free" if quote["free"] else "momo",
            "createdAt": now, "updatedAt": now, "expiresAt": now + timedelta(minutes=ORDER_MINUTES),
        }
        if quote["free"]:
            self._put(order)
            self._fulfil(order, trans_id=None)
            return self.public(self._get(order_id) or order)
        label = "Pro" if quote["tier"] == "pro" else "Ultra"
        try:
            links = self.momo.create(
                order_id=order_id, amount=quote["amount"],
                order_info=f"Pinova {label} {'1 năm' if quote['period'] == 'year' else '1 tháng'}",
                redirect_url=f"{self.public_base_url}/thanh-toan/ket-qua?orderId={order_id}",
                ipn_url=f"{self.public_base_url}/api/billing/momo/ipn", expire_minutes=ORDER_MINUTES)
        except MomoError as error:
            self._log("payment_create_failed", order_id, {"code": error.code, "resultCode": error.result_code})
            raise BillingError("paymentUnavailable", "Chưa tạo được đơn MoMo. Bạn thử lại sau.", 502) from None
        order.update(links)
        self._put(order)
        return self.public(order, links=True)

    def _fulfil(self, order: dict, *, trans_id, pay_type=None) -> dict:
        order_id = order["orderId"]
        if order.get("status") == "paid":
            return order
        if not self._claim(order_id):
            claimed = self._claimed_at(order_id)
            fresh = self._get(order_id) or order
            # Another caller is fulfilling it; a marker left by a crash more
            # than a minute ago is finished here (apply_purchase is idempotent).
            if fresh.get("status") == "paid" or claimed is None or self.clock() - claimed < timedelta(minutes=1):
                return fresh
            order = fresh
        now = self.clock()
        uid = order["uid"]
        current = self.entitlements.state(uid, fresh=True)
        higher = (current["status"] == "active"
                  and features.RANK[current["tier"]] > features.RANK[order["tier"]])
        if higher:
            # The account moved up meanwhile (e.g. an admin grant): keep the
            # money on record for a refund rather than overwrite the plan.
            order = self._update(order, {"status": "paid", "paidAt": now, "transId": trans_id,
                                         "payType": pay_type, "needsReview": True})
            self._log("payment_needs_review", order_id, {"tier": order["tier"]})
            return order
        self.entitlements.apply_purchase(uid, order_id=order_id, tier=order["tier"], period=order["period"],
                                         days=int(order["days"]), amount=int(order["amount"]),
                                         carried=int(order.get("credit") or 0),
                                         source=("momo" if order.get("method") == "momo"
                                                 or int(order.get("credit") or 0) > 0 else "promo"))
        if order.get("promoCode"):
            self.promos.consume(uid, order["promoCode"], order_id)
        order = self._update(order, {"status": "paid", "paidAt": now, "transId": trans_id, "payType": pay_type})
        self._log("payment_paid", order_id, {"tier": order["tier"], "period": order["period"],
                                             "amount": order["amount"], "transId": trans_id})
        return order

    def _settle(self, order: dict, result: dict, source: str) -> dict:
        """Apply what MoMo reported (IPN or query) to a pending order."""
        if order.get("status") != "pending":
            return order
        try:
            result_code = int(result.get("resultCode"))
        except (TypeError, ValueError):
            return order
        if result_code == 0:
            try:
                paid_amount = int(result.get("amount"))
            except (TypeError, ValueError):
                paid_amount = -1
            if paid_amount != int(order["amount"]):
                self._log("payment_amount_mismatch", order["orderId"],
                          {"expected": order["amount"], "got": result.get("amount"), "source": source})
                return self._update(order, {"status": "review", "reviewReason": "amountMismatch"})
            return self._fulfil(order, trans_id=result.get("transId"), pay_type=result.get("payType"))
        expired = (_utc(order.get("expiresAt")) or self.clock()) + timedelta(minutes=5) < self.clock()
        if result_code in FINAL_FAILURES or (result_code not in PENDING_CODES and expired):
            return self._update(order, {"status": "failed", "resultCode": result_code,
                                        "failureMessage": str(result.get("message") or "")[:200]})
        return order

    def ipn(self, body: dict) -> bool:
        """MoMo's server-to-server result. False = bad signature (400)."""
        if self.momo is None or not self.momo.verify_ipn(body):
            return False
        order = self._get(str(body.get("orderId") or ""))
        if order is None:
            self._log("payment_unknown_order", str(body.get("orderId") or "")[:64], {})
            return True
        self._settle(order, body, "ipn")
        return True

    def status(self, uid: str, order_id: str) -> dict:
        order = self._get(str(order_id or ""))
        if order is None or order.get("uid") != uid:
            raise BillingError("orderNotFound", "Không tìm thấy đơn thanh toán.", 404)
        order = self._reconcile(order)
        return self.public(order, links=order.get("status") == "pending")

    def _reconcile(self, order: dict) -> dict:
        if order.get("status") != "pending" or order.get("method") != "momo" or self.momo is None:
            return order
        created = _utc(order.get("createdAt")) or self.clock()
        if (self.clock() - created).total_seconds() < QUERY_AFTER_SECONDS:
            return order
        try:
            result = self.momo.query(order["orderId"])
        except MomoError:
            return order
        return self._settle(order, result, "query")

    def orders(self, uid: str) -> list[dict]:
        rows = self._user_orders(uid)
        out = []
        for row in rows:
            if row.get("status") == "pending":
                row = self._reconcile(self._get(row["orderId"]) or row)
            out.append(self.public(row))
        return out

    def reconcile_user(self, uid: str) -> None:
        """Opening the plan settles any order whose IPN was lost."""
        for row in self._user_orders(uid, limit=5):
            if row.get("status") == "pending":
                self._reconcile(self._get(row["orderId"]) or row)

    # -- admin ------------------------------------------------------------
    def admin_orders(self, status: str | None = None, limit: int = 200) -> dict:
        if self.db is None:
            with self._lock:
                rows = [dict(o) for o in self._orders.values()]
        else:
            query = self.db.collection(COLLECTION).order_by("createdAt", direction="DESCENDING").limit(limit)
            rows = [s.to_dict() or {} for s in query.stream()]
        rows.sort(key=lambda r: _utc(r.get("createdAt")) or datetime.min.replace(tzinfo=timezone.utc),
                  reverse=True)
        now = self.clock().astimezone(timezone(timedelta(hours=7)))
        month = now.strftime("%Y-%m")
        revenue = sum(int(r.get("amount") or 0) for r in rows if r.get("status") == "paid"
                      and (_utc(r.get("paidAt")) or now).astimezone(now.tzinfo).strftime("%Y-%m") == month)
        if status:
            rows = [r for r in rows if r.get("status") == status]
        return {"items": [self.public(r, admin=True) for r in rows[:limit]], "monthRevenue": revenue,
                "month": month, "channels": self.channels()}

    def refund(self, order_id: str, actor: str = "") -> dict:
        order = self._get(str(order_id or ""))
        if order is None:
            raise BillingError("orderNotFound", "Không tìm thấy đơn thanh toán.", 404)
        if order.get("status") != "paid" or order.get("method") != "momo" or not order.get("transId"):
            raise BillingError("notRefundable", "Chỉ hoàn tiền được đơn MoMo đã thanh toán.", 409)
        if self.momo is None:
            raise BillingError("paymentUnavailable", "Chưa cấu hình MoMo.", 503)
        try:
            result = self.momo.refund(order_id=order["orderId"], trans_id=order["transId"],
                                      amount=int(order["amount"]),
                                      description=f"Hoàn tiền đơn {order['orderId']}")
        except MomoError as error:
            raise BillingError("refundFailed", f"MoMo chưa hoàn tiền: {error}", 502) from None
        paid = self.entitlements.paid_state(order["uid"])
        current = self.entitlements.state(order["uid"], fresh=True)
        revoked = False
        if order["orderId"] in paid["orderIds"] and current["tier"] == order["tier"]:
            self.entitlements.revoke(order["uid"], actor=actor)
            revoked = True
        order = self._update(order, {"status": "refunded", "refundedAt": self.clock(),
                                     "refundId": result.get("refundId"), "refundedBy": actor[:128],
                                     "planRevoked": revoked})
        return self.public(order, admin=True)

    def check(self, order_id: str) -> dict:
        """Admin: ask MoMo again about a pending order."""
        order = self._get(str(order_id or ""))
        if order is None:
            raise BillingError("orderNotFound", "Không tìm thấy đơn thanh toán.", 404)
        if order.get("status") == "pending" and self.momo is not None:
            try:
                order = self._settle(order, self.momo.query(order["orderId"]), "admin")
            except MomoError as error:
                raise BillingError("paymentUnavailable", str(error), 502) from None
        return self.public(order, admin=True)

    # -- views ------------------------------------------------------------
    def public(self, order: dict, *, links: bool = False, admin: bool = False) -> dict:
        out = {
            "orderId": order.get("orderId"), "tier": order.get("tier"), "period": order.get("period"),
            "days": order.get("days"), "base": order.get("base"), "promoCode": order.get("promoCode"),
            "percentOff": order.get("percentOff") or 0, "credit": order.get("credit") or 0,
            "extraDays": order.get("extraDays") or 0, "amount": order.get("amount"),
            "status": order.get("status"), "method": order.get("method"),
            "createdAt": _iso(order.get("createdAt")), "paidAt": _iso(order.get("paidAt")),
            "refundedAt": _iso(order.get("refundedAt")), "expiresAt": _iso(order.get("expiresAt")),
        }
        if links:
            out.update({"payUrl": order.get("payUrl"), "deeplink": order.get("deeplink"),
                        "qrCodeUrl": order.get("qrCodeUrl")})
        if admin:
            out.update({"uid": order.get("uid"), "transId": order.get("transId"),
                        "payType": order.get("payType"), "needsReview": bool(order.get("needsReview")),
                        "reviewReason": order.get("reviewReason"), "resultCode": order.get("resultCode"),
                        "planRevoked": order.get("planRevoked")})
        return out
