"""Admin promo codes (QA 135): a % off, a validity window, the plans and
periods it applies to. A valid code is remembered on the account
(``users/{uid}/billing/pendingPromo``) and applied when payment opens; it
never grants a plan by itself.

``promoCodes/{CODE}`` is server-only (no rule matches it).
"""
from __future__ import annotations

import re
import secrets
import threading
from datetime import datetime, timedelta, timezone

from . import features
from .entitlements import BillingError, _iso, _utc

CODE_RE = re.compile(r"^[A-Z0-9]{4,16}$")
_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I
MAX_FAILURES = 10
FAILURE_WINDOW = timedelta(minutes=10)
COLLECTION = "promoCodes"


def normalize_code(value) -> str:
    return re.sub(r"[\s-]", "", str(value or "")).upper()


def generate_code(length: int = 8) -> str:
    return "".join(secrets.choice(_ALPHABET) for _ in range(length))


class PromoService:
    def __init__(self, db=None, clock=None):
        self.db = db
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        self._local: dict[str, dict] = {}
        self._pending: dict[str, dict] = {}
        self._failures: dict[str, list[datetime]] = {}
        self._lock = threading.Lock()

    # -- storage ----------------------------------------------------------
    def _get(self, code: str) -> dict | None:
        if self.db is None:
            with self._lock:
                item = self._local.get(code)
                return dict(item) if item else None
        snapshot = self.db.collection(COLLECTION).document(code).get()
        return (snapshot.to_dict() or {}) if snapshot.exists else None

    def _put(self, code: str, data: dict, create: bool = False) -> None:
        if self.db is None:
            with self._lock:
                if create and code in self._local:
                    raise BillingError("codeExists", "Mã đã tồn tại.", 409)
                self._local[code] = dict(data)
            return
        ref = self.db.collection(COLLECTION).document(code)
        if create:
            try:
                ref.create(data)
            except Exception as error:
                if type(error).__name__ in ("AlreadyExists", "Conflict"):
                    raise BillingError("codeExists", "Mã đã tồn tại.", 409) from None
                raise
        else:
            ref.set(data)

    def _count_check(self, code: str) -> None:
        now = self.clock()
        if self.db is None:
            with self._lock:
                item = self._local.get(code)
                if item is not None:
                    item["checks"] = int(item.get("checks") or 0) + 1
                    item["lastCheckedAt"] = now
            return
        try:
            from google.cloud import firestore as gfs
            self.db.collection(COLLECTION).document(code).update(
                {"checks": gfs.Increment(1), "lastCheckedAt": now})
        except Exception:
            pass  # a counter must never fail the check

    # -- admin ------------------------------------------------------------
    @staticmethod
    def _clean_list(values, allowed, label):
        if values is None:
            return list(allowed)
        if not isinstance(values, list):
            raise BillingError("invalidPromo", f"{label} phải là danh sách.")
        items = [str(v).lower() for v in values if str(v).lower() in allowed]
        if not items:
            raise BillingError("invalidPromo", f"Chọn ít nhất một {label}.")
        return sorted(set(items), key=list(allowed).index)

    def _validated(self, body: dict, existing: dict | None = None) -> dict:
        base = dict(existing or {})
        if "percentOff" in body or existing is None:
            try:
                percent = int(body.get("percentOff"))
            except (TypeError, ValueError):
                raise BillingError("invalidPromo", "% giảm phải là số.") from None
            if not 1 <= percent <= 90:
                raise BillingError("invalidPromo", "% giảm phải từ 1 đến 90.")
            base["percentOff"] = percent
        if "validTo" in body or existing is None:
            valid_to = _utc(body.get("validTo"))
            if valid_to is None:
                raise BillingError("invalidPromo", "Cần ngày hết hạn.")
            base["validTo"] = valid_to
        if "validFrom" in body:
            base["validFrom"] = _utc(body.get("validFrom"))
        base.setdefault("validFrom", None)
        if base["validFrom"] and base["validFrom"] >= base["validTo"]:
            raise BillingError("invalidPromo", "Ngày bắt đầu phải trước ngày hết hạn.")
        if "tiers" in body or existing is None:
            base["tiers"] = self._clean_list(body.get("tiers"), features.PAID_TIERS, "gói")
        if "periods" in body or existing is None:
            base["periods"] = self._clean_list(body.get("periods"), features.PERIODS, "kỳ hạn")
        if "active" in body or existing is None:
            base["active"] = body.get("active") is not False
        if "note" in body or existing is None:
            base["note"] = str(body.get("note") or "").strip()[:120]
        return base

    def create(self, body: dict, actor: str = "") -> dict:
        raw = normalize_code(body.get("code"))
        code = raw or generate_code()
        if not CODE_RE.match(code):
            raise BillingError("invalidCode", "Mã gồm 4–16 chữ cái in hoa hoặc số.")
        now = self.clock()
        data = self._validated(body)
        if data["validTo"] <= now:
            raise BillingError("invalidPromo", "Ngày hết hạn phải ở tương lai.")
        data.update({"code": code, "createdAt": now, "createdBy": actor[:128], "checks": 0})
        self._put(code, data, create=True)
        return self.public(data)

    def update(self, code: str, body: dict, actor: str = "") -> dict:
        code = normalize_code(code)
        existing = self._get(code)
        if existing is None:
            raise BillingError("promoNotFound", "Không tìm thấy mã.", 404)
        data = self._validated(body, existing)
        data.update({"updatedAt": self.clock(), "updatedBy": actor[:128]})
        self._put(code, data)
        return self.public(data)

    def list(self, limit: int = 200) -> list[dict]:
        if self.db is None:
            with self._lock:
                rows = [dict(v) for v in self._local.values()]
        else:
            # QA 138: newest codes first (a bare limit took the first by id).
            query = self.db.collection(COLLECTION).order_by("createdAt", direction="DESCENDING")
            rows = [s.to_dict() or {} for s in query.limit(limit).stream()]
        rows.sort(key=lambda r: str(_iso(r.get("createdAt")) or ""), reverse=True)
        return [self.public(r) for r in rows]

    def public(self, data: dict) -> dict:
        now = self.clock()
        valid_to = _utc(data.get("validTo"))
        valid_from = _utc(data.get("validFrom"))
        state = ("inactive" if not data.get("active") else
                 "expired" if valid_to and valid_to <= now else
                 "scheduled" if valid_from and valid_from > now else "active")
        return {
            "code": data.get("code"), "percentOff": data.get("percentOff"),
            "validFrom": _iso(valid_from), "validTo": _iso(valid_to),
            "tiers": list(data.get("tiers") or []), "periods": list(data.get("periods") or []),
            "active": bool(data.get("active")), "note": data.get("note") or "",
            "checks": int(data.get("checks") or 0), "state": state,
            "createdAt": _iso(data.get("createdAt")), "createdBy": data.get("createdBy"),
        }

    # -- users ------------------------------------------------------------
    def _rate_limited(self, uid: str) -> bool:
        now = self.clock()
        with self._lock:
            recent = [t for t in self._failures.get(uid, []) if now - t < FAILURE_WINDOW]
            self._failures[uid] = recent
            return len(recent) >= MAX_FAILURES

    def _fail(self, uid: str, code: str, message: str, status: int = 400):
        with self._lock:
            self._failures.setdefault(uid, []).append(self.clock())
        raise BillingError(code, message, status)

    def redeem(self, uid: str, raw_code: str) -> dict:
        """Check a code for this account and remember it for checkout."""
        if self._rate_limited(uid):
            raise BillingError("promoRateLimited", "Bạn đã nhập sai quá nhiều lần. Thử lại sau 10 phút.", 429)
        code = normalize_code(raw_code)
        if not CODE_RE.match(code):
            self._fail(uid, "promoInvalid", "Mã khuyến mãi không hợp lệ.")
        data = self._get(code)
        if data is None:
            self._fail(uid, "promoInvalid", "Mã khuyến mãi không đúng.", 404)
        info = self.public(data)
        if info["state"] == "expired":
            self._fail(uid, "promoExpired", "Mã khuyến mãi đã hết hạn.", 410)
        if info["state"] == "scheduled":
            self._fail(uid, "promoNotStarted", "Mã khuyến mãi chưa đến ngày dùng.", 409)
        if info["state"] != "active":
            self._fail(uid, "promoInvalid", "Mã khuyến mãi không còn hiệu lực.", 410)
        self._count_check(code)
        prices = {}
        for tier in info["tiers"]:
            for period in info["periods"]:
                base = features.PRICES[tier][period]
                prices.setdefault(tier, {})[period] = {
                    "base": base, "final": features.discounted(base, info["percentOff"])}
        quote = {"code": code, "percentOff": info["percentOff"], "validTo": info["validTo"],
                 "tiers": info["tiers"], "periods": info["periods"], "prices": prices}
        self._save_pending(uid, quote)
        return quote

    def _save_pending(self, uid: str, quote: dict) -> None:
        payload = {**quote, "savedAt": self.clock()}
        if self.db is None:
            with self._lock:
                self._pending[uid] = payload
            return
        (self.db.collection("users").document(uid).collection("billing")
         .document("pendingPromo").set(payload))

    def pending(self, uid: str) -> dict | None:
        if self.db is None:
            with self._lock:
                data = dict(self._pending.get(uid) or {}) or None
        else:
            snapshot = (self.db.collection("users").document(uid).collection("billing")
                        .document("pendingPromo").get())
            data = (snapshot.to_dict() or None) if snapshot.exists else None
        if not data:
            return None
        valid_to = _utc(data.get("validTo"))
        if valid_to and valid_to <= self.clock():
            return None
        data.pop("savedAt", None)
        return data

    def clear_pending(self, uid: str) -> None:
        if self.db is None:
            with self._lock:
                self._pending.pop(uid, None)
            return
        (self.db.collection("users").document(uid).collection("billing")
         .document("pendingPromo").delete())
