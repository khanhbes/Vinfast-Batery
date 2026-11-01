"""Per-account assistant memory: facts the user told Pinova + privacy/lifecycle governance (Stage 4).

Firestore ``users/{uid}/assistantMemory/{id}`` (one doc per fact) and
``users/{uid}/assistant/settings``. Learning is on by default; the user can
turn it off or delete facts from the app at any time. Transcripts are never
stored server-side.
"""
from __future__ import annotations

import copy
import re
import threading
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

MAX_FACTS = 60
CATEGORIES = {"habit", "preference", "vehicle", "trip", "personal", "profile", "location_safe", "other"}
CATEGORY_LABELS_VI = {
    "habit": "Thói quen sạc/lái",
    "preference": "Sở thích hội thoại",
    "vehicle": "Xe & Thiết bị",
    "trip": "Lộ trình thường đi",
    "personal": "Hồ sơ",
    "profile": "Hồ sơ",
    "location_safe": "Địa điểm quen thuộc",
    "other": "Khác",
}
_SECRET = re.compile(
    r"(mat khau|mật khẩu|password|otp|cvv|cccd|cmnd|auth[_ -]?key|api[_ -]?key|bearer\s|\b\d{9,}\b|[^\s@]+@[^\s@]+\.|bệnh\s*án|tiểu\s*đường|huyết\s*áp|tôn\s*giáo|chính\s*trị)",
    re.IGNORECASE,
)
_VN = timezone(timedelta(hours=7))


def mask_pii_text(text: str) -> str:
    """Mask emails, phone numbers, device IDs,plates, and district names for default Admin view."""
    out = str(text or "")
    out = re.sub(r"([a-zA-Z0-9])[a-zA-Z0-9._%+-]*@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})", r"\1***@\2", out)
    out = re.sub(r"\b(\d{2}[A-Z]\d?[-.\s]?)\d{3}([.\s]?\d{2})\b", r"\1***\2", out)
    out = re.sub(r"\b([0-9a-fA-F]{4})[0-9a-fA-F]{4,8}([0-9a-fA-F]{4})\b", r"\1***\2", out)
    out = re.sub(r"(Quận\s+|Phường\s+|Đường\s+)([A-ZÀ-Ỹa-zà-ỹ0-9\s]{2,15})", r"\1***", out)
    return out


class AssistantMemory:
    def __init__(self, db=None):
        self.db = db
        self._local_facts: dict[str, dict[str, dict[str, Any]]] = {}
        self._local_settings: dict[str, dict[str, Any]] = {}
        self._admin_profiles: dict[str, dict[str, Any]] = self._seed_admin_profiles()
        self._lock = threading.Lock()

    def _seed_admin_profiles(self) -> dict[str, dict[str, Any]]:
        now = datetime.now(_VN)
        exp_180 = (now + timedelta(days=180)).strftime("%d/%m/%Y")
        exp_30 = (now + timedelta(days=30)).strftime("%d/%m/%Y")
        return {
            "uzBg5EgLFBOOQXHjoqjJi7JGxP82": {
                "uid": "uzBg5EgLFBOOQXHjoqjJi7JGxP82",
                "userName": "Phan Nam Khánh",
                "email": "khanhnhim21102004@gmail.com",
                "maskedEmail": "k***@gmail.com",
                "consentGranted": True,
                "consentDate": "18/10/2026",
                "tier": "ultra",
                "vehicleModel": "VinFast Feliz 2025",
                "shellyDevice": "Shelly 1 (d0cf13de932c)",
                "maskedShellyDevice": "Shelly 1 (d0cf***932c)",
                "salutation": "Anh Khánh",
                "chargingHabits": {
                    "preferredTime": "22:00 – 05:30",
                    "targetSoc": 90,
                    "autoStopAtIdle": True,
                },
                "drivingHabits": {
                    "dailyAvgKm": 28,
                    "avgSpeedKmh": 36,
                    "ecoPreference": "Ưu tiên tuổi thọ pin LFP",
                },
                "dynamicFields": {
                    "wh_per_pct_learned": 34.2,
                    "preferred_display_style": "luxe_dial",
                    "safety_cutoff_watts": 2200,
                },
                "items": [
                    {
                        "id": "mem-khanh-01",
                        "uid": "uzBg5EgLFBOOQXHjoqjJi7JGxP82",
                        "scope": "user",
                        "category": "profile",
                        "categoryLabelVi": "Hồ sơ",
                        "text": "Chủ xe: Anh Khánh · Phương tiện liên kết: VinFast Feliz 2025",
                        "maskedText": "Chủ xe: Anh Khánh · Phương tiện liên kết: VinFast Feliz 2025",
                        "confidence": 1.0,
                        "sensitivity": "normal",
                        "status": "active",
                        "source": "user_explicit",
                        "createdAt": "18/10/2026 09:15",
                        "expiresAt": None,
                    },
                    {
                        "id": "mem-khanh-02",
                        "uid": "uzBg5EgLFBOOQXHjoqjJi7JGxP82",
                        "scope": "vehicle",
                        "category": "habit",
                        "categoryLabelVi": "Thói quen sạc/lái",
                        "text": "Thiết bị sạc liên kết: Shelly 1 (d0cf13de932c) · Ngưỡng bảo vệ 12 A / 2500 W",
                        "maskedText": "Thiết bị sạc liên kết: Shelly 1 (d0cf***932c) · Ngưỡng bảo vệ 12 A / 2500 W",
                        "confidence": 1.0,
                        "sensitivity": "sensitive",
                        "status": "active",
                        "source": "telemetry_learned",
                        "createdAt": "22/10/2026 22:40",
                        "expiresAt": exp_180,
                    },
                ],
                "lastInteraction": "Hôm nay",
                "updatedAt": "28/10/2026",
            }
        }

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
                if uid in self._admin_profiles:
                    self._admin_profiles[uid]["consentGranted"] = bool(enabled)
        return self.settings(uid)

    # -- facts ------------------------------------------------------------
    def _collection(self, uid: str):
        return self.db.collection("users").document(uid).collection("assistantMemory")

    def facts(self, uid: str) -> list[dict]:
        if self.db is not None:
            items = []
            for snapshot in self._collection(uid).limit(MAX_FACTS).stream():
                data = snapshot.to_dict() or {}
                if data.get("status", "active") != "active":
                    continue
                items.append({
                    "id": snapshot.id,
                    "text": data.get("text", ""),
                    "category": data.get("category", "other"),
                    "createdAt": data.get("createdAt"),
                    "confidence": float(data.get("confidence", 1.0)),
                    "status": data.get("status", "active"),
                    "expiresAt": data.get("expiresAt"),
                })
        else:
            with self._lock:
                items = [
                    dict(item)
                    for item in self._local_facts.get(uid, {}).values()
                    if item.get("status", "active") == "active"
                ]
        items.sort(key=lambda item: str(item.get("createdAt") or ""))
        return items

    @staticmethod
    def clean(text: str) -> str | None:
        text = re.sub(r"\s+", " ", str(text or "")).strip()[:200]
        if len(text) < 3 or _SECRET.search(text):
            return None  # never store credentials, ids, emails, health/political PII or long numbers
        return text

    def remember(
        self,
        uid: str,
        text: str,
        category: str = "other",
        *,
        confidence: float = 0.95,
        source: str = "user_explicit",
        scope: str = "user",
        sensitivity: str = "normal",
    ) -> dict | None:
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

        now_utc = datetime.now(timezone.utc)
        ttl_days = 180 if category in ("habit", "preference", "vehicle") else (None if category in ("personal", "profile") else 30)
        expires_at = (now_utc + timedelta(days=ttl_days)).isoformat() if ttl_days else None
        status = "active" if float(confidence) >= 0.85 else "pending_confirmation"

        fact = {
            "id": uuid.uuid4().hex[:16],
            "text": text,
            "maskedText": mask_pii_text(text),
            "category": category,
            "categoryLabelVi": CATEGORY_LABELS_VI.get(category, "Khác"),
            "confidence": round(float(confidence), 2),
            "sensitivity": sensitivity,
            "status": status,
            "source": source,
            "scope": scope,
            "createdAt": now_utc,
            "expiresAt": expires_at,
        }
        if self.db is not None:
            self._collection(uid).document(fact["id"]).set(
                {"text": text, "category": category, "createdAt": fact["createdAt"]}
            )
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
        if best is None or best_score < 0.6 or tie:
            return 0
        return int(self.forget(uid, best["id"]))

    def clear(self, uid: str) -> int:
        removed = 0
        for item in self.facts(uid):
            removed += int(self.forget(uid, item["id"]))
        return removed

    # -- Admin Memory Governance APIs (Stage 4) ----------------------------
    def admin_list_users(self, *, include_unmasked_uid: str | None = None) -> list[dict[str, Any]]:
        with self._lock:
            out: list[dict[str, Any]] = []
            for uid, prof in self._admin_profiles.items():
                p = copy.deepcopy(prof)
                is_unmasked = uid == include_unmasked_uid
                p["isUnmasked"] = is_unmasked
                if not is_unmasked:
                    p["email"] = p.get("maskedEmail") or mask_pii_text(p.get("email", ""))
                    p["shellyDevice"] = p.get("maskedShellyDevice") or mask_pii_text(p.get("shellyDevice", ""))
                    for item in p.get("items", []):
                        item["displayText"] = item.get("maskedText") or mask_pii_text(item.get("text", ""))
                else:
                    for item in p.get("items", []):
                        item["displayText"] = item.get("text", "")
                out.append(p)
            return out

    def admin_approve_pending(self, uid: str, item_id: str, *, approve: bool) -> dict[str, Any] | None:
        with self._lock:
            prof = self._admin_profiles.get(uid)
            if not prof:
                return None
            for idx, item in enumerate(prof.get("items", [])):
                if item["id"] == item_id:
                    if approve:
                        item["status"] = "active"
                        item["confidence"] = max(0.88, float(item.get("confidence", 0.85)))
                        prof["updatedAt"] = datetime.now(_VN).strftime("%d/%m/%Y")
                        return copy.deepcopy(item)
                    else:
                        removed = prof["items"].pop(idx)
                        prof["updatedAt"] = datetime.now(_VN).strftime("%d/%m/%Y")
                        return copy.deepcopy(removed)
            return None

    def admin_upsert_item(self, uid: str, payload: dict[str, Any]) -> dict[str, Any]:
        cleaned = self.clean(payload.get("text", ""))
        if not cleaned:
            raise ValueError("Nội dung bộ nhớ không hợp lệ hoặc chứa thông tin nhạy cảm bị cấm (mật khẩu, CCCD, y tế, tôn giáo)")
        with self._lock:
            prof = self._admin_profiles.get(uid)
            if not prof:
                raise ValueError("Không tìm thấy hồ sơ người dùng")
            if not prof.get("consentGranted", True):
                raise ValueError("Chủ xe đã tắt quyền thu thập bộ nhớ cá nhân (Opt-out)")
            cat = str(payload.get("category") or "habit")
            item_id = str(payload.get("id") or f"mem-{uuid.uuid4().hex[:8]}")
            now_str = datetime.now(_VN).strftime("%d/%m/%Y %H:%M")
            exp_str = (datetime.now(_VN) + timedelta(days=180)).strftime("%d/%m/%Y")
            new_item = {
                "id": item_id,
                "uid": uid,
                "scope": str(payload.get("scope") or "user"),
                "category": cat,
                "categoryLabelVi": CATEGORY_LABELS_VI.get(cat, "Thói quen sạc/lái"),
                "text": cleaned,
                "maskedText": mask_pii_text(cleaned),
                "displayText": cleaned,
                "confidence": float(payload.get("confidence", 0.95)),
                "sensitivity": str(payload.get("sensitivity") or "normal"),
                "status": "active" if float(payload.get("confidence", 0.95)) >= 0.85 else "pending_confirmation",
                "source": "admin_configured",
                "createdAt": now_str,
                "expiresAt": exp_str,
            }
            existing_idx = next((i for i, x in enumerate(prof["items"]) if x["id"] == item_id), -1)
            if existing_idx >= 0:
                prof["items"][existing_idx] = new_item
            else:
                prof["items"].insert(0, new_item)
            prof["updatedAt"] = datetime.now(_VN).strftime("%d/%m/%Y")
            return copy.deepcopy(new_item)

    def admin_delete_item(self, uid: str, item_id: str) -> bool:
        with self._lock:
            prof = self._admin_profiles.get(uid)
            if not prof:
                return False
            before = len(prof.get("items", []))
            prof["items"] = [x for x in prof.get("items", []) if x["id"] != item_id]
            return len(prof["items"]) < before

    def admin_set_dynamic_field(self, uid: str, key: str, value: Any) -> dict[str, Any]:
        k = re.sub(r"[^a-zA-Z0-9_.-]", "_", str(key or "").strip())[:60]
        if not k:
            raise ValueError("Tên trường mở rộng không hợp lệ")
        with self._lock:
            prof = self._admin_profiles.get(uid)
            if not prof:
                raise ValueError("Không tìm thấy hồ sơ người dùng")
            prof.setdefault("dynamicFields", {})[k] = value
            prof["updatedAt"] = datetime.now(_VN).strftime("%d/%m/%Y")
            return copy.deepcopy(prof["dynamicFields"])

    def admin_delete_dynamic_field(self, uid: str, key: str) -> bool:
        with self._lock:
            prof = self._admin_profiles.get(uid)
            if not prof:
                return False
            return prof.get("dynamicFields", {}).pop(key, None) is not None

    def admin_gdpr_wipe(self, uid: str, confirm_name: str) -> dict[str, Any]:
        with self._lock:
            prof = self._admin_profiles.get(uid)
            if not prof:
                raise ValueError("Không tìm thấy hồ sơ người dùng")
            expected_name = str(prof.get("userName") or "").strip()
            if str(confirm_name or "").strip().lower() != expected_name.lower():
                raise ValueError(f"Xác nhận tên chưa khớp. Vui lòng gõ chính xác '{expected_name}'.")
            wiped_count = len(prof.get("items", [])) + len(prof.get("dynamicFields", {}))
            prof["items"] = []
            prof["dynamicFields"] = {}
            prof["consentGranted"] = False
            prof["chargingHabits"] = {"preferredTime": "Mặc định", "targetSoc": 80, "autoStopAtIdle": False}
            prof["drivingHabits"] = {"dailyAvgKm": 0, "avgSpeedKmh": 0, "ecoPreference": "Normal"}
            prof["updatedAt"] = datetime.now(_VN).strftime("%d/%m/%Y")
        self.clear(uid)
        self.set_learning(uid, False)
        return {"uid": uid, "userName": expected_name, "wipedItemsCount": wiped_count, "consentGranted": False}
