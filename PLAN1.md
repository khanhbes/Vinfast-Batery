# Plan Tích Hợp Charging ETA Beta Từ AI Center Vào App

## Summary
- App sẽ dùng cùng mô hình `charging_time` đang active trên web AI Center, không đóng gói model mới vào mobile ở v1.
- Khi bấm `Sạc`, app mở flow `Smart Charging ETA (Beta)`: hỏi `% pin hiện tại` và `% muốn dừng`, tự suy luận phần còn lại, dự đoán thời gian sạc còn lại và hiển thị `Rút lúc HH:mm`.
- Khi bấm `Dừng`, app bắt buộc hỏi `% pin hiện tại thực tế`; giá trị này sẽ override số mô phỏng để lưu dữ liệu chuẩn hơn cho fine-tune sau này.
- App sẽ thu thập dữ liệu sạc ngầm qua `ChargeLogs` + `ChargeSamples`, còn web sẽ là nơi upload/activate model, theo dõi độ chính xác, export dataset và fine-tune vòng sau.
- Quyết định đã khóa: `web model + fallback local` và `1 thông báo đúng giờ rút`.

## Key Changes
### 1. Shared backend contract giữa web và app
- Nâng cấp `POST /api/ai/predict-charging-time` thành endpoint public dùng chung cho web/app:
  request nhận `{ vehicleId, currentBattery, targetBattery, ambientTempC? }`.
- Luồng xử lý của endpoint:
  ưu tiên gọi active model `charging_time` từ AI Center; nếu model chưa sẵn sàng, lỗi mạng AI server, hoặc output bất thường thì fallback sang heuristic hiện có.
- Chuẩn hóa output công khai về **giây** để chặn lỗi đơn vị:
  response luôn trả `predictedDurationSec`, `predictedDurationMin`, `formattedDuration`, `modelSource`, `modelVersion`, `isBeta`, `confidence`, `warnings`.
- Thêm guardrail chống số vô lý:
  nếu AI trả `NaN`, `<= 0`, `< 5 phút`, `> 12 giờ`, hoặc lệch quá mạnh so với heuristic cùng input thì tự rơi về fallback và gắn `modelSource = heuristic_guardrail`.
- Giữ tương thích ngược cho web cũ bằng cách vẫn trả các field hiện có như `estimatedMinutes`, `formattedTime`, `chargingCurve`.

### 2. App flow trên Dashboard
- Giữ Dashboard là entry chính vì hiện đã có `Bắt đầu sạc` và banner `Đang sạc`.
- `Bắt đầu sạc` mở bottom sheet `Smart Charging ETA (Beta)` với:
  `pin hiện tại` prefill từ xe nhưng cho sửa tay, `pin muốn dừng`, toggle `Nhắc tôi khi nên rút sạc` mặc định bật.
- App gọi endpoint dự đoán trước khi bắt đầu phiên sạc; sheet hiển thị:
  `Thời gian dự kiến`, `Rút lúc HH:mm`, badge `Beta`, nguồn dự đoán `AI / history / heuristic`.
- Khi user xác nhận bắt đầu:
  app lưu metadata dự đoán vào session, schedule 1 local notification đúng giờ rút, rồi mới start `ChargeTrackingService`.
- Banner `Đang sạc` trên Dashboard đổi sang bản có:
  `AI Beta`, `Rút lúc`, `Còn lại`, `Mục tiêu`, `model source/version`, và không hiển thị số phút thô.
- `ChargeTrackingService` không còn lấy ETA chính từ average rate cũ; thay vào đó tính `chargeRatePerMin` từ `predictedDurationSec` để ETA, progress, notification và giờ rút đồng bộ với nhau.
- Khi bấm `Dừng`, modal sẽ hỏi thêm `% pin hiện tại thực tế`; app dùng số này để lưu log cuối cùng, hủy reminder, tính sai số giữa `predicted` và `actual`.

### 3. Notifications và recovery
- Mở rộng `NotificationService` với scheduled one-shot reminder theo `sessionId`; dùng `flutter_local_notifications` + `timezone`.
- Không tạo thông báo trùng:
  reminder đúng giờ rút và notify đạt target dùng cùng session state; khi stop hoặc target đã đạt thì hủy lịch còn lại.
- Recovery sau app restart phải khôi phục đủ:
  session sạc, `predictedStopAt`, `formattedDuration`, trạng thái reminder, và Beta metadata.

### 4. Dữ liệu sạc để fine-tune
- Mở rộng `ChargeLogs` với block `aiPrediction`:
  `requestedAt`, `startBatteryPercent`, `targetBatteryPercent`, `predictedDurationSec`, `predictedStopAt`, `modelSource`, `modelVersion`, `isBeta`, `actualStopBatteryPercent`, `actualDurationSec`, `predictionErrorSec`, `eligibleForTraining`.
- Mở rộng `ChargeSamples` với metadata hữu ích cho training:
  `startBatteryPercent`, `targetBatteryPercent`, `predictedStopAt`, `modelVersion`, `modelSource`, `ambientTempC`, `sessionId`, `ownerUid`, và nếu đã có quyền/location sẵn thì lấy `latitude`,`longitude`; không xin prompt mới chỉ để training.
- Sửa `firestore.rules` để app được `create/read` owner-only cho `ChargeSamples`; hiện tại flow thu thập ngầm dễ bị chặn.
- Quy tắc dữ liệu đủ chuẩn để fine-tune:
  chỉ dùng session `app_live_charge`, có user xác nhận pin lúc dừng, thời lượng > 0, pin tăng hợp lệ, không phải manual log; log không đạt chuẩn vẫn lưu nhưng `eligibleForTraining = false`.
- Web sẽ có bước normalize/export về đúng schema CSV kiểu `charging_900.csv`:
  `charge_id,start_timestamp_utc,end_timestamp_utc,start_soc,end_soc,delta_soc,duration_sec,latitude,longitude,ambient_temp_c`.

### 5. Đồng bộ hiển thị giữa web và app
- App:
  Dashboard là nơi thao tác chính; `AI Function Center` đổi card thành `Smart Charging ETA Beta`, nêu rõ “đang học từ dữ liệu sạc của bạn”.
- Web:
  AI Center vẫn là nơi upload/activate/test model; thêm phần theo dõi `charging_time beta` gồm số session hợp lệ, MAE/MAPE, biểu đồ predicted-vs-actual, version đang active.
- Hai bên dùng cùng `modelVersion` và `modelSource`; app không tự định nghĩa version riêng.

## Public Interfaces / Types
- `POST /api/ai/predict-charging-time`
  - Request: `{ vehicleId, currentBattery, targetBattery, ambientTempC? }`
  - Response: `{ predictedDurationSec, predictedDurationMin, formattedDuration, modelSource, modelVersion, isBeta, confidence, warnings, estimatedMinutes, formattedTime }`
- `ChargeTrackingService.startCharging(...)`
  - thêm `startBatteryPercent`, `predictedDurationSec`, `predictedStopAt`, `modelSource`, `modelVersion`, `reminderEnabled`
- `ChargeTrackingService.stopCharging(...)`
  - đổi sang nhận `actualBatteryPercent`
- `ChargeLogModel`
  - thêm `aiPrediction` metadata và actual-vs-predicted fields
- Flutter dependency
  - thêm `timezone` để schedule local reminder ổn định

## Test Plan
- Backend:
  - AI model path hoạt động với active version từ AI Center.
  - Output luôn chuẩn hóa sang `predictedDurationSec`; case unit lỗi lớn phải rơi về guardrail fallback.
  - Input lỗi `target <= current`, ngoài `0..100` trả lỗi rõ.
  - Khi AI model down/unloaded, endpoint vẫn trả fallback hợp lệ.
- App:
  - Start flow với ví dụ `7:00, 30% -> 80%` phải hiển thị `Rút lúc ...` theo prediction, có badge `Beta`, không crash nếu backend lỗi.
  - Reminder được tạo đúng giờ, hủy đúng khi stop, recovery sau restart không mất ETA.
  - Stop flow bắt nhập `% pin hiện tại`, lưu đúng actual battery, tính đúng actual duration và prediction error.
  - Banner đang sạc, charge log, AI Function Center hiển thị đồng bộ model source/beta.
- Sync / training:
  - `ChargeSamples` ghi được thật dưới Firestore rules mới.
  - Dataset export từ web sinh đúng cột CSV và loại bỏ session không đủ chuẩn.
- Build:
  - `flutter analyze` tối thiểu trên các file chạm tới và `flutter build apk`.
  - Web backend check cho route mới và AI Center dataset/evaluation view.

## Assumptions
- V1 không chạy model `charging_time` on-device; app dùng backend active model của web và fallback local khi cần.
- App vẫn hỏi `% pin hiện tại` dù xe đã có sẵn giá trị; field này sẽ prefill từ `vehicle.currentBattery` để user sửa nhanh.
- Nhiệt độ không hỏi user trong app v1; ưu tiên dữ liệu gần nhất nếu có, không có thì dùng default an toàn `25°C`.
- Nhắc rút sạc là **1 thông báo đúng giờ rút**, không thêm cảnh báo sớm ở v1.
- Manual charge logs không dùng để fine-tune model ETA trừ khi sau này có cờ xác nhận dữ liệu chuẩn.
