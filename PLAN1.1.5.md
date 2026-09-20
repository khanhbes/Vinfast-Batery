# Báo cáo khắc phục và kế hoạch phát hành VinFast Battery v1.1.5

## 1. Kết quả cần tạo

Tạo báo cáo mới `VinFast_Battery_Release_Remediation_Plan_2026-09-20.md`, liên kết trực tiếp tới báo cáo QA và bằng chứng hiện có, không sửa hoặc ghi đè báo cáo cũ.

Mục tiêu phát hành:

- Điểm release readiness tối thiểu `8.5/10`.
- Không còn lỗi `P0/P1`.
- 100% luồng quan trọng đạt Pass; tối thiểu 95% toàn bộ test case thực thi được đạt Pass.
- Không còn test quan trọng ở trạng thái Blocked.
- Không crash/ANR do ứng dụng.
- Bản release candidate dự kiến `1.1.5+115`, được build lại từ đúng source sau khi hợp nhất các thay đổi đang dang dở.

Báo cáo phải nói rõ bản APK `1.1.4+114` không đủ điều kiện phát hành và source hiện tại có nhiều thay đổi chưa được xác minh lại; không được coi các thay đổi này là đã sửa lỗi chỉ vì chúng tồn tại trong working tree.

## 2. Kế hoạch khắc phục theo mức ưu tiên

### P0 — Hạ tầng production và TLS

- Chuyển API khỏi laptop/Tailscale Funnel sang dịch vụ cloud luôn bật với domain production riêng và TLS được quản lý tự động.
- Tailscale chỉ dùng cho development hoặc quản trị nội bộ.
- Tách endpoint:
  - `/api/health`: process còn hoạt động.
  - `/api/ready`: Firebase, AI service và các dependency bắt buộc đã sẵn sàng.
- Thiết lập DNS, certificate-chain monitoring, uptime alert, structured logging và cảnh báo lỗi 5xx/TLS.
- Build APK production với `APP_API_BASE_URL` trỏ cố định tới domain production; không để URL laptop/Tailscale làm giá trị mặc định.
- Smoke test health, bootstrap, onboarding, profile, vehicle và Shelly từ mạng ngoài trước mỗi release.
- Các API tạo dữ liệu phải nhận `idempotencyKey` để retry không tạo trùng xe, hồ sơ hoặc phiên sạc.

Acceptance:

- HTTPS hợp lệ trên emulator và thiết bị thật, không có `HandshakeException`.
- Health/readiness đạt liên tục từ mạng Wi‑Fi và di động.
- Onboarding và sync hoạt động sau mất mạng/phục hồi mạng.
- Retry cùng một request không tạo bản ghi trùng.

### P0 — Onboarding local-first

- Tách trạng thái onboarding khỏi việc API riêng có đang hoạt động hay không.
- Hồ sơ và xe tối thiểu được lưu vào Firebase/local draft trước; API server được đồng bộ sau qua durable sync queue.
- Bổ sung trạng thái rõ ràng: `localPending`, `syncing`, `synced`, `failedRetryable`, `failedPermanent`.
- Mỗi queue item lưu loại thao tác, payload version, idempotency key, số lần thử và thời điểm thử tiếp theo; không lưu token hoặc bí mật.
- Dùng exponential backoff có jitter, dừng retry nền khi offline và tiếp tục khi mạng trở lại.
- Người dùng được vào app sau khi dữ liệu thiết yếu đã lưu; hiển thị “Đang chờ đồng bộ” thay vì báo hoàn tất giả.
- Lỗi validation/server không retry vô hạn; lỗi xác thực yêu cầu đăng nhập lại.

Acceptance:

- Người dùng mới hoàn tất onboarding khi API riêng mất kết nối nhưng Firebase còn hoạt động.
- Sau khi API phục hồi, dữ liệu tự đồng bộ đúng một lần.
- Thoát app, khởi động lại hoặc đăng nhập lại không mất draft và không tạo xe trùng.
- Chỉ tính onboarding hoàn tất sau khi hồ sơ và ít nhất một xe hợp lệ đã được lưu.

### P1 — API, lỗi nền và phản hồi giao diện

- Chuẩn hóa kết quả API thành kiểu dữ liệu có `status`, `code`, `userMessage`, `retryable`, `requestId`; không truyền exception thô lên UI.
- Tạo một nguồn trạng thái kết nối dùng chung thay cho từng service tự phát banner.
- Lỗi sync nền chỉ cập nhật một status strip nhỏ, không mở overlay che màn hình.
- Overlay chỉ dùng cho hành động do người dùng chủ động thực hiện; có hành động cụ thể như “Thử lại”, “Mở cài đặt mạng” hoặc “Đăng nhập lại”.
- Gom lỗi theo mã + endpoint + failure window; đóng banner không được tái xuất hiện liên tục.
- Phân biệt rõ dữ liệu realtime, dữ liệu cache và lệnh điều khiển chưa được server xác nhận.
- Không coi `RenderFlex overflow` là lỗi vận hành được phép bỏ qua; phải ghi nhận trong test/debug.

Acceptance:

- Offline kéo dài không tạo chuỗi popup.
- Nội dung và bottom navigation vẫn thao tác được khi server lỗi.
- Không hiển thị stack trace, hostname nội bộ, UID, token hoặc nội dung exception cho người dùng release.
- Lệnh Shelly chỉ báo thành công sau khi nhận xác nhận trạng thái thiết bị.

### P1 — UI/UX và accessibility

- Bỏ ellipsis tự động đối với nội dung mang nghĩa tại notification và dashboard customization; cho wrap hoặc “Xem thêm”.
- Audit toàn bộ `TextOverflow.ellipsis`; chỉ giữ ở nhãn ngắn mà người dùng vẫn hiểu đầy đủ.
- Sửa form đăng ký/onboarding để tự cuộn tới trường focus và giữ CTA nhìn thấy khi bàn phím mở.
- Kiểm tra touch target tối thiểu 48dp, semantic label cho icon-only, focus order và contrast.
- Chuẩn hóa thuật ngữ giữa “xe”, “phương tiện”, “sạc pin”, “phiên sạc”, “bộ sạc thông minh” và Shelly.
- Bổ sung trạng thái loading, success, empty và error cho tất cả màn hình có dữ liệu động.
- Giữ portrait-only cho bản này và ghi rõ trong đặc tả sản phẩm; chưa tuyên bố hỗ trợ landscape/tablet.

Acceptance:

- Không mất nghĩa do `...` ở 320–412dp và font scale đến 1.5.
- Mọi field và CTA truy cập được khi IME mở.
- Light/Dark Mode đều đạt contrast và không overflow.
- TalkBack đọc được mục đích của các icon tương tác.

### P1 — An toàn sạc và Shelly

- Chặn double-submit bằng trạng thái pending và operation ID.
- Start/stop phải có timeout, xác nhận trạng thái relay sau lệnh và trạng thái “chưa xác định” nếu mất mạng giữa thao tác.
- Giữ giới hạn tải ≤12A/2500W, watchdog, giới hạn thời gian sạc và cơ chế safe-stop.
- Không tự động retry lệnh bật relay nếu chưa biết lệnh trước đã tới thiết bị hay chưa.
- Ghi audit log không chứa Cloud Key hoặc token.

Acceptance:

- Double-tap chỉ tạo một operation.
- Mất mạng sau lệnh không hiển thị thành công giả.
- Relay trở về trạng thái ban đầu sau mỗi test.
- Trạng thái app, backend và thiết bị được đối chiếu trước khi sign-off.

### P2/P3

- P2: permission rationale và nhánh “không hỏi lại”, notification settings, empty states, guide/tooltip, performance và reduced-motion.
- P2: test đầy đủ AI predictor, route planner, maintenance, export, nhiều xe, đồng bộ đăng xuất/đăng nhập.
- P3: feedback/rating trong app, analytics funnel onboarding, richer empty states và benchmark sâu hơn.
- Không đưa survey/rating thành blocker nếu chưa phải yêu cầu kinh doanh của bản v1.1.5.

## 3. Bảo mật và quản lý cấu hình

- File Firebase Admin đang có trong workspace được `.gitignore` bao phủ và không xuất hiện trong danh sách file Git hiện tại; tuy nhiên chưa thể chứng minh khóa chưa từng được chia sẻ hoặc commit ở lịch sử khác.
- Kiểm tra toàn bộ Git history, artifact, cloud drive và CI log. Nếu khóa từng rời khỏi máy tin cậy, thu hồi và cấp khóa mới trước release.
- Di chuyển production secrets vào secret manager; không đóng gói service-account, Shelly key hoặc admin credential trong APK.
- Quét secret trên source và artifact trong CI.
- Xác minh Firebase Rules, App Check, quyền owner theo UID, rate limit đăng nhập/reset password và log redaction.
- `google-services.json` của ứng dụng không thay thế service-account private key; vẫn phải giới hạn API key và cấu hình Firebase đúng package/signing certificate.

## 4. Kiểm thử và cổng phát hành

Chạy lại ba vòng QA trên APK release candidate mới:

- Product Lead: toàn bộ screen map, control ledger, bốn trạng thái dữ liệu và tính nhất quán.
- Người dùng mới: cài sạch, đăng ký, onboarding local-first, từ chối quyền, mất mạng và resume.
- Người dùng lâu năm: auto-login, nhiều xe, lịch sử, sync, start/stop, double-tap và background/foreground.

Ma trận bắt buộc:

- Android API hỗ trợ tối thiểu và API 36.
- Điện thoại portrait 320dp, 360–390dp và 412dp.
- Light/Dark Mode; font scale 1.0, 1.3 và 1.5.
- Mạng bình thường, throttling chậm, offline giữa request và phục hồi.
- Ít nhất một thiết bị Android vật lý để loại trừ lỗi riêng của emulator.
- Shelly test với tải an toàn và người giám sát trực tiếp.

CI bắt buộc:

- Flutter analyze, unit/widget/integration tests.
- Backend và gateway tests.
- Contract tests cho onboarding/sync/idempotency.
- TLS/health smoke test trên domain staging và production.
- Secret scan, dependency scan và build release reproducible.

Release chỉ được duyệt khi:

- 0 P0, 0 P1 mở.
- 100% luồng đăng ký, onboarding, chọn xe, sync và Shelly critical pass.
- Không dữ liệu trùng sau retry.
- Không popup lỗi lặp, overflow hoặc ellipsis mất nghĩa.
- Không crash/ANR ứng dụng trong test matrix.
- QA account được purge và tài khoản thật được hoàn nguyên.
- Có rollback backend và APK trước khi mở rollout theo giai đoạn.

## 5. Những phần chưa thể cam kết

- Chưa thể cam kết sửa TLS nếu chưa có quyền triển khai cloud, DNS, certificate và secret manager.
- Chưa thể chứng nhận start/stop sạc an toàn nếu không có Shelly cùng tải thử được giám sát.
- Chưa thể kết luận khóa Firebase Admin chưa lộ nếu chưa audit Git history và nơi từng chia sẻ file.
- Chưa thể cấp điểm mới chỉ từ source; phải build APK mới và chạy lại toàn bộ runtime QA.
- Landscape, tablet, OTP và Bluetooth không nằm trong cam kết v1.1.5.
- Mục tiêu `8.5/10` chỉ đạt sau khi các cổng phát hành trên có bằng chứng; không nâng điểm dựa trên kế hoạch hoặc thay đổi chưa kiểm thử.
