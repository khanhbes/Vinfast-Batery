# Báo cáo Phiên Làm Việc Web — Pinova Drive Admin & Backend

> Tài liệu tổng hợp toàn bộ mã nguồn đã đọc, các thay đổi đã thực hiện, kết quả kiểm thử và trạng thái triển khai (deploy) cho phần Web trong phiên làm việc kết thúc ngày **17/11/2026**.

---

## 1. Các thành phần & tệp mã nguồn đã đọc khảo sát

### 1.1. Frontend Admin Dashboard (`web/dashboard/`)
- **Cấu hình & giao diện nền:** `package.json`, `index.html`, `src/index.css`, `public/staticwebapp.config.json`, `.env`, `.env.local`.
- **Quản lý dữ liệu tập trung:** `src/data/AdminDataContext.tsx` (cơ chế tải `INITIAL_DATASETS = ['core']`, cache `sessionStorage`, gộp snapshot từng phần).
- **Thành phần dùng chung:**
  - `src/components/common/StatusBadge.tsx` (`StatusBadge`, `PlanBadge`).
  - `src/components/common/DataTableSurface.tsx` (bảng dữ liệu, skeleton, trạng thái rỗng/lỗi, hover hàng và thao tác).
  - `src/components/catalog/ShowroomEditor.tsx` (`ShowroomEditor`, `SpinPreview`, quản lý màu và chuỗi góc ảnh 2.5D/360°).
- **Các trang quản trị:** `src/pages/Dashboard.tsx`, `src/pages/PremiumPlans.tsx`, `src/pages/UserManagement.tsx`, `src/pages/VehicleCatalog.tsx`, `src/pages/SupportInbox.tsx`, `src/pages/DeveloperHub.tsx`, `src/pages/AssistantKnowledge.tsx`.

### 1.2. Backend Flask API & Modules (`web/`)
- **API trung tâm:** `server.py` (Flask v4.1: `_account_record`, `admin_accounts`, `admin_data_snapshot`, `_ADMIN_SNAPSHOT_COLLECTIONS`, `_ADMIN_SNAPSHOT_GROUPS`, `_register_billing`, `create_catalog_blueprint`).
- **Gói dịch vụ & thanh toán:** `billing/features.py`, `billing/entitlements.py`, `billing/routes.py`, `billing/promos.py`.
- **Danh mục xe & xử lý ảnh:** `vehicle_catalog.py`, `vehicle_media.py` (`AzureBlobMediaStore`, `FirebaseMediaStore`, tách nền tự động, tạo biến thể WebP).
- **Trợ lý Pinova:** `assistant/schemas.py`, `assistant/guardrails.py`, `models/pinova_config/state.json`.
- **IoT & AI (khảo sát bài toán chẩn đoán bất thường sạc):** `shelly/models.py`, `shelly/charge_model.py`, `ai_server/main.py`, `docs/specs/TELEMETRY_SCHEMA.md`.

### 1.3. Đối chiếu đồng bộ sang Mobile App (`app/lib/`) & Script Deploy (`deploy/azure/`)
- **Mobile App:** `data/models/entitlement.dart`, `core/providers/entitlement_provider.dart`, `core/widgets/vehicle_photo.dart`, `data/models/vehicle_showroom.dart`, `data/models/vehicle_model.dart`, `data/models/vinfast_model_spec.dart`, `core/services/auth_service.dart`, `features/settings/vehicle_spec_detail_screen.dart`.
- **Triển khai Azure:** `deploy/azure/staging.json`, `deploy/azure/common.ps1`, `deploy/azure/07-build-admin.ps1`, `deploy/azure/11-publish-admin-artifact.ps1`, `deploy/azure/14-update-api-image.ps1`.

---

## 2. Những công việc đã hoàn thành

### 2.1. Đồng bộ gói dịch vụ (chỉ còn Free / Pro / Ultra) & tối ưu Firestore
- **Loại bỏ gói không tồn tại:** Xóa toàn bộ tham chiếu `Plus`, `Starter`, `Pro Concierge`, `Fleet` / `Doanh nghiệp` khỏi:
  - `web/dashboard/src/components/common/StatusBadge.tsx` (`PlanBadge`)
  - `web/dashboard/src/pages/UserManagement.tsx`
  - `web/dashboard/src/pages/SupportInbox.tsx`
  - `web/dashboard/src/pages/DeveloperHub.tsx`
  - `web/dashboard/src/types/pinova.ts`
  - `web/assistant/guardrails.py`, `web/assistant/schemas.py`, `web/models/pinova_config/state.json`
- **Đồng bộ gói thật lên hồ sơ người dùng (không tăng lượt đọc Firestore):**
  - `web/billing/entitlements.py`: bổ sung `_mirror_profile()` tự động ghi `planTier`, `planStatus`, `planExpiresAt` vào `users/{uid}` mỗi khi gói thay đổi (cấp, mua, dùng thử, thu hồi); thêm bộ nhớ đệm `_counts_cache` (`COUNTS_CACHE_SECONDS = 300`) cho `tier_counts()` để giảm quét `collection_group("entitlements")`.
  - `web/server.py`: thêm `_account_plan()` đọc trường gói từ hồ sơ đã tải trong `admin_accounts` (tự quy về `free` nếu hết hạn/thu hồi) và truyền `accounts_total` vào blueprint billing.
  - `web/billing/routes.py`: endpoint `/api/admin/billing/stats` tính thêm số lượng người dùng `free` thực tế (`tổng tài khoản - pro - ultra - trial`).
  - `web/dashboard/src/pages/PremiumPlans.tsx`: hiển thị `—` khi chưa tải được số người dùng từng gói thay vì mặc định `0`.

### 2.2. Xóa bỏ số liệu bịa trên Dashboard & Quản lý tài khoản
- **`web/dashboard/src/pages/Dashboard.tsx`:**
  - Gỡ bỏ toàn bộ dữ liệu giả định cứng: tên tài khoản quản trị mặc định, thẻ MRR `249.000đ` / `+25%`, nhãn `100% xác thực`, `100% đúng SLA`, `SoH 99.0%`, xe mặc định `VinFast Feliz 2025`, số đếm Shelly `1 / 1`.
  - Thay thẻ MRR bằng **"Gói trả phí đang dùng"** lấy số liệu từ `adminBillingStats()`.
  - Biểu đồ xu hướng chỉ vẽ số liệu thật theo ngày/tuần từ bản ghi đã tải (`Tài khoản mới` và `Phiên sạc`); gỡ tab `Doanh thu` giả định.
  - Hiển thị `—` cho các bộ dữ liệu chưa được tải (`shelly`, `support`, `accounts`) nhằm giữ nguyên cơ chế tải nhóm `core` tiết kiệm Firestore reads.
- **`web/dashboard/src/pages/UserManagement.tsx`:**
  - Bỏ thông tin thiết bị bịa (`1 thiết bị` / `0 thiết bị`), hiển thị `—` khi `vehicleCount` chưa có và cập nhật đúng số xe từ `/api/admin/accounts/<uid>`.

### 2.3. Danh mục xe: tải ảnh, màu sắc & đồng bộ về App
- Xác nhận luồng tải ảnh theo màu/góc qua `ShowroomEditor.tsx` → `/api/admin/vehicle-catalog/<catalogId>/media` (`AzureBlobMediaStore` + tự tách nền ở `vehicle_media.py`) và đẩy vào `Vehicles.catalogSnapshot` khi Admin bấm xuất bản.
- **Backend (`web/vehicle_catalog.py`):** bổ sung `colorId` vào `PERSONAL_VEHICLE_FIELDS` và kiểm tra trong `patch_personal_vehicle()` chỉ chấp nhận màu nằm trong `catalogSnapshot.media.showroom.colors` đã xuất bản.
- **App (`app/lib/`):** hỗ trợ chọn và lưu `colorId` ở `vehicle_spec_detail_screen.dart`; `VehicleImages.resolve()` ưu tiên ảnh đúng màu đã chọn (mặc định là màu mặc định của danh mục), ảnh `feliz_mint.webp` đóng gói sẵn chỉ làm fallback khi catalog chưa có ảnh.

### 2.4. Font chữ, hiệu ứng Hover & Deploy Web
- **Giữ hệ font dễ đọc trên server:** Cấu hình đồng bộ `Inter` (nội dung & `tabular-nums`), `Manrope` & `Space Grotesk` (tiêu đề), `JetBrains Mono` (mã/ID) trong `web/dashboard/index.html` và `web/dashboard/src/index.css`.
- **Hiệu ứng tương tác & Hover:**
  - `web/dashboard/src/index.css`: thêm `.hover-lift` (nâng thẻ `-2px`, làm rõ viền, đổ bóng nhẹ), `.hover-pill` (nâng nhẹ `-1px`), transition cho nút/liên kết (`120ms`), phản hồi nhấn `scale(0.98)` và `:focus-visible`, toàn bộ tuân thủ `@media (prefers-reduced-motion: reduce)`.
  - Áp dụng `.hover-pill` và `.hover-lift` cho dải **"Cần xử lý ngay"** và 4 thẻ KPI trên `Dashboard.tsx`, thẻ gói trên `PremiumPlans.tsx` và thẻ xe trên `VehicleCatalog.tsx`.
- **Script Deploy (`deploy/azure/07-build-admin.ps1`):** bổ sung tham số `-SkipInstall` để tái sử dụng `node_modules` đã cài sạch.

### 2.5. Phân tích chuyên môn (không sửa code)
- Đã khảo sát và đánh giá tính khả thi của bài toán **"Chẩn đoán bất thường không xâm lấn qua đường đặc tính công suất xoay chiều phía lưới điện"** dựa trên Shelly Plug S Gen3, `charge_model.py`, `learning.py`, `SmartChargeSafetyPolicy` và `web/ai_server/`.

### 2.6. Đồng bộ Mẹo nhỏ từ app, sửa lỗi 404/400 & hoàn thiện Hover (17/11/2026)
- **Nguyên nhân lỗi `"The request is invalid. Check the input and try again."` tại `/assistant/tips`:**
  - Container backend cloud `vinfast-api` đang chạy revision ngày `2026-11-12` (trước QA 163), nên `GET /api/admin/tips` trả HTTP `404`, còn `httpClient.ts` trước đó map `404` sang thông báo chung `'The request is invalid. Check the input and try again.'`.
  - Đồng thời sửa lỗi hàm `audit(...)` thiếu tham số trên `PUT`/`DELETE /api/admin/tips/<tip_id>` (`web/assistant/routes.py`) và sửa khóa dataset `'charges'`/`'trips'` thành `'chargeLogs'`/`'tripLogs'` trong `UserManagement.tsx`.
- **Đồng bộ 35 mẹo chuẩn từ App (`app/assets/tips/tips_vi.json` -> `web/dashboard/src/data/appTips.json` & `AssistantTips.tsx`):**
  - Map `status === 404` trong `httpClient.ts` sang `'Không tìm thấy endpoint hoặc dữ liệu trên máy chủ.'` (vẫn giữ nguyên quy tắc không rò rỉ payload thô theo `portal-safety.test.ts`).
  - Khi `/api/admin/tips` trả `404` từ bản `vinfast-api` cũ, `AssistantTips.tsx` fallback sang 35 mẹo chuẩn đồng bộ từ app kèm banner thông báo rõ ràng trạng thái chỉ xem và cảnh báo khi bấm Lưu/Ẩn.
- **Hoàn thiện Hover toàn trang:** Bổ sung `.hover-card`, `.hover-pill`, `.hover-row`, `.hover-arrow`, `.hover-lift` trên Sidebar, Topbar, Dashboard, SupportInbox, AiCenter, PremiumPlans, VehicleCatalog, AssistantTips, DataTableSurface và FilterBar.

### 2.7. Kiểm tra & Tối ưu UI/UX & Animation đồng loạt (17/11/2026)
- **Dark Mode đồng nhất 100% & sửa tương phản:**
  - `sonner.tsx`: thiết lập `theme="dark"` + `richColors` và token bề mặt tối (`--bg-elevated`, `--border-strong`), loại bỏ popup thông báo nền trắng gắt trên nền tối.
  - `App.tsx`: thay màn hình chờ `bg-slate-50` sáng chói bằng nền tối Pinova (`--bg-canvas`) kèm chữ tiếng Việt.
  - `Topbar.tsx`: bỏ nút chuyển Light/Dark chưa lưu & gây loang màu giữa các trang; kích hoạt phím tắt toàn cục `⌘K` / `Ctrl+K` để mở/đóng Command Palette.
  - `PremiumPlans.tsx`: đổi màu chữ nút chính `Cấp / Gia hạn gói` và `Lưu & Kích hoạt mã` từ `text-slate-950` sang `text-white` trên nền indigo `--accent-primary`.
  - `ModelTypeCard.tsx`, `ModelCatalog.tsx`, `UploadDialog.tsx`: thay toàn bộ card nền pastel/trắng (`bg-emerald-50`, `bg-white`, `bg-slate-50`) sang token tối đồng nhất.
- **Chuẩn hóa nút bấm, Việt hóa & An toàn dữ liệu:**
  - `button.tsx` & `index.css`: đưa nút desktop về `32px–36px` (`h-8` / `h-9`), giữ chuẩn chạm `44px–48px` trên mobile (`<768px`) và giữ nguyên nút `min-h-12 min-w-12` bật/ẩn mã Shelly.
  - `Login.tsx`: Việt hóa 100% giao diện & thông báo lỗi Firebase Auth; tối ưu nền phát sáng gradient tĩnh thân thiện GPU thay cho pulse blur liên tục.
  - `ShellyGateway.tsx`: gỡ fallback tên/biển số cứng (`'Phan Nam Khánh'` / `'VinFast Feliz 2025'` → `'Chưa gán người dùng'` / `'Chưa gắn xe'`), gỡ nút `"Chế độ xem | 1"` không có chức năng, thêm đóng modal/drawer bằng phím `Esc` và hiệu ứng `.animate-modal-enter` / `.animate-drawer-enter`.
- **Animation & Micro-interactions mượt chuẩn 60fps:**
  - `Sidebar.tsx`: gỡ xung đột `transition-all` khỏi `<motion.aside>` để Motion thu/mở mượt; thêm `layoutId="sidebar-active-surface"` trượt vạch active mượt (có tôn trọng `useReducedMotion`).
  - `CommandPalette.tsx`: bổ sung chọn nhanh bằng phím mũi tên `↑`/`↓` + `Enter`, đồng bộ hover và lọc `chargeLogs` theo `DevelopModeContext`.
  - `VehicleCatalog.tsx`: bỏ `layoutId` mồ côi xuyên portal trên ảnh hero drawer, thay bằng transition scale/opacity gọn mượt.
  - `PageLoadBoundary.tsx`, `Dashboard.tsx`, `AssistantTips.tsx`, `UserManagement.tsx`, `ShellyGateway.tsx` & `index.css`: thêm `.skeleton-shimmer` đồng bộ khi tải trang/bảng/drawer và tối ưu thanh điều hướng ngang trên mobile (`<768px`).

---

## 3. Kết quả kiểm thử & trạng thái triển khai

| Hạng mục | Kết quả | Ghi chú |
| :--- | :--- | :--- |
| **Backend Pytest** (`test_qa163_tips_and_bot_settings.py`, `test_assistant`, `test_pinova_suite`, `test_qa135_billing`, `test_qa145_payments`, `test_vehicle_catalog`, `test_vehicle_media`...) | **Pass** | Đã chạy thêm bộ QA 163 CRUD + audit log cho `/api/admin/tips` |
| **Frontend Security Audit (`npm audit`)** | **0 high / 0 critical** | Không có lỗ hổng mức cao |
| **Frontend TypeScript (`tsc --noEmit`)** | **0 lỗi** | Sạch kiểu dữ liệu |
| **Frontend Tests (`portal-safety`, `model-lab`)** | **32 / 32 passed** | Kiểm tra an toàn portal đạt 100% |
| **Frontend Build (`vite build`)** | **Thành công** | Xuất `dist/assets/index-ZTPwxc5s.js`, `index-CPvj-cXD.css` |
| **Flutter Static Analysis (`dart analyze`)** | **No issues found** | Kiểm tra trên các file model, ảnh và chi tiết xe |
| **Azure Static Web Apps (Web Admin)** | **Đã Deploy Live** | URL: `https://victorious-tree-076e47d00.6.azurestaticapps.net/` (đã xác minh live HTML phục vụ `index-ZTPwxc5s.js` và `index-CPvj-cXD.css`) |
| **Azure Container Apps (Backend `vinfast-api`)** | **Chưa deploy lại** | Đang chạy revision `2026-11-12`; cần mở Docker Desktop và chạy rollout `14-update-api-image.ps1` để bật lưu/ẩn mẹo Firestore, `planTier` mirror & `colorId` trên cloud |

---

## 4. Lưu ý vận hành còn lại
1. **Tài khoản cũ trong Firestore:** Tài khoản đã có gói trước thời điểm cập nhật sẽ hiển thị `free` trong danh sách tài khoản cho đến khi phát sinh giao dịch/cấp/thu hồi gói mới hoặc chạy script backfill `planTier` sang `users/{uid}`.
2. **Triển khai Backend:** Để tính năng tính gói `free` trong `/api/admin/billing/stats`, trường `tier` trong danh sách tài khoản, và lưu `colorId` xe hoạt động trên server cloud, cần build & cập nhật image container `vinfast-api` lên Azure Container Apps.
