# VinFast Battery — Developer & AI Agent Master Guide

> **Dành cho AI Agent & Kỹ sư phát triển**: Đây là tài liệu kỹ thuật tập trung duy nhất mô tả toàn bộ kiến trúc, thành phần, luồng dữ liệu, schema và quy ước phát triển của hệ sinh thái **VinFast Battery**. Bất kỳ Agent nào khi tiếp nhận dự án đều có thể đọc tài liệu này để nắm toàn bộ codebase trong 1 lần đọc.

---

## 1. Tổng Quan Hệ Sinh Thái & Topology

VinFast Battery là nền tảng quản lý pin xe máy điện (Feliz, Evo, Klara, Vento, Theon...) tích hợp AI và sạc thông minh IoT.

```text
                                       ┌──────────────────────────────────────────────┐
                                       │              CLIENT LAYER                    │
                                       │  - Flutter Mobile App (Android/iOS)          │
                                       │  - React 18 / Vite Admin Dashboard (Web)    │
                                       └──────────────────────┬───────────────────────┘
                                                              │
                                            HTTPS / Quick Tunnel / Tailscale
                                                              ▼
                                       ┌──────────────────────────────────────────────┐
                                       │          UNIFIED FLASK API (server.py)       │
                                       │  - Port 5000 (Local) / Custom Domain (Cloud) │
                                       │  - Request ID (X-Request-Id), Error Envelope │
                                       │  - Firebase Auth Token & RBAC Middleware     │
                                       │  - Idempotent Onboarding Commit Engine       │
                                       │  - Vehicles, Trips, ChargeLogs, Telemetry    │
                                       └───────────┬──────────────────────┬───────────┘
                                                   │                      │
                                 gRPC / REST       │                      │ HTTP Internal
                                 (Service Account) │                      │ Port 8001
                                                   ▼                      ▼
                     ┌────────────────────────────────┐   ┌────────────────────────────────┐
                     │    FIREBASE / FIRESTORE        │   │    FASTAPI AI SERVICE          │
                     │  - Users, Vehicles, ChargeLogs │   │    (web/ai_server/main.py)     │
                     │  - OnboardingDrafts (secure)   │   │  - ModelStore & Registry       │
                     │  - TelemetryPoints             │   │  - Range / Charging Time / SoC │
                     │  - AuditLogs, ChargeFeedback   │   │  - Personal AI & Drift Monitor │
                     └────────────────────────────────┘   └────────────────────────────────┘
                                                                  ▲
                                                                  │ Sync telemetry
                                                                  ▼
                                       ┌──────────────────────────────────────────────┐
                                       │       SMART CHARGER GATEWAY (FastAPI)        │
                                       │  - smart_charger_gateway/main.py (Port 8002) │
                                       │  - Hardware Watchdog: Safe max 12A / 2500W   │
                                       │  - Shelly Plug S Gen3 (Cloud / optional LAN) │
                                       └──────────────────────────────────────────────┘
```

---

## 2. Bản Đồ Thư Mục (Codebase Directory Map)

```text
Vinfast-Batery/
├── app/                              # Flutter Mobile Application (iOS/Android)
│   ├── lib/
│   │   ├── core/                     # Constants, AppTheme, Utilities, Global Providers
│   │   │   ├── constants/            # app_constants.dart (API Base URL, build info)
│   │   │   ├── providers/            # auth_provider, vehicle_provider, battery_provider...
│   │   │   └── widgets/              # InternetConnectionNotice, Status strips
│   │   ├── features/
│   │   │   ├── auth/                 # AuthGate, Login, Register
│   │   │   ├── onboarding/           # Onboarding chat, OnboardingDraft, OnboardingSyncCoordinator
│   │   │   ├── home/                 # HomeScreen, Battery gauge, Quick actions
│   │   │   ├── dashboard/            # DashboardScreen, Fleet stats, Energy graph
│   │   │   ├── battery/              # BatteryMonitorScreen, Cell health, Temperature
│   │   │   ├── trip/                 # TripPlannerScreen, GPS tracking, Live route
│   │   │   ├── smart_charging/       # SmartChargingControlScreen, Target SoC, Schedule
│   │   │   ├── ai/                   # AI Chatbot, Range & charging time widgets, Model lab
│   │   │   │   ├── controllers/      # chat_controller, behavior_tracker (Riverpod)
│   │   │   │   ├── models/           # chat_session, chat_message, behavior_profile
│   │   │   │   ├── services/         # chat_api_service, behavior_sync_service, suggestion_service
│   │   │   │   └── widgets/          # chat_message_bubble, action_confirmation_card, streaming_text
│   │   │   └── settings/             # SettingsScreen, Vehicle profile, Server config
│   │   └── navigation/               # app_navigation.dart (AppNavigation shell & routes)
│   └── test/                         # Flutter Unit & Widget tests
│
├── web/                              # Backend Services & Admin Portal
│   ├── server.py                     # Unified Flask API (Entrypoint chính: Port 5000)
│   ├── vehicle_catalog.py            # Quản lý danh mục xe EV & thông số kỹ thuật pin
│   ├── ai_server/                    # FastAPI AI Service (Entrypoint: Port 8001)
│   │   ├── main.py                   # Prediction endpoints & Model Lifecycle API
│   │   ├── chat_engine.py            # [AI Chatbot] Gemini API wrapper & prompt builder
│   │   ├── chat_tools.py             # [AI Chatbot] Function calling tool definitions
│   │   ├── chat_memory.py            # [AI Chatbot] Conversation context manager
│   │   ├── behavior_analyzer.py      # [AI Chatbot] User behavior aggregation
│   │   ├── suggestion_engine.py      # [AI Chatbot] Proactive suggestion rules
│   │   ├── chat_schemas.py           # [AI Chatbot] Pydantic models for chat API
│   │   ├── models/                   # TFLite & PKL model storage
│   │   └── fine_tune.py              # Personal AI fine-tuning pipeline
│   ├── dashboard/                    # React 18 + Vite + TypeScript Admin Dashboard
│   │   ├── src/components/ai-center/ # Model lab, AI monitoring & evaluation
│   │   └── src/pages/                # Dashboard, Vehicles, Telemetry, Gateway management
│   ├── shelly/                       # Shelly Cloud & LAN integration utilities
│   ├── cloudrun/                     # Manifests & contracts cho Google Cloud Run
│   └── tests/                        # Toàn bộ backend test suites (Pytest)
│
├── smart_charger_gateway/            # IoT Hardware Gateway (FastAPI: Port 8002)
│   ├── main.py                       # Gateway REST API & RPC handlers
│   ├── shelly.py                     # Shelly Plug S Gen3 driver & power telemetry polling
│   ├── safety_monitor.py             # Watchdog giám sát an toàn (ngắt khi >12A, quá nhiệt)
│   └── tests/                        # Gateway unit & mock tests (Pytest)
│
├── docs/
│   ├── specs/                        # Các đặc tả kỹ thuật chi tiết
│   │   ├── AI_LIFECYCLE.md           # Quy trình huấn luyện, drift, canary AI
│   │   ├── TELEMETRY_SCHEMA.md       # Schema chuẩn pin & sạc
│   │   ├── VEHICLE_CATALOG.md        # Danh mục xe và định mức pin
│   │   ├── START_LAPTOP_SERVER.md    # Hướng dẫn chạy server local với Tailscale/Tunnel
│   │   ├── IOS.md                    # Hướng dẫn build/test trên iOS
│   │   └── AI_CHATBOT_PERSONALIZATION.md  # Đặc tả AI Chatbot cá nhân hóa & kế hoạch triển khai
│   └── archive/                      # Kho lưu trữ các kế hoạch và audit cũ (được giữ để đối soát)
│
├── AGENTS.md                         # (File này) Cẩm nang kiến trúc dành cho Agent
├── PROJECT_STATUS.md                 # Single Source of Truth: Tiến độ, Release Gates & Changelog
├── SMART_CHARGE_SETUP_GUIDE.md       # Hướng dẫn đấu nối và cấu hình phần cứng Shelly
└── README.md                         # Trang thông tin tổng quan của dự án
```

---

## 3. Các Luồng Nghiệp Vụ & Quy Chuẩn Kỹ Thuật Cốt Lõi

### 3.1. Xác thực & Kết nối API
- **Client → Backend**: Gửi Bearer Firebase ID token qua header `Authorization`.
- **Request ID**: Mọi request backend tự gắn `X-Request-Id` (UUID) và trả về trong response header lẫn body.
- **Error Envelope**: Chuẩn hóa lỗi dạng JSON:
  ```json
  {
    "code": "BAD_REQUEST",
    "userMessage": "Thông báo thân thiện người dùng",
    "requestId": "uuid",
    "retryable": false,
    "error": "Chi tiết kỹ thuật tương thích cũ"
  }
  ```
- **Readiness Probe**: Endpoint `GET /api/ready` trả `200` khi Firebase sẵn sàng; trả `503` nếu thiếu cấu hình lõi.

### 3.2. Luồng Onboarding & Idempotency
- Khảo sát người dùng lưu draft cục bộ (`OnboardingDraft` trong Secure Storage) và Firestore (`users/{uid}/onboardingDrafts/current`).
- Commit qua `POST /api/mobile/onboarding/commit` với header `Idempotency-Key`.
- Server xác thực tuổi tối thiểu, ODO, thông số pin và lưu document ID xác định, ngăn chặn hoàn toàn việc tạo xe trùng lặp khi retry mạng yếu.

### 3.3. Battery Telemetry Schema v1 (`battery-telemetry/v1`)
Mọi điểm dữ liệu đo đạc tuân thủ cấu trúc:
```json
{
  "schemaVersion": "battery-telemetry/v1",
  "vehicleId": "VF-FELIZ-001",
  "chargerId": "shelly-plug-s-gen3-01",
  "chargingSessionId": "session-20260905-001",
  "recordedAt": "2026-09-21T10:30:00Z",
  "measurements": {
    "soc": { "value": 75.0, "unit": "%", "source": "bms", "confidence": 1.0, "measuredAt": "2026-09-21T10:30:00Z" },
    "power": { "value": 2200, "unit": "W", "source": "shelly_meter", "confidence": 0.98, "measuredAt": "2026-09-21T10:30:00Z" }
  }
}
```
- Các chỉ số: `soc`, `soh` (`%`), `voltage` (`V`), `power` (`W`), `energy` (`Wh`).
- Mọi đơn vị kW/kWh được backend tự động chuyển về W/Wh.

### 3.4. AI Lifecycle & Quản Trị Mô Hình
- **Huấn luyện & Canary**: Candidate chỉ được triển khai Canary 10% khi có tối thiểu 20 mẫu test, MAE cải thiện ≥2%, RMSE không xấu hơn 3%, bias không tăng.
- **Personal AI**: Chỉ kích hoạt khi xe có tối thiểu 30 mẫu telemetry đã xác thực trải qua ít nhất 14 ngày. Chưa đủ điều kiện luôn fallback về Base Model.

### 3.5. Smart Charging & An Toàn Phần Cứng (IoT)
- **Tải tối đa cho phép**: ≤ 12A / 2500W (tiêu chuẩn an toàn điện áp lưới sinh hoạt).
- **Safety Watchdog**: Tự động ngắt relay khi nhiệt độ Shelly vượt ngưỡng (>75°C), công suất vượt định mức hoặc mất heartbeat quá 60s.
- **Auto Cutoff**: Ngắt relay ngay khi SoC đạt mức mục tiêu được thiết lập bởi người dùng (Target SoC).

### 3.6. Cơ Chế Kết Nối Shelly 3-Flow & Cấp Mã Admin (v1.1.6+)
- **Flow 1 (mDNS/LAN Auto-discovery)**: Ứng dụng tự động quét mạng nội bộ tìm kiếm thiết bị Shelly Plug S Gen3 qua mDNS.
- **Flow 2 (Cloud / AP Fallback)**: Khi không tìm thấy qua quét cục bộ, chuyển sang kết nối qua Shelly Cloud API hoặc Access Point của thiết bị.
- **Flow 3 (Admin Connection Code)**: Khi cả Flow 1 & Flow 2 không thể kết nối, người dùng nhập mã kết nối 6 ký tự do Quản trị viên cung cấp.
  - Admin tạo thiết bị và sinh mã tại trang `/shelly` trên Web Dashboard (`POST /api/admin/shelly-devices`).
  - Server tạo mã 6 ký tự ngẫu nhiên (uppercase alphanumeric), lưu trữ trong Firestore `shellyConnectionCodes` (hạn dùng 24h, vô hiệu hóa ngay sau khi đổi).
  - Mobile App gửi mã qua `POST /api/shelly/redeem-code` để nhận cấu hình Shelly mã hóa và tự động liên kết xe an toàn.

### 3.7. AI Chatbot Cá Nhân Hóa & Behavior Learning
- **LLM Engine**: Google Gemini API (2.0 Flash / Pro), gọi qua backend proxy, API key chỉ lưu server-side.
- **Behavior Learning**: Thu thập thói quen sạc, lịch sử chuyến đi, thời gian dùng app, tương tác chatbot, tùy chọn cài đặt → lưu hybrid (local Hive + Firestore `users/{uid}/behaviorProfile/current`).
- **Personalized Prompt**: System prompt được inject behavior profile (giờ sạc ưa thích, quãng đường hàng ngày, chủ đề hay hỏi...) → câu trả lời khác biệt theo từng user.
- **Function Calling**: 9 tools (get_battery_status, start_smart_charging, schedule_charging...). Các tool điều khiển phần cứng (bật/tắt sạc) **bắt buộc Human-in-the-Loop** qua Action Confirmation Card.
- **SSE Streaming**: Response trả qua Server-Sent Events, hiển thị từng chữ trên Flutter.
- **Chat History**: Hybrid local Hive + Firestore backup 30 ngày. Sliding window 20 messages cho context.
- **Proactive Suggestions**: 8 rules chủ động gợi ý (pin thấp, nhắc bảo dưỡng, tips tiết kiệm pin...). Rate limit 1 bubble/30 phút, 5/ngày.
- **Feedback Loop**: 👍/👎 trên mỗi câu trả lời → điều chỉnh response style và topic ranking.
- **Đặc tả chi tiết**: Xem `docs/specs/AI_CHATBOT_PERSONALIZATION.md`.

---

## 4. Lệnh Kiểm Thử & Kiểm Soát Chất Lượng Chuẩn

Trước khi hoàn tất bất kỳ task nào, chạy các lệnh kiểm thử liên quan:

```bash
# 1. Backend Flask & AI Services (web/tests)
cd web
python -m pytest tests -v

# 2. Smart Charger Gateway (smart_charger_gateway/tests)
cd ../smart_charger_gateway
python -m pytest tests -v

# 3. Flutter Mobile App (app/)
cd ../app
flutter test

# 4. Admin Dashboard (web/dashboard)
cd ../web/dashboard
npm run lint
npm run build
```

---

## 5. Quy Tắc Bắt Buộc Khi Làm Việc Cho AI Agent

1. **KHÔNG TỰ Ý TẠO FILE `.md` MỚI**:
   - Tuyệt đối không tạo các file như `PLAN.md`, `PLANx.md`, `QA_AUDIT_xxx.md`, `REPORT_xxx.md` rải rác trong repo.
2. **CẬP NHẬT `PROJECT_STATUS.md` SAU MỖI TASK**:
   - Mọi tiến độ, thay đổi code, kết quả kiểm thử và trạng thái blocker/task phải được ghi vào [PROJECT_STATUS.md](PROJECT_STATUS.md) mục **Task Completion Log**.
3. **GIỮ NGUYÊN KIẾN TRÚC TỐI THIỂU**:
   - Bất kỳ tài liệu giải thích chi tiết mới nào phải nằm trong `docs/specs/` hoặc gộp vào `AGENTS.md`.
