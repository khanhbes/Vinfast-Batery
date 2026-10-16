"""Per-account assistant memory: facts the user told BatteryBot + settings.

Firestore ``users/{uid}/assistantMemory/{id}`` (one doc per fact) and
``users/{uid}/assistant/settings``. Learning is on by default; the user can
turn it off or delete facts from the app at any time. Transcripts are never
stored server-side.
"""
from __future__ import annotations

import re
import threading
import uuid
from datetime import datetime, timezone

MAX_FACTS = 60
CATEGORIES = {"habit", "preference", "vehicle", "trip", "personal", "other"}
_SECRET = re.compile(
    r"(mat khau|mật khẩu|password|otp|cvv|auth[_ -]?key|api[_ -]?key|bearer\s|\b\d{9,}\b|[^\s@]+@[^\s@]+\.)",
    re.IGNORECASE)


class AssistantMemory:
    def __init__(self, db=None):
        self.db = db
        self._local_facts: dict[str, dict[str, dict]] = {}
        self._local_settings: dict[str, dict] = {}
        self._lock = threading.Lock()

    # -- settings ---------------------------------------------------------
    def settings(self, uid: str) -> dict:
        data = {}
        if self.db is not None:
            snapshot = self.db.collection("users").document(uid).collection("assistant").document("settings").get()
            data = snapshot.to_dict() or {} if snapshot.exists else {}
        else:
            with self._lock:
                data = dict(self._local_settings.get(uid, {}))
        return {"learningEnabled": data.get("learningEnabled") is not False}

    def set_learning(self, uid: str, enabled: bool) -> dict:
        payload = {"learningEnabled": bool(enabled), "updatedAt": datetime.now(timezone.utc)}
        if self.db is not None:
            (self.db.collection("users").document(uid).collection("assistant")
             .document("settings").set(payload, merge=True))
        else:
            with self._lock:
                self._local_settings.setdefault(uid, {}).update(payload)
        return self.settings(uid)

    # -- facts ------------------------------------------------------------
    def _collection(self, uid: str):
        return self.db.collection("users").document(uid).collection("assistantMemory")

    def facts(self, uid: str) -> list[dict]:
        if self.db is not None:
            items = []
            for snapshot in self._collection(uid).limit(MAX_FACTS).stream():
                data = snapshot.to_dict() or {}
                items.append({"id": snapshot.id, "text": data.get("text", ""),
                              "category": data.get("category", "other"),
                              "createdAt": data.get("createdAt")})
        else:
            with self._lock:
                items = [dict(item) for item in self._local_facts.get(uid, {}).values()]
        items.sort(key=lambda item: str(item.get("createdAt") or ""))
        return items

    @staticmethod
    def clean(text: str) -> str | None:
        text = re.sub(r"\s+", " ", str(text or "")).strip()[:200]
        if len(text) < 3 or _SECRET.search(text):
            return None  # never store credentials, ids, emails or long numbers
        return text

    def remember(self, uid: str, text: str, category: str = "other") -> dict | None:
        if not self.settings(uid)["learningEnabled"]:
            return None
        text = self.clean(text)
        if text is None:
            return None
        category = category if category in CATEGORIES else "other"
        existing = self.facts(uid)
        lowered = text.lower()
        for item in existing:
            if item["text"].lower() == lowered:
                return item
        if len(existing) >= MAX_FACTS:
            self.forget(uid, existing[0]["id"])  # oldest goes first
        fact = {"id": uuid.uuid4().hex[:16], "text": text, "category": category,
                "createdAt": datetime.now(timezone.utc)}
        if self.db is not None:
            self._collection(uid).document(fact["id"]).set(
                {"text": text, "category": category, "createdAt": fact["createdAt"]})
        else:
            with self._lock:
                self._local_facts.setdefault(uid, {})[fact["id"]] = fact
        return fact

    def forget(self, uid: str, fact_id: str) -> bool:
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", fact_id or ""):
            return False
        if self.db is not None:
            self._collection(uid).document(fact_id).delete()
            return True
        with self._lock:
            return self._local_facts.get(uid, {}).pop(fact_id, None) is not None

    def forget_matching(self, uid: str, text: str) -> int:
        """Forget the one fact the user meant (accent-insensitive). A short
        word like "sạc" used to delete every fact containing it (Task 125)."""
        from .knowledge import fold

        needle = fold(text or "")
        words = set(re.findall(r"\w+", needle))
        if len(needle) < 3 or not words:
            return 0
        best, best_score, tie = None, 0.0, False
        for item in self.facts(uid):
            folded = fold(item["text"])
            if needle == folded or (len(needle) >= 8 and needle in folded):
                score = 1.0
            else:
                fact_words = set(re.findall(r"\w+", folded))
                score = len(words & fact_words) / max(len(words), 1)
            if score > best_score:
                best, best_score, tie = item, score, False
            elif score == best_score and score > 0:
                tie = True
        # Ambiguous ("sạc" in two facts) or weak: delete nothing; the user can
        # be more specific or use the memory screen.
        if best is None or best_score < 0.6 or tie:
            return 0
        return int(self.forget(uid, best["id"]))

    def clear(self, uid: str) -> int:
        removed = 0
        for item in self.facts(uid):
            removed += int(self.forget(uid, item["id"]))
        return removed
