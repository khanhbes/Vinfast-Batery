# VinFast Battery — Smart Charge Cloud-First Implementation Plan

## 0. Thông tin tài liệu

- Repository: `https://github.com/khanhbes/Vinfast-Batery`
- Nhánh đã phân tích: `feature/ai-target-charging-uiux`
- Commit tham chiếu khi phân tích: `89d124c`
- Đối tượng sử dụng tài liệu: coding agent, reviewer, QA và người triển khai backend
- Mục tiêu: biến Smart Charge thành tính năng cực kỳ đơn giản cho người dùng phổ thông, vẫn giữ chế độ thiết lập nâng cao hiện tại

> Lưu ý quan trọng: tại thời điểm phân tích, nhánh `main` chưa chứa code Shelly. Toàn bộ phần Smart Charge mới nằm trên `feature/ai-target-charging-uiux`. Agent không được triển khai tiếp trên `main` rồi vô tình bỏ mất các thay đổi của nhánh feature.

---

## 1. Kết quả sản phẩm cần đạt

### 1.1 Trải nghiệm hằng ngày

Sau lần kết nối thiết bị đầu tiên, người dùng chỉ cần:

1. Mở ứng dụng VinFast Battery.
2. Vào **Sạc thông minh**.
3. Xem mức pin hiện tại đã được app điền sẵn.
4. Chọn mức pin muốn đạt, ví dụ `80%`, `90%` hoặc `100%`.
5. Nhấn **Bắt đầu sạc & tự ngắt**.
6. Xem AI dự đoán thời lượng và giờ ngắt.
7. Xác nhận một lần.

Kết quả:

- Backend gọi AI dự đoán thời gian.
- Backend gửi lệnh `ON + toggle_after` tới Shelly Cloud.
- Timer tự ngắt được cài trực tiếp trên Shelly.
- App và backend đọc lại để xác minh relay đã ON và timer đã được arm.
- Người dùng có thể đóng app, chuyển sang 4G hoặc Wi-Fi khác.
- Shelly vẫn tự OFF khi timer kết thúc, miễn thiết bị vẫn được cấp điện.
- Người dùng có thể bật/tắt từ xa qua app khi Shelly còn kết nối Internet.

### 1.2 Trải nghiệm thiết lập

Ứng dụng phải có hai chế độ:

#### Chế độ A — Kết nối dễ, mặc định và được khuyến nghị

- Không nhập Cloud Host.
- Không sao chép Authorization Key.
- Không nhập Device ID thủ công.
- Không nhập IP LAN.
- Không yêu cầu DHCP reservation.
- Không yêu cầu tắt Client Isolation.
- Người dùng chỉ kết nối Shelly vào Wi-Fi một lần và cấp quyền cho tài khoản/app.
- Backend giữ liên kết thiết bị và điều khiển qua Shelly Cloud.

#### Chế độ B — Thiết lập nâng cao

Giữ khả năng hiện tại cho người dùng kỹ thuật:

- Cloud Host.
- Cloud Authorization Key.
- Device ID.
- LAN discovery hoặc IP/hostname `.local`.
- Digest SHA-256 local password.
- Cloud-first, LAN fallback.
- Safe boot và bài test không tải.

Chế độ nâng cao phải nằm sau nút **Thiết lập nâng cao**, không xuất hiện trong luồng chính.

---

## 2. Sự thật kỹ thuật và giới hạn bắt buộc

### 2.1 Server có thể làm gì?

Server có thể:

- xác thực người dùng bằng Firebase;
- liên kết người dùng với Shelly thuộc quyền sở hữu của họ;
- gọi AI;
- gửi lệnh ON/OFF qua Shelly Cloud;
- gửi `toggle_after` để cài timer trên thiết bị;
- đọc trạng thái relay, công suất, điện áp, dòng điện, nhiệt độ và timer;
- lưu phiên sạc, lịch sử và audit log;
- đồng bộ trạng thái giữa nhiều điện thoại;
- gửi push notification;
- gửi OFF dự phòng ở thời điểm kết thúc;
- điều khiển khi điện thoại dùng 4G hoặc Wi-Fi khác.

### 2.2 Server không thể làm gì?

Server không thể cấu hình Wi-Fi cho một Shelly đang hoàn toàn Offline, vì thiết bị chưa có đường ra Internet và đang nằm sau router/NAT của người dùng.

Các thao tác sau vẫn cần thực hiện cục bộ một lần:

- chọn Wi-Fi nhà người dùng;
- nhập mật khẩu Wi-Fi;
- gửi thông tin Wi-Fi xuống Shelly bằng BLE/AP;
- hoặc thực hiện bước này bằng Shelly Smart Control.

Server cũng không thể:

- tắt Client Isolation trên router của người dùng;
- tạo DHCP reservation trên router của người dùng;
- điều khiển từ xa khi chính Shelly đã mất Wi-Fi/Internet;
- biết SOC thật của pin nếu không có dữ liệu BMS/vehicle API.

### 2.3 Cam kết SOC phải trung thực

Shelly chỉ đo điện ở phía AC. Nó không đọc trực tiếp SOC trong pin xe.

Vì vậy UI và dữ liệu phải dùng:

- `SOC ước tính`;
- `Dự kiến đạt ~80%`;
- `AI dự kiến ngắt lúc 22:40`.

Không được dùng câu khẳng định `Sẽ đạt chính xác 80%` nếu chưa có dữ liệu BMS thật.

### 2.4 Nguồn sự thật cho tự ngắt

Timer trên Shelly là nguồn sự thật cuối cùng cho phiên sạc.

Không được dùng các thành phần sau làm lớp ngắt duy nhất:

- timer Dart trong Flutter;
- Android background service;
- push notification;
- scheduler chỉ chạy trên server;
- thời gian hiển thị trên UI.

Server scheduler chỉ là lớp OFF dự phòng. Nếu backend chết sau khi timer đã arm thành công, Shelly vẫn phải tự OFF.

---

## 3. Đánh giá code hiện tại

### 3.1 Thành phần có thể tái sử dụng

- `app/lib/data/services/smart_charger_service.dart`
  - Cloud-first, LAN fallback.
  - Arm `toggle_after`.
  - Readback tối đa 10 giây.
  - OFF best-effort qua Cloud và LAN.
  - Hiệu chỉnh timer từ công suất thực.
- `app/lib/data/services/shelly_clients.dart`
  - Shelly Cloud Control API v2.
  - Rate limit một request/giây trong client.
  - LAN RPC.
  - Digest SHA-256.
- `app/lib/features/smart_charging/shelly_setup_screen.dart`
  - Có thể giữ làm màn thiết lập nâng cao.
- `app/lib/features/ai/controllers/smart_charging_controller.dart`
  - Có state machine, polling và thao tác start/stop.
- `app/lib/features/ai/smart_charging_control_screen.dart`
  - Có preview, active session, countdown, status và emergency OFF.
- `app/lib/data/services/charging_prediction_adapter.dart`
  - Gọi AI và physics fallback.
- `smart_charger_gateway/`
  - Giữ làm công cụ legacy/diagnostic, không dùng làm dependency bắt buộc của app.

### 3.2 Vấn đề cần sửa

1. Màn setup yêu cầu người dùng nhập quá nhiều thông tin kỹ thuật.
2. Flutter đang giữ Cloud Authorization Key trên từng điện thoại.
3. Hồ sơ Shelly không đồng bộ giữa các điện thoại.
4. Active session lưu trong `SharedPreferences`, không phải server.
5. `getSessionHistory()` hiện trả danh sách rỗng.
6. `SmartChargerService.isConfigured` luôn trả `true` để tương thích, không phản ánh cấu hình thật.
7. Default `hardDeadlineAt = now + 2 giờ` có thể cắt sớm hơn ETA AI dù người dùng chỉ muốn đạt SOC mục tiêu.
8. Màn hình chính vẫn hiển thị current SOC slider, deadline, chiến lược và nhiều khái niệm nâng cao.
9. Rate limiter đang nằm trong từng instance Flutter; nhiều điện thoại có thể cùng gọi quá giới hạn Cloud.
10. `turnOn()` ưu tiên Cloud nhưng chưa có cùng chiến lược fallback rõ ràng như OFF trong chế độ nâng cao.
11. Nhánh `main` chưa có phần Smart Charge mới.

---

## 4. Kiến trúc mục tiêu

```text
Flutter App
   |
   | Firebase ID token
   v
VinFast Battery Backend (Flask)
   |-- AI prediction service
   |-- Smart charging session service
   |-- Shelly device ownership
   |-- Per-device rate limiter
   |-- Audit log / Firestore
   |-- Push notification
   |
   | HTTPS / consent token
   v
Shelly Cloud
   |
   v
Shelly Plug S Gen3
   |-- Relay ON/OFF
   |-- Power meter
   |-- Device-native toggle_after timer
   v
VinFast charger
```

### 4.1 Hai transport mode

Backend và Flutter phải hiểu hai mode:

```text
server_cloud   = mặc định, backend điều khiển qua Shelly Cloud
advanced_direct = Flutter điều khiển Cloud/LAN theo cấu hình hiện tại
```

Không được chạy đồng thời cả hai mode cho cùng một phiên.

Không cho phép đổi mode khi đang có active session.

### 4.2 Provider abstraction trên backend

Tạo interface chung:

```python
class ShellyControlProvider(Protocol):
    def list_devices(...): ...
    def get_status(...): ...
    def turn_on_with_timer(...): ...
    def turn_off(...): ...
    def verify_timer(...): ...
    def revoke(...): ...
```

Các implementation:

```text
IntegratorShellyProvider       # production nhiều người dùng
LegacyCloudControlProvider     # pilot/dev hoặc một tài khoản
FakeShellyProvider             # test
```

Flutter không được biết provider cụ thể khi dùng `server_cloud`.

---

## 5. Lựa chọn Shelly API

### 5.1 Production nhiều người dùng

Sử dụng Shelly Integrator API theo mô hình consent:

1. Người dùng nhấn **Kết nối tài khoản Shelly**.
2. Backend tạo `state` ngẫu nhiên, gắn Firebase UID và TTL.
3. App mở trang cấp quyền chính thức của Shelly.
4. Người dùng đăng nhập Shelly và chọn thiết bị được chia sẻ.
5. Shelly callback về backend.
6. Backend xác minh `state`, lưu device binding và quyền điều khiển.
7. Người dùng có thể thu hồi quyền sau này.

Điều kiện chặn:

- Phải đăng ký integrator account/license với Shelly.
- Không giả lập OAuth/consent bằng cách thu mật khẩu Shelly.
- Không dùng một Authorization Key toàn quyền cho nhiều tài khoản độc lập.

### 5.2 Pilot hoặc tài khoản cá nhân

Trong lúc chờ Integrator API:

- Cho phép `LegacyCloudControlProvider` sau feature flag.
- Chỉ dùng cho thiết bị/tài khoản được kiểm soát trong pilot.
- Key phải nằm trong secret store/KMS hoặc biến môi trường, không nằm trong source code.
- Không trả key xuống app.
- Không ghi query string chứa `auth_key` vào log.

### 5.3 Advanced direct

Giữ API v2 hiện tại trong Flutter cho người dùng tự setup.

Các trường Cloud Host, Authorization Key, Device ID, LAN IP và local password tiếp tục lưu bằng `flutter_secure_storage`.

Đây là compatibility mode, không phải luồng mặc định cho người dùng phổ thông.

---

## 6. Thiết kế onboarding

### 6.1 Setup Hub mới

Thay việc mở thẳng `ShellySetupScreen` bằng `SmartChargerSetupHubScreen`:

```text
Kết nối bộ sạc thông minh

[ KẾT NỐI DỄ — KHUYẾN NGHỊ ]
Điều khiển từ mọi nơi qua Shelly Cloud

[ Thiết lập nâng cao ]
Cloud key, LAN fallback và cấu hình kỹ thuật
```

### 6.2 Easy Connect giai đoạn đầu

Luồng phát hành sớm:

1. App giải thích đây là thiết lập một lần.
2. Nếu Shelly chưa có Wi-Fi, hướng dẫn mở Shelly Smart Control để thêm thiết bị.
3. Quay lại app VinFast Battery.
4. Nhấn **Kết nối tài khoản Shelly**.
5. Thực hiện consent.
6. Hiển thị danh sách đúng loại `Shelly Plug S Gen3`.
7. Người dùng chọn thiết bị.
8. Backend đọc trạng thái, model, generation và power meter.
9. Backend lưu binding.
10. App hiển thị `Đã kết nối`.

Không yêu cầu nhập IP LAN trong Easy Connect.

### 6.3 Native Wi-Fi provisioning trong app

Đây là phase riêng sau khi core cloud flow ổn định:

1. Viết spike xác minh secure provisioning của firmware Shelly hiện tại.
2. Ưu tiên giao thức/tài liệu chính thức.
3. Không thêm package Flutter bỏ bảo trì chỉ để né việc viết platform channel.
4. App xin quyền Bluetooth/Nearby Devices đúng thời điểm.
5. Quét thiết bị unprovisioned.
6. Người dùng chọn Wi-Fi 2.4 GHz và nhập password.
7. Gửi credentials cục bộ qua BLE/AP.
8. Không gửi Wi-Fi password lên backend.
9. Xóa password khỏi memory/state sau khi hoàn tất.
10. Chờ Shelly online rồi chuyển sang consent flow.

Fallback nếu native provisioning thất bại:

- mở Shelly Smart Control;
- hoặc kết nối AP `Shelly...` và mở `192.168.33.1`;
- quay lại app bằng deep link/resume.

### 6.4 Advanced Setup

Đổi tên màn hiện tại thành `ShellyAdvancedSetupScreen` hoặc giữ class nhưng đổi route/label.

Giữ:

- Cloud profile;
- mDNS discovery;
- LAN address;
- local auth;
- test connection;
- configure safe boot;
- no-load test.

Thêm cảnh báo rõ:

> Chế độ nâng cao lưu hồ sơ trên điện thoại này. Điều khiển từ xa qua Cloud vẫn hoạt động; LAN chỉ hoạt động khi điện thoại và Shelly có thể liên lạc trong cùng mạng.

---

## 7. Backend implementation

### 7.1 Tổ chức file

Không tiếp tục nhồi toàn bộ logic vào `web/server.py`.

Đề xuất:

```text
web/
  shelly/
    __init__.py
    routes.py
    models.py
    service.py
    session_repository.py
    device_repository.py
    rate_limiter.py
    crypto.py
    providers/
      __init__.py
      base.py
      integrator.py
      legacy_cloud.py
      fake.py
  smart_charge_worker.py
```

`server.py` chỉ đăng ký Blueprint và dependency.

### 7.2 Environment variables

```text
SHELLY_PROVIDER=integrator|legacy|fake
SHELLY_INTEGRATOR_TAG=
SHELLY_INTEGRATOR_TOKEN=
SHELLY_CONSENT_CALLBACK_URL=
SHELLY_CREDENTIAL_ENCRYPTION_KEY=
SHELLY_LEGACY_HOST=
SHELLY_LEGACY_AUTH_KEY=
SMART_CHARGE_MAX_MINUTES=360
SMART_CHARGE_DEFAULT_MODE=server_cloud
SMART_CHARGE_ENABLE_REMOTE_ON=true
SMART_CHARGE_ENABLE_NATIVE_PROVISIONING=false
```

Không commit giá trị thật vào Git.

### 7.3 Firestore data model

#### Device binding

```text
users/{uid}/shellyDevices/{deviceId}
```

```json
{
  "deviceId": "...",
  "displayName": "Shelly sạc xe",
  "model": "S3PL-00112EU",
  "generation": 3,
  "provider": "integrator",
  "connectionMode": "server_cloud",
  "permissions": ["read", "control"],
  "online": true,
  "powerMeterVerified": true,
  "safeBootVerified": false,
  "createdAt": "server timestamp",
  "updatedAt": "server timestamp",
  "revokedAt": null
}
```

Không lưu token/key dạng plaintext trong document này.

#### Session

```text
users/{uid}/smartChargingSessions/{sessionId}
```

```json
{
  "sessionId": "...",
  "deviceId": "...",
  "vehicleId": "...",
  "state": "arming|active|completed|cancelled|interrupted|failed",
  "startSoc": 35,
  "targetSoc": 80,
  "estimatedSoc": 35,
  "predictedMinutes": 154,
  "predictionSource": "ai_model",
  "predictionConfidence": 87,
  "aiStopAt": "...",
  "effectiveStopAt": "...",
  "absoluteSafetyStopAt": "...",
  "baselineEnergyWh": 100,
  "energyUsedWh": 0,
  "relayVerified": true,
  "timerVerified": true,
  "transport": "shelly_cloud",
  "idempotencyKey": "...",
  "createdAt": "...",
  "updatedAt": "...",
  "stoppedAt": null,
  "stopReason": null,
  "version": 1
}
```

#### Audit log

```text
users/{uid}/smartChargingAudit/{eventId}
```

Lưu command, actor, kết quả, thời gian, device ID, session ID và error code; không lưu secret.

### 7.4 API endpoints

#### Connection

```text
POST   /api/shelly/consent/start
GET    /api/shelly/consent/callback
GET    /api/shelly/devices
POST   /api/shelly/devices/{device_id}/select
GET    /api/shelly/device
DELETE /api/shelly/device
```

#### Smart charging

```text
POST /api/smart-charging/preview
POST /api/smart-charging/sessions
GET  /api/smart-charging/session/current
GET  /api/smart-charging/sessions?limit=20
GET  /api/smart-charging/status
POST /api/smart-charging/on
POST /api/smart-charging/off
POST /api/smart-charging/session/{id}/stop
```

Tất cả endpoint user-facing, trừ callback có xác minh riêng, phải dùng Firebase authentication.

### 7.5 Preview API

Request:

```json
{
  "vehicleId": "...",
  "currentSoc": 35,
  "targetSoc": 80,
  "chargingMode": "standard"
}
```

Response:

```json
{
  "success": true,
  "data": {
    "previewId": "...",
    "currentSoc": 35,
    "targetSoc": 80,
    "predictedMinutes": 154,
    "predictedStopAt": "...",
    "modelSource": "ai_model",
    "confidence": 87,
    "socIsEstimated": true,
    "expiresAt": "..."
  }
}
```

Preview phải có TTL ngắn, ví dụ 10 phút. Start phải dùng preview hợp lệ thay vì để client tự gửi số phút tùy ý.

### 7.6 Start session transaction

Agent triển khai đúng thứ tự:

1. Xác thực Firebase UID.
2. Xác thực device thuộc UID.
3. Kiểm tra không có active session khác.
4. Kiểm tra `Idempotency-Key`.
5. Nạp preview và kiểm tra chưa hết hạn.
6. Kiểm tra `targetSoc > currentSoc` và `targetSoc <= 100`.
7. Kiểm tra predicted duration trong giới hạn an toàn.
8. Đọc Shelly status và xác nhận online.
9. Tạo session trạng thái `arming`.
10. Gửi `ON + toggle_after=effectiveDurationSeconds`.
11. Đợi một giây rồi đọc lại.
12. Poll readback tối đa 10 giây, tôn trọng rate limit.
13. Chỉ chuyển `active` khi:
    - relay ON;
    - timer remaining lớn hơn 0;
    - device ID đúng;
    - không có lỗi overtemperature/overpower nếu status cung cấp.
14. Nếu không xác minh được, gửi OFF best-effort.
15. Đọc lại OFF nếu có thể.
16. Mark session `failed` với error code ổn định.
17. Trả session active cho app.

### 7.7 Manual ON/OFF

#### OFF

- Cho phép người dùng gửi OFF ngay từ màn active.
- Gửi OFF qua provider.
- Đọc lại tối đa ba lần.
- Chỉ hiển thị `Đã ngắt` khi relay OFF được xác minh.
- Nếu không xác minh được, hiển thị hướng dẫn ngắt vật lý.

#### ON

- Yêu cầu confirmation.
- Không bật vô thời hạn.
- Gắn absolute safety timer theo giới hạn đã kiểm chứng.
- Không cho ON nếu active session tồn tại hoặc thiết bị báo lỗi an toàn.
- Không tự ON lại sau reboot/reconnect.

### 7.8 Worker và OFF dự phòng

Device timer vẫn là nguồn sự thật.

Worker thực hiện:

- theo dõi active sessions;
- tại `effectiveStopAt`, gửi OFF dự phòng;
- reconcile relay/timer;
- cập nhật năng lượng;
- đóng session;
- gửi notification;
- lấy distributed lease để tránh nhiều instance cùng điều khiển;
- không vượt rate limit theo device/provider.

Nếu worker restart:

1. Nạp tất cả active/arming sessions.
2. Đọc trạng thái thiết bị.
3. Nếu relay OFF gần mốc dự kiến, mark completed.
4. Nếu relay ON và timer còn, giữ active.
5. Nếu relay ON nhưng timer mất, gửi OFF an toàn.
6. Nếu không liên lạc được, không gửi ON và tạo cảnh báo retryable.

---

## 8. Flutter implementation

### 8.1 Files mới

```text
app/lib/data/services/server_smart_charger_service.dart
app/lib/data/models/smart_charger_binding.dart
app/lib/data/models/smart_charge_preview.dart
app/lib/features/smart_charging/smart_charger_setup_hub_screen.dart
app/lib/features/smart_charging/easy_shelly_connect_screen.dart
app/lib/features/smart_charging/advanced_shelly_setup_screen.dart
app/lib/features/smart_charging/widgets/target_soc_picker.dart
app/lib/features/smart_charging/widgets/connection_mode_badge.dart
```

### 8.2 Repository abstraction

Tạo interface Flutter:

```dart
abstract interface class SmartChargerRepository {
  Future<SmartChargerBinding?> getBinding();
  Future<SmartChargerStatus> getStatus();
  Future<SmartChargingPlanPreview> createPreview(...);
  Future<SmartChargingSession> startSession(...);
  Future<SmartChargingSession?> getCurrentSession();
  Future<List<SmartChargingSession>> getHistory();
  Future<void> turnOff();
  Future<void> turnOnWithSafetyTimer(...);
}
```

Implementation:

```text
ServerSmartChargerRepository   # default
DirectShellyRepository         # adapter quanh SmartChargerService hiện tại
FakeSmartChargerRepository     # tests
```

### 8.3 Controller

Refactor `SmartChargingController`:

- nhận repository qua dependency injection;
- đọc connection mode;
- default lấy session từ backend;
- không dùng local `SharedPreferences` làm nguồn sự thật trong server mode;
- history phải lấy từ backend;
- giữ local countdown chỉ để hiển thị;
- định kỳ reconcile với backend;
- không để lỗi status polling xóa active session đã biết;
- tránh request chồng nhau;
- app resume phải refresh ngay;
- app background không cần giữ timer sống để ngắt điện.

### 8.4 Màn Smart Charging đơn giản

Màn mặc định:

```text
SẠC THÔNG MINH

Shelly sạc xe             Online
Pin hiện tại              ~35%

Bạn muốn sạc đến mức nào?
[ 80% ] [ 90% ] [ 100% ]
[ slider nếu cần ]

[ DỰ ĐOÁN VỚI AI ]
```

Sau preview:

```text
AI dự kiến              2 giờ 34 phút
Tự ngắt khoảng          22:40
Mức pin dự kiến         ~80%

[ BẮT ĐẦU SẠC & TỰ NGẮT ]
```

Trong active session:

```text
ĐANG SẠC
Timer trên Shelly       02:33:14
Công suất               387 W
Pin dự kiến             ~52%
Tự ngắt lúc             22:40

[ NGẮT NGUỒN NGAY ]
```

### 8.5 Current SOC

- Tự lấy từ vehicle hiện tại như code đang làm.
- Không bắt người dùng nhập lại trên luồng chính.
- Hiển thị nút nhỏ **Chỉnh mức pin hiện tại** nếu dữ liệu cũ hoặc không chính xác.
- Nếu SOC không có, mới yêu cầu nhập current SOC trước target SOC.
- Ghi timestamp của SOC để AI biết độ mới.

### 8.6 Target SOC

- Preset `80%`, `90%`, `100%`.
- Cho phép slider hoặc nhập số trong `Nâng cao`.
- Không cho target nhỏ hơn hoặc bằng current SOC.
- Không cho target ngoài 1–100.

### 8.7 Deadline và strategy

- Không đặt `now + 2 giờ` làm hard deadline mặc định cho simple mode.
- Simple mode dùng `target_soc` và absolute safety cap.
- Deadline, strategy và charging mode chuyển vào `Tùy chọn nâng cao`.
- Nếu người dùng không mở advanced, deadline không được cắt ngắn ETA AI một cách âm thầm.

### 8.8 Setup routing

Trạng thái:

```text
not_connected
connecting
connected_server_cloud
connected_advanced_direct
revoked
offline
needs_reauthentication
```

Nếu chưa kết nối, nút Start đổi thành **Kết nối Shelly**.

Nếu Cloud offline nhưng AI hoạt động, vẫn cho preview; không cho start cho tới khi Shelly online.

---

## 9. AI và hiệu chỉnh

### 9.1 Prediction

Tái sử dụng endpoint AI hiện tại nhưng backend Smart Charge phải gọi nội bộ và chuẩn hóa kết quả.

Input tối thiểu:

- vehicle ID/model;
- current SOC;
- target SOC;
- battery capacity;
- ambient temperature nếu có;
- charging mode;
- lịch sử charging curve nếu có.

Output:

- predicted duration;
- model source/version;
- confidence;
- fallback reason;
- estimated stop time.

### 9.2 Physics fallback

Giữ dung lượng mặc định hiện tại `2400 Wh` cho Feliz nếu chưa có catalog chính xác.

Không quay lại công thức `72 kWh` cũ.

Fallback:

```text
requiredWh = capacityWh * (targetSoc - currentSoc) / 100
minutes = requiredWh / (powerW * efficiency) * 60
```

### 9.3 Power calibration

- Dùng Shelly `apower` sau khi sạc ổn định.
- Thu tối thiểu số mẫu đã thống nhất trước khi rearm.
- Không rearm quá thường xuyên.
- Không vượt absolute safety stop.
- Nếu calibration thất bại, giữ timer cũ.
- Mỗi lần rearm phải readback timer.

### 9.4 Chính xác SOC

Cho tới khi có BMS:

- `estimatedSoc` được tính từ năng lượng AC với efficiency;
- không dùng estimated SOC đơn độc để gửi OFF sớm;
- thời gian AI/timer vẫn là quyết định chính;
- thu dữ liệu để cải thiện model sau này.

---

## 10. Security

### 10.1 Authentication và ownership

- Mọi endpoint phải verify Firebase ID token.
- Device binding gắn với Firebase UID.
- Mọi command phải kiểm tra ownership.
- Không tin device ID do client gửi nếu không khớp binding.

### 10.2 Consent flow

- `state` ngẫu nhiên đủ mạnh.
- TTL ngắn.
- One-time use.
- Gắn với UID và app session.
- Xác minh callback.
- Chống CSRF/replay.
- Hỗ trợ revoke.

### 10.3 Secrets

- Không commit secret.
- Không lưu plaintext trong Firestore.
- Mã hóa at rest bằng secret manager/KMS.
- Redact Authorization, token, auth key và Wi-Fi password khỏi log/crash report.
- Không gửi Wi-Fi password lên server trong native provisioning.
- Không trả Shelly token về Flutter trong server mode.

### 10.4 Network

- Không expose IP Shelly hoặc port 80 ra Internet.
- Không port-forward FastAPI gateway.
- LAN fallback chỉ nhận private IP/`.local` như hiện tại.
- Backend chỉ gọi HTTPS Shelly Cloud host allowlist.
- Chống SSRF; không nhận arbitrary URL từ Flutter.

### 10.5 Rate limiting

- Queue command/status theo device.
- Tôn trọng giới hạn Shelly Cloud.
- Manual OFF có ưu tiên cao nhưng vẫn không tạo request storm.
- Poll UI qua backend với cache ngắn thay vì mỗi điện thoại poll trực tiếp Cloud.

---

## 11. Safety rules

1. Device timer là nguồn sự thật.
2. Start chỉ thành công sau readback timer.
3. Không xác minh được timer thì gửi OFF.
4. OFF phải readback.
5. Không tự ON khi app startup.
6. Không tự ON sau reconnect.
7. Không tự ON sau server restart.
8. Safe boot phải đặt `initial_state=off` khi kênh/provider hỗ trợ.
9. Nếu safe boot không thể cấu hình qua Cloud provider, thực hiện một lần trong advanced/local commissioning.
10. Không scheduled auto-ON mặc định; người dùng phải xác nhận **Bắt đầu sạc**.
11. Manual ON phải có safety timer.
12. Giữ absolute cap hiện tại 6 giờ cho tới khi test phần cứng chứng minh cần thay đổi.
13. Nếu mất điện/reboot Shelly, ưu tiên OFF an toàn.
14. Nếu Shelly Offline trước khi arm, không bắt đầu session.
15. Nếu Shelly mất Internet sau khi timer đã arm, không hủy timer cục bộ.
16. Nếu nhiệt độ/công suất vượt giới hạn phần cứng, gửi OFF và tạo cảnh báo.
17. Không tự suy luận pin đã đạt chính xác target chỉ từ công suất thấp.

---

## 12. Migration

### 12.1 Branch

1. Tạo nhánh triển khai mới từ `feature/ai-target-charging-uiux` hoặc merge nhánh này vào integration branch trước.
2. Không bắt đầu từ `main` hiện tại nếu chưa đưa các file Shelly vào.
3. Chạy toàn bộ test trước khi refactor để có baseline.
4. Sau khi hoàn thành, merge có kiểm soát về `main`.

### 12.2 Existing advanced users

Nếu secure storage có `smart_charger.shelly_profile.v1`:

- không tự động upload Cloud Key lên server;
- hiển thị `Bạn đang dùng thiết lập nâng cao`;
- cho phép tiếp tục dùng;
- đề nghị chuyển sang Kết nối dễ bằng consent;
- chỉ xóa profile local sau khi server binding đã được xác minh và người dùng đồng ý.

### 12.3 Session migration

- Session local đang active phải được reconcile trước khi đổi mode.
- Không đổi mode giữa active session.
- Lịch sử local cũ nếu có có thể upload dưới dạng `legacyImported=true`, nhưng không upload secret.

---

## 13. Testing plan

### 13.1 Backend unit tests

- Firebase ownership.
- Consent state TTL/replay.
- Provider mapping.
- Rate limiter.
- Preview validation.
- Idempotent start.
- Active-session conflict.
- Timer readback success.
- Timer readback failure dẫn tới OFF.
- Manual OFF readback.
- Worker recovery.
- Token revoked.
- Device offline.
- AI failure và physics fallback.
- Secret redaction.

### 13.2 Backend contract tests

Fake provider mô phỏng:

- normal online device;
- device offline;
- 401/403;
- 429;
- relay ON nhưng timer missing;
- timer armed;
- OFF rejected;
- delayed status;
- malformed Cloud response.

### 13.3 Flutter unit tests

- repository selection theo connection mode;
- simple target validation;
- current SOC prefill;
- preview mapping;
- server session parsing;
- advanced adapter;
- app resume refresh;
- offline/error states;
- không xóa active session khi poll lỗi;
- không đổi mode trong active session.

### 13.4 Widget tests

- simple screen chỉ hiển thị target controls;
- advanced options mặc định đóng;
- setup hub có Easy Connect và Advanced;
- confirmation hiển thị estimated SOC warning;
- Start disabled khi chưa connect;
- Start disabled khi Shelly offline;
- emergency OFF luôn dễ thấy khi active;
- accessibility/semantics cho slider và trạng thái.

### 13.5 Manual network matrix

| Tình huống | Kết quả bắt buộc |
|---|---|
| Điện thoại và Shelly cùng Wi-Fi | Start/status/OFF hoạt động qua Cloud |
| Điện thoại chuyển sang 4G | Status và ON/OFF vẫn hoạt động |
| Điện thoại ở Wi-Fi khác | Status và ON/OFF vẫn hoạt động |
| App bị force-close sau khi arm | Shelly vẫn tự OFF |
| Điện thoại mất mạng sau khi arm | Shelly vẫn tự OFF |
| Backend restart sau khi arm | Shelly vẫn tự OFF; backend reconcile sau restart |
| Shelly mất Internet sau khi arm nhưng còn điện | Timer đã arm tiếp tục chạy |
| Shelly Offline trước khi Start | Không bật relay; hiển thị lỗi rõ |
| Cloud token bị revoke | Yêu cầu kết nối lại, không fallback nguy hiểm |
| Người dùng nhấn Start hai lần | Chỉ có một session/lệnh |
| Client Isolation bật | Server Cloud mode vẫn hoạt động; LAN advanced có thể không hoạt động |
| IP Shelly đổi | Server Cloud mode không bị ảnh hưởng |
| Power cycle Shelly | Không tự ON lại |
| Manual OFF từ 4G | Relay OFF được readback hoặc cảnh báo khẩn |

### 13.6 Hardware acceptance

- Test không tải trước.
- Test với charger thật dưới giám sát.
- Kiểm tra 12A/2500W limit và tải thực.
- Kiểm tra nhiệt độ plug.
- Kiểm tra timer 1 phút, 5 phút và phiên dài.
- Kiểm tra mất Internet sau khi arm.
- Kiểm tra power cycle.
- Không bật automatic cutoff production trước khi các test trên đạt.

---

## 14. Rollout phases

### Phase 0 — Baseline và external gate

- [ ] Chốt base branch.
- [ ] Chạy test hiện tại.
- [ ] Đăng ký Shelly Integrator access/license.
- [ ] Xác minh consent callback và quyền control.
- [ ] Viết secure provisioning spike.
- [ ] Chốt server secret storage.

Exit criteria:

- Có provider strategy được phê duyệt.
- Không dựa vào giả định chưa xác minh về Shelly OAuth/provisioning.

### Phase 1 — Backend domain và fake provider

- [ ] Tạo Blueprint/module.
- [ ] Tạo models/repositories.
- [ ] Tạo Firebase ownership.
- [ ] Tạo preview/start/status/on/off APIs.
- [ ] Tạo FakeShellyProvider.
- [ ] Tạo idempotency/rate limiter.
- [ ] Tạo tests.

Exit criteria:

- Luồng đầy đủ chạy bằng fake provider.

### Phase 2 — Shelly cloud provider

- [ ] Integrator provider hoặc legacy pilot provider.
- [ ] Status mapping.
- [ ] ON + toggle_after.
- [ ] Readback 10 giây.
- [ ] OFF verification.
- [ ] Token revoke/reconnect.
- [ ] Audit log.

Exit criteria:

- Điều khiển Shelly thật qua server từ mạng ngoài.
- App không cần LAN hoặc laptop gateway.

### Phase 3 — Flutter simple mode

- [ ] Server repository.
- [ ] Setup Hub.
- [ ] Target-only UI.
- [ ] Current SOC prefill.
- [ ] Preview/start/active/stop.
- [ ] Server session/history.
- [ ] App resume/reconnect.

Exit criteria:

- Người dùng đã kết nối chỉ cần chọn target và xác nhận Start.

### Phase 4 — Easy Connect consent

- [ ] Consent start/callback.
- [ ] Device selection.
- [ ] Binding status.
- [ ] Revoke/reconnect.
- [ ] Deep link/app resume.

Exit criteria:

- Không cần nhập host/key/device ID trong luồng mặc định.

### Phase 5 — Advanced compatibility

- [ ] Giữ setup hiện tại.
- [ ] Di chuyển vào Advanced.
- [ ] Direct Cloud/LAN adapter.
- [ ] Safe boot/no-load test.
- [ ] Migration prompt.
- [ ] Không đổi mode khi active.

Exit criteria:

- Người dùng kỹ thuật vẫn dùng được toàn bộ tính năng hiện tại.

### Phase 6 — Native Wi-Fi provisioning

- [ ] Secure provisioning spike đạt.
- [ ] BLE/AP flow.
- [ ] Không gửi Wi-Fi password lên server.
- [ ] Retry và official-app fallback.
- [ ] Test nhiều firmware/Android version/router.

Exit criteria:

- Người dùng mới có thể setup từ app VinFast Battery mà không nhập thông tin Cloud kỹ thuật.

### Phase 7 — Production hardening

- [ ] Worker/recovery.
- [ ] Push notifications.
- [ ] Monitoring/alerting.
- [ ] Network matrix.
- [ ] Hardware acceptance.
- [ ] Shadow rollout.
- [ ] Staged automatic cutoff rollout.

---

## 15. Definition of Done

Tính năng chỉ hoàn thành khi:

- [ ] Code Smart Charge đã được đưa vào nhánh phát hành đúng cách.
- [ ] Simple mode không yêu cầu Cloud Host, key, Device ID hoặc LAN IP.
- [ ] Advanced mode vẫn tồn tại.
- [ ] Backend xác thực Firebase và ownership.
- [ ] Backend có provider abstraction.
- [ ] Multi-user production không dùng global Cloud key của người dùng.
- [ ] Start dùng AI preview do server phát hành.
- [ ] Start gửi device-native timer.
- [ ] Timer được readback trước khi báo thành công.
- [ ] App đóng hoặc chuyển sang 4G không làm mất auto cutoff.
- [ ] Remote ON/OFF hoạt động qua Shelly Cloud.
- [ ] IP LAN thay đổi không ảnh hưởng simple mode.
- [ ] Server session/history đồng bộ giữa thiết bị.
- [ ] OFF được readback.
- [ ] Duplicate tap không tạo nhiều session.
- [ ] Không có secret trong Git, log hoặc Firestore plaintext.
- [ ] UI ghi rõ SOC là ước tính.
- [ ] Không có unattended auto-ON mặc định.
- [ ] Mất điện/reboot không làm Shelly tự ON.
- [ ] Flutter analyze/test đạt.
- [ ] Backend tests đạt.
- [ ] Manual network matrix đạt.
- [ ] Hardware acceptance đạt.

---

## 16. Những điều agent không được làm

- Không xóa chế độ Advanced hiện tại.
- Không tiếp tục để màn setup kỹ thuật là luồng mặc định.
- Không lưu Shelly password/Auth Key plaintext trên server.
- Không upload profile local lên server mà không có sự đồng ý.
- Không cho Flutter gửi arbitrary Shelly host tới backend.
- Không expose Shelly LAN ra Internet.
- Không dùng local FastAPI gateway làm yêu cầu bắt buộc.
- Không dùng server scheduler làm cơ chế tự ngắt duy nhất.
- Không báo Start thành công trước khi timer readback.
- Không tự ON khi app mở, reconnect hoặc server restart.
- Không hứa đạt chính xác target SOC nếu chưa có BMS.
- Không để hard deadline mặc định hai giờ âm thầm cắt ETA AI.
- Không implement multi-user production bằng một Cloud Authorization Key toàn quyền.

---

## 17. Thứ tự giao việc khuyến nghị cho coding agent

1. Baseline branch và chạy test.
2. Tạo backend provider abstraction với fake provider.
3. Tạo server session/device repositories và API.
4. Tích hợp Shelly Cloud provider thật.
5. Chứng minh remote control bằng 4G.
6. Chứng minh device timer tự OFF khi app đóng.
7. Refactor Flutter sang server repository.
8. Làm target-only UI.
9. Làm Easy Connect consent.
10. Đưa setup hiện tại vào Advanced.
11. Làm migration.
12. Làm worker/recovery/push.
13. Thực hiện native Wi-Fi provisioning sau feasibility spike.
14. Chạy test matrix và hardware acceptance.
15. Merge về `main` sau review.

---

## 18. Tài liệu kỹ thuật bắt buộc đối chiếu

- Shelly Cloud Control API v2:
  `https://shelly-api-docs.shelly.cloud/cloud-control-api/communication-v2/`
- Shelly Integrator API:
  `https://shelly-api-docs.shelly.cloud/integrator-api/`
- So sánh Cloud Control, Integrator và Fleet Manager:
  `https://kb.shelly.cloud/knowledge-base/kbuca-understanding-the-differences-between-shelly`
- Shelly Switch RPC và `toggle_after`:
  `https://shelly-api-docs.shelly.cloud/gen2/ComponentsAndServices/Switch/`
- Shelly Gen2+/Gen3 provisioning/status:
  `https://shelly-api-docs.shelly.cloud/gen2/ComponentsAndServices/Shelly/`

Agent phải kiểm tra lại tài liệu chính thức tại thời điểm implement, đặc biệt auth, consent, secure provisioning, rate limit và firmware behavior.
