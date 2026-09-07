# Kế hoạch Master QA/UIUX Audit cho VinFast Battery App

## Tóm tắt

Audit toàn bộ Flutter app theo `VINFAST_BATTERY_APP_MASTER_QA_UIUX_AUDIT.md`, lấy trạng thái working tree hiện tại làm mốc. Kiểm thử bằng Firebase Emulator, API/Shelly mock và một điện thoại Android thật; không tác động Firebase production hoặc relay thật.

Đợt này chỉ thực hiện audit, thu thập bằng chứng, bổ sung regression test và đề xuất sửa lỗi. Không sửa production code.

## 1. Chuẩn bị và đóng băng phiên bản audit

- Tạo nhánh `qa/app-master-audit-2026-09-07`.
- Kiểm tra secret và file lớn trước khi tạo snapshot; không commit credential, dataset runtime, model binary, APK hoặc log.
- Commit snapshot source/config/docs hiện tại và ghi lại:
  - commit SHA, branch, dirty state;
  - Flutter/Dart/Android SDK;
  - thiết bị và emulator;
  - URL/config test đã được che secret.
- Xử lý Flutter CLI đang treo bằng cách xác định và dừng riêng tiến trình Flutter/Dart mồ côi, không ảnh hưởng IDE đang chạy.
- Dùng Android Studio JBR cho Java; gọi `firebase.cmd` để tránh PowerShell execution-policy.
- Tạo `app/QA_ARCHITECTURE_INVENTORY.md` và traceability matrix ánh xạ đủ 59 mục audit cùng 25 giả thuyết `APP-H1…APP-UX-H25`.

## 2. Hạ tầng kiểm thử cô lập

- Bổ sung test harness, không thay đổi hành vi production:
  - `integration_test` cho luồng chạy trên emulator/điện thoại;
  - Firebase Auth/Firestore Emulator;
  - hai user giả lập A/B cùng dữ liệu Vehicle, Charge, Trip, Notification tương ứng;
  - fixture Firestore malformed;
  - fake API/Shelly gateway có state machine và fault injection;
  - golden tests bằng công cụ Flutter chuẩn.
- Mock gateway phải mô phỏng:
  - offline, timeout, HTTP 500/503;
  - stale telemetry và readback mismatch;
  - Cloud fail → LAN fallback;
  - duplicate/out-of-order response;
  - restart, safety cutoff và manual OFF;
  - AI unavailable, malformed response và fallback.
- Emulator Android:
  - API 31/Android 12;
  - API 33/Android 13;
  - API 34/Android 14;
  - API 35/Android 15.
- Viewport: `320×568`, `360×640`, `375×812`, `412×915`, tablet portrait/landscape.
- Điện thoại thật dùng cho GPS, notification, background service, Doze, battery saver, TalkBack, keyboard và lifecycle restart.
- Không gửi lệnh tới Shelly thật; kiểm tra phần cứng thật không khả dụng được ghi `BLOCKED`.

## 3. Các vòng kiểm thử

### Baseline và kiến trúc

- Chạy `flutter pub get`, `flutter analyze`, toàn bộ `flutter test`, debug APK và release APK nếu không cần production signing key.
- Inventory entrypoint, Riverpod providers, navigation, Firebase collections, API, storage, background services, GPS, notifications, AI, update và Smart Charger.
- Lập state machine cho Auth, Charge, Trip, Sync và relay.
- Ghi riêng các test hiện có; không coi `app/test/integration/smoke_test.dart` là device integration test vì hiện chỉ là logic test.

### Logic, dữ liệu và bảo mật

- Test boundary/property cho SOC, SoH, capacity, voltage, power, range, duration và mọi giá trị NaN/Infinity/âm/vượt giới hạn.
- Kiểm tra parser với missing field, null, sai kiểu, timestamp/enum lỗi và document bị xóa.
- Kiểm tra User A không thể đọc/ghi dữ liệu User B bằng Firebase Rules Emulator.
- Xác minh UID luôn lấy từ Firebase Auth, không tin `ownerUid` do client tự cung cấp.
- Audit SharedPreferences, secure storage, log redaction, token, Shelly credential, Android component, deep link và network-security config.
- Kiểm tra riêng cấu hình cleartext và tham chiếu VPS cũ trong Android network security.
- Không đưa secret hoặc dữ liệu người dùng vào report/evidence.

### State machine và concurrency

- Charge: double start/stop, rapid tap, retry, write fail, restart và idempotent session ID.
- Trip: duplicate start, GPS outlier, out-of-order points, app kill/restart và recovery.
- Sync: offline queue, reconnect, duplicate write và stale response.
- Race condition: đổi xe khi AI request đang chạy, logout khi request pending, refresh/navigation đồng thời.
- Update flow: semantic version, metadata lỗi, download gián đoạn, checksum/trust và APK cache cũ.

### Smart Charger và AI

- Xác minh đầy đủ các trạng thái `OFF`, `TURNING ON`, `ON`, `TURNING OFF`, `OFFLINE`, `ERROR`, `READBACK MISMATCH`, `SAFETY STOP`.
- Không công nhận ON trước readback; manual OFF luôn khả dụng và có ưu tiên cao nhất.
- Kiểm tra Cloud/LAN fallback không phát sinh double command và restart không auto-ON.
- AI phải đảm bảo output hữu hạn, đúng giới hạn, có confidence, source, model version, timestamp và đánh dấu fallback.
- Kiểm tra Personal AI, range prediction và charging ETA với API timeout, model lỗi, response malformed và response cũ đến sau response mới.

### UI/UX và accessibility

- Tạo state matrix cho từng màn: initial, loading, success, empty, error, offline, stale, partial, permission denied và unauthorized.
- Kiểm tra toàn bộ màn bắt buộc trong audit ở:
  - light/dark;
  - Vietnamese/English;
  - text scale `1.0`, `1.15`, `1.3`, `1.5`, `2.0`;
  - phone portrait/landscape và tablet.
- Kiểm tra overflow, keyboard che CTA, touch target tối thiểu 44–48dp, back navigation, modal, scroll/focus restoration và duplicate route.
- Dùng TalkBack kiểm tra battery gauge, charger controls, biểu đồ, offline/error state và traversal order.
- Kiểm tra reduced motion và đảm bảo animation không mô phỏng trạng thái thành công trước dữ liệu thật.

### Visual regression và hiệu năng

- Golden baseline cho Login, Home, Dashboard, Battery Monitor, Charge Log, Smart Charging, AI Predictor, Statistics và Settings.
- Mỗi màn core có baseline bao phủ loaded/empty/error, light/dark và VI/EN; functional test vẫn là nguồn xác nhận hành vi.
- Profile trên điện thoại thật:
  - cold/warm start;
  - Home/Dashboard;
  - chart/map;
  - AI request;
  - polling Smart Charger;
  - 20–50 vòng navigation.
- Ghi slow frame, rebuild storm, memory growth và resource không được dispose.
- Báo performance defect nếu p95 frame vượt 32 ms hoặc slow-frame rate vượt 5% trong kịch bản core; bộ nhớ phải ổn định trong 10 vòng cuối của bài navigation lặp.

## 4. Báo cáo và release gate

Tạo:

- `app/QA_AUDIT_REPORT.md`;
- `app/QA_ARCHITECTURE_INVENTORY.md`;
- `app/qa-evidence/screenshots`;
- `app/qa-evidence/videos`;
- `app/qa-evidence/logs`;
- `app/qa-evidence/golden-diffs`.

Mỗi mục checklist phải có `PASS`, `FAIL` hoặc `BLOCKED`, liên kết tới test/evidence. Mỗi lỗi dùng đúng mẫu `APP-BUG-XXX` hoặc `APP-UX-XXX`, có severity, reproduction, root cause, impact, regression test và fix proposal.

Kết luận chỉ được chọn một:

- `BLOCK RELEASE`;
- `RELEASE WITH CONDITIONS`;
- `READY FOR RELEASE`.

Không được đánh dấu ready nếu còn P0, P1 về auth/data/safety, duplicate session, auto-ON, manual OFF bị cản, core layout vỡ, TalkBack không dùng được, AI vi phạm invariant hoặc build/test nghiêm trọng thất bại.

## Giả định đã chốt

- Audit snapshot là working tree hiện tại, không phải chỉ commit `9b09091`.
- Firebase Emulator và Shelly mock là nguồn test chính.
- Có một điện thoại Android thật để kiểm tra phần cứng/background.
- Không dùng production Firebase, tài khoản thật hoặc relay thật.
- Không sửa production code trong audit; testability gap và lỗi được ghi thành fix proposal cho đợt tiếp theo.
- Kiểm tra phụ thuộc Shelly vật lý/OEM không thể mô phỏng đầy đủ sẽ được ghi `BLOCKED`, không được suy diễn thành PASS.
