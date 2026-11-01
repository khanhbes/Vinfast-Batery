"""HTTP surface for Pinova / BatteryBot (Task 124 + Pinova v3 Governance Stages 1–7)."""
from __future__ import annotations

import re
from datetime import datetime, timezone

from flask import Blueprint, jsonify, request

from .eval_runner import run_eval_suite, run_playground_turn
from .gemini import GeminiUnavailable
from .guardrails import check_emergency_sos


def create_assistant_blueprint(*, engine, memory, quota, knowledge, auth_resolver, require_admin, db=None,
                               audit=None):
    bp = Blueprint("assistant", __name__)

    def fail(status, code, message, retryable=False):
        return jsonify({"success": False, "error": {"code": code, "message": message, "retryable": retryable}}), status

    def user():
        uid, _email, _role = auth_resolver()
        return uid

    def admin_actor() -> tuple[str, str]:
        uid = getattr(request, "_uid", None) or "admin"
        email = getattr(request, "_email", None) or "khanhnhim21102004@gmail.com"
        return str(uid), str(email)

    @bp.post("/api/assistant/chat")
    def chat():
        uid = user()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        body = request.get_json(silent=True) or {}
        # Rule 9: Emergency SOS never costs quota and is never blocked by 429
        sos = check_emergency_sos(str(body.get("message") or ""))
        if sos:
            left = max(0, quota.limit_for(uid) - quota.used_today(uid))
            return jsonify({"success": True, "data": {**sos, "remainingToday": left}})
        # Empty / secret-bearing messages are answered without the model and
        # never cost a message from the daily quota (Task 125).
        early = engine.precheck(body.get("message"))
        if early:
            left = max(0, quota.limit_for(uid) - quota.used_today(uid))
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
                                                  "usage": {"usedToday": quota.used_today(uid), "limit": quota.limit_for(uid)}}})

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

    # -- Pinova v3 Admin Governance Endpoints (Stages 1–7) ------------------
    @bp.get("/api/admin/assistant/overview")
    @require_admin
    def admin_overview():
        overview = engine.config_store.get_overview()
        overview["userMemories"] = memory.admin_list_users()
        overview["knowledgeEntries"] = knowledge.admin_entries()
        overview["runtimeStatus"] = {
            "geminiConfigured": bool(getattr(engine.gemini, "configured", False)),
            "model": getattr(engine.gemini, "model", "gemini-3-flash-preview"),
            "dailyQuotaLimit": quota.limit,
        }
        return jsonify({"success": True, "data": overview})

    @bp.post("/api/admin/assistant/kill-switch")
    @require_admin
    def admin_set_kill_switch():
        body = request.get_json(silent=True) or {}
        uid, email = admin_actor()
        try:
            ks = engine.config_store.set_kill_switch(
                mode=str(body.get("mode") or "normal"),
                reason=str(body.get("reason") or ""),
                actor=email,
                fallback_message_vi=body.get("fallbackMessageVi"),
            )
        except ValueError as err:
            return fail(400, "invalidKillSwitch", str(err))
        if audit:
            audit("pinova_kill_switch_change", "pinovaKillSwitch", ks["mode"], uid, email, {"reason": ks["reason"]})
        return jsonify({"success": True, "data": ks})

    @bp.put("/api/admin/assistant/draft")
    @require_admin
    def admin_update_draft():
        body = request.get_json(silent=True) or {}
        uid, email = admin_actor()
        try:
            draft = engine.config_store.update_draft(body, actor=email)
        except ValueError as err:
            return fail(400, "lintFailed", str(err))
        if audit:
            audit("pinova_draft_update", "pinovaConfigVersion", draft["versionId"], uid, email,
                  {"releaseNote": draft.get("releaseNote", "")[:120]})
        return jsonify({"success": True, "data": draft})

    @bp.get("/api/admin/assistant/diff")
    @require_admin
    def admin_diff_versions():
        base_id = request.args.get("base") or engine.config_store.get_overview()["activeVersionId"]
        target_id = request.args.get("target") or engine.config_store.get_overview()["draftVersionId"]
        return jsonify({"success": True, "data": engine.config_store.diff_versions(base_id, target_id)})

    @bp.post("/api/admin/assistant/playground")
    @require_admin
    def admin_playground():
        body = request.get_json(silent=True) or {}
        message = str(body.get("message") or "").strip()
        if not message:
            return fail(400, "emptyMessage", "Vui lòng nhập nội dung thử nghiệm")
        ctx = body.get("context") if isinstance(body.get("context"), dict) else {}
        sim_uid = str(body.get("uid") or ctx.get("uid") or "uzBg5EgLFBOOQXHjoqjJi7JGxP82")
        version_id = body.get("versionId")
        compare_id = body.get("compareVersionId")
        out = run_playground_turn(
            engine=engine,
            uid=sim_uid,
            message=message,
            context=ctx,
            version_id=version_id,
            compare_version_id=compare_id,
        )
        out["flaggedConversations"] = engine.config_store.get_overview().get("flaggedConversations", [])
        return jsonify({"success": True, "data": out})

    @bp.post("/api/admin/assistant/flagged/<conv_id>/review")
    @require_admin
    def admin_review_flagged(conv_id):
        body = request.get_json(silent=True) or {}
        uid, email = admin_actor()
        decision = str(body.get("decision") or "approved")
        note = str(body.get("note") or "")
        updated = engine.config_store.review_flagged_conversation(
            conv_id,
            decision=decision,
            note=note,
            actor=email,
        )
        if not updated:
            return fail(404, "notFound", "Không tìm thấy trường hợp hội thoại cần đánh giá")
        if audit:
            audit("pinova_flagged_review", "pinovaFlaggedConversation", conv_id, uid, email, {"decision": decision})
        return jsonify({"success": True, "data": updated})

    @bp.post("/api/admin/assistant/eval/run")
    @require_admin
    def admin_run_eval():
        body = request.get_json(silent=True) or {}
        uid, email = admin_actor()
        version_id = str(body.get("versionId") or engine.config_store.get_overview()["draftVersionId"])
        run_res = run_eval_suite(engine=engine, version_id=version_id, actor=email)
        if audit:
            audit("pinova_eval_run", "pinovaEvalRun", run_res["runId"], uid, email,
                  {"versionId": version_id, "safetyScorePct": run_res["safetyScorePct"], "passed": run_res["passedCases"]})
        return jsonify({"success": True, "data": run_res})

    @bp.post("/api/admin/assistant/eval/cases")
    @require_admin
    def admin_add_eval_case():
        body = request.get_json(silent=True) or {}
        if not str(body.get("userMessage") or "").strip():
            return fail(400, "invalidCase", "Thiếu câu hỏi người dùng cho kịch bản kiểm thử")
        created = engine.config_store.add_eval_case(body)
        return jsonify({"success": True, "data": created})

    @bp.post("/api/admin/assistant/publish")
    @require_admin
    def admin_publish():
        body = request.get_json(silent=True) or {}
        uid, email = admin_actor()
        version_id = str(body.get("versionId") or engine.config_store.get_overview()["draftVersionId"])
        stage = str(body.get("stage") or "full_100")
        try:
            plan = engine.config_store.publish_version(
                version_id=version_id,
                stage=stage,
                actor=email,
                approver=body.get("approver"),
                release_note=body.get("releaseNote"),
            )
        except ValueError as err:
            return fail(400, "publishBlocked", str(err))
        if audit:
            audit("pinova_publish_version", "pinovaReleasePlan", plan["releaseId"], uid, email,
                  {"versionId": version_id, "stage": stage, "rolloutPercent": plan["rolloutPercent"]})
        return jsonify({"success": True, "data": plan})

    @bp.post("/api/admin/assistant/rollback")
    @require_admin
    def admin_rollback():
        body = request.get_json(silent=True) or {}
        uid, email = admin_actor()
        try:
            plan = engine.config_store.rollback(
                target_version_id=body.get("targetVersionId"),
                reason=str(body.get("reason") or ""),
                actor=email,
            )
        except ValueError as err:
            return fail(400, "rollbackFailed", str(err))
        if audit:
            audit("pinova_rollback", "pinovaReleasePlan", plan["releaseId"], uid, email,
                  {"versionId": plan["versionId"], "reason": plan.get("rollbackReason", "")})
        return jsonify({"success": True, "data": plan})

    # -- Admin User Memory Privacy & Lifecycle Routes -----------------------
    @bp.post("/api/admin/assistant/memory/<target_uid>/unmask")
    @require_admin
    def admin_unmask_memory(target_uid):
        body = request.get_json(silent=True) or {}
        reason = str(body.get("reason") or "").strip()
        if len(reason) < 5:
            return fail(400, "reasonRequired", "Bắt buộc nhập lý do nghiệp vụ (tối thiểu 5 ký tự) để mở khóa PII và ghi Nhật ký bảo mật.")
        uid, email = admin_actor()
        users = memory.admin_list_users(include_unmasked_uid=target_uid)
        found = next((u for u in users if u["uid"] == target_uid), None)
        if not found:
            return fail(404, "notFound", "Không tìm thấy hồ sơ bộ nhớ người dùng")
        if audit:
            audit("pinova_memory_pii_unmask", "assistantMemory", target_uid, uid, email, {"reason": reason})
        return jsonify({"success": True, "data": found})

    @bp.post("/api/admin/assistant/memory/<target_uid>/pending/<item_id>")
    @require_admin
    def admin_decide_pending_memory(target_uid, item_id):
        body = request.get_json(silent=True) or {}
        approve = bool(body.get("approve", True))
        updated = memory.admin_approve_pending(target_uid, item_id, approve=approve)
        if not updated:
            return fail(404, "notFound", "Không tìm thấy mục chờ xác nhận")
        return jsonify({"success": True, "data": updated})

    @bp.post("/api/admin/assistant/memory/<target_uid>/items")
    @require_admin
    def admin_upsert_memory_item(target_uid):
        body = request.get_json(silent=True) or {}
        try:
            item = memory.admin_upsert_item(target_uid, body)
        except ValueError as err:
            return fail(400, "invalidMemoryItem", str(err))
        return jsonify({"success": True, "data": item})

    @bp.delete("/api/admin/assistant/memory/<target_uid>/items/<item_id>")
    @require_admin
    def admin_delete_memory_item(target_uid, item_id):
        deleted = memory.admin_delete_item(target_uid, item_id)
        return jsonify({"success": True, "data": {"deleted": deleted}})

    @bp.post("/api/admin/assistant/memory/<target_uid>/dynamic")
    @require_admin
    def admin_set_dynamic(target_uid):
        body = request.get_json(silent=True) or {}
        try:
            fields = memory.admin_set_dynamic_field(target_uid, str(body.get("key") or ""), body.get("value"))
        except ValueError as err:
            return fail(400, "invalidDynamicField", str(err))
        return jsonify({"success": True, "data": {"dynamicFields": fields}})

    @bp.delete("/api/admin/assistant/memory/<target_uid>/dynamic/<key>")
    @require_admin
    def admin_delete_dynamic(target_uid, key):
        deleted = memory.admin_delete_dynamic_field(target_uid, key)
        return jsonify({"success": True, "data": {"deleted": deleted}})

    @bp.post("/api/admin/assistant/memory/<target_uid>/gdpr-wipe")
    @require_admin
    def admin_gdpr_wipe_memory(target_uid):
        body = request.get_json(silent=True) or {}
        uid, email = admin_actor()
        try:
            receipt = memory.admin_gdpr_wipe(target_uid, str(body.get("confirmName") or ""))
        except ValueError as err:
            return fail(400, "confirmMismatch", str(err))
        if audit:
            audit("pinova_memory_gdpr_wipe", "assistantMemory", target_uid, uid, email, receipt)
        return jsonify({"success": True, "data": receipt})

    return bp
