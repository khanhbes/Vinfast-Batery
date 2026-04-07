# ROADMAP · ĐỒNG BỘ TÍNH NĂNG · CHUẨN UI/UX
## VinFast Battery Management — Tài liệu chiến lược 6 tháng

> **Audience**: Team dev  
> **Cập nhật lần cuối**: 2026-04-05  
> **Phạm vi**: Flutter mobile app · Flask AI API · Flask Web Dashboard  

---

## MỤC LỤC

1. [Hiện trạng hệ thống](#1-hiện-trạng-hệ-thống)
2. [Bản đồ tính năng](#2-bản-đồ-tính-năng)
3. [Ma trận đồng bộ tính năng](#3-ma-trận-đồng-bộ-tính-năng)
4. [Chuẩn UI/UX nhất quán](#4-chuẩn-uiux-nhất-quán)
5. [Roadmap 6 tháng](#5-roadmap-6-tháng)
6. [Public APIs & Interface Contracts](#6-public-apis--interface-contracts)
7. [Phụ lục](#7-phụ-lục)

---

# 1. HIỆN TRẠNG HỆ THỐNG

## 1.1 Kiến trúc tổng thể

```
┌─────────────────────────────────────────────────────────┐
│                   MOBILE APP (Flutter)                  │
│  ┌──────┐ ┌──────┐ ┌────────┐ ┌────────┐ ┌────────┐   │
│  │Dashb.│ │ Home │ │Thống kê│ │Bảo dưỡng│ │Cài đặt│   │
│  └──┬───┘ └──┬───┘ └───┬────┘ └───┬─────┘ └───┬────┘   │
│     └────────┴─────────┴──────────┴────────────┘        │
│         Riverpod Providers (State Management)           │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  Repositories │  │   Services   │  │ Core Widgets  │  │
│  │ (Firestore)   │  │ (GPS/Notif)  │  │ (Theme/Anim)  │  │
│  └───────┬───────┘  └──────┬───────┘  └───────────────┘  │
└──────────┼─────────────────┼────────────────────────────┘
           │                 │
           ▼                 ▼
┌──────────────────┐  ┌──────────────────┐
│ Cloud Firestore  │  │  Flask AI API    │
│  (Firebase)      │  │  (port 5001)     │
│ ─ Vehicles       │  │ /predict-degrad. │
│ ─ ChargeLogs     │  │ /analyze-patterns│
│ ─ TripLogs       │  └──────────────────┘
│ ─ MaintTasks     │
└──────────────────┘
           ▲
           │ (In-memory copy)
┌──────────────────┐
│  Flask Web Demo  │
│  (port 5000)     │
│ HTML/CSS/JS      │
│ Chart.js         │
└──────────────────┘
```

## 1.2 Module đang có

| # | Module | Stack | Trạng thái | Ghi chú |
|---|--------|-------|-----------|---------|
| 1 | **Flutter Mobile App** | Flutter 3.x, Dart SDK ^3.11.0, Riverpod | ✅ MVP hoạt động | 5 tab, tracking trip/charge, notifications |
| 2 | **Flask AI API** | Flask 3.0, NumPy, CORS | ⚠️ Prototype | Statistical model, chưa ML thực thụ |
| 3 | **Flask Web Dashboard** | Flask 3.0, HTML/CSS/JS, Chart.js | ⚠️ Demo | In-memory DB, seed data, không kết nối Firestore |
| 4 | **Firebase Backend** | Cloud Firestore, Firebase Core | ✅ Production-ready | 4 collections, transaction-based writes |
| 5 | **Background Service** | flutter_background_service, Foreground Service | ⚠️ Cơ bản | Heartbeat 10s, command-based, chưa test kỹ edge cases |

## 1.3 Nguồn dữ liệu hiện dùng

| Nguồn | Nơi dùng | Loại | Ghi chú |
|-------|---------|------|---------|
| **Cloud Firestore** | Mobile App (3 repositories) | Persistent, cloud-synced | Nguồn sự thật chính cho mobile |
| **In-memory dict** | Web Dashboard (app.py) | Volatile, seed khi khởi động | Hoàn toàn tách biệt khỏi Firestore |
| **SharedPreferences** | Trip/Charge tracking state | Local key-value | Persist trạng thái tracking qua restart |
| **GPS Stream** | TripTrackingService | Real-time sensor | Geolocator, accuracy high, 10m filter |
| **HTTP API** | Statistics screen → AI API | Request-response | Timeout 15s, graceful fallback |

## 1.4 Dependency chính (Mobile)

| Package | Version | Mục đích |
|---------|---------|---------|
| `firebase_core` | ^3.13.0 | Firebase initialization |
| `cloud_firestore` | ^5.6.9 | Database |
| `flutter_riverpod` | ^2.6.1 | State management |
| `fl_chart` | ^0.70.2 | Charts (line, bar) |
| `google_fonts` | ^6.2.1 | Typography (Inter) |
| `shimmer` | ^3.0.0 | Loading skeleton |
| `flutter_animate` | ^4.5.2 | Declarative animations |
| `intl` | ^0.20.2 | Date/number formatting |
| `uuid` | ^4.5.1 | Unique ID generation |
| `http` | ^1.2.0 | HTTP client (AI API) |
| `flutter_background_service` | ^5.0.5 | Background isolate |
| `geolocator` | ^13.0.2 | GPS tracking |
| `permission_handler` | ^11.3.1 | Runtime permissions |
| `flutter_local_notifications` | ^18.0.1 | Local notifications |
| `shared_preferences` | ^2.3.4 | Key-value local storage |

## 1.5 Mức hoàn thiện từng feature

| Feature | UI | Logic | Data | Test | Tổng |
|---------|:--:|:-----:|:----:|:----:|:----:|
| **Dashboard** (SoH + tracking) | 🟢 80% | 🟡 70% | 🟢 85% | 🔴 0% | **~60%** |
| **Home** (Battery gauge + recent charges) | 🟢 85% | 🟢 80% | 🟢 85% | 🔴 0% | **~63%** |
| **Charge Log** (CRUD + manual add) | 🟢 90% | 🟢 85% | 🟢 90% | 🔴 0% | **~66%** |
| **Statistics** (Charts + AI) | 🟡 75% | 🟡 65% | 🟡 60% | 🔴 0% | **~50%** |
| **Maintenance** (Task CRUD) | 🟢 80% | 🟢 80% | 🟢 85% | 🔴 0% | **~61%** |
| **Settings** (Vehicle management) | 🟡 70% | 🟡 70% | 🟢 80% | 🔴 0% | **~55%** |
| **Trip Tracking** (GPS real-time) | 🟡 70% | 🟡 65% | 🟢 80% | 🔴 0% | **~54%** |
| **Charge Tracking** (Simulated) | 🟡 70% | 🟡 65% | 🟢 80% | 🔴 0% | **~54%** |
| **AI API** (Flask predict) | — | 🟡 60% | 🟡 50% | 🔴 0% | **~28%** |
| **Web Dashboard** (Demo) | 🟡 75% | 🟡 50% | 🔴 20% | 🔴 0% | **~36%** |

> **Legend**: 🟢 ≥ 75% · 🟡 50–74% · 🔴 < 50%

---

# 2. BẢN ĐỒ TÍNH NĂNG

## 2.1 Trục 1 — Mobile App

### 2.1.1 Dashboard Screen

| Tính năng | Input | Output | Nơi lưu | Màn hình |
|-----------|-------|--------|---------|---------|
| Hiển thị SoH tổng | Trip logs gần nhất | SoH % + status badge | Computed từ TripLogs (Firestore) | Dashboard → SoH Card |
| Banner Trip đang chạy | TripTrackingService state | Distance, battery drain, duration | RAM + SharedPreferences | Dashboard → Active Trip Banner |
| Banner Charge đang chạy | ChargeTrackingService state | Current %, time elapsed | RAM + SharedPreferences | Dashboard → Active Charge Banner |
| Quick Actions | User tap | Start/Stop trip hoặc charge | Triggers service → Firestore | Dashboard → Action Buttons |
| Pending Maintenance | MaintenanceRepository | Tasks sắp đến hạn | Firestore: MaintenanceTasks | Dashboard → Maintenance Section |

### 2.1.2 Home Screen

| Tính năng | Input | Output | Nơi lưu | Màn hình |
|-----------|-------|--------|---------|---------|
| Battery Gauge | Vehicle.currentBattery | Animated circular gauge | Firestore: Vehicles | Home → Center Gauge |
| Vehicle Switcher | allVehiclesProvider | Selected vehicle chip | StateProvider (RAM) | Home → Header |
| Quick Stats | chargeLogsProvider + vehicleStatsProvider | 4 stat cards (total charges, avg gain, energy, duration) | Computed từ ChargeLogs | Home → Stats Row |
| Recent Charges | chargeLogsProvider (latest 5) | List cards | Firestore: ChargeLogs | Home → Recent Section |
| Pull-to-refresh | User gesture | Invalidate tất cả providers | — | Home (toàn màn hình) |

### 2.1.3 Charge Log Screen

| Tính năng | Input | Output | Nơi lưu | Màn hình |
|-----------|-------|--------|---------|---------|
| Danh sách charge logs | vehicleId | Grouped by date, sorted desc | Firestore: ChargeLogs | ChargeLog → List |
| Thêm charge log (manual) | Form: start%, end%, ODO, time range | New ChargeLogModel | Firestore: ChargeLogs + Vehicles (transaction) | AddChargeLogModal |
| Xóa charge log | logId | Remove from Firestore | Firestore: ChargeLogs | Swipe/button delete |
| Summary bar | All logs | Total laps, energy gained, avg gain | Computed | ChargeLog → Top Summary |

### 2.1.4 Statistics Screen

| Tính năng | Input | Output | Nơi lưu | Màn hình |
|-----------|-------|--------|---------|---------|
| Summary Cards | chargeLogsProvider | 4 metric cards | Computed | Statistics → Grid |
| Charge Trend Chart | ChargeLogs sorted by time | fl_chart LineChart | Computed | Statistics → Line Chart |
| Battery Health Card | Vehicle SoH | Status + % display | Computed từ trips | Statistics → Health Card |
| AI Prediction | ChargeLogs → HTTP POST | healthScore, recommendations, cycles | Flask API response (transient) | Statistics → AI Widget |
| Consumption Analysis | TripLogs | Efficiency chart | Computed | Statistics → Bar Chart |
| Charging Pattern | ChargeLogs | Preferred hours, frequency | Computed | Statistics → Pattern Card |

### 2.1.5 Maintenance Screen

| Tính năng | Input | Output | Nơi lưu | Màn hình |
|-----------|-------|--------|---------|---------|
| Danh sách tasks | vehicleId | Tasks sorted by targetOdo | Firestore: MaintenanceTasks | Maintenance → List |
| Thêm task | Form: title, description, targetOdo | New MaintenanceTaskModel | Firestore: MaintenanceTasks | Add Dialog |
| Hoàn thành task | taskId | isCompleted=true, completedDate | Firestore: MaintenanceTasks | Task Card → Complete Button |
| Xóa task | taskId | Remove document | Firestore: MaintenanceTasks | Task Card → Delete |
| Trạng thái cảnh báo | currentOdo vs targetOdo | Due soon (< 50km) / Overdue badges | Computed từ Vehicle.currentOdo | Task Card → Badge |

### 2.1.6 Settings Screen

| Tính năng | Input | Output | Nơi lưu | Màn hình |
|-----------|-------|--------|---------|---------|
| Garage (danh sách xe) | allVehiclesProvider | Vehicle chips, selectable | Firestore: Vehicles | Settings → Garage Section |
| Thêm xe | Form: name, initial ODO, battery | New VehicleModel | Firestore: Vehicles | Add Vehicle Dialog |
| Xóa xe | vehicleId | Cascade delete + ChargeLogs | Firestore: Vehicles + ChargeLogs | Confirmation Dialog |
| Info ứng dụng | Hardcoded | Version, about text | — | Settings → App Info |

## 2.2 Trục 2 — AI API (Flask, port 5001)

| Tính năng | Endpoint | Input | Output | Ghi chú |
|-----------|----------|-------|--------|---------|
| Dự đoán suy giảm pin | `POST /api/predict-degradation` | vehicleId + chargeLogs[] | healthScore, equivalentCycles, remainingCycles, estimatedLifeMonths, recommendations | Statistical model, không có ML training |
| Phân tích pattern sạc | `POST /api/analyze-patterns` | vehicleId + chargeLogs[] | avgChargeStart/End%, preferredHour, chargesPerWeek, fast/slow% | Thuần thống kê |
| Health check | `GET /api/health` | — | 200 OK | Kiểm tra API sống |

**Model tính toán hiện tại** (`BatteryDegradationModel`):
- `MAX_CYCLES = 800`, `NOMINAL_CAPACITY_KWH = 1.5`, `CRITICAL_HEALTH = 60`
- `health_score = 100 - (cycle_aging + stress_aging)`
  - `cycle_aging = (equivalent_cycles / 800) × 100`
  - `stress_aging = f(dod_stress, rate_stress, calendar_stress)`
- `confidence = min(1.0, log_count / 50) × 100`

## 2.3 Trục 3 — Web Dashboard (Flask, port 5000)

| Tính năng | Endpoint | Input | Output | Ghi chú |
|-----------|----------|-------|--------|---------|
| Trang chính | `GET /` | — | Render index.html | SPA-like với JS tabs |
| Danh sách xe | `GET /api/vehicles` | — | vehicles[] | In-memory, seed data |
| Chi tiết xe | `GET /api/vehicles/<id>` | vehicleId | VehicleModel | 404 nếu không tìm thấy |
| Charge logs | `GET /api/charge-logs?vehicleId=` | vehicleId (query) | chargeLogs[] sorted desc | In-memory array |
| Thêm charge log | `POST /api/charge-logs` | JSON body | Created log + updated vehicle | Validation tương tự mobile |
| Xóa charge log | `DELETE /api/charge-logs/<id>` | logId | 200 OK | Xóa khỏi array |
| Thống kê | `GET /api/stats/<id>` | vehicleId | totalCharges, avgGain, totalEnergy, avgDuration | Tính từ in-memory logs |

**UI Web**: Sidebar 3 tab (Dashboard, Analytics, History), Chart.js line/bar, glassmorphism CSS, responsive.

---

# 3. MA TRẬN ĐỒNG BỘ TÍNH NĂNG

## 3.1 Tổng quan luồng dữ liệu

```
                  ┌──────────────┐
                  │   Firestore   │
                  │ (Source of    │
                  │  Truth)       │
                  └──────┬───────┘
                         │
            ┌────────────┼────────────┐
            ▼            ▼            ▼
     ┌──────────┐ ┌───────────┐ ┌─────────┐
     │ Mobile   │ │ AI API    │ │ Web     │
     │ App      │ │ (nhận qua │ │ Demo    │
     │(Riverpod)│ │  HTTP)    │ │(in-mem) │
     └──────────┘ └───────────┘ └─────────┘
```

## 3.2 Ma trận đồng bộ theo luồng

### Luồng 1: Trip Tracking

| Bước | Hành động | Dữ liệu ghi | Dữ liệu đọc | Nơi xử lý | Đồng bộ? |
|------|-----------|-------------|-------------|-----------|----------|
| 1 | Bắt đầu trip | SharedPrefs: `trip_active=true` | Vehicle (ODO, battery) | TripTrackingService | — |
| 2 | Cập nhật GPS | RAM (distance, battery drain) | GPS stream | Geolocator + BatteryLogic | — |
| 3 | Notification ongoing | — | RAM state | NotificationService | — |
| 4 | Kết thúc trip | Firestore: TripLogs (new doc), Vehicles (ODO, battery, totalTrips) | RAM accumulated state | TripLogRepository (transaction) | ✅ Mobile |
| 5 | UI cập nhật | — | Invalidate providers | Riverpod | ✅ Mobile |

| Điểm lệch | Mô tả | Rủi ro | Mức độ |
|-----------|-------|--------|--------|
| **DL-TRIP-01** | Web Dashboard không nhận TripLogs | Web không hiển thị trips | 🟡 Trung bình |
| **DL-TRIP-02** | AI API không nhận trip data | Không tính consumption-based SoH | 🟠 Cao |
| **DL-TRIP-03** | Battery drain là simulated (dựa defaultEfficiency) | Sai lệch với thực tế nếu efficiency thay đổi | 🟡 Trung bình |
| **DL-TRIP-04** | GPS noise filter cố định (5m–1km) | Có thể bỏ sót hoặc nhận noise ở tốc độ thấp | 🟡 Trung bình |

### Luồng 2: Charge Tracking (Real-time simulated)

| Bước | Hành động | Dữ liệu ghi | Dữ liệu đọc | Nơi xử lý | Đồng bộ? |
|------|-----------|-------------|-------------|-----------|----------|
| 1 | Bắt đầu sạc | SharedPrefs: `charge_active`, vehicleId, startBattery, startTime | Vehicle (battery, ODO) | ChargeTrackingService | — |
| 2 | Tick mỗi 30s | RAM (currentBattery += rate × elapsed) | chargeRatePerMin (0.38) | Timer callback | — |
| 3 | Thông báo 80% & 100% | — | currentBattery thresholds | NotificationService | — |
| 4 | Kết thúc sạc | Firestore: ChargeLogs (new), Vehicles (ODO, totalCharges, lastBattery) | RAM final state | ChargeLogRepository (transaction) | ✅ Mobile |

| Điểm lệch | Mô tả | Rủi ro | Mức độ |
|-----------|-------|--------|--------|
| **DL-CHG-01** | Charge rate cố định 0.38%/min, không phản ánh thực tế | Thời gian ước tính có thể sai lớn | 🟠 Cao |
| **DL-CHG-02** | Web Dashboard tạo charge log riêng (in-memory), không sync | Data mismatch giữa mobile và web | 🔴 Nghiêm trọng |
| **DL-CHG-03** | Nếu app crash giữa chừng, SharedPrefs giữ `charge_active=true` nhưng Firestore chưa ghi | Orphaned state, không recovery | 🟠 Cao |

### Luồng 3: Add Manual Charge Log

| Bước | Hành động | Dữ liệu ghi | Dữ liệu đọc | Nơi xử lý | Đồng bộ? |
|------|-----------|-------------|-------------|-----------|----------|
| 1 | Mở form | — | Vehicle (currentOdo, currentBattery) | AddChargeLogNotifier | — |
| 2 | Validate form | — | User input vs Vehicle constraints | Client-side validation | — |
| 3 | Lưu | Firestore: ChargeLogs (new), Vehicles (ODO, totalCharges, lastBattery) | Validated form data | ChargeLogRepository (transaction) | ✅ Mobile |
| 4 | UI update | — | Invalidate chargeLogsProvider, vehicleProvider | Riverpod | ✅ Mobile |

| Điểm lệch | Mô tả | Rủi ro | Mức độ |
|-----------|-------|--------|--------|
| **DL-MAN-01** | Web có POST /api/charge-logs nhưng ghi in-memory, không vào Firestore | Duplicate logic, data silos | 🔴 Nghiêm trọng |
| **DL-MAN-02** | Manual log không validate against ongoing charge session | Có thể tạo log chồng thời gian | 🟡 Trung bình |
| **DL-MAN-03** | Không lock ODO khi save (race condition nếu 2 device ghi cùng lúc) | Firestore transaction giảm thiểu nhưng không triệt để | 🟡 Trung bình |

### Luồng 4: Statistics / AI Prediction

| Bước | Hành động | Dữ liệu ghi | Dữ liệu đọc | Nơi xử lý | Đồng bộ? |
|------|-----------|-------------|-------------|-----------|----------|
| 1 | Mở Statistics | — | chargeLogsProvider | Riverpod | ✅ Mobile |
| 2 | Render charts | — | ChargeLogs mapped to chart data | fl_chart | — |
| 3 | Gọi AI prediction | HTTP POST (chargeLogs JSON) | /api/predict-degradation response | AiPredictionService → Flask | ⚠️ Một chiều |
| 4 | Hiển thị kết quả AI | — | healthScore, recommendations | Statistics Screen | — |

| Điểm lệch | Mô tả | Rủi ro | Mức độ |
|-----------|-------|--------|--------|
| **DL-STAT-01** | AI API nhận chargeLogs qua HTTP body, không đọc Firestore trực tiếp | Phụ thuộc mobile gửi đúng/đủ data | 🟠 Cao |
| **DL-STAT-02** | AI model là statistical, không có training set | Accuracy thấp, không cải thiện theo thời gian | 🟠 Cao |
| **DL-STAT-03** | AI không nhận TripLogs → thiếu consumption metrics | SoH chỉ dựa charge patterns, thiếu usage patterns | 🟠 Cao |
| **DL-STAT-04** | Web stats endpoint tính từ in-memory, khác mobile stats | Số liệu hiển thị khác nhau giữa 2 nền tảng | 🔴 Nghiêm trọng |

### Luồng 5: Maintenance

| Bước | Hành động | Dữ liệu ghi | Dữ liệu đọc | Nơi xử lý | Đồng bộ? |
|------|-----------|-------------|-------------|-----------|----------|
| 1 | Tạo task | Firestore: MaintenanceTasks | User input | MaintenanceRepository | ✅ Mobile |
| 2 | Kiểm tra overdue | — | Vehicle.currentOdo vs task.targetOdo | Computed (isDueSoon, isOverdue) | ✅ Mobile |
| 3 | Complete task | Firestore: MaintenanceTasks (isCompleted, completedDate) | taskId | MaintenanceRepository | ✅ Mobile |
| 4 | Notification nhắc | — | getPendingTasks + Vehicle.currentOdo | NotificationService | ✅ Mobile |

| Điểm lệch | Mô tả | Rủi ro | Mức độ |
|-----------|-------|--------|--------|
| **DL-MAINT-01** | Web Dashboard không có Maintenance | Chỉ quản lý trên mobile | 🟡 Trung bình |
| **DL-MAINT-02** | Maintenance notification chỉ khi mở app, không có scheduled check | Có thể bỏ lỡ nếu user không mở app | 🟡 Trung bình |

### Luồng 6: Vehicle Settings / Management

| Bước | Hành động | Dữ liệu ghi | Dữ liệu đọc | Nơi xử lý | Đồng bộ? |
|------|-----------|-------------|-------------|-----------|----------|
| 1 | Thêm xe | Firestore: Vehicles (new doc) | User input | ChargeLogRepository | ✅ Mobile |
| 2 | Chọn xe active | StateProvider (RAM) | allVehiclesProvider | Riverpod | ✅ Mobile |
| 3 | Xóa xe | Firestore: Vehicles + ChargeLogs (cascade) | vehicleId | ChargeLogRepository | ✅ Mobile |
| 4 | Auto-seed | Firestore: Vehicles (2 default) | getAllVehicles().isEmpty | ChargeLogRepository | ✅ Mobile |

| Điểm lệch | Mô tả | Rủi ro | Mức độ |
|-----------|-------|--------|--------|
| **DL-VEH-01** | Web dùng in-memory vehicles, không đọc Firestore | Khác danh sách xe giữa mobile và web | 🔴 Nghiêm trọng |
| **DL-VEH-02** | Cascade delete trên mobile xóa ChargeLogs nhưng không xóa TripLogs, MaintenanceTasks | Orphaned data trong Firestore | 🟠 Cao |
| **DL-VEH-03** | selectedVehicleId là StateProvider (RAM), mất khi restart | Luôn reset về xe đầu tiên | 🟡 Trung bình |

## 3.3 Tổng hợp điểm lệch nghiêm trọng

| Mã | Tóm tắt | Ảnh hưởng | Phase xử lý |
|----|---------|----------|-------------|
| 🔴 DL-CHG-02 | Web tạo charge log in-memory, không vào Firestore | Data silos | Phase 4 |
| 🔴 DL-MAN-01 | Web POST charge log ghi in-memory | Duplicate logic | Phase 4 |
| 🔴 DL-STAT-04 | Web stats tính từ in-memory, khác mobile | UX mismatch | Phase 4 |
| 🔴 DL-VEH-01 | Web vehicles in-memory, không sync Firestore | Data silos | Phase 4 |
| 🟠 DL-TRIP-02 | AI không nhận trip data | SoH thiếu chính xác | Phase 2 |
| 🟠 DL-CHG-01 | Charge rate cố định 0.38%/min | Ước tính sai | Phase 1 |
| 🟠 DL-CHG-03 | Crash recovery cho charge session | Orphaned state | Phase 1 |
| 🟠 DL-STAT-01 | AI nhận data qua HTTP, không đọc Firestore trực tiếp | Phụ thuộc client | Phase 2 |
| 🟠 DL-STAT-02 | AI model statistical, không ML | Accuracy thấp | Phase 4 |
| 🟠 DL-STAT-03 | AI không nhận TripLogs | SoH thiếu usage data | Phase 2 |
| 🟠 DL-VEH-02 | Cascade delete không xóa TripLogs, MaintenanceTasks | Orphaned data | Phase 1 |

---

# 4. CHUẨN UI/UX NHẤT QUÁN

## 4.1 Design Tokens

### Colors

| Token | Hex | Mục đích |
|-------|-----|---------|
| `primaryGreen` | `#00C853` | Brand chính, CTA, accent |
| `accentGreen` | `#00E676` | Hover, active states |
| `lightGreen` | `#69F0AE` | Subtle highlights |
| `background` | `#0A0E14` | Nền chính app |
| `surface` | `#111720` | Nền card layer 1 |
| `surfaceLight` | `#1A2332` | Nền card layer 2 |
| `card` | `#151C28` | Card background |
| `cardElevated` | `#1C2536` | Card elevated |
| `border` | `#1E2A3A` | Border mặc định |
| `borderLight` | `#2A3A4E` | Border nhạt |
| `textPrimary` | `#FFFFFF` | Text chính |
| `textSecondary` | `#8899AA` | Text phụ |
| `textTertiary` | `#556677` | Text mờ nhất |
| `error` | `#FF5252` | Lỗi, validation |
| `warning` | `#FFB74D` | Cảnh báo |
| `info` | `#42A5F5` | Thông tin |
| `success` | `#66BB6A` | Thành công |

### Battery State Colors

| Trạng thái | Ngưỡng | Màu |
|-----------|--------|-----|
| Full | ≥ 70% | `#00C853` (primaryGreen) |
| Medium | 40–69% | `#FFB74D` (warning/orange) |
| Low | 20–39% | `#FF5252` (error/red) |
| Critical | < 20% | `#B71C1C` (dark red) |

### Typography

| Style | Font | Size | Weight | Line Height |
|-------|------|------|--------|-------------|
| `displayLarge` | Inter | 32 | Bold (700) | 1.2 |
| `displayMedium` | Inter | 28 | Bold (700) | 1.2 |
| `headlineLarge` | Inter | 24 | SemiBold (600) | 1.3 |
| `headlineMedium` | Inter | 20 | SemiBold (600) | 1.3 |
| `titleLarge` | Inter | 18 | SemiBold (600) | 1.4 |
| `titleMedium` | Inter | 16 | Medium (500) | 1.4 |
| `bodyLarge` | Inter | 16 | Regular (400) | 1.5 |
| `bodyMedium` | Inter | 14 | Regular (400) | 1.5 |
| `bodySmall` | Inter | 12 | Regular (400) | 1.5 |
| `labelLarge` | Inter | 14 | SemiBold (600) | 1.4 |

### Spacing & Sizing

| Token | Value | Sử dụng |
|-------|-------|---------|
| `spacing-xs` | 4px | Padding nhỏ, gap icon-text |
| `spacing-sm` | 8px | Padding trong card, gap items |
| `spacing-md` | 16px | Padding section, margin items |
| `spacing-lg` | 24px | Padding screen, gap sections |
| `spacing-xl` | 32px | Gap lớn giữa sections |
| `radius-sm` | 8px | Small chips, badges |
| `radius-md` | 12px | Cards, buttons |
| `radius-lg` | 16px | Modal, bottom sheet |
| `radius-xl` | 20px | Large containers |
| `radius-full` | 999px | Circular elements |

### Shadows & Effects

| Effect | Giá trị | Sử dụng |
|--------|---------|---------|
| Card shadow | None (dark theme, dùng border thay thế) | Cards |
| Glassmorphism | BackdropFilter blur(10, 10) + gradient border | GradientCard |
| Shimmer | shimmer package, base `#1A2332`, highlight `#2A3A4E` | Loading states |

## 4.2 Component Patterns

### Card Pattern

```
┌─────────────────────────┐   Background: AppColors.card (#151C28)
│ ┌ Icon ┐  Title          │   Border: 1px AppColors.border (#1E2A3A)
│ │      │  Subtitle        │   Radius: 12px
│ └──────┘                  │   Padding: 16px
│                           │   
│  Value / Content          │   
│  Secondary info           │   
└─────────────────────────┘
```

**Variants đang dùng**:
- `StatCard`: Icon circle + value + title + optional subtitle
- `GradientCard`: Glassmorphism border, onTap callback
- Inline card: Dùng Container trực tiếp với decoration

**Quy tắc**: Mọi card PHẢI dùng `AppColors.card` background, `AppColors.border` border, radius 12px.

### Button Pattern

| Loại | Style | Sử dụng |
|------|-------|---------|
| Primary | Filled gradient (primaryGreen → accentGreen) | CTA chính: Start trip, Save |
| Secondary | Outlined, border primaryGreen | Cancel, View all |
| Danger | Filled error color | Delete |
| Icon | CircleAvatar + Icon | Quick actions |
| FAB | FloatingActionButton, primaryGreen | Add charge log |

### Navigation Pattern

```
┌──────────────────────────────────────┐
│         Screen Content                │
│         (IndexedStack)                │
│                                       │
├──────────────────────────────────────┤
│  [Dashboard] [Home] [Stats] [Maint] [Settings]  │
│  NavItem: icon + label, animated     │
│  Active: primaryGreen, scale 1.1     │
│  Inactive: textTertiary              │
└──────────────────────────────────────┘
```

### Modal / Bottom Sheet Pattern

- Drag handle: Center, 40×4px, rounded, AppColors.borderLight
- Background: AppColors.surface
- Border top radius: 20px
- Content padding: 24px horizontal, 16px vertical
- Action buttons: Full width, bottom aligned

## 4.3 Trạng thái Loading / Error / Empty

### Quy tắc chung cho mọi màn hình

| Trạng thái | Hiện tại | Chuẩn nên theo |
|-----------|---------|---------------|
| **Loading** | CircularProgressIndicator (mặc định Flutter) hoặc Shimmer (Home) | **Shimmer skeleton** cho mọi screen — mimic layout thật |
| **Error** | Text đỏ đơn giản hoặc SnackBar | **Error card**: Icon ⚠️ + message + "Thử lại" button |
| **Empty** | Text "Chưa có dữ liệu" | **Empty state**: Illustration/icon + message + CTA button |
| **Success** | SnackBar xanh | **SnackBar** positional bottom, icon ✓, auto-dismiss 3s |

### Checklist trạng thái từng màn hình

| Màn hình | Loading | Error | Empty | Cần bổ sung |
|---------|---------|-------|-------|-------------|
| Dashboard | ⚠️ Chưa nhất quán | ⚠️ Thiếu | ✅ Có message | Shimmer skeleton, Error card |
| Home | ✅ Shimmer | ⚠️ Thiếu | ✅ Có message | Error card |
| Charge Log | ⚠️ CircularProgress | ⚠️ Thiếu | ✅ Có message | Shimmer, Error card |
| Statistics | ⚠️ CircularProgress | ⚠️ Thiếu cho AI fail | ⚠️ Thiếu | Shimmer, Error card, Empty state |
| Maintenance | ⚠️ CircularProgress | ⚠️ Thiếu | ✅ Có message | Shimmer, Error card |
| Settings | ⚠️ CircularProgress | ⚠️ Thiếu | — (luôn có data) | Shimmer |

## 4.4 Copywriting Rules

| Quy tắc | Ví dụ đúng | Ví dụ sai |
|---------|-----------|----------|
| Viết tiếng Việt cho user-facing text | "Bắt đầu chuyến đi" | "Start trip" |
| Dùng "bạn" khi xưng hô | "Pin của bạn đã sạc 80%" | "Pin đã charge 80%" |
| Ngắn gọn, không dư thừa | "Thêm lần sạc" | "Nhấn vào đây để thêm một lần sạc mới cho xe" |
| Số liệu kèm đơn vị | "1.250 km" | "1250" |
| Phần trăm không khoảng trắng | "85%" | "85 %" |
| Thời gian dạng tương đối khi < 24h | "2 giờ trước" | "2024-01-15 08:00" |
| Thời gian dạng dd/MM/yyyy khi > 24h | "15/01/2024" | "January 15, 2024" |

## 4.5 Motion / Animation Rules

| Loại | Duration | Curve | Sử dụng |
|------|----------|-------|---------|
| Page transition | 300ms | `easeInOut` | Tab switch (IndexedStack — instant, không animate) |
| Card entrance | 400ms | `easeOutBack` | flutter_animate fadeIn + slideY |
| Battery gauge | 1500ms | `easeInOutCubic` | AnimatedBatteryGauge arc fill |
| Value counter | 800ms | `easeOut` | Stat card number animation |
| Bottom sheet | 300ms | `easeOut` | Modal show/dismiss |
| SnackBar | 200ms in, 200ms out | `easeIn/easeOut` | Notification feedback |
| Shimmer | Loop | Linear | Loading skeleton |

**Quy tắc**:
- Không animate elements > 500ms (trừ battery gauge — focal element)
- Stagger delay cho list items: 50ms × index
- Respect `MediaQuery.disableAnimations` cho accessibility

## 4.6 Accessibility Baseline

| Tiêu chí | Yêu cầu | Hiện trạng |
|---------|---------|-----------|
| Contrast ratio | ≥ 4.5:1 text, ≥ 3:1 large text | ⚠️ Chưa audit |
| Touch target | ≥ 48×48dp | ✅ Buttons, ⚠️ Nav items chưa kiểm tra |
| Screen reader | Semantics labels cho widgets chính | ❌ Chưa implement |
| Font scaling | Respect system font size | ⚠️ Chưa test |
| Color-blind | Không chỉ dùng màu để truyền thông tin | ⚠️ Battery state chỉ dùng màu |

## 4.7 Checklist nhất quán giữa các tab

| Tiêu chí | Dashboard | Home | Statistics | Maintenance | Settings |
|---------|:---------:|:----:|:----------:|:----------:|:--------:|
| Dùng AppColors tokens | ✅ | ✅ | ✅ | ✅ | ✅ |
| Dùng AppTheme typography | ✅ | ✅ | ✅ | ✅ | ✅ |
| Pull-to-refresh | ✅ | ✅ | ❌ | ❌ | ❌ |
| Shimmer loading | ❌ | ✅ | ❌ | ❌ | ❌ |
| Error state UI | ❌ | ❌ | ❌ | ❌ | ❌ |
| Empty state UI | ⚠️ | ✅ | ❌ | ✅ | — |
| Card style nhất quán | ⚠️ | ✅ | ⚠️ | ✅ | ⚠️ |
| Consistent header style | ✅ | ✅ | ✅ | ✅ | ✅ |
| Animation entrance | ✅ | ✅ | ⚠️ | ⚠️ | ❌ |
| Tiếng Việt copywriting | ✅ | ✅ | ⚠️ | ✅ | ⚠️ |

> **Legend**: ✅ Đạt · ⚠️ Một phần · ❌ Chưa có · — Không áp dụng

---

# 5. ROADMAP 6 THÁNG

## Tổng quan timeline

```
Tháng 1          Tháng 2          Tháng 3          Tháng 4          Tháng 5          Tháng 6
├─ Phase 0 (2w) ─┤                                                                    
│  Baseline &     ├── Phase 1 (4w) ──┤                                                 
│  Contract       │ Chuẩn hóa data   ├──── Phase 2 (6w) ────┤                          
│                 │   flow            │ Đồng bộ liên tính    ├──── Phase 3 (6w) ────┤   
│                 │                   │   năng                │  Thống nhất UI       │   
│                 │                   │                       │    system             │   
│                 │                   │                       ├──── Phase 4 (6w) ────┤
│                 │                   │                       │  Hợp nhất backend +  │
│                 │                   │                       │    production AI/Web  │
```

> *Phase 3 và Phase 4 chạy song song (2 track riêng biệt).*

---

## Phase 0 — Baseline & Contract (2 tuần)

### Mục tiêu
Thiết lập baseline đo được, chốt interface contracts, chuẩn bị infrastructure cho các phase sau.

### Hạng mục chính

| # | Task | Owner gợi ý | Deliverable |
|---|------|-------------|-------------|
| 0.1 | Viết unit tests cho `BatteryLogicService` (pure logic) | Dev Mobile | ≥ 90% coverage cho file `battery_logic_service.dart` |
| 0.2 | Viết integration tests cho 3 Repositories (mock Firestore) | Dev Mobile | Test CRUD + transaction cho mỗi repo |
| 0.3 | Chốt Firestore schema contract (xem [Section 6.1](#61-firestore-contract)) | Lead | Document chính thức, review bởi team |
| 0.4 | Chốt HTTP API contract cho AI API (xem [Section 6.3](#63-http-api-contract--ai)) | Dev AI | OpenAPI spec hoặc markdown contract |
| 0.5 | Setup CI pipeline (lint + test) | DevOps/Lead | GitHub Actions hoặc tương đương |
| 0.6 | Audit accessibility baseline | Dev Mobile | Report WCAG issues với priority |

### Phụ thuộc
- Không phụ thuộc phase nào khác.
- Cần team đồng ý contracts trước khi vào Phase 1.

### Rủi ro

| Rủi ro | Xác suất | Tác động | Giảm thiểu |
|--------|---------|---------|-----------|
| Team chưa quen testing Flutter | Cao | Chậm delivery | Pair programming, chia task nhỏ |
| Thay đổi contract sau khi đã chốt | Trung bình | Ảnh hưởng Phase 1-4 | Version contracts, migration plan |

### KPI

| Metric | Target |
|--------|--------|
| Test coverage `BatteryLogicService` | ≥ 90% |
| Test count Repositories | ≥ 15 test cases (5/repo) |
| Contract documents approved | 3/3 (Firestore, Service, HTTP) |
| CI pipeline green | YES |

### Definition of Done
- [ ] Tất cả unit tests pass trên CI.
- [ ] 3 contract documents được merge vào repo.
- [ ] CI chạy lint + test trên mỗi PR.
- [ ] Accessibility audit report có ≥ 10 findings được phân loại priority.

---

## Phase 1 — Chuẩn hóa Data Flow (4 tuần)

### Mục tiêu
Fix các điểm lệch dữ liệu nghiêm trọng trong mobile app, đảm bảo mỗi write operation tuân thủ contract đã chốt.

### Hạng mục chính

| # | Task | Xử lý điểm lệch | Deliverable |
|---|------|------------------|-------------|
| 1.1 | Fix cascade delete: xóa vehicle phải xóa cả TripLogs + MaintenanceTasks | DL-VEH-02 | Cập nhật `ChargeLogRepository.deleteVehicle()` |
| 1.2 | Thêm crash recovery cho ChargeTracking: khi app restart, check SharedPrefs `charge_active` → prompt user resume/discard | DL-CHG-03 | Recovery flow trong `main.dart` hoặc Dashboard |
| 1.3 | Thêm crash recovery cho TripTracking (tương tự 1.2) | Mới | Recovery flow |
| 1.4 | Validate overlap: khi tạo manual charge log, check không trùng time range với charge đang chạy | DL-MAN-02 | Validation trong `AddChargeLogNotifier` |
| 1.5 | Adaptive charge rate: tính `chargeRatePerMin` từ lịch sử charge logs thay vì hardcode 0.38 | DL-CHG-01 | `BatteryLogicService.avgChargeRate()` đã có, cần wire vào `ChargeTrackingService.startCharging()` |
| 1.6 | Persist `selectedVehicleId` vào SharedPreferences | DL-VEH-03 | Cập nhật provider và main.dart |
| 1.7 | Thêm `updatedAt` timestamp cho mọi Firestore document | Contract compliance | Migration script + model updates |
| 1.8 | Viết test cho tất cả fix trong Phase 1 | — | ≥ 10 test cases |

### Phụ thuộc
- Phase 0 hoàn thành (contracts chốt, CI sẵn sàng).

### Rủi ro

| Rủi ro | Xác suất | Tác động | Giảm thiểu |
|--------|---------|---------|-----------|
| Crash recovery phức tạp hơn dự kiến | Trung bình | +1 tuần | Prototype spike 2 ngày trước commit |
| Migration `updatedAt` ảnh hưởng data cũ | Thấp | Data inconsistency | Nullable field, backfill script |

### KPI

| Metric | Target |
|--------|--------|
| Điểm lệch 🟠 đã fix | ≥ 4/5 (DL-CHG-01, DL-CHG-03, DL-VEH-02, DL-VEH-03) |
| Crash recovery test scenarios | Pass 100% |
| Regression tests | 0 failures |
| Code coverage tăng | ≥ 30% overall |

### Definition of Done
- [ ] Cascade delete xóa sạch 3 collections liên quan.
- [ ] Charge & Trip recovery flow hoạt động sau force-kill app.
- [ ] Manual charge log validate overlap với active session.
- [ ] Charge rate lấy từ lịch sử (fallback 0.38 nếu chưa có log).
- [ ] selectedVehicleId persist qua restart.
- [ ] Mọi Firestore doc mới có `updatedAt`.
- [ ] 100% tests pass trên CI.

---

## Phase 2 — Đồng bộ liên tính năng (6 tuần)

### Mục tiêu
Kết nối AI API với đầy đủ dữ liệu (charge + trip), thống nhất SoH calculation, đồng bộ metrics xuyên screens.

### Hạng mục chính

| # | Task | Xử lý điểm lệch | Deliverable |
|---|------|------------------|-------------|
| 2.1 | Mở rộng AI API nhận TripLogs trong request body | DL-TRIP-02, DL-STAT-03 | Endpoint mới hoặc mở rộng `/api/predict-degradation` |
| 2.2 | AI API tự đọc Firestore (Firebase Admin SDK) thay vì nhận data qua HTTP body | DL-STAT-01 | `firebase-admin` Python package + service account |
| 2.3 | Thống nhất SoH calculation: Mobile app và AI API dùng cùng formula | Nhất quán | Document formula + implement đồng nhất 2 nơi |
| 2.4 | Dashboard hiển thị SoH từ AI API (khi available) fallback local calculation | — | Conditional UI trong Dashboard |
| 2.5 | Statistics screen hiển thị trip-based metrics (total km, avg efficiency) | — | Thêm TripLogs provider + cards mới |
| 2.6 | Cross-screen metric consistency: Home, Dashboard, Statistics hiển thị cùng số liệu cho cùng vehicle | — | Shared computed providers |
| 2.7 | Thêm endpoint AI: `POST /api/estimate-range` (ước tính km còn lại) | Mới | Input: currentBattery, payload, recentTrips → Output: estimatedRange |
| 2.8 | Maintenance auto-suggest: AI đề xuất task dựa trên ODO + usage pattern | Mới | Endpoint + UI integration |

### Phụ thuộc
- Phase 1 hoàn thành (data flow chuẩn, crash recovery done).
- Firebase Admin SDK service account.

### Rủi ro

| Rủi ro | Xác suất | Tác động | Giảm thiểu |
|--------|---------|---------|-----------|
| Firebase Admin SDK setup phức tạp | Trung bình | +1 tuần | Document step-by-step, test account |
| SoH formula disagreement giữa mobile/AI | Thấp | Confusion | Chốt 1 formula duy nhất trong Phase 0 contract |
| AI API latency cao khi đọc Firestore | Trung bình | UX chậm | Cache layer + timeout 10s |

### KPI

| Metric | Target |
|--------|--------|
| AI prediction accuracy (manual test 10 vehicles) | ≥ 70% reasonable |
| SoH mismatch giữa mobile/AI | 0 (cùng formula) |
| Cross-screen metric consistency | 100% (cùng giá trị cho cùng vehicle) |
| New AI endpoints working | ≥ 2 (estimate-range, maintenance-suggest) |
| Điểm lệch 🟠 đã fix | ≥ 3 (DL-TRIP-02, DL-STAT-01, DL-STAT-03) |

### Definition of Done
- [ ] AI API đọc Firestore trực tiếp (Firebase Admin SDK).
- [ ] AI nhận cả ChargeLogs + TripLogs cho prediction.
- [ ] SoH formula đồng nhất mobile/AI, documented.
- [ ] Dashboard hiển thị AI SoH khi API available, fallback local.
- [ ] Statistics hiển thị trip-based metrics + charge-based metrics.
- [ ] `/api/estimate-range` hoạt động, trả về estimatedRange km.
- [ ] 3 screens (Dashboard, Home, Statistics) hiển thị consistent metrics.
- [ ] Mọi tests pass.

---

## Phase 3 — Thống nhất UI System (6 tuần) ⟨Song song với Phase 4⟩

### Mục tiêu
Áp dụng design system nhất quán cho toàn bộ 5 tab, chuẩn hóa trạng thái, animations, accessibility.

### Hạng mục chính

| # | Task | Deliverable |
|---|------|-------------|
| 3.1 | Tạo `core/widgets/loading_skeleton.dart` — Shimmer skeleton builder nhận layout config | Reusable widget |
| 3.2 | Tạo `core/widgets/error_state.dart` — Error card với icon, message, retry button | Reusable widget |
| 3.3 | Tạo `core/widgets/empty_state.dart` — Empty state với icon, message, CTA button | Reusable widget |
| 3.4 | Áp dụng loading/error/empty cho tất cả 5 screens | Xem checklist 4.7 → all ✅ |
| 3.5 | Thêm Pull-to-refresh cho Statistics, Maintenance, Settings | Consistent gesture |
| 3.6 | Chuẩn hóa Card styles: mọi card dùng GradientCard hoặc standard card pattern | Visual consistency |
| 3.7 | Chuẩn hóa entrance animations (flutter_animate) cho mọi screen | Motion consistency |
| 3.8 | Accessibility: thêm Semantics labels cho mọi interactive widget | WCAG baseline |
| 3.9 | Accessibility: battery state hiển thị text label kèm màu | Color-blind support |
| 3.10 | Responsive: test trên tablet, adjust layouts nếu cần | Layout kiểm tra |
| 3.11 | Dark/Light theme toggle (nếu đủ thời gian — stretch goal) | AppTheme.lightTheme |
| 3.12 | Chuẩn hóa copywriting: audit tất cả strings, đảm bảo tiếng Việt nhất quán | Strings review |

### Phụ thuộc
- Phase 2 hoàn thành (mọi screen có data sources cuối cùng).
- Phase 3 chạy song song với Phase 4 (2 track khác nhau: UI vs Backend).

### Rủi ro

| Rủi ro | Xác suất | Tác động | Giảm thiểu |
|--------|---------|---------|-----------|
| Refactor UI gây regression | Trung bình | Bugs | Test mỗi screen sau refactor, screenshot tests |
| Dark/Light theme phức tạp hơn dự kiến | Cao | Scope creep | Đặt là stretch goal, skip nếu thiếu thời gian |
| Accessibility chỉnh nhiều widget | Thấp | +1 tuần | Ưu tiên interactive widgets trước |

### KPI

| Metric | Target |
|--------|--------|
| Screens có shimmer loading | 5/5 |
| Screens có error state | 5/5 |
| Screens có pull-to-refresh | 5/5 |
| Accessibility Semantics labels | ≥ 80% interactive widgets |
| Visual regression (manual test) | 0 unintended changes |

### Definition of Done
- [ ] 3 shared widgets mới: LoadingSkeleton, ErrorState, EmptyState.
- [ ] Mọi screen dùng shared loading/error/empty widgets.
- [ ] Pull-to-refresh hoạt động trên tất cả 5 tabs.
- [ ] Card styles nhất quán (kiểm tra visual).
- [ ] Entrance animations nhất quán (stagger pattern thống nhất).
- [ ] Semantics labels cho buttons, cards, navigation items.
- [ ] Battery state hiển thị text label: "Tốt", "Trung bình", "Thấp", "Nguy hiểm".
- [ ] Tất cả user-facing strings là tiếng Việt, tuân thủ copywriting rules.

---

## Phase 4 — Hợp nhất Backend + Production Readiness (6 tuần) ⟨Song song với Phase 3⟩

### Mục tiêu
Web Dashboard kết nối Firestore thật, AI model nâng cấp, chuẩn bị production deployment.

### Hạng mục chính

| # | Task | Xử lý điểm lệch | Deliverable |
|---|------|------------------|-------------|
| 4.1 | Web Dashboard kết nối Firestore (thay in-memory) | DL-CHG-02, DL-MAN-01, DL-VEH-01, DL-STAT-04 | `firebase-admin` Python + Firestore reads/writes |
| 4.2 | Web Dashboard hiển thị TripLogs, MaintenanceTasks | DL-TRIP-01, DL-MAINT-01 | Thêm routes + UI components |
| 4.3 | Web Dashboard dùng cùng API contract với Mobile | — | Endpoints trả về cùng format |
| 4.4 | AI model upgrade: train regression model trên charge data thật | DL-STAT-02 | scikit-learn hoặc TensorFlow Lite model |
| 4.5 | AI API containerize (Docker) + deployment setup | — | Dockerfile + docker-compose |
| 4.6 | Firebase Security Rules viết production-grade | — | Firestore rules file, tested |
| 4.7 | Performance audit: Firestore query optimization, index creation | — | Composite indexes, query profiling |
| 4.8 | Error monitoring setup (Crashlytics hoặc Sentry) | — | SDK integration + dashboard |
| 4.9 | Web Dashboard responsive + mobile-friendly | — | CSS media queries |
| 4.10 | End-to-end test: Mobile tạo data → Web hiển thị → AI phân tích | — | E2E test script |

### Phụ thuộc
- Phase 2 hoàn thành (AI API đọc Firestore).
- Firebase service account (đã setup Phase 2).
- Phase 4 chạy song song với Phase 3.

### Rủi ro

| Rủi ro | Xác suất | Tác động | Giảm thiểu |
|--------|---------|---------|-----------|
| Web migration từ in-memory sang Firestore phức tạp | Trung bình | +2 tuần | Giữ lại in-memory như fallback |
| ML model training data không đủ | Cao | Model kém | Dùng synthetic data + statistical baseline |
| Firebase Security Rules block legitimate queries | Trung bình | App broken | Test rules trên emulator trước deploy |

### KPI

| Metric | Target |
|--------|--------|
| Web Dashboard Firestore integration | 100% endpoints kết nối Firestore |
| Dữ liệu Mobile ↔ Web khớp | 100% consistency |
| AI model accuracy (vs statistical baseline) | ≥ 15% improvement |
| Firebase Security Rules test coverage | ≥ 20 test cases |
| Docker build + run time | < 60s build, < 5s startup |
| Điểm lệch 🔴 đã fix | 4/4 |

### Definition of Done
- [ ] Web Dashboard CRUD operations đọc/ghi Firestore.
- [ ] Tạo charge log trên Mobile → hiển thị trên Web (< 5s delay).
- [ ] Web hiển thị TripLogs và MaintenanceTasks.
- [ ] AI model trained, deployed trong Docker container.
- [ ] Firebase Security Rules deployed, tested.
- [ ] Performance: Firestore queries < 500ms p95.
- [ ] Error monitoring active, capturing crashes.
- [ ] E2E test pass: Mobile → Firestore → Web → AI pipeline.

---

# 6. PUBLIC APIs & INTERFACE CONTRACTS

## 6.1 Firestore Contract

### Collection: `Vehicles`

```
/Vehicles/{vehicleId}
```

| Field | Type | Required | Default | Mô tả |
|-------|------|----------|---------|-------|
| `vehicleId` | string | ✅ | — | Document ID, format: `VF-{MODEL}-{NUM}` |
| `vehicleName` | string | ✅ | — | Tên hiển thị |
| `currentOdo` | int | ✅ | 0 | Số km hiện tại |
| `currentBattery` | int | ✅ | 100 | Pin hiện tại (0-100) |
| `stateOfHealth` | double | ✅ | 100.0 | SoH % (0-100) |
| `defaultEfficiency` | double | ✅ | 1.2 | km / 1% battery (VinFast Feliz Neo) |
| `totalCharges` | int | ✅ | 0 | Tổng số lần sạc |
| `totalTrips` | int | ✅ | 0 | Tổng số chuyến đi |
| `lastBatteryPercent` | int | ✅ | 100 | Pin lần cập nhật cuối |
| `avatarColor` | string | ✅ | "#00C853" | Hex color cho avatar |
| `updatedAt` | timestamp | ✅* | — | *Thêm Phase 1 |
| `createdAt` | timestamp | ✅* | — | *Thêm Phase 1 |

**Quy tắc cập nhật xuyên tính năng**:
- `currentOdo`: Chỉ tăng, KHÔNG bao giờ giảm. Cập nhật bởi: `saveChargeLogAndUpdateOdo()`, `saveTripAndUpdateVehicle()`.
- `currentBattery`: Cập nhật khi kết thúc sạc (= endBatteryPercent) hoặc kết thúc trip (= endBattery).
- `totalCharges`: +1 mỗi lần `saveChargeLogAndUpdateOdo()`.
- `totalTrips`: +1 mỗi lần `saveTripAndUpdateVehicle()`.

### Collection: `ChargeLogs`

```
/ChargeLogs/{logId}
```

| Field | Type | Required | Mô tả |
|-------|------|----------|-------|
| `logId` | string | ✅ | UUID v4 |
| `vehicleId` | string | ✅ | FK → Vehicles.vehicleId |
| `startBatteryPercent` | int | ✅ | 0-100 |
| `endBatteryPercent` | int | ✅ | 0-100, > startBatteryPercent |
| `odoAtCharge` | int | ✅ | km, ≥ Vehicle.currentOdo tại thời điểm tạo |
| `startTime` | timestamp | ✅ | Bắt đầu sạc |
| `endTime` | timestamp | ✅ | Kết thúc sạc, > startTime |
| `updatedAt` | timestamp | ✅* | *Thêm Phase 1 |

**Computed (client-side)**:
- `chargeGain` = endBatteryPercent - startBatteryPercent
- `chargeDuration` = endTime - startTime
- `chargeRate` = chargeGain / durationMinutes

### Collection: `TripLogs`

```
/TripLogs/{tripId}
```

| Field | Type | Required | Mô tả |
|-------|------|----------|-------|
| `tripId` | string | ✅ | UUID v4 |
| `vehicleId` | string | ✅ | FK → Vehicles.vehicleId |
| `startTime` | timestamp | ✅ | Bắt đầu trip |
| `endTime` | timestamp | ✅ | Kết thúc trip |
| `distance` | double | ✅ | km (GPS-based) |
| `startBattery` | int | ✅ | 0-100 |
| `endBattery` | int | ✅ | 0-100, ≤ startBattery |
| `batteryConsumed` | int | ✅ | startBattery - endBattery |
| `efficiency` | double | ✅ | km / 1% battery |
| `startOdo` | int | ✅ | km |
| `endOdo` | int | ✅ | km, > startOdo |
| `payloadType` | string | ✅ | "onePerson" / "twoPerson" |
| `updatedAt` | timestamp | ✅* | *Thêm Phase 1 |

**Computed (client-side)**:
- `duration` = endTime - startTime
- `avgSpeed` = distance / durationHours

### Collection: `MaintenanceTasks`

```
/MaintenanceTasks/{taskId}
```

| Field | Type | Required | Mô tả |
|-------|------|----------|-------|
| `taskId` | string | ✅ | UUID v4 |
| `vehicleId` | string | ✅ | FK → Vehicles.vehicleId |
| `title` | string | ✅ | Tên task |
| `description` | string | ❌ | Mô tả chi tiết |
| `targetOdo` | int | ✅ | km khi cần thực hiện |
| `isCompleted` | bool | ✅ | false |
| `completedDate` | timestamp | ❌ | Ngày hoàn thành (null nếu chưa) |
| `createdAt` | timestamp | ✅ | Ngày tạo |
| `updatedAt` | timestamp | ✅* | *Thêm Phase 1 |

**Logic kiểm tra**:
- `isDueSoon` = Vehicle.currentOdo ≥ targetOdo - 50
- `isOverdue` = Vehicle.currentOdo ≥ targetOdo
- `remainingKm` = targetOdo - Vehicle.currentOdo

## 6.2 Service Contract nội bộ

### TripTrackingService

```
┌──────────────────────────────────────┐
│         TripTrackingService          │
│  (Singleton)                         │
├──────────────────────────────────────┤
│  State (read-only from outside):     │
│  ─ isTracking: bool                  │
│  ─ vehicleId: String?               │
│  ─ totalDistance: double (km)        │
│  ─ currentBattery: int (%)          │
│  ─ startTime: DateTime?             │
│  ─ payload: PayloadType             │
├──────────────────────────────────────┤
│  Events / Write:                     │
│  ─ startTrip(vehicleId, payload,     │
│      startBattery, startOdo,         │
│      efficiency, onUpdate)           │
│  ─ stopTrip() → TripLogModel?       │
├──────────────────────────────────────┤
│  Persistence:                        │
│  ─ SharedPrefs: trip_active (bool)   │
│  Reads:                              │
│  ─ GPS stream (Geolocator)          │
│  Writes:                             │
│  ─ Firestore: TripLogs (on stop)    │
│  ─ Firestore: Vehicles (on stop)    │
│  ─ NotificationService (ongoing)    │
└──────────────────────────────────────┘
```

### ChargeTrackingService

```
┌──────────────────────────────────────┐
│       ChargeTrackingService          │
│  (Singleton)                         │
├──────────────────────────────────────┤
│  State (read-only from outside):     │
│  ─ isCharging: bool                  │
│  ─ vehicleId: String?               │
│  ─ currentBattery: double (%)       │
│  ─ startBattery: int                │
│  ─ startTime: DateTime?             │
│  ─ chargeRatePerMin: double         │
├──────────────────────────────────────┤
│  Events / Write:                     │
│  ─ startCharging(vehicleId,          │
│      startBattery, currentOdo,       │
│      chargeRate)                     │
│  ─ stopCharging() → ChargeLogModel? │
├──────────────────────────────────────┤
│  Persistence:                        │
│  ─ SharedPrefs: charge_active,       │
│    vehicleId, startBattery,          │
│    startTime                         │
│  Reads:                              │
│  ─ Timer (30s interval)             │
│  Writes:                             │
│  ─ Firestore: ChargeLogs (on stop)  │
│  ─ Firestore: Vehicles (on stop)    │
│  ─ NotificationService (80%, 100%)  │
└──────────────────────────────────────┘
```

### NotificationService

```
┌──────────────────────────────────────┐
│       NotificationService            │
│  (Singleton, flutter_local_notif.)   │
├──────────────────────────────────────┤
│  Channels:                           │
│  ─ charge_channel (high importance)  │
│  ─ trip_channel (low importance)     │
│  ─ maintenance_channel (high)        │
├──────────────────────────────────────┤
│  Notification IDs:                   │
│  ─ 1001: Charge 80%                 │
│  ─ 1002: Charge 100%                │
│  ─ 1003: Charging ongoing           │
│  ─ 1004: Trip ongoing               │
│  ─ 2000+: Maintenance (base+index)  │
├──────────────────────────────────────┤
│  Methods:                            │
│  ─ init()                            │
│  ─ notifyCharge80()                  │
│  ─ notifyCharge100()                 │
│  ─ showChargingOngoing(battery, dur) │
│  ─ showTripOngoing(dist, battery)    │
│  ─ notifyMaintenanceDue(task, km)    │
│  ─ cancel(id), cancelAll()          │
└──────────────────────────────────────┘
```

### BackgroundServiceConfig

```
┌──────────────────────────────────────┐
│     BackgroundServiceConfig          │
│  (flutter_background_service)        │
├──────────────────────────────────────┤
│  Android Foreground Service          │
│  ─ Channel: vinfast_bg_channel       │
│  ─ Notification ID: 888             │
│  ─ Heartbeat: 10s                   │
├──────────────────────────────────────┤
│  Commands (via sendCommand):         │
│  ─ startTrip                         │
│  ─ stopTrip                          │
│  ─ startCharge                       │
│  ─ stopCharge                        │
├──────────────────────────────────────┤
│  Static methods:                     │
│  ─ initialize()                      │
│  ─ startService() / stopService()    │
│  ─ sendCommand(Map<String,dynamic>)  │
│  ─ onDataReceived → Stream          │
└──────────────────────────────────────┘
```

## 6.3 HTTP API Contract — AI

### Base URL
- **Development**: `http://10.0.2.2:5001` (Android emulator → host localhost)
- **Production**: TBD (Phase 4 deployment)

### `GET /api/health`

**Response** `200`:
```json
{
  "status": "ok",
  "version": "2.0-statistical"
}
```

### `POST /api/predict-degradation`

**Request**:
```json
{
  "vehicleId": "string (required)",
  "chargeLogs": [
    {
      "startBatteryPercent": "int 0-100",
      "endBatteryPercent": "int 0-100",
      "startTime": "ISO 8601 string",
      "endTime": "ISO 8601 string",
      "odoAtCharge": "int (km)"
    }
  ],
  "tripLogs": []  // Phase 2: thêm field này
}
```

**Response** `200`:
```json
{
  "success": true,
  "data": {
    "healthScore": "float 0-100",
    "healthStatus": "string (Tốt | Khá | Trung bình | Kém)",
    "healthStatusCode": "string (good | fair | average | poor)",
    "equivalentCycles": "float",
    "remainingCycles": "float",
    "estimatedLifeMonths": "float",
    "avgChargeRate": "float (%/hour)",
    "avgDoD": "float (average depth of discharge %)",
    "chargeRateTrend": "float (slope, negative = degrading)",
    "totalOdometer": "int (km)",
    "degradationFactors": [
      {
        "factor": "string",
        "impact": "float",
        "percentage": "int"
      }
    ],
    "recommendations": ["string"],
    "confidence": "float 0-100",
    "modelVersion": "string"
  }
}
```

**Error** `400`:
```json
{
  "success": false,
  "error": "Mô tả lỗi"
}
```

### `POST /api/analyze-patterns`

**Request**: Tương tự predict-degradation.

**Response** `200`:
```json
{
  "success": true,
  "data": {
    "avgChargeStartPercent": "float",
    "avgChargeEndPercent": "float",
    "preferredChargeHour": "int 0-23",
    "chargesPerWeek": "float",
    "fastChargePercentage": "float",
    "slowChargePercentage": "float"
  }
}
```

### `POST /api/estimate-range` *(Phase 2 — mới)*

**Request**:
```json
{
  "vehicleId": "string",
  "currentBattery": "int 0-100",
  "payloadType": "onePerson | twoPerson",
  "recentEfficiency": "float (km/%) — optional, API tự tính nếu có Firestore access"
}
```

**Response** `200`:
```json
{
  "success": true,
  "data": {
    "estimatedRangeKm": "float",
    "confidenceLevel": "string (high | medium | low)",
    "basedOnTrips": "int (number of trips used for calculation)"
  }
}
```

## 6.4 HTTP API Contract — Web Dashboard

### Base URL
- **Development**: `http://localhost:5000`

### Hiện tại (In-memory)

| Method | Endpoint | Trạng thái |
|--------|----------|-----------|
| `GET /` | Render index.html | ✅ Hoạt động |
| `GET /api/vehicles` | List vehicles | ✅ In-memory |
| `GET /api/vehicles/<id>` | Get vehicle | ✅ In-memory |
| `GET /api/charge-logs?vehicleId=` | List charge logs | ✅ In-memory |
| `POST /api/charge-logs` | Add charge log | ✅ In-memory |
| `DELETE /api/charge-logs/<id>` | Delete charge log | ✅ In-memory |
| `GET /api/stats/<id>` | Vehicle stats | ✅ In-memory |

### Phase 4 Migration

Tất cả endpoints giữ nguyên URL và response format, chỉ thay backend:
- `vehicles_db` dict → `firebase_admin.firestore` collection `Vehicles`
- `charge_logs_db` list → `firebase_admin.firestore` collection `ChargeLogs`
- Thêm endpoints mới:
  - `GET /api/trip-logs?vehicleId=` → collection `TripLogs`
  - `GET /api/maintenance?vehicleId=` → collection `MaintenanceTasks`
  - `POST /api/maintenance` → Create task
  - `PUT /api/maintenance/<id>/complete` → Complete task

## 6.5 Nguồn sự thật duy nhất (Single Source of Truth)

### Nguyên tắc

```
            ┌──────────────────────────────┐
            │     CLOUD FIRESTORE          │
            │  ═══════════════════════     │
            │  Nguồn sự thật duy nhất      │
            │  cho TẤT CẢ dữ liệu         │
            │  persistent                   │
            └──────────┬───────────────────┘
                       │
         ┌─────────────┼─────────────────┐
         ▼             ▼                 ▼
   ┌──────────┐  ┌──────────┐     ┌──────────┐
   │ Mobile   │  │ Web      │     │ AI API   │
   │ (SDK)    │  │ (Admin)  │     │ (Admin)  │
   │          │  │          │     │          │
   │ Read/    │  │ Read/    │     │ Read-    │
   │ Write    │  │ Write    │     │ only     │
   └──────────┘  └──────────┘     └──────────┘
```

### Quy tắc đồng bộ

| Quy tắc | Mô tả |
|---------|-------|
| **R1**: Firestore là nguồn sự thật | Mọi dữ liệu persistent PHẢI lưu trong Firestore |
| **R2**: Không in-memory DB | Web Dashboard PHẢI đọc/ghi Firestore (Phase 4) |
| **R3**: AI đọc trực tiếp | AI API PHẢI đọc Firestore bằng Admin SDK (Phase 2) |
| **R4**: Client gửi ID, không data | Mobile/Web gửi vehicleId, server tự query data |
| **R5**: Transaction cho write đa collection | Mọi write ảnh hưởng ≥ 2 collections PHẢI dùng transaction |
| **R6**: ODO chỉ tăng | Validation tại cả client và server: newOdo ≥ currentOdo |
| **R7**: Timestamps UTC | Mọi timestamp lưu UTC, chuyển đổi timezone tại client |
| **R8**: updatedAt mỗi write | Mỗi document update PHẢI set updatedAt = server timestamp |

### Hướng đồng bộ Mobile-Web-AI

| Phase | Mobile | Web | AI |
|-------|--------|-----|-----|
| **Hiện tại** | Firestore SDK (read/write) | In-memory (tách biệt) | HTTP body từ mobile |
| **Phase 2** | Firestore SDK (read/write) | In-memory (tách biệt) | Firebase Admin SDK (read) |
| **Phase 4** | Firestore SDK (read/write) | Firebase Admin SDK (read/write) | Firebase Admin SDK (read) |

**Kết quả Phase 4**: Cả 3 nền tảng đọc/ghi cùng 1 Firestore → dữ liệu luôn nhất quán, real-time sync.

---

# 7. PHỤ LỤC

## 7.1 Glossary

| Thuật ngữ | Định nghĩa |
|-----------|-----------|
| **SoH** | State of Health — % sức khỏe pin, tính từ efficiency hiện tại / efficiency gốc |
| **DoD** | Depth of Discharge — % pin đã xả trước khi sạc lại (100 - startBattery%) |
| **Equivalent Cycle** | 1 lần sạc từ 0→100% = 1 cycle; sạc 50→100% = 0.5 cycle |
| **Efficiency** | Số km đi được trên 1% pin (km/%) |
| **Payload Factor** | Hệ số tiêu hao theo tải: 1 người = 1.0×, 2 người = 1.3× |
| **Charge Rate** | Tốc độ sạc (% pin / phút) |
| **ODO** | Odometer — tổng số km đã đi |
| **Transaction** | Firestore batch write đảm bảo atomic: hoặc tất cả success hoặc tất cả rollback |

## 7.2 Danh sách file chính

```
lib/
├── main.dart                              # Entry point, Firebase init
├── app.dart                               # MaterialApp config
├── core/
│   ├── constants/app_constants.dart        # Firestore names, battery thresholds
│   ├── theme/app_colors.dart              # Color tokens (25+ colors)
│   ├── theme/app_theme.dart               # Material 3 dark theme + typography
│   └── widgets/
│       ├── animated_battery_gauge.dart    # Circular battery animation
│       ├── gradient_card.dart             # Glassmorphism card
│       └── stat_card.dart                 # Metric display card
├── data/
│   ├── models/
│   │   ├── vehicle_model.dart             # Vehicle fields + Firestore serialization
│   │   ├── charge_log_model.dart          # Charge log + computed properties
│   │   ├── trip_log_model.dart            # Trip log + PayloadType enum
│   │   └── maintenance_task_model.dart    # Task + isDueSoon/isOverdue logic
│   ├── repositories/
│   │   ├── charge_log_repository.dart     # Vehicle + ChargeLog CRUD, transactions
│   │   ├── trip_log_repository.dart       # TripLog CRUD, vehicle updates
│   │   └── maintenance_repository.dart    # MaintenanceTask CRUD
│   └── services/
│       ├── notification_service.dart       # Local notifications (3 channels)
│       ├── battery_logic_service.dart      # SoH, efficiency, charge rate calc
│       ├── trip_tracking_service.dart      # GPS tracking singleton
│       ├── charge_tracking_service.dart    # Simulated charge singleton
│       ├── ai_prediction_service.dart      # HTTP client for Flask AI
│       └── background_service_config.dart  # Foreground service setup
├── features/
│   ├── dashboard/dashboard_screen.dart     # Tab 1: SoH + active tracking
│   ├── home/home_screen.dart              # Tab 2: Battery gauge + recent charges
│   ├── charge_log/
│   │   ├── charge_log_screen.dart          # Charge history list
│   │   ├── add_charge_log_modal.dart       # Manual charge form
│   │   └── add_charge_log_controller.dart  # Form state + validation
│   ├── statistics/statistics_screen.dart    # Tab 3: Charts + AI
│   ├── maintenance/maintenance_screen.dart  # Tab 4: Task management
│   └── settings/settings_screen.dart       # Tab 5: Vehicle management
└── navigation/app_navigation.dart          # 5-tab bottom nav

ai_api.py          # Flask AI API (port 5001)
app.py             # Flask Web Dashboard (port 5000)
templates/index.html
static/css/style.css
static/js/app.js
requirements.txt   # flask, flask-cors, numpy
pubspec.yaml       # Flutter dependencies
```

## 7.3 Firebase Project Info

| Key | Value |
|-----|-------|
| Project ID | `vinfast-873db` |
| Project Number | `450938791386` |
| Storage Bucket | `vinfast-873db.firebasestorage.app` |
| Android Package | `com.bes.vinbatery` |
| App ID | `1:450938791386:android:fde2bf0210038fa32dcce3` |

## 7.4 Checklist tổng kiểm tra tài liệu

| Tiêu chí | Đạt? |
|---------|:----:|
| Mọi tính năng chính đều xuất hiện trong feature map (Section 2) | ✅ |
| Mọi tính năng chính đều xuất hiện trong sync matrix (Section 3) | ✅ |
| Mọi roadmap item có deliverable đo được | ✅ |
| Mọi roadmap item có owner gợi ý | ✅ |
| Mọi roadmap item có KPI | ✅ |
| Mọi roadmap item có Definition of Done | ✅ |
| Mỗi màn hình chính có mapping về token/component/state pattern | ✅ |
| Mọi điểm lệch dữ liệu quan trọng có phương án xử lý + phase | ✅ |
| Implementer khác có thể triển khai theo tài liệu | ✅ |

---

> **Hết tài liệu.**  
> File này là nguồn tham chiếu duy nhất cho roadmap, đồng bộ tính năng, và chuẩn UI/UX.  
> Cập nhật khi có thay đổi scope hoặc hoàn thành phase.
