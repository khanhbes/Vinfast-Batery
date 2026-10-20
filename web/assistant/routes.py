"""HTTP surface for BatteryBot (Task 124)."""
from __future__ import annotations

import re
from datetime import datetime, timezone

from flask import Blueprint, jsonify, request

from .gemini import GeminiUnavailable


def create_assistant_blueprint(*, engine, memory, quota, knowledge, auth_resolver, require_admin, db=None,
                               audit=None):
    bp = Blueprint("assistant", __name__)

    def fail(status, code, message, retryable=False):
        return jsonify({"success": False, "error": {"code": code, "message": message, "retryable": retryable}}), status

    def user():
        uid, _email, _role = auth_resolver()
        return uid

    @bp.post("/api/assistant/chat")
    def chat():
        uid = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        body = request.get_json(silent=True) or {}
        # Empty / secret-bearing messages are answered without the model and
        # never cost a message from the daily quota (Task 125).
        early = engine.precheck(body.get("message"))
        if early:
            left = max(0, quota.limit - quota.used_today(uid))
            return jsonify({"success": True, "data": {**early, "remainingToday": left}})
        allowed, remaining = quota.take(uid)
        if not allowed:
            return fail(429, "ASSISTANT_QUOTA", "Bạn đã dùng hết lượt trò chuyện hôm nay. Pinova Bot chuyển sang chế độ cơ bản.")
        try:
            result = engine.chat(uid, body.get("message"), body.get("history"), body.get("context"))
        except GeminiUnavailable as error:
            quota.refund(uid)
            return fail(503, "ASSISTANT_UNAVAILABLE", "Trợ lý AI tạm thời không phản hồi.", retryable=True) \
                if str(error) != "notConfigured" else fail(503, "ASSISTANT_NOT_CONFIGURED", "Trợ lý AI chưa được cấu hình.")
        except Exception:
            # Firestore/tool/bug: the user got no answer, so no charge.
            quota.refund(uid)
            return fail(503, "ASSISTANT_UNAVAILABLE", "Trợ lý AI tạm thời không phản hồi.", retryable=True)
        return jsonify({"success": True, "data": {**result, "remainingToday": remaining}})

    @bp.get("/api/assistant/memory")
    def get_memory():
        uid = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        facts = [{**item, "createdAt": item["createdAt"].isoformat() if hasattr(item.get("createdAt"), "isoformat")
                  else item.get("createdAt")} for item in memory.facts(uid)]
        return jsonify({"success": True, "data": {"settings": memory.settings(uid), "facts": facts,
                                                  "usage": {"usedToday": quota.used_today(uid), "limit": quota.limit}}})

    @bp.delete("/api/assistant/memory/<fact_id>")
    def delete_fact(fact_id):
        uid = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        return jsonify({"success": True, "data": {"deleted": memory.forget(uid, fact_id)}})

    @bp.delete("/api/assistant/memory")
    def clear_memory():
        uid = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        return jsonify({"success": True, "data": {"deleted": memory.clear(uid)}})

    @bp.put("/api/assistant/settings")
    def put_settings():
        uid = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        body = request.get_json(silent=True) or {}
        if not isinstance(body.get("learningEnabled"), bool):
            return fail(400, "invalidSettings", "Thiếu learningEnabled")
        return jsonify({"success": True, "data": memory.set_learning(uid, body["learningEnabled"])})

    # -- admin knowledge ----------------------------------------------------
    @bp.get("/api/admin/assistant/knowledge")
    @require_admin
    def list_knowledge():
        return jsonify({"success": True, "data": {
            "entries": knowledge.admin_entries(),
            "assistant": {"configured": engine.gemini.configured, "model": engine.gemini.model,
                          "dailyLimit": quota.limit}}})

    @bp.put("/api/admin/assistant/knowledge/<entry_id>")
    @require_admin
    def put_knowledge(entry_id):
        if not re.fullmatch(r"[a-z0-9-]{2,60}", entry_id or ""):
            return fail(400, "invalidId", "Mã mục chỉ gồm a-z, 0-9 và dấu gạch")
        body = request.get_json(silent=True) or {}
        title, text = str(body.get("title") or "").strip(), str(body.get("body") or "").strip()
        enabled = body.get("enabled") is not False
        if enabled and (not title or not text):
            return fail(400, "invalidEntry", "Cần tiêu đề và nội dung")
        # Admin text feeds every user's prompt: reject instead of silently
        # truncating, and a string is not a keyword list (Task 125).
        if len(title) > 120 or len(text) > 2000:
            return fail(400, "entryTooLong", "Tiêu đề tối đa 120 ký tự, nội dung tối đa 2000 ký tự")
        raw_keywords = body.get("keywords") or []
        if not isinstance(raw_keywords, list):
            return fail(400, "invalidKeywords", "Từ khóa phải là danh sách")
        if db is None:
            return fail(503, "firestoreUnavailable", "Firestore chưa sẵn sàng")
        keywords = [str(k).strip()[:60] for k in raw_keywords if str(k).strip()][:20]
        actor = getattr(request, "_uid", None)
        db.collection(knowledge.COLLECTION).document(entry_id).set({
            "title": title, "body": text, "keywords": keywords, "enabled": enabled,
            "updatedAt": datetime.now(timezone.utc), "updatedBy": actor})
        knowledge.invalidate()
        if audit:
            audit("assistant_knowledge_update", "assistantKnowledge", entry_id, actor or "",
                  getattr(request, "_email", "") or "",
                  {"enabled": enabled, "titleLength": len(title), "bodyLength": len(text),
                   "keywords": len(keywords)})
        return jsonify({"success": True, "data": {"id": entry_id}})

    @bp.delete("/api/admin/assistant/knowledge/<entry_id>")
    @require_admin
    def delete_knowledge(entry_id):
        if not re.fullmatch(r"[a-z0-9-]{2,60}", entry_id or "") or db is None:
            return fail(400, "invalidId", "Mã mục không hợp lệ")
        db.collection(knowledge.COLLECTION).document(entry_id).delete()
        knowledge.invalidate()
        if audit:
            audit("assistant_knowledge_delete", "assistantKnowledge", entry_id,
                  getattr(request, "_uid", "") or "", getattr(request, "_email", "") or "", {})
        return jsonify({"success": True, "data": {"id": entry_id}})

    return bp
