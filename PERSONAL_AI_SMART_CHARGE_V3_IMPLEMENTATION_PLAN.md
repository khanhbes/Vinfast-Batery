# IMPLEMENTATION PLAN — PERSONAL AI SMART CHARGE V3
## Cá nhân hóa theo tài khoản + xe, AI/Physics Fusion, Safety, Offline Resilience, Realtime History và Minimal UX

> **Repo:** `khanhbes/Vinfast-Batery`  
> **Branch baseline:** `feature/ai-target-charging-uiux`  
> **Mục tiêu:** nâng Smart Charge từ một chức năng dự đoán thời gian + điều khiển Shelly thành một hệ thống sạc cá nhân hóa theo từng tài khoản và từng chiếc xe, học sau mỗi phiên sạc, có guardrail vật lý/safety, không mất trạng thái khi mất mạng, có lịch sử realtime và UI tối giản.

---

# 0. Các quyết định đã chốt

```text
1A  Personal Calibration Model riêng cho (ownerUid + vehicleId).
2A  AI cá nhân khóa theo (ownerUid, vehicleId).
3A  Phiên dừng giữa chừng vẫn dùng để học đoạn dữ liệu thực tế.
4A  Dừng sạc giữa chừng phải xác nhận bằng bottom sheet rõ ràng.
5A  Mất Internet nhưng LAN Shelly còn → tiếp tục phiên, giữ UI.
6A  Mất cả Internet và Shelly → giữ nguyên màn hình/state, reconnect tự động.
7A  Battery Fill Selector dạng VIÊN PIN NẰM NGANG.
8A  Khi sạc dùng animation pin đầy dần tới mức mục tiêu.
9A  Tối giản Smart Charge + Dashboard + Charge History trước.
    Nội dung phải ngắn, dễ hiểu, bỏ dấu "~" trên toàn UI người dùng.
10A ETA cuối = weighted fusion giữa Base AI + Physics + Personal AI.
11A effectiveCapacityWh = nominalCapacityWh × SoH, sau đó hiệu chỉnh bằng dữ liệu Wh thực.
12A Personalization theo stage:
    0–2 phiên = Base AI + Physics
    3–9 phiên = thêm Personal Calibration
    10+ phiên = Personal AI có trọng số cao hơn.
13A Nếu AI lệch vật lý quá lớn → giảm trọng số nguồn bất thường + clamp.
14A Safety bất thường → gateway tự OFF + verify OFF + log + notification.
15A Threshold safety đặt ở gateway/server config, user thường không chỉnh.
16A Nếu có BMS/API xe → tách batteryTemp và ShellyTemp, không đánh đồng.
17A Firebase auth + ownership + idempotency/version + bảo mật đầy đủ.
    Toàn bộ lịch sử phải truy cập lại được, không bị mất do limit hoặc overwrite.
18A Lịch sử có LIVE card realtime nằm trên cùng, khi kết thúc chuyển chính record đó thành terminal.
19A UI poll nhanh; telemetry persist 15–30 giây hoặc theo significant change.
20A Reset năng lượng theo từng SESSION bằng baseline, không reset lifetime meter của Shelly.
21A Khi chuyển màn vẫn có persistent charging pill để quay về Smart Charge.
22A Khi reconnect phải reconcile local + gateway + Shelly + Firestore;
    gateway/Shelly là nguồn sự thật cho relay/timer.
```

---

# 1. Hiện trạng repo cần giữ lại và tận dụng

## 1.1 Smart Charging Controller

File hiện tại:

```text
app/lib/features/ai/controllers/smart_charging_controller.dart
```

Đã có:

- polling charger status mỗi 5 giây;
- polling current session mỗi 3 giây;
- countdown mỗi 1 giây;
- `SmartChargingViewPhase`;
- session recovery khi app resume;
- AI preview;
- start/stop;
- readback relay;
- calibration power;
- history;
- notification;
- timer Shelly.

Không viết lại controller từ đầu.

Phải refactor controller thành state machine bền vững hơn nhưng giữ các hành vi an toàn hiện có.

## 1.2 Smart Charge UI

File hiện tại:

```text
app/lib/features/ai/smart_charging_control_screen.dart
```

Hiện UI vẫn có nhiều text kỹ thuật:

```text
SOC
Relay ON/OFF
Cloud/LAN
Model
Prediction source
Timer trên thiết bị
~
```

và target hiện đang dùng quick choice.

Plan mới phải thay UI chính bằng:

```text
Trạng thái kết nối
Horizontal Battery Fill Selector
Kết quả dự kiến
Battery charging animation
Target rõ ràng
Dừng sạc có xác nhận
```

Metadata kỹ thuật chỉ nằm trong Debug/Developer Detail.

## 1.3 Session model

File:

```text
app/lib/data/models/smart_charging_session.dart
```

Đã có:

```text
startSoc
targetSoc
predictedMinutes
estimatedCapacityWh
baselineEnergyWh
energyUsedWh
estimatedSoc
modelVersion
predictionConfidence
stopReason
relayVerified
timerVerified
```

Mở rộng model hiện tại để chứa:

```text
ownerUid
personalizationStage
baseAiMinutes
physicsMinutes
personalMinutes
finalMinutes
fusionWeights
effectiveCapacityWh
nominalCapacityWh
stateOfHealth
batteryTempC
shellyTempC
avgPowerW
peakPowerW
avgVoltageV
avgCurrentA
userStopReason
trainingEligible
trainingState
```

## 1.4 Energy session hiện đã có baseline

Gateway:

```text
smart_charger_gateway/smart_charging.py
```

đã có logic tương đương:

```text
sessionEnergyWh
=
Shelly lifetime energy meter
-
baselineEnergyWh
```

Đây là cơ chế đúng.

KHÔNG reset bộ đếm lifetime energy của Shelly sau mỗi phiên.

Chỉ reset UI/session về:

```text
0 Wh
```

khi phiên mới bắt đầu.

## 1.5 Lịch sử hiện chưa realtime

File:

```text
app/lib/data/services/shelly_charge_log_service.dart
```

hiện chỉ ghi terminal session.

Phải chuyển thành:

```text
createLiveSession()
updateLiveSession()
finalizeSession()
```

dùng cùng một `sessionId`.

## 1.6 Battery/vehicle data

File:

```text
app/lib/data/models/vehicle_model.dart
```

đã có:

```text
currentBattery
stateOfHealth
vinfastModelId
vinfastModelName
```

File fallback spec:

```text
app/assets/vinfast_specs_fallback.json
```

đã có:

```text
nominalCapacityWh
nominalCapacityAh
nominalVoltageV
maxChargePowerW
```

cho nhiều model VinFast.

Plan phải dùng spec thật theo model xe, không giữ fallback toàn hệ thống là `2400 Wh`.

`2400 Wh` chỉ được dùng khi không thể resolve spec và phải được đánh dấu data quality thấp.

---

# 2. Kiến trúc cuối cùng

```text
                    ┌───────────────────────┐
                    │   Firebase Account    │
                    │       ownerUid        │
                    └───────────┬───────────┘
                                │
                                ▼
                     ┌──────────────────────┐
                     │   Selected Vehicle   │
                     │      vehicleId       │
                     └──────────┬───────────┘
                                │
                Personal scope = ownerUid + vehicleId
                                │
        ┌───────────────────────┼─────────────────────────┐
        │                       │                         │
        ▼                       ▼                         ▼
┌───────────────┐      ┌──────────────────┐      ┌──────────────────┐
│ Base AI Model │      │ Physical Model   │      │ Personal Model   │
│ charging_time │      │ Capacity/Power   │      │ Calibration      │
└──────┬────────┘      └────────┬─────────┘      └────────┬─────────┘
       │                        │                         │
       └────────────────────────┼─────────────────────────┘
                                ▼
                    ┌───────────────────────┐
                    │ Prediction Fusion     │
                    │ + Guardrails          │
                    └───────────┬───────────┘
                                ▼
                       Final Charging ETA
                                │
                                ▼
                    ┌───────────────────────┐
                    │ Smart Charger Gateway │
                    │ Shelly timer + safety │
                    └───────────┬───────────┘
                                ▼
                         Shelly Plug
                                │
                  telemetry / session result
                                │
                                ▼
                    ┌──────────────────────┐
                    │ ChargeLogs + curves │
                    └──────────┬───────────┘
                               ▼
                   Personal Calibration Update
```

---

# 3. P0 — Security trước Personal AI

## 3.1 Personal AI key

Không dùng:

```text
vehicleId
```

làm khóa duy nhất.

Dùng:

```text
(ownerUid, vehicleId)
```

Canonical key:

```text
personalProfileId = SHA256(ownerUid + ":" + vehicleId)
```

hoặc document ID ổn định tương đương ở server.

Không cho Flutter tự quyết định `ownerUid`.

Server lấy UID từ verified Firebase token.

## 3.2 Ownership check bắt buộc

Mọi endpoint personal AI phải:

```text
@require_auth
```

và verify:

```text
Vehicles/{vehicleId}.ownerUid == request._uid
```

Áp dụng:

```text
GET  /api/ai/personal/profile/<vehicleId>
POST /api/ai/personal/predict-charging-time
POST /api/ai/personal/ingest-session
POST /api/ai/train-vehicle-profile
GET  /api/ai/profile-status/<vehicleId>
GET  /api/user/charge-logs
```

Nếu xe không thuộc tài khoản:

```http
403 Forbidden
```

Không trả profile/telemetry/history của xe khác.

---

# 4. Firestore security model

Mỗi record quan trọng phải có:

```text
ownerUid
vehicleId
```

nhưng server không tin `ownerUid` gửi từ client.

Firestore rule phải đảm bảo:

```text
request.auth.uid == resource.data.ownerUid
```

cho read user-scoped.

Các write hệ thống quan trọng nên ưu tiên server/admin SDK.

---

# 5. Personal AI Profile schema

Collection đề xuất:

```text
AiVehicleProfiles/{profileId}
```

Schema:

```json
{
  "ownerUid": "firebase_uid",
  "vehicleId": "vehicle_id",
  "modelKey": "charging_time",
  "baseModelVersion": "vX",
  "personalizationStage": "base|calibrating|personalized",
  "trainingSessions": 12,
  "trainingSegments": 48,
  "nominalCapacityWh": 2400,
  "estimatedEffectiveCapacityWh": 2180,
  "capacityConfidence": 0.86,
  "stateOfHealth": 90.8,
  "correction": {
    "globalTimeScale": 0.96,
    "globalTimeBiasMinutes": -3.2,
    "powerScale": 0.98
  },
  "socBands": {
    "0_20": {},
    "20_40": {},
    "40_60": {},
    "60_80": {},
    "80_90": {},
    "90_100": {}
  },
  "quality": {
    "confidence": 0.91,
    "lastTrainingError": null
  },
  "lastTrainedAt": "...",
  "createdAt": "...",
  "updatedAt": "..."
}
```

---

# 6. Không retrain full base model sau mỗi phiên

Lựa chọn 1A phải được hiểu đúng:

Sau MỖI phiên:

```text
session completed/interrupted
↓
validate data quality
↓
extract charging segments
↓
update personal residual/calibration
↓
update capacity estimate
↓
update SOC-band charging curve
```

Không làm full retrain shared model sau mỗi lần sạc.

Base model vẫn do Admin AI Center quản lý.

Personal model là lớp correction nhỏ và an toàn.

---

# 7. Personalization stages

## Stage 0 — Cold start

```text
0–2 phiên hợp lệ
```

Dùng:

```text
Base AI + Physical Model
```

UI:

```text
AI đang làm quen với xe của bạn
```

## Stage 1 — Calibrating

```text
3–9 phiên
```

Dùng:

```text
Base AI
Physical Model
Personal correction nhẹ
```

UI:

```text
AI đang học thói quen sạc
```

## Stage 2 — Personalized

```text
>= 10 phiên đủ chất lượng
```

Dùng personal model với trọng số cao hơn.

UI:

```text
Đã cá nhân hóa cho xe này
```

---

# 8. Partial session learning

Ví dụ:

```text
Start: 20%
Target: 80%
User stop: 55%
```

Không bỏ dữ liệu.

Không giả định:

```text
20 → 80 hoàn thành
```

Training record chỉ sử dụng:

```text
20 → 55
```

và curve thực:

```text
timestamp
energyWh
powerW
voltage
current
temperature
SOC estimate/BMS SOC
```

---

# 9. Chia curve thành SOC bands

Các band đề xuất:

```text
0–20
20–40
40–60
60–80
80–90
90–100
```

Personal AI học:

```text
average W
Wh per %
minutes per %
temperature sensitivity
taper behavior
```

theo từng band.

---

# 10. Dừng sạc giữa chừng bắt buộc xác nhận

Flow mới:

```text
User bấm Dừng sạc
↓
StopConfirmationSheet
↓
User xác nhận
↓
controller.stop(...)
↓
Gateway OFF
↓
readback
↓
relay == false
↓
session terminal
```

## Stop Confirmation UI

Tạo:

```text
app/lib/features/ai/widgets/stop_charging_confirmation_sheet.dart
```

UI:

```text
Dừng sạc?

[ horizontal battery ]

Hiện tại        55%
Mục tiêu        80%
Còn lại         1 giờ 35 phút

Lý do (không bắt buộc)
[ Cần dùng xe ]
[ Pin đã đủ ]
[ Khác ]

[ Tiếp tục sạc ]

[ Dừng sạc ]
```

---

# 11. Stop reason schema

Bổ sung:

```text
userStopReason
```

Values:

```text
need_vehicle
enough_charge
safety_concern
other
none
```

Dữ liệu này không được dùng sai như charging-performance ground truth.

---

# 12. AI + Physics + Personal Fusion

Có 3 estimate:

```text
T_ai
T_physics
T_personal
```

Trong đó:

```text
T_ai
= output base charging_time model

T_physics
= estimate từ effectiveCapacityWh
  + actual/expected charge power
  + charge efficiency
  + SOC taper

T_personal
= estimate/correction từ historical curve của đúng ownerUid + vehicleId
```

---

# 13. Công thức fusion

Dùng:

```text
T_final =
(
  w_ai       × T_ai
+ w_physics  × T_physics
+ w_personal × T_personal
)
/
(
  w_ai + w_physics + w_personal
)
```

Weights dynamic.

## Gợi ý theo stage

### 0–2 phiên

```text
w_ai       ≈ 0.45
w_physics  ≈ 0.55
w_personal = 0
```

### 3–9 phiên

```text
w_ai       ≈ 0.40
w_physics  ≈ 0.40
w_personal ≈ 0.20
```

### 10+ phiên

Baseline:

```text
w_ai       ≈ 0.30
w_physics  ≈ 0.30
w_personal ≈ 0.40
```

sau đó điều chỉnh theo quality/confidence.

---

# 14. Dynamic confidence weighting

Weight phụ thuộc:

```text
AI model confidence
personal sample count
personal data quality
power stability
temperature coverage
capacity confidence
telemetry freshness
SOC-band coverage
```

Không để personal weight tăng chỉ vì số lượng nhiều nếu dữ liệu kém.

---

# 15. Ví dụ fusion

```text
AI ETA       = 240 phút
Physics ETA  = 230 phút
Personal ETA = 234 phút

weights:
AI       0.35
Physics  0.35
Personal 0.30

Final ETA ≈ 235 phút
≈ 3 giờ 55 phút
```

UI chỉ hiện:

```text
Dự kiến
3 giờ 55 phút
```

Debug detail mới hiện decomposition.

---

# 16. Physical capacity model

Nguồn dung lượng:

```text
nominalCapacityWh
```

từ linked VinFast model spec.

Sau đó:

```text
effectiveCapacityWh
=
nominalCapacityWh
× stateOfHealth / 100
```

Ví dụ:

```text
nominal = 2400 Wh
SoH = 92%
effectiveCapacity = 2208 Wh
```

---

# 17. Capacity calibration bằng lịch sử thực

Sau nhiều phiên quality tốt:

```text
estimatedEffectiveCapacityWh
```

được hiệu chỉnh bằng:

```text
sessionEnergyWh
SOC delta
charge efficiency
temperature
```

Raw observed estimate:

```text
capacityObserved
=
energyDeliveredWh
/
(SOC_delta / 100)
× efficiencyCorrection
```

Phải clamp và robust-filter outlier.

Không update capacity từ phiên có:

```text
SOC delta quá nhỏ
meter reset
telemetry stale
power bất thường
SOC không đáng tin
```

---

# 18. Physics ETA

```text
remainingPercent
=
targetSoc - currentSoc

requiredBatteryWh
=
effectiveCapacityWh
× remainingPercent / 100

inputEnergyWh
=
requiredBatteryWh / chargeEfficiency
```

ETA phải tính taper:

```text
< 80%    normal power
80–90%   taper
90–100%  stronger taper
```

Personal SOC-band data có thể thay curve mặc định.

---

# 19. Guardrail khi AI lệch Physics

Nếu deviation vượt threshold:

- giảm confidence nguồn lệch;
- giảm weight nguồn đó;
- clamp final ETA trong physical plausible bounds;
- log debug warning.

User không thấy thuật ngữ guardrail.

---

# 20. Prediction response contract mới

Endpoint có thể mở rộng:

```text
POST /api/ai/predict-charging-time
```

hoặc tạo:

```text
POST /api/ai/personal/predict-charging-time
```

Internal response:

```json
{
  "success": true,
  "finalMinutes": 235,
  "formattedDuration": "3 giờ 55 phút",
  "components": {
    "baseAiMinutes": 240,
    "physicsMinutes": 230,
    "personalMinutes": 234
  },
  "weights": {
    "ai": 0.35,
    "physics": 0.35,
    "personal": 0.30
  },
  "effectiveCapacityWh": 2208,
  "personalizationStage": "personalized",
  "confidence": 0.91,
  "guardrail": {
    "clamped": false,
    "warnings": []
  }
}
```

Frontend user chỉ dùng:

```text
finalMinutes
formattedDuration
personalizationStage friendly label
```

---

# 21. Training trigger sau mỗi phiên

Khi session terminal:

```text
completed
cancelled
interrupted
failed
```

Pipeline:

```text
terminal session
↓
finalize ChargeLog
↓
validate telemetry
↓
trainingEligibility
↓
server ingest session
↓
update personal profile
```

Không phải mọi failed session đều training eligible.

---

# 22. Training eligibility

Eligible nếu:

```text
duration đủ dài
SOC delta đủ
energy quality tốt
power samples đủ
session ownership valid
timestamps valid
no meter corruption
```

Partial cancelled/interrupted có thể eligible.

---

# 23. Training state

Trong ChargeLog:

```text
personalAiTrainingState
```

Values:

```text
pending
processing
trained
skipped
failed
```

Thêm:

```text
personalAiTrainingReason
personalAiProfileVersion
trainedAt
```

Training idempotent theo:

```text
sessionId
```

---

# 24. Telemetry schema

```text
ChargeLogs/{sessionId}/telemetry/{bucketId}
```

Fields:

```json
{
  "timestamp": "...",
  "sessionEnergyWh": 412.3,
  "powerW": 398.0,
  "voltageV": 228.1,
  "currentA": 1.75,
  "shellyTempC": 44.2,
  "batteryTempC": null,
  "soc": 55.2,
  "socSource": "bms|estimated",
  "targetSoc": 80,
  "relay": true,
  "timerRemainingSec": 5100,
  "quality": "good"
}
```

---

# 25. Telemetry frequency

UI:

```text
3–5 giây
```

Training persistence:

```text
15–30 giây
```

hoặc significant change.

Không write Firestore mỗi 3 giây.

---

# 26. Local durable telemetry spool

Để không mất data khi Internet mất:

```text
Telemetry sample
↓
local durable queue
↓
Internet available?
  ├─ yes → sync Firestore
  └─ no  → keep queue
↓
reconnect
↓
flush idempotently
```

Không giữ pending telemetry chỉ trong RAM.

Ưu tiên gateway/session store vì gateway đang sở hữu physical session.

---

# 27. Lịch sử không được mất

Phải thay access kiểu limit cố định bằng pagination.

Không coi:

```text
limit 20
```

là toàn bộ lịch sử.

---

# 28. Charge History architecture mới

`ChargeLogs/{sessionId}` được tạo NGAY KHI start thành công.

Status:

```text
active
```

Trong lúc sạc:

```text
same document
```

được cập nhật summary định kỳ.

Khi kết thúc:

```text
same document
```

được finalize:

```text
completed
cancelled
interrupted
failed
```

KHÔNG tạo document terminal thứ hai.

---

# 29. Realtime history UI

File:

```text
app/lib/features/charge_log/charge_log_screen.dart
```

Trên cùng:

```text
● ĐANG SẠC

┌──────────────────────────────────────┐
│ [ horizontal animated battery ]      │
│                                      │
│ Pin hiện tại             55%         │
│ Mục tiêu                 80%         │
│                                      │
│ Còn lại             1 giờ 35 phút    │
│ Năng lượng              412 Wh       │
│ Công suất               398 W        │
└──────────────────────────────────────┘
```

Advanced metrics trong expandable detail.

---

# 30. History pagination

Provider dùng cursor pagination:

```text
page size 20–50
```

Có:

```text
load first page
load more
refresh
```

Query:

```text
ownerUid
vehicleId
startTime descending
```

Không load 100 rồi `.take(20)` và coi là toàn bộ lịch sử.

---

# 31. Không hard-delete lịch sử Smart Charge

Nút user delete đổi thành:

```text
Ẩn khỏi danh sách
```

hoặc soft-delete:

```text
isHiddenByUser = true
```

Training data hệ thống vẫn giữ theo retention policy.

Nếu user yêu cầu privacy deletion, dùng destructive flow riêng và retrain profile tương ứng.

---

# 32. Energy reset per session

Khi start:

```text
baselineEnergyWh = Shelly.energyWh
sessionEnergyWh = 0
```

Trong phiên:

```text
sessionEnergyWh
=
max(0, currentMeterWh - baselineEnergyWh)
```

UI PHẢI dùng:

```text
session.energyUsedWh
```

Không dùng raw:

```text
status.energyWh
```

làm “Năng lượng phiên”.

---

# 33. Meter reset handling

Nếu:

```text
currentMeterWh < baselineEnergyWh
```

thì:

```text
energyQuality = meter_reset
new baseline = currentMeterWh
sessionEnergyWh = 0
```

Không cho số âm.

---

# 34. Connection architecture

Tạo:

```text
ConnectionCoordinator
```

State:

```text
internetAvailable
apiReachable
firebaseReachable
gatewayReachable
shellyReachable
lastSuccessfulStatusAt
lastSuccessfulSessionAt
reconnecting
```

---

# 35. Không reset app khi mất mạng

Khi request lỗi:

KHÔNG:

```text
phase = loading
clear session
clear charger status
clear preview
```

Phải giữ:

```text
lastKnownState
```

và chỉ cập nhật connection state.

---

# 36. Floating Offline Banner

Internet mất nhưng Shelly còn:

```text
Mất Internet
Sạc vẫn được bảo vệ

[ Thử lại ]
```

Mất toàn bộ:

```text
Mất kết nối
Đang thử kết nối lại

[ Thử lại ]
```

Không dùng full-screen error.

---

# 37. Bỏ dấu "~" trong scope UI mới

Không hiện:

```text
~55%
~01:35
~402 Wh
```

Thay bằng:

```text
Pin ước tính
55%

Thời gian dự kiến
1 giờ 35 phút
```

Uncertainty biểu diễn bằng label, không bằng ký hiệu `~`.

---

# 38. Mất cả Internet và Shelly

Giữ:

```text
battery visual
target
last known SOC
last known energy
last known ETA
```

Countdown vẫn chạy theo:

```text
effectiveStopAt
```

label:

```text
Thời gian theo kế hoạch
```

Không dùng `~`.

---

# 39. Reconnect backoff

```text
1s
2s
4s
8s
15s
30s
30s...
```

Nút:

```text
Thử lại
```

→ immediate attempt.

---

# 40. Reconcile khi reconnect

Nguồn:

```text
local active session snapshot
gateway current session
Shelly relay
Shelly timer
Firestore live ChargeLog
```

Priority:

```text
Shelly relay/timer
      ↓
Gateway session
      ↓
Firestore
      ↓
Local UI snapshot
```

Nếu:

```text
Shelly relay OFF
app says active
```

→ không giữ fake “Đang sạc”.

---

# 41. Persistent session snapshot

Lưu local non-secret:

```text
sessionId
vehicleId
targetSoc
effectiveStopAt
lastEstimatedSoc
lastSessionEnergyWh
lastKnownRelay
```

Không lưu secrets trong SharedPreferences.

---

# 42. Persistent Charging Pill

Khi session active và user sang màn khác:

```text
┌────────────────────────────┐
│ ⚡ Đang sạc  55% → 80%     │
│          còn 1g35p         │
└────────────────────────────┘
```

Bấm:

```text
→ SmartChargingControlScreen
```

---

# 43. Battery Fill Selector dạng viên pin nằm ngang

Tạo:

```text
app/lib/features/ai/widgets/horizontal_battery_target_selector.dart
```

Thiết kế:

```text
         Mục tiêu 80%

╭────────────────────────────────────────╮╮
│████████████████████████░░░░░░░░░░░░░░││
╰────────────────────────────────────────╯╯
 ↑ current                              ↑ 100
```

User có thể:

```text
tap vị trí trong pin
drag ngang
```

Min:

```text
currentSoc + 1
```

Max:

```text
100
```

---

# 44. Presets

Dưới battery selector:

```text
[ 80% ] [ 90% ] [ 100% ]
```

Preset <= current SOC disabled.

---

# 45. Haptic

Light haptic khi qua mốc:

```text
5%
```

Không rung mỗi 1%.

---

# 46. Charging Battery Animation

Tạo:

```text
app/lib/features/ai/widgets/charging_battery_animation.dart
```

Active UI:

```text
Mục tiêu 80%

╭────────────────────────────────────────╮╮
│██████████████████████▒▒▒▒▒▒▒░░░░░░░░░││
╰────────────────────────────────────────╯╯

Pin hiện tại 55%
```

Khi relay ON:

- fill pulse nhẹ;
- shimmer chạy ngang;
- không flash mạnh;
- respect reduced motion.

---

# 47. Không animate giả SOC

Chỉ interpolate:

```text
previousSoc
→ newSoc
```

khi telemetry mới tới.

Không dùng countdown để tự tăng SOC giả.

---

# 48. Smart Charge minimal UI mới

Idle:

```text
Smart Charge

[ trạng thái kết nối compact ]

Pin hiện tại
[ horizontal battery ]

Mức muốn sạc
[ target battery selector ]

Dự kiến
3 giờ 55 phút
Hoàn tất lúc 14:25

[ Bắt đầu sạc ]
```

Ẩn khỏi primary UI:

```text
model version
prediction source
runtime health
relay
LAN/cloud
confidence raw
```

---

# 49. Active minimal UI

```text
Smart Charge

● Đang sạc

Mục tiêu 80%

[ animated horizontal battery ]

Pin hiện tại
55%

Còn lại
1 giờ 35 phút

Năng lượng phiên
412 Wh

[ Dừng sạc ]
```

Advanced electrical metrics ở expandable detail.

---

# 50. Preview wording

Dùng:

```text
Dự kiến
3 giờ 55 phút

Hoàn tất lúc
14:25

AI đang học xe của bạn
```

hoặc:

```text
Đã cá nhân hóa cho xe này
```

---

# 51. Scope tối giản UI

Phase này redesign:

```text
Smart Charge
Dashboard
Charge History
```

Không redesign toàn bộ Trip Planner/Maintenance/Settings trong cùng implementation.

Nhưng tạo reusable design primitives để rollout sau.

---

# 52. Safety architecture

Safety owner:

```text
Smart Charger Gateway
```

App chỉ:

```text
display
notify
acknowledge
```

Gateway phải OFF được khi app đóng/mất mạng.

---

# 53. Safety inputs

Gateway monitor:

```text
Shelly temperature
voltage
current
power
relay
timer
telemetry freshness
session elapsed time
```

Nếu có BMS/API:

```text
battery temperature
battery SOC
battery fault flags
```

---

# 54. Tách nhiệt độ

Không gọi:

```text
SmartChargerStatus.temperatureC
```

là “Nhiệt độ pin”.

Đổi semantics thành:

```text
shellyTemperatureC
```

Thêm:

```text
batteryTemperatureC
```

riêng.

---

# 55. BatteryTelemetrySource abstraction

Tạo interface:

```text
BatteryTelemetrySource
```

Output:

```text
soc
temperatureC
timestamp
source
quality
```

Implementations:

```text
BmsBatteryTelemetrySource
EstimatedBatteryTelemetrySource
```

Nếu chưa có BMS:

```text
batteryTemperatureC = null
```

Không copy Shelly temp sang field pin.

---

# 56. Safety thresholds

Đặt gateway/server config:

```text
SMART_CHARGE_MAX_PLUG_TEMP_C
SMART_CHARGE_MAX_BATTERY_TEMP_C
SMART_CHARGE_MIN_VOLTAGE_V
SMART_CHARGE_MAX_VOLTAGE_V
SMART_CHARGE_MAX_CURRENT_A
SMART_CHARGE_MAX_POWER_W
SMART_CHARGE_MAX_SESSION_MINUTES
SMART_CHARGE_TELEMETRY_STALE_SECONDS
SMART_CHARGE_ZERO_POWER_GRACE_SECONDS
```

Không hardcode ngưỡng production tùy ý.

Giá trị thật phải dựa trên official Shelly/charger/vehicle specs và hardware validation.

---

# 57. Safety actions

Critical breach:

```text
detect
↓
session state = stopping
↓
Shelly OFF
↓
readback OFF
↓
session terminal safety
↓
write SafetyEvent
↓
push notification
```

Không yêu cầu user confirm safety shutdown.

---

# 58. Safety stop reasons

Bổ sung:

```text
over_temperature
battery_over_temperature
over_voltage
under_voltage
over_current
over_power
telemetry_stale
absolute_timeout
unexpected_relay_state
```

---

# 59. Safety Event schema

```text
ChargeLogs/{sessionId}/safetyEvents/{eventId}
```

Fields:

```text
ownerUid
vehicleId
sessionId
type
severity
observedValue
threshold
timestamp
relayBefore
relayAfter
offVerified
```

---

# 60. Security bổ sung

- HTTPS only production;
- API rate limiting;
- reject replay/stale commands;
- idempotency key cho start;
- optimistic `expectedVersion` cho stop/patch;
- server-side vehicle ownership;
- sanitize debug logs;
- secrets không nằm trong APK;
- Shelly credentials secure storage/server;
- không log Authorization header;
- audit command ON/OFF;
- audit safety events.

---

# 61. Manual ON security/safety

Manual ON vẫn phải:

```text
timer required
max duration enforced
safety monitoring enabled
relay readback
```

Không có ON vô hạn.

Manual sessions vẫn có thể đóng góp calibration nếu data quality đủ.

---

# 62. Offline action policy

## Internet mất, LAN Shelly còn

Cho phép:

```text
view session
view telemetry
OFF
```

Không tạo AI prediction mới.

Manual timed start có thể chỉ cho khi gateway safety ready.

## Internet + LAN đều mất

Không báo command thành công giả.

Nếu user bấm Stop mà device unreachable:

```text
Không kết nối được ổ sạc.
Hệ thống sẽ thử lại khi kết nối trở lại.
```

Nếu safety concern:

```text
Hãy ngắt nguồn vật lý.
```

---

# 63. Background behavior

App background/đóng:

- Shelly timer vẫn là fail-safe;
- gateway monitoring tiếp tục;
- background service sync khi có thể;
- notification khi terminal/safety;
- app resume → reconcile, không tạo session mới.

---

# 64. History access không bị mất

Cần sửa:

```text
ShellyChargeLogService
ChargeLogRepository
chargeLogsProvider
ChargeLogScreen
```

Requirements:

- pagination;
- no artificial terminal-only limit;
- live + historical merge by sessionId;
- offline cache;
- idempotent sync;
- soft-hide instead of hard delete;
- stale cache vẫn hiển thị với connection banner;
- refresh không clear list trước khi network response về.

---

# 65. Realtime provider

Dùng stream cho live head:

```text
active sessions listener
```

và pagination cho historical terminal sessions.

UI combine:

```text
liveSessions
+
historyPages
```

dedupe:

```text
sessionId
```

---

# 66. Training history retention

Personal AI không phụ thuộc vào 20 log gần nhất.

Tốt nhất:

```text
profile lưu aggregate
+
new session incremental update
```

Không retrain toàn lịch sử mỗi lần.

---

# 67. Profile versioning

Mỗi update:

```text
profileVersion += 1
```

Lưu:

```text
previousConfidence
newConfidence
sessionsAdded
capacityBefore
capacityAfter
correctionBefore
correctionAfter
```

Có khả năng rollback/debug server-side.

---

# 68. Base model version change

Profile lưu:

```text
baseModelVersion
```

Nếu Admin deploy base model mới:

```text
rebase personal correction
```

hoặc tạm giảm personal weight cho tới khi validated.

---

# 69. Personal model không upload từ user

User không upload Personal AI.

Admin AI Center quản lý:

```text
base model
```

Server quản lý:

```text
per-user/per-vehicle calibration
```

---

# 70. API đề xuất

```text
GET  /api/ai/personal/profile/<vehicleId>
POST /api/ai/personal/predict-charging-time
POST /api/ai/personal/ingest-session
```

`ingest-session` request:

```json
{
  "vehicleId": "...",
  "sessionId": "..."
}
```

Server tự lấy trusted Firestore data.

---

# 71. Không gửi raw training dataset từ Flutter nếu không cần

Ưu tiên:

```text
client gửi sessionId
server đọc trusted Firestore data
```

giảm spoof/tamper/cross-user training.

---

# 72. Training retry queue

Nếu terminal khi offline:

```text
trainingState = pending
```

Khi reconnect:

```text
TrainingSyncService
```

gửi pending sessionId.

Server idempotent.

---

# 73. Data quality score

Mỗi session/segment có:

```text
qualityScore 0..1
```

Dựa trên:

```text
telemetry completeness
duration
SOC source
power stability
meter health
temperature availability
network gaps
```

Training weight:

```text
sampleWeight = qualityScore
```

---

# 74. BMS priority

SOC source priority:

```text
BMS
↓
trusted vehicle API
↓
energy-based estimate
↓
manual user SOC
```

Debug mới hiển thị source.

---

# 75. Target SOC luôn hiển thị khi active

Bắt buộc:

```text
Mục tiêu 80%
```

kể cả offline/background resume/history LIVE card.

---

# 76. Remove engineering jargon

Primary UI không có:

```text
SOC
relay
RPC
LAN fallback
Cloud provider
modelVersion
runtimeHealth
heuristic
physics fallback
confidence raw
timerVerified
```

Thay bằng:

```text
Pin hiện tại
Mức muốn sạc
Đang sạc
Đã tắt
Mất kết nối
Dự kiến
AI đang học xe của bạn
```

---

# 77. Files cần sửa — Flutter

```text
app/lib/features/ai/controllers/smart_charging_controller.dart
app/lib/features/ai/smart_charging_control_screen.dart

app/lib/data/models/smart_charging_session.dart
app/lib/data/models/smart_charger_status.dart
app/lib/data/models/vehicle_model.dart

app/lib/data/services/smart_charger_service.dart
app/lib/data/services/charging_prediction_adapter.dart
app/lib/data/services/shelly_charge_log_service.dart

app/lib/data/repositories/smart_charger_repository.dart
app/lib/data/repositories/charge_log_repository.dart

app/lib/features/charge_log/charge_log_screen.dart
app/lib/features/dashboard/*
```

---

# 78. Files mới — Flutter

```text
app/lib/features/ai/widgets/horizontal_battery_target_selector.dart
app/lib/features/ai/widgets/charging_battery_animation.dart
app/lib/features/ai/widgets/stop_charging_confirmation_sheet.dart
app/lib/features/ai/widgets/charging_connection_banner.dart
app/lib/features/ai/widgets/persistent_charging_pill.dart

app/lib/core/services/connection_coordinator.dart

app/lib/data/models/personal_ai_profile.dart
app/lib/data/models/charging_telemetry_sample.dart
app/lib/data/models/charging_prediction_fusion.dart

app/lib/data/services/personal_ai_service.dart
app/lib/data/services/charging_telemetry_service.dart
app/lib/data/services/charging_training_sync_service.dart
app/lib/data/services/battery_telemetry_source.dart
```

---

# 79. Files cần sửa — Gateway

```text
smart_charger_gateway/smart_charging.py
smart_charger_gateway/models.py
smart_charger_gateway/main.py
smart_charger_gateway/smart_session_store.py
smart_charger_gateway/.env.example
```

Có thể thêm:

```text
smart_charger_gateway/safety_monitor.py
smart_charger_gateway/telemetry_store.py
```

---

# 80. Files cần sửa — Web/API

```text
web/server.py
web/ai_server/*
```

Tách module:

```text
web/ai_server/personalization.py
web/ai_server/personal_profile_store.py
web/ai_server/charging_fusion.py
```

Không nhét toàn bộ logic mới vào `server.py`.

---

# 81. Firestore migration

Collections:

```text
Vehicles
ChargeLogs
AiVehicleProfiles
```

Subcollections:

```text
ChargeLogs/{sessionId}/telemetry
ChargeLogs/{sessionId}/safetyEvents
```

Migration không destructive.

---

# 82. Existing history migration

Legacy logs vẫn hiển thị.

Nếu thiếu `ownerUid`, phải migration/admin mapping trước khi enforce strict access.

Không silently làm history biến mất.

---

# 83. App history merge

Charge History hiển thị:

```text
manual legacy logs
smart charging logs
live smart session
completed smart sessions
```

Sort theo start time.

Dedupe:

```text
sessionId/logId
```

---

# 84. Tests — ownership isolation

Case:

```text
User A
Vehicle X
```

không thể đọc/train/predict bằng profile User B.

Expected:

```text
403
```

Same vehicleId ở hai account phải tạo hai profile riêng.

---

# 85. Test — interrupted learning

```text
20% → target 80%
actual stop 55%
```

Expected:

- history terminal cancelled/manual;
- telemetry 20→55 retained;
- training eligible nếu quality pass;
- chỉ update covered SOC bands;
- không fake target 80.

---

# 86. Test — stop confirmation

- chưa confirm → không OFF;
- cancel sheet → session tiếp tục;
- confirm → OFF;
- readback false → terminal;
- readback fail → không báo “Đã tắt”.

---

# 87. Test — fusion

Cases:

```text
cold start
calibrating
personalized
high AI deviation
high physics deviation
low quality personal data
missing SoH
missing BMS
```

Final ETA deterministic theo fixture.

---

# 88. Test — effective capacity

```text
nominal 2400
SoH 90
→ effective 2160 Wh
```

Observed sessions có thể hiệu chỉnh nhưng phải clamp/outlier reject.

---

# 89. Test — safety

Mock:

```text
over temp
over current
over voltage
under voltage
max duration
stale telemetry
unexpected relay off
```

Expected:

```text
OFF sent
OFF readback verified
SafetyEvent persisted
terminal reason correct
notification created
```

---

# 90. Test — offline UI

Mất Internet:

- screen không reset;
- active session vẫn hiển thị;
- banner hiện;
- no `~`;
- LAN status vẫn update nếu available.

Mất toàn bộ:

- last state giữ;
- countdown theo plan;
- retry;
- reconnect reconcile.

---

# 91. Test — history realtime

Start:

```text
live card xuất hiện
```

Telemetry:

```text
Wh/current/power update
```

Stop:

```text
cùng sessionId chuyển terminal
```

Không duplicate.

---

# 92. Test — history retention

Tạo >100 logs.

Phải:

- xem page đầu;
- load more;
- truy cập log cũ;
- refresh không mất;
- restart app vẫn truy cập;
- offline vẫn thấy cache cũ.

---

# 93. Test — energy reset

Session A:

```text
Shelly meter start 1000 Wh
end 1500 Wh
sessionEnergy = 500 Wh
```

Session B:

```text
baseline 1500 Wh
UI starts 0 Wh
meter 1600 Wh
sessionEnergy = 100 Wh
```

Không hiện 1600 Wh là energy của phiên.

---

# 94. Test — Battery Fill Selector

Cases:

```text
current 40
target min 41
target 80
target 90
target 100
drag
tap
preset
accessibility
reduced motion
```

Target không được <= current.

---

# 95. Test — no tilde

Automated search/widget tests cho:

```text
Smart Charge
Dashboard
Charge History
```

không còn dấu `~` với nghĩa estimated.

Dùng label “ước tính/dự kiến”.

---

# 96. Test — charging target visible

Active session luôn có:

```text
Mục tiêu XX%
```

kể cả offline/background/history LIVE.

---

# 97. Performance constraints

- animation 60fps target;
- không write Firestore mỗi poll;
- không rebuild full history mỗi giây;
- countdown state tách khỏi history query;
- telemetry batching;
- dispose timers/subscriptions đúng lifecycle.

---

# 98. Observability

Debug/admin cần xem:

```text
Base AI ETA
Physics ETA
Personal ETA
weights
capacity estimate
profile stage
session quality
training state
safety events
connection timeline
```

User UI không hiển thị các field này.

---

# 99. Rollout strategy

## Phase A — Data/Safety Foundation

```text
ownership security
live ChargeLog
session energy baseline
telemetry persistence
safety monitor
```

## Phase B — Prediction Fusion

```text
nominal capacity resolve
effective capacity
physics ETA
base AI
fusion
guardrail
```

## Phase C — Personal AI

```text
AiVehicleProfiles
incremental calibration
partial segments
training trigger
profile stages
```

## Phase D — Offline resilience

```text
ConnectionCoordinator
last-known state
reconnect
reconcile
local telemetry spool
```

## Phase E — UX

```text
horizontal Battery Fill Selector
charging animation
target visible
stop confirmation
connection banner
persistent pill
minimal wording
```

## Phase F — Realtime History

```text
LIVE card
Firestore stream
pagination
soft-hide
all-history access
```

---

# 100. Thứ tự ưu tiên cho agent

## P0 — Safety + integrity

```text
1. Secure personal endpoints with Firebase auth
2. Verify ownerUid + vehicleId
3. Fix live session persistence
4. Fix per-session energy display
5. Add safety gateway monitor
6. Add safety stop reasons/events
7. Preserve history; remove artificial access limits
```

## P1 — Prediction foundation

```text
8. Resolve nominal vehicle capacity
9. effectiveCapacityWh
10. Physics ETA
11. Fusion response contract
12. Guardrail dynamic weighting
13. Extend session prediction metadata
```

## P2 — Personal AI

```text
14. AiVehicleProfiles
15. Training telemetry schema
16. Partial session segmentation
17. Incremental personal calibration
18. Personal stages
19. Training retry/idempotency
20. Base-model compatibility/rebase
```

## P3 — Connectivity

```text
21. ConnectionCoordinator
22. Last-known state preservation
23. Offline banner
24. Retry/backoff
25. Reconcile
26. Local telemetry spool
```

## P4 — UX

```text
27. Horizontal Battery Fill Selector
28. Charging Battery Animation
29. Active target %
30. Stop Confirmation Sheet
31. Remove "~"
32. Minimal Smart Charge
33. Persistent charging pill
34. Minimal Dashboard
```

## P5 — Realtime History

```text
35. LIVE ChargeLog card
36. Stream live session
37. Historical pagination
38. Dedupe same session
39. Soft hide/restore
40. Offline cached history
```

## P6 — QA

```text
41. Unit tests
42. Widget tests
43. Gateway safety tests
44. API auth tests
45. Firestore rules tests
46. Offline integration tests
47. Physical Shelly test
48. APK release QA
```

---

# 101. Definition of Done

## Personal AI

- [ ] Profile khóa theo `(ownerUid, vehicleId)`.
- [ ] Cross-account access bị chặn.
- [ ] Sau mỗi phiên hợp lệ profile update idempotently.
- [ ] Partial session được học đúng đoạn thực tế.
- [ ] Không extrapolate partial session thành target chưa đạt.
- [ ] 0–2 / 3–9 / 10+ stages hoạt động.
- [ ] Base model update không làm personal correction cũ gây lỗi.

## Prediction

- [ ] Final ETA kết hợp Base AI + Physics + Personal.
- [ ] effectiveCapacityWh dùng nominal capacity + SoH.
- [ ] Capacity được hiệu chỉnh từ lịch sử tốt.
- [ ] AI/physics deviation có guardrail.
- [ ] User chỉ thấy một ETA dễ hiểu.
- [ ] Target SOC luôn rõ ràng.

## Safety

- [ ] Safety chạy ở gateway.
- [ ] Electrical/temperature abnormality có automatic OFF.
- [ ] OFF có readback.
- [ ] Max session duration enforced.
- [ ] Stale telemetry có policy.
- [ ] Shelly temp và battery temp không bị đánh đồng.
- [ ] Safety events được lưu.

## Security

- [ ] Personal APIs yêu cầu Firebase auth.
- [ ] Ownership vehicle verify server-side.
- [ ] ownerUid không tin từ request body.
- [ ] Start có idempotency.
- [ ] Stop/patch có version protection.
- [ ] Secrets không log.
- [ ] History chỉ owner đọc được.

## Offline

- [ ] Mất Internet không reset màn.
- [ ] LAN còn thì phiên vẫn được theo dõi phù hợp.
- [ ] Mất toàn bộ giữ last-known state.
- [ ] Có floating reconnect banner.
- [ ] Không dùng dấu `~`.
- [ ] Reconnect reconcile theo Shelly/gateway.
- [ ] Không duplicate session.
- [ ] Pending telemetry không mất.

## UX

- [ ] Target selector là viên pin nằm ngang.
- [ ] Drag/tap chọn target.
- [ ] Presets 80/90/100.
- [ ] Active có battery fill animation.
- [ ] Mục tiêu luôn hiển thị.
- [ ] Dừng sạc phải confirm.
- [ ] Primary UI không còn jargon kỹ thuật.
- [ ] Dashboard/History cùng design language.
- [ ] Reduced-motion respected.

## History

- [ ] Active session hiện LIVE ở đầu.
- [ ] LIVE update realtime.
- [ ] Same session record finalize, không duplicate.
- [ ] Session energy bắt đầu 0 Wh mỗi lần.
- [ ] Không reset lifetime Shelly meter.
- [ ] Lịch sử cũ vẫn đọc được.
- [ ] Pagination toàn bộ lịch sử.
- [ ] Refresh/restart/offline không làm mất record.
- [ ] Không hard-delete training history từ nút xóa thông thường.

## Tests

- [ ] `flutter analyze` pass.
- [ ] `flutter test` pass.
- [ ] Backend `pytest` pass.
- [ ] Gateway tests pass.
- [ ] Auth isolation tests pass.
- [ ] Safety tests pass.
- [ ] Offline/reconnect tests pass.
- [ ] >100 history records pagination test pass.
- [ ] Real Shelly smoke test pass.
- [ ] APK release build pass.

---

# 102. Acceptance scenarios

## Scenario A — First charging session

```text
User A
Vehicle A
Personal history = 0

40% → target 80%
↓
Base AI predicts
Physics predicts
↓
fusion without personal
↓
start
↓
telemetry saved
↓
complete
↓
profile trainingSessions = 1
```

UI:

```text
AI đang làm quen với xe của bạn
```

## Scenario B — Personalized vehicle

```text
12 good sessions
↓
profile stage personalized
↓
Base AI 240 min
Physics 230 min
Personal 234 min
↓
final 235 min
```

UI:

```text
Đã cá nhân hóa cho xe này
Dự kiến 3 giờ 55 phút
```

## Scenario C — User stops early

```text
20 → target 80
actual 55
↓
confirm Stop
↓
OFF verify
↓
history cancelled
↓
20→55 telemetry remains
↓
personal bands covered by actual data update
```

## Scenario D — Internet loss during charge

```text
relay ON
Shelly timer armed
Internet lost
LAN still works
```

UI giữ:

```text
Đang sạc
Mục tiêu 80%
battery animation
```

Banner:

```text
Mất Internet
Sạc vẫn được bảo vệ
```

## Scenario E — All connectivity lost

```text
Internet lost
LAN lost
```

UI không reset.

Banner:

```text
Mất kết nối
Đang thử kết nối lại
```

Countdown label:

```text
Thời gian theo kế hoạch
```

Không có dấu `~`.

## Scenario F — Safety event

```text
temperature/current/voltage critical
↓
gateway OFF
↓
readback false
↓
SafetyEvent
↓
notification
↓
history finalized
```

Không yêu cầu user confirm safety shutdown.

## Scenario G — History with 500 sessions

```text
open Charge History
↓
LIVE current session
↓
recent history first page
↓
load more
↓
older sessions accessible
```

Không mất các session cũ vì limit 20/100.

---

# 103. Nguyên tắc agent không được vi phạm

1. Không retrain full shared model sau mỗi session.
2. Không dùng `vehicleId` một mình làm personal identity.
3. Không tin `ownerUid` từ client.
4. Không gọi Shelly temperature là battery temperature.
5. Không dùng raw Shelly lifetime `energyWh` làm session energy.
6. Không reset lifetime energy counter của Shelly mỗi phiên.
7. Không clear active screen chỉ vì network request fail.
8. Không hiển thị dấu `~` để diễn đạt estimated.
9. Không báo OFF thành công nếu relay readback chưa false.
10. Không cho user chỉnh production safety thresholds.
11. Không hard-delete Smart Charge training history từ nút xóa thông thường.
12. Không persist telemetry Firestore mỗi 3 giây.
13. Không train partial session như thể nó đã đạt target.
14. Không để Personal AI của account A dùng data account B.
15. Không duplicate live ChargeLog khi session terminal.
16. Không làm animation giả SOC khi chưa có telemetry update.
17. Không đưa jargon AI/Shelly vào primary user UI.
18. Không để app state override sự thật từ gateway/Shelly sau reconnect.
19. Không thêm hardcoded `2400 Wh` làm capacity cho mọi xe.
20. Không coi feature hoàn thành chỉ vì UI chạy; phải test gateway + backend + Firestore + Shelly thật.

---

# 104. Kết quả sản phẩm mong muốn

```text
Chọn mức pin muốn sạc
        ↓
AI hiểu đúng chiếc xe của bạn
        ↓
Kết hợp lịch sử + dung lượng pin + điều kiện sạc
        ↓
Tính thời gian hợp lý
        ↓
Sạc
        ↓
Pin animation đầy dần
        ↓
Safety hoạt động độc lập
        ↓
Dữ liệu phiên được lưu realtime
        ↓
AI học thêm từ phiên vừa sạc
        ↓
Lần sau dự đoán sát hơn
```

Người dùng không cần hiểu:

```text
model
relay
heuristic
residual
confidence weighting
RPC
Cloud/LAN
```

nhưng hệ thống bên dưới phải lưu đủ dữ liệu để debug, audit, safety và tiếp tục cá nhân hóa chính xác theo từng tài khoản + từng chiếc xe.
