# VinFast Battery — Developer & AI Agent Master Guide

> **Dành cho AI Agent & Kỹ sư phát triển**: Đây là tài liệu kỹ thuật tập trung duy nhất mô tả toàn bộ kiến trúc, thành phần, luồng dữ liệu, schema và quy ước phát triển của hệ sinh thái **VinFast Battery**. Bất kỳ Agent nào khi tiếp nhận dự án đều có thể đọc tài liệu này để nắm toàn bộ codebase trong 1 lần đọc.

---

## 1. Tổng Quan Hệ Sinh Thái & Topology

**Pinova** (trước là "VinFast Battery"; đổi tên 20/10/2026, QA 133) là nền tảng quản lý pin xe máy điện VinFast (Feliz, Evo, Klara, Vento, Theon...) tích hợp AI và sạc thông minh IoT. Trợ lý là **Pinova Bot** (mã vẫn tên `BatteryBot*`). Logo/nguồn ảnh: `app/brand/`; package Android `com.bes.vinbatery` giữ nguyên.

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

  Sạc thông minh: server.py + smart_charge_worker.py (Azure) ──► Shelly Cloud ──► Shelly Plug S Gen3
  (ngưỡng an toàn 12A / 2500W, readback, tự ngắt theo %/hẹn giờ). Gateway LAN cũ đã gỡ (QA 131).
  BatteryBot: web/assistant/ ──► Gemini qua relay APIM (docs/specs/BATTERYBOT_ASSISTANT.md).
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
│   │   ├── features/                 # (rà soát 13/10/2026, Task 115 — đã xóa code không dùng)
│   │   │   ├── auth/                 # AuthGate, Getting started, Login/Register, Survey (onboarding_chat_screen)
│   │   │   ├── overview/ · home/     # Tab Tổng quan (luxe hero, thẻ, biểu đồ 7 ngày)
│   │   │   ├── charge/               # Tab Sạc pin → ai/smart_charging_control_screen
│   │   │   ├── ai/                   # Sạc AI/hẹn giờ, Lịch sử sạc, BatteryBot (assistant_sheet)
│   │   │   │   ├── controllers/      # smart_charging_controller
│   │   │   │   ├── models/ services/ # chat models, tool gateway, local calibration
│   │   │   │   └── widgets/          # luxe dial, history_luxe_widgets, xác nhận Start/Stop, action_confirmation_card
│   │   │   ├── achievements/         # Thành tựu + hạng (sổ cái local + users/{uid}/achievements/summary)
│   │   │   ├── maintenance/          # Lịch bảo dưỡng (trục ODO, lịch chuẩn VinFast)
│   │   │   ├── smart_charging/       # Kết nối/thiết lập Shelly (3-flow, mã admin)
│   │   │   ├── battery_monitor/ · trip_planner/ · notifications/
│   │   │   ├── more/                 # Tab Cài đặt (menu)
│   │   │   └── settings/             # SettingsScreen, Vehicle profile, Server config
│   │   └── navigation/               # app_navigation.dart (AppNavigation shell & routes)
│   └── test/                         # Flutter Unit & Widget tests
│
├── web/                              # Backend Services & Admin Portal
│   ├── server.py                     # Unified Flask API (Entrypoint chính: Port 5000)
│   ├── vehicle_catalog.py            # Quản lý danh mục xe EV & thông số kỹ thuật pin
│   ├── ai_server/                    # FastAPI AI Service (Entrypoint: Port 8001)
│   │   ├── main.py                   # Prediction endpoints & Model Lifecycle API
│   │   └── fine_tune.py              # Personal AI fine-tuning pipeline
│   ├── dashboard/                    # React 18 + Vite + TypeScript Admin Dashboard
│   │   ├── src/components/ai-center/ # Model lab, AI monitoring & evaluation
│   │   └── src/pages/                # Dashboard, Vehicles, Telemetry, Gateway management
│   ├── assistant/                    # BatteryBot v2 (Gemini qua relay, kiến thức, bộ nhớ, quota)
│   ├── shelly/                       # Shelly Cloud: phiên sạc, an toàn, học Wh/%
│   ├── models/                       # Model registry (manifest + artifact)
│   └── tests/                        # Toàn bộ backend test suites (Pytest)
│
├── deploy/azure/                     # Bicep + script rollout (bằng chứng ghi vào docs/qa_evidence)
├── tools/                            # Quality gate, kiểm tra image/container, dọn workspace
│
├── docs/
│   ├── specs/                        # Các đặc tả kỹ thuật chi tiết
│   │   ├── AI_LIFECYCLE.md           # Quy trình huấn luyện, drift, canary AI
│   │   ├── TELEMETRY_SCHEMA.md       # Schema chuẩn pin & sạc
│   │   ├── VEHICLE_CATALOG.md        # Danh mục xe và định mức pin
│   │   ├── START_LAPTOP_SERVER.md    # Hướng dẫn chạy server local với Tailscale/Tunnel
│   │   ├── IOS.md                    # Hướng dẫn build/test trên iOS
│   │   └── BATTERYBOT_ASSISTANT.md   # BatteryBot v2 hiện hành (đã gộp đặc tả chatbot cũ)
│   └── qa_evidence/                  # Chỉ bằng chứng rollout/gate deploy (QA cũ đã dọn 19/10/2026)
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
- **Task 125:** `X-Request-Id` hợp lệ từ client được giữ nguyên; mỗi request `/api/*` ghi một dòng `[access]` JSON (route mẫu, status, ms) vào Log Analytics `law-vinfast-battery` (30 ngày, trần 0,5 GB/ngày); lỗi 500 dùng `_internal_error` (không trả `str(e)`); route blueprint trả `error` object vẫn có `code`/`userMessage` chuỗi.

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
- **Auto Cutoff (Task 126, hiện thực thật)**: phiên `stop_mode=target` — máy chủ (`/live` + worker 30 s) tắt khi Wh đã nạp + P×20 s ≥ `wh_per_pct`×(mục tiêu − đầu) → `target_reached`; xe < 15 W liên tục 3 phút → `charger_idle`; `toggle_after` trên Shelly là **trần** `min(600 phút, dự đoán×1,5 + 20 phút)` để vẫn tự tắt khi máy chủ chết (`ceiling_timer`). Mô hình chung `web/shelly/charge_model.py` ↔ `ChargeEstimator.wallSeconds` (vector `web/tests/fixtures/charge_model_vectors.json`); `wh_per_pct` học từ % user đọc trên đồng hồ xe (`confirm_actual_soc`, hồ sơ `learned`). Ước tính vẫn `isDisplayOnly`; ON vẫn chỉ qua vuốt. Lịch sử rác (< 30 Wh, chưa xác nhận %) ẩn theo `history_quality` (không xóa). Lộ trình: `TripEnergyModel` ↔ `web/assistant/trip_model.py` (vector `trip_model_vectors.json`); BatteryBot `estimate_trip`/`estimate_charge`/`plan_trip`/`prepare_target_charging`.
- **Task 127 (16/10/2026) — học do user bấm, pin đầy, số đọc:** mọi phiên (cả hẹn giờ) tắt `battery_full` khi sau đỉnh ≥ 150 W công suất < 40 W liên tục 5 phút và là đuôi sạc thật (không phải rút xe 420 → 0 W) → SoC 100 %, nhãn tự động. Dữ liệu chỉ **xếp hàng** (`learned.pending`, `users/{uid}/tripSamples`, `users/{uid}/batteryReadings`); ước tính đổi khi user bấm Huấn luyện ở AI cá nhân (`/api/learning/<vid>/status|train|readings|trips`, `web/shelly/learning.py`), luôn giữ bản cũ nếu kém hơn; app báo một lần khi đủ (sạc ≥ 3 mẫu mới, chuyến ≥ 10). Lộ trình v2: %/km theo tốc độ TB (chữ U), tải, mưa — hệ số fit từ 77 chuyến thật của chủ xe (`web/tests/fixtures/owner_rides_sample.csv`), nguồn `model|odo|catalog`. % pin/ODO: nhập tay, BatteryBot (ghi số đọc `chat`) hoặc ảnh đồng hồ đọc trên máy (`DashboardReader`, ML Kit; iOS ≥ 15.5); hai số đọc không có sạc ở giữa = một chuyến `odo_segment`.

- **QA 129 (18/10/2026) — một nguồn số liệu:** km/% và quãng đường chỉ qua `estimateRange` (`range_estimator.dart`: mô hình chuyến đã học > catalog×SoH) với `learnedModelsProvider` (server `/api/learning/<vid>/status`; invalidate sau Huấn luyện); thời gian sạc ngoài tab Sạc dùng Wh/% + công suất đã học. Giám sát pin chỉ hiện dữ liệu thật (không nhiệt độ/cell/N/A, không ghi Firestore khi mở). Trạng thái phiên = kết quả, "thiếu số đo" là ý riêng. Máy chủ ghi Trung tâm thông báo cho mọi phiên kết thúc (`write_inbox_item`, id như app). Sổ cái Thành tựu theo xe, ngưỡng 30 Wh, đồng bộ toàn bộ mỗi 24 h. Số đọc pin cập nhật `batteryDataUpdatedAt`. Nhóm nghìn = khoảng trắng hẹp (`core/utils/number_text.dart`), thập phân dấu chấm.
- **QA 131 (18/10/2026) — quét đồng hồ:** `scanDashboard()` (`features/ai/dashboard_scan_screen.dart`, gói `camera`) quét trực tiếp, `DashboardLayoutParser` đọc theo vị trí chữ (%, ODO/KM, loại tốc độ/°C, chữ số 7 đoạn, ghép "48 18", ODO cũ làm mốc), `DashboardScanVote` khóa khi 3/6 khung trùng; kết quả chỉ điền sẵn sheet, user vẫn bấm Lưu. Số trên LCD đọc bằng `SevenSegmentReader` (Dart thuần, isolate; ML Kit chỉ dự phòng vì không đọc được chữ số 7 đoạn), fixture ảnh thật `test/fixtures/dashboard`. Giao diện (Cài đặt → Giao diện, `appearanceProvider`, lưu `users/{uid}/smartChargePreferences/appearance`): Tổng quan luxe/lcd/compact/minimal, Sạc dial/bar/lcd/detail, bật sạc slide/hold/tap (`ChargeConfirmControl`; tap là lựa chọn của chủ app 19/10/2026, mặc định vẫn vuốt, vẫn sau ô xác nhận). Ảnh xe: một nguồn `VehicleImages`/`VehiclePhoto` (`core/widgets/vehicle_photo.dart`; Feliz = `assets/vehicles/feliz_mint.webp`), đã bỏ trình xem 360°. Không chạy `flutter test integration_test`/`flutter run` trên điện thoại của user.

### 3.5.1. Xác nhận bật/tắt sạc (Task 115)
- **Bật relay mặc định "vuốt để sạc"** (QA 131: user có thể đổi sang Giữ 1 giây hoặc Bấm 1 lần trong Cài đặt → Giao diện; mọi kiểu vẫn sau ô xác nhận/thẻ BatteryBot) (`core/widgets/luxe_slide_to_confirm.dart`): sheet Bắt đầu (sau ô xác nhận "pin là ước tính") và thẻ BatteryBot cho tool `start_timed_charging` (`ActionConfirmationCard.energizingTool`). Một lần chạm không bao giờ bật relay; TalkBack kích hoạt bằng chạm đúp.
- **Tắt sạc là nút bấm thường** (không thêm thao tác cản trở OFF). Giao diện chỉ là bước xác nhận; repository vẫn kiểm tra backend tươi trước mọi lệnh.

### 3.6. Cơ Chế Kết Nối Shelly 3-Flow & Cấp Mã Admin (v1.1.6+)
- **Flow 1 (mDNS/LAN Auto-discovery)**: Ứng dụng tự động quét mạng nội bộ tìm kiếm thiết bị Shelly Plug S Gen3 qua mDNS.
- **Flow 2 (Cloud / AP Fallback)**: Khi không tìm thấy qua quét cục bộ, chuyển sang kết nối qua Shelly Cloud API hoặc Access Point của thiết bị.
- **Flow 3 (Admin Connection Code)**: Khi cả Flow 1 & Flow 2 không thể kết nối, người dùng nhập mã kết nối 6 ký tự do Quản trị viên cung cấp.
  - Admin tạo thiết bị và sinh mã tại trang `/shelly` trên Web Dashboard (`POST /api/admin/shelly-devices`).
  - Server tạo mã 6 ký tự ngẫu nhiên (uppercase alphanumeric), lưu trữ trong Firestore `shellyConnectionCodes` (hạn dùng 24h, vô hiệu hóa ngay sau khi đổi).
  - Mobile App gửi mã qua `POST /api/shelly/redeem-code` để nhận cấu hình Shelly mã hóa và tự động liên kết xe an toàn.
- **Task 108 (11/10/2026) — luồng hiện hành `server_cloud`/`vault_cloud` qua Azure:** redeem nâng cả liên kết legacy; ON chỉ sau safety test không tải (timer 20s). Mọi lệnh Cloud qua `CloudDispatchGate` (1 in-flight, giãn 1,1s). Lỗi đọc tạm thời (`TRANSIENT_READ_CODES`) **không** được đánh dấu phiên `unknown`. Đọc trạng thái dùng cache ngắn (profile 60s, status idle 10s khi relay OFF, capabilities 30s); lệnh/ON/kiểm tra an toàn luôn đọc tươi. App: `ShellyConnectionCoordinator` là nguồn trạng thái chung (snapshot lưu, grace 3 phút); poll `/live` 60s khi rảnh, 5s khi sạc, chỉ khi foreground. Timeout lệnh điều khiển 45s, tool chat 120s. Gói Firebase Spark: luôn `limit()` khi đọc chẩn đoán. Chi tiết và việc còn mở: `PROJECT_STATUS.md` mục 108.
- **Task 123 (14/10/2026) — lệnh nhanh, đồng bộ một nguồn:** ON = 3 lượt Cloud (`prepare_on` GET an toàn → `set` → readback), context >6s đọc lại, trong slot vẫn `_assert_safety_context` ≤10s; không retry ON. OFF đọc lại ≤5 lần; Cloud chưa báo OFF thì phiên `stopping` + `offPendingReadback` (app **không** gửi OFF lần 2), reconcile/worker kết thúc `cancelled/manual`, quá 25s mới OFF dự phòng. API min 1 replica. GET dùng cache kiểm thu hồi token 5 phút. App: 1 controller/xe (args theo `vehicleId`), controller ↔ coordinator hai chiều, burst đọc 1/2/4/7s sau lệnh, `forgetLive` bỏ bản đọc cũ đang chạy, server mode không POST telemetry. Ước tính dùng `ChargeEstimator`/`estimateRangeKm`/`formatChargeDuration` dùng chung, luôn `isDisplayOnly`. Cập nhật sau (15/10): gate Shelly Cloud + lease/heartbeat worker ở Azure Table `shellyDispatch` (`SHELLY_DISPATCH_TABLE_ACCOUNT`, `SHELLY_CONTROL_STATE=table`; rollback `16-vehicle-media.ps1 -DisableDispatch`); BatteryBot gửi lệnh không đọc `/live` trước/sau, tin phản hồi máy chủ (từ chối 403/404/409 trước lệnh → báo rõ, lỗi khác `unknown`, không gửi lại ON); TẮT đã đọc lại OFF thì trả lời ngay, ghi kết thúc phiên chạy nền (reconcile hoàn tất nếu lỗi); ON đã xác minh gửi push dữ liệu cho mọi điện thoại cùng tài khoản (`SmartChargeRemoteEvents`). Audit lệnh có `timings_ms`. Phiên/vault/liên kết/membership/khóa thiết bị vẫn ở Firestore (giai đoạn 2 chưa làm).
- **Task 125 (15/10/2026) — rà soát & sửa an toàn:** reconcile (`/live`, worker) không đụng phiên `arming/starting` <60 s; lưu `active` bị xung đột → tắt ổ + 409 `sessionChangedElsewhere`; `get_session` đọc tươi phiên chưa kết thúc; lease cổng Cloud 20 s; `/live` một truy vấn phiên/poll + cache membership 60 s. Server mode: app không ghi ChargeLog/active session (server là nguồn ghi duy nhất); Dừng không bị chặn bởi một lần đọc lỗi; tab Sạc key theo `vehicleId`; đếm ngược dùng `SmartChargerStatus.readAt`/`timerRemainingAt`. Thông báo phiên sạc id `<uid>_sc_<session>_<state>`. Production không có `DEV_ADMIN_KEY`; decorator `developer` chỉ theo `_dev_admin_allowed()`. Mã kết nối: 24 h (≤168), 1 lần, 10 lần sai/10 phút/tài khoản. File `.env` không được commit.

### 3.6.1. Ngôn ngữ thiết kế LUXE (Tasks 117–121)
- **Dark-only.** `AppTheme.darkTheme` = `LuxeTheme.data()` (`core/theme/luxe_theme.dart`), dựng một lần. `lightTheme`/`amoledTheme` đã deprecated và cũng trả LUXE. `SettingsService.getThemeModeValue()` luôn là `dark`.
- **Màu:**
  - Nền `#050506`, chữ `#F2F2F0`, muted `#9A9EA5`, dim `#858990` (≥4,5:1 trên mọi lớp nền).
  - Glass/hairline là trắng alpha; platinum là thang `platinumHi…platinumLow`.
  - Accent duy nhất cho trạng thái đã xác minh là **emerald** `#34D399`. Champagne `#E8C170` cho ước tính/cảnh báo, rose `#F59E9E` cho lỗi/nguy hiểm, steel `#9DB8E8` cho thông tin.
  - `CockpitColors`, `AppColors` và `AppUiColors` chỉ còn là alias trỏ về LUXE. Code mới dùng `LuxeColors`.
- **Kit:**
  - `core/widgets/luxe_kit.dart`: `LuxeScaffold`, `LuxeAppBar`, `LuxeCircleButton`, `showLuxeSheet`/`LuxeSheetHeader`, `LuxePageHeaderText`, `LuxeCountUp`, `LuxeStatTile`, `LuxeRing`, `LuxeSparkline`, `LuxeEmptyArt`, `LuxeShimmer`, `LuxeSegmented`, `LuxeNotice`.
  - `core/widgets/luxe_settings.dart`: nhóm/hàng/công tắc/medallion/confirm.
  - Auth dùng `features/auth/widgets/luxe_auth_widgets.dart`.
  - `LuxeOrb` (quả cầu nhuộm màu) khác `LuxeMedallion` (giếng kim loại).
- **Motion:**
  - Dùng `LuxeMotion.enter/exit`, `LuxeReveal` (520ms, stagger 70ms, tối đa 8 mục), chuyển trang `LuxePageTransitionsBuilder`.
  - Không có animation trang trí lặp vô hạn. Vòng lặp chỉ được gắn với trạng thái thật (đang sạc, đang quét, đang tải), phải tôn trọng `TickerMode` và `disableAnimations`, nếu không `pumpAndSettle` sẽ treo.
  - 2D vẽ bằng `CustomPainter`; không thêm package animation (`flutter_animate`, `shimmer`, `google_fonts` đã gỡ).
- **Bắt buộc:**
  - Vùng chạm ≥48dp; mọi màn mới phải có test 320dp ở chữ ×1/×2.
  - Không hiển thị dữ liệu giả; không in lỗi thô (`$e`) ra UI.
  - Giữ `ValueKey`/`GuideRegistry` và cổng an toàn sạc.
  - Task 125: `LuxeText.eyebrow` là platinum (emerald chỉ cho trạng thái đã xác minh); mascot/avatar/nút bot nổi/chấm trạng thái chỉ chuyển động khi có hoạt động thật; thẻ xác nhận BatteryBot: champagne chờ, rose không thực hiện, emerald đã xác minh.

### 3.7. BatteryBot (trợ lý AI)

- **Hiện hành (Task 124, 15/10/2026):** app `HybridAssistantEngine` → `POST /api/assistant/chat` (Flask, `web/assistant/`, Gemini `GEMINI_CHAT_MODEL` qua REST). **Gemini chặn Azure East Asia (Hồng Kông)** → API gọi qua relay APIM Consumption ở Japan East (`GEMINI_RELAY_URL`, secret `gemini-relay-token`, header `X-Relay-Token`; `deploy/azure/gemini-relay-apim.bicep`); khóa Gemini chỉ nằm trong named value của APIM. Subscription Student: chỉ 1 Container Apps environment, không tạo được App Service plan, vùng cho phép eastasia/japaneast/koreacentral/indonesiacentral/indiasouthcentral.
- Kiến thức: `assistant/knowledge.py` + Firestore `assistantKnowledge` (dashboard `/assistant`). Bộ nhớ: `users/{uid}/assistantMemory` + `assistant/settings.learningEnabled` (mặc định bật; màn "BatteryBot đang nhớ gì"); không lưu transcript. Quota 50 tin/ngày (Azure Table). Gemini 3 bắt buộc gửi lại `thoughtSignature`.
- Hành động: `navigate` chạy ngay; sạc/dừng/nhắc lịch luôn qua `BatteryBotLocalEngine` + gateway đã xác minh (bật theo kiểu xác nhận đã chọn, mặc định vuốt); pin/ODO/xe/mục tiêu/giá điện và `set_app_setting` (chỉ thông báo đẩy) là thẻ một chạm + "hoàn tác". Mất mạng/hết lượt → chế độ cơ bản trên máy.
- Lịch sử chat, hành vi, gợi ý chủ động chỉ trên máy (`localOnly`; 1 bong bóng/30 phút, 5/ngày). Dự đoán sạc trên máy luôn `isDisplayOnly`, không phải quyền ON. Thiếu model phải báo unavailable, không giả lập AI.
- **Đã gỡ (QA 131, 19/10/2026):** chatbot Gemini/SSE cũ trong `web/ai_server` và proxy `/api/chat/*`, `/api/behavior/*` (app không còn gọi). Đặc tả: `docs/specs/BATTERYBOT_ASSISTANT.md`.

### 3.8. Premium, Trợ giúp, sạc đêm, quét đồng hồ (QA 135, 25/10/2026)
- **Gói:** `web/billing/` (Free/Pro/Ultra, không trọn đời; `features.py` là bảng quyền một nguồn ↔ `app/lib/data/models/entitlement.dart`). Máy chủ quyết định: `service.require_feature(uid, ...)` (Shelly), quota Bot/AI ảnh theo gói, số xe, lịch sử 30 ngày Free. `users/{uid}/entitlements/*`, `promoCodes`, `supportTickets`, `nightPlans` chỉ Admin SDK (không có rule). `BILLING_ENFORCED=false` mở hết. Không bao giờ chặn Dừng sạc/an toàn; hết hạn không ngắt phiên đang chạy.
- **Trợ giúp:** `web/support/` (phiếu + email ACS qua `ACS_CONNECTION_STRING`/`SUPPORT_SENDER_EMAIL`/`SUPPORT_ADMIN_EMAIL`), app `features/support/` (tự kiểm tra có nút sửa).
- **Quét:** `SevenSegmentReader.readDashboard` = nhiều ngưỡng + `DashboardLayoutParser.combine`; khung camera chỉ đọc vùng khung ngắm (`GrayImage.crop`); fallback `POST /api/scan/dashboard` (Gemini, không lưu ảnh). Thử nghiệm bằng `test/unit/qa135_scan_synthetic_test.dart` (≥ 95 %).
- **Sạc:** đổi mục tiêu `PATCH .../sessions/<id>/target` (tăng = `extend_timer` relay ON + readback); sạc đêm `shelly/night.py` (worker bật, `strategy=night_target` có ngưỡng 60 °C/công suất/quá giờ, kênh `pinova_urgent`); % pin chai `charge_model.battery_health`.
- **Hướng dẫn:** `core/services/screen_tour.dart` (một lần mỗi tài khoản mỗi lần cài, sau tour Tổng quan; Android `allowBackup=false`). Nút lưu có chờ: `LuxeSubmitButton`.

---

## 4. Lệnh Kiểm Thử & Kiểm Soát Chất Lượng Chuẩn

Trước khi hoàn tất bất kỳ task nào, chạy các lệnh kiểm thử liên quan:

```bash
# 1. Backend Flask & AI Services (web/tests)
cd web
python -m pytest tests -v

# 2. Flutter Mobile App (app/)
cd ../app
flutter test

# 3. Admin Dashboard (web/dashboard)
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
