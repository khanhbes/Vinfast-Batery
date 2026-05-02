# Plan Fix Triệt Để Alarms, Service Và AI Model

## Summary
Sửa theo hướng “không phụ thuộc trạng thái may rủi”: reminder vẫn hoạt động dù Android không cho exact alarm, lịch bảo dưỡng không vỡ vì thiếu index, và AI model dùng một contract server duy nhất có cache + tự phục hồi khi app/server lệch trạng thái.

## Key Changes
- **Alarms & Reminders**
  - Thêm vào `AndroidManifest.xml`: `SCHEDULE_EXACT_ALARM`, các receiver của `flutter_local_notifications` cho scheduled notification và boot restore.
  - Không dùng `USE_EXACT_ALARM` vì app không phải clock/calendar app và có thể vướng policy phát hành.
  - Trong `NotificationService`, thêm flow:
    - init timezone `Asia/Ho_Chi_Minh`;
    - request `POST_NOTIFICATIONS`;
    - check `canScheduleExactNotifications()`;
    - nếu chưa có exact alarm thì gọi `requestExactAlarmsPermission()`;
    - nếu Android vẫn không cho bật hoặc switch bị mờ, schedule bằng `AndroidScheduleMode.inexactAllowWhileIdle`.
  - UI nhắc sạc/bảo dưỡng không báo lỗi nữa: hiển thị rõ “Nhắc gần đúng” khi dùng inexact fallback.
  - Kết quả mong muốn: người dùng không bị kẹt ở màn setting bị mờ; app vẫn đặt được reminder an toàn.

- **Lịch Bảo Dưỡng / Service**
  - Sửa `web/firebase.json` để deploy cả index:  
    `firestore.indexes.json`.
  - Thêm composite index cho query hiện tại:
    `MaintenanceTasks(ownerUid ASC, vehicleId ASC, isDeleted ASC, targetOdo ASC)`.
  - Sửa `MaintenanceRepository.watchMaintenanceTasks()`:
    - query chính vẫn dùng `orderBy(targetOdo)`;
    - nếu gặp `failed-precondition/requires index`, fallback query không `orderBy`, sort `targetOdo` ở client;
    - không để màn Service rơi vào error toàn trang vì index đang build.
  - Sửa `MaintenanceTaskModel.fromFirestore()` parse số/ngày an toàn:
    `targetOdo` nhận được `int`, `double`, `num`, string đều không crash.
  - Sau khi thêm/sửa/xóa/complete task, reset notification flag liên quan để nhắc bảo dưỡng không bị stale.

- **AI Model Deploy Trên Server Và App**
  - Đổi `ApiService.getUserAiModels()` dùng endpoint canonical `/api/user/ai/models`, không dùng `/api/user/ai/models/deployed` cho UI status.
  - Chuẩn hóa backend `/api/user/ai/models` trả một schema duy nhất:
    `runtimeStatus`, `isLoaded`, `isPredictable`, `activeVersion`, `runMode`, `featureCount`, `lastLoadAt`, `lastError`.
  - Backend tự phục hồi status:
    - đọc active model từ manifest disk;
    - nếu có active version nhưng runtime chưa loaded, gọi `load-active`;
    - chạy smoke predict nhẹ trước khi báo `loaded`;
    - chỉ báo “không có model” khi không có active artifact thật sự.
  - Deploy từ dashboard chỉ thành công khi:
    upload tồn tại, activate thành công, runtime load thành công, smoke predict thành công, và `AiModelDeployments` đã lưu `deploymentStatus=deployed`.
  - App thêm cache model catalog trong `SharedPreferences`:
    - khi refresh thất bại, giữ trạng thái loaded gần nhất thay vì nhảy về “CHƯA CÓ MODEL”;
    - khi predict thành công, update cache model đó thành loaded;
    - có retry/backoff khi server chập chờn.
  - Với `.keras` server-only model, app vẫn hiển thị `ĐÃ LOAD` nếu server predict được; không yêu cầu tải model local.

## Test Plan
- **Alarms**
  - Cài APK mới, vào đặt nhắc sạc: nếu exact permission bật được thì schedule exact; nếu switch bị mờ/từ chối thì vẫn schedule inexact và không crash.
  - Kill app, reboot máy, kiểm tra scheduled notification còn được restore.
- **Service**
  - Trước khi index deploy xong: màn Service vẫn tải bằng fallback client sort.
  - Sau deploy index: stream realtime hoạt động, thêm/sửa/complete/xóa mốc không lỗi.
- **AI**
  - Deploy `charging_time` trên dashboard: app refresh thấy `ĐÃ LOAD`.
  - Restart server/app: model vẫn hiện loaded nếu manifest active còn tồn tại.
  - Tắt AI server tạm thời: app giữ cache trạng thái cuối và hiển thị “đang kiểm tra”, không nhảy về “CHƯA CÓ MODEL”.
  - Bấm dự đoán: nếu model chạy được trả AI result; nếu server lỗi thì fallback heuristic có cảnh báo rõ.
- Chạy `flutter analyze`, `flutter test`, `npm run build` cho dashboard nếu đụng frontend, và deploy `firestore:rules,firestore:indexes`.

## Assumptions & References
- Không thể ép Android bật exact alarm nếu hệ điều hành/OEM không cho; app sẽ dùng inexact fallback để “fix hoàn toàn” trải nghiệm.
- Theo Android docs, `SCHEDULE_EXACT_ALARM` cần được kiểm tra/xin quyền trước khi dùng exact alarm; Android 14 có thể từ chối mặc định: https://developer.android.com/about/versions/14/changes/schedule-exact-alarms
- `flutter_local_notifications` yêu cầu khai báo permission/receivers cho scheduled notifications và có `requestExactAlarmsPermission()`: https://pub.dev/packages/flutter_local_notifications
