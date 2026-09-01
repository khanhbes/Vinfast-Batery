# Quản lý dữ liệu fine-tune AI cá nhân

## Xem dữ liệu

Trong app, chạm 7 lần vào phiên bản để mở **Developer Mode**, sau đó vào:

`Cài đặt → Developer Mode → Dữ liệu fine-tune AI`

Màn hình này đọc dữ liệu theo xe đang chọn và cho xem/copy JSON từng mẫu. Dữ liệu
gốc nằm trong Firestore:

- Mẫu học: `users/{uid}/chargingTrainingSamples/{sessionId}`
- Profile đang dùng: `AiVehicleProfiles/{uid}_{vehicleId}`
- Job huấn luyện: `personalChargingTrainingJobs/{uid}_{vehicleId}`
- Lịch sử phiên gốc: `ChargeLogs/{sessionId}`

## Sửa một mẫu sai

Chỉ tài khoản có Firebase custom claim `admin: true` (hoặc admin email được
server cho phép) mới có nút sửa trong Developer Mode. Chạm 7 lần chỉ mở giao
diện chẩn đoán, **không tự cấp quyền ghi**.

Để cấp quyền cho tài khoản developer, một admin hiện có gọi
`POST /api/auth/set-admin` với `{ "email": "developer@example.com" }`, hoặc
dùng Firebase Admin SDK để đặt custom claim `{ "admin": true }`. Sau đó đăng
xuất/đăng nhập lại để token được làm mới.

Trong app, developer mở JSON của mẫu rồi chạm biểu tượng chỉnh sửa để:

- Loại mẫu khỏi train (`trainingExcluded`).
- Ghi chú lý do (`developerNote`).
- Override thời lượng thực hoặc ETA dự đoán dùng cho train kế tiếp.

Override không ghi đè số đo gốc; chúng được lưu cạnh mẫu, có audit và chỉ được
worker áp dụng khi fine-tune. Nếu cần thao tác bằng Firebase Admin Console:

1. Mở đúng document mẫu theo `uid`, `vehicleId` và `sessionId`.
2. Không sửa `ownerUid`, `vehicleId`, `sessionId` hoặc số đo gốc.
3. Đặt `trainingExcluded = true` để loại mẫu khỏi lần train tiếp theo.
4. Thêm `developerNote` mô tả lý do, ví dụ `SOC cuối nhập nhầm`.
5. Nếu cần dùng lại, đặt `trainingExcluded = false` sau khi đã xác minh nguồn dữ liệu.

Worker loại mọi document có `trainingExcluded = true`. Cách này giữ được provenance
và audit, an toàn hơn việc ghi đè nhãn đo gốc.

## Khi nào fine-tune chạy và user nhận thông báo

- Phiên phải đủ điều kiện dữ liệu; batch train bắt đầu từ tối thiểu 5 mẫu hợp lệ.
- Worker: `web/smart_charge_worker.py`.
- Logic chọn mẫu/calibration: `web/shelly/personalization.py`.
- Guardrail promote/rollback: `web/shelly/personal_model_registry.py`.
- Nếu model mới tốt hơn validation, nó được promote và user nhận thông báo
  **AI cá nhân đã được cập nhật**.
- Nếu không tốt hơn, model hiện tại được giữ nguyên và user nhận thông báo kết quả
  kiểm tra. Job chưa đủ 5 mẫu không được gọi là một lần fine-tune hoàn tất.

Thông báo được lưu idempotent trong `UserNotifications` và xuất hiện ở Trung tâm
thông báo của đúng tài khoản.
