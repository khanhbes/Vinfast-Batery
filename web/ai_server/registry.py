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
        "shortName": "Battery Consumption",
        "group": "survival",
        "phase": "v1.0",
        "status": "ready",
        "icon": "BatteryCharging",
        "accent": "emerald",
        "description": "Dự đoán phần trăm SOC tiêu thụ cho một chuyến đi.",
        "useCase": "Ước tính phần trăm pin sẽ tiêu thụ dựa trên hành trình, tốc độ, gia tốc, tải trọng, thời tiết và địa hình.",
        "outputDescription": "Phần trăm pin dự kiến tiêu thụ trong chuyến đi.",
        "outputUnit": "%",
        "outputMeaning": "Độ giảm SOC dự kiến, tính theo điểm phần trăm.",
        "display_unit": "percentage",
        "input_fields": [
            "distance_km", "duration_min", "avg_speed_kmh", "max_speed_kmh",
            "avg_acceleration", "max_acceleration", "min_acceleration",
            "payload_kg", "ambient_temp_c", "weather_encoded",
            "elevation_change_m",
        ],
        "visible_input_fields": [
            "distance_km", "duration_min", "avg_speed_kmh", "max_speed_kmh",
            "payload_kg", "ambient_temp_c", "elevation_change_m",
        ],
        "input_schema": {
            "distance_km": {"type": "number", "label": "Quãng đường", "desc": "Quãng đường di chuyển", "min": 1, "max": 150, "step": 1, "unit": "km"},
            "duration_min": {"type": "number", "label": "Thời gian", "desc": "Thời gian dự kiến", "min": 2, "max": 240, "step": 1, "unit": "phút"},
            "avg_speed_kmh": {"type": "number", "label": "Tốc độ trung bình", "desc": "Tốc độ trung bình trong chuyến", "min": 10, "max": 100, "step": 1, "unit": "km/h"},
            "max_speed_kmh": {"type": "number", "label": "Tốc độ tối đa", "desc": "Tốc độ tối đa đạt được", "min": 15, "max": 120, "step": 1, "unit": "km/h"},
            "avg_acceleration": {"type": "number", "label": "Gia tốc trung bình", "desc": "Gia tốc trung bình", "min": -3, "max": 3, "step": 0.1, "unit": "m/s²"},
            "max_acceleration": {"type": "number", "label": "Gia tốc tối đa", "desc": "Gia tốc tăng tốc cực đại", "min": 0, "max": 5, "step": 0.1, "unit": "m/s²"},
            "min_acceleration": {"type": "number", "label": "Gia tốc phanh", "desc": "Gia tốc giảm tốc cực đại", "min": -5, "max": 0, "step": 0.1, "unit": "m/s²"},
            "payload_kg": {"type": "number", "label": "Tải trọng", "desc": "Khối lượng người và hành lý", "min": 40, "max": 250, "step": 5, "unit": "kg"},
            "ambient_temp_c": {"type": "number", "label": "Nhiệt độ môi trường", "desc": "Nhiệt độ thời tiết", "min": -10, "max": 50, "step": 1, "unit": "°C"},
            "weather_encoded": {"type": "integer", "label": "Thời tiết", "desc": "0: Nắng ráo, 1: Mưa nhỏ, 2: Mưa lớn", "min": 0, "max": 2, "step": 1, "unit": "mã"},
            "elevation_change_m": {"type": "number", "label": "Độ dốc địa hình", "desc": "Độ chênh cao độ hành trình", "min": -100, "max": 300, "step": 5, "unit": "m"},
        },
        "smoke_input": {
            "distance_km": 10.0,
            "duration_min": 25.0,
            "avg_speed_kmh": 30.0,
            "max_speed_kmh": 55.0,
            "avg_acceleration": 0.0,
            "max_acceleration": 2.0,
            "min_acceleration": -2.0,
            "payload_kg": 75.0,
            "ambient_temp_c": 30.0,
            "weather_encoded": 0,
            "elevation_change_m": 10.0,
        },
        "output_kind": "scalar",
        "legacy_pkl": [],
    },

    "dte": {
        "key": "dte",
        "label": "Quãng đường còn lại linh hoạt",
        "shortName": "Dynamic DTE",
        "group": "survival",
        "phase": "v1.0",
        "status": "ready",
        "icon": "Gauge",
        "accent": "blue",
        "description": "Ước tính quãng đường còn lại dựa trên tình trạng pin và điều kiện vận hành.",
        "useCase": "Hiệu chỉnh quãng đường có thể đi tiếp theo dung lượng pin còn lại, sức khỏe pin SoH, nhiệt độ, tốc độ và tải trọng.",
        "outputDescription": "Quãng đường còn lại dự kiến.",
        "outputUnit": "km",
        "outputMeaning": "Quãng đường xe có thể di chuyển tiếp theo các điều kiện hiện tại.",
        "display_unit": "distance",
        "input_fields": [
            "batteryPercent", "stateOfHealth", "temperatureC",
            "averageSpeedKmh", "payloadKg", "baseEfficiencyKmPerPercent",
        ],
        "visible_input_fields": [
            "batteryPercent", "stateOfHealth", "temperatureC",
            "averageSpeedKmh", "payloadKg", "baseEfficiencyKmPerPercent",
        ],
        "input_schema": {
            "batteryPercent": {"type": "number", "label": "Pin hiện tại", "desc": "Phần trăm dung lượng pin hiện có", "min": 0, "max": 100, "step": 1, "unit": "%"},
            "stateOfHealth": {"type": "number", "label": "Sức khỏe pin", "desc": "Tỷ lệ dung lượng tối đa còn lại (SoH)", "min": 50, "max": 100, "step": 1, "unit": "%"},
            "temperatureC": {"type": "number", "label": "Nhiệt độ", "desc": "Nhiệt độ môi trường vận hành", "min": -10, "max": 50, "step": 1, "unit": "°C"},
            "averageSpeedKmh": {"type": "number", "label": "Tốc độ trung bình", "desc": "Tốc độ hành trình dự kiến", "min": 10, "max": 100, "step": 1, "unit": "km/h"},
            "payloadKg": {"type": "number", "label": "Tải trọng", "desc": "Tổng tải trọng người & hàng hóa", "min": 40, "max": 250, "step": 5, "unit": "kg"},
            "baseEfficiencyKmPerPercent": {"type": "number", "label": "Hiệu suất cơ sở", "desc": "Hiệu suất di chuyển cơ sở", "min": 0.4, "max": 3.0, "step": 0.1, "unit": "km/%"},
        },
        "smoke_input": {
            "batteryPercent": 70.0,
            "stateOfHealth": 95.0,
            "temperatureC": 30.0,
            "averageSpeedKmh": 35.0,
            "payloadKg": 75.0,
            "baseEfficiencyKmPerPercent": 1.2,
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
        "outputUnit": "điểm",
        "outputMeaning": "Điểm số lái xe tiết kiệm năng lượng (0-100).",
        "display_unit": "scalar",
        "input_fields": [
            "hardAccelCount", "hardBrakeCount", "avgSpeed", "maxSpeed",
            "accelerationStd", "tripDurationMin", "idleTimeMin",
        ],
        "visible_input_fields": [
            "hardAccelCount", "hardBrakeCount", "avgSpeed", "maxSpeed",
            "accelerationStd", "tripDurationMin", "idleTimeMin",
        ],
        "input_schema": {
            "hardAccelCount": {"type": "integer", "label": "Tăng tốc mạnh", "desc": "Số lần thốc ga đột ngột", "min": 0, "max": 20, "step": 1, "unit": "lần"},
            "hardBrakeCount": {"type": "integer", "label": "Phanh gấp", "desc": "Số lần phanh gấp", "min": 0, "max": 20, "step": 1, "unit": "lần"},
            "avgSpeed": {"type": "number", "label": "Tốc độ trung bình", "desc": "Tốc độ trung bình", "min": 10, "max": 90, "step": 1, "unit": "km/h"},
            "maxSpeed": {"type": "number", "label": "Tốc độ tối đa", "desc": "Tốc độ cao nhất trong chuyến", "min": 15, "max": 120, "step": 1, "unit": "km/h"},
            "accelerationStd": {"type": "number", "label": "Độ biến thiên gia tốc", "desc": "Độ ổn định chân ga", "min": 0.1, "max": 3.0, "step": 0.1, "unit": "m/s²"},
            "tripDurationMin": {"type": "number", "label": "Thời gian chuyến đi", "desc": "Tổng thời gian di chuyển", "min": 5, "max": 180, "step": 1, "unit": "phút"},
            "idleTimeMin": {"type": "number", "label": "Thời gian dừng", "desc": "Thời gian xe nổ máy nhưng đứng yên", "min": 0, "max": 60, "step": 1, "unit": "phút"},
        },
        "smoke_input": {
            "hardAccelCount": 2,
            "hardBrakeCount": 1,
            "avgSpeed": 25.0,
            "maxSpeed": 55.0,
            "accelerationStd": 0.8,
            "tripDurationMin": 30.0,
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
        "outputUnit": "%",
        "outputMeaning": "Tiêu hao pin dự kiến trên từng tuyến đường.",
        "display_unit": "scalar",
        "input_fields": [
            "route1_distanceKm", "route1_trafficIndex", "route1_elevationGain",
            "route2_distanceKm", "route2_trafficIndex", "route2_elevationGain",
            "currentBattery", "temperature",
        ],
        "visible_input_fields": [
            "route1_distanceKm", "route1_trafficIndex", "route1_elevationGain",
            "route2_distanceKm", "route2_trafficIndex", "route2_elevationGain",
            "currentBattery", "temperature",
        ],
        "input_schema": {
            "route1_distanceKm": {"type": "number", "label": "Tuyến 1 - Khoảng cách", "desc": "Quãng đường tuyến 1", "min": 1, "max": 60, "step": 0.5, "unit": "km"},
            "route1_trafficIndex": {"type": "number", "label": "Tuyến 1 - Ùn tắc", "desc": "Chỉ số ùn tắc tuyến 1 (0: thông thoáng, 1: kẹt xe)", "min": 0, "max": 1, "step": 0.05, "unit": "index"},
            "route1_elevationGain": {"type": "number", "label": "Tuyến 1 - Độ dốc", "desc": "Độ cao tăng thêm tuyến 1", "min": 0, "max": 200, "step": 5, "unit": "m"},
            "route2_distanceKm": {"type": "number", "label": "Tuyến 2 - Khoảng cách", "desc": "Quãng đường tuyến 2", "min": 1, "max": 60, "step": 0.5, "unit": "km"},
            "route2_trafficIndex": {"type": "number", "label": "Tuyến 2 - Ùn tắc", "desc": "Chỉ số ùn tắc tuyến 2 (0: thông thoáng, 1: kẹt xe)", "min": 0, "max": 1, "step": 0.05, "unit": "index"},
            "route2_elevationGain": {"type": "number", "label": "Tuyến 2 - Độ dốc", "desc": "Độ cao tăng thêm tuyến 2", "min": 0, "max": 200, "step": 5, "unit": "m"},
            "currentBattery": {"type": "number", "label": "Pin hiện tại", "desc": "Mức pin hiện có", "min": 10, "max": 100, "step": 1, "unit": "%"},
            "temperature": {"type": "number", "label": "Nhiệt độ", "desc": "Nhiệt độ môi trường", "min": -10, "max": 50, "step": 1, "unit": "°C"},
        },
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
        "label": "Smart Charge",
        "shortName": "Smart Charge",
        "group": "assistant",
        "phase": "v2.0",
        "status": "ready",
        "icon": "Timer",
        "accent": "blue",
        "description": "Dự đoán thời gian sạc bằng AI và tự ngắt nguồn qua Shelly.",
        "useCase": "Pin đang 20%, muốn sạc lên 80%. AI tính toán dựa trên tốc độ sạc trung bình, nhiệt độ, SoH → trả về 'Dự kiến 2h45 phút'. Giúp người dùng lên kế hoạch thời gian.",
        "outputDescription": "Thời gian sạc dự kiến để đạt mức pin mong muốn.",
        "outputUnit": "giây",
        "outputMeaning": "Thời gian cần sạc tính bằng giây; app định dạng thành giờ và phút.",
        "display_unit": "time",
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
        "input_schema": {
            "start_soc": {"type": "number", "label": "Pin hiện tại", "desc": "Mức pin lúc bắt đầu sạc", "min": 0, "max": 100, "step": 1, "unit": "%"},
            "end_soc": {"type": "number", "label": "Pin muốn sạc đến", "desc": "Mức pin mục tiêu", "min": 1, "max": 100, "step": 1, "unit": "%"},
            "ambient_temp_c": {"type": "number", "label": "Nhiệt độ môi trường", "desc": "Nhiệt độ môi trường xung quanh", "min": -20, "max": 60, "step": 1, "unit": "°C"},
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
        "useCase": "8h tối thứ 6, pin còn 30%. AI biết ngày mai user thường đi xa (cần 50%). Đẩy push: 'Pin không đủ cho lịch cuối tuần — sạc đêm nay nhé!'.",
        "outputDescription": "Xác suất cần sạc trong 24h tới + thời điểm gợi ý.",
        "outputUnit": "%",
        "outputMeaning": "Xác suất nên cắm sạc trong vòng 24 giờ tới.",
        "display_unit": "scalar",
        "input_fields": [
            "currentBattery", "dayOfWeek", "avgDailyKm_lastWeek",
            "avgDailyKm_sameDow", "lastChargeHoursAgo", "nightChargeRatio",
            "weekendTrips",
        ],
        "visible_input_fields": [
            "currentBattery", "dayOfWeek", "avgDailyKm_lastWeek",
            "avgDailyKm_sameDow", "lastChargeHoursAgo", "nightChargeRatio",
            "weekendTrips",
        ],
        "input_schema": {
            "currentBattery": {"type": "number", "label": "Pin hiện tại", "desc": "Mức pin hiện có", "min": 0, "max": 100, "step": 1, "unit": "%"},
            "dayOfWeek": {"type": "integer", "label": "Thứ trong tuần", "desc": "1: T2, 2: T3, ..., 7: CN", "min": 1, "max": 7, "step": 1, "unit": "thứ"},
            "avgDailyKm_lastWeek": {"type": "number", "label": "Km TB tuần trước", "desc": "Quãng đường TB mỗi ngày tuần trước", "min": 0, "max": 100, "step": 1, "unit": "km"},
            "avgDailyKm_sameDow": {"type": "number", "label": "Km TB cùng thứ", "desc": "Quãng đường TB vào đúng thứ này", "min": 0, "max": 100, "step": 1, "unit": "km"},
            "lastChargeHoursAgo": {"type": "number", "label": "Lần sạc cuối", "desc": "Số giờ kể từ lần sạc trước", "min": 0, "max": 168, "step": 1, "unit": "giờ"},
            "nightChargeRatio": {"type": "number", "label": "Tỷ lệ sạc đêm", "desc": "Thói quen sạc qua đêm (0-1)", "min": 0, "max": 1, "step": 0.05, "unit": "tỷ lệ"},
            "weekendTrips": {"type": "integer", "label": "Chuyến cuối tuần", "desc": "Số chuyến dự kiến cuối tuần", "min": 0, "max": 10, "step": 1, "unit": "chuyến"},
        },
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
        "outputUnit": "nhãn",
        "outputMeaning": "Mục đích chuyến đi được suy luận bởi AI.",
        "display_unit": "scalar",
        "input_fields": [
            "startLat", "startLng", "endLat", "endLng",
            "startHour", "dayOfWeek", "durationMin", "distanceKm",
            "frequencyLastMonth",
        ],
        "visible_input_fields": [
            "startLat", "startLng", "endLat", "endLng",
            "startHour", "dayOfWeek", "durationMin", "distanceKm",
            "frequencyLastMonth",
        ],
        "input_schema": {
            "startLat": {"type": "number", "label": "Vĩ độ điểm đi", "desc": "Tọa độ vĩ độ nơi xuất phát", "min": 8.0, "max": 24.0, "step": 0.0001, "unit": "°"},
            "startLng": {"type": "number", "label": "Kinh độ điểm đi", "desc": "Tọa độ kinh độ nơi xuất phát", "min": 102.0, "max": 110.0, "step": 0.0001, "unit": "°"},
            "endLat": {"type": "number", "label": "Vĩ độ điểm đến", "desc": "Tọa độ vĩ độ nơi đến", "min": 8.0, "max": 24.0, "step": 0.0001, "unit": "°"},
            "endLng": {"type": "number", "label": "Kinh độ điểm đến", "desc": "Tọa độ kinh độ nơi đến", "min": 102.0, "max": 110.0, "step": 0.0001, "unit": "°"},
            "startHour": {"type": "integer", "label": "Giờ bắt đầu", "desc": "Khung giờ khởi hành (0-23)", "min": 0, "max": 23, "step": 1, "unit": "h"},
            "dayOfWeek": {"type": "integer", "label": "Thứ trong tuần", "desc": "1: T2, ..., 7: CN", "min": 1, "max": 7, "step": 1, "unit": "thứ"},
            "durationMin": {"type": "number", "label": "Thời gian di chuyển", "desc": "Thời gian chạy xe", "min": 2, "max": 180, "step": 1, "unit": "phút"},
            "distanceKm": {"type": "number", "label": "Quãng đường", "desc": "Chiều dài hành trình", "min": 0.5, "max": 100, "step": 0.5, "unit": "km"},
            "frequencyLastMonth": {"type": "integer", "label": "Tần suất tháng trước", "desc": "Số lần đi cung đường tương tự", "min": 0, "max": 60, "step": 1, "unit": "lần"},
        },
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
        "outputUnit": "tháng",
        "outputMeaning": "Thời gian ước tính đến ngưỡng thoái hóa pin.",
        "display_unit": "scalar",
        "input_fields": [
            "currentSoH", "cycleCount", "avgDoD", "fastChargeRatio",
            "avgTempCharging", "monthsInUse", "aggressiveDrivingRatio",
        ],
        "visible_input_fields": [
            "currentSoH", "cycleCount", "avgDoD", "fastChargeRatio",
            "avgTempCharging", "monthsInUse", "aggressiveDrivingRatio",
        ],
        "input_schema": {
            "currentSoH": {"type": "number", "label": "Sức khỏe pin hiện tại", "desc": "SoH hiện tại", "min": 50, "max": 100, "step": 1, "unit": "%"},
            "cycleCount": {"type": "integer", "label": "Số chu kỳ sạc", "desc": "Số chu kỳ sạc-xả tích lũy", "min": 0, "max": 2000, "step": 10, "unit": "chu kỳ"},
            "avgDoD": {"type": "number", "label": "Độ sâu xả trung bình", "desc": "Độ sâu xả pin bình quân (0-1)", "min": 0.1, "max": 1.0, "step": 0.05, "unit": "DoD"},
            "fastChargeRatio": {"type": "number", "label": "Tỷ lệ sạc nhanh", "desc": "Tần suất dùng sạc công suất lớn", "min": 0, "max": 1, "step": 0.05, "unit": "tỷ lệ"},
            "avgTempCharging": {"type": "number", "label": "Nhiệt độ sạc TB", "desc": "Nhiệt độ pin khi cắm sạc", "min": 15, "max": 55, "step": 1, "unit": "°C"},
            "monthsInUse": {"type": "integer", "label": "Số tháng sử dụng", "desc": "Thời gian xe lăn bánh", "min": 1, "max": 120, "step": 1, "unit": "tháng"},
            "aggressiveDrivingRatio": {"type": "number", "label": "Tỷ lệ lái gắt", "desc": "Tỷ lệ tăng tốc mạnh/thốc ga", "min": 0, "max": 1, "step": 0.05, "unit": "tỷ lệ"},
        },
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
        "useCase": "Chuyến 5km, model SOC đoán tốn 5% nhưng thực tế tụt 12%. Lặp lại 4-5 chuyến → cảnh báo đỏ: 'Lốp non hơi hoặc cell pin lỗi — đi kiểm tra!'.",
        "outputDescription": "Anomaly score (0-1) + nhãn nguyên nhân gợi ý + trend 30 ngày.",
        "outputUnit": "score",
        "outputMeaning": "Chỉ số bất thường từ 0 (bình thường) đến 1 (nghiêm trọng).",
        "display_unit": "scalar",
        "input_fields": [
            "predictedSoCDrop", "actualSoCDrop", "tripDistanceKm",
            "avgSpeed", "temperature", "consecutiveAnomalies",
        ],
        "visible_input_fields": [
            "predictedSoCDrop", "actualSoCDrop", "tripDistanceKm",
            "avgSpeed", "temperature", "consecutiveAnomalies",
        ],
        "input_schema": {
            "predictedSoCDrop": {"type": "number", "label": "Tụt pin dự đoán", "desc": "Mức pin ước tính tiêu thụ", "min": 0, "max": 50, "step": 0.5, "unit": "%"},
            "actualSoCDrop": {"type": "number", "label": "Tụt pin thực tế", "desc": "Mức pin thực tế bị tụt", "min": 0, "max": 50, "step": 0.5, "unit": "%"},
            "tripDistanceKm": {"type": "number", "label": "Quãng đường", "desc": "Chiều dài chuyến đi", "min": 0.5, "max": 100, "step": 0.5, "unit": "km"},
            "avgSpeed": {"type": "number", "label": "Tốc độ trung bình", "desc": "Vận tốc trung bình", "min": 5, "max": 100, "step": 1, "unit": "km/h"},
            "temperature": {"type": "number", "label": "Nhiệt độ môi trường", "desc": "Nhiệt độ khi vận hành", "min": -10, "max": 50, "step": 1, "unit": "°C"},
            "consecutiveAnomalies": {"type": "integer", "label": "Số lần bất thường liên tiếp", "desc": "Số chuyến gần nhất bị lệch lớn", "min": 0, "max": 10, "step": 1, "unit": "chuyến"},
        },
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
