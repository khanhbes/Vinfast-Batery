# IMPLEMENTATION PLAN — SMART CHARGE UX + DEBUG + WEB AI

## Mục tiêu

Sau khi hoàn thành:

- App hiển thị được lỗi đủ chi tiết để debug.
- Người dùng nhìn Smart Charge là hiểu ngay:
  - đang sạc hay không;
  - pin hiện tại;
  - pin muốn sạc tới;
  - còn bao lâu;
  - khi nào tự tắt.
- Người dùng được tự chọn % pin mục tiêu từ pin hiện tại đến 100%.
- Smart Charge dùng model `charging_time` đã deploy trên web làm nguồn AI chính.
- Không hiển thị các thuật ngữ kỹ thuật không cần thiết như `Relay`, `RPC`, `SOC`, `heuristic`, `modelVersion`, `Cloud/LAN`.
- Không thay đổi cơ chế an toàn hiện tại của Shelly.

---

## Phase 0 — Baseline và bảo vệ code hiện tại

Trước khi sửa:

```bash
git checkout feature/ai-target-charging-uiux
git pull
git checkout -b feature/smart-charge-user-debug-ai
```

Chạy baseline:

```bash
cd app

flutter pub get
flutter analyze
flutter test
```

Backend:

```bash
cd ../web
pytest
```

Gateway nếu có:

```bash
cd ../smart_charger_gateway
pytest
```

### Không được phá các chức năng hiện có

Giữ nguyên:

- Shelly device timer.
- Readback sau ON/OFF.
- Safe OFF.
- Cloud → LAN fallback.
- Poll status định kỳ.
- Idempotency khi start phiên.
- Safety stop 6 giờ.
- Calibration công suất.
- Recovery phiên sạc.
- Secure storage credentials.

---

## Phase 1 — Xây hệ thống Error Reporter dùng chung

### 1.1 Tạo model lỗi

Tạo:

```text
app/lib/core/services/app_error_reporter.dart
```

Model:

```dart
class AppErrorEntry {
  DateTime time;
  String source;
  String message;
  String stackTrace;

  String? endpoint;
  int? statusCode;
  String? debugCode;
}
```

Ví dụ một entry:

```text
Time:
2026-08-29 01:42:12

Source:
SmartChargePrediction

Endpoint:
/api/ai/predict-charging-time

HTTP:
503

Code:
AI_MODEL_UNAVAILABLE

Error:
Model charging_time unavailable

Stack:
...
```

---

## Phase 2 — Bắt toàn bộ lỗi cấp ứng dụng

Sửa:

```text
app/lib/main.dart
```

Nối:

```dart
FlutterError.onError
```

vào:

```dart
AppErrorReporter.report(...)
```

Tương tự:

```dart
PlatformDispatcher.instance.onError
```

và:

```dart
runZonedGuarded(...)
```

### Firebase

Thay:

```dart
catch (e) {
  debugPrint(...)
}
```

bằng:

```dart
catch (e, stack) {
  AppErrorReporter.report(
    e,
    stack,
    source: 'Firebase',
  );
}
```

Áp dụng cho:

- Firebase initialize.
- Notification initialize.
- Background service.
- Recovery.
- Smart Charging.
- Shelly.
- API.
- Firebase sync.

---

## Phase 3 — Error Detail UI

Tạo:

```text
app/lib/core/widgets/debug_error_sheet.dart
```

Khi lỗi xảy ra, người dùng chỉ thấy thông báo ngắn:

```text
⚠ Không thể tính thời gian sạc

[Xem chi tiết]
```

Không đập toàn bộ stack trace vào màn chính.

Khi bấm:

```text
Xem chi tiết
```

mở bottom sheet:

```text
Chi tiết lỗi

SmartChargePrediction
29/08/2026 01:42

HTTP 503
AI_MODEL_UNAVAILABLE

Model charging_time unavailable

Stack trace
────────────────
...

[Sao chép lỗi]
```

---

## Phase 4 — Bảo mật debug log

Đây là bắt buộc.

Trước khi lưu hoặc hiển thị lỗi phải redact:

```text
Authorization
Bearer token
Firebase token
Shelly auth key
Shelly password
Wi-Fi password
cookie
API key
refresh token
```

Ví dụ:

```text
Authorization: Bearer abc123
```

thành:

```text
Authorization: Bearer ***
```

Không để secret xuất hiện khi người dùng copy debug.

---

## Phase 5 — Nối Error Reporter vào ApiService

Sửa:

```text
app/lib/core/services/api_service.dart
```

Hiện tại API trả:

```dart
{
  'success': false,
  'error': ...
}
```

nhưng không có centralized debug.

Thêm:

```dart
AppErrorReporter.report(...)
```

cho:

```text
GET timeout
POST timeout
HTTP != 200
JSON parse error
SocketException
Firebase auth token error
unknown exception
```

### Ví dụ

```dart
final error = ApiException(
  endpoint: endpoint,
  statusCode: response.statusCode,
  responseBody: response.body,
);
```

Sau đó report:

```dart
AppErrorReporter.report(
  error,
  StackTrace.current,
  source: 'ApiService',
);
```

---

## Phase 6 — Chuẩn hóa trạng thái Smart Charge

Nguồn trạng thái phải là:

```dart
SmartChargerStatus.relay
```

không phải:

```dart
ChargeTrackingService.isCharging
```

Xây UI state:

```dart
enum ChargerDisplayState {
  connecting,
  charging,
  off,
  offline,
  error,
}
```

Mapping:

```text
loading
→ connecting

online + relay=true
→ charging

online + relay=false
→ off

!online
→ offline

exception
→ error
```

---

## Phase 7 — Đổi Smart Charge Status UI

Sửa:

```text
app/lib/features/ai/smart_charging_control_screen.dart
```

### Hiện tại

Không nên hiện:

```text
Shelly Plug S
LAN · Relay ON · 402 W
```

### Đổi thành

Khi bật:

```text
🟢 Đang sạc

Đang nhận điện
402 W
```

Khi tắt:

```text
⚪ Đã tắt sạc
```

Khi offline:

```text
🔴 Mất kết nối

Không tìm thấy ổ sạc
```

Khi đang reconnect:

```text
🟠 Đang kết nối...
```

---

## Phase 8 — Đơn giản hóa toàn bộ terminology

Thay:

```text
SOC
```

→

```text
Pin
```

Thay:

```text
SOC hiện tại
```

→

```text
Pin hiện tại
```

Thay:

```text
SOC mục tiêu
```

→

```text
Pin muốn sạc tới
```

Thay:

```text
ETA
```

→

```text
Còn khoảng
```

Thay:

```text
Relay ON
```

→

```text
Đang sạc
```

Thay:

```text
Relay OFF
```

→

```text
Đã tắt
```

Thay:

```text
AI Prediction
```

→

```text
Tính thời gian sạc
```

Thay:

```text
Sạc theo AI
```

→

```text
Bắt đầu sạc
```

---

## Phase 9 — Ẩn thông tin kỹ thuật khỏi màn người dùng

Không hiển thị ở Smart Charge chính:

```text
modelKey
modelVersion
predictionSource
confidence
runtimeHealth
Cloud
LAN
RPC
Relay
heuristic
fallback
analyzedAt
```

Những field này vẫn giữ trong data model.

Chúng chỉ dùng:

```text
Error Detail
Debug
Log
Developer mode
```

Không xóa khỏi backend.

---

## Phase 10 — Cho tự chọn pin mục tiêu

Hiện tại UI chỉ có:

```text
80%
90%
100%
```

Phải đổi sang:

```text
42%             87%               100%
────────────────●──────────────────
```

Slider:

```dart
Slider(
  value: targetSoc,
  min: currentSoc + 1,
  max: 100,
  divisions: ...,
)
```

Người dùng chọn được:

```text
61%
62%
63%
...
87%
...
99%
100%
```

---

## Phase 11 — Giữ quick presets

Không bỏ:

```text
80%
90%
100%
```

Nhưng chỉ coi đây là shortcut.

Ví dụ UI:

```text
Pin muốn sạc tới

             87%

───────●────────────

80%       90%       100%
```

Nếu pin hiện tại là:

```text
85%
```

thì:

```text
80%
```

phải disabled.

---

## Phase 12 — Validate target pin

Trong:

```text
SmartChargingPlanDraft.validate()
```

đảm bảo:

```dart
targetSoc > currentSoc
```

và:

```dart
targetSoc <= 100
```

Ví dụ:

```text
current = 85
target = 80
```

không hợp lệ.

Hiển thị:

```text
Mức pin muốn sạc phải cao hơn pin hiện tại.
```

---

## Phase 13 — Nhớ pin mục tiêu gần nhất

Có thể dùng:

```text
SharedPreferences
```

Key:

```text
smart_charge_last_target_soc
```

Ví dụ người dùng lần trước chọn:

```text
85%
```

lần sau Smart Charge mở ra:

```text
85%
```

thay vì mặc định 80%.

Nhưng phải clamp:

```dart
max(savedTarget, currentSoc + 1)
```

---

## Phase 14 — App phải dùng model AI trên web

Luồng chuẩn:

```text
Smart Charge UI
        ↓
SmartChargingController
        ↓
ChargingPredictionAdapter
        ↓
ApiService
        ↓
POST /api/ai/predict-charging-time
        ↓
web/server.py
        ↓
AI server
        ↓
charging_time model
```

Không chạy `.pkl` trực tiếp trong Flutter.

Không duplicate model vào APK.

---

## Phase 15 — Thêm strict AI mode

Sửa:

```text
app/lib/core/services/api_service.dart
```

Thêm:

```dart
bool strictAi = false
```

Request:

```json
{
  "vehicleId": "...",
  "currentBattery": 42,
  "targetBattery": 87,
  "ambientTempC": 30,
  "strictAi": true
}
```

Smart Charge gọi:

```dart
strictAi: true
```

---

## Phase 16 — ChargingPredictionAdapter chỉ dùng AI thật

Sửa:

```text
app/lib/data/services/charging_prediction_adapter.dart
```

Hiện đang:

```text
AI web
 ↓ lỗi
physicsFallback()
```

Smart Charge mới phải là:

```text
AI web
 ↓ lỗi
show AI error
```

Không tự chuyển sang physics fallback trong Smart Charge.

### Có thể giữ physicsFallback

Không cần xóa function.

Nó vẫn có thể dùng ở:

```text
debug
simulation
legacy predictor
unit test
```

Nhưng:

```text
Smart Charge
```

không được dùng.

---

## Phase 17 — Backend strict AI

Sửa:

```text
web/server.py
```

Hiện flow:

```text
AI
 ↓ fail
heuristic fallback
```

Thêm:

```python
strict_ai = bool(body.get('strictAi', False))
```

Nếu AI model không chạy:

```http
503
```

Response:

```json
{
  "success": false,
  "error": "Model AI hiện chưa khả dụng.",
  "debugCode": "AI_MODEL_UNAVAILABLE"
}
```

---

## Phase 18 — Guardrail khi strict AI

Hiện:

```text
AI output bất thường
↓
heuristic
```

Nếu:

```text
strictAi=true
```

thì không chuyển sang heuristic.

Trả:

```http
422
```

```json
{
  "success": false,
  "error": "Kết quả AI chưa đủ tin cậy.",
  "debugCode": "AI_PREDICTION_REJECTED",
  "debugDetail": "heuristic_guardrail_deviation"
}
```

---

## Phase 19 — Không bỏ heuristic hoàn toàn khỏi server

Các chức năng cũ vẫn có thể gọi:

```json
{
  "strictAi": false
}
```

Flow:

```text
AI
↓ fail
heuristic
```

để giữ backward compatibility.

Chỉ:

```text
Smart Charge
```

gửi:

```text
strictAi=true
```

---

## Phase 20 — Smart Charge Preview mới

Hiện preview chứa quá nhiều:

```text
Model
Source
Confidence
analyzedAt
warnings kỹ thuật
```

Đổi thành:

```text
Thời gian dự kiến

1 giờ 42 phút

Dự kiến dừng lúc
03:25
```

Có thể thêm:

```text
42% → 87%
```

Không hiện:

```text
modelVersion
```

---

## Phase 21 — Active Charging UI

Khi relay thật ON:

```text
        🟢 ĐANG SẠC

           42%
             ↓
           87%

       Còn khoảng
          01:42

Công suất
402 W

Tự tắt lúc
03:25

       [ DỪNG SẠC ]
```

---

## Phase 22 — Relay readback bắt buộc

Sau:

```text
BẮT ĐẦU SẠC
```

không đổi UI ngay.

Flow:

```text
User nhấn Start
      ↓
API/Shelly ON
      ↓
read status
      ↓
relay == true
      ↓
Đang sạc
```

Nếu:

```text
relay != true
```

thì:

```text
Không thể bật sạc
```

và debug detail.

---

## Phase 23 — OFF cũng phải readback

Flow:

```text
Dừng sạc
   ↓
Shelly OFF
   ↓
status readback
   ↓
relay=false
```

mới hiện:

```text
Đã tắt sạc
```

Nếu không xác minh được:

```text
⚠ Chưa xác nhận được ổ sạc đã tắt.

Hãy kiểm tra ổ sạc.
```

Không được giả định OFF thành công.

---

## Phase 24 — Error UX trong Smart Charge

### User-facing

AI lỗi:

```text
Không thể tính thời gian sạc.
Hãy thử lại.
```

Shelly lỗi:

```text
Không kết nối được ổ sạc.
```

Network:

```text
Không có kết nối tới máy chủ.
```

### Developer detail

Bấm:

```text
Xem chi tiết
```

mới thấy:

```text
SocketException
503
AI_MODEL_UNAVAILABLE
...
```

---

## Phase 25 — Test Error Reporter

Tạo:

```text
app/test/unit/app_error_reporter_test.dart
```

Test:

```text
stores error
stores stack
max 50 entries
newest first
redacts Bearer token
redacts password
redacts API key
```

---

## Phase 26 — Test target slider

Sửa/thêm:

```text
app/test/widget/smart_charging_control_screen_test.dart
```

Test:

```text
target slider exists
```

```text
current=40
target can be 41
```

```text
target can be 87
```

```text
target can be 100
```

```text
target cannot be <= current
```

---

## Phase 27 — Test trạng thái sạc

Test:

```text
relay=true
→ Đang sạc
```

```text
relay=false
→ Đã tắt sạc
```

```text
online=false
→ Mất kết nối
```

Không assert UI bằng:

```text
Relay ON
Relay OFF
```

nữa.

---

## Phase 28 — Test AI adapter

Thêm case:

```text
AI success
```

→ preview success.

Case:

```text
HTTP 503
```

→ exception.

Không:

```text
physicsFallback
```

khi Smart Charge dùng strict mode.

---

## Phase 29 — Backend tests

Trong:

```text
web/tests/
```

thêm:

```python
test_charging_prediction_strict_ai_success
```

```python
test_charging_prediction_strict_ai_unavailable_returns_503
```

```python
test_charging_prediction_strict_ai_guardrail_returns_422
```

```python
test_charging_prediction_non_strict_keeps_heuristic_fallback
```

---

## Phase 30 — Integration test

### Scenario 1

```text
Pin 40%
→ chọn 85%
→ AI web
→ trả 120 phút
→ Start
→ Shelly ON
→ relay=true
→ UI Đang sạc
```

### Scenario 2

```text
AI server OFF
→ chọn 85%
→ Tính thời gian
→ 503
→ app báo thử lại
→ Debug hiển thị AI_MODEL_UNAVAILABLE
→ Shelly không bật
```

### Scenario 3

```text
Shelly offline
→ AI vẫn dự đoán được
→ Start disabled
```

### Scenario 4

```text
Shelly ON
→ user Stop
→ OFF
→ readback false
→ Đã tắt sạc
```

---

## Phase 31 — Kiểm tra UI terminology

Search toàn project:

```bash
grep -R "Relay ON" app/lib
grep -R "Relay OFF" app/lib
grep -R "SOC mục tiêu" app/lib
grep -R "Model" app/lib/features/ai
grep -R "heuristic" app/lib/features/ai
```

Các text kỹ thuật không được xuất hiện trong Smart Charge user UI.

---

## Phase 32 — Kiểm tra build

```bash
cd app

dart format lib test
flutter analyze
flutter test
```

Build debug:

```bash
flutter build apk --debug
```

Sau đó:

```bash
flutter build apk --release
```

---

## Phase 33 — Kiểm thử trên điện thoại thật

Không chỉ emulator.

Test:

- App mở khi có mạng.
- App mở khi mất mạng.
- Shelly LAN.
- Shelly Cloud.
- Shelly offline.
- AI server hoạt động.
- AI server tắt.
- Bấm Start nhiều lần.
- Bấm Stop nhiều lần.
- Đóng app khi đang sạc.
- Mở lại app.
- Mất Wi-Fi khi đang sạc.
- Mất Internet nhưng LAN Shelly còn.
- Timer Shelly hết hạn khi app đóng.

---

## Phase 34 — Definition of Done

Feature chỉ được coi là hoàn thành khi:

- [ ] Người dùng chọn được bất kỳ target từ `current + 1` đến `100`.
- [ ] 80/90/100 vẫn là quick presets.
- [ ] Trạng thái “Đang sạc” lấy từ Shelly relay thật.
- [ ] Không dùng app session state để giả định đang sạc.
- [ ] Smart Charge sử dụng `charging_time` model trên web.
- [ ] Smart Charge không tự fallback physics khi AI lỗi.
- [ ] Backend hỗ trợ `strictAi`.
- [ ] AI unavailable trả 503.
- [ ] AI guardrail reject trả 422.
- [ ] Legacy API vẫn được phép heuristic fallback.
- [ ] Error + stack trace xem được trên app.
- [ ] Có nút copy lỗi.
- [ ] Secret bị redact.
- [ ] Màn Smart Charge không còn thuật ngữ khó hiểu.
- [ ] ON/OFF đều có readback.
- [ ] `flutter analyze` pass.
- [ ] `flutter test` pass.
- [ ] backend tests pass.
- [ ] APK release build thành công.

---

## Thứ tự ưu tiên cho agent

Cho agent triển khai theo đúng thứ tự này:

```text
P0
1. strictAi backend
2. ChargingPredictionAdapter chỉ dùng AI web
3. target slider
4. relay state → user state
5. ON/OFF readback giữ nguyên an toàn

P1
6. AppErrorReporter
7. API error reporting
8. Error detail sheet
9. redact secrets

P2
10. Simplify toàn bộ Smart Charge UI
11. Ẩn technical metadata
12. remember target %
13. tests

P3
14. integration test
15. APK QA
```

> Điểm quan trọng nhất: **không viết lại Smart Charger architecture**. Agent chỉ sửa lớp UX/debug/AI contract phía trên hệ thống Shelly hiện tại, tránh phá phần timer, fail-safe, Cloud/LAN fallback và readback mà branch hiện tại đã triển khai.
