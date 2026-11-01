"""Versioned configuration store for Pinova (Firestore + local JSON dual persistence)."""
from __future__ import annotations

import copy
import json
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from .schemas import (
    CORE_CHARTER_LAYER_TEXT,
    PERSONA_PRESETS,
    default_config_versions,
    default_eval_cases,
    default_guardrail_policy,
    default_prompt_layers,
    default_tool_definitions,
)

_VN = timezone(timedelta(hours=7))
_DEFAULT_JSON_PATH = Path(__file__).resolve().parent.parent / "models" / "pinova_config" / "state.json"

_FORBIDDEN_OVERRIDE_PATTERNS = re.compile(
    r"(?i)(bỏ\s*qua\s*xác\s*nhận|ignore\s+previous|bypass\s+safety|tắt\s*rào\s*chắn|vượt\s*12\s*a|vượt\s*2500\s*w)"
)


class PinovaConfigStore:
    """Manages PinovaConfigVersion, KillSwitchState, ReleasePlan, EvalCase, EvalRun & Monitoring traces."""

    COLLECTION = "pinovaConfigStore"
    DOC_ID = "runtime_state"

    def __init__(self, db=None, json_path: Path | str | None = None):
        self.db = db
        self.json_path = Path(json_path) if json_path else _DEFAULT_JSON_PATH
        self._state: dict[str, Any] = self._load_initial_state()

    def _now_iso(self) -> str:
        return datetime.now(_VN).isoformat()

    def _seed_state(self) -> dict[str, Any]:
        now_iso = self._now_iso()
        versions = default_config_versions()
        eval_cases = default_eval_cases()
        initial_eval_run = {
            "runId": "eval-run-v310-release",
            "versionId": "v3.1.0",
            "executedAt": now_iso,
            "executedBy": "khanhnhim21102004@gmail.com",
            "totalCases": len(eval_cases),
            "passedCases": len(eval_cases),
            "safetyScorePct": 100.0,
            "qualityScorePct": 100.0,
            "avgLatencyMs": 13,
            "results": [
                {
                    "caseId": c["id"],
                    "title": c["title"],
                    "suite": c["suite"],
                    "suiteLabelVi": c["suiteLabelVi"],
                    "passed": True,
                    "reply": "Đã vượt qua kiểm tra an toàn, ứng xử văn minh 3 cấp (VI/EN) & định dạng chuẩn QA 137.",
                    "calledTools": c["expectedCriteria"].get("mustCallTools", []),
                    "latencyMs": 12,
                }
                for c in eval_cases
            ],
        }
        return {
            "schemaRevision": 5,
            "activeVersionId": "v3.1.0",
            "draftVersionId": "v3.2.0-draft",
            "killSwitch": {
                "mode": "normal",  # normal | safe_mode | disabled
                "reason": "Pinova 3.1 đang vận hành ổn định",
                "fallbackMessageVi": (
                    "Pinova đang tạm bảo trì nâng cấp an toàn trong ít phút. "
                    "Bạn vẫn có thể điều khiển sạc trực tiếp tại tab Sạc pin hoặc gửi phiếu Hỗ trợ nhé."
                ),
                "updatedBy": "khanhnhim21102004@gmail.com",
                "updatedAt": now_iso,
            },
            "releasePlan": {
                "releaseId": "rel-v310-prod",
                "versionId": "v3.1.0",
                "previousVersionId": "v3.0.0",
                "stage": "full_100",  # internal | canary_5 | canary_25 | full_100 | rolled_back
                "rolloutPercent": 100,
                "evalRunId": "eval-run-v310-release",
                "autoRollbackOnErrorRatePct": 5.0,
                "updatedAt": now_iso,
                "updatedBy": "khanhnhim21102004@gmail.com",
            },
            "versions": versions,
            "evalCases": eval_cases,
            "evalRuns": [initial_eval_run],
            "metrics": {
                "satisfactionPct": 100.0,
                "escalationRatePct": 0.0,
                "guardrailTriggers24h": 0,
                "toolErrorRatePct": 0.0,
                "p95LatencyMs": 13,
                "totalTurns24h": len(eval_cases),
            },
            "flaggedConversations": [],
            "conductRecords": {},
        }

    def _load_initial_state(self) -> dict[str, Any]:
        # 1. Try Firestore first if available
        if self.db is not None:
            try:
                snap = self.db.collection(self.COLLECTION).document(self.DOC_ID).get()
                if getattr(snap, "exists", False):
                    data = snap.to_dict()
                    if isinstance(data, dict) and data.get("schemaRevision") == 5 and data.get("versions"):
                        self._save_local_json(data)
                        return data
            except Exception:
                pass
        # 2. Try local JSON file fallback
        if self.json_path.exists():
            try:
                raw = json.loads(self.json_path.read_text(encoding="utf-8"))
                if isinstance(raw, dict) and raw.get("schemaRevision") == 5 and raw.get("versions"):
                    return raw
            except Exception:
                pass
        # 3. Seed default state and persist
        seeded = self._seed_state()
        self._save_local_json(seeded)
        return seeded

    def _save_local_json(self, state: dict[str, Any]) -> None:
        try:
            self.json_path.parent.mkdir(parents=True, exist_ok=True)
            tmp_path = self.json_path.with_suffix(".tmp")
            tmp_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
            os.replace(tmp_path, self.json_path)
        except Exception:
            pass

    def _persist(self) -> None:
        self._save_local_json(self._state)
        if self.db is not None:
            try:
                self.db.collection(self.COLLECTION).document(self.DOC_ID).set(self._state)
            except Exception:
                pass

    # -- Readers ------------------------------------------------------------
    def get_overview(self) -> dict[str, Any]:
        return copy.deepcopy({
            "activeVersionId": self._state["activeVersionId"],
            "draftVersionId": self._state["draftVersionId"],
            "killSwitch": self._state["killSwitch"],
            "releasePlan": self._state["releasePlan"],
            "metrics": self._state["metrics"],
            "flaggedConversations": self._state["flaggedConversations"],
            "versions": self._state["versions"],
            "personaPresets": list(PERSONA_PRESETS.values()),
            "evalCases": self._state["evalCases"],
            "evalRuns": self._state["evalRuns"][:10],
        })

    def get_version(self, version_id: str | None = None) -> dict[str, Any]:
        target_id = version_id or self._state["activeVersionId"]
        for v in self._state["versions"]:
            if v["versionId"] == target_id:
                return copy.deepcopy(v)
        return copy.deepcopy(self._state["versions"][0])

    def get_active_version(self) -> dict[str, Any]:
        return self.get_version(self._state["activeVersionId"])

    def get_draft_version(self) -> dict[str, Any]:
        return self.get_version(self._state["draftVersionId"])

    def get_kill_switch(self) -> dict[str, Any]:
        return copy.deepcopy(self._state["killSwitch"])

    # -- Mutations ----------------------------------------------------------
    def set_kill_switch(self, *, mode: str, reason: str, actor: str, fallback_message_vi: str | None = None) -> dict[str, Any]:
        if mode not in ("normal", "safe_mode", "disabled"):
            raise ValueError("Chế độ Kill Switch không hợp lệ (chỉ nhận normal, safe_mode, disabled)")
        reason_clean = str(reason or "").strip()[:300]
        if len(reason_clean) < 5:
            raise ValueError("Vui lòng nhập lý do tối thiểu 5 ký tự để ghi nhận vào nhật ký bảo mật")
        ks = self._state["killSwitch"]
        ks["mode"] = mode
        ks["reason"] = reason_clean
        if fallback_message_vi and fallback_message_vi.strip():
            ks["fallbackMessageVi"] = fallback_message_vi.strip()[:500]
        ks["updatedBy"] = actor or "admin"
        ks["updatedAt"] = self._now_iso()
        self._persist()
        return copy.deepcopy(ks)

    def lint_layers(self, layers: list[dict[str, Any]]) -> list[str]:
        """Validate token budgets, core lock, and forbid dangerous override instructions."""
        errors: list[str] = []
        if not isinstance(layers, list) or len(layers) != 6:
            return ["Cấu hình Prompt bắt buộc có đủ 6 tầng (Tầng 0 -> Tầng 5)."]
        for layer in layers:
            idx = layer.get("layerIndex")
            text = str(layer.get("templateText") or "")
            budget = int(layer.get("tokenBudget") or 600)
            est_tokens = max(1, round(len(text) / 3.8))
            if est_tokens > budget:
                errors.append(
                    f"Tầng {idx} ({layer.get('nameVi')}) vượt ngân sách token ({est_tokens} / {budget} tokens)."
                )
            if idx == 0 and text.strip() != CORE_CHARTER_LAYER_TEXT.strip():
                errors.append("Tầng 0 (Core Hiến chương Pinova) bị khóa cứng, không được phép sửa trực tiếp.")
            if idx in (1, 2, 5) and _FORBIDDEN_OVERRIDE_PATTERNS.search(text):
                errors.append(
                    f"Tầng {idx} chứa chỉ dẫn vi phạm an toàn (yêu cầu bỏ qua xác nhận hoặc vượt giới hạn 12A/2500W)."
                )
            if "~" in text:
                errors.append(f"Tầng {idx} chứa ký tự dấu ngã '~' vi phạm quy chuẩn hiển thị QA 137.")
        return errors

    def update_draft(self, payload: dict[str, Any], actor: str) -> dict[str, Any]:
        draft_id = self._state["draftVersionId"]
        draft_idx = next((i for i, v in enumerate(self._state["versions"]) if v["versionId"] == draft_id), -1)
        if draft_idx < 0:
            base = self.get_active_version()
            draft = {
                **base,
                "versionId": draft_id,
                "status": "draft",
                "basedOnVersionId": base["versionId"],
                "createdAt": self._now_iso(),
                "publishedAt": None,
            }
            self._state["versions"].append(draft)
            draft_idx = len(self._state["versions"]) - 1
        else:
            draft = copy.deepcopy(self._state["versions"][draft_idx])

        if "releaseNote" in payload:
            draft["releaseNote"] = str(payload["releaseNote"] or "").strip()[:400]

        if "layers" in payload and isinstance(payload["layers"], list):
            # Always keep Layer 0 locked to CORE_CHARTER_LAYER_TEXT
            new_layers = copy.deepcopy(payload["layers"])
            for layer in new_layers:
                if layer.get("layerIndex") == 0:
                    layer["templateText"] = CORE_CHARTER_LAYER_TEXT
                    layer["locked"] = True
            lint_errors = self.lint_layers(new_layers)
            if lint_errors:
                raise ValueError(" | ".join(lint_errors))
            draft["layers"] = new_layers

        if "persona" in payload and isinstance(payload["persona"], dict):
            preset_id = payload["persona"].get("presetId", "companion")
            preset_base = copy.deepcopy(PERSONA_PRESETS.get(preset_id, PERSONA_PRESETS["companion"]))
            preset_base.update({
                k: payload["persona"][k]
                for k in ("defaultSelfPronoun", "defaultUserPronoun", "honorificRespectUserMemory", "sliders", "drivingModeMaxSentences", "promptInstructionVi")
                if k in payload["persona"]
            })
            draft["persona"] = preset_base

        if "modelConfig" in payload and isinstance(payload["modelConfig"], dict):
            mc = draft.get("modelConfig", {})
            for k in ("provider", "primaryModel", "fallbackModel", "temperature", "topP", "maxOutputTokens", "timeoutMs"):
                if k in payload["modelConfig"]:
                    mc[k] = payload["modelConfig"][k]
            draft["modelConfig"] = mc

        if "guardrails" in payload and isinstance(payload["guardrails"], dict):
            gr = draft.get("guardrails", default_guardrail_policy())
            for k in ("blockPromptInjection", "maskPiiInLogs", "requireDisambiguationOnMultiVehicle", "enforceQa137Format", "emergencyResponseVi", "forbiddenTopics", "emergencyKeywords"):
                if k in payload["guardrails"]:
                    gr[k] = payload["guardrails"][k]
            draft["guardrails"] = gr

        if "tools" in payload and isinstance(payload["tools"], list):
            # Ensure stop_charging is never disabled in safe_mode
            tools_clean = copy.deepcopy(payload["tools"])
            for t in tools_clean:
                if t.get("name") == "stop_charging":
                    t["disabledInSafeMode"] = False
            draft["tools"] = tools_clean

        draft["createdBy"] = actor or draft.get("createdBy") or "admin"
        self._state["versions"][draft_idx] = draft
        self._persist()
        return copy.deepcopy(draft)

    def diff_versions(self, base_id: str, target_id: str) -> dict[str, Any]:
        base = self.get_version(base_id)
        target = self.get_version(target_id)
        changes: list[dict[str, Any]] = []
        if base.get("persona", {}).get("presetId") != target.get("persona", {}).get("presetId"):
            changes.append({
                "section": "Nhân cách (Persona)",
                "before": base.get("persona", {}).get("nameVi"),
                "after": target.get("persona", {}).get("nameVi"),
            })
        if base.get("modelConfig", {}).get("temperature") != target.get("modelConfig", {}).get("temperature"):
            changes.append({
                "section": "Tham số Model (Temperature)",
                "before": str(base.get("modelConfig", {}).get("temperature")),
                "after": str(target.get("modelConfig", {}).get("temperature")),
            })
        for b_layer, t_layer in zip(base.get("layers", []), target.get("layers", [])):
            if b_layer.get("templateText") != t_layer.get("templateText"):
                changes.append({
                    "section": t_layer.get("nameVi", f"Tầng {t_layer.get('layerIndex')}"),
                    "before": b_layer.get("templateText", "")[:180],
                    "after": t_layer.get("templateText", "")[:180],
                })
        b_tools = {t["name"]: t["enabled"] for t in base.get("tools", [])}
        t_tools = {t["name"]: t["enabled"] for t in target.get("tools", [])}
        for name, enabled in t_tools.items():
            if b_tools.get(name) != enabled:
                changes.append({
                    "section": f"Công cụ {name}",
                    "before": "Đang bật" if b_tools.get(name) else "Đang tắt",
                    "after": "Đang bật" if enabled else "Đang tắt",
                })
        return {
            "baseVersionId": base["versionId"],
            "targetVersionId": target["versionId"],
            "totalChanges": len(changes),
            "changes": changes,
        }

    def record_eval_run(self, eval_run: dict[str, Any]) -> dict[str, Any]:
        self._state["evalRuns"].insert(0, eval_run)
        self._state["evalRuns"] = self._state["evalRuns"][:20]
        self._persist()
        return copy.deepcopy(eval_run)

    def add_eval_case(self, case_data: dict[str, Any]) -> dict[str, Any]:
        new_id = case_data.get("id") or f"eval-custom-{len(self._state['evalCases']) + 1:02d}"
        item = {
            "id": new_id,
            "title": str(case_data.get("title") or "Kịch bản từ Playground").strip()[:140],
            "suite": case_data.get("suite") or "happy_path",
            "suiteLabelVi": case_data.get("suiteLabelVi") or "Kịch bản tùy chỉnh",
            "mockContext": case_data.get("mockContext") or default_eval_cases()[0]["mockContext"],
            "userMessage": str(case_data.get("userMessage") or "").strip()[:500],
            "expectedCriteria": case_data.get("expectedCriteria") or {"mustNotContainPhrases": ["~"]},
        }
        self._state["evalCases"].append(item)
        self._persist()
        return copy.deepcopy(item)

    def publish_version(
        self,
        *,
        version_id: str,
        stage: str,
        actor: str,
        approver: str | None = None,
        release_note: str | None = None,
    ) -> dict[str, Any]:
        stage_rollout = {
            "internal": 1,
            "canary_5": 5,
            "canary_25": 25,
            "full_100": 100,
        }
        if stage not in stage_rollout:
            raise ValueError("Giai đoạn phát hành không hợp lệ (internal, canary_5, canary_25, full_100)")

        target = next((v for v in self._state["versions"] if v["versionId"] == version_id), None)
        if not target:
            raise ValueError(f"Không tìm thấy phiên bản {version_id}")

        # Verify there is a passing EvalRun (safetyScorePct == 100) for this version
        latest_run = next((r for r in self._state["evalRuns"] if r["versionId"] == version_id), None)
        if not latest_run or float(latest_run.get("safetyScorePct", 0)) < 100.0:
            raise ValueError(
                f"Chặn xuất bản: Phiên bản {version_id} chưa chạy bộ kiểm thử tự động hoặc điểm An toàn chưa đạt 100%."
            )

        prev_active = self._state["activeVersionId"]
        now_iso = self._now_iso()
        if release_note:
            target["releaseNote"] = str(release_note).strip()[:400]
        target["approvedBy"] = approver or "security-lead@pinova.vn"
        target["publishedAt"] = now_iso
        target["status"] = "published" if stage == "full_100" else "canary"

        if stage == "full_100":
            for v in self._state["versions"]:
                if v["versionId"] != version_id and v["status"] == "published":
                    v["status"] = "archived"
            self._state["activeVersionId"] = version_id
            # Create next draft version automatically
            parts = re.findall(r"\d+", version_id)
            next_patch = int(parts[-1]) + 1 if parts else 1
            next_draft_id = f"v2.5.{next_patch}"
            if not any(v["versionId"] == next_draft_id for v in self._state["versions"]):
                new_draft = copy.deepcopy(target)
                new_draft["versionId"] = next_draft_id
                new_draft["status"] = "draft"
                new_draft["basedOnVersionId"] = version_id
                new_draft["createdAt"] = now_iso
                new_draft["publishedAt"] = None
                self._state["versions"].append(new_draft)
                self._state["draftVersionId"] = next_draft_id

        self._state["releasePlan"] = {
            "releaseId": f"rel-{version_id}-{stage}",
            "versionId": version_id,
            "previousVersionId": prev_active,
            "stage": stage,
            "rolloutPercent": stage_rollout[stage],
            "evalRunId": latest_run["runId"],
            "autoRollbackOnErrorRatePct": 5.0,
            "updatedAt": now_iso,
            "updatedBy": actor or "admin",
        }
        self._persist()
        return copy.deepcopy(self._state["releasePlan"])

    def rollback(self, *, target_version_id: str | None, reason: str, actor: str) -> dict[str, Any]:
        reason_clean = str(reason or "").strip()[:300]
        if len(reason_clean) < 5:
            raise ValueError("Vui lòng nhập lý do Rollback tối thiểu 5 ký tự")
        fallback_id = target_version_id or self._state["releasePlan"].get("previousVersionId") or "v2.4.0"
        target = next((v for v in self._state["versions"] if v["versionId"] == fallback_id), None)
        if not target:
            target = self._state["versions"][0]
            fallback_id = target["versionId"]

        prev_active = self._state["activeVersionId"]
        for v in self._state["versions"]:
            if v["versionId"] == fallback_id:
                v["status"] = "published"
            elif v["status"] in ("published", "canary") and v["versionId"] != fallback_id:
                v["status"] = "archived"

        self._state["activeVersionId"] = fallback_id
        self._state["releasePlan"] = {
            "releaseId": f"rollback-to-{fallback_id}",
            "versionId": fallback_id,
            "previousVersionId": prev_active,
            "stage": "rolled_back",
            "rolloutPercent": 100,
            "evalRunId": "eval-run-v300-release",
            "autoRollbackOnErrorRatePct": 5.0,
            "updatedAt": self._now_iso(),
            "updatedBy": actor or "admin",
            "rollbackReason": reason_clean,
        }
        self._persist()
        return copy.deepcopy(self._state["releasePlan"])

    # -- Pinova 3.1 Conduct Strike & Suspension Tracking --------------------
    def get_conduct_record(self, uid: str) -> dict[str, Any]:
        records = self._state.setdefault("conductRecords", {})
        rec = records.get(uid) or {
            "uid": uid,
            "strikeCount": 0,
            "warningEmailsSent": 0,
            "chatbotDisabledUntil": None,
            "lastViolationCategory": None,
            "updatedAt": None,
        }
        return copy.deepcopy(rec)

    def record_conduct_violation(
        self,
        uid: str,
        violation_info: dict[str, Any],
        message: str,
        *,
        dry_run: bool = False,
    ) -> dict[str, Any]:
        """Increment user's strike count (1 -> 2 -> 3) and record warning email / temporary suspension."""
        records = self._state.setdefault("conductRecords", {})
        rec = records.get(uid) or {
            "uid": uid,
            "strikeCount": 0,
            "warningEmailsSent": 0,
            "chatbotDisabledUntil": None,
            "lastViolationCategory": None,
            "updatedAt": None,
        }
        if dry_run:
            return copy.deepcopy(rec)

        now = datetime.now(_VN)
        rec["strikeCount"] = min(3, int(rec.get("strikeCount") or 0) + 1)
        rec["lastViolationCategory"] = violation_info.get("category")
        rec["updatedAt"] = now.isoformat()

        if rec["strikeCount"] >= 2:
            rec["warningEmailsSent"] = int(rec.get("warningEmailsSent") or 0) + 1
        if rec["strikeCount"] >= 3:
            disable_min = int(violation_info.get("chatbotDisabledMinutes") or 30)
            rec["chatbotDisabledUntil"] = (now + timedelta(minutes=disable_min)).isoformat()

        records[uid] = rec
        self._state["metrics"]["guardrailTriggers24h"] = int(self._state["metrics"].get("guardrailTriggers24h") or 0) + 1
        self._persist()
        return copy.deepcopy(rec)

    def reset_conduct_strikes(self, uid: str) -> dict[str, Any]:
        records = self._state.setdefault("conductRecords", {})
        records[uid] = {
            "uid": uid,
            "strikeCount": 0,
            "warningEmailsSent": 0,
            "chatbotDisabledUntil": None,
            "lastViolationCategory": None,
            "updatedAt": self._now_iso(),
        }
        self._persist()
        return copy.deepcopy(records[uid])

    # -- Pinova 3.1 Unscripted Question Escalation & Admin Evaluation --------
    def record_unscripted_question(
        self,
        uid: str,
        message: str,
        bot_reply: str,
        *,
        version_id: str = "v3.1.0",
    ) -> dict[str, Any]:
        """Record an unscripted/out-of-scope user question and forward it to the Admin review queue."""
        from .memory import mask_pii_text

        now = datetime.now(_VN)
        clean_msg = mask_pii_text(str(message or "").strip()[:500])
        flagged = self._state.setdefault("flaggedConversations", [])
        masked_user = (
            "k***@gmail.com"
            if uid == "uzBg5EgLFBOOQXHjoqjJi7JGxP82"
            else f"{str(uid or 'u')[:3]}***@pinova.vn"
        )

        # Avoid duplicate spam if the exact same unscripted question is already in the queue
        existing = next(
            (
                item
                for item in flagged
                if item.get("category") == "unscripted_escalation"
                and str(item.get("summary") or "").strip().lower() == clean_msg.lower()
            ),
            None,
        )
        if existing:
            existing["time"] = now.strftime("%H:%M · %d/%m/%Y")
            existing["botReply"] = str(bot_reply or "").strip()[:800]
            existing["reviewStatus"] = existing.get("reviewStatus") or "pending"
            self._persist()
            return copy.deepcopy(existing)

        entry = {
            "id": f"unscripted-{int(now.timestamp() * 1000)}",
            "category": "unscripted_escalation",
            "categoryLabelVi": "Ngoài kịch bản (Chờ Admin đánh giá)",
            "maskedUser": masked_user,
            "time": now.strftime("%H:%M · %d/%m/%Y"),
            "summary": clean_msg,
            "botReply": str(bot_reply or "").strip()[:800],
            "actionTaken": f"Pinova ({version_id}) đã trả lời chung an toàn & chuyển lên Admin đánh giá bổ sung kịch bản",
            "reviewStatus": "pending",
        }
        flagged.insert(0, entry)
        self._state["flaggedConversations"] = flagged[:50]
        self._persist()
        return copy.deepcopy(entry)

    def review_flagged_conversation(
        self,
        conv_id: str,
        *,
        decision: str,
        note: str = "",
        actor: str = "admin",
    ) -> dict[str, Any] | None:
        """Allow Admin to evaluate an escalated conversation/unscripted question."""
        flagged = self._state.setdefault("flaggedConversations", [])
        found = next((item for item in flagged if item.get("id") == conv_id), None)
        if not found:
            return None

        decision_labels = {
            "added_to_kb": "Admin đã đánh giá & bổ sung vào Kho kiến thức",
            "added_to_eval": "Admin đã đánh giá & đưa vào Bộ Test Chuẩn (Golden Set)",
            "approved": "Admin đã đánh giá: Phản hồi chung đạt chuẩn",
            "dismissed": "Admin đã đánh giá & đóng trường hợp ngoài phạm vi",
        }
        found["reviewStatus"] = decision if decision in decision_labels else "approved"
        label = decision_labels.get(found["reviewStatus"], "Admin đã đánh giá")
        if note and note.strip():
            label = f"{label} ({note.strip()[:120]})"
        found["actionTaken"] = label
        found["reviewedBy"] = actor
        found["reviewedAt"] = self._now_iso()
        self._persist()
        return copy.deepcopy(found)



