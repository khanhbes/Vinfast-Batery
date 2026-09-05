# AI lifecycle: range prediction and charging time

Hai task được vận hành theo cùng một vòng đời:

```text
Telemetry đã xác minh → Dataset version → Split theo xe + thời gian
→ Train → MAE/RMSE/bias → So sánh baseline → Canary 10% → Monitor drift
→ Promote hoặc rollback
```

## Quy tắc triển khai

- Dataset nhận fingerprint SHA-256 và `datasetVersion`; metadata ghi số xe, số bản ghi và khoảng thời gian.
- Mỗi xe được sắp theo thời gian. Bản ghi mới nhất chỉ xuất hiện trong validation/test, không đi vào train.
- Candidate chỉ được canary 10% nếu có ít nhất 20 mẫu test, MAE tốt hơn baseline ≥2%, RMSE không xấu hơn quá 3% và bias không tăng.
- Drift dùng mean-shift trên feature hoặc prediction error; ít hơn 20 mẫu ở một phía luôn là `insufficient_data`, không được coi là ổn định.
- Mỗi prediction phải lưu `modelVersion`, `confidence` (0–1), `reason` và context tối thiểu qua prediction audit.
- Personal AI chỉ eligible khi xe có ≥30 mẫu đã xác minh trải trên ≥14 ngày; thiếu dữ liệu luôn giữ base model.

## API quản trị

- `POST /api/admin/ai/lifecycle/{range_prediction|charging_time}/dataset` với `{ "rows": [...] }`
- `POST /api/admin/ai/lifecycle/{task}/evaluate` với `rows`, `candidateVersion`, `candidateMetrics`, `baselineMetrics`
- `POST /api/admin/ai/lifecycle/{task}/drift` với `{ "baseline": [...], "recent": [...] }`
- `GET /api/admin/ai/lifecycle/{task}`

## API cho prediction và Personal AI

- `POST /api/ai/lifecycle/{task}/prediction-audit`
- `POST /api/ai/lifecycle/{task}/personal-eligibility`

Các endpoint đều giữ model inactive khi quality gate không đạt. Canary/rollback runtime
phải được gọi qua model deployment API hiện có sau khi evaluation trả `approved: true`.

## Personal AI và dữ liệu đã xác minh

Personal AI tách theo tài khoản và xe. Chỉ bắt đầu học khi có tối thiểu 30 mẫu đã
xác minh, trải trên ít nhất 14 ngày. Một phiên sạc chỉ được dùng làm nhãn khi có
telemetry đủ coverage, năng lượng hợp lệ và SOC cuối được người dùng hoặc nguồn tin
cậy xác nhận. Mẫu sai có thể bị đánh dấu loại trừ thay vì ghi đè số đo gốc; provenance
và audit phải được giữ lại. Người dùng luôn thấy model version, confidence và lý do
dự đoán; khi chưa đạt ngưỡng, hệ thống tiếp tục dùng base model.
