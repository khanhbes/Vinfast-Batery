"""AI Chatbot Guardrails Layer (Phase 5B).

Validates and sanitizes LLM responses against:
1. Electrical & Hardware Safety: Safe max ≤ 12A / 2500W, temperature ≤ 75°C, charging temp ≤ 45°C.
2. Vehicle Catalog Ground Truth: Prevents spec hallucinations regarding range and non-existent models.
3. PII Redaction: Automatically obscures Vietnamese phone numbers and ID numbers.
"""

from __future__ import annotations

import json
import logging
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger("ai_server.chat_guardrails")

# Hardware safety thresholds per AGENTS.md
MAX_SAFE_AMPS = 12.0
MAX_SAFE_WATTS = 2500.0
MAX_SAFE_TEMP_C = 75.0
MAX_CHARGING_SAFE_TEMP_C = 45.0

# Known VinFast electric scooter specs baseline
DEFAULT_CATALOG_SPECS: Dict[str, Dict[str, Any]] = {
    "evo200": {"modelName": "VinFast Evo200", "rangeKm": 203, "nominalCapacityWh": 1872, "topSpeedKmh": 70},
    "evo_lite_neo": {"modelName": "VinFast Evo Lite Neo", "rangeKm": 110, "nominalCapacityWh": 1488, "topSpeedKmh": 49},
    "evo_grand": {"modelName": "VinFast Evo Grand", "rangeKm": 262, "nominalCapacityWh": 2400, "topSpeedKmh": 70},
    "feliz_2025": {"modelName": "VinFast Feliz 2025", "rangeKm": 270, "nominalCapacityWh": 2600, "topSpeedKmh": 65},
    "feliz_s": {"modelName": "VinFast Feliz S", "rangeKm": 198, "nominalCapacityWh": 1440, "topSpeedKmh": 60},
    "klara_s": {"modelName": "VinFast Klara S 2022", "rangeKm": 194, "nominalCapacityWh": 1440, "topSpeedKmh": 60},
    "vento_s": {"modelName": "VinFast Vento S", "rangeKm": 160, "nominalCapacityWh": 1440, "topSpeedKmh": 80},
    "theon_s": {"modelName": "VinFast Theon S", "rangeKm": 150, "nominalCapacityWh": 1440, "topSpeedKmh": 99},
}


@dataclass
class GuardrailResult:
    """Kết quả kiểm duyệt câu trả lời của LLM qua Guardrails."""
    is_safe: bool = True
    original_text: str = ""
    sanitized_text: str = ""
    violations: List[str] = field(default_factory=list)


class ChatGuardrails:
    """Bộ lọc kiểm duyệt an toàn, tính xác thực và bảo mật cho Chatbot."""

    def __init__(self, catalog_specs: Optional[Dict[str, Dict[str, Any]]] = None) -> None:
        self.catalog_specs = catalog_specs or self._load_catalog_specs()

    def _load_catalog_specs(self) -> Dict[str, Dict[str, Any]]:
        """Tải thông số kỹ thuật xe từ file assets nếu tồn tại."""
        assets_path = Path(__file__).resolve().parent.parent / "assets" / "vinfast_specs_fallback.json"
        if assets_path.is_file():
            try:
                with open(assets_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    specs = {}
                    for item in data:
                        mid = item.get("modelId", "").lower()
                        if mid:
                            specs[mid] = {
                                "modelName": item.get("modelName", mid),
                                "rangeKm": float(item.get("rangeKm", 200)),
                                "nominalCapacityWh": float(item.get("nominalCapacityWh", 2000)),
                                "topSpeedKmh": float(item.get("topSpeedKmh", 60)),
                            }
                    if specs:
                        return specs
            except Exception as e:
                logger.warning("Could not load catalog fallback json: %s", e)
        return DEFAULT_CATALOG_SPECS

    def validate_electrical_safety(self, text: str) -> tuple[str, List[str]]:
        """Reject unsafe output, do not turn a limit into a charging recommendation."""
        violations: List[str] = []
        patterns = [
            (r"(?i)\b(\d+(?:[.,]\d+)?)\s*(?:a|ampe|ampere)\b", MAX_SAFE_AMPS, "GR-ELEC-001"),
            (r"(?i)\b(\d+(?:[.,]\d+)?)\s*(?:w|watt)\b", MAX_SAFE_WATTS, "GR-ELEC-002"),
            (r"(?i)\b(\d+(?:[.,]\d+)?)\s*kw\b", MAX_SAFE_WATTS / 1000, "GR-ELEC-002"),
        ]
        for pattern, limit, code in patterns:
            for match in re.finditer(pattern, text):
                if float(match.group(1).replace(",", ".")) > limit:
                    violations.append(code + ": Nội dung vượt giới hạn hệ thống.")
        if any(word in text.lower() for word in ["sạc", "cắm sạc"]):
            for match in re.finditer(r"(?i)\b(\d+(?:[.,]\d+)?)\s*(?:°c|độ c)\b", text):
                if float(match.group(1).replace(",", ".")) > MAX_CHARGING_SAFE_TEMP_C:
                    violations.append("GR-TEMP-001: Cần kiểm tra nhiệt độ trước khi sạc.")
                    break
        if violations:
            return (
                "Cảnh báo an toàn: Mình không thể khuyến nghị sạc theo thông số này. "
                "Hãy kiểm tra hướng dẫn của xe và bộ sạc trước khi thao tác. "
                "Giới hạn hệ thống là 12A / 2500W, không phải dòng hay công suất nên chọn.",
                violations,
            )
        return text, []

    def validate_vehicle_specs(
        self, text: str, vehicle_context: Optional[Dict[str, Any]] = None
    ) -> tuple[str, List[str]]:
        """Phát hiện và ngăn chặn ảo giác (hallucination) về thông số phạm vi di chuyển (range)."""
        violations: List[str] = []
        sanitized = text

        v_ctx = vehicle_context or {}
        model_name = str(v_ctx.get("model", "")).lower()

        # Tìm model trong catalog
        matched_spec = None
        for key, spec in self.catalog_specs.items():
            if key in model_name or spec["modelName"].lower() in model_name or spec["modelName"].lower() in text.lower():
                matched_spec = spec
                break

        if matched_spec:
            official_range = matched_spec["rangeKm"]
            # Cho phép biên độ tối đa 1.4x (ví dụ đi rất chậm ở điều kiện lý tưởng)
            max_credible_range = official_range * 1.4

            # Tìm các con số km trong câu trả lời
            range_matches = re.finditer(r"\b(\d{3,4})\s*(?:km|cây số)\b", text, re.IGNORECASE)
            for m in range_matches:
                claimed_range = float(m.group(1))
                if claimed_range > max_credible_range and "odo" not in text.lower():
                    violations.append(
                        f"GR-SPEC-001: Quãng đường {claimed_range:.0f} km vượt quá thông số kỹ thuật catalog "
                        f"cho xe {matched_spec['modelName']} (tối đa ~{official_range:.0f} km)."
                    )
                    disclaimer = f"\n\n*(Lưu ý: Theo công bố chính thức từ VinFast, {matched_spec['modelName']} có phạm vi di chuyển tiêu chuẩn ~{official_range:.0f} km/lần sạc)*"
                    if disclaimer not in sanitized:
                        sanitized += disclaimer
                    break

        return sanitized, violations

    def sanitize_pii(self, text: str) -> tuple[str, List[str]]:
        """Tự động che số điện thoại và số định danh cá nhân (CCCD/CMND)."""
        violations: List[str] = []
        sanitized = text

        # 1. Số điện thoại Việt Nam (10 hoặc 11 chữ số)
        sanitized = re.sub(r'(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', '[Email đã ẩn]', sanitized)
        sanitized = re.sub(r'(?i)(?:bearer\s+)[A-Za-z0-9._~+/=-]+', '[Token đã ẩn]', sanitized)
        sanitized = re.sub(r'(?i)(?:cloud[_ ]?key|auth[_ ]?key|api[_ ]?key|password|mật khẩu)\s*[:=]\s*\S+', '[Khóa truy cập đã ẩn]', sanitized)
        if sanitized != text:
            violations.append('GR-PII-003: Thông tin riêng tư đã ẩn.')
        phone_pattern = r"(?<!\d)(?:(?:\+84|0)(?:3|5|7|8|9)\d{8}|02\d{9})(?!\d)"
        if re.search(phone_pattern, sanitized):
            violations.append("GR-PII-001: Phát hiện số điện thoại cá nhân.")
            sanitized = re.sub(phone_pattern, "[Số điện thoại đã ẩn]", sanitized)

        # 2. Số CCCD/CMND (9 hoặc 12 số sau các từ khóa định danh)
        cccd_pattern = r"(?i)(?:cccd|cmnd|căn cước|chứng minh|định danh)[:\s]*([0-9]{9,12})"
        if re.search(cccd_pattern, sanitized):
            violations.append("GR-PII-002: Phát hiện số CCCD/CMND cá nhân.")
            sanitized = re.sub(cccd_pattern, "CCCD: [Số định danh đã ẩn]", sanitized)

        return sanitized, violations

    def apply_guardrails(
        self, text: str, vehicle_context: Optional[Dict[str, Any]] = None
    ) -> GuardrailResult:
        """Thực thi toàn diện các bộ lọc Guardrails trên văn bản phản hồi."""
        if not text:
            return GuardrailResult(is_safe=True, original_text="", sanitized_text="")

        all_violations: List[str] = []
        current_text = text

        # 1. An toàn điện áp / dòng sạc
        current_text, elec_v = self.validate_electrical_safety(current_text)
        all_violations.extend(elec_v)

        # 2. Ngăn ngừa ảo giác thông số xe
        current_text, spec_v = self.validate_vehicle_specs(current_text, vehicle_context)
        all_violations.extend(spec_v)

        # 3. Che thông tin PII
        current_text, pii_v = self.sanitize_pii(current_text)
        all_violations.extend(pii_v)

        is_safe = len(all_violations) == 0
        return GuardrailResult(
            is_safe=is_safe,
            original_text=text,
            sanitized_text=current_text,
            violations=all_violations,
        )


# Global singleton instance
chat_guardrails = ChatGuardrails()
