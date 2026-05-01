# Plan Fix Đăng Nhập, Home, AI Charging, CSV Và Nhắc Rút Sạc

## Summary
Sửa 4 lỗi đang thấy trên app: giữ session đăng nhập sau khi thoát/update/mở lại, lỗi Home `type 'double' is not a subtype of type 'int'`, tab AI hiển thị sai trạng thái model `charging_time`, bổ sung lưu/gửi/chia sẻ CSV, và sửa lỗi đặt nhắc rút sạc do timezone/local notification chưa khởi tạo.

## Key Changes
- **Giữ đăng nhập sau khi mở lại app**
  - Dùng Firebase Auth persistence làm source of truth, không tự logout khi app cold start, kill đa nhiệm, hoặc update.
  - Sửa `AuthGate` thành bootstrap có trạng thái rõ: chờ `Firebase.initializeApp()` và `FirebaseAuth.authStateChanges()` restore xong mới render `LoginScreen` hoặc `AppNavigation`.
  - `SessionService` lưu marker `was_authenticated` và `explicit_signed_out`; chỉ `AuthService.signOut()` mới set explicit sign out và clear session metadata.
  - Nếu Firebase init/auth restore lỗi, hiển thị màn lỗi/retry thay vì đưa user về Login.
  - Khi login/register thành công, ghi lại `lastLoginEmail`, `was_authenticated=true`, `explicit_signed_out=false`.

- **Fix Home hiển thị lỗi double/int**
  - Sửa `VehicleModel.fromFirestore()` parse số an toàn bằng helper `_asInt()` và `_asDouble()`.
  - Các field cần đổi: `currentOdo`, `currentBattery`, `lastBatteryPercent`, `totalCharges`, `totalTrips`, `stateOfHealth`, `defaultEfficiency`, `specVersion`.
  - Chuẩn hóa `AuthService.addVehicle()` ghi field số dạng phù hợp: các giá trị phần trăm/ODO hiển thị int thì lưu `round()`, còn `batteryCapacity`, `defaultEfficiency`, `stateOfHealth` có thể giữ double.
  - Sau khi fix, `allVehiclesProvider` và `vehicleProvider` không còn throw, Home không hiện 2 banner lỗi đỏ.

- **Fix AI model status và CSV**
  - Sửa backend `/api/user/ai/models`: parse đúng response AI server `/v1/types`, lấy status từ `data.types[*].runtimeStatus`.
  - Trả về cho app các field ổn định: `runtimeStatus`, `activeVersion`, `isLoaded`, `isPredictable`, `featureCount`, `lastLoadAt`, `runMode`.
  - Sửa `AiModelsScreen` để model có `runtimeStatus.loaded` hoặc `isLoaded/isPredictable=true` hiển thị `ĐÃ LOAD`, không còn `CHƯA LOAD`.
  - Với model `.keras` server-only, vẫn coi là usable nếu server predict được; app không yêu cầu tải local.
  - Bổ sung `share_plus` để chia sẻ file CSV qua Android share sheet.
  - `ChargingFeedbackService` thêm hàm `shareCsv()` trả/share file `charging_feedback.csv`.
  - Nút `GỬI & LƯU CSV` sẽ lưu local trước, gọi `/api/ai/charge-feedback` sau; nếu API lỗi vẫn giữ CSV local và báo rõ “Đã lưu local, gửi server thất bại”.
  - Thêm nút hoặc action `Chia sẻ CSV` sau khi có dữ liệu feedback.

- **Fix đặt nhắc nhở rút sạc**
  - Sửa `NotificationService.initialize()` để khởi tạo timezone trước khi schedule:
    `tz.initializeTimeZones()` và set local `Asia/Ho_Chi_Minh`.
  - Đảm bảo `_setReminder()` luôn gọi `await NotificationService().initialize()` trước `scheduleChargeReminder()`.
  - Xin quyền notification trước khi schedule trên Android 13+.
  - Với Android 12+, dùng exact alarm nếu được phép; nếu không, fallback sang `inexactAllowWhileIdle` để không crash.
  - Validate thời gian nhắc: nếu thời điểm đã qua hoặc `_predictedMinutes <= 0`, không schedule và hiện thông báo hợp lệ.

## Public API / Dependencies
- Thêm dependency app: `share_plus`.
- Backend `/api/user/ai/models` giữ route cũ, bổ sung/chuẩn hóa fields:
  - `runtimeStatus`: `"loaded" | "not_loaded" | "error"`.
  - `isLoaded`: bool.
  - `isPredictable`: bool.
  - `activeVersion`: string/null.
  - `runMode`: `"server_only" | "on_device" | "none"`.
- App tiếp tục dùng `/api/ai/predict-charging-time` và `/api/ai/charge-feedback`.

## Test Plan
- **Session**
  - Login thành công, kill app khỏi đa nhiệm, mở lại: vẫn vào Home.
  - Login thành công, cài APK update cùng package id, mở lại: vẫn logged in.
  - Bấm Đăng xuất, kill/mở lại: về Login.
- **Home**
  - Tạo xe mới có `currentOdo: 0.0`, `lastBatteryPercent: 100.0`: Home load không lỗi.
  - Pull refresh Home: không hiện `Không tải được danh sách xe` hoặc `Không tải được thông tin xe`.
- **AI**
  - Backend trả `charging_time` active/loaded: app hiển thị `ĐÃ LOAD`.
  - Tap model, bấm `DỰ ĐOÁN VỚI AI`: nhận kết quả thời gian và giờ hoàn thành.
  - Bấm `GỬI & LƯU CSV`: file local được tạo, feedback server gửi được hoặc lỗi server không làm mất CSV.
  - Bấm chia sẻ CSV: Android share sheet mở và file đính kèm được.
- **Reminder**
  - Bấm `Đặt nhắc nhở rút sạc`: không còn `LateInitializationError`.
  - Từ chối quyền notification: app báo cần quyền, không crash.
  - Cho quyền notification: schedule thành công và snackbar “Đã đặt nhắc nhở...” hiển thị.
- Chạy `flutter analyze`, unit/widget tests hiện có, và build APK release.

## Assumptions
- Không lưu mật khẩu người dùng local; giữ đăng nhập bằng Firebase Auth token persistence.
- Model `charging_time` hiện chạy server-side, nên status `ĐÃ LOAD` dựa trên runtime server, không dựa trên local model file.
- CSV cần chia sẻ qua share sheet hệ thống Android là đủ cho “gửi và chia sẻ”.
