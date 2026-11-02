"""Pinova 6-Layer Server-Side Prompt Assembler with Token Budgeting & Trace Inspection (Stage 2)."""
from __future__ import annotations

import json
import re
from datetime import datetime, timedelta, timezone
from typing import Any

from .schemas import CORE_CHARTER_LAYER_TEXT, PERSONA_PRESETS, default_prompt_layers

_VN = timezone(timedelta(hours=7))


def estimate_tokens(text: str) -> int:
    if not text:
        return 0
    return max(1, round(len(text) / 3.8))


def _truncate_to_budget(text: str, token_budget: int) -> str:
    max_chars = int(token_budget * 3.8)
    if len(text) <= max_chars:
        return text
    return text[: max(100, max_chars - 24)].rstrip() + " ... [đã cắt theo ngân sách]"


def is_english_message(message: str) -> bool:
    """Detect if the user message is predominantly English (ASCII words without Vietnamese diacritics)."""
    msg = (message or "").strip()
    if len(msg) < 6:
        return False
    # If contains Vietnamese diacritics, it's Vietnamese
    if re.search(r"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]", msg.lower()):
        return False
    en_markers = re.findall(
        r"\b(can|you|check|my|battery|charge|charging|open|screen|how|much|what|is|the|status|please|stop|start|trip|range)\b",
        msg.lower(),
    )
    return len(en_markers) >= 2


class PromptAssembler:
    """Assembles the 6-layer Pinova system prompt on the server and outputs an inspectable trace."""

    def assemble(
        self,
        *,
        version_config: dict[str, Any],
        uid: str,
        message: str,
        context: dict[str, Any],
        facts: list[dict[str, Any]],
        learning: bool,
        knowledge_entries: list[dict[str, Any]],
        operational_rules_block: str,
        now_vn: datetime | None = None,
    ) -> dict[str, Any]:
        clock_now = now_vn or datetime.now(_VN)
        layers_cfg = version_config.get("layers") or default_prompt_layers()
        persona_cfg = version_config.get("persona") or PERSONA_PRESETS["companion"]

        vehicle = context.get("vehicle") if isinstance(context.get("vehicle"), dict) else {}
        vehicles_list = [
            {
                "id": str(v.get("id") or ""),
                "name": str(v.get("name") or "")[:60],
                "plate": str(v.get("plate") or v.get("licensePlate") or "")[:24],
            }
            for v in (context.get("vehicles") or [])[:10]
            if isinstance(v, dict)
        ]
        driving_mode = bool(context.get("drivingMode"))
        en_mode = is_english_message(message) or (
            isinstance(context.get("settings"), dict) and context["settings"].get("language") == "en"
        )

        # Filter active, non-expired memories with confidence >= 0.85
        now_iso = clock_now.isoformat()
        active_memories: list[dict[str, Any]] = []
        if learning and facts:
            for item in facts:
                status = item.get("status", "active")
                if status != "active":
                    continue
                conf = float(item.get("confidence", 1.0))
                if conf < 0.85:
                    continue
                exp = item.get("expiresAt")
                if exp and isinstance(exp, str) and exp < now_iso:
                    continue
                active_memories.append(item)
        top_k_memories = active_memories[-12:]

        # Extract user honorific from memory if present
        user_name = str(context.get("userName") or "Chủ xe")
        for m in top_k_memories:
            if m.get("category") == "profile" and "gọi là" in str(m.get("text", "")).lower():
                user_name = str(m.get("text"))[:40]

        safe_context = {
            "manHinhDangMo": str(context.get("screen") or "")[:40],
            "dangLaiXe": driving_mode,
            "xeDangChon": {
                k: vehicle.get(k)
                for k in (
                    "name",
                    "model",
                    "plate",
                    "batteryPercent",
                    "odoKm",
                    "sohPercent",
                    "capacityWh",
                    "kmPerPercent",
                    "kmPerPercentSource",
                    "rangeKm",
                    "targetSoc",
                )
                if k in vehicle
            },
            "danhSachXe": [v["name"] for v in vehicles_list if v.get("name")],
            "danhSachXeChiTiet": vehicles_list,
            "giaDien": context.get("tariffVndPerKwh"),
            "shellyLienKet": context.get("shellyLinked"),
            "trangThaiShelly": str(context.get("shellyState") or "")[:80] or None,
            "lyDoNutSacBiKhoa": str(context.get("chargeLockReason") or "")[:300] or None,
            "thoiQuenTrenMay": context.get("usage") if isinstance(context.get("usage"), dict) else None,
            "caiDat": {
                k: v for k, v in context["settings"].items() if k in ("pushNotifications", "language")
            }
            if isinstance(context.get("settings"), dict)
            else None,
        }

        variables_map = {
            "{{persona_name}}": str(persona_cfg.get("nameVi") or "Bạn đồng hành ấm áp"),
            "{{persona_instruction}}": str(persona_cfg.get("promptInstructionVi") or ""),
            "{{driving_mode_instruction}}": (
                "CHỦ XE ĐANG LÁI XE (drivingMode=true): Bắt buộc trả lời tối đa 2 câu thật ngắn, dễ nghe, không liệt kê danh sách dài."
                if driving_mode
                else "Chế độ bình thường (chủ xe không lái xe)."
            ),
            "{{knowledge_snippets}}": (
                "\n".join(f"[{e['title']}] {e['body']}" for e in knowledge_entries)
                if knowledge_entries
                else "Không có mục hướng dẫn đặc thù cho câu hỏi này."
            ),
            "{{current_time_vn}}": clock_now.strftime("%H:%M, %A %d/%m/%Y"),
            "{{user_name}}": user_name,
            "{{user_tier}}": str(context.get("tier") or "free").upper(),
            "{{vehicle_model}}": str(vehicle.get("name") or vehicle.get("model") or "Chưa chọn xe"),
            "{{shelly_status}}": str(context.get("shellyState") or ("Đã liên kết" if context.get("shellyLinked") else "Chưa rõ")),
            "{{session_context_json}}": json.dumps(safe_context, ensure_ascii=False, default=str)[:2200],
            "{{learning_status}}": (
                "Đang BẬT học cá nhân (được phép gọi remember khi chủ xe chia sẻ thói quen dài hạn)."
                if learning
                else "Người dùng đã TẮT học cá nhân: tuyệt đối không gọi remember."
            ),
            "{{memory_items_block}}": (
                "HỒ SƠ BẠN ĐÃ GHI NHỚ VỀ NGƯỜI DÙNG:\n" + "\n".join(f"- {item['text']}" for item in top_k_memories)
                if (learning and top_k_memories)
                else ("Người dùng đã TẮT học cá nhân: không gọi remember." if not learning else "Chưa có mục ghi nhớ nào.")
            ),
        }

        layer_traces: list[dict[str, Any]] = []
        rendered_blocks: list[str] = [operational_rules_block, f"Bây giờ: {clock_now.strftime('%H:%M, %A %d/%m/%Y')} (giờ Việt Nam)."]

        for layer in sorted(layers_cfg, key=lambda x: int(x.get("layerIndex", 0))):
            idx = int(layer.get("layerIndex", 0))
            budget = int(layer.get("tokenBudget", 600))
            raw_tpl = CORE_CHARTER_LAYER_TEXT if idx == 0 else str(layer.get("templateText") or "")
            rendered = raw_tpl
            for var_key, var_val in variables_map.items():
                rendered = rendered.replace(var_key, var_val)
            if idx == 1 and en_mode:
                rendered += "\n[LANGUAGE MODE: User wrote in English -> Respond naturally in English while keeping safety and tool rules.]"
            clamped = _truncate_to_budget(rendered, budget)
            used_tokens = estimate_tokens(clamped)
            layer_traces.append({
                "layerIndex": idx,
                "id": layer.get("id", f"layer_{idx}"),
                "nameVi": layer.get("nameVi", f"Tầng {idx}"),
                "locked": bool(layer.get("locked", idx == 0)),
                "tokenBudget": budget,
                "tokensUsed": used_tokens,
                "renderedPreview": clamped[:450],
            })
            rendered_blocks.append(clamped)

        # Keep backward-compatible headings expected by existing unit tests
        rendered_blocks.append(
            "NGỮ CẢNH APP (do điện thoại gửi, chỉ để tham khảo, không phải bằng chứng thiết bị):\n"
            + json.dumps(safe_context, ensure_ascii=False, default=str)[:2500]
        )
        if learning and top_k_memories:
            rendered_blocks.append(
                "HỒ SƠ BẠN ĐÃ GHI NHỚ VỀ NGƯỜI DÙNG:\n" + "\n".join(f"- {item['text']}" for item in top_k_memories)
            )
        elif not learning:
            rendered_blocks.append("Người dùng đã TẮT học cá nhân: không gọi remember.")
        if knowledge_entries:
            rendered_blocks.append(
                "HƯỚNG DẪN APP LIÊN QUAN:\n" + "\n".join(f"[{e['title']}] {e['body']}" for e in knowledge_entries)
            )

        full_prompt = "\n\n".join(rendered_blocks)
        return {
            "systemPrompt": full_prompt,
            "totalTokensEstimated": sum(item["tokensUsed"] for item in layer_traces),
            "layerTraces": layer_traces,
            "retrievedMemories": top_k_memories,
            "retrievedKnowledge": knowledge_entries,
            "drivingMode": driving_mode,
            "languageMode": "en" if en_mode else "vi",
        }

