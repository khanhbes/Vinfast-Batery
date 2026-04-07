# Kế Hoạch Triển Khai Phần Còn Thiếu (MVP Gap Closure, Firestore-first)

## ✅ TRẠNG THÁI: ĐÃ HOÀN THÀNH (2026-04-06)

---

## Tóm tắt
- Mục tiêu đợt này: hoàn thiện các phần thiếu quan trọng theo plan mới của bạn, ưu tiên vận hành thực tế trên app hiện tại.
- Trục thực hiện: `Dual Input` đầy đủ cho trip/charge, `Smart Charging` có target + ETA + nhắc giờ, `Maintenance` có nhắc tự động, wiring background service đúng luồng, và `Route Prediction` bản khung dùng mock (chưa cần Google Maps key thật).
- Không làm trong đợt này: refactor backend-first, Firebase Auth, tích hợp Google Maps production.

## Thay đổi triển khai chính

### ✅ 1. Dual Input cho hành trình (Trip) và sạc (Charge)
**Đã triển khai:**
- `TripLogModel`: thêm `entryMode` (live/manual) + `distanceSource` (gps/odometer) enums
- `ChargeLogModel`: thêm `targetBatteryPercent` + `estimatedCompleteAt` fields
- Tạo `AddManualTripModal` (lib/features/dashboard/add_manual_trip_modal.dart): form nhập tay chuyến đi với validation đầy đủ (pin range, ODO monotonic, endTime > startTime)
- Dashboard: thêm nút "Nhập chuyến đi thủ công" trong Quick Actions
- Dashboard: dialog xác nhận khi stop trip (hiện quãng đường, pin, thời gian)
- Dashboard: dialog xác nhận khi stop charge (hiện pin hiện tại, mục tiêu, đã nạp, thời gian)
- Dashboard: dialog chọn % mục tiêu sạc (80/90/100%) trước khi bắt đầu sạc
- Quy tắc tính: `distance = endOdo - startOdo`, `batteryConsumed = startBattery - endBattery`, `efficiency = distance / batteryConsumed`

### ✅ 2. Smart Charging (target + ETA)
**Đã triển khai:**
- `SmartChargingService` (lib/data/services/smart_charging_service.dart): ETA sạc theo bucketed curve lịch sử, fallback linear khi <3 logs
- `ChargeTrackingService`: thêm `_targetBattery`, `_estimatedCompleteAt`, `_updateEta()`, `etaText` getter
- `NotificationService`: thêm `notifyChargeTarget()` — thông báo khi đạt target
- Dashboard charge banner: hiện Mục tiêu + ETA realtime thay vì tốc độ sạc
- Khi start charge: dialog chọn target (80/90/100%), tính ETA dựa trên adaptive rate
- Khi đạt target: gửi local notification riêng biệt

### ✅ 3. Maintenance reminder tự động
**Đã triển khai:**
- `MaintenanceReminderService` (lib/data/services/maintenance_reminder_service.dart): singleton kiểm tra tasks due_soon/overdue
- Trigger tại: app launch (main.dart), sau stop trip, sau stop charge (dashboard)
- Chống spam: cờ `maint_notified_{taskId}_{threshold}` trong SharedPreferences
- Reset cờ khi: completeTask hoặc deleteTask trong maintenance_screen
- Notification via `NotificationService.notifyMaintenanceDue()`

### ✅ 4. Wiring background service đúng lifecycle
**Đã triển khai:**
- Start trip → `BackgroundServiceConfig.startService()` + `sendCommand('startTrip')`
- Stop trip → `sendCommand('stopTrip')`
- Start charge → `BackgroundServiceConfig.startService()` + `sendCommand('startCharge')`
- Stop charge → `sendCommand('stopCharge')`
- Recovery resume → cũng start service + send command tương ứng
- Giữ kiến trúc hiện tại (isolate chỉ heartbeat, GPS logic ở main isolate)

### ✅ 5. Route consumption prediction (mock)
**Đã triển khai:**
- `RouteDistanceProvider` abstraction + `MockRouteDistanceProvider` (lib/data/services/route_prediction_service.dart)
- `RoutePredictionService.predict()`: tính % pin tiêu hao, pin còn lại, đủ/không đủ
- Hiệu suất lấy theo payload matching từ trip history, fallback default efficiency
- `RoutePredictionCard` widget (lib/features/dashboard/route_prediction_card.dart): expandable card trên dashboard
- User nhập: điểm đến + khoảng cách (km) + tải trọng → kết quả: tiêu hao, còn lại, hiệu suất, đủ pin hay không

## Thay đổi API / Interface / Type (public-facing)
| Thành phần | Thay đổi | Trạng thái |
|---|---|---|
| `TripLogs` schema | Thêm `entryMode` (`live`/`manual`) và `distanceSource` (`odometer`/`gps`) | ✅ |
| `ChargeLogs` schema | Thêm optional `targetBatteryPercent`, `estimatedCompleteAt` | ✅ |
| Trip service contract | `stopTrip()` hiện dialog xác nhận giá trị trước khi lưu | ✅ |
| Charge service contract | `startCharging()` nhận `targetBatteryPercent`; `stopCharging()` chốt log với target | ✅ |
| Route prediction interface | `RouteDistanceProvider` abstraction; `MockRouteDistanceProvider` default | ✅ |

## Files đã tạo mới
- `lib/features/dashboard/add_manual_trip_modal.dart` — Form nhập chuyến đi thủ công
- `lib/features/dashboard/route_prediction_card.dart` — Card dự báo lộ trình
- `lib/data/services/smart_charging_service.dart` — ETA sạc bucketed curve
- `lib/data/services/maintenance_reminder_service.dart` — Nhắc bảo dưỡng tự động
- `lib/data/services/route_prediction_service.dart` — Dự báo tiêu hao lộ trình

## Files đã chỉnh sửa
- `lib/data/models/trip_log_model.dart` — Thêm TripEntryMode, DistanceSource enums + fields
- `lib/data/models/charge_log_model.dart` — Thêm targetBatteryPercent, estimatedCompleteAt
- `lib/data/services/charge_tracking_service.dart` — Target, ETA, notifyTarget logic
- `lib/data/services/trip_tracking_service.dart` — entryMode/distanceSource in saved trip
- `lib/data/services/notification_service.dart` — notifyChargeTarget(), idChargeTarget
- `lib/features/dashboard/dashboard_screen.dart` — Charge target dialog, stop confirmations, manual trip button, route card, background service wiring, maintenance check triggers
- `lib/features/maintenance/maintenance_screen.dart` — Reset notify flags on complete/delete
- `lib/main.dart` — Maintenance check at app launch

## ✅ Test plan — ĐÃ VIẾT & PASS (93/93 tests)
1. ✅ Unit test validation form: pin range 0-100, end > start, ODO monotonic, endTime > startTime, cross-field validation → `test/unit/manual_trip_validation_test.dart` (20 tests)
2. ✅ Unit test thuật toán ETA sạc: no logs fallback, 1-2 logs linear, 3+ logs bucketed curve, target gần/xa, zero duration skip, custom rate → `test/unit/smart_charging_service_test.dart` (12 tests)
3. ✅ Unit test route prediction: 1 người, 2 người, đủ/không đủ pin, buffer 5%, no matching payload fallback, no trips default efficiency, zero distance → `test/unit/route_prediction_service_test.dart` (10 tests)
4. ✅ Unit test maintenance reminder dedupe: isDueSoon boundaries, isOverdue boundaries, remainingKm, completed tasks, dedupe key format, copyWith → `test/unit/maintenance_reminder_test.dart` (18 tests)
5. ✅ Widget test AddManualTripModal: renders form, ODO pre-fill, empty form validation, battery > 100 rejection, payload toggle → `test/widget/manual_trip_modal_test.dart` (6 tests)
6. ✅ Integration smoke: live/manual trip fields, charge target log, end-to-end trip→ETA→prediction, maintenance ODO flow, enum round-trip, BatteryLogic SoH calculations → `test/integration/smoke_test.dart` (19 tests)

### Test files
- `test/unit/manual_trip_validation_test.dart` — 20 tests
- `test/unit/smart_charging_service_test.dart` — 12 tests
- `test/unit/route_prediction_service_test.dart` — 10 tests
- `test/unit/maintenance_reminder_test.dart` — 18 tests
- `test/widget/manual_trip_modal_test.dart` — 6 tests
- `test/integration/smoke_test.dart` — 19 tests

## Assumptions & defaults
- Giữ `Firestore trực tiếp` là nguồn dữ liệu chính cho mobile; Python backend vẫn là AI service phụ trợ.
- Chưa tích hợp Google Maps thật trong đợt này; route feature dùng mock distance có thể thay provider sau.
- Chưa bật Firebase Auth ở đợt này, nên security hardening bằng rules chi tiết sẽ để phase kế tiếp cùng Auth.
- Local notifications là kênh nhắc chính; chưa triển khai FCM push trong đợt này.

---

# Tính Năng "Dung Lượng Pin AI" + Tự Động Thu Thập Thông Số VinFast

## ✅ TRẠNG THÁI: ĐÃ HOÀN THÀNH

---

### ✅ Subsystem 1 — VinFast Spec Catalog (Firestore → cache → local fallback)
**Đã triển khai:**
- `VinFastModelSpec` model (lib/data/models/vinfast_model_spec.dart): catalog data với aliases matching
- `assets/vinfast_specs_fallback.json`: 7 models VinFast (Feliz, Klara S, Opes, Vento, Theon, Ludo, Tempest)
- `VehicleSpecRepository` (lib/data/repositories/vehicle_spec_repository.dart): Firestore → SharedPreferences cache (24h TTL) → local asset fallback, auto-seed Firestore

### ✅ Subsystem 2 — Vehicle ↔ Model Mapping
**Đã triển khai:**
- `VehicleModel` updated: thêm `vinfastModelId`, `vinfastModelName`, `specVersion`, `specLinkedAt` + `hasModelLink` getter
- `VehicleModelLinkService` (lib/data/services/vehicle_model_link_service.dart): linkModel, unlinkModel, autoMatch, autoMatchAndLink
- Auto-match khi app launch (main.dart) cho selected vehicle

### ✅ Subsystem 3 — AI Capacity Engine (Hybrid SoH)
**Đã triển khai:**
- `BatteryCapacityService` (lib/data/services/battery_capacity_service.dart):
  - `CapacityResult`: nominalCapacityWh/Ah, sohPercent, usableCapacityWh/Ah, observedChargePowerW, confidence, alertLevel
  - `CapacityConfidence`: high (AI + đủ dữ liệu), medium (local + đủ dữ liệu), low (ít dữ liệu)
  - `SoHAlertLevel.fromSoH()`: none(≥80), mild(≥70), moderate(≥60), severe(<60)
  - Hybrid calculate: AI API → fallback local BatteryLogicService
  - Observed charge power: duration-weighted average, clamped by maxChargePower * 1.2

### ✅ Subsystem 4 — UI/UX
**Đã triển khai:**
- **Dashboard AI Capacity Card** (lib/features/dashboard/ai_capacity_card.dart):
  - Hiện: usable Wh/Ah, SoH%, alert banner, confidence badge, observed charge power, AI/On-device source
  - CTA card khi chưa link model
- **Statistics Capacity Detail Panel** (_AiCapacityDetailPanel trong statistics_screen.dart):
  - So sánh nominal vs usable (Wh, Ah), SoH progress bar, observed charge power bar, confidence badge, source indicator
- **Settings Model Link** (settings_screen.dart):
  - Vehicle card hiện linked model badge
  - Add Vehicle dialog: dropdown chọn VinFast model (tùy chọn)
  - Link model khi thêm xe mới

### Files đã tạo mới
- `lib/data/models/vinfast_model_spec.dart`
- `assets/vinfast_specs_fallback.json`
- `lib/data/repositories/vehicle_spec_repository.dart`
- `lib/data/services/vehicle_model_link_service.dart`
- `lib/data/services/battery_capacity_service.dart`
- `lib/features/dashboard/ai_capacity_card.dart`
- `test/unit/battery_capacity_test.dart` — 22 tests

### Files đã chỉnh sửa
- `lib/data/models/vehicle_model.dart` — Thêm 4 fields + hasModelLink getter
- `lib/features/dashboard/dashboard_screen.dart` — Thêm AI Capacity Card
- `lib/features/statistics/statistics_screen.dart` — Thêm _AiCapacityDetailPanel
- `lib/features/settings/settings_screen.dart` — Model link badge + dropdown chọn model
- `lib/main.dart` — Auto-sync specs + auto-match vehicle
- `pubspec.yaml` — Thêm vinfast_specs_fallback.json asset

### ✅ Tests — 22/22 PASS
- Alias matching (7 tests): exact, case-insensitive, alias substring, partial alias, unrelated, empty, different case
- Serialization (2 tests): roundtrip, missing fields
- SoH thresholds (4 tests): none/mild/moderate/severe boundaries
- Confidence labels (3 tests): high/medium/low
- Capacity formulas (3 tests): usable = nominal × SoH/100, 100% SoH, 50% SoH
- hasModelLink (3 tests): null, empty, non-empty

---

# Hoàn Thiện UI/UX + AI Function Center (Dashboard/Home/Stats)

## ✅ TRẠNG THÁI: ĐÃ HOÀN THÀNH

---

### ✅ 1. Fix Loading Dashboard / Bảo dưỡng
**Đã triển khai:**
- Trích inline `FutureProvider` trong `build()` ra top-level family providers:
  - `dashboardTripsProvider(vehicleId)` — trips gần nhất cho SoH card
  - `dashboardMaintenanceProvider(vehicleId)` — pending maintenance tasks
- Fix `onRetry` maintenance: invalidate đúng provider (trước đó invalidate nhầm vehicleProvider)
- RefreshIndicator invalidate cả 3 providers: vehicleProvider, dashboardTripsProvider, dashboardMaintenanceProvider

### ✅ 2. Fix tràn chữ Home / Thống kê
**Đã triển khai:**
- `StatCard`: thêm `FittedBox(fit: BoxFit.scaleDown)` cho value text, `maxLines: 1` + `TextOverflow.ellipsis` cho title/subtitle
- Home grid + Statistics grid: `LayoutBuilder` responsive ratio (`>340px → normal, else compressed`)

### ✅ 3. Tap xe xem chi tiết (VehicleDetailSheet)
**Đã triển khai:**
- `VehicleDetailSheet` (lib/core/widgets/vehicle_detail_sheet.dart): ConsumerStatefulWidget với capacity loading
- Hiển thị: avatar + tên + model badge, 4 stat tiles (pin, ODO, tổng sạc, tổng chuyến), capacity section (SoH bar + usable Wh + charge power), nút "Chọn xe này"
- Static `show()` method cho dễ gọi
- Wired vào Settings: long press `_VehicleCard` → mở VehicleDetailSheet

### ✅ 4. Hướng dẫn sử dụng (GuideScreen)
**Đã triển khai:**
- `GuideScreen` (lib/features/settings/guide_screen.dart): 5 accordion sections
  1. Luồng sử dụng hàng ngày
  2. Tracking chuyến đi & sạc (live + manual)
  3. AI hoạt động như nào (Hybrid AI Engine, thời gian học)
  4. Confidence / SoH / Cảnh báo (thang đánh giá chi tiết)
  5. FAQ & xử lý lỗi thường gặp
- Custom `_GuideSection` widget: animated accordion với bold text rendering
- Truy cập từ: Settings ("Hướng dẫn sử dụng" tile) + FAB menu

### ✅ 5. AI Function Center (AiFunctionsScreen)
**Đã triển khai:**
- `AiFunctionsScreen` (lib/features/settings/ai_functions_screen.dart): danh sách 5 AI features
  1. Smart Charging ETA — cần ≥3 lần sạc
  2. Route Consumption — cần ≥3 chuyến đi
  3. AI Capacity / SoH — cần link model + đủ dữ liệu
  4. Degradation Prediction — cần AI API online + ≥3 sạc
  5. Pattern Analysis — cần AI API online + ≥3 sạc
- Status badges: Đang hoạt động / Đang học / Cần thêm dữ liệu / Cần link model / API offline
- API status banner: kiểm tra AI Flask API realtime
- Data summary row: hiện số lần sạc, số chuyến, trạng thái link model
- Truy cập từ: Settings ("AI Function Center" tile) + FAB menu

### ✅ 6. FAB "+" + BottomSheet Menu
**Đã triển khai:**
- `QuickActionFab` + `_QuickActionSheet` (lib/core/widgets/quick_action_menu.dart):
  - 7 menu items: Bắt đầu đi, Bắt đầu sạc, Nhập chuyến đi thủ công, Nhập sạc, Dự báo lộ trình, AI Function Center, Hướng dẫn sử dụng
  - Phân nhóm: Primary actions → Manual input → AI features
  - Animated fade-in cho từng menu item
- Wired vào Dashboard: FAB mở menu, xử lý tất cả 7 actions
- Wired vào Home: FAB mở menu, xử lý: Nhập sạc, AI Functions, Guide

### Files đã tạo mới
- `lib/core/widgets/vehicle_detail_sheet.dart` — Bottom sheet chi tiết xe
- `lib/core/widgets/quick_action_menu.dart` — FAB + BottomSheet menu
- `lib/features/settings/guide_screen.dart` — Hướng dẫn sử dụng accordion
- `lib/features/settings/ai_functions_screen.dart` — AI Function Center

### Files đã chỉnh sửa
- `lib/core/widgets/stat_card.dart` — FittedBox + maxLines + ellipsis
- `lib/features/dashboard/dashboard_screen.dart` — Stable providers, FAB, _handleQuickAction
- `lib/features/home/home_screen.dart` — LayoutBuilder grid, QuickActionFab thay FAB cũ
- `lib/features/statistics/statistics_screen.dart` — LayoutBuilder responsive grid
- `lib/features/settings/settings_screen.dart` — VehicleDetailSheet on long press, Guide + AI Functions links
