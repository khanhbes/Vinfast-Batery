# AI CENTER MODEL LAB V2 — IMPLEMENTATION PLAN

## 1. Mục tiêu

Tái cấu trúc toàn bộ trang **AI Center** trên web theo hướng:

- Giữ nguyên dashboard tổng quan, KPI, nhóm model và danh sách model hiện tại.
- Đưa khối test màu đen hiện có của `RangePredictionLab` vào đúng model **Quãng đường còn lại linh hoạt** (`dte`).
- Khi người dùng click một model, khối test màu đen mới xuất hiện ngay bên dưới card/hàng chứa model đó.
- Toàn bộ các model còn lại dùng cùng một hệ thống test UI thống nhất, thiết kế giống khối màu đen hiện tại.
- Nội dung, input, icon, output, chart và unit thay đổi động theo từng model.
- Nếu model chưa có version active/deployed/loaded/predictable thì nút **Chạy dự đoán** bị disable.
- Có nút **Upload model** và **Quản lý model**.
- Luồng quản lý model phải hỗ trợ: upload, validate, smoke test, test version, deploy, active/load, deactivate, delete, quản lý nhiều version.
- Không tạo 9 màn test riêng. Tạo một `UniversalModelLab` dùng metadata của registry để sinh UI.
- Giữ nguyên API/backend hiện có nếu đã đủ khả năng; chỉ bổ sung metadata/contract khi cần.

---

## 2. Phạm vi repo

Branch mục tiêu:

```text
feature/ai-target-charging-uiux
```

Các phần liên quan chính:

```text
web/dashboard/src/pages/AiCenter.tsx
web/dashboard/src/components/ai-center/ModelCatalog.tsx
web/dashboard/src/components/ai-center/ModelTypeCard.tsx
web/dashboard/src/components/ai-center/ModelDetailPanel.tsx
web/dashboard/src/components/ai-center/RangePredictionLab.tsx
web/dashboard/src/components/ai-center/UploadDialog.tsx
web/dashboard/src/components/ai-center/PredictionResultChart.tsx
web/dashboard/src/components/ai-center/types.ts
web/dashboard/src/api.js

web/ai_server/registry.py
web/server.py
web/ai_server/*
web/tests/*
```

---

## 3. Kiến trúc UI cuối cùng

Sau khi triển khai:

```text
AI Center
│
├── Header
│   ├── AI Center
│   ├── Quản lý và giám sát...
│   └── Cài đặt
│
├── KPI tổng quan
│   ├── Tổng mô hình
│   ├── Đã triển khai
│   ├── Model đã nạp
│   └── Tổng versions
│
├── Nhóm: Tính năng Sinh tồn
│   ├── Dự đoán tiêu hao pin
│   ├── Quãng đường còn lại linh hoạt
│   └── Đánh giá hành vi lái xe
│
├── Nhóm: Trợ lý Thông minh
│   ├── Gợi ý tuyến đường tiết kiệm pin
│   ├── Smart Charge
│   ├── Nhắc sạc thông minh
│   └── Nhận diện mục đích chuyến đi
│
└── Nhóm: Sức khỏe Xe
    ├── Dự đoán độ chai pin
    └── Phát hiện bất thường
```

Khi click một model:

```text
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Tiêu hao pin │ │ DTE          │ │ Eco Driving  │
└──────────────┘ └──────▲───────┘ └──────────────┘
                        │ selected

┌────────────────────────────────────────────────────┐
│                UNIVERSAL MODEL LAB                 │
│                                                    │
│  Inputs                               Result       │
│                                                    │
│  sliders / fields                    big result    │
│  icons                               metrics       │
│                                      chart         │
│                                                    │
│ [ Chạy dự đoán ] [ Quản lý model ]                │
└────────────────────────────────────────────────────┘
```

Chỉ một lab được mở tại một thời điểm.

---

## 4. Quyết định UX đã chốt

```text
1A — Lab mở ngay bên dưới model đang chọn.
2A — Một layout chung, nội dung động theo metadata.
3B — Chỉ model active/deployed/loaded/predictable mới được chạy.
4A — Có nút Quản lý model trong lab, mở panel/drawer.
5A — Upload → Validate → Smoke Test → Test → Deploy → Active.
6A — Áp dụng cho toàn bộ 9 model.
7A — Giữ KPI + nhóm + card model; chỉ bỏ RangePredictionLab độc lập.
```

---

## 5. Phase 0 — Baseline

Trước khi sửa:

```bash
git checkout feature/ai-target-charging-uiux
git pull
git checkout -b feature/ai-center-model-lab-v2
```

Frontend:

```bash
cd web/dashboard
npm install
npm run build
npm test
```

Backend:

```bash
cd ../..
pytest
```

Ghi lại baseline hiện tại trước khi refactor.

---

## 6. Phase 1 — Bỏ RangePredictionLab độc lập khỏi AI Center

Hiện `AiCenter.tsx` đang render:

```tsx
<RangePredictionLab />
<ModelCatalog />
```

Phải đổi thành:

```tsx
<ModelCatalog />
```

Xóa import:

```tsx
import RangePredictionLab from '@/components/ai-center/RangePredictionLab';
```

Không xóa file ngay ở bước đầu.

Mục tiêu:

```text
Khối màu đen không còn hiện mặc định ở đầu AI Center.
```

Khối này chỉ xuất hiện khi user click model `dte`.

---

## 7. Phase 2 — Đưa Range Prediction vào đúng model DTE

Model key:

```text
dte
```

Label:

```text
Quãng đường còn lại linh hoạt
```

Khi click card DTE:

```text
ModelTypeCard(dte)
↓
selectedKey = "dte"
↓
UniversalModelLab(meta=dte)
↓
render Range Prediction UI
```

Không còn `RangePredictionLab` độc lập.

---

## 8. Phase 3 — Sửa contract metadata DTE

Đây là P0.

Hiện metadata `dte` đang có dấu hiệu copy từ `soc` nhưng UI Range Prediction thực tế sử dụng:

```text
estimatedRangeKm
rangeLowKm
rangeHighKm
confidence
adjustedEfficiencyKmPerPercent
```

Phải thống nhất lại contract.

DTE nên khai báo theo bài toán range:

```python
"dte": {
    "key": "dte",
    "label": "Quãng đường còn lại linh hoạt",
    "shortName": "Dynamic DTE",
    "description": "Ước tính quãng đường còn lại dựa trên tình trạng pin và điều kiện vận hành.",
    "outputDescription": "Quãng đường còn lại dự kiến.",
    "outputUnit": "km",
    "display_unit": "distance",
}
```

Input nên tương ứng với Range Prediction hiện tại:

```text
batteryPercent
stateOfHealth
temperatureC
averageSpeedKmh
payloadKg
baseEfficiencyKmPerPercent
```

Hoặc dùng naming convention backend thống nhất, nhưng frontend và backend phải cùng contract.

---

## 9. Phase 4 — Chuẩn hóa metadata toàn bộ 9 model

Mỗi model phải có tối thiểu:

```text
key
label
shortName
description
useCase
icon
accent
group
phase
status

inputFields
visibleInputFields
inputSchema
derivedFields
sampleInput

outputKind
outputUnit
displayUnit
outputMeaning

runtimeStatus
```

Không để `UniversalModelLab` phải hardcode từng model.

---

## 10. Bổ sung label thân thiện vào InputSchema

Mở rộng frontend `InputSchema`:

```ts
export interface InputSchema {
  type: 'string' | 'integer' | 'number';
  label?: string;
  desc?: string;
  unit?: string;
  min?: number;
  max?: number;
  step?: number;
  enum?: number[] | string[];
  enumLabels?: string[];
}
```

Ví dụ backend:

```python
"avg_speed_kmh": {
    "type": "number",
    "label": "Tốc độ trung bình",
    "desc": "Tốc độ trung bình trong chuyến đi",
    "unit": "km/h",
    "min": 0,
    "max": 120,
    "step": 1,
}
```

Không hiển thị raw field như `avg_speed_kmh`, `ambient_temp_c`, `payload_kg` trên UI user.

---

## 11. Phase 5 — Tạo UniversalModelLab

Tạo:

```text
web/dashboard/src/components/ai-center/lab/UniversalModelLab.tsx
```

Component nhận:

```tsx
<UniversalModelLab
  meta={selectedModel}
  onModelChanged={reload}
/>
```

Cấu trúc:

```text
UniversalModelLab
│
├── ModelLabHeader
├── ModelAvailabilityBanner
├── ModelInputPanel
├── ModelResultPanel
├── ModelLabActions
└── ModelManagerDrawer
```

---

## 12. Structure folder mới

```text
web/dashboard/src/components/ai-center/
│
├── ModelCatalog.tsx
├── ModelTypeCard.tsx
│
├── lab/
│   ├── UniversalModelLab.tsx
│   ├── ModelLabHeader.tsx
│   ├── ModelAvailabilityBanner.tsx
│   ├── ModelInputPanel.tsx
│   ├── DynamicInput.tsx
│   ├── ModelResultPanel.tsx
│   ├── ScalarResult.tsx
│   ├── VectorResult.tsx
│   ├── ClassResult.tsx
│   └── modelLabUtils.ts
│
├── management/
│   ├── ModelManagerDrawer.tsx
│   ├── ModelVersionsList.tsx
│   ├── ModelVersionActions.tsx
│   └── UploadDialog.tsx
│
├── PredictionResultChart.tsx
├── modelAvailability.ts
├── modelIcons.ts
└── types.ts
```

---

## 13. Phase 6 — Giữ design y hệt khối đen hiện tại

Base design lấy từ `RangePredictionLab.tsx`.

Khung chung:

```tsx
<section className="overflow-hidden rounded-2xl border bg-slate-950 text-white shadow-sm">
```

Grid:

```tsx
<div className="grid lg:grid-cols-[1.1fr_.9fr]">
```

Bên trái:

```text
Model badge
Title
Description
Inputs
Run button
Manage Model button
```

Bên phải:

```text
Progress / visual
Result title
Large value
Secondary metrics
Chart
Confidence
Interpretation
```

---

## 14. Accent color động

Background luôn giữ:

```text
bg-slate-950
```

Accent thay đổi theo model metadata:

```text
emerald
amber
violet
blue
rose
slate
```

Accent dùng cho icon, label, slider, button, progress, status dot, result highlight, chart accent.

---

## 15. Phase 7 — Tách icon map dùng chung

Tạo:

```text
web/dashboard/src/components/ai-center/modelIcons.ts
```

Ví dụ:

```ts
export const MODEL_ICONS = {
  BatteryCharging,
  Gauge,
  Award,
  Navigation,
  Timer,
  BellRing,
  MapPin,
  HeartPulse,
  Stethoscope,
};
```

Dùng chung cho `ModelTypeCard`, `UniversalModelLab`, `ModelManagerDrawer`.

---

## 16. Phase 8 — Dynamic input renderer

Tạo:

```text
DynamicInput.tsx
```

Rules:

```text
number + min/max → slider + number
integer + min/max → slider + number
enum → segmented control hoặc select
string → text input
boolean nếu sau này có → switch
```

Input render từ:

```ts
meta.visibleInputFields ?? meta.inputFields
```

---

## 17. Derived Fields

Không hiển thị derived fields cho user.

Ví dụ Smart Charge:

```text
delta_soc
avg_charge_rate
temp_deviation
```

User chỉ thấy:

```text
Pin hiện tại
Pin muốn sạc đến
Nhiệt độ
```

Trước khi predict:

```text
visible fields
↓
derive hidden fields
↓
final payload
↓
aiQuickPredict()
```

Tạo helper:

```text
buildPredictionPayload(meta, inputState)
```

---

## 18. Phase 9 — Dynamic result renderer

Tạo:

```text
ModelResultPanel.tsx
```

Rules:

```text
displayUnit == "time" → formatted duration
displayUnit == "percentage" → %
displayUnit == "distance" → km
displayUnit == "scalar" → numeric value
outputKind == "vector" → chart
outputKind == "class" → classification card/badge
```

---

## 19. Scalar Result

Tạo `ScalarResult.tsx`.

Ví dụ:

```text
Điểm lái xe
87 / 100
```

hoặc:

```text
Mức bất thường
0.87
```

---

## 20. Vector Result

Tạo `VectorResult.tsx` và reuse `PredictionResultChart.tsx`.

Dùng cho `eco_routing`, `soh_degradation` và model vector khác.

---

## 21. Class Result

Tạo `ClassResult.tsx`.

Ví dụ:

```text
Mục đích chuyến đi
NHÀ → CÔNG TY

Độ tin cậy
94%
```

Không render class output bằng raw JSON.

---

## 22. Model-specific content nhưng không model-specific component

Không tạo:

```text
DteLab.tsx
SmartChargeLab.tsx
EcoDrivingLab.tsx
...
```

Chỉ cho phép renderer đặc biệt nếu output thực sự khác loại như `scalar`, `vector`, `class`, và sau này có thể mở rộng `map`, `timeline`, `multi-route`.

---

## 23. Phase 10 — DTE Lab

Header:

```text
RANGE PREDICTION · V1
Quãng đường còn lại linh hoạt
```

Input:

```text
Pin hiện tại
Sức khỏe pin
Nhiệt độ
Tốc độ trung bình
Tải trọng
Hiệu suất cơ sở
```

Result:

```text
Quãng đường dự kiến
64.2 km

Khoảng an toàn
58–70 km

Độ tin cậy
93%

Hiệu suất đã chỉnh
1.4 km/%
```

---

## 24. Phase 11 — Eco Driving Lab

Header:

```text
ECO DRIVING · V1
Đánh giá hành vi lái xe
```

Input:

```text
Tăng tốc mạnh
Phanh gấp
Tốc độ trung bình
Tốc độ tối đa
Độ biến thiên gia tốc
Thời gian chuyến đi
Thời gian dừng
```

Result:

```text
Điểm lái xe
87 / 100

Phong cách
Tiết kiệm

Tăng tốc
Tốt

Phanh
Tốt
```

---

## 25. Phase 12 — Eco Routing Lab

Input:

```text
Tuyến 1: quãng đường, traffic index, elevation
Tuyến 2: quãng đường, traffic index, elevation
Pin hiện tại
Nhiệt độ
```

Result:

```text
Tuyến nên chọn
Tuyến 2

Tiết kiệm dự kiến
3.2%

Tuyến 1
8.4% pin

Tuyến 2
5.2% pin
```

Nếu output vector thì render comparison chart.

---

## 26. Phase 13 — Smart Charge Lab

Input visible:

```text
Pin hiện tại
Pin muốn sạc đến
Nhiệt độ
```

Hidden derived:

```text
delta_soc
avg_charge_rate
temp_deviation
```

Result:

```text
Thời gian dự kiến
2 giờ 45 phút

Mức tăng pin
60%

Độ tin cậy
...
```

---

## 27. Phase 14 — Charging Recommendation Lab

Input:

```text
Pin hiện tại
Ngày trong tuần
Quãng đường trung bình tuần
Quãng đường trung bình cùng thứ
Lần sạc cuối
Tỷ lệ sạc ban đêm
Số chuyến cuối tuần
```

Result:

```text
Nên sạc
TỐI NAY

Khả năng cần sạc
87%

Thời gian đề xuất
22:00
```

---

## 28. Phase 15 — Trip Labeling Lab

Input:

```text
Điểm bắt đầu
Latitude
Longitude

Điểm đến
Latitude
Longitude

Giờ bắt đầu
Ngày trong tuần
Thời gian chuyến đi
Quãng đường
Tần suất tháng
```

Result:

```text
Mục đích chuyến đi
NHÀ → CÔNG TY

Độ tin cậy
94%
```

Không ép tọa độ thành slider nếu không phù hợp.

---

## 29. Phase 16 — SoH Degradation Lab

Input:

```text
Sức khỏe pin hiện tại
Số chu kỳ
Độ sâu xả
Tỷ lệ sạc nhanh
Nhiệt độ sạc
Số tháng sử dụng
Tỷ lệ lái mạnh
```

Result:

```text
Sức khỏe pin dự kiến
80%

Còn khoảng
23 tháng

[ degradation line chart ]
```

---

## 30. Phase 17 — Anomaly Detection Lab

Input:

```text
Pin dự kiến giảm
Pin thực tế giảm
Quãng đường
Tốc độ
Nhiệt độ
Số lần bất thường liên tiếp
```

Result:

```text
Mức bất thường
CAO

Score
0.87

Khuyến nghị
Kiểm tra pin / lốp
```

---

## 31. Phase 18 — Inline selection behavior

Giữ state `selectedKey` nhưng đổi render strategy.

```ts
setSelectedKey(prev => prev === model.key ? null : model.key);
```

Behavior:

```text
click DTE → DTE lab open
click Eco Driving → DTE close → Eco lab open
click Eco Driving again → close
```

---

## 32. Render lab ngay dưới hàng model

Không render `ModelDetailPanel` một lần ở cuối toàn catalog nữa.

Cần insert lab sau row chứa selected card.

Recommended:

```text
Desktop: 3 cards / row → lab full width
Tablet: 2 cards / row → lab full width
Mobile: 1 card → lab ngay dưới card
```

Có thể refactor thành `ModelGroupGrid`.

---

## 33. Responsive behavior

Lab:

```text
desktop → 2 columns
mobile → stacked
```

Buttons không overflow, result panel không bị bó hẹp.

---

## 34. Phase 19 — Animation

Dùng `motion/react`:

```text
opacity 0 → 1
translateY 8 → 0
height auto
```

Duration:

```text
180–250ms
```

---

## 35. Phase 20 — Model availability helper

Tạo:

```text
web/dashboard/src/components/ai-center/modelAvailability.ts
```

```ts
type ModelAvailabilityState =
  | 'no_model'
  | 'uploaded_only'
  | 'deployed_not_loaded'
  | 'loading'
  | 'ready'
  | 'invalid'
  | 'error';
```

Helper:

```ts
getModelAvailability(meta)
```

---

## 36. Rule canPredict

Chỉ cho predict khi:

```ts
const canPredict =
  isDeployed(meta) &&
  Boolean(activeVersion) &&
  meta.runtimeStatus.isLoaded === true &&
  meta.runtimeStatus.isPredictable === true;
```

Không dùng `versionsCount > 0` làm điều kiện chạy.

---

## 37. State: chưa có model

Nếu `versionsCount == 0`:

```text
Chưa có model
Hãy upload model trước khi chạy dự đoán.

[ Upload model ]
```

Run disabled.

---

## 38. State: đã upload nhưng chưa deploy

Nếu có version nhưng `activeVersion == null`:

```text
Model chưa được triển khai
Bạn đã upload model nhưng chưa chọn version hoạt động.

[ Quản lý model ]
```

Run disabled.

---

## 39. State: deployed nhưng chưa loaded

Nếu có activeVersion nhưng `isLoaded == false`:

```text
Đang chuẩn bị model...
```

Có thể gọi `aiLoadActiveModel(typeKey)` một lần. Run disabled trong lúc load.

---

## 40. State: load lỗi

```text
Không thể nạp model

[ Thử lại ]
[ Quản lý model ]
```

Run disabled.

---

## 41. State: loaded nhưng không predictable

```text
Model có lỗi và chưa thể chạy.

[ Quản lý model ]
```

Run disabled.

---

## 42. State: ready

Nếu active + loaded + predictable:

```text
● Sẵn sàng
v1.x.x
```

Run enabled.

---

## 43. ModelTypeCard phải dùng cùng availability helper

Refactor logic status hiện có sang `modelAvailability.ts` và dùng chung cho:

```text
ModelTypeCard
UniversalModelLab
ModelManagerDrawer
```

Tránh card và lab báo trạng thái khác nhau.

---

## 44. Phase 21 — Prediction API

Admin Universal Lab dùng:

```js
aiQuickPredict(typeKey, payload)
```

Endpoint:

```text
/api/admin/ai/models/:typeKey/predict
```

Không tạo 9 API frontend riêng.

Public APIs cho mobile như `/api/ai/predict-range`, `/api/ai/predict-charging-time` vẫn giữ.

---

## 45. Prediction state

Khi click Run:

```text
spinner
Đang dự đoán...
```

Disable double click.

---

## 46. Result loading

Dùng skeleton và giữ layout ổn định. Có thể giữ kết quả cũ với opacity thấp trong lúc refresh.

---

## 47. Prediction error

```text
Không thể chạy dự đoán
Model không phản hồi hoặc dữ liệu chưa hợp lệ.

[ Thử lại ]
```

Không crash toàn trang.

---

## 48. Phase 22 — Model Manager Drawer

Tạo:

```text
web/dashboard/src/components/ai-center/management/ModelManagerDrawer.tsx
```

Bấm `Quản lý model` mở drawer/panel lớn, không chuyển route.

---

## 49. Drawer layout

```text
┌──────────────────────────────────────┐
│ Quản lý model                     X │
│                                      │
│ Smart Charge                         │
│ Active: v1.3.0                       │
│                                      │
│ [ Upload model ]                     │
│                                      │
│ Versions                             │
│                                      │
│ v1.4.0                               │
│ Uploaded · Smoke test ✓              │
│ [Test] [Deploy] [Delete]             │
│                                      │
│ v1.3.0 ACTIVE                        │
│ Loaded · Predictable                 │
│ [Deactivate]                         │
└──────────────────────────────────────┘
```

---

## 50. Reuse logic ModelDetailPanel

Không viết lại business logic. Refactor các chức năng sẵn có như list models, delete, quick predict, load active, deactivate, test version, deploy, upload thành management components mới.

---

## 51. Tabs management

Drawer có thể có:

```text
Versions
Test version
Đánh giá
```

Default là `Versions` vì Universal Lab đã là nơi chạy active model.

---

## 52. Phase 23 — Upload model

Reuse `UploadDialog.tsx`.

Nút Upload xuất hiện ở:

```text
UniversalModelLab
ModelManagerDrawer
NoModelState
```

---

## 53. Upload flow bắt buộc

```text
UPLOAD
↓
VALIDATE
↓
SMOKE TEST
↓
TEST VERSION
↓
DEPLOY
↓
ACTIVE
↓
LOAD
↓
PREDICTABLE
↓
RUN
```

Không upload rồi auto active.

---

## 54. Upload form

```text
File model
Version
Ghi chú

[ Upload & kiểm tra ]
```

Option `Skip smoke test` chỉ dành cho debug/admin nâng cao, không hiển thị mặc định.

---

## 55. Upload success state

```text
Upload thành công
Version v1.4.0

✓ File hợp lệ
✓ Smoke test pass

[ Test version ]
[ Deploy ]
```

Không tự deploy.

---

## 56. Upload fail

```text
Upload thất bại
Smoke test không đạt.

Chi tiết: ...

[ Thử lại ]
```

Không trở thành active version.

---

## 57. Phase 24 — Version management

Danh sách version cần có:

```text
Version
Status
Uploaded time
Size
Note
Actions
```

Ví dụ:

```text
v1.4.0
Uploaded
Smoke ✓
[Test] [Deploy] [Delete]
```

Active:

```text
v1.3.0
ACTIVE
Loaded
Predictable
[Deactivate]
```

---

## 58. Deploy flow

Confirm trước khi deploy:

```text
Triển khai version v1.4.0?
Version này sẽ trở thành model active cho chức năng này.
```

Sau deploy:

```text
deploy
↓
reload metadata
↓
load active model
↓
check isPredictable
```

---

## 59. Delete active version

Không xóa silently.

```text
Version này đang được sử dụng.
Nếu xóa, chức năng dự đoán sẽ bị vô hiệu hóa.

[ Hủy ]
[ Xóa và vô hiệu hóa ]
```

---

## 60. Deactivate model

Action `Deactivate` phải làm lab chuyển về trạng thái disabled sau reload.

---

## 61. Phase 25 — API reuse

Ưu tiên dùng API hiện có:

```text
aiListTypes
aiListModels
aiQuickPredict
aiLoadActiveModel
aiActivateModel
aiDeactivateModel
aiValidateVersion
aiTestVersion
aiDeployModel
aiDeleteModel
aiUploadModel
```

Không tạo API duplicate nếu API cũ đã đáp ứng.

---

## 62. Phase 26 — Text số model phải dynamic

Không hardcode:

```text
8 mô hình AI
```

Đổi thành:

```tsx
`${types.length} mô hình AI`
```

---

## 63. 9 model phải được hỗ trợ

```text
1. Dự đoán tiêu hao pin
2. Quãng đường còn lại linh hoạt
3. Đánh giá hành vi lái xe
4. Gợi ý tuyến đường tiết kiệm pin
5. Smart Charge
6. Nhắc sạc thông minh
7. Nhận diện mục đích chuyến đi
8. Dự đoán độ chai pin (SoH)
9. Phát hiện bất thường & tụt pin ảo
```

---

## 64. Phase 27 — Loading UX

Khi click model, nếu status đang load thì dùng skeleton có cùng chiều cao với lab. Không render form rồi nhảy layout.

---

## 65. Phase 28 — Empty state UX

No model:

```text
Chưa có model
Upload model để bắt đầu kiểm thử chức năng này.

[ Upload model ]
```

Uploaded only:

```text
Đã có model nhưng chưa triển khai

[ Quản lý model ]
```

---

## 66. Phase 29 — Status badge

Header lab có trạng thái:

```text
● Sẵn sàng · v1.3.0
● Chưa có model
● Chưa deploy
● Đang nạp
● Có lỗi
```

---

## 67. Phase 30 — Mobile responsive

Desktop: lab 2 cột.

Mobile:

```text
Header
Inputs
Run button
Result
Manager button
```

Không overflow.

---

## 68. Phase 31 — Accessibility

Inputs phải có label, aria-label, keyboard support, focus state. Không dựa hoàn toàn vào màu để báo status.

---

## 69. Phase 32 — Frontend tests

Tạo `UniversalModelLab.test.tsx`.

Test:

```text
render scalar model
render vector model
render class model
render DTE
render Smart Charge
```

---

## 70. Test click behavior

```text
click DTE → lab open
click Eco Driving → DTE close → Eco Driving open
click Eco Driving again → close
```

---

## 71. Test availability

```text
versionsCount=0 → Run disabled
version exists + activeVersion=null → Run disabled
activeVersion exists + isLoaded=false → Run disabled/loading
isLoaded=true + isPredictable=false → Run disabled
isLoaded=true + isPredictable=true → Run enabled
```

---

## 72. Test upload flow

```text
upload
→ version appears
→ run remains disabled
```

Sau đó:

```text
test version
→ deploy
→ load
→ predictable
→ run enabled
```

---

## 73. Test DTE contract

Input:

```text
batteryPercent
stateOfHealth
temperatureC
averageSpeedKmh
payloadKg
baseEfficiencyKmPerPercent
```

Output:

```text
estimatedRangeKm
rangeLowKm
rangeHighKm
confidence
adjustedEfficiencyKmPerPercent
```

UI phải render đúng `km`.

---

## 74. Backend registry tests

```python
for key, model in MODEL_TYPES.items():
    assert model["key"]
    assert model["label"]
    assert model["input_fields"]
    assert model["smoke_input"]
    assert model["output_kind"]
```

---

## 75. Validate visibleInputFields

```text
visibleInputFields ⊆ inputFields
```

---

## 76. Validate inputSchema

```text
inputSchema keys ⊆ inputFields
min <= max
```

---

## 77. Validate derived fields

Derived field phải thuộc inputFields và dependencies trong `from` phải tồn tại.

---

## 78. Integration test DTE

```text
Open AI Center
↓
Range Prediction standalone không xuất hiện
↓
Click DTE
↓
Black Lab mở
↓
Inputs đúng
↓
Model ready
↓
Run
↓
Prediction API
↓
Result km
```

---

## 79. Integration test no model

```text
Click model chưa upload
↓
Black Lab mở
↓
Run disabled
↓
Upload model visible
```

---

## 80. Integration test uploaded only

```text
Upload model
↓
Smoke pass
↓
Not deployed
↓
Run disabled
↓
Manage model visible
```

---

## 81. Integration test deploy

```text
Deploy version
↓
load active
↓
predictable true
↓
Run enabled
```

---

## 82. Integration test model switching

```text
Open model A
↓
Run
↓
Result A

Click model B
↓
A closes
↓
B opens
↓
Inputs reset to B sampleInput
```

Không giữ input model A trong model B.

---

## 83. Error handling

Prediction error:

```text
Không thể chạy dự đoán.
[ Thử lại ]
```

Upload error:

```text
Không thể upload model.
```

Load error:

```text
Không thể nạp model.
```

Không crash toàn trang.

---

## 84. Không render raw JSON cho user

Không hiển thị output JSON thô. Phải format theo `outputKind`, `displayUnit`, `outputMeaning`.

---

## 85. Không hardcode model-specific frontend API

Admin Lab không làm:

```text
if dte → aiPredictRange
if charging_time → aiPredictChargingTime
...
```

Mà dùng:

```text
aiQuickPredict(typeKey, payload)
```

---

## 86. Không duplicate Model Manager logic

Không giữ hai hệ thống management đầy đủ song song. Refactor business logic dùng chung.

---

## 87. Migration strategy

```text
1. Add UniversalModelLab
2. Move DTE UI vào lab
3. Universalize inputs/results
4. Move ModelDetailPanel management logic vào Drawer
5. Remove old detail panel render
6. Remove obsolete RangePredictionLab
```

Không xóa component cũ trước khi migration hoàn thành.

---

## 88. File cần sửa chính

### Frontend

```text
web/dashboard/src/pages/AiCenter.tsx
web/dashboard/src/components/ai-center/ModelCatalog.tsx
web/dashboard/src/components/ai-center/ModelTypeCard.tsx
web/dashboard/src/components/ai-center/ModelDetailPanel.tsx
web/dashboard/src/components/ai-center/RangePredictionLab.tsx
web/dashboard/src/components/ai-center/UploadDialog.tsx
web/dashboard/src/components/ai-center/PredictionResultChart.tsx
web/dashboard/src/components/ai-center/types.ts
web/dashboard/src/api.js
```

### Backend

```text
web/ai_server/registry.py
```

Có thể thêm/sửa `web/ai_server/*` hoặc `web/server.py` chỉ khi API quick predict/status chưa đáp ứng.

---

## 89. File mới đề xuất

```text
web/dashboard/src/components/ai-center/lab/UniversalModelLab.tsx
web/dashboard/src/components/ai-center/lab/ModelLabHeader.tsx
web/dashboard/src/components/ai-center/lab/ModelAvailabilityBanner.tsx
web/dashboard/src/components/ai-center/lab/ModelInputPanel.tsx
web/dashboard/src/components/ai-center/lab/DynamicInput.tsx
web/dashboard/src/components/ai-center/lab/ModelResultPanel.tsx
web/dashboard/src/components/ai-center/lab/ScalarResult.tsx
web/dashboard/src/components/ai-center/lab/VectorResult.tsx
web/dashboard/src/components/ai-center/lab/ClassResult.tsx
web/dashboard/src/components/ai-center/lab/modelLabUtils.ts

web/dashboard/src/components/ai-center/management/ModelManagerDrawer.tsx
web/dashboard/src/components/ai-center/management/ModelVersionsList.tsx
web/dashboard/src/components/ai-center/management/ModelVersionActions.tsx

web/dashboard/src/components/ai-center/modelAvailability.ts
web/dashboard/src/components/ai-center/modelIcons.ts
```

---

## 90. Definition of Done

- [ ] `RangePredictionLab` không còn đứng độc lập ở đầu AI Center.
- [ ] Click `Quãng đường còn lại linh hoạt` mới mở khối black lab.
- [ ] Click model khác đóng lab cũ và mở lab mới.
- [ ] Click lại model đang chọn đóng lab.
- [ ] Cả 9 model dùng chung `UniversalModelLab`.
- [ ] Không có 9 component lab riêng.
- [ ] Inputs sinh từ metadata.
- [ ] Labels thân thiện, không hiện raw field name.
- [ ] Icons sinh theo metadata.
- [ ] Accent sinh theo metadata.
- [ ] Derived fields không hiện trên UI.
- [ ] Scalar output render đúng.
- [ ] Vector output có chart.
- [ ] Class output có classification UI.
- [ ] DTE output đúng đơn vị km.
- [ ] DTE metadata đúng contract Range Prediction.
- [ ] Smart Charge input/output đúng.
- [ ] Text số model dùng `types.length`.
- [ ] Model chưa upload → Run disabled.
- [ ] Model upload nhưng chưa deploy → Run disabled.
- [ ] Model chưa loaded → Run disabled/loading.
- [ ] Model không predictable → Run disabled.
- [ ] Chỉ active + loaded + predictable mới Run.
- [ ] Có nút Upload model.
- [ ] Có nút Quản lý model.
- [ ] Model Manager mở drawer/panel.
- [ ] Upload không tự deploy.
- [ ] Validate model sau upload.
- [ ] Smoke test model.
- [ ] Có test version.
- [ ] Có deploy version.
- [ ] Có deactivate.
- [ ] Có delete.
- [ ] Delete active version có confirmation rõ ràng.
- [ ] Active version được highlight.
- [ ] Reload status sau deploy/delete/deactivate.
- [ ] Responsive desktop/tablet/mobile.
- [ ] Loading state ổn định.
- [ ] Prediction errors không crash trang.
- [ ] Upload errors không crash trang.
- [ ] Frontend tests pass.
- [ ] Backend tests pass.
- [ ] Production build pass.

---

## 91. Thứ tự triển khai cho agent

### P0 — Core architecture

```text
1. Remove standalone RangePredictionLab from AiCenter
2. Fix DTE registry contract
3. Normalize metadata 9 models
4. Extend InputSchema with label/step
5. Create modelIcons
6. Create modelAvailability
7. Create UniversalModelLab
8. Create DynamicInput
9. Create ModelResultPanel
10. Inline lab dưới selected model
```

### P1 — Prediction system

```text
11. Build payload from metadata
12. Derived fields
13. aiQuickPredict integration
14. Scalar renderer
15. Vector renderer
16. Class renderer
17. Loading state
18. Error state
19. Disable Run by availability
```

### P2 — Management

```text
20. ModelManagerDrawer
21. Reuse UploadDialog
22. Version list
23. Smoke test state
24. Test version
25. Deploy
26. Active/load
27. Deactivate
28. Delete
29. Active version warning
```

### P3 — UX polish

```text
30. Inline row positioning
31. Responsive layout
32. Motion animations
33. Friendly labels
34. Icons
35. Accent colors
36. Empty states
37. Skeletons
```

### P4 — Tests / cleanup

```text
38. Frontend unit tests
39. Component tests
40. Registry tests
41. DTE integration
42. Upload/deploy integration
43. Availability tests
44. Remove old ModelDetailPanel render
45. Remove obsolete RangePredictionLab
46. Production build
47. Final QA
```

---

## 92. Nguyên tắc bắt buộc cho agent

1. Không viết lại toàn bộ AI Center.
2. Không phá KPI, grouping và catalog hiện tại.
3. Không tạo 9 lab riêng.
4. Registry phải là nguồn metadata chính.
5. Admin test dùng `aiQuickPredict(typeKey, payload)`.
6. Public/mobile API hiện có vẫn giữ.
7. Upload không tự active.
8. Chỉ model active + loaded + predictable mới cho Run.
9. Không hiển thị raw field names cho user.
10. Không render raw JSON làm kết quả chính.
11. Không duplicate logic ModelDetailPanel.
12. Không xóa RangePredictionLab trước khi migration thành công.
13. DTE contract phải được sửa trước khi coi feature hoàn thành.
14. Toàn bộ 9 model phải render được bằng một architecture thống nhất.

---

## 93. Kết quả mong đợi sau cùng

AI Center trở thành một **Model Hub + Interactive Model Lab** thống nhất:

```text
Model Catalog
    ↓ click
Universal Black Lab
    ↓
Dynamic Inputs
    ↓
Active Model Check
    ↓
Prediction
    ↓
Formatted Result
    ↓
Manage Model
    ↓
Upload / Test / Deploy / Versions
```

Mục tiêu dài hạn là khi thêm model thứ 10 hoặc thứ 20, developer chủ yếu chỉ cần:

```text
1. đăng ký metadata trong registry
2. định nghĩa input schema
3. định nghĩa output kind/unit
4. upload/deploy model
```

mà không phải thiết kế thêm một màn test mới.
