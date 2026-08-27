# IMPLEMENTATION PLAN — STEP 8
## Tích hợp Shelly Plug S Gen3 vào VinFast Battery Flutter App qua Local Smart Charger Gateway

**Repository:** `khanhbes/Vinfast-Batery`  
**Target branch:** `main`  
**Scope:** Step 8 only — kết nối app Flutter với local FastAPI gateway, hiển thị telemetry, điều khiển relay thủ công, và gửi metadata dự đoán AI sang gateway ở chế độ **monitor-only**.  
**Không thuộc Step 8:** tự động ngắt khi đầy, suy luận FULL từ power curve, shadow-mode full detector, retrain AI bằng telemetry Shelly, cloud remote control.

---

# 0. Bối cảnh đã xác nhận

Hệ thống hiện tại có 3 lớp:

```text
Flutter App
    │
    │ Cloud API / Firebase
    ▼
Unified Flask API
    │
    ├── Firestore
    └── AI server

VÀ một nhánh local mới:

Flutter App
    │
    │ HTTP LAN
    ▼
Local FastAPI Smart Charger Gateway
    │
    │ HTTP LAN
    ▼
Shelly Plug S Gen3
    │
    ▼
VinFast charger
```

Thiết bị/prototype hiện tại đã được test thủ công thành công:

```text
Laptop:           192.168.1.12
Local FastAPI:    http://192.168.1.12:8000
Shelly:           192.168.1.3
Shelly model:     S3PL-00112EU / PlugSG3 / Gen3

GET  /api/charger/status   ✅
POST /api/charger/on       ✅
POST /api/charger/off      ✅

Python -> Shelly status     ✅
Python -> Relay ON          ✅
Python -> Relay OFF         ✅
Điện thoại -> FastAPI LAN   ✅
```

Các giá trị Shelly đã đọc được thực tế:

```text
relay
power_w
voltage_v
current_a
frequency_hz
temperature_c
energy_wh
```

## Repo hiện tại liên quan trực tiếp

### Flutter
- `app/lib/core/constants/app_constants.dart`
- `app/lib/core/services/api_service.dart`
- `app/lib/features/ai/ai_charging_predictor_screen.dart`
- `app/lib/data/services/smart_charging_service.dart`
- `app/lib/data/services/charging_feedback_service.dart`
- `app/lib/data/services/battery_state_service.dart`
- `app/lib/core/providers/app_providers.dart`
- `app/android/app/src/main/AndroidManifest.xml`
- `app/android/app/src/debug/AndroidManifest.xml`
- `app/pubspec.yaml`

### Web/cloud
- `web/server.py`

## Repo facts phải giữ nguyên

1. Flutter đã có package `http`, không thêm HTTP package khác.
2. `ApiService` hiện dành cho cloud API và Firebase token.
3. Không nhét local Shelly gateway vào `ApiService`.
4. Repo đã có `SmartChargingService`, nhưng class này dùng để ước tính ETA dựa vào charge logs. **Không đổi tên, không thay thế nó.**
5. Tên service mới cho phần hardware phải khác, đề xuất:
   - `SmartChargerService`
6. `AiChargingPredictorScreen` hiện giữ:
   - `_currentSOC`
   - `_targetSOC`
   - `_predictedMinutes`
   - `_completionTime`
   - `_startTime`
7. Màn AI đang gọi `ApiService().predictChargingTime(...)`.
8. Không refactor toàn bộ AI/cloud architecture trong Step 8.
9. Không cho cloud `web/server.py` gọi thẳng `192.168.1.3`; cloud không thể truy cập LAN của người dùng.
10. Local gateway là boundary bắt buộc giữa Flutter và Shelly.

---

# 1. Mục tiêu Step 8

Sau khi hoàn thành, luồng phải hoạt động:

```text
AiChargingPredictorScreen
        │
        ├── Cloud AI prediction
        │
        ▼
  predictedMinutes
  predictedFullAt
        │
        ├──────────────────────────────┐
        │                              │
        ▼                              ▼
Hiển thị AI result           Local Smart Charger Gateway
                                      │
                                      ├── nhận prediction metadata
                                      │   monitor-only
                                      │
                                      └── đọc/điều khiển Shelly
```

App phải làm được:

```text
✅ Đọc gateway online/offline
✅ Đọc relay state
✅ Đọc W
✅ Đọc V
✅ Đọc A
✅ Đọc Hz
✅ Đọc nhiệt độ Shelly
✅ Đọc Wh
✅ Bật relay thủ công
✅ Tắt relay thủ công
✅ Poll status định kỳ khi màn AI đang mở
✅ Không spam SnackBar khi mất mạng
✅ Gửi prediction metadata sang gateway
✅ Gateway lưu session monitor-only
✅ AI prediction vẫn hoạt động nếu gateway offline
✅ App không phụ thuộc Shelly để dự đoán AI
```

---

# 2. Non-goals bắt buộc

Agent **KHÔNG** được implement trong Step 8:

```text
❌ if predictedFullAt reached -> turnOff()
❌ if power < X -> turnOff()
❌ full detection algorithm
❌ auto cutoff
❌ background auto control
❌ tự bật charger
❌ tự reconnect và bật relay
❌ cloud điều khiển Shelly
❌ mở port 8000 ra Internet
❌ port-forward Shelly
❌ MQTT
❌ ESP32
❌ BMS integration
❌ train/retrain AI từ Shelly telemetry
❌ thay đổi Firestore schema để lưu telemetry hàng 5 giây
```

Step 8 là **integration + manual control + monitor-only session metadata**.

---

# 3. Quyết định kiến trúc

## 3.1 Không gọi Shelly trực tiếp từ Flutter

Không làm:

```text
Flutter
  ↓
http://192.168.1.3/rpc/...
  ↓
Shelly
```

Phải giữ:

```text
Flutter
  ↓
Local Gateway :8000
  ↓
Shelly
```

Lý do:

- không leak Shelly RPC chi tiết vào UI;
- sau này full detector chạy ngoài app;
- app đóng vẫn không phá architecture tương lai;
- gateway chuẩn hóa JSON;
- gateway xử lý timeout/error Shelly;
- đổi model smart plug không phải sửa Flutter.

## 3.2 Cloud API và local gateway là hai service riêng

Cloud:

```text
ApiService
  ↓
APP_API_BASE_URL
```

Local hardware:

```text
SmartChargerService
  ↓
SMART_CHARGER_API_BASE_URL
```

Không merge hai base URL.

---

# 4. Cấu hình URL local gateway

## File cần sửa

`app/lib/core/constants/app_constants.dart`

Thêm:

```dart
static const String smartChargerApiBaseUrl = String.fromEnvironment(
  'SMART_CHARGER_API_BASE_URL',
  defaultValue: '',
);
```

## Yêu cầu

- Không hard-code `192.168.1.12` trong source production.
- Current dev command:

```bash
flutter run \
  --dart-define=SMART_CHARGER_API_BASE_URL=http://192.168.1.12:8000
```

Trên Windows PowerShell có thể chạy một dòng:

```powershell
flutter run --dart-define=SMART_CHARGER_API_BASE_URL=http://192.168.1.12:8000
```

## Behavior khi URL rỗng

Không crash.

Service phải trả lỗi typed hoặc trạng thái:

```text
Smart Charger chưa được cấu hình
```

UI vẫn cho AI predictor hoạt động bình thường.

---

# 5. Android HTTP LAN policy

Local gateway hiện dùng HTTP:

```text
http://192.168.1.12:8000
```

Không bật cleartext global trong `src/main`.

## Sửa debug manifest

File:

`app/android/app/src/debug/AndroidManifest.xml`

Cho phép cleartext **chỉ debug build**.

Mục tiêu manifest merge phải tạo:

```xml
<application android:usesCleartextTraffic="true" />
```

Giữ `INTERNET` permission.

Ví dụ:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>

    <application
        android:usesCleartextTraffic="true" />
</manifest>
```

## Không làm

Không thêm:

```xml
android:usesCleartextTraffic="true"
```

vào `src/main/AndroidManifest.xml` trong Step 8.

Release prototype qua HTTP local sẽ được xử lý riêng sau bằng HTTPS/local secure design hoặc network policy cụ thể.

---

# 6. Data models mới trong Flutter

Tạo:

```text
app/lib/data/models/smart_charger_status.dart
app/lib/data/models/smart_charging_session.dart
```

---

# 7. Model `SmartChargerStatus`

## Required fields

```dart
class SmartChargerStatus {
  final bool online;
  final bool relay;
  final double powerW;
  final double voltageV;
  final double currentA;
  final double frequencyHz;
  final double? temperatureC;
  final double energyWh;
}
```

## Parsing rules

JSON gateway:

```json
{
  "online": true,
  "relay": false,
  "power_w": 0.0,
  "voltage_v": 228.9,
  "current_a": 0.0,
  "frequency_hz": 49.8,
  "temperature_c": 46.2,
  "energy_wh": 10.0
}
```

Parser phải chấp nhận `int` hoặc `double`.

Dùng helper:

```dart
double _asDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}
```

Không cast thẳng:

```dart
json['power_w'] as double
```

vì server có thể trả `0` thay vì `0.0`.

## UI semantics

Không tự suy luận:

```text
power > 0 => charging
```

trong Step 8.

Chỉ hiển thị:

```text
relay = true  -> "Đang cấp nguồn"
relay = false -> "Đã ngắt nguồn"
online false  -> "Không kết nối"
```

Power được hiển thị độc lập.

---

# 8. Model `SmartChargingSessionRequest`

Tạo typed request để app gửi prediction sang gateway.

Fields:

```dart
class SmartChargingSessionRequest {
  final String vehicleId;
  final double startSoc;
  final double targetSoc;
  final int predictedMinutes;
  final DateTime startedAt;
  final DateTime predictedFullAt;
  final String chargingMode;
  final String? predictionSource;
  final double? predictionConfidence;
}
```

JSON canonical:

```json
{
  "vehicle_id": "vehicle-id",
  "start_soc": 20.0,
  "target_soc": 80.0,
  "predicted_minutes": 160,
  "started_at": "2026-08-27T18:30:00.000+07:00",
  "predicted_full_at": "2026-08-27T21:10:00.000+07:00",
  "charging_mode": "standard",
  "prediction_source": "ai_model",
  "prediction_confidence": 82.0
}
```

Date dùng `toIso8601String()`.

Không gửi `_completionTime` dạng `"21:10"` làm dữ liệu canonical.

---

# 9. Local `SmartChargerService`

Tạo:

`app/lib/data/services/smart_charger_service.dart`

Lưu ý:

- repo đã có `smart_charging_service.dart`
- service mới phải là **smart_charger_service.dart**
- class mới là **SmartChargerService**

## Constructor phải hỗ trợ dependency injection

Đề xuất:

```dart
class SmartChargerService {
  final http.Client _client;
  final String baseUrl;

  SmartChargerService({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        baseUrl = (baseUrl ?? AppConstants.smartChargerApiBaseUrl)
            .replaceAll(RegExp(r'/$'), '');
}
```

Mục đích:

- unit test bằng `MockClient`;
- không hard-code IP;
- có thể đổi gateway trong dev.

## Timeout

Local LAN timeout:

```dart
const Duration(seconds: 3)
```

Không dùng 30 giây như cloud `ApiService`.

Nếu gateway chết, UI cần phản hồi nhanh.

---

# 10. Methods trong `SmartChargerService`

Implement tối thiểu:

```dart
Future<SmartChargerStatus> getStatus();

Future<SmartChargerCommandResult> turnOn();

Future<SmartChargerCommandResult> turnOff();

Future<SmartChargingSessionResponse> startMonitoringSession(
  SmartChargingSessionRequest request,
);
```

Có thể thêm:

```dart
Future<bool> healthCheck();
```

nhưng không bắt buộc nếu `getStatus()` đủ.

## Endpoints

```text
GET  /api/charger/status
POST /api/charger/on
POST /api/charger/off
POST /api/charging/session
```

## Error behavior

Không trả loose map kiểu:

```dart
{'success': false}
```

cho service hardware.

Nên throw custom exception:

```dart
class SmartChargerException implements Exception {
  final String message;
  final int? statusCode;
}
```

Cases:

```text
baseUrl empty
timeout
Socket/network failure
HTTP != 2xx
invalid JSON
required response field malformed
```

Screen catch exception và chuyển sang offline/error state.

---

# 11. Command response model

Có thể đặt trong `smart_charger_status.dart` hoặc file riêng.

```dart
class SmartChargerCommandResult {
  final bool success;
  final bool relay;
  final bool? previousState;
}
```

Expected:

```json
{
  "success": true,
  "relay": true,
  "previous_state": false
}
```

Sau `turnOn` hoặc `turnOff`, app **phải gọi lại `getStatus()`** để confirm actual relay state.

Không dùng response command như bằng chứng duy nhất.

---

# 12. Local Gateway phải được đưa vào source control

Hiện gateway đã chạy ngoài repo trên laptop. Agent làm việc từ GitHub phải có source reproducible.

Tạo root folder:

```text
smart_charger_gateway/
├── main.py
├── shelly.py
├── models.py
├── session_store.py
├── requirements.txt
├── .env.example
├── README.md
└── tests/
```

Không nhét code Shelly vào:

```text
web/server.py
```

Cloud Flask API không phải local hardware gateway.

---

# 13. Gateway config

`shelly.py` không hard-code lâu dài.

Dùng env:

```python
import os

SHELLY_IP = os.getenv("SHELLY_IP", "192.168.1.3")
```

`.env.example`:

```env
SHELLY_IP=192.168.1.3
SMART_CHARGER_HOST=0.0.0.0
SMART_CHARGER_PORT=8000
```

Không commit:

```text
Wi-Fi password
router password
Firebase key
personal secrets
```

---

# 14. Gateway status contract

Giữ endpoint đang hoạt động:

```text
GET /api/charger/status
```

Response canonical:

```json
{
  "online": true,
  "relay": false,
  "power_w": 0.0,
  "voltage_v": 228.9,
  "current_a": 0.0,
  "frequency_hz": 49.8,
  "temperature_c": 46.2,
  "energy_wh": 10.0
}
```

Không đổi tên field trong lúc Flutter integration.

Shelly raw response chỉ tồn tại bên trong gateway.

---

# 15. Gateway manual relay commands

Giữ:

```text
POST /api/charger/on
POST /api/charger/off
```

Sau lệnh Shelly, gateway trả:

```json
{
  "success": true,
  "relay": true,
  "previous_state": false
}
```

hoặc OFF tương ứng.

Nếu Shelly unavailable:

```text
HTTP 503
```

Không giả success.

---

# 16. Gateway monitor-only prediction session

Thêm:

```text
POST /api/charging/session
```

## Pydantic request

```python
class ChargingSessionRequest(BaseModel):
    vehicle_id: str
    start_soc: float
    target_soc: float
    predicted_minutes: int
    started_at: datetime
    predicted_full_at: datetime
    charging_mode: str = "standard"
    prediction_source: str | None = None
    prediction_confidence: float | None = None
```

Validation:

```text
0 <= start_soc <= 100
0 <= target_soc <= 100
target_soc > start_soc
1 <= predicted_minutes <= 720
predicted_full_at > started_at
charging_mode in {"standard", "fast"}
```

## Response

```json
{
  "success": true,
  "session_id": "uuid",
  "mode": "monitor_only",
  "received_at": "ISO8601"
}
```

## Safety invariant

Endpoint này:

```text
KHÔNG turn_on()
KHÔNG turn_off()
KHÔNG start auto detector
KHÔNG set timer để cắt điện
```

Chỉ lưu metadata.

---

# 17. Persist current monitor session

Tạo:

`smart_charger_gateway/session_store.py`

Lưu current session vào:

```text
smart_charger_gateway/state/current_session.json
```

Thư mục `state/` nên gitignore content runtime.

Mục tiêu:

- gateway restart không mất metadata hoàn toàn;
- Step 9 có nền để đọc lại session;
- chưa có background controller.

Dùng atomic replace nếu implement đơn giản:

```text
write temp file
fsync/close
replace current_session.json
```

Không cần database cho Step 8.

---

# 18. Optional current-session endpoint

Nên thêm:

```text
GET /api/charging/session/current
```

Response:

```json
{
  "active": true,
  "session": {
    "...": "..."
  }
}
```

Nếu chưa có:

```json
{
  "active": false,
  "session": null
}
```

Endpoint này hữu ích cho debug/acceptance test.

---

# 19. Sửa `AiChargingPredictorScreen` state

File:

`app/lib/features/ai/ai_charging_predictor_screen.dart`

Không nhét toàn bộ HTTP logic vào screen.

Thêm fields:

```dart
final SmartChargerService _smartChargerService = SmartChargerService();

SmartChargerStatus? _smartChargerStatus;
String? _smartChargerError;

bool _smartChargerLoading = false;
bool _smartChargerCommandBusy = false;

Timer? _smartChargerPollTimer;

DateTime? _predictedFullAt;
String? _predictionSource;
double? _predictionConfidence;

String? _monitorSessionId;
String? _monitorSessionError;
```

Add import:

```dart
import 'dart:async';
```

và model/service imports.

---

# 20. Polling lifecycle

Trong `initState()`:

```text
1. giữ _loadCurrentBatteryState()
2. giữ _loadFeedbackStats()
3. gọi _refreshSmartChargerStatus()
4. start Timer.periodic 5 seconds
```

Pseudo:

```dart
void _startSmartChargerPolling() {
  _refreshSmartChargerStatus();

  _smartChargerPollTimer?.cancel();
  _smartChargerPollTimer = Timer.periodic(
    const Duration(seconds: 5),
    (_) => _refreshSmartChargerStatus(silent: true),
  );
}
```

Trong `dispose()`:

```dart
_smartChargerPollTimer?.cancel();
super.dispose();
```

## Rules

- không tạo timer mới mỗi rebuild;
- không poll khi widget disposed;
- mỗi 5 giây đủ;
- tránh request overlap:
  - nếu request trước chưa xong thì bỏ tick mới;
- silent poll không hiện SnackBar.

---

# 21. Status refresh behavior

Implement:

```dart
Future<void> _refreshSmartChargerStatus({
  bool silent = false,
}) async
```

Success:

```text
_smartChargerStatus = status
_smartChargerError = null
```

Failure:

```text
_smartChargerStatus = null hoặc giữ last-known status với stale marker
_smartChargerError = human-readable error
```

Đề xuất tốt hơn:

- giữ `lastKnownStatus`;
- thêm `DateTime? _smartChargerLastUpdated`;
- offline state hiển thị "Mất kết nối";
- không biến telemetry cũ thành telemetry current.

Nếu giữ last known data, UI phải ghi:

```text
Dữ liệu gần nhất: HH:mm:ss
```

---

# 22. Manual relay ON flow

`_turnSmartChargerOn()`:

1. Nếu gateway offline -> không gọi.
2. Hiện confirmation dialog.
3. Text rõ:

```text
Bật nguồn sạc?
Hãy đảm bảo bộ sạc và xe đã được kết nối đúng cách.
```

4. User confirm mới POST `/api/charger/on`.
5. Set `_smartChargerCommandBusy = true`.
6. Gọi `turnOn()`.
7. Gọi ngay `getStatus()` để confirm.
8. Nếu `relay != true`, coi là failure.
9. Update UI.
10. SnackBar success/failure.
11. finally busy=false.

Không auto turn on khi:
- mở app;
- mở màn AI;
- prediction thành công;
- gateway reconnect;
- app resume.

---

# 23. Manual relay OFF flow

`_turnSmartChargerOff()`:

- có thể OFF ngay, không cần confirm;
- set busy;
- `turnOff()`;
- `getStatus()` confirm;
- relay phải false;
- success SnackBar;
- finally clear busy.

OFF được ưu tiên vì đây là hành động an toàn hơn ON.

---

# 24. Extract UI widget để tránh phình screen

Tạo:

```text
app/lib/features/ai/widgets/smart_charger_card.dart
```

Widget nhận props:

```dart
SmartChargerStatus? status
String? error
bool loading
bool commandBusy
DateTime? lastUpdated
VoidCallback onRefresh
VoidCallback onTurnOn
VoidCallback onTurnOff
String? monitorSessionId
String? monitorSessionError
```

Không để widget tự gọi HTTP.

---

# 25. Smart Charger Card UI

Đặt card trong `AiChargingPredictorScreen`:

```text
AI Predictor Card
↓
Smart Charger Card
↓
Prediction Result
↓
Feedback
```

Tức thêm SliverToBoxAdapter sau `_buildChargingCard()` và trước `_buildPredictionResult()`.

## Card states

### A. Not configured

```text
SMART CHARGER
⚪ Chưa cấu hình gateway

Thiết lập SMART_CHARGER_API_BASE_URL để kết nối.
```

Không crash.

### B. Connecting

```text
SMART CHARGER
Đang kết nối...
```

### C. Online / relay OFF

```text
SMART CHARGER
🟢 Gateway online
⚪ Đã ngắt nguồn

⚡ 0.0 W
🔌 0.000 A
〰 228.9 V
🌡 46.2 °C
🔋 Energy 10 Wh

[BẬT NGUỒN SẠC]
```

### D. Online / relay ON

```text
SMART CHARGER
🟢 Gateway online
🟢 Đang cấp nguồn

⚡ ...
...

[NGẮT NGUỒN]
```

### E. Gateway offline

```text
SMART CHARGER
🔴 Không kết nối gateway
Dữ liệu gần nhất: ...
[THỬ LẠI]
```

## Không dùng text sai

Không ghi:

```text
"Pin đang sạc"
```

chỉ vì relay ON.

Relay ON chỉ nghĩa:

```text
Shelly đang cấp điện cho output
```

---

# 26. Giữ UI style hiện tại

Card phải dùng:

```text
AppColors.card
AppColors.glassBorder
AppColors.primary
AppColors.success
AppColors.warning
AppColors.error
AppColors.textPrimary
AppColors.textSecondary
```

Giữ rounded card style hiện tại.

Không thêm UI framework.

Có thể dùng `flutter_animate` giống screen hiện tại.

---

# 27. Refactor prediction timestamp trước khi gửi gateway

Hiện `_predictCharging()` gọi `DateTime.now()` nhiều lần.

Sửa để capture một thời điểm:

```dart
final predictionStartedAt = DateTime.now();
```

Sau khi có `minutes`:

```dart
final predictedFullAt = predictionStartedAt.add(
  Duration(minutes: minutes),
);
```

State:

```dart
_startTime = predictionStartedAt;
_predictedFullAt = predictedFullAt;
```

`_completionTime` chỉ là formatted UI.

Canonical time gửi gateway là `_predictedFullAt`.

---

# 28. Giữ model source/confidence

Trong response AI:

```dart
final data = response['data'] as Map<String, dynamic>? ?? {};
```

Extract thêm:

```dart
final modelSource = data['modelSource']?.toString();

final confidenceValue = data['confidence'];
final confidence = confidenceValue is num
    ? confidenceValue.toDouble()
    : double.tryParse(confidenceValue?.toString() ?? '');
```

Save:

```dart
_predictionSource = modelSource;
_predictionConfidence = confidence;
```

Không đổi logic AI model selection trong Step 8.

---

# 29. Fix fallback bug bắt buộc trước session sync

Hiện screen có fallback:

```dart
final energyNeeded =
    (_targetSOC - _currentSOC) / 100 * 72.0; // kWh
```

Đây là dimensional bug.

`72` không được dùng như kWh battery capacity.

Repo/backend hiện dùng battery capacity mặc định `2400 Wh`.

Agent phải sửa fallback để dùng Wh rõ ràng.

Ví dụ:

```dart
const batteryCapacityWh = 2400.0;
final chargerPowerW = _isFastCharging ? 1000.0 : 400.0;

final energyNeededWh =
    (_targetSOC - _currentSOC) / 100.0 * batteryCapacityWh;

final hours = energyNeededWh / chargerPowerW;
final minutes = (hours * 60).round();
```

Tốt hơn:

- tạo `AppConstants.defaultBatteryCapacityWh = 2400.0`
- tránh magic number.

Không thay server heuristic trong Step 8.

Mục tiêu là không gửi một ETA fallback sai nghiêm trọng sang gateway.

---

# 30. Session sync sau prediction thành công

Sau khi prediction được set thành công:

```text
AI prediction result
      ↓
UI update
      ↓
attempt startMonitoringSession()
```

Gateway failure **không được làm AI prediction fail**.

Implement method:

```dart
Future<void> _syncPredictionToSmartCharger({
  required String vehicleId,
}) async
```

Preconditions:

```text
SMART_CHARGER_API_BASE_URL != empty
_predictedMinutes > 0
_startTime != null
_predictedFullAt != null
```

Payload:

```dart
SmartChargingSessionRequest(
  vehicleId: vehicleId,
  startSoc: _currentSOC,
  targetSoc: _targetSOC,
  predictedMinutes: _predictedMinutes,
  startedAt: _startTime!,
  predictedFullAt: _predictedFullAt!,
  chargingMode: _isFastCharging ? 'fast' : 'standard',
  predictionSource: _predictionSource,
  predictionConfidence: _predictionConfidence,
);
```

---

# 31. Session sync UX

Nếu success:

```text
monitorSessionId = response.sessionId
monitorSessionError = null
```

Trong Smart Charger card có dòng nhỏ:

```text
AI monitor: Đã đồng bộ
Session: abcd1234
```

Không cần hiện UUID full.

Nếu fail:

```text
AI monitor: Chưa đồng bộ gateway
```

AI result vẫn giữ nguyên.

Không hiện modal blocking.

Không gọi relay OFF/ON.

---

# 32. AI screen behavior khi gateway offline

Đây là invariant bắt buộc:

```text
Gateway offline
    │
    ├── Smart charger card = offline
    │
    └── AI prediction = vẫn chạy bình thường
```

Không được:

```text
if gateway offline:
  disable AI predict
```

Hardware là optional companion trong Step 8.

---

# 33. AI screen behavior khi cloud AI offline

Existing local fallback vẫn hoạt động.

Sau khi fallback ETA tính xong:

```text
fallback prediction
      ↓
session metadata có thể gửi local gateway
```

`prediction_source`:

```text
local_fallback
```

hoặc giữ semantic rõ.

Không giả source là `ai_model`.

---

# 34. Không dùng Shelly power làm AI input trong Step 8

Dù app đọc được:

```text
power_w
current_a
voltage_v
```

không sửa `predictChargingTime()` request để dùng power ngay.

Lý do:

- chưa có schema/model được train cho field mới;
- telemetry cần được collect/validate trước;
- Step 9/10 mới xử lý charging curve.

---

# 35. Riverpod

Không bắt buộc tạo provider/controller mới trong Step 8.

Screen hiện là `ConsumerStatefulWidget`.

Để giảm risk:

```text
network logic -> SmartChargerService
display -> SmartChargerCard
lifecycle/poll -> AiChargingPredictorScreen
```

Không refactor toàn màn sang AsyncNotifier trong cùng PR.

Nếu agent muốn tạo provider, phải chứng minh không tăng scope và tests pass; default plan là không.

---

# 36. Unit tests — model

Tạo:

```text
app/test/unit/smart_charger_status_test.dart
```

Cases:

```text
1. parse normal doubles
2. parse integer 0 into double 0.0
3. temperature null
4. missing optional numeric fields -> safe fallback
5. relay true/false
6. online true/false
```

---

# 37. Unit tests — service

Tạo:

```text
app/test/unit/smart_charger_service_test.dart
```

Dùng:

```dart
package:http/testing.dart
```

Cases:

```text
GET status 200 -> typed model
GET status 503 -> SmartChargerException
GET status malformed JSON -> exception
empty baseUrl -> configuration exception
POST ON 200 -> result
POST OFF 200 -> result
session POST serializes ISO timestamps correctly
session POST 200 -> session id
```

Không cần real Shelly trong unit tests.

---

# 38. Widget test — Smart Charger Card

Tạo:

```text
app/test/widget/smart_charger_card_test.dart
```

Cases:

```text
not configured state
loading state
online + relay OFF
online + relay ON
offline/error
button ON callback
button OFF callback
busy disables commands
telemetry labels render
```

Widget này không import Firebase.

---

# 39. Gateway tests

Tạo:

```text
smart_charger_gateway/tests/test_api.py
smart_charger_gateway/tests/test_session_store.py
```

Mock Shelly calls.

Test:

```text
status normalized
on command
off command
Shelly timeout -> 503
session valid -> monitor_only
invalid SOC -> 422/400
target <= start -> reject
predictedFullAt <= startedAt -> reject
session persistence
GET current session
```

Không test bằng relay thật trong automated suite.

---

# 40. Manual acceptance test

## Environment

```text
Phone + laptop: same Wi-Fi
Laptop IP: 192.168.1.12
Shelly IP: 192.168.1.3
Gateway: 0.0.0.0:8000
```

Start gateway:

```powershell
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

Run Flutter:

```powershell
flutter run --dart-define=SMART_CHARGER_API_BASE_URL=http://192.168.1.12:8000
```

---

# 41. Acceptance sequence A — status only

Chưa cắm VinFast charger.

Expected card:

```text
online
relay correct
power ~0
current ~0
voltage ~220-240
temperature non-null
```

Poll update every ~5 sec.

Không crash.

---

# 42. Acceptance sequence B — manual ON/OFF

1. Relay OFF.
2. Tap BẬT NGUỒN.
3. Confirmation dialog hiện.
4. Cancel -> relay không đổi.
5. Tap lại, confirm.
6. Shelly relay ON.
7. UI confirm relay ON.
8. Tap NGẮT NGUỒN.
9. Relay OFF.
10. UI confirm OFF.

Không auto ON ở bất kỳ thời điểm nào.

---

# 43. Acceptance sequence C — gateway offline

1. Stop Uvicorn.
2. Chờ polling.
3. Card chuyển offline.
4. AI predictor vẫn usable.
5. Không có SnackBar mỗi 5 giây.
6. Start Uvicorn lại.
7. App tự recover ở poll sau hoặc nút THỬ LẠI.

---

# 44. Acceptance sequence D — AI prediction session

1. Gateway online.
2. Chọn current SOC.
3. Chọn target SOC.
4. Bấm DỰ ĐOÁN VỚI AI.
5. AI result xuất hiện.
6. Gateway nhận POST `/api/charging/session`.
7. Response `mode=monitor_only`.
8. App hiện "AI monitor: Đã đồng bộ".
9. `GET /api/charging/session/current` chứa:
   - vehicle id
   - start SOC
   - target SOC
   - predicted minutes
   - start time
   - predicted full time
10. Relay không đổi do prediction.

---

# 45. Acceptance sequence E — gateway offline khi predict

1. Stop gateway.
2. Bấm AI predict.
3. Prediction vẫn hiển thị.
4. Session sync báo unavailable nhẹ.
5. Không mất prediction.
6. Không crash.

---

# 46. Acceptance sequence F — malformed/slow gateway

Test bằng mock hoặc temporary endpoint:

```text
timeout > 3 sec
500
503
invalid JSON
```

App:

```text
không treo spinner vĩnh viễn
không crash
card = error/offline
AI flow independent
```

---

# 47. Static analysis/build gates

Agent phải chạy:

```bash
cd app
flutter pub get
flutter analyze
flutter test
```

Sau đó Android debug build:

```bash
flutter build apk --debug \
  --dart-define=SMART_CHARGER_API_BASE_URL=http://192.168.1.12:8000
```

Nếu repo convention yêu cầu build khác thì giữ convention, nhưng ít nhất debug APK phải build.

---

# 48. Python gateway gates

Trong `smart_charger_gateway`:

```bash
python -m pip install -r requirements.txt
pytest
```

Nếu chưa dùng pytest trong repo, thêm dependency dev riêng hoặc ghi rõ manual test.

Start check:

```bash
python -m uvicorn main:app --host 0.0.0.0 --port 8000
```

Then:

```text
GET http://127.0.0.1:8000/api/charger/status
```

phải chạy.

---

# 49. Files expected to add

```text
smart_charger_gateway/
├── main.py
├── shelly.py
├── models.py
├── session_store.py
├── requirements.txt
├── .env.example
├── README.md
└── tests/...

app/lib/data/models/smart_charger_status.dart
app/lib/data/models/smart_charging_session.dart
app/lib/data/services/smart_charger_service.dart
app/lib/features/ai/widgets/smart_charger_card.dart

app/test/unit/smart_charger_status_test.dart
app/test/unit/smart_charger_service_test.dart
app/test/widget/smart_charger_card_test.dart
```

---

# 50. Files expected to modify

```text
app/lib/core/constants/app_constants.dart

app/lib/features/ai/ai_charging_predictor_screen.dart

app/android/app/src/debug/AndroidManifest.xml

.gitignore
```

Optional:

```text
README.md
```

to document local smart charger development command.

---

# 51. Files agent should NOT modify unless required by compiler

```text
web/server.py
app/lib/core/services/api_service.dart
app/lib/data/services/smart_charging_service.dart
app/lib/data/services/battery_state_service.dart
Firestore rules
AI server models
Docker production stack
```

`ApiService` cloud contract must remain intact.

---

# 52. `.gitignore`

Ignore gateway runtime:

```gitignore
smart_charger_gateway/.venv/
smart_charger_gateway/__pycache__/
smart_charger_gateway/.pytest_cache/
smart_charger_gateway/state/*.json
smart_charger_gateway/.env
```

Commit:

```text
.env.example
```

Do not commit `.env`.

---

# 53. Logging

Flutter debug logs may use:

```text
[SmartCharger]
```

Gateway:

```text
[SmartChargerGateway]
[Shelly]
[MonitorSession]
```

Không log:
- Wi-Fi passwords;
- Firebase tokens;
- full auth headers.

---

# 54. Error text đề xuất

Gateway not configured:

```text
Smart Charger chưa được cấu hình.
```

Gateway unreachable:

```text
Không thể kết nối bộ điều khiển sạc trong mạng Wi-Fi.
```

Shelly unavailable via gateway:

```text
Gateway đang chạy nhưng không liên lạc được với Shelly.
```

ON failed:

```text
Không thể bật nguồn sạc.
```

OFF failed:

```text
Không thể ngắt nguồn sạc.
```

Prediction sync failed:

```text
Dự đoán vẫn hợp lệ, nhưng chưa đồng bộ được với Smart Charger.
```

---

# 55. Safety requirements

1. Prediction không được tự điều khiển relay.
2. Reconnect không được tự bật relay.
3. App startup không được tự bật relay.
4. ON luôn là explicit user action.
5. OFF có thể thực hiện trực tiếp bằng user action.
6. Gateway session mode phải là `monitor_only`.
7. Không implement threshold W.
8. Không implement countdown -> OFF.
9. Không expose port 8000 ra public Internet.
10. Không expose Shelly port 80 ra Internet.

---

# 56. Technical debt discovered — xử lý trong Step 8

## A. Local fallback 72 kWh bug

Phải fix vì prediction metadata có thể được gửi sang hardware gateway.

Current:

```dart
* 72.0 // kWh
```

Target:

```text
battery capacity in Wh
```

Repo canonical current default:

```text
2400 Wh
```

## B. Current completion timestamp only string

Add real:

```dart
DateTime? _predictedFullAt
```

String `_completionTime` chỉ để UI.

## C. Current screen discards model source/confidence

Preserve these fields for session metadata.

## D. Do not conflate `SmartChargingService` with hardware

Existing `SmartChargingService` stays history/ETA utility.

New hardware class:

```text
SmartChargerService
```

---

# 57. Definition of Done

Step 8 được coi là DONE khi tất cả điều kiện sau đúng:

```text
[ ] Local gateway source nằm trong repo hoặc được agent quản lý reproducibly
[ ] Gateway nhận status/on/off từ Shelly
[ ] Gateway có monitor-only session endpoint
[ ] Flutter có configurable local gateway URL
[ ] Không hard-code laptop IP trong Dart source
[ ] Debug Android cho phép local HTTP
[ ] SmartChargerStatus typed model
[ ] SmartChargerService typed service
[ ] SmartChargerCard widget
[ ] Card hiển thị V/A/W/Hz/°C/Wh
[ ] Polling 5s hoạt động
[ ] Poll timer dispose đúng
[ ] Offline không spam notification
[ ] Manual ON có confirmation
[ ] Manual OFF hoạt động
[ ] Command được confirm bằng status readback
[ ] Prediction lưu DateTime predictedFullAt thật
[ ] Prediction source/confidence được giữ
[ ] 72 kWh fallback bug được sửa
[ ] Prediction metadata gửi gateway
[ ] Gateway lưu mode=monitor_only
[ ] Prediction không thay đổi relay
[ ] Gateway offline không làm AI predictor fail
[ ] Existing cloud API vẫn hoạt động
[ ] Existing SmartChargingService tests vẫn pass
[ ] New unit tests pass
[ ] Widget tests pass
[ ] flutter analyze pass
[ ] flutter test pass
[ ] debug APK build pass
```

---

# 58. Implementation order bắt buộc cho agent

Agent nên implement đúng thứ tự để giảm lỗi:

```text
1. Inspect current repo, do not assume stale file contents.
2. Add gateway source/config without changing behavior status/on/off.
3. Add monitor-only session endpoint + tests.
4. Add AppConstants SMART_CHARGER_API_BASE_URL.
5. Add debug cleartext manifest.
6. Add Dart data models.
7. Add SmartChargerService + unit tests.
8. Add SmartChargerCard + widget tests.
9. Add polling lifecycle to AiChargingPredictorScreen.
10. Add manual ON/OFF handlers.
11. Fix prediction timestamp + 72 kWh fallback bug.
12. Preserve prediction source/confidence.
13. Add session sync after prediction.
14. Run analyze/tests.
15. Manual test with real gateway/Shelly.
16. Build debug APK.
17. Summarize changed files and remaining Step 9 work.
```

---

# 59. Agent execution rules

Agent must:

- inspect current file before editing;
- preserve unrelated existing functionality;
- keep public cloud API behavior unchanged;
- avoid broad refactors;
- avoid formatting entire unrelated files;
- not delete legacy code merely because it looks unused unless compiler proves it is required;
- use typed models instead of loose maps for new hardware layer;
- add tests with each new service/model;
- never implement auto-off in this PR;
- report any repo inconsistency discovered instead of silently changing product behavior.

---

# 60. Expected final report from agent

Agent final response should include:

```text
1. Summary of implementation.
2. Files added.
3. Files modified.
4. API contracts added.
5. Tests added.
6. Commands run and results.
7. Manual Shelly test status.
8. Known limitations.
9. Explicit statement:
   "Automatic cutoff is NOT implemented in Step 8."
10. Recommended next step:
    Step 9 = real charger telemetry collection / charging curve logging.
```

---

# 61. Architecture after Step 8

```text
                          INTERNET
                             │
                             ▼
┌─────────────────┐     Cloud API
│ Flutter App     │──────────────► AI / Firestore
│                 │
│ AI Predictor    │
│                 │
│ Smart Charger   │
│ Card            │
└────────┬────────┘
         │
         │ LOCAL LAN HTTP
         ▼
┌──────────────────────────┐
│ Smart Charger Gateway    │
│ FastAPI :8000            │
│                          │
│ status                   │
│ manual ON/OFF            │
│ monitor-only session     │
└────────────┬─────────────┘
             │
             │ Shelly local RPC
             ▼
┌──────────────────────────┐
│ Shelly Plug S Gen3       │
│                          │
│ Relay                    │
│ V / A / W / Wh / Temp    │
└────────────┬─────────────┘
             │
             ▼
      VinFast charger
             │
             ▼
          Vehicle
```

**Step 8 kết thúc tại đây. Không thêm automatic cutoff.**
