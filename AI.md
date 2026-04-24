# AI.md — Kiến trúc đầy đủ AI BMS Assistant + Fine-tuning

## Summary
- Viết mới `AI.md` bằng tiếng Việt theo kiến trúc đang chạy thật: `Flutter App -> Flask Gateway (5000) -> FastAPI AI Server (8001 nội bộ)` với `X-Internal-Token`.
- Tài liệu sẽ chốt 3 vòng MLOps (Inference, Ingestion, Continuous Learning) kèm blueprint code-level để triển khai ngay ở prompt tiếp theo.
- Giữ tương thích API cũ (`/api/soc/predict`, `/api/soc/status`) và mở rộng API chuẩn cho bài toán `energy_per_km_wh` + `SoH fine-tune`.

## Implementation Changes
- **Public APIs/Interfaces (chốt trong AI.md):**
- `POST /api/ai/energy/predict` (Flask public) -> proxy `POST /v1/energy/predict` (FastAPI nội bộ).
- `POST /api/soc/predict` giữ backward compatibility, adapter về output cũ cho app.
- `POST /api/ai/trips/ingest` để ghi trip thực tế sau chuyến đi.
- `GET /api/admin/ai/fine-tune/status` và `POST /api/admin/ai/fine-tune/run` (manual override, vẫn có auto scheduler).
- Contract output inference chuẩn hóa: `predicted_energy_per_km_wh`, `predicted_trip_energy_wh`, `predicted_soc_drop_pct`, `predicted_soc_after_trip_pct`, `estimated_remaining_range_km`, `model_version`.
- **Giai đoạn 1 — Inference pipeline:**
- Model mặc định: `ExtraTreesRegressor`; `XGBoost` là model dự phòng/A-B.
- Feature bắt buộc: `distance_km`, `duration_min`, `elevation_gain_m`, `hard_accel_ratio`, `temperature_c`.
- Công thức pin/range trong tài liệu:
- `trip_energy_wh = predicted_energy_per_km_wh * distance_km` (clamp >= 0).
- `usable_capacity_wh = 2400 * (soh_pct/100)`.
- `predicted_soc_drop_pct = (trip_energy_wh / usable_capacity_wh) * 100` (clamp 0..100).
- `estimated_remaining_range_km = max(0, (current_energy_wh - trip_energy_wh) / predicted_energy_per_km_wh)`.
- **Giai đoạn 2 — Data ingestion + cleaning (PostgreSQL + sync Firestore):**
- PostgreSQL là nguồn train chính; Firestore vẫn đồng bộ để phục vụ app/dashboard realtime.
- Bảng chính trong AI.md: `trip_ingest_raw`, `trip_ingest_clean`, `ml_training_state`, `ml_model_registry`, `ml_fine_tune_runs`.
- Rule cleaning bắt buộc:
- `max_speed_kmh = min(max_speed_kmh, 71)`.
- `charge_type`: nếu `DC` -> chuyển `AC`.
- `avg_charge_power_kw = min(avg_charge_power_kw, 0.5)`.
- Loại bản ghi nhiễu: `distance_km < 0.1` hoặc `soc_drop_pct == 0`.
- Ràng buộc vật lý: năng lượng không âm, SoH không nhảy phi lý, AC không vượt thiết kế.
- **Giai đoạn 3 — Continuous learning + fine_tune.py (LSTM):**
- Trigger tự động: scheduler mỗi giờ, chạy khi có `>=500` trip thực tế mới chưa dùng train.
- Anti-catastrophic forgetting cố định: lấy `500 real + 300 synthetic random` (Replay Buffer Strategy).
- LSTM defaults chốt trong tài liệu: `lookback_window=30`, `optimizer=Adam(lr=1e-4)`, `loss=Huber`, `batch_size=64`, `early_stopping_patience=6`.
- Nhãn SoH dùng từ `BMS/Capacity test` cho `soh_next_cycle_pct`.
- Artifact versioning: lưu `.h5` theo version + metadata; chỉ activate khi pass eval; có rollback.

## Test Plan
- Giữ cố định 41 chuyến đi thực tế làm `locked test set` (không dùng fine-tune).
- Inference tests: schema validation, clamp vật lý, công thức `% pin` và `range_km` đúng với capacity 2.4 kWh.
- Ingestion tests: verify rule clipping/conversion/filter nhiễu; đảm bảo dual-write PG + Firestore thành công.
- Fine-tune tests: chỉ chạy khi đủ ngưỡng 500; kiểm tra tỷ lệ replay 500:300; xác nhận learning rate đúng `1e-4`.
- Regression tests: model mới không degrade vượt ngưỡng trên locked test set trước khi activate.

## Assumptions
- Tài liệu `AI.md` sẽ dùng chuẩn tên biến có hậu tố đơn vị (`_km`, `_min`, `_wh`, `_kw`, `_pct`, `_c`, `_kmh`).
- Hardware constants mặc định: pin LFP `2.4 kWh`, speed limit `70 km/h`, sạc AC max `0.5 kW`, có regen braking.
- Hệ thống tiếp tục mô hình gateway hiện tại (Flask public, FastAPI nội bộ) thay vì gom toàn bộ về một service.
- Dữ liệu telemetry theo giây (như `trips.csv`) sẽ được tổng hợp lên trip-level trước khi train/infer.
