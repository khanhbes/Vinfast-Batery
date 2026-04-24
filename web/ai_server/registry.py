"""Registry of AI model types supported by the AI server.

Mỗi entry mô tả một mô hình AI trên roadmap. UI Admin sử dụng dữ liệu này
để render catalog, phân nhóm theo phase và trạng thái triển khai.

Structure:
    key             : canonical id dùng trong URL paths
    label           : tên hiển thị (VN)
    shortName       : tên ngắn (tiếng Anh, dùng trong badge)
    group           : 'survival' | 'assistant' | 'health'
    phase           : 'v1.0' | 'v2.0' | 'v3.0'
    status          : 'ready' | 'in_progress' | 'planned'
    icon            : tên lucide icon (frontend resolve)
    accent          : mã màu tailwind theme
    description     : mô tả 1 dòng
    useCase         : bài toán cụ thể model giải quyết
    outputDescription: mô tả đầu ra
    inputFields     : danh sách feature (dùng cho quick-test UI)
    smokeInput      : payload mẫu để validate model upload
    legacyPkl       : file .pkl hiện có để auto-seed (nếu có)
    outputKind      : 'scalar' | 'vector' | 'class'
"""
from __future__ import annotations

from typing import Any, Dict, List


MODEL_TYPES: Dict[str, Dict[str, Any]] = {
    # ─────────────────────────────────────────────────────────────
    # NHÓM 1 — SINH TỒN (v1.0): giải quyết range anxiety
    # ─────────────────────────────────────────────────────────────
    "soc": {
        "key": "soc",
        "label": "Dự đoán tiêu hao pin",
        "shortName": "SoC Consumption",
        "group": "survival",
        "phase": "v1.0",
        "status": "ready",
        "icon": "BatteryCharging",
        "accent": "emerald",
        "description": "Dự đoán phần trăm pin còn lại sau chuyến đi dựa trên điều kiện vận hành.",
        "useCase": "Giải bài toán \"Đi từ A đến B hết bao nhiêu % pin?\" — Extra Trees model dự đoán ~9.2% cho chuyến mẫu.",
        "outputDescription": "Dự đoán % pin còn lại sau chặng đi.",
        "outputUnit": "%",
        "outputMeaning": "SOC (State of Charge) - % pin còn lại. Ví dụ: 45% nghĩa là còn gần một nửa pin.",
        # SOC model expects 19 driving behavior features
        "input_fields": [
            "total_distance_km", "avg_speed_kmh", "max_speed_kmh", "avg_acceleration_ms2",
            "max_acceleration_ms2", "payload_kg", "duration_sec", "altitude_range_m",
            "ambient_temp_c", "weather_condition", "speed_std_kmh", "speed_p90_kmh",
            "stop_ratio", "hard_accel_ratio", "hard_brake_ratio", "elevation_gain_m",
            "elevation_loss_m", "distance_payload_interaction", "distance_speed_interaction",
        ],
        "input_schema": {
            "total_distance_km": {"type": "number", "desc": "Tổng quãng đường", "min": 0, "unit": "km"},
            "avg_speed_kmh": {"type": "number", "desc": "Tốc độ trung bình", "min": 0, "unit": "km/h"},
            "max_speed_kmh": {"type": "number", "desc": "Tốc độ tối đa", "min": 0, "unit": "km/h"},
            "avg_acceleration_ms2": {"type": "number", "desc": "Gia tốc trung bình", "unit": "m/s²"},
            "max_acceleration_ms2": {"type": "number", "desc": "Gia tốc tối đa", "unit": "m/s²"},
            "payload_kg": {"type": "number", "desc": "Tải trọng", "min": 0, "unit": "kg"},
            "duration_sec": {"type": "number", "desc": "Thời gian di chuyển", "min": 0, "unit": "s"},
            "altitude_range_m": {"type": "number", "desc": "Chênh lệch độ cao", "unit": "m"},
            "ambient_temp_c": {"type": "number", "desc": "Nhiệt độ môi trường", "unit": "°C"},
            "weather_condition": {"type": "integer", "desc": "Điều kiện thời tiết", "enum": [0, 1, 2, 3], "enumLabels": ["Nắng", "Mưa", "Nhiều mây", "Tuyết"]},
            "speed_std_kmh": {"type": "number", "desc": "Độ lệch chuẩn tốc độ", "unit": "km/h"},
            "speed_p90_kmh": {"type": "number", "desc": "Tốc độ phân vị 90", "unit": "km/h"},
            "stop_ratio": {"type": "number", "desc": "Tỷ lệ dừng", "min": 0, "max": 1},
            "hard_accel_ratio": {"type": "number", "desc": "Tỷ lệ tăng tốc mạnh", "min": 0, "max": 1},
            "hard_brake_ratio": {"type": "number", "desc": "Tỷ lệ phanh mạnh", "min": 0, "max": 1},
            "elevation_gain_m": {"type": "number", "desc": "Độ cao leo", "unit": "m"},
            "elevation_loss_m": {"type": "number", "desc": "Độ cao xuống", "unit": "m"},
            "distance_payload_interaction": {"type": "number", "desc": "Tương tác quãng đường x tải trọng"},
            "distance_speed_interaction": {"type": "number", "desc": "Tương tác quãng đường x tốc độ"},
        },
        "smoke_input": {
            "total_distance_km": 25.0,
            "avg_speed_kmh": 35.0,
            "max_speed_kmh": 80.0,
            "avg_acceleration_ms2": 0.5,
            "max_acceleration_ms2": 2.0,
            "payload_kg": 150.0,
            "duration_sec": 2571.0,
            "altitude_range_m": 50.0,
            "ambient_temp_c": 28.0,
            "weather_condition": 0,
            "speed_std_kmh": 15.0,
            "speed_p90_kmh": 60.0,
            "stop_ratio": 0.1,
            "hard_accel_ratio": 0.05,
            "hard_brake_ratio": 0.05,
            "elevation_gain_m": 30.0,
            "elevation_loss_m": 20.0,
            "distance_payload_interaction": 3750.0,
            "distance_speed_interaction": 875.0,
        },
        "output_kind": "scalar",
        "legacy_pkl": ["ev_soc_pipeline.pkl"],
    },

    "dte": {
        "key": "dte",
        "label": "Quãng đường còn lại linh hoạt",
        "shortName": "Dynamic DTE",
        "group": "survival",
        "phase": "v1.0",
        "status": "planned",
        "icon": "Gauge",
        "accent": "blue",
        "description": "Ước tính km còn đi được theo thời gian thực, thay vì công thức cứng nhắc.",
        "useCase": "Đồng hồ xe báo 50% = 45km cố định. AI này giảm xuống 30km nếu phát hiện đang leo dốc / thốc ga liên tục — cảnh báo sớm hết pin.",
        "outputDescription": "Số km còn lại (float), cập nhật theo mỗi lần tính.",
        "input_fields": [
            "currentBattery", "batteryHealth", "avgSpeed", "accelerationStd",
            "elevationGradient", "temperature", "loadWeight", "tirePressure",
        ],
        "smoke_input": {
            "currentBattery": 50.0, "batteryHealth": 95.0, "avgSpeed": 35.0,
            "accelerationStd": 1.2, "elevationGradient": 2.5, "temperature": 30.0,
            "loadWeight": 75.0, "tirePressure": 2.3,
        },
        "output_kind": "scalar",
        "legacy_pkl": [],
    },

    "eco_driving": {
        "key": "eco_driving",
        "label": "Đánh giá hành vi lái xe",
        "shortName": "Eco-Driving Score",
        "group": "survival",
        "phase": "v1.0",
        "status": "planned",
        "icon": "Award",
        "accent": "amber",
        "description": "Chấm điểm chuyến đi 1–100 dựa trên gia tốc, phanh gấp, tốc độ.",
        "useCase": "Gom hard_accel / hard_brake để phân loại tay lái: Eco / Normal / Aggressive. Làm cơ sở trao huy hiệu gamification trên App.",
        "outputDescription": "Score 1-100 + nhãn phân loại (eco/normal/aggressive).",
        "input_fields": [
            "hardAccelCount", "hardBrakeCount", "avgSpeed", "maxSpeed",
            "accelerationStd", "tripDurationMin", "idleTimeMin",
        ],
        "smoke_input": {
            "hardAccelCount": 2, "hardBrakeCount": 1, "avgSpeed": 25.0,
            "maxSpeed": 55.0, "accelerationStd": 0.8, "tripDurationMin": 30.0,
            "idleTimeMin": 3.0,
        },
        "output_kind": "scalar",
        "legacy_pkl": [],
    },

    # ─────────────────────────────────────────────────────────────
    # NHÓM 2 — TRỢ LÝ THÔNG MINH (v2.0)
    # ─────────────────────────────────────────────────────────────
    "eco_routing": {
        "key": "eco_routing",
        "label": "Gợi ý tuyến đường tiết kiệm pin",
        "shortName": "Eco-Routing",
        "group": "assistant",
        "phase": "v2.0",
        "status": "planned",
        "icon": "Navigation",
        "accent": "violet",
        "description": "So sánh nhiều tuyến từ Google Maps và chỉ tuyến tiết kiệm pin nhất.",
        "useCase": "Tuyến 1 ngắn nhất nhưng hay tắc (tốn pin do dừng đỗ), tuyến 2 xa hơn 1km nhưng bon bon. Dựa trên traffic + độ dốc, AI chỉ tuyến 2 giúp tiết kiệm ~3% pin.",
        "outputDescription": "Mảng tuyến với tiêu hao SOC dự đoán + khuyến nghị best-pick.",
        "input_fields": [
            "route1_distanceKm", "route1_trafficIndex", "route1_elevationGain",
            "route2_distanceKm", "route2_trafficIndex", "route2_elevationGain",
            "currentBattery", "temperature",
        ],
        "smoke_input": {
            "route1_distanceKm": 10.0, "route1_trafficIndex": 0.7, "route1_elevationGain": 20.0,
            "route2_distanceKm": 11.0, "route2_trafficIndex": 0.3, "route2_elevationGain": 10.0,
            "currentBattery": 60.0, "temperature": 28.0,
        },
        "output_kind": "vector",
        "legacy_pkl": [],
    },

    "charging_time": {
        "key": "charging_time",
        "label": "Dự đoán thời gian sạc pin",
        "shortName": "Charge Time ETA",
        "group": "assistant",
        "phase": "v2.0",
        "status": "ready",
        "icon": "Timer",
        "accent": "blue",
        "description": "Dự đoán thời gian sạc từ mức pin hiện tại đến mức mong muốn dựa trên lịch sử sạc.",
        "useCase": "Pin đang 20%, muốn sạc lên 80%. AI tính toán dựa trên tốc độ sạc trung bình, nhiệt độ, SoH → trả về 'Dự kiến 2h45 phút'. Giúp người dùng lên kế hoạch thời gian.",
        "outputDescription": "Thời gian sạc dự kiến để đạt mức pin mong muốn.",
        "outputUnit": "phút",
        "outputMeaning": "Thời gian cần sạc (phút). Ví dụ: 120 phút = 2 giờ.",
        "input_fields": [
            "start_soc", "end_soc", "delta_soc",
            "ambient_temp_c", "avg_charge_rate", "temp_deviation",
        ],
        "visible_input_fields": ["start_soc", "end_soc", "ambient_temp_c"],
        "derived_fields": {
            "delta_soc": {"from": ["start_soc", "end_soc"], "formula": "end_soc - start_soc"},
            "avg_charge_rate": {"default": 22.5},
            "temp_deviation": {"from": ["ambient_temp_c"], "formula": "abs(ambient_temp_c - 27)"},
        },
        "display_unit": "time",
        "input_schema": {
            "start_soc": {"type": "number", "desc": "% Pin lúc bắt đầu sạc", "min": 0, "max": 100, "unit": "%"},
            "end_soc": {"type": "number", "desc": "% Pin muốn sạc đến", "min": 0, "max": 100, "unit": "%"},
            "ambient_temp_c": {"type": "number", "desc": "Nhiệt độ môi trường", "min": -20, "max": 60, "unit": "°C"},
        },
        "smoke_input": {
            "start_soc": 20.0, "end_soc": 80.0, "delta_soc": 60.0,
            "ambient_temp_c": 30.0, "avg_charge_rate": 22.5, "temp_deviation": 3.0,
        },
        "output_kind": "scalar",
        "legacy_pkl": [],
    },

    "charging_recommender": {
        "key": "charging_recommender",
        "label": "Nhắc sạc thông minh",
        "shortName": "Smart Charging",
        "group": "assistant",
        "phase": "v2.0",
        "status": "planned",
        "icon": "BellRing",
        "accent": "rose",
        "description": "Học thói quen đi lại hàng tuần để gợi ý thời điểm cần cắm sạc.",
        "useCase": "8h tối thứ 6, pin còn 30%. AI biết ngày mai user thường đi xa (cần 50%). Đẩy push: \"Pin không đủ cho lịch cuối tuần — sạc đêm nay nhé!\".",
        "outputDescription": "Xác suất cần sạc trong 24h tới + thời điểm gợi ý.",
        "input_fields": [
            "currentBattery", "dayOfWeek", "avgDailyKm_lastWeek",
            "avgDailyKm_sameDow", "lastChargeHoursAgo", "nightChargeRatio",
            "weekendTrips",
        ],
        "smoke_input": {
            "currentBattery": 30.0, "dayOfWeek": 5, "avgDailyKm_lastWeek": 12.0,
            "avgDailyKm_sameDow": 25.0, "lastChargeHoursAgo": 48.0,
            "nightChargeRatio": 0.7, "weekendTrips": 2,
        },
        "output_kind": "scalar",
        "legacy_pkl": [],
    },

    "trip_labeling": {
        "key": "trip_labeling",
        "label": "Nhận diện mục đích chuyến đi",
        "shortName": "Auto-Trip Labeling",
        "group": "assistant",
        "phase": "v2.0",
        "status": "planned",
        "icon": "MapPin",
        "accent": "slate",
        "description": "Tự động dán nhãn chuyến đi: Nhà → Công ty, Siêu thị, Đi chơi cuối tuần...",
        "useCase": "Không cần user nhập thủ công. Dựa trên cluster tọa độ + tần suất + thời điểm, AI đoán mục đích và hiển thị trên timeline.",
        "outputDescription": "Nhãn phân loại (home_to_work / shopping / leisure / other) + confidence.",
        "input_fields": [
            "startLat", "startLng", "endLat", "endLng",
            "startHour", "dayOfWeek", "durationMin", "distanceKm",
            "frequencyLastMonth",
        ],
        "smoke_input": {
            "startLat": 10.7769, "startLng": 106.7009,
            "endLat": 10.8231, "endLng": 106.6297,
            "startHour": 8, "dayOfWeek": 1, "durationMin": 25.0,
            "distanceKm": 8.5, "frequencyLastMonth": 20,
        },
        "output_kind": "class",
        "legacy_pkl": [],
    },

    # ─────────────────────────────────────────────────────────────
    # NHÓM 3 — SỨC KHỎE XE & BẢO DƯỠNG DỰ ĐOÁN (v3.0)
    # ─────────────────────────────────────────────────────────────
    "soh_degradation": {
        "key": "soh_degradation",
        "label": "Dự đoán độ chai pin (SoH)",
        "shortName": "SoH Degradation",
        "group": "health",
        "phase": "v3.0",
        "status": "planned",
        "icon": "HeartPulse",
        "accent": "rose",
        "description": "Vẽ đường cong lão hóa LFP battery, dự đoán thời điểm pin xuống < 80%.",
        "useCase": "Phân tích thói quen thốc ga + sạc nhồi 100% của user → ước tính còn bao nhiêu tháng nữa pin đạt ngưỡng bảo hành / cần thay.",
        "outputDescription": "Số tháng còn lại đến khi SoH < 80%, kèm đường cong dự đoán theo tháng.",
        "input_fields": [
            "currentSoH", "cycleCount", "avgDoD", "fastChargeRatio",
            "avgTempCharging", "monthsInUse", "aggressiveDrivingRatio",
        ],
        "smoke_input": {
            "currentSoH": 95.0, "cycleCount": 300, "avgDoD": 0.6,
            "fastChargeRatio": 0.3, "avgTempCharging": 32.0,
            "monthsInUse": 12, "aggressiveDrivingRatio": 0.2,
        },
        "output_kind": "vector",
        "legacy_pkl": [],
    },

    "anomaly_detection": {
        "key": "anomaly_detection",
        "label": "Phát hiện bất thường & tụt pin ảo",
        "shortName": "Anomaly Detection",
        "group": "health",
        "phase": "v3.0",
        "status": "planned",
        "icon": "Stethoscope",
        "accent": "amber",
        "description": "So sánh SOC thực tế vs SOC dự đoán — phát hiện lốp non hơi, lỗi cell pin...",
        "useCase": "Chuyến 5km, model SOC đoán tốn 5% nhưng thực tế tụt 12%. Lặp lại 4-5 chuyến → cảnh báo đỏ: \"Lốp non hơi hoặc cell pin lỗi — đi kiểm tra!\".",
        "outputDescription": "Anomaly score (0-1) + nhãn nguyên nhân gợi ý + trend 30 ngày.",
        "input_fields": [
            "predictedSoCDrop", "actualSoCDrop", "tripDistanceKm",
            "avgSpeed", "temperature", "consecutiveAnomalies",
        ],
        "smoke_input": {
            "predictedSoCDrop": 5.0, "actualSoCDrop": 12.0,
            "tripDistanceKm": 5.0, "avgSpeed": 25.0,
            "temperature": 28.0, "consecutiveAnomalies": 3,
        },
        "output_kind": "scalar",
        "legacy_pkl": [],
    },
}


# Group metadata for UI section headers
GROUPS: Dict[str, Dict[str, Any]] = {
    "survival": {
        "key": "survival",
        "label": "Tính năng Sinh tồn",
        "subtitle": "Giải quyết nỗi lo hết pin (range anxiety)",
        "phase": "v1.0",
        "order": 1,
    },
    "assistant": {
        "key": "assistant",
        "label": "Trợ lý Thông minh",
        "subtitle": "Can thiệp thói quen hàng ngày của người dùng",
        "phase": "v2.0",
        "order": 2,
    },
    "health": {
        "key": "health",
        "label": "Sức khỏe Xe & Bảo dưỡng Dự đoán",
        "subtitle": "Giá trị thương mại cho hãng xe & xưởng dịch vụ",
        "phase": "v3.0",
        "order": 3,
    },
}


def list_types() -> List[Dict[str, Any]]:
    """Returns public metadata for each registered model type."""
    out = []
    for t in MODEL_TYPES.values():
        input_fields = t["input_fields"]
        smoke_input = t.get("smoke_input", {})
        # Use defined input_schema or build from sample input
        input_schema = t.get("input_schema", {})
        if not input_schema:
            for field in input_fields:
                value = smoke_input.get(field, 0)
                if isinstance(value, str):
                    input_schema[field] = {"type": "string"}
                elif isinstance(value, int):
                    input_schema[field] = {"type": "integer"}
                else:
                    input_schema[field] = {"type": "number"}
        
        out.append({
            "key": t["key"],
            "label": t["label"],
            "shortName": t.get("shortName", t["label"]),
            "description": t["description"],
            "useCase": t.get("useCase", ""),
            "outputDescription": t.get("outputDescription", ""),
            "outputUnit": t.get("outputUnit", ""),
            "outputMeaning": t.get("outputMeaning", ""),
            "icon": t.get("icon", "Box"),
            "accent": t.get("accent", "slate"),
            "group": t.get("group", "survival"),
            "phase": t.get("phase", "v1.0"),
            "status": t.get("status", "planned"),
            "inputFields": input_fields,
            "visibleInputFields": t.get("visible_input_fields"),
            "derivedFields": t.get("derived_fields"),
            "displayUnit": t.get("display_unit"),
            "inputSchema": input_schema,
            "outputKind": t.get("output_kind", "scalar"),
            "chartHint": _get_chart_hint(t.get("output_kind", "scalar")),
            "sampleInput": smoke_input,
        })
    return out


def _get_chart_hint(output_kind: str) -> str:
    """Get chart hint based on output kind."""
    hints = {
        "scalar": "bar",
        "vector": "line",
        "class": "bar",
    }
    return hints.get(output_kind, "bar")


def list_groups() -> List[Dict[str, Any]]:
    return sorted(GROUPS.values(), key=lambda g: g["order"])


def get_type(key: str) -> Dict[str, Any]:
    if key not in MODEL_TYPES:
        raise KeyError(f"unknown model type: {key}")
    return MODEL_TYPES[key]


def known_keys() -> List[str]:
    return list(MODEL_TYPES.keys())
