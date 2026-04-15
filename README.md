# VinFast Battery

Tài liệu này mô tả **cơ chế hoạt động giữa App (User)** và **Web Admin Portal** trong hệ thống VinFast Battery.

## Cấu trúc thư mục

- `app/`: Flutter mobile app (Android, `lib/`, `pubspec.yaml`, assets, test).
- `web/`: Unified API Flask + Admin Portal React (`server.py`, `dashboard/`, `start_all.ps1`).

## 1) Kiến trúc tổng thể

Hệ thống gồm 3 phần chính:

1. **App Flutter (User)**
   - Người dùng đăng ký/đăng nhập bằng Firebase Auth.
   - Ghi dữ liệu xe, sạc, chuyến đi, bảo dưỡng.
   - Dữ liệu được gắn `ownerUid` để tách theo từng tài khoản.

2. **Web Admin Portal (React + Tailwind)**
   - Admin đăng nhập bằng Firebase Auth.
   - Quản trị dữ liệu toàn hệ thống (CRUD, import/export, AI lab).
   - Gọi backend Unified API qua token Firebase.

3. **Unified API (Flask)**
   - Verify Firebase ID token bằng Firebase Admin SDK.
   - RBAC: `user` / `admin`.
   - Cung cấp API user, admin, AI, import/export, migration legacy.

Nguồn dữ liệu chung: **Firestore**.

## 2) Cơ chế xác thực & phân quyền

### App (User)
- `AuthGate` quyết định:
  - Chưa đăng nhập -> `LoginScreen`.
  - Đã đăng nhập -> `AppNavigation`.
- Đăng ký/đăng nhập dùng email-password Firebase.

### Web (Admin)
- Màn login web hỗ trợ:
  - Đăng nhập.
  - Đăng ký tài khoản mới.
- Sau login, web gọi `GET /api/auth/me` để lấy role.
- Nếu role khác `admin`, web hiển thị “Không có quyền truy cập”.

### Quy tắc admin trong backend
- Một user được coi là admin nếu:
  - Có custom claim `admin=true`, **hoặc**
  - Email nằm trong `ADMIN_EMAILS`, **hoặc**
  - `ADMIN_EMAILS=*` (chế độ bootstrap local).

## 3) Luồng dữ liệu App <-> Web

### Luồng App -> Firestore
1. User đăng nhập app.
2. App tạo/cập nhật dữ liệu:
   - `Vehicles`
   - `ChargeLogs`
   - `TripLogs`
   - `MaintenanceTasks`
3. Mỗi bản ghi được chuẩn hóa tối thiểu:
   - `ownerUid`
   - `createdAt`, `updatedAt`
   - `isDeleted` (soft delete support)

### Luồng Web Admin -> Unified API -> Firestore
1. Admin đăng nhập web.
2. Web gửi token Firebase tới API.
3. API kiểm tra quyền admin.
4. Admin có thể:
   - Xem toàn bộ dữ liệu, lọc theo `ownerUid`, `vehicleId`.
   - Thêm/sửa/xóa mềm/khôi phục.
   - Import/Export dữ liệu JSON/CSV.
   - Train/Test AI.

### Đồng bộ dữ liệu
- Vì App và Web cùng dùng Firestore làm nguồn dữ liệu, thay đổi sẽ đồng bộ gần như realtime.
- Dữ liệu web sửa sẽ phản ánh lại app (theo `ownerUid` tương ứng).

## 4) Cơ chế AI

Unified API cung cấp:
- `POST /api/ai/predict-degradation`
- `POST /api/ai/analyze-patterns`
- `POST /api/ai/train-vehicle-profile`
- `GET /api/ai/profile-status/<vehicleId>`

Admin AI endpoints:
- `POST /api/admin/ai/normalize-dataset`
- `POST /api/admin/ai/train`
- `POST /api/admin/ai/test`

Mục tiêu:
- Chuẩn hóa dataset trước train.
- Train profile theo từng xe.
- Test mô hình trên dữ liệu mới.

## 5) Cơ chế Import/Export dữ liệu

- Export:
  - `GET /api/admin/export?entity=<...>&format=json|csv`
- Import:
  - `POST /api/admin/import?entity=<...>&mode=upsert`

Dữ liệu import được chuẩn hóa và ghi audit log để truy vết.

## 6) Dữ liệu legacy

- Bản ghi cũ không có `ownerUid` được đánh dấu legacy bằng:
  - `POST /api/admin/migrate-legacy`
- Legacy hiển thị cho admin, không dùng như dữ liệu user chuẩn.

## 7) Chạy local

Chạy toàn bộ dịch vụ:

```powershell
.\web\start_all.ps1
```

Script sẽ mở:
- API: `http://localhost:5000`
- Admin Portal: `http://localhost:3000`

Lưu ý:
- Cần file Firebase Admin key (`*firebase-adminsdk*.json`) trong `web/` hoặc `web/secrets/`.
- Không commit file key vào git.

## 8) Endpoint nhanh

- Health: `GET /api/health`
- Auth me: `GET /api/auth/me`
- Set admin: `POST /api/auth/set-admin`
- User data:
  - `GET /api/user/vehicles`
  - `GET /api/user/charge-logs`
  - `GET /api/user/trip-logs`
  - `GET /api/user/maintenance`
- Admin data: `CRUD /api/admin/<entity>`
