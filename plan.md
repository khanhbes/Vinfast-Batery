# Prompt Yêu Cầu Code: Tính năng Nhập nhật ký sạc thủ công

## 1. Ngữ cảnh (Context)
Đóng vai là một Senior Flutter Developer. Tôi đang xây dựng một ứng dụng quản lý xe máy điện VinFast. Tech stack hiện tại bao gồm: Flutter, Firebase Cloud Firestore, và Riverpod để quản lý State.

## 2. Yêu cầu (Task)
Hãy viết code hoàn chỉnh cho tính năng "Nhập nhật ký sạc thủ công" (Add Manual Charge Log). Tính năng này cho phép người dùng mở một form điền thông tin sau khi họ sạc xe xong và lưu trực tiếp vào Firestore.

## 3. Cấu trúc Database liên quan (Firestore)
* **Collection `Vehicles`**: chứa document của xe hiện tại.
  * Fields cần thiết: `vehicleId` (string), `currentOdo` (int).
* **Collection `ChargeLogs`**: chứa lịch sử sạc.
  * Fields cần thiết: `logId` (string), `vehicleId` (string), `startTime` (timestamp), `endTime` (timestamp), `startBatteryPercent` (int), `endBatteryPercent` (int), `odoAtCharge` (int).

## 4. Yêu cầu về UI/UX (View)
* Tạo một `StatefulWidget` hoặc `ConsumerWidget` có dạng Bottom Sheet hoặc Dialog (tên class: `AddChargeLogModal`).
* Các trường nhập liệu (TextFormField):
  * Mức pin trước khi sạc (%, giới hạn 0-100).
  * Mức pin sau khi sạc (%, giới hạn 0-100, hint text/mặc định có thể là 100).
  * ODO hiện tại trên đồng hồ xe (km).
  * Thời gian bắt đầu sạc và kết thúc sạc (sử dụng Date/Time Picker của Flutter).
* Cần có nút "Lưu nhật ký" (Nút này sẽ disable và hiển thị loading spinner khi đang thực hiện gọi API Firebase).

## 5. Yêu cầu về Logic & Validation (ViewModel/Controller)
**Validation Form:**
* Tất cả các trường nhập liệu không được để trống.
* `startBatteryPercent` và `endBatteryPercent` phải là số nguyên nằm trong khoảng từ 0 đến 100.
* `endBatteryPercent` bắt buộc phải lớn hơn `startBatteryPercent`.
* `odoAtCharge` nhập vào bắt buộc phải **lớn hơn hoặc bằng** `currentOdo` lấy từ collection `Vehicles`.
* `endTime` phải là thời điểm diễn ra sau `startTime`.

**Xử lý lưu dữ liệu (Dùng Batch write hoặc Transaction):** Khi người dùng bấm lưu và form hợp lệ, cần thực hiện đồng thời 2 thao tác để đảm bảo tính toàn vẹn dữ liệu:
1. Tạo một document mới trong collection `ChargeLogs`.
2. Cập nhật lại trường `currentOdo` thành giá trị mới trong document của xe tương ứng ở collection `Vehicles`.

## 6. Đầu ra mong đợi (Output)
1. Cung cấp code cho lớp **Repository/Service** xử lý các hàm gọi Firebase (bắt buộc dùng Batch hoặc Transaction).
2. Cung cấp code cho **Controller/Notifier (Riverpod)** xử lý logic form, quản lý trạng thái loading và validation.
3. Cung cấp code **UI (Flutter Widget)** với các TextFormField đầy đủ validation và hiển thị lỗi trực quan bên dưới text field cho người dùng.

*Lưu ý: Tuân thủ Clean Architecture, chia tách file hợp lý, phân định rõ ràng giữa UI và Logic.*

---

# 📱 Kế Hoạch Phát Triển Tổng Thể — VinFast Battery App

## 7. Tổng quan dự án

**Mục tiêu**: Xây dựng ứng dụng Android (Flutter) quản lý pin xe máy điện VinFast — theo dõi chu kỳ sạc, phân tích tiêu thụ điện, và tích hợp AI dự đoán chai pin.

**Chiến lược phát triển**: Hybrid theo giai đoạn
- **Phase 1 (MVP)**: Firebase trực tiếp — CRUD, offline support, demo data
- **Phase 2 (Mở rộng)**: Kết nối Firebase thật + tối ưu UX
- **Phase 3 (AI)**: Flask API backend cho ML dự đoán tuổi thọ pin

## 8. Tech Stack

| Layer | Công nghệ | Mục đích |
|-------|-----------|----------|
| Framework | Flutter 3.x | Cross-platform (Android ưu tiên) |
| State Management | Riverpod (StateNotifier) | Reactive, testable |
| Database | Firebase Cloud Firestore | Realtime sync, offline |
| Charts | fl_chart 0.70+ | Biểu đồ xu hướng & thống kê |
| Animations | flutter_animate | Micro-interactions, staggered |
| Typography | Google Fonts (Inter) | Premium UI |
| Backend (Phase 3) | Flask + Python | AI/ML prediction API |

## 9. Kiến trúc ứng dụng (Clean Architecture)

```
lib/
├── main.dart                              # Entry point + ProviderScope
├── app.dart                               # MaterialApp (Dark Theme)
│
├── core/                                  # ── SHARED / FOUNDATION ──
│   ├── theme/
│   │   ├── app_colors.dart                # 25+ color tokens (VinFast green brand)
│   │   └── app_theme.dart                 # Material 3 dark theme + Google Fonts
│   ├── constants/
│   │   └── app_constants.dart             # Collection names, validation limits
│   └── widgets/
│       ├── animated_battery_gauge.dart    # Custom circular gauge (sweep gradient + glow)
│       ├── gradient_card.dart             # Glassmorphism card (backdrop blur)
│       └── stat_card.dart                 # Reusable metric display card
│
├── data/                                  # ── DATA LAYER ──
│   ├── models/
│   │   ├── vehicle_model.dart             # Xe: id, name, odo, totalCharges, lastBattery
│   │   └── charge_log_model.dart          # Log: pin trước/sau, thời gian, ODO, computed props
│   └── repositories/
│       └── charge_log_repository.dart     # CRUD + demo data source (45 sample logs)
│
├── features/                              # ── FEATURE MODULES ──
│   ├── home/
│   │   └── home_screen.dart               # Dashboard: gauge, stats grid, recent charges
│   ├── charge_log/
│   │   ├── charge_log_screen.dart         # Lịch sử sạc: date groups, delete, pull-refresh
│   │   ├── add_charge_log_modal.dart      # Bottom sheet form nhập sạc (✅ đã hoàn thành)
│   │   └── add_charge_log_controller.dart # Riverpod StateNotifier + validation
│   ├── statistics/
│   │   └── statistics_screen.dart         # Charts, battery health, consumption, patterns
│   └── settings/
│       └── settings_screen.dart           # Vehicle management, app info, about
│
└── navigation/
    └── app_navigation.dart                # Bottom nav 4 tabs (pill-style indicator)
```

## 10. Cấu trúc Database mở rộng (Firestore)

### Collection `Vehicles`
| Field | Type | Mô tả |
|-------|------|--------|
| `vehicleId` | string | ID xe (VF-OPES-001) |
| `vehicleName` | string | Tên hiển thị (VinFast Opes) |
| `currentOdo` | int | Số ODO hiện tại (km) |
| `totalCharges` | int | Tổng số lần sạc |
| `lastBatteryPercent` | int | % pin lần sạc cuối |
| `avatarColor` | string | Màu đại diện (#00C853) |

### Collection `ChargeLogs`
| Field | Type | Mô tả |
|-------|------|--------|
| `logId` | string (auto) | ID tự sinh |
| `vehicleId` | string | FK → Vehicles |
| `startTime` | timestamp | Thời gian bắt đầu sạc |
| `endTime` | timestamp | Thời gian kết thúc sạc |
| `startBatteryPercent` | int | % pin trước sạc (0-100) |
| `endBatteryPercent` | int | % pin sau sạc (0-100) |
| `odoAtCharge` | int | Số ODO tại lúc sạc (km) |

### Computed Properties (trong ChargeLogModel)
- `chargeGain` = `endBatteryPercent - startBatteryPercent`
- `chargeDuration` = `endTime - startTime`
- `durationText` = format "2h 30m"

## 11. Các màn hình (4 tabs)

### 🏠 Tab 1: Trang chủ (HomeScreen)
- **Animated Battery Gauge**: Vòng tròn hiển thị % pin, đổi màu theo mức (xanh/vàng/đỏ)
- **Vehicle Selector**: Dropdown chọn xe đang theo dõi
- **Quick Stats Grid**: 4 card (tổng sạc, sạc TB, năng lượng nạp, thời gian TB)
- **Recent Charges**: 5 lần sạc gần nhất
- **FAB**: Nút "Nhập sạc" → AddChargeLogModal

### 📋 Tab 2: Lịch sử sạc (ChargeLogScreen)
- **Summary Bar**: Tổng lần / Tổng nạp / Sạc TB
- **Date-grouped List**: Phân nhóm HÔM NAY, HÔM QUA, ngày cụ thể
- **Detail Cards**: Pin trước→sau, thời gian, duration, ODO, battery progress bar
- **Delete**: Xác nhận xóa log
- **Pull-to-refresh**

### 📊 Tab 3: Thống kê (StatisticsScreen)
- **Summary Cards**: 4 metrics tổng quan
- **Line Chart**: Xu hướng sạc — charge gain + start battery (20 lần gần nhất)
- **Battery Health Card**: Điểm sức khỏe 0-100, so sánh tốc độ sạc gần đây vs cũ, cảnh báo degradation
- **Bar Chart**: Tiêu thụ điện theo tuần (8 tuần)
- **Charging Pattern**: Giờ/ngày sạc phổ biến, chu kỳ sạc trung bình

### ⚙️ Tab 4: Cài đặt (SettingsScreen)
- **Vehicle Info Card**: Tên, ID, ODO, tổng sạc (gradient card)
- **Vehicle List**: Chọn xe đang active
- **App Settings**: Version, Firebase status, AI feature teaser
- **About**: VinFast Battery branding

## 12. Trạng thái triển khai hiện tại

| Thành phần | Trạng thái | Ghi chú |
|------------|-----------|---------|
| Flutter project setup | ✅ Hoàn thành | `flutter create`, pubspec.yaml |
| Design System (colors, theme) | ✅ Hoàn thành | Dark theme, 25+ tokens |
| Core Widgets | ✅ Hoàn thành | Battery gauge, cards |
| Data Models | ✅ Hoàn thành | Vehicle, ChargeLog (extended) |
| Repository (Firebase) | ✅ Hoàn thành | Firestore CRUD + Transaction |
| HomeScreen | ✅ Hoàn thành | Gauge, stats, recent charges |
| ChargeLogScreen | ✅ Hoàn thành | Date groups, detail cards |
| AddChargeLogModal | ✅ Hoàn thành | Form, validation, save |
| StatisticsScreen | ✅ Hoàn thành | Charts, health, patterns, AI |
| SettingsScreen | ✅ Hoàn thành | Vehicle mgmt, about |
| Bottom Navigation | ✅ Hoàn thành | 4 tabs, pill indicator |
| APK Build | ✅ Hoàn thành | `app-debug.apk` with Firebase |
| Firebase Integration | ✅ Hoàn thành | google-services.json, init, Firestore |
| Flask AI API | ✅ Hoàn thành | predict-degradation, analyze-patterns |
| AI Widget (Flutter) | ✅ Hoàn thành | AiPredictionService + UI widget |

## 13. Roadmap chi tiết

### 📌 Phase 1: MVP — Demo Mode (✅ DONE)
> *Mục tiêu: App chạy được với demo data, UI/UX hoàn chỉnh*

- [x] Tạo Flutter project + dependencies
- [x] Thiết lập Dark Theme (VinFast green brand)
- [x] Animated Battery Gauge widget
- [x] 4 màn hình (Home, History, Statistics, Settings)
- [x] AddChargeLogModal (form + validation)
- [x] Repository với demo data (45 charge logs)
- [x] Biểu đồ xu hướng & tiêu thụ (fl_chart)
- [x] Battery Health analysis
- [x] Charging Pattern insights
- [x] Build APK thành công

### 📌 Phase 2: Firebase Integration (✅ DONE)
> *Mục tiêu: Kết nối Firebase thật, dữ liệu persist, multi-device*

- [x] Tạo Firebase project trên console.firebase.google.com
- [x] Thêm `google-services.json` vào `android/app/`
- [x] Cấu hình `build.gradle.kts` (Google Services plugin)
- [x] Đồng bộ `applicationId` với Firebase package name (`com.bes.vinbatery`)
- [x] Chuyển Repository từ demo → Firestore (Transaction/Batch)
- [x] Xóa toàn bộ demo data — dùng dữ liệu thật từ Firestore
- [x] Firebase.initializeApp() trong main.dart
- [x] INTERNET permission trong AndroidManifest.xml
- [x] minSdk = 23 cho Firebase compatibility
- [x] Auto-seed khi Firestore trống (tạo xe mặc định)
- [x] Build APK thành công với Firebase
- [ ] Setup Firestore Security Rules
- [ ] Firebase Auth (đăng nhập Google/Email)
- [ ] Offline persistence (Firestore cache)
- [ ] Push Notification nhắc sạc (FCM)

### 📌 Phase 3: AI Dự đoán chai pin (✅ DONE)
> *Mục tiêu: ML prediction tích hợp trong app*

- [x] Xây dựng Flask API (`ai_api.py`)
  - `POST /api/predict-degradation` → Dự đoán chai pin
  - `POST /api/analyze-patterns` → Phân tích thói quen sạc
  - `GET /api/health` → Health check
- [x] BatteryDegradationModel — Tính equivalent cycles, DoD stress, charge rate trend, calendar aging
- [x] ChargingPatternAnalyzer — Phân tích giờ/ngày sạc, chu kỳ, range ưa thích
- [x] Health Score 0-100 với degradation factors và recommendations
- [x] Flutter `AiPredictionService` — HTTP client gọi Flask API
- [x] `_AiPredictionWidget` tích hợp trong StatisticsScreen
- [x] Graceful fallback khi API offline
- [ ] Training model ML nâng cao (Random Forest / LSTM)
- [ ] Dashboard widget "Tuổi thọ pin còn lại" trên HomeScreen

## 14. Lệnh phát triển

```bash
# Chạy app trên emulator/device
flutter run

# Build debug APK
flutter build apk --debug

# Build release APK
flutter build apk --release

# Kiểm tra lỗi code
flutter analyze

# Chạy tests
flutter test

# Cài thêm package
flutter pub add <package_name>

# Cập nhật dependencies
flutter pub upgrade
```

## 15. Design Tokens tham khảo

```
Primary Green:    #00C853   → Brand, CTA, active states
Accent Green:     #00E676   → Gradient highlights
Background:       #0F0F1A   → App background
Surface:          #1A1A2E   → Bottom nav, sheets
Card:             #1E1E36   → Card surfaces
Border:           #2E2E4E   → Subtle borders
Text Primary:     #FFFFFF   → Main text
Text Secondary:   #8888AA   → Descriptions
Text Tertiary:    #5A5A7A   → Hints, labels
Error:            #FF6B6B   → Errors, low battery
Warning:          #FFB74D   → Medium battery
Info:             #448AFF   → ODO, neutral info
```