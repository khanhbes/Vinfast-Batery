"""Which plan an account is on (QA 135).

Firestore ``users/{uid}/entitlements/current`` (written only by this server:
the rules have no match for it, so clients can neither read nor write it)
and a create-once marker ``users/{uid}/entitlements/trial``. Without a
database (tests, local dev) everything lives in process memory.

An expired or revoked plan is Free. A running charge session is never cut
because a plan ended; gates apply when something new starts.
"""
from __future__ import annotations

import os
import threading
from datetime import datetime, timedelta, timezone

from . import features

CACHE_SECONDS = 60
MAX_HISTORY = 20


def _utc(value):
    if value is None:
        return None
    if isinstance(value, str):
        try:
            value = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    if not isinstance(value, datetime):
        return None
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def _iso(value):
    value = _utc(value)
    return value.isoformat().replace("+00:00", "Z") if value else None


class BillingError(RuntimeError):
    def __init__(self, code: str, message: str, status: int = 400):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


class EntitlementService:
    def __init__(self, db=None, clock=None, enforced: bool | None = None):
        self.db = db
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        if enforced is None:
            enforced = os.environ.get("BILLING_ENFORCED", "true").strip().lower() not in ("0", "false", "no", "off")
        # Rollback switch: when off every account is treated as Ultra for
        # gates (the plan shown stays the real one).
        self.enforced = enforced
        self._local: dict[str, dict] = {}
        self._trials: set[str] = set()
        self._cache: dict[str, tuple[datetime, dict]] = {}
        self._lock = threading.Lock()

    # -- storage ----------------------------------------------------------
    def _ref(self, uid: str, doc: str = "current"):
        return self.db.collection("users").document(uid).collection("entitlements").document(doc)

    def _read(self, uid: str) -> dict:
        if self.db is None:
            with self._lock:
                return dict(self._local.get(uid) or {})
        snapshot = self._ref(uid).get()
        return (snapshot.to_dict() or {}) if snapshot.exists else {}

    def _write(self, uid: str, data: dict) -> None:
        if self.db is None:
            with self._lock:
                self._local[uid] = dict(data)
        else:
            self._ref(uid).set(data)
        with self._lock:
            self._cache.pop(uid, None)

    def _trial_used(self, uid: str) -> bool:
        if self.db is None:
            with self._lock:
                return uid in self._trials
        return self._ref(uid, "trial").get().exists

    def _claim_trial(self, uid: str, now: datetime) -> bool:
        """Atomic once per account: ``create`` fails when the marker exists."""
        if self.db is None:
            with self._lock:
                if uid in self._trials:
                    return False
                self._trials.add(uid)
                return True
        try:
            self._ref(uid, "trial").create({"startedAt": now})
            return True
        except Exception as error:  # AlreadyExists / Conflict
            if type(error).__name__ in ("AlreadyExists", "Conflict"):
                return False
            raise

    # -- reading ----------------------------------------------------------
    def state(self, uid: str, fresh: bool = False) -> dict:
        now = self.clock()
        if not fresh:
            with self._lock:
                cached = self._cache.get(uid)
            if cached and (now - cached[0]).total_seconds() < CACHE_SECONDS:
                return dict(cached[1])
        data = self._read(uid)
        tier = features.normalize_tier(data.get("tier"))
        status = str(data.get("status") or ("active" if tier != "free" else "none"))
        expires = _utc(data.get("expiresAt"))
        if tier != "free" and (status not in ("active", "trial") or expires is None or expires <= now):
            tier, status = "free", ("expired" if status in ("active", "trial") or expires else status)
        value = {
            "tier": tier,
            "status": status,
            "period": data.get("period"),
            "source": data.get("source"),
            "expiresAt": _iso(expires) if tier != "free" else None,
            "lastPlan": features.normalize_tier(data.get("tier")),
            "lastExpiresAt": _iso(expires),
        }
        with self._lock:
            self._cache[uid] = (now, value)
        return dict(value)

    def tier(self, uid: str) -> str:
        """Tier the gates use (Ultra for everyone when enforcement is off)."""
        if not self.enforced:
            return "ultra"
        try:
            return self.state(uid)["tier"]
        except Exception:
            # A Firestore hiccup must not lock paying users out; it also
            # must not hand out Premium, so the cached value wins, else Free.
            with self._lock:
                cached = self._cache.get(uid)
            return cached[1]["tier"] if cached else "free"

    def allows(self, uid: str, feature: str) -> bool:
        return features.allows(self.tier(uid), feature)

    def limit(self, uid: str, name: str):
        return features.limit(self.tier(uid), name)

    def summary(self, uid: str) -> dict:
        state = self.state(uid, fresh=True)
        gate_tier = state["tier"] if self.enforced else "ultra"
        return {
            **state,
            "trialAvailable": not self._trial_used(uid),
            "trialDays": features.TRIAL_DAYS,
            "trialTier": features.TRIAL_TIER,
            "features": features.feature_map(gate_tier),
            "limits": features.limit_map(gate_tier),
            "requiredTiers": dict(features.FEATURES),
            "prices": features.PRICES,
            "enforced": self.enforced,
        }

    # -- changes ----------------------------------------------------------
    def _history(self, data: dict, entry: dict) -> list:
        history = list(data.get("history") or [])[-(MAX_HISTORY - 1):]
        history.append(entry)
        return history

    def start_trial(self, uid: str) -> dict:
        now = self.clock()
        current = self.state(uid, fresh=True)
        if current["tier"] != "free":
            raise BillingError("alreadyPremium", "Tài khoản đang có gói Premium.", 409)
        if not self._claim_trial(uid, now):
            raise BillingError("trialUsed", "Tài khoản đã dùng thử Premium.", 409)
        data = self._read(uid)
        expires = now + timedelta(days=features.TRIAL_DAYS)
        self._write(uid, {
            "tier": features.TRIAL_TIER, "status": "trial", "period": None, "source": "trial",
            "startedAt": now, "expiresAt": expires, "updatedAt": now,
            "history": self._history(data, {"at": _iso(now), "action": "trial",
                                            "tier": features.TRIAL_TIER, "expiresAt": _iso(expires)}),
        })
        return self.summary(uid)

    def grant(self, uid: str, tier: str, *, period: str | None = None, days: int | None = None,
              actor: str = "", source: str = "admin") -> dict:
        tier = str(tier or "").lower()
        if tier not in features.PAID_TIERS:
            raise BillingError("invalidTier", "Gói phải là pro hoặc ultra.")
        if period in features.PERIODS:
            length = features.PERIOD_DAYS[period]
        else:
            try:
                length = int(days)
            except (TypeError, ValueError):
                raise BillingError("invalidPeriod", "Cần kỳ hạn tháng/năm hoặc số ngày.") from None
            if not 1 <= length <= 730:
                raise BillingError("invalidPeriod", "Số ngày phải từ 1 đến 730.")
            period = None
        now = self.clock()
        data = self._read(uid)
        current = self.state(uid, fresh=True)
        start = now
        # Extending the same plan adds to what is left of it.
        if current["tier"] == tier and current["status"] == "active":
            start = max(now, _utc(data.get("expiresAt")) or now)
        expires = start + timedelta(days=length)
        self._write(uid, {
            "tier": tier, "status": "active", "period": period, "source": source,
            "startedAt": _utc(data.get("startedAt")) if start != now else now,
            "expiresAt": expires, "updatedAt": now, "updatedBy": actor[:128],
            "history": self._history(data, {"at": _iso(now), "action": "grant", "tier": tier,
                                            "days": length, "expiresAt": _iso(expires),
                                            "by": actor[:128], "source": source}),
        })
        return self.summary(uid)

    def revoke(self, uid: str, actor: str = "") -> dict:
        now = self.clock()
        data = self._read(uid)
        self._write(uid, {
            **{k: v for k, v in data.items() if k != "history"},
            "tier": "free", "status": "revoked", "expiresAt": None, "updatedAt": now,
            "updatedBy": actor[:128],
            "history": self._history(data, {"at": _iso(now), "action": "revoke", "by": actor[:128]}),
        })
        return self.summary(uid)

    def history(self, uid: str) -> list:
        return list(self._read(uid).get("history") or [])

    def tier_counts(self, limit: int = 2000) -> dict:
        """Accounts per active plan, for the portal (bounded read)."""
        counts = {"pro": 0, "ultra": 0, "trial": 0, "expired": 0}
        now = self.clock()
        if self.db is None:
            with self._lock:
                rows = list(self._local.values())
        else:
            rows = [s.to_dict() or {} for s in self.db.collection_group("entitlements").limit(limit).stream()
                    if s.id == "current"]
        for data in rows:
            tier = features.normalize_tier(data.get("tier"))
            expires = _utc(data.get("expiresAt"))
            if tier == "free":
                continue
            if expires is None or expires <= now or data.get("status") not in ("active", "trial"):
                counts["expired"] += 1
            elif data.get("status") == "trial":
                counts["trial"] += 1
            else:
                counts[tier] += 1
        return counts
