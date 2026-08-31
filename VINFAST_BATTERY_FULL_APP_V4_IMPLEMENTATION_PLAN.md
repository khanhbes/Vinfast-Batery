# VINFAST BATTERY — FULL APP V4 IMPLEMENTATION PLAN
## Minimal App Redesign + Multi-Vehicle + Per-Vehicle Personal AI + Durable Charging History

**Repository:** `khanhbes/Vinfast-Batery`  
**Audited branch:** `feature/smart-charge-user-debug-ai`  
**Audited HEAD:** `e27f8fba81cc78045815edfa6a353ae165a5759f`  
**Plan status:** Agent-ready implementation specification  
**Primary scope:** Flutter app + Smart Charge server + Firestore schema/rules/indexes  
**Non-goal:** Rewrite the working Shelly control/safety architecture from scratch.

---

# 0. Product decisions locked for V4

| # | Decision |
|---|---|
| 1 | Personal AI is **server-primary hybrid**. Server runs Base AI, personalization, candidate training/validation/promotion. Phone renders UI, caches non-sensitive state, buffers telemetry, and preserves offline UX. |
| 2 | Architecture supports N vehicles, but `maxVehiclesPerAccount = 2` is configurable. |
| 3 | A compact **Vehicle Switcher** is visible in important screens and changes the active vehicle context globally. |
| 4 | Vehicle Switcher shows vehicle icon/name, battery, SoH, and charging status. |
| 5 | User may switch to vehicle B while vehicle A is charging. A's charging session remains locked to A. |
| 6 | Support both one-Shelly-per-vehicle and shared-Shelly configurations through explicit `VehicleChargerBinding`. |
| 7 | Main navigation becomes **Tổng quan · Sạc · Lịch sử · Khác**. |
| 8 | Overview prioritizes Vehicle Switcher → battery/SoH → Smart Charge → a small number of useful AI insights. |
| 9 | Remove AI as a primary tab. AI becomes a capability of the selected vehicle. |
| 10 | Consumer Personal AI UI only shows friendly stages: **Đang làm quen → Đang học → Đã cá nhân hóa**. |
| 11 | Keep backend stages: `0–2 base`, `3–9 calibrating`, `10+ personalized`. |
| 12 | Each eligible charging session creates a **candidate update**. Promote only after validation. |
| 13 | If a candidate is worse, do not promote it; keep/rollback to the previous promoted version. |
| 14 | Prefer real BMS/API SOC when available. Otherwise ask a lightweight end-of-charge SOC confirmation. |
| 15 | Automatically collect the full useful charging feature set for training. |
| 16 | Keep charging summaries indefinitely; keep raw high-frequency telemetry for 12 months then compact/expire it. |
| 17 | History defaults to selected vehicle and offers `Xe này · Tất cả xe`. |
| 18 | Removing a vehicle means **Archive**, not hard delete. History, AI profile, and audit remain recoverable. |
| 19 | Normal history removal means **Hide**; true erase lives in Privacy/Data with strong confirmation. |
| 20 | Minimal history row: `% start → target/end`, duration, energy, mode/status, date/time. |
| 21 | One main chart with selector `Pin · Công suất · Năng lượng · Nhiệt độ`. |
| 22 | Technical values are collapsed under `Xem chi tiết`. |
| 23 | Unfinished features are visibly disabled with a reason; missing-data and missing-setup states are distinct. |
| 24 | One central `FeatureAvailabilityRegistry` decides feature state. |
| 25 | If an AI model is not deployed/predictable, disable the AI feature. Do not disguise physics fallback as AI. |
| 26 | When offline before a new session, block new AI charging; allow safe timed charging through reachable Shelly/LAN where supported. |
| 27 | Ask Personal AI consent once per vehicle. User can later turn it off. |
| 28 | Visual direction: **Minimal EV cockpit**. |
| 29 | Trip, Maintenance, Statistics, AI tools, Settings move into `Khác`. |
| 30 | Charging notifications carry `vehicleId + sessionId`; opening them does not silently change the global selected vehicle. |

---

# 1. Repository audit at the V4 baseline

## 1.1 What already exists and MUST be preserved

The latest commit already implements important V3 foundations. V4 must build on them instead of replacing them.

### Smart Charge / device safety
- Shelly Cloud + fallback architecture.
- Physical relay-derived charging state.
- Device timer as safety authority.
- ON/OFF readback.
- Status/session polling.
- Foreground telemetry support.
- Idempotent Smart Charge start.
- Safe OFF behavior.
- Existing safety monitor and safety events.
- Existing error reporter/debug sheet.
- Connection coordinator and connection banner.

### Personal AI V3
Already present:
- `app/lib/data/services/personal_ai_service.dart`
- `app/lib/data/models/personal_charging_profile.dart`
- `app/lib/features/settings/personal_ai_settings_screen.dart`
- `web/shelly/personalization.py`
- `web/shelly/charging_fusion.py`
- Personal profiles keyed by owner + vehicle.
- Base / calibrating / personalized stages.
- SOC-band learning.
- Effective capacity estimation.
- Power learning.
- SoH estimation.
- Personal ETA correction.
- Base AI + physics + personal fusion.

### Charging UX V3
Already present:
- `ChargingBatteryAnimationV3`
- `HorizontalBatteryTargetSelector`
- `ChargingConnectionBanner`
- `PersistentChargingPill`
- `StopChargingConfirmationSheet`
- Smart Charge history screen with cursor pagination.
- Realtime refresh when an active history item exists.

### Multi-vehicle foundations
Already present:
- `selectedVehicleIdProvider`
- `restoreVehicleIdProvider`
- `vehicleProvider`
- `allVehiclesProvider`
- Garage UI.
- Vehicle-specific data models and repositories.

Do not create duplicate implementations for these concepts.

---

# 2. Important gaps found in the current code

## 2.1 Current app navigation is still the old 5-tab information architecture

`app/lib/navigation/app_navigation.dart` currently builds:

```text
Home
AI
Trip
Service
Settings
```

V4 changes this to:

```text
Tổng quan
Sạc
Lịch sử
Khác
```

AI is no longer a navigation silo. It becomes a capability scoped to the selected vehicle.

## 2.2 Vehicle context exists but is not yet a first-class app-wide domain

Current code already has:

```dart
selectedVehicleIdProvider
allVehiclesProvider
vehicleProvider
```

but different feature screens can still resolve vehicle data independently or use default/fallback vehicle IDs.

V4 must introduce a single `VehicleContext` abstraction used by:
- Overview
- Smart Charge
- History
- AI
- Trip
- Maintenance
- Statistics
- Notifications/deep links
- Charger setup/binding

No feature may silently fall back to another vehicle while an explicit selected vehicle exists.

## 2.3 Vehicle limit is not enforced safely

`AuthService.addVehicle()` currently creates a vehicle directly in Firestore and does not enforce the two-vehicle product limit.

V4 must implement:

```dart
maxVehiclesPerAccount = 2
```

as configuration, not a hardcoded UI-only condition.

The limit must be enforced at data-write level, not only by disabling the button.

## 2.4 Vehicle deletion currently hard-deletes the vehicle

The current Garage flow calls:

```dart
AuthService().deleteVehicle(vehicleId)
```

and the service deletes the `Vehicles/{vehicleId}` document.

That conflicts with the product requirement that charging history must never disappear because the user removed a vehicle from the Garage.

V4 replaces normal deletion with **Archive Vehicle**.

## 2.5 Shelly backend is still effectively single-device-v1

Current route:

```text
POST /api/shelly/devices/<device_id>/select
```

explicitly revokes other active bindings.

Current repository:

```python
get_binding(uid)
```

returns the first active binding.

Current status endpoint is account-level rather than vehicle-level.

This must change before the app can safely support:
- vehicle A → Shelly A
- vehicle B → Shelly B
- vehicle A and B sharing one Shelly

## 2.6 Current-session lookup is account-wide

Current API:

```text
GET /api/smart-charging/session/current
```

returns one account-level active session.

V4 needs vehicle-aware and account-wide active-session APIs separately.

## 2.7 History pagination is not yet vehicle-aware

Current Flutter API:

```text
/api/smart-charging/history?limit=&cursor=&strategy=
```

has no `vehicleId`.

Current backend pagination also applies `strategy` filtering after the initial Firestore page is loaded, which can result in short/incorrectly paged filtered results.

V4 must move all supported filters into the datastore query before page slicing.

## 2.8 Personal AI currently updates profile directly

Current `web/shelly/personalization.py` incrementally mutates and saves:
- power estimate;
- ETA scale;
- capacity;
- SoH;
- SOC-band features.

This is a good learning primitive, but V4 requires a safer lifecycle:

```text
eligible session
    ↓
immutable training sample
    ↓
candidate profile/model version
    ↓
validation
    ├── pass → promote
    └── fail → reject, current promoted version remains active
```

## 2.9 Personal AI UI text is inconsistent with backend stage thresholds

Backend personalization stage currently becomes:
- base: `<3 valid sessions`
- calibrating: `3–9`
- personalized: `>=10`

The current Personal AI settings UI contains text implying deeper learning from 5 sessions.

V4 must remove that mismatch and show only consumer-friendly stage messaging.

## 2.10 Feature flags are not an availability system

Current `AppFeatureFlags` only contains a few UI flags.

V4 must NOT expand this class into a tangle of runtime conditions.

Remote flags and runtime availability have different responsibilities.

Implement a new centralized `FeatureAvailabilityRegistry`.

---

# 3. Target V4 architecture

```text
                         ┌─────────────────────────┐
                         │      Flutter App        │
                         │                         │
                         │ VehicleContextProvider  │
                         │ FeatureAvailability     │
                         │ ConnectionCoordinator   │
                         └────────────┬────────────┘
                                      │ authenticated API
                                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Smart Charge API                        │
│                                                                 │
│ vehicle ownership ─ charger binding ─ session ownership         │
│                                                                 │
│    Global AI       Physics       Personal promoted profile       │
│       │                │                  │                      │
│       └────────────── Charging ETA Fusion ─────────────────────┐ │
│                                                               │ │
│                         Safety Guardrails                      │ │
│                                                               ▼ │
│                                                        Shelly command
└─────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
                         ┌─────────────────────────┐
                         │       Firestore         │
                         │                         │
                         │ Vehicles                │
                         │ ChargeLogs              │
                         │ smartChargingSessions   │
                         │ AiVehicleProfiles       │
                         │ profile versions        │
                         │ training samples        │
                         │ telemetry TTL           │
                         └─────────────────────────┘
```

---

# 4. Personal AI: server-primary hybrid

## 4.1 Why server-primary is the correct choice

Do NOT move training/fine-tuning to Flutter for V4.

Server-primary provides:
- one canonical profile per account + vehicle;
- no divergent models across two phones;
- easier model rollback;
- centralized safety validation;
- protected model artifacts;
- access to full historical data;
- controlled CPU/RAM usage;
- background candidate evaluation after a session;
- auditability;
- easier deployment of new base models;
- easier migration when training schema changes.

Phone responsibilities:
- render friendly Personal AI status;
- cache last profile summary for offline display;
- buffer telemetry when connectivity is temporarily lost;
- sync buffered telemetry later;
- never train/activate an authoritative model locally;
- never start a new AI-controlled charge using stale cached Personal AI while the server is unreachable.

---

# 5. Personal AI lifecycle V4

## 5.1 Scope identity

Every Personal AI artifact MUST use:

```text
ownerUid + vehicleId
```

Never key personalization only by vehicle model.

Two Feliz vehicles belonging to one account must learn independently.

## 5.2 Consumer stages

### Stage 1 — `base`
Condition:

```text
validSessions < 3
```

Consumer text:

```text
AI đang làm quen với xe của bạn
```

Fusion behavior:
- Base AI: primary.
- Physics: strong guardrail.
- Personal ETA contribution: 0.
- Capacity/power calibration may be collected in the background.

### Stage 2 — `calibrating`
Condition:

```text
3 <= validSessions < 10
```

Consumer text:

```text
AI đang học thói quen sạc
```

Fusion behavior:
- Personal candidate may influence ETA with a conservative capped weight.
- Global AI and physics remain significant.

### Stage 3 — `personalized`
Condition:

```text
validSessions >= 10
```

Consumer text:

```text
Đã cá nhân hóa cho xe này
```

Personal contribution may become the strongest candidate only when confidence and validation quality support it.

Do not show adapter version, SOC band names, MAPE, raw weights, or model artifact names on the normal consumer screen. Put them in developer/admin diagnostics only.

---

# 6. Candidate → Validate → Promote pipeline

## 6.1 Replace direct authoritative mutation

Refactor:

`web/shelly/personalization.py`

from:

```text
session → mutate current profile → save
```

to:

```text
session
  ↓
evaluate_training()
  ↓
TrainingSample
  ↓
build_candidate(current_promoted_profile, samples)
  ↓
validate_candidate()
  ↓
CandidateDecision
  ├── promoted
  └── rejected
```

## 6.2 New server concepts

Create:

```text
web/shelly/personal_model_registry.py
```

Recommended types:

```python
PersonalProfileVersion
CandidateValidationResult
PromotionDecision
```

A profile version needs at least:

```text
profileVersion
ownerUid
vehicleId
baseModelVersion
createdAt
sourceSessionIds
validSessions
trainingSegments

globalTimeScale
globalTimeBiasMinutes
powerScale
medianPowerW
estimatedEffectiveCapacityWh
stateOfHealth
socBands

validationMape
validationMaeMinutes
guardrailPassRate
qualityConfidence

status:
  candidate
  promoted
  rejected
  superseded

promotionReason
rejectionReason
```

## 6.3 Validation policy

Candidate promotion is forbidden if any of these are true:
- validation dataset is malformed;
- candidate produces non-finite ETA;
- candidate violates physical charging bounds;
- critical safety guardrail regression;
- vehicle ownership mismatch;
- training sample was already consumed;
- data quality is below threshold.

### Initial candidate
When no promoted personal version exists:
- candidate may be promoted after the existing session eligibility checks pass;
- ETA contribution remains controlled by personalization stage.

### Existing promoted version
New candidate must outperform the current promoted version on the validation set.

Primary metric:

```text
MAPE of final charging duration
```

Secondary metrics:
- MAE minutes
- large-error tail
- physical-clamp frequency
- safety event correlation
- calibration stability

Suggested promotion rule:

```text
candidate_mape < promoted_mape
AND candidate_guardrail_pass_rate >= promoted_guardrail_pass_rate
AND no safety regression
```

Do not promote merely because the latest session was predicted better.

---

# 7. Long-term model evolution

V4 should distinguish **personal calibration** from literal neural-network fine-tuning.

## Phase A — V4
Use the existing safe Personal AI adapter:
- capacity calibration;
- charging power calibration;
- SOC-band behavior;
- ETA bias/scale;
- confidence-weighted fusion.

This is the production mechanism for early data.

## Phase B — after sufficient high-quality data
Train a per-vehicle lightweight residual model on the server.

Example target:

```text
actual_duration_minutes - global_ai_duration_minutes
```

Possible features:
- start SOC
- target SOC
- SOC delta
- SoH
- effective capacity
- median/average charger power
- temperature
- recent charge behavior
- SOC band
- battery age / mileage when available

Do not train a heavy model after every single charge.

## Phase C — optional true base-model fine-tuning
Only evaluate per-vehicle transfer learning after enough representative data exists.

Recommended prerequisite:

```text
>= 30–50 high-quality sessions
```

plus:
- coverage across SOC bands;
- stable actual end SOC labels;
- acceptable telemetry completeness;
- separate validation set.

Every model remains candidate-first and rollbackable.

---

# 8. Training data automatically collected

For every Smart Charge session, persist the following when available.

## Identity
```text
ownerUid
vehicleId
sessionId
deviceId
```

## Vehicle
```text
vehicle model snapshot
model year
nominal capacity Wh
effective capacity Wh
capacity confidence
SoH
odometer
```

## Charge intent
```text
startSoc
targetSoc
actualEndSoc
charging mode
AI/manual mode
user stop reason
```

## Prediction
```text
base AI minutes
physics minutes
personal minutes
final minutes
model key
base model version
personal profile version
fusion weights
confidence
guardrail result
```

## Physical charge measurements
```text
energy Wh
session duration
average power W
peak power W
average voltage V
voltage min/max
average current A
current peak
Shelly temperature average/max
battery temperature average/max if available
ambient temperature if available
```

## Data quality
```text
telemetry coverage
number of samples
missing intervals
energy quality
relay verification
timer verification
network interruptions
server interruptions
device disconnect count
safety events
```

## Outcome
```text
completed / stopped / interrupted / failed
actual stop time
actual duration
actual SOC gain
training eligibility
training rejection reason
```

---

# 9. End-of-charge SOC confirmation

When a terminal session has no trusted actual final SOC, show a lightweight sheet/notification:

```text
Pin sau khi sạc

78%

[ Đúng ]     [ Chỉnh ]
```

Requirements:
- non-blocking;
- history is saved even if ignored;
- session may still be used for power-learning if eligible;
- full SOC-duration personalization waits for trusted `actualEndSoc`;
- tapping `Chỉnh` opens the existing horizontal battery selector;
- later BMS/API integration should auto-populate and skip this prompt when a trusted value exists.

Reuse:

```text
PATCH /api/smart-charging/sessions/{sessionId}/actual-soc
```

Do not create a second competing endpoint.

---

# 10. Multi-vehicle architecture

## 10.1 New domain object

Create:

```text
app/lib/core/models/vehicle_context.dart
app/lib/core/providers/vehicle_context_provider.dart
```

Suggested state:

```dart
class VehicleContext {
  final String selectedVehicleId;
  final VehicleModel? selectedVehicle;
  final List<VehicleModel> activeVehicles;
  final bool isRestoring;
}
```

Methods:

```text
selectVehicle(id)
restoreSelection()
selectFirstAvailableIfMissing()
archiveSelectedVehicle()
```

Persist selected vehicle through the existing `SessionService`.

## 10.2 Vehicle count

Add:

```dart
class VehiclePolicy {
  static const int maxVehiclesPerAccount = 2;
}
```

Do not scatter literal `2` across widgets/services.

### Enforcement layers

1. UI:
   - disable `Thêm xe` when two active vehicles already exist;
   - show `Tài khoản hiện hỗ trợ tối đa 2 xe.`

2. service:
   - `AuthService.addVehicle()` must reject over-limit creation.

3. Firestore:
   - security rules must prevent bypass from a modified client.

Use a transaction rather than the current write-batch-only flow so the active vehicle list/count is read and validated atomically.

---

# 11. Archive vehicle instead of delete

Replace consumer-facing:

```text
Xóa xe
```

with:

```text
Lưu trữ xe
```

Confirmation:

```text
Lưu trữ xe này?

Xe sẽ được ẩn khỏi danh sách sử dụng.
Lịch sử sạc và dữ liệu AI của xe vẫn được giữ.

[ Hủy ] [ Lưu trữ ]
```

### Vehicle document

Add:

```text
isArchived: true|false
archivedAt
archivedBy
```

Do NOT set `isDeleted=true` for normal archive.

On archive:
- remove vehicle from active `users/{uid}.vehicles`;
- preserve `Vehicles/{vehicleId}`;
- preserve ChargeLogs;
- preserve smartChargingSessions;
- preserve Personal AI;
- preserve audits;
- prevent starting a new charge for an archived vehicle.

### Restore

Garage → `Xe đã lưu trữ`

Allow restore only if:

```text
activeVehicleCount < maxVehiclesPerAccount
```

---

# 12. Vehicle Switcher UX

Create:

```text
app/lib/core/widgets/vehicle_switcher.dart
```

Visible on:
- Tổng quan
- Sạc
- Lịch sử

Optional compact display in Khác.

Collapsed form:

```text
[ 🛵 ] Feliz 2024
      67% · Pin 93%
                         ▾
```

If charging:

```text
Feliz 2024
67% · Đang sạc
```

On tap, show a bottom sheet with up to two active vehicles.

Each vehicle card:

```text
vehicle icon
vehicle name
battery
SoH
charging status
```

Bottom action:

```text
Quản lý xe
```

If fewer than two vehicles:

```text
+ Thêm xe
```

---

# 13. Vehicle switching while charging

Vehicle switching must NEVER mutate an active session.

Example:

```text
Vehicle A → active session SA
User selects Vehicle B
```

Result:

```text
selectedVehicleId = B
SA.vehicleId remains A
SA.deviceId remains its original device
```

The app shows a persistent global pill:

```text
Feliz 2024 đang sạc · còn 2 giờ 14 phút
```

Tapping it opens A's session.

If two different devices are charging two vehicles at once:

```text
2 xe đang sạc
```

Tap → session chooser.

---

# 14. Vehicle ↔ Shelly binding V4

## 14.1 New model

Create server + app equivalent:

```text
VehicleChargerBinding
```

Suggested fields:

```text
ownerUid
vehicleId
deviceId
createdAt
updatedAt
isDefault
```

Store under:

```text
users/{uid}/vehicleChargerBindings/{vehicleId}
```

The Shelly device metadata itself remains under:

```text
users/{uid}/shellyDevices/{deviceId}
```

## 14.2 Shared Shelly is allowed

Two vehicle bindings may reference the same `deviceId`.

But enforce invariant:

```text
one active charging session per physical device
```

Therefore:

### A → Shelly A, B → Shelly B
Both may charge concurrently.

### A → Shelly X, B → Shelly X
If A is charging:
- B can be selected;
- B cannot start a session on X until A stops.

Consumer message:

```text
Bộ sạc này đang được Xe A sử dụng.
```

## 14.3 Remove single-device selection behavior

Current backend selection revokes other devices.

Replace this behavior for V4.

Keep old endpoint temporarily for compatibility, but do not use it in the V4 app.

Add vehicle-aware APIs:

```text
GET    /api/smart-charging/vehicles/{vehicleId}/charger
PUT    /api/smart-charging/vehicles/{vehicleId}/charger
DELETE /api/smart-charging/vehicles/{vehicleId}/charger
```

PUT body:

```json
{
  "deviceId": "..."
}
```

Server verifies:
- authenticated owner owns vehicle;
- device belongs to account;
- device binding is not revoked.

---

# 15. Make all Smart Charge operations vehicle-aware

## 15.1 Status

Change from account-only:

```text
GET /api/smart-charging/status
```

to preferred V4:

```text
GET /api/smart-charging/status?vehicleId={vehicleId}
```

Legacy no-query behavior may remain temporarily for backward compatibility.

Server resolves:

```text
vehicleId
  ↓
VehicleChargerBinding
  ↓
DeviceBinding
  ↓
Shelly provider
```

## 15.2 Current session

Add:

```text
GET /api/smart-charging/session/current?vehicleId={vehicleId}
```

Also add global active sessions:

```text
GET /api/smart-charging/sessions/active
```

This global endpoint feeds:
- persistent charging pill;
- notification reconciliation;
- cold-start recovery.

## 15.3 Preview/start

Preview already carries `vehicleId`.

At preview creation:
- verify vehicle ownership;
- verify vehicle is not archived;
- resolve current charger binding;
- place `deviceId` into the server-side preview.

At session start:
- use `deviceId` stored in preview;
- do NOT re-resolve to a potentially different newly selected device;
- enforce no active session on the same physical device;
- save both `vehicleId` and `deviceId` in the session.

---

# 16. New navigation

Refactor:

```text
app/lib/navigation/app_navigation.dart
```

New tab indices:

```text
0 Tổng quan
1 Sạc
2 Lịch sử
3 Khác
```

Do not preserve old numeric assumptions such as:

```text
1 = AI
2 = Trip
3 = Service
4 = Settings
```

Search and migrate all uses of:

```dart
AppNavigation.navigateToTab(...)
currentTabProvider
```

Prefer a semantic enum:

```dart
enum AppTab {
  overview,
  charge,
  history,
  more,
}
```

and map it to index only in navigation.

---

# 17. V4 screen structure

## 17.1 Tổng quan

New/Refactored:

```text
app/lib/features/overview/overview_screen.dart
```

Recommended composition:

```text
Vehicle Switcher

Battery Hero
  large horizontal battery visual
  current battery
  SoH
  estimated remaining range when available

Smart Charge
  current charger state
  if active: progress + target + remaining time
  if inactive: primary CTA "Sạc"

AI insight #1
AI insight #2

Small secondary shortcuts
```

Rules:
- no giant list of statistics;
- no engineering vocabulary;
- maximum 2–3 AI insights above the fold;
- unfinished insight cards disabled rather than fake-populated.

## 17.2 Sạc

Use the existing Smart Charge controller/service architecture.

Refactor consumer presentation in:

```text
app/lib/features/ai/smart_charging_control_screen.dart
```

or create a thin feature-level wrapper:

```text
app/lib/features/charge/charge_screen.dart
```

The primary screen should show:

```text
Vehicle Switcher

Connection state

Horizontal battery animation

Current battery → target battery

Target selector

Estimated completion
Target %
Primary charge action

Safety/status only when relevant
```

While charging:

```text
[ animated horizontal battery ]
67% → Mục tiêu 85%

Còn 1 giờ 42 phút
Dự kiến xong 18:35

[ Dừng sạc ]
```

Stop always uses the existing confirmation sheet.

## 17.3 Lịch sử

Refactor:

```text
app/lib/features/ai/smart_charge_history_screen.dart
```

Top:

```text
Vehicle Switcher

[ Xe này ] [ Tất cả xe ]

[ Tất cả ] [ Sạc AI ] [ Thủ công ]
```

When `Xe này`:

```text
vehicleId = selectedVehicleId
```

When `Tất cả xe`:

```text
no vehicle filter
```

## 17.4 Khác

Create:

```text
app/lib/features/more/more_screen.dart
```

Sections:

```text
Xe & AI
  Garage
  AI cá nhân
  Chức năng AI

Chuyến đi
  Trip Planner
  Trip history

Bảo dưỡng
  Maintenance

Dữ liệu
  Statistics

Ứng dụng
  Notifications
  Settings
  Help
```

Every tile uses `FeatureAvailabilityRegistry`.

---

# 18. Minimal history row

Replace verbose history list items with a compact row.

Example:

```text
30/08 · 15:20                    Hoàn tất

32%  →  80%

2 giờ 48 phút · 1.16 kWh        Sạc AI
```

If all-vehicle scope:

```text
Feliz 2024
32% → 80%
2 giờ 48 phút · 1.16 kWh
```

Avoid on the list row:
- voltage;
- current;
- raw model version;
- adapter version;
- telemetry coverage;
- transport;
- confidence internals.

---

# 19. Charging session detail

Top section:

```text
32% → 80%

2 giờ 48 phút
1.16 kWh
Hoàn tất
```

Then chart.

Then:

```text
AI đã dự đoán
Thời gian thực tế
Mục tiêu pin
```

Then collapsed:

```text
Xem chi tiết kỹ thuật
```

Technical content:
- average/peak power;
- voltage;
- current;
- max temperature;
- model/version;
- telemetry quality;
- safety events;
- stop reason.

---

# 20. Chart redesign

Use one chart viewport.

Segment selector:

```text
Pin | Công suất | Năng lượng | Nhiệt độ
```

### Pin
Use only if SOC data quality is sufficient.

If actual SOC is unavailable, label:

```text
Pin ước tính
```

Do not use a `~` prefix.

### Công suất
Y-axis:

```text
W
```

### Năng lượng
Y-axis:

```text
Wh / kWh
```

Energy must be **session-relative**, not Shelly lifetime total.

### Nhiệt độ
Prefer:
- battery temperature when trusted;
- Shelly temperature otherwise, clearly labeled in technical details.

Default:
- `Pin` if SOC series quality is valid;
- otherwise `Năng lượng`.

---

# 21. Preserve chart usability after raw telemetry TTL

Raw high-frequency telemetry expires after 12 months.

Before TTL deletion, keep an indefinite compact visualization series in the session summary:

```text
chartSummary:
  soc: <= 60 points
  power: <= 60 points
  energy: <= 60 points
  temperature: <= 60 points
```

Generate using deterministic downsampling.

This allows old charging sessions to remain understandable even after raw telemetry expires.

---

# 22. History retention policy

## Keep indefinitely
- session summary;
- ChargeLog summary;
- vehicle snapshot;
- target/start/end SOC;
- duration;
- energy;
- charge mode;
- stop reason;
- Personal AI training result;
- compact chart summary;
- safety event summary.

## Keep 12 months
- raw/high-frequency telemetry;
- large debug payloads.

Add Firestore TTL-compatible:

```text
expiresAt
```

to raw telemetry/chunk documents.

Do not add TTL to summary session documents.

---

# 23. History hide vs true delete

## Normal UX

Action:

```text
Ẩn khỏi lịch sử
```

Add:

```text
hiddenByUserAt
```

The session remains:
- in Firestore;
- available for AI training;
- available for audit/privacy export.

Normal history queries exclude hidden records by default.

Optional later view:

```text
Khác → Dữ liệu → Mục đã ẩn
```

## Privacy erase

Separate destructive action:

```text
Xóa dữ liệu sạc này vĩnh viễn
```

Requirements:
- strong confirmation;
- clear Personal AI impact;
- delete training sample derived solely from that session;
- rebuild/revalidate affected Personal AI profile if necessary;
- audit the privacy operation without retaining erased payload.

---

# 24. History API V4

Extend:

```text
GET /api/smart-charging/history
```

Parameters:

```text
limit
cursor
vehicleId
strategy
includeHidden=false
```

Examples:

```text
/api/smart-charging/history?vehicleId=abc&limit=20
/api/smart-charging/history?limit=20
```

### Important backend fix

Apply:
- vehicle filter;
- strategy filter;
- hidden filter;
- cursor;

**inside the datastore query before `limit + 1`.**

Do not fetch 21 records and then filter them in Python.

Add required composite indexes.

---

# 25. FeatureAvailabilityRegistry

Create:

```text
app/lib/core/models/feature_availability.dart
app/lib/core/services/feature_availability_registry.dart
app/lib/core/providers/feature_availability_provider.dart
app/lib/core/widgets/feature_availability_tile.dart
```

Possible state:

```dart
enum FeatureAvailabilityState {
  available,
  needsData,
  needsSetup,
  modelUnavailable,
  offline,
  comingSoon,
  disabled,
}
```

Model:

```dart
class FeatureAvailability {
  final FeatureAvailabilityState state;
  final String? userMessage;
  final String? actionLabel;
}
```

---

# 26. Inputs to availability

The registry combines:

```text
1. implementation manifest
2. remote feature flag
3. active model availability/predictability
4. selected vehicle data
5. charger binding/capabilities
6. auth state
7. network state
```

Priority example:

```text
not implemented
    → comingSoon

implemented but remote-killed
    → disabled

requires model and no active predictable model
    → modelUnavailable

requires vehicle spec but missing
    → needsData

requires Shelly but not bound
    → needsSetup

requires server and offline
    → offline

otherwise
    → available
```

---

# 27. Disabled feature visual contract

For `comingSoon`, `modelUnavailable`, `disabled`:

```text
opacity: 0.45–0.60
tap: disabled
badge: short reason
```

Examples:

```text
Phát hiện bất thường
Đang phát triển
```

```text
Dự đoán quãng đường
Chưa có model
```

Do not display an apparently active CTA that always fails.

For `needsSetup`, keep tap enabled if tapping opens setup:

```text
Sạc thông minh
Cần kết nối bộ sạc
```

For `needsData`, allow tap if the destination explains/fixes missing data.

---

# 28. AI model availability rule

For an AI-labelled function:

```text
active model exists
AND runtime health is predictable
AND feature implementation is complete
```

Otherwise disable.

Do NOT:

```text
model missing
→ run physics
→ display "AI prediction"
```

Physics can be offered only under a clearly non-AI safe fallback mode where the product explicitly supports it.

For Smart Charge:
- AI Charge disabled if strict AI is unavailable.
- safe timed/manual charging may still remain available.

---

# 29. Offline behavior

## Existing screen
Do not navigate user away. Do not blank the UI.

Keep last known data and show a floating connection notice:

```text
Mất kết nối
Đang hiển thị dữ liệu gần nhất.

[ Thử lại ]
```

Reuse:
- `ConnectionCoordinator`
- `ChargingConnectionBanner`
- existing local state.

## Starting a new charge while offline

### AI Charge
Disabled when authoritative server cannot be reached.

Message:

```text
Cần kết nối mạng để bắt đầu Sạc theo AI.
```

### Timed/manual charge
May remain available only if:
- Shelly is reachable safely by supported control path;
- timer can be armed on device;
- readback can be verified.

Never start an unsafe app-only countdown.

---

# 30. Persistent charging state

`PersistentChargingPill` becomes app-global rather than Smart-Charge-screen-only.

Data source:

```text
GET /api/smart-charging/sessions/active
```

plus foreground service/current local session cache.

Display cases:

### Selected vehicle active
```text
Đang sạc · còn 1 giờ 42 phút
```

### Another vehicle active
```text
Feliz 2024 đang sạc · còn 1 giờ 42 phút
```

### Two vehicles active
```text
2 xe đang sạc
```

This pill must survive:
- switching tabs;
- switching selected vehicle;
- temporary server connection loss;
- app resume.

---

# 31. Notification deep-link contract

Every Smart Charge notification payload must include:

```json
{
  "type": "smart_charge",
  "vehicleId": "...",
  "sessionId": "..."
}
```

On tap:
1. fetch/open exact session;
2. render vehicle name in that session;
3. do not silently change `selectedVehicleId`;
4. offer action `Quản lý xe này` if user wants to switch global vehicle context.

Remove any notification flow that opens Smart Charge using a generic/default vehicle ID.

---

# 32. Firestore data model V4

## `users/{uid}`

Keep active vehicle IDs in the existing `vehicles` array for compatibility.

Add/normalize:

```text
vehicles: [active vehicle ids, max 2]
selectedVehicleId: optional cloud preference
vehiclePolicyVersion: 1
```

## `Vehicles/{vehicleId}`

Add:

```text
isArchived: bool
archivedAt
archivedBy
```

Keep:

```text
isDeleted=false
```

for archive.

## `users/{uid}/shellyDevices/{deviceId}`

Keep existing device metadata.

Do not store vehicle-specific relation directly as the only mapping.

## `users/{uid}/vehicleChargerBindings/{vehicleId}`

New:

```text
ownerUid
vehicleId
deviceId
createdAt
updatedAt
```

## `users/{uid}/smartChargingSessions/{sessionId}`

Keep indefinitely.

Ensure/add:

```text
ownerUid
vehicleId
deviceId

vehicleNameSnapshot
vehicleModelSnapshot

startSoc
targetSoc
actualEndSoc

energyUsedWh
duration
strategy
state
stopReason

baseAiMinutes
physicsMinutes
personalMinutes
finalMinutes

personalProfileVersion
baseModelVersion
trainingState
trainingReason

chartSummary
hiddenByUserAt

createdAt
updatedAt
```

## `ChargeLogs/{sessionId}`

Keep existing upsert pattern.

Use it as durable cross-feature charging summary.

Never reset/remove an old log when a new charge starts.

Session energy starts from a session baseline, while Shelly lifetime energy remains untouched.

## `AiVehicleProfiles/{owner+vehicle}`

Continue using existing collection.

This document points to the **current promoted** personal profile.

Add:

```text
promotedVersionId
candidateVersionId
lastValidationAt
lastPromotionAt
```

## New profile-version storage

Recommended:

```text
AiVehicleProfiles/{profileId}/versions/{versionId}
```

Store:
- candidates;
- promoted versions;
- rejected metadata.

Do not duplicate large raw telemetry here.

## Training samples

Continue/normalize:

```text
users/{uid}/chargingTrainingSamples/{sessionId}
```

One immutable sample per session.

Idempotency:

```text
sessionId
```

---

# 33. Firestore rules

Update:

```text
web/firestore.rules
```

Rules must guarantee:

### Vehicles
- authenticated owner only;
- ownerUid immutable after create;
- active vehicle list max 2;
- archive does not transfer ownership.

### Smart Charge history
- owner can read own history;
- normal client cannot change safety/model-controlled server fields;
- preferably server writes authoritative Smart Charge session records.

### Personal AI
- user can read own public profile summary;
- user can change consent through trusted API;
- arbitrary client cannot write model weights/profile metrics directly.

### Charger binding
- user sees only own device/binding records;
- server validates actual binding writes.

---

# 34. Firestore indexes

Update:

```text
web/firestore.indexes.json
```

At minimum support history combinations:

```text
created_at DESC
vehicle_id + created_at DESC
strategy + created_at DESC
vehicle_id + strategy + created_at DESC
```

If hidden filtering is implemented in the same query:

```text
vehicle_id + hiddenByUserAt + created_at DESC
```

Use the actual stored field naming consistently; do not mix snake_case and camelCase across new queries.

---

# 35. Fix naming/schema consistency

The repo currently contains a mixture of:
- `vehicleId`
- `vehicle_id`
- `createdAt`
- `created_at`

V4 should not attempt a destructive full migration in one release.

Rule:

### Existing documents
Read both legacy forms where necessary.

### New authoritative server writes
Pick one canonical wire schema.

Recommended API JSON:

```text
camelCase
```

Recommended Python internal dataclass:

```text
snake_case
```

Repository serializer/deserializer is responsible for translation.

Do not leak raw Firestore field naming into Flutter.

---

# 36. Smart Charge safety requirements

Do not loosen existing safety behavior while redesigning UI.

Preserve:
- device-side timer;
- physical relay verification;
- OFF readback;
- idempotency;
- connection recovery;
- safety events;
- safe boot/no-load verification;
- maximum charging deadline configured by server.

Current server policy already contains warning/cutoff thresholds for:
- current;
- power;
- Shelly temperature;
- voltage.

V4 should centralize policy source and persist a policy snapshot/version into each session so historical safety decisions remain explainable after future threshold changes.

Add:

```text
safetyPolicyVersion
```

to session summary.

---

# 37. Security hardening

## Authentication
All Smart Charge, Personal AI and binding operations stay behind Firebase-authenticated server APIs.

## Ownership
Every server endpoint receiving:

```text
vehicleId
sessionId
deviceId
```

must verify that object belongs to `uid`.

Do not trust a vehicle ID merely because it came from the authenticated app.

## Idempotency
Keep idempotency keys for:
- starting AI session;
- manual ON;
- training ingestion.

## Secrets
Never put:
- Shelly cloud auth keys;
- server credentials;
- admin secrets

into Flutter assets or Firestore-readable user documents.

## Error redaction
Keep the existing `AppErrorReporter` redaction behavior.

## Replay / stale preview
Preview must:
- expire;
- be owner-bound;
- vehicle-bound;
- device-bound.

---

# 38. Home/Overview AI content policy

The Overview should not become an AI dashboard.

At most surface useful outcomes, for example:

```text
AI đang học xe này
Dự đoán sạc đã chính xác hơn sau các phiên gần đây
```

or:

```text
Quãng đường dự kiến: 62 km
```

when the corresponding model is available.

Detailed model catalog/testing remains in:

```text
Khác → AI & Tính năng
```

and admin web dashboard.

---

# 39. Personal AI settings redesign

Refactor:

```text
app/lib/features/settings/personal_ai_settings_screen.dart
```

Consumer view:

```text
AI cá nhân cho Feliz 2024

[toggle] Cho phép AI học từ các lần sạc

Đang học thói quen sạc

AI sẽ dùng dữ liệu sạc của riêng xe này
để dự đoán thời gian chính xác hơn.
```

Optional:

```text
7 phiên phù hợp đã được học
```

Do not show:
- adapter string;
- MAPE;
- correction scale;
- SOC-band count;
- internal model version;

unless Developer Mode/Admin diagnostics is enabled.

Fix any text implying 5 sessions = personalized. Backend threshold remains 10.

---

# 40. User-consent lifecycle

On first Smart Charge setup for a vehicle:

```text
Cá nhân hóa dự đoán cho xe này?

Ứng dụng có thể học từ các phiên sạc của riêng chiếc xe
để dự đoán thời gian chính xác hơn.

[ Không phải bây giờ ] [ Cho phép ]
```

Consent is scoped per vehicle.

Turning Personal AI off:
- stop using future sessions for personal training;
- stop personal candidate contribution in ETA;
- preserve history;
- preserve existing profile unless user explicitly deletes Personal AI data.

Deleting Personal AI data remains a separate destructive action.

---

# 41. App file impact matrix

## Core / navigation

### Modify
```text
app/lib/navigation/app_navigation.dart
app/lib/core/providers/app_providers.dart
app/lib/core/providers/app_state_providers.dart
app/lib/core/services/app_feature_flags.dart
```

### Add
```text
app/lib/core/models/vehicle_context.dart
app/lib/core/providers/vehicle_context_provider.dart
app/lib/core/models/feature_availability.dart
app/lib/core/services/feature_availability_registry.dart
app/lib/core/providers/feature_availability_provider.dart
app/lib/core/widgets/vehicle_switcher.dart
app/lib/core/widgets/feature_availability_tile.dart
```

## New information architecture

### Add
```text
app/lib/features/overview/overview_screen.dart
app/lib/features/charge/charge_screen.dart
app/lib/features/more/more_screen.dart
```

### Refactor/reuse
```text
app/lib/features/home/*
app/lib/features/ai/smart_charging_control_screen.dart
app/lib/features/ai/smart_charge_history_screen.dart
app/lib/features/ai/ai_models_screen.dart
```

Do not delete old screens until V4 feature-flag rollout is stable.

## Vehicle management

### Modify
```text
app/lib/features/settings/vehicle_garage_screen.dart
app/lib/core/services/auth_service.dart
app/lib/data/models/vehicle_model.dart
```

### Add
```text
app/lib/data/models/vehicle_charger_binding.dart
app/lib/data/services/vehicle_charger_binding_service.dart
```

## Personal AI

### Modify
```text
app/lib/data/models/personal_charging_profile.dart
app/lib/data/services/personal_ai_service.dart
app/lib/features/settings/personal_ai_settings_screen.dart
app/lib/data/services/charging_training_sync_service.dart
```

## Smart Charge

### Modify
```text
app/lib/features/ai/controllers/smart_charging_controller.dart
app/lib/data/services/server_smart_charger_service.dart
app/lib/data/repositories/smart_charger_repository.dart
app/lib/features/ai/widgets/persistent_charging_pill.dart
app/lib/features/ai/widgets/charging_connection_banner.dart
app/lib/features/ai/widgets/horizontal_battery_target_selector.dart
app/lib/features/ai/widgets/stop_charging_confirmation_sheet.dart
```

Important: `lastTargetSocKey` is currently global.

Make it vehicle-scoped:

```text
smart_charge_last_target_soc_{vehicleId}
```

so vehicle A's preferred target does not overwrite vehicle B's.

---

# 42. Server file impact matrix

## Modify
```text
web/shelly/models.py
web/shelly/repositories.py
web/shelly/routes.py
web/shelly/service.py
web/shelly/personalization.py
web/shelly/charging_fusion.py
web/smart_charge_worker.py
web/firestore.rules
web/firestore.indexes.json
```

## Add
```text
web/shelly/personal_model_registry.py
```

Optional if service complexity grows:

```text
web/shelly/vehicle_charger_binding.py
```

Keep Personal AI logic server-side.

---

# 43. API compatibility strategy

Do not break installed V3 APKs immediately.

For one rollout cycle:

### Legacy
```text
GET /api/smart-charging/status
GET /api/smart-charging/session/current
```

still work using legacy selected/default binding.

### V4
Flutter always supplies:

```text
vehicleId
```

Server logs legacy endpoint usage.

After V4 adoption is high enough, legacy behavior can be deprecated.

---

# 44. Migration strategy — zero history loss

## Step 1 — deploy server readers first
Server understands:
- archived vehicles;
- vehicle charger bindings;
- old and new session fields;
- old single-device users.

No destructive writes.

## Step 2 — auto-create initial vehicle charger binding
For an account with:
- exactly one active vehicle;
- exactly one existing active Shelly binding;

automatically create:

```text
vehicleId → deviceId
```

No user interaction.

If mapping is ambiguous:
- show setup selector;
- do not guess.

## Step 3 — backfill history snapshots lazily
When an old session is read and vehicle still exists:
- enrich response with vehicle name/model;
- optionally backfill snapshot fields asynchronously.

Do not block History on backfill.

## Step 4 — enable V4 app shell behind new flag

Add:

```text
ui.full_app_v4
```

Keep V3 route available for rollback until QA is complete.

## Step 5 — stop hard vehicle deletes
Deploy Archive before enabling the two-vehicle V4 Garage.

---

# 45. Implementation phases

# P0 — Data safety and multi-vehicle correctness

Must complete before visual redesign rollout.

## P0.1
Create `VehiclePolicy.maxVehiclesPerAccount`.

## P0.2
Replace hard delete with archive/restore.

## P0.3
Add `VehicleChargerBinding`.

## P0.4
Make Smart Charge status/current/history vehicle-aware.

## P0.5
Add global active-session endpoint.

## P0.6
Lock session to `vehicleId + deviceId`.

## P0.7
Enforce one active session per physical device.

## P0.8
Add history vehicle filtering in Firestore query.

## P0.9
Add indexes/rules.

## P0.10
Add non-destructive migrations and backward compatibility.

### P0 exit criteria
No UI redesign is considered safe until:
- A/B data cannot cross;
- archived history remains readable;
- shared Shelly cannot start two sessions concurrently;
- different Shellys may run independent sessions;
- history pagination returns correct vehicle-specific records.

---

# P1 — Minimal EV cockpit app shell

## P1.1
Introduce `AppTab` enum.

## P1.2
Implement 4 tabs:

```text
Tổng quan · Sạc · Lịch sử · Khác
```

## P1.3
Implement `VehicleContextProvider`.

## P1.4
Implement global Vehicle Switcher.

## P1.5
Build minimal Overview.

## P1.6
Move AI, Trip, Service, Statistics, Settings into Khác.

## P1.7
Make Persistent Charging Pill global.

## P1.8
Implement notification session deep links.

### P1 exit criteria
Selecting vehicle B immediately changes all vehicle-scoped normal content, while active vehicle A session continues untouched.

---

# P2 — Feature availability + UX state correctness

## P2.1
Implement `FeatureAvailabilityRegistry`.

## P2.2
Create standard disabled/needs-setup/needs-data widgets.

## P2.3
Connect model runtime health.

## P2.4
Disable AI functions without a usable model.

## P2.5
Implement offline-safe state preservation.

## P2.6
Ensure timed/manual charge remains separate from AI availability.

---

# P3 — History and charts

## P3.1
Add `Xe này · Tất cả xe`.

## P3.2
Simplify rows.

## P3.3
Build one-chart selector.

## P3.4
Generate persistent chart summaries.

## P3.5
Add raw telemetry TTL.

## P3.6
Implement hide/history privacy actions.

## P3.7
Add end-of-session SOC confirmation.

---

# P4 — Personal AI candidate lifecycle

## P4.1
Make training samples immutable/idempotent.

## P4.2
Create profile version registry.

## P4.3
Build candidate from promoted profile.

## P4.4
Validate candidate against held-out/recent historical samples.

## P4.5
Promote/reject.

## P4.6
Keep rollbackable promoted profile.

## P4.7
Store training decision on session.

## P4.8
Refactor consumer Personal AI screen to friendly status only.

---

# P5 — Long-term true per-vehicle model research

Do not block V4 release on this.

## P5.1
Export high-quality training dataset per vehicle.

## P5.2
Evaluate residual model.

## P5.3
Require minimum dataset size/coverage.

## P5.4
Train candidate server-side.

## P5.5
Offline compare against promoted adapter/base model.

## P5.6
Canary activation.

## P5.7
Rollback automatically on regression.

---

# 46. Tests — Flutter unit

Add tests for:

```text
VehiclePolicy
VehicleContext
vehicle selection restore
target SOC storage scoped by vehicle
FeatureAvailabilityRegistry
Personal AI friendly stage mapping
history vehicle/all filtering request construction
archive/restore state
notification deep-link parsing
```

Files recommended:

```text
app/test/unit/vehicle_context_test.dart
app/test/unit/feature_availability_registry_test.dart
app/test/unit/vehicle_policy_test.dart
app/test/unit/notification_smart_charge_route_test.dart
```

---

# 47. Tests — Flutter widget

Add:

```text
app/test/widget/vehicle_switcher_test.dart
app/test/widget/overview_v4_test.dart
app/test/widget/navigation_v4_test.dart
app/test/widget/history_v4_test.dart
app/test/widget/more_feature_availability_test.dart
```

Critical cases:

### Vehicle Switcher
- 1 vehicle.
- 2 vehicles.
- selected vehicle highlight.
- other vehicle charging.
- both vehicles charging.

### Navigation
- only 4 primary tabs.
- AI is no longer a primary tab.
- old features remain reachable via Khác.

### Disabled feature
- visibly dimmed;
- no feature action fires;
- reason visible.

### Offline
- last data remains visible;
- connection banner appears;
- retry works.

---

# 48. Tests — server unit/integration

Extend:

```text
web/tests/test_personal_smart_charge_v3.py
web/tests/test_shelly_cloud_first.py
```

Add:

```text
web/tests/test_multivehicle_smart_charge_v4.py
web/tests/test_personal_candidate_promotion_v4.py
web/tests/test_history_retention_v4.py
```

Must test:

## Multi vehicle
- owner A cannot access owner B vehicle.
- same owner has vehicle A and B isolated.
- A history filter does not return B.
- all-history returns both.
- archived vehicle history remains available.
- archived vehicle cannot start new session.

## Charger binding
- A→device1, B→device2.
- A→device1, B→device1 shared.
- same device second active session rejected.
- separate devices concurrent sessions allowed.
- changing vehicle binding does not alter an active session's device.

## Personal AI
- A and B have separate profiles.
- session A cannot update profile B.
- duplicate ingest is idempotent.
- bad candidate rejected.
- promoted version remains unchanged after rejection.
- good candidate promotes.
- rollback data exists.

## History
- vehicle filter applied before pagination.
- strategy filter applied before pagination.
- cursor has no duplicates.
- hidden records excluded by default.
- old archived vehicle records still readable.

---

# 49. Physical-device QA

Use real Shelly Plug S Gen3.

## Vehicle A

```text
bind Shelly
start AI charge
verify relay ON
verify device timer
switch app to vehicle B
return to A
verify same active session
stop with confirmation
verify relay OFF
```

## Shared device

```text
bind A and B to same Shelly
start A
attempt B
expect blocked: charger is in use
stop A
start B
expect success
```

## Connection failure

```text
active charge
disable phone internet
app remains on same screen
connection warning appears
device timer remains armed
restore internet
app reconciles session
```

## App kill

```text
start charge
force close app
reopen
active session pill restored
correct vehicle/session restored
```

---

# 50. Commands required before merge

Flutter:

```powershell
cd app
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Backend:

```powershell
cd web
python -m pytest tests -q
```

Gateway if touched:

```powershell
cd smart_charger_gateway
python -m pytest tests -q
```

Do not mark V4 complete if any required suite fails.

---

# 51. Recommended implementation branch

At the audited baseline:

```powershell
git checkout feature/smart-charge-user-debug-ai
git pull
git rev-parse HEAD
```

Expected audited SHA:

```text
e27f8fba81cc78045815edfa6a353ae165a5759f
```

Then:

```powershell
git checkout -b feature/full-app-v4-multivehicle-personal-ai
```

If HEAD has changed from the audited SHA, the agent must re-audit changed files before modifying code rather than blindly applying this plan.

---

# 52. Suggested commit sequence

```text
feat(v4): add vehicle context and configurable vehicle limit
feat(v4): archive vehicles without deleting history
feat(v4): add vehicle charger bindings
feat(v4): make smart charging sessions vehicle-aware
feat(v4): add four-tab minimal navigation
feat(v4): add global vehicle switcher
feat(v4): add central feature availability registry
feat(v4): redesign overview and charge experience
feat(v4): simplify charging history and charts
feat(v4): add durable chart summaries and telemetry ttl
feat(v4): add personal ai candidate validation and promotion
test(v4): add multivehicle and personal ai regression coverage
```

Avoid one giant commit.

---

# 53. Definition of Done

V4 is DONE only when all of the following are true.

## Multi-vehicle
- [ ] One account supports two active vehicles.
- [ ] Limit is configurable, not scattered hardcode.
- [ ] Third active vehicle creation is blocked safely.
- [ ] Vehicle Switcher is global and persists selection.
- [ ] Every vehicle-scoped feature uses selected `vehicleId`.
- [ ] Vehicle A data never appears as vehicle B data.

## Charger binding
- [ ] A vehicle has an explicit charger binding.
- [ ] Shared Shelly configuration works.
- [ ] One physical Shelly cannot run two sessions simultaneously.
- [ ] Two distinct Shellys can run independent sessions.
- [ ] Active session remains locked to original vehicle + device.

## Personal AI
- [ ] Profile identity is owner + vehicle.
- [ ] 0–2 sessions = base.
- [ ] 3–9 sessions = calibrating.
- [ ] 10+ sessions = personalized.
- [ ] Every eligible session creates an idempotent training sample.
- [ ] Candidate is validated before promotion.
- [ ] Regressing candidate is rejected.
- [ ] Previous promoted version remains available.
- [ ] Consumer UI hides engineering internals.
- [ ] End SOC confirmation feeds training.
- [ ] Vehicle A cannot train vehicle B.

## History
- [ ] Vehicle history is paginated correctly.
- [ ] `Xe này · Tất cả xe` works.
- [ ] Archive does not delete history.
- [ ] Charging summaries are retained indefinitely.
- [ ] Raw telemetry has 12-month TTL.
- [ ] Compact historical chart remains after raw TTL.
- [ ] Normal user action hides rather than destroys history.
- [ ] Privacy erase is separate and strongly confirmed.

## App UX
- [ ] Main navigation is `Tổng quan · Sạc · Lịch sử · Khác`.
- [ ] AI is not a main tab.
- [ ] Overview is minimal and vehicle-centric.
- [ ] Charging screen shows target SOC while charging.
- [ ] Battery animation replaces number-heavy presentation.
- [ ] Technical history values are collapsed.
- [ ] Offline state keeps current UI/data visible.
- [ ] Global charging pill survives tab and vehicle changes.
- [ ] Notification opens exact session by vehicleId + sessionId.

## Availability
- [ ] One registry decides feature availability.
- [ ] Not-implemented feature is dimmed/disabled.
- [ ] Missing model disables AI action.
- [ ] Missing vehicle data is shown as `Cần thêm dữ liệu`, not fake values.
- [ ] Missing charger setup routes to setup instead of being falsely disabled.
- [ ] No physics fallback is presented as AI.

## Safety/security
- [ ] Existing physical relay readback remains intact.
- [ ] Existing device-side timer remains the independent safety authority.
- [ ] Safety thresholds are not weakened by UI work.
- [ ] Every vehicle/device/session API verifies ownership.
- [ ] Secret material does not enter the APK.
- [ ] Idempotency remains enforced.
- [ ] `flutter analyze` passes.
- [ ] `flutter test` passes.
- [ ] backend pytest passes.
- [ ] release APK builds.
- [ ] real Shelly QA passes.

---

# 54. Implementation rule for the coding agent

The coding agent should treat this as a **migration and consolidation project**, not a greenfield rewrite.

Priority order:

```text
DATA SAFETY
    ↓
VEHICLE/DEVICE ISOLATION
    ↓
SESSION CORRECTNESS
    ↓
PERSONAL AI VALIDATION
    ↓
HISTORY DURABILITY
    ↓
FEATURE AVAILABILITY
    ↓
MINIMAL UI REDESIGN
```

Never trade working charging safety for visual polish.

When a V3 implementation already satisfies the V4 requirement, reuse/refactor it instead of creating a parallel subsystem.

The final architecture should make this invariant obvious everywhere:

> **The account owns vehicles. The selected vehicle defines the app context. Every Smart Charge session is permanently bound to exactly one vehicle and one physical charger. Every Personal AI profile learns only from the history of that vehicle.**

That invariant is the core of V4.
