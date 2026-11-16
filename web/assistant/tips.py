"""Mẹo nhỏ (QA 163): tips for riding and charging an electric scooter.

One list for the app's "Mẹo nhỏ" screen and for Pinova Bot. The built-in
list is ``tips_vi.json`` (the app ships the same file as an asset; a test
keeps the two identical). Admin documents in ``assistantTips`` change a
built-in tip with the same id or add new ones; ``enabled=false`` hides one.
"""
from __future__ import annotations

import json
import threading
import time
from pathlib import Path

from .knowledge import _tokens, fold

TIPS_FILE = Path(__file__).with_name("tips_vi.json")
CATEGORIES = ("drive", "charge", "battery", "weather", "storage", "safety", "app")
APPLIES = ("all", "lithium", "leadAcid")
MOMENTS = ("morning", "afterCharge", "lowBattery", "rain", "any")
CATEGORY_TITLES = {
    "drive": "Lái xe tiết kiệm", "charge": "Sạc pin", "battery": "Giữ pin bền",
    "weather": "Trời mưa & nắng nóng", "storage": "Để xe lâu ngày",
    "safety": "An toàn", "app": "Dùng app Pinova",
}
# Words that make a question about tips (accent-folded).
TIP_WORDS = ("meo", "tiet kiem", "ben pin", "di xa", "keo dai", "giu pin", "lam sao de", "kinh nghiem")


def builtin() -> dict:
    return json.loads(TIPS_FILE.read_text(encoding="utf-8"))


def clean(tip_id: str, data: dict, base: dict | None = None) -> dict | None:
    """One tip from an admin edit (over ``base`` when it changes a built-in
    one), or None when it is not usable."""
    base = base or {}
    merged = {**base, **{k: v for k, v in data.items() if v is not None}}
    title = str(merged.get("title") or "").strip()[:60]
    body = str(merged.get("body") or "").strip()[:600]
    category = merged.get("category")
    if not title or not body or category not in CATEGORIES:
        return None
    source = merged.get("source") if isinstance(merged.get("source"), dict) else {}
    url = source.get("url")
    return {
        "id": tip_id,
        "category": category,
        "title": title,
        "body": body,
        "appliesTo": merged.get("appliesTo") if merged.get("appliesTo") in APPLIES else "all",
        "tags": [str(t)[:40] for t in (merged.get("tags") or [])][:12],
        "when": merged.get("when") if merged.get("when") in MOMENTS else "any",
        **({"action": str(merged["action"])[:40]} if merged.get("action") else {}),
        "source": {"name": str(source.get("name") or "Pinova")[:80],
                   "url": str(url)[:300] if isinstance(url, str) and url.startswith("https://") else None},
    }


class TipStore:
    COLLECTION = "assistantTips"

    def __init__(self, db=None, *, ttl_seconds: float = 60):
        self.db = db
        self.ttl = ttl_seconds
        self._cache: tuple[float, dict] | None = None
        self._lock = threading.Lock()

    def listing(self) -> dict:
        """{version, tips, categories} for the app."""
        with self._lock:
            if self._cache and time.monotonic() - self._cache[0] <= self.ttl:
                return self._cache[1]
        data = builtin()
        merged = {tip["id"]: tip for tip in data["tips"]}
        version = str(data.get("version") or "")
        if self.db is not None:
            try:
                latest = ""
                for snapshot in self.db.collection(self.COLLECTION).limit(200).stream():
                    doc = snapshot.to_dict() or {}
                    latest = max(latest, str(doc.get("updatedAt") or ""))
                    if doc.get("enabled") is False:
                        merged.pop(snapshot.id, None)
                        continue
                    tip = clean(snapshot.id, doc, merged.get(snapshot.id))
                    if tip:
                        merged[snapshot.id] = tip
                if latest:
                    version = f"{version}+{latest[:19]}"
            except Exception:
                pass  # the built-in list still answers
        result = {
            "version": version,
            "tips": list(merged.values()),
            "categories": [{"id": c, "title": CATEGORY_TITLES[c]} for c in CATEGORIES],
        }
        with self._lock:
            self._cache = (time.monotonic(), result)
        return result

    def invalidate(self) -> None:
        with self._lock:
            self._cache = None

    def admin_entries(self) -> list[dict]:
        """Every tip for the dashboard, hidden ones included."""
        merged = {tip["id"]: {**tip, "source": tip.get("source"), "origin": "builtin", "enabled": True}
                  for tip in builtin()["tips"]}
        if self.db is not None:
            for snapshot in self.db.collection(self.COLLECTION).limit(200).stream():
                doc = snapshot.to_dict() or {}
                base = merged.get(snapshot.id)
                tip = clean(snapshot.id, doc, base) or base
                if tip is None:
                    continue
                merged[snapshot.id] = {**tip, "origin": "admin", "enabled": doc.get("enabled") is not False}
        return list(merged.values())

    def search(self, query: str, *, chemistry: str | None = None, limit: int = 2) -> list[dict]:
        """Tips for a question that asks for them (\"mẹo\", \"tiết kiệm\"…), the
        ones that fit the vehicle's battery first."""
        folded = f" {fold(query)} "
        if not any(f" {word} " in folded or word in folded for word in TIP_WORDS):
            return []
        words = _tokens(query)
        lead = chemistry is not None and "lead" in fold(chemistry)
        scored = []
        for tip in self.listing()["tips"]:
            applies = tip.get("appliesTo", "all")
            if chemistry and applies != "all" and (applies == "leadAcid") != lead:
                continue
            score = 0.0
            for tag in tip.get("tags") or []:
                key = fold(tag)
                if key and f" {key} " in folded:
                    score += 3
            score += 0.8 * len(words & _tokens(tip["title"]))
            score += 0.2 * len(words & _tokens(tip["body"]))
            if score > 0:
                scored.append((score, tip))
        scored.sort(key=lambda item: -item[0])
        return [tip for _, tip in scored[:limit]]
