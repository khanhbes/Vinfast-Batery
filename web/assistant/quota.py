"""Daily message quota per account (50/day by default, Task 124).

Uses the East Asia table store when configured (atomic ETag counter), else a
process-local counter (tests / local dev). Over the limit the phone falls
back to its offline engine; nothing is billed.
"""
from __future__ import annotations

import hashlib
import os
import threading
from datetime import datetime, timedelta, timezone

DAILY_LIMIT = int(os.environ.get("ASSISTANT_DAILY_LIMIT", "50") or 50)
_PARTITION = "assistantQuota"
_VN = timezone(timedelta(hours=7))


def _key(uid: str, day: str) -> str:
    return hashlib.sha256(uid.encode("utf-8")).hexdigest()[:40] + "-" + day


class DailyQuota:
    def __init__(self, store=None, limit: int = DAILY_LIMIT, clock=None):
        self.store = store
        self.limit = limit
        self.clock = clock or (lambda: datetime.now(_VN))
        self._local: dict[str, int] = {}
        self._lock = threading.Lock()

    def _day(self) -> str:
        return self.clock().strftime("%Y%m%d")

    def take(self, uid: str) -> tuple[bool, int]:
        """Count one message. Returns (allowed, remaining after this one)."""
        key = _key(uid, self._day())
        limit = self.limit

        def bump(data, _now):
            used = int(data.get("used") or 0)
            if used >= limit:
                return data, (False, 0)
            return {**data, "used": used + 1, "uid": uid[:128]}, (True, limit - used - 1)

        if self.store is not None:
            try:
                return self.store.change_entity(_PARTITION, key, bump)
            except Exception:
                pass  # store hiccup must not block the user; fall back below
        with self._lock:
            used = self._local.get(key, 0)
            if used >= limit:
                return False, 0
            self._local[key] = used + 1
            return True, limit - used - 1

    def refund(self, uid: str) -> None:
        """Give back one message when the model never answered."""
        key = _key(uid, self._day())

        def give_back(data, _now):
            used = int(data.get("used") or 0)
            return ({**data, "used": used - 1}, None) if used > 0 else (data, None)

        if self.store is not None:
            try:
                self.store.change_entity(_PARTITION, key, give_back)
                return
            except Exception:
                pass
        with self._lock:
            if self._local.get(key, 0) > 0:
                self._local[key] -= 1

    def used_today(self, uid: str) -> int:
        key = _key(uid, self._day())
        if self.store is not None:
            try:
                return int(self.store.read_entity(_PARTITION, key).get("used") or 0)
            except Exception:
                pass
        with self._lock:
            return self._local.get(key, 0)
