# Kế hoạch đồng bộ app/web và dọn legacy theo server live

## Tóm tắt
- Đã kiểm tra ngày **27/04/2026**: `http://api.evbattery.live/api/health`, `http://api.evbattery.live/api/app/config`, và `http://api.evbattery.live/api/ai/charging-model-status` đều trả `200`. App production phải dùng base URL **`http://api.evbattery.live`**, không dùng `.../ai` làm API base.
- Làm sạch app theo hướng “server-first”: bỏ toàn bộ header/bell cũ lặp lại, bỏ flow AI/admin/dev-local trong app user, bỏ endpoint/local URL cũ, và chỉ giữ các flow đang bám server live.
- Giữ quyết định đã chốt: model update cho app vẫn theo **app-open/resume sync**, catalog xe **VinFast-first nhưng mở sẵn để thêm hãng khác**, và sync dữ liệu theo **Shared Firestore + backend sync routes**.

## Thay đổi chính

### 1. App shell, header cố định, và pull-to-refresh toàn app
- Dùng **một AppBar dùng chung ở `AppNavigation` cho cả 5 tab root**: chỉ giữ `VinFast Battery` + chuông thông báo ở hàng trên cùng.
- Xóa toàn bộ header cũ bên trong các tab root:
  - Home: bỏ hàng profile/title/bell cũ phía dưới AppBar.
  - AI, Trip, Service, Settings: bỏ header tự dựng trong từng screen.
  - Service hiện đang dùng `SharedStickyHeader` riêng thì chuyển về dùng AppBar chung luôn để thống nhất.
- Home chỉ còn phần banner/vehicle card là nội dung đầu tiên; dòng `Connected to ...` chuyển xuống vehicle card hoặc subtitle nội dung, không nằm trong header lặp.
- Thay cơ chế điều hướng tab bằng **Riverpod tab-state provider**, bỏ cách dùng `GlobalKey` sai ở `AppNavigation` và bỏ `dispose()` bất thường trong `initState`.
- Tất cả tab root bọc bằng `RefreshIndicator` và gọi chung một `AppRefreshCoordinator.refreshAll(...)`.
- `refreshAll` sẽ:
  - refetch vehicle/profile/log/maintenance/trip providers,
  - gọi `NotificationCenterService().syncModels(force: true)`,
  - refetch `/api/user/ai/models` và `/api/user/sync/overview`,
  - cập nhật badge chuông và dữ liệu UI đang mở.
- `pull-to-refresh` chỉ **reload dữ liệu app**, không tự động gọi `sync/full`; `Manual Sync` trong Settings vẫn là hành động push dữ liệu có chủ đích.

### 2. Chuông thông báo và Notification Center hoàn chỉnh
- Tất cả bell trên app mở cùng một `NotificationCenterScreen`; xóa bottom sheet mock ở Home.
- Sửa `NotificationRepository.watchUnreadCount()` từ aggregate one-shot sang **query snapshots realtime** để badge cập nhật thật.
- `watchNotifications()` phải luôn phát ra dữ liệu an toàn:
  - chưa đăng nhập: trả `[]`,
  - không có thông báo: trả `[]`,
  - lỗi Firestore/query: fallback `[]` và UI hiển thị empty/error nhẹ, không treo loading vô hạn.
- Empty state đổi đúng text thành **`Không có thông báo`**.
- `NotificationCenterService` nối với `NotificationService` hiện có để khi model mới được tải/cập nhật sẽ:
  - ghi `UserNotifications`,
  - tăng unread badge,
  - bắn local notification Android.
- Sửa deep-link tab index trong Notification Center:
  - `/ai/...` phải vào tab AI index `1`, không phải `2`.
  - `/maintenance` vào tab Service index `3`.
- Giữ các loại notification hiện có: `modelUpdated`, `modelDownloadFailed`, `syncCompleted`, `syncFailed`, `maintenanceDue`, `batteryAlert`, `chargeReminder`, `system`.

### 3. Web AI Center: sửa upload validation để không còn lỗi `model has no predict() method`
- Giữ lifecycle quản trị đã chốt:
  - `Đang lên kế hoạch`
  - `Chưa triển khai`
  - `Đã triển khai`
- Upload không còn là “upload & kích hoạt” trực tiếp. Luồng chuẩn là:
  - `Validate file`
  - `Upload để test`
  - `Deploy`
- Thêm/hoàn thiện proxy admin route:
  - `POST /api/admin/ai/models/<type_key>/validate-file`
  - dùng FastAPI `/v1/models/{type_key}/validate-file`
- `UploadDialog` đổi sang preflight validation trước khi cho upload, và nút đổi từ `Upload & kích hoạt` thành `Upload để test`.
- Cải thiện `PredictorAdapter`/validation theo format:
  - `.pkl/.joblib`: sklearn/xgboost/catboost/lightgbm wrappers có `predict`, `predict_proba`, hoặc wrapper `.model.predict`
  - `.keras/.h5`: Keras/TensorFlow
  - `.tflite/.lite`: TFLite interpreter
  - `.onnx`: ONNX Runtime
  - `.pt/.pth`: chỉ nhận TorchScript; raw `state_dict` phải báo lỗi rõ ràng
  - callable model có `__call__`/`forward` thì map sang predictor hợp lệ nếu inference được
- Thông báo lỗi phải đổi từ generic sang lỗi có hành động:
  - ví dụ `Raw PyTorch state_dict is unsupported; export TorchScript or ONNX`
  - hoặc `Custom Keras layer dependency missing`
- Successful upload chỉ tạo version ở trạng thái **`Chưa triển khai`**; version active cũ không bị đổi cho đến khi admin bấm `Deploy`.
- Chuẩn hóa luôn route app-facing `/api/user/ai/models`:
  - parse đúng payload `/v1/types`,
  - lấy `runtimeStatus`, `activeVersion`, `lastLoadAt`, `error` từ `runtimeStatus` nested object,
  - không để app AI tab bị sai trạng thái do parse nhầm dữ liệu.

### 4. App AI cleanup theo server live
- App user chỉ dùng:
  - `GET /api/user/ai/models`
  - `GET /api/user/ai/models/deployed`
  - `GET /api/user/ai/models/<type>/download`
  - `POST /api/user/ai/models/<type>/predict`
- Gỡ hoàn toàn trong app user:
  - `X-Admin-Key`
  - hardcoded `10.0.2.2`, `localhost`, placeholder URL
  - nút reload ở AI tab
  - các flow AI cũ bám endpoint dev/local hoặc mock pre-server
- `APP_API_BASE_URL` production mặc định chuyển sang `http://api.evbattery.live`; URL emulator chỉ còn dùng khi truyền `--dart-define` cho build dev.
- Màn AI vẫn cho mở `charging_time`, nhưng màn dự đoán phải gọi generic user-model contract hoặc local TFLite fallback; endpoint `/api/ai/predict-charging-time` chỉ còn là compatibility path, không còn là flow chính của app.
- Dọn các consumer app còn phụ thuộc model/endpoint legacy trước-server, đặc biệt các phần đang bám `soc`/consumption cũ mà user đã yêu cầu bỏ.

### 5. Settings > Model Name: trang chi tiết xe và relink model xe
- Click `Model Name` mở `VehicleModelDetailScreen` mới, không còn là row tĩnh.
- Tạo catalog generic mới trong Firestore, ví dụ `VehicleCatalogModels`, với schema:
  - `catalogModelId`, `brand`, `provider`, `modelName`, `displayName`
  - `heroImageUrl`, `thumbnailUrl`
  - `battery`, `charging`, `motor`, `dimensions`
  - `components/accessories`
  - `defaultEfficiency`, `specVersion`, `source`
- Scope đợt này: **seed đầy đủ VinFast** trong catalog mới; UI/search/filter đã mở sẵn cho brand/provider khác nhưng chưa cam kết phủ toàn thị trường ở v1.
- Trang Model Name hiển thị:
  - tên xe, ảnh, brand/provider
  - pin/sạc/motor/kích thước
  - linh phụ kiện nếu có
  - version/spec source/last synced
  - CTA `Link lại xe`
- `Linked Devices` mở picker catalog:
  - search theo model
  - filter theo brand/provider
  - chọn model mới
  - confirm relink
- Khi relink:
  - cập nhật `Vehicles/{vehicleId}` với `vehicleName`, `catalogModelId`, `brand`, `provider`, `imageUrl`, `defaultEfficiency`, spec snapshot, `specVersion`, `updatedAt`, `syncedAt`
  - vẫn backfill `vinfastModelId/vinfastModelName` cho tương thích chỗ cũ trong giai đoạn migration
  - invalidate toàn bộ provider đang đọc xe/spec
  - cập nhật tên/ảnh/thông số ở Home, AI, Trip, Service, Settings ngay lập tức
  - gọi `POST /api/web/sync/vehicle` hoặc `sync/full` để server/web dashboard nhận cùng dữ liệu
- `VehicleSpecRepository` hiện chỉ có VinFast sẽ được thay bằng catalog repository mới, có fallback asset local để app vẫn chạy nếu Firestore chưa có seed.

## API / interface cần khóa
- App production dùng base URL: **`http://api.evbattery.live`**
- Admin AI:
  - `POST /api/admin/ai/models/<type_key>/validate-file`
  - giữ `upload`, `deploy`, `undeploy`, `validate-version`, `predict`
- User AI:
  - `GET /api/user/ai/models`
  - `GET /api/user/ai/models/deployed`
  - `GET /api/user/ai/models/<type_key>/download`
  - `POST /api/user/ai/models/<type_key>/predict`
- Sync:
  - `GET /api/user/sync/overview`
  - `POST /api/web/sync/vehicle`
  - `POST /api/web/sync/full`
- App types mới/chỉnh:
  - `AppRefreshCoordinator`
  - `currentTabProvider` thay cho `AppNavigation.navigateToTab()`
  - `VehicleCatalogEntry` thay cho model spec VinFast-only
  - `VehicleModel` mở rộng thêm `catalogModelId`, `brand`, `provider`, `imageUrl`

## Kiểm thử
- Home không còn header/bell lặp; AI/Trip/Service/Settings đều có một AppBar chung cố định.
- Vuốt xuống ở từng tab root đều refresh cùng một tập dữ liệu; badge chuông, AI catalog, vehicle data, sync overview cùng đổi.
- Notification Center:
  - có thông báo thì hiển thị list,
  - không có thì hiển thị `Không có thông báo`,
  - unread badge cập nhật realtime,
  - tap notification model update đưa đúng sang tab AI.
- AI upload:
  - `.pkl`, `.keras/.h5`, `.tflite`, `.onnx`, TorchScript `.pt` pass khi hợp lệ,
  - raw `state_dict` báo lỗi rõ ràng,
  - upload không làm mất active version cũ nếu validation fail,
  - upload thành công tạo `Chưa triển khai`, deploy xong mới thành `Đã triển khai`.
- `GET /api/user/ai/models` trả đúng `activeVersion`, `runtimeStatus`, `runMode`, `downloadUrl`.
- Build app với `APP_API_BASE_URL=http://api.evbattery.live`; không còn gọi `10.0.2.2`, `localhost`, hoặc admin AI endpoints từ app user.
- Relink xe:
  - chọn model VinFast khác trong Settings đổi tên/ảnh/spec ở toàn app ngay,
  - dữ liệu `Vehicles` trên Firestore và web dashboard phản ánh cùng model vừa link.

## Giả định và mặc định
- Dùng **`http://api.evbattery.live`** làm API base production; `/ai` chỉ là web route, không phải mobile API root.
- `pull-to-refresh` là reload dữ liệu app, không phải auto push sync toàn bộ lên server.
- Notification model update tiếp tục theo **app-open/resume sync**, chưa làm FCM/push thật trong đợt này.
- Catalog xe đợt này là **VinFast-first**, nhưng schema/UI/backend sẵn cho đa hãng ở các đợt sau.
- Các endpoint/model/thiết kế legacy trước khi web live vẫn có thể còn trên server tạm thời, nhưng app user sau đợt này sẽ không còn phụ thuộc vào chúng.
