# VinFast Battery v1.1.5 — Báo cáo khắc phục và trạng thái phát hành

Ngày cập nhật: 20/09/2026  
Baseline: [QA v1.1.4](VinFast_Battery_Release_QA_2026-09-20.md)  
Bằng chứng runtime: [docs/qa_evidence/release-qa-2026-09-20](docs/qa_evidence/release-qa-2026-09-20/)

## 1. Kết luận trung thực

APK `1.1.4+114` trong báo cáo QA vẫn **không đủ điều kiện phát hành** với điểm `3.5/10`. Bản source hiện tại có nhiều thay đổi chưa từng được build và chạy lại trên emulator; không được coi là đã sửa lỗi chỉ vì diff tồn tại.

Trong lượt này đã triển khai một phần P0/P1 vào source:

| Hạng mục | Trạng thái | Ghi chú |
|---|---|---|
| API request ID và error envelope tương thích | Đã làm | Backend tự thêm `requestId`, `code`, `userMessage`, `retryable`; giữ `error` cũ |
| `/api/ready` | Đã làm | Firebase là dependency bắt buộc; AI được báo degraded |
| Onboarding commit idempotent | Đã làm | `POST /api/mobile/onboarding/commit`, `Idempotency-Key`, vehicle ID xác định |
| Validate tuổi tối thiểu/ODO/khảo sát | Đã làm | Client và server cùng chặn dữ liệu sai |
| Draft onboarding Firestore + secure local | Đã làm một phần | Có model/repository/rules và luồng chat chính |
| Retry worker/backoff | Đã làm một phần | Có coordinator và lịch backoff; chưa có background service độc lập khi app bị kill |
| Không dùng Tailscale làm default release | Đã làm | URL release lấy từ `--dart-define`; CI yêu cầu HTTPS secret |
| Popup lỗi lặp và offline strip | Đã làm một phần | Có failure window và status strip; API/Shelly state chưa hiển thị đầy đủ trong mọi màn hình |
| Zero-ellipsis tại lỗi QA đã xác nhận | Đã làm | Notification và dashboard customization đã wrap text |
| Loại admin key hard-code khỏi app | Đã làm | Client Shelly không còn gửi `X-Admin-Key` |
| Smart Charging hardware sign-off | Chưa làm | Chưa có tải Shelly an toàn để xác minh thực tế |
| Cloud/DNS/TLS production | Chưa làm | Chưa có domain/quyền cloud trong workspace |
| Flutter analyze/test/build | Blocked | Flutter/Dart daemon cũ trong môi trường treo, lệnh không trả output |

## 2. Thay đổi đã triển khai

### Backend

- Thêm request ID ổn định cho request/response và header `X-Request-Id`.
- Bổ sung `/api/ready` với trạng thái Firebase/AI và HTTP `503` khi dependency lõi chưa sẵn sàng.
- Chuẩn hóa lỗi API mà không xoá trường `error` để giữ tương thích caller cũ.
- Thêm endpoint commit onboarding local-first có kiểm tra schema, tuổi, ODO, catalog và hồ sơ khảo sát.
- Retry cùng operation/idempotency key trả lại cùng vehicle, không tạo bản ghi thứ hai.
- Sửa server nhận và validate `avgDailyDistanceKm`, `usagePurpose`, `typicalSocWhenCharge`.
- Mở rộng `vehicle_catalog.create_user_vehicle` để nhận document ID xác định.

### Flutter

- Phiên bản app chuyển sang `1.1.5+115`.
- Default API không còn là Tailscale; release chỉ dùng URL HTTPS do CI truyền vào.
- Thêm `ApiResult<T>` và các adapter typed cho GET/POST/PATCH/PUT/DELETE.
- Thêm `OnboardingDraft`, secure local cache, Firestore draft và `OnboardingSyncCoordinator`.
- Onboarding chat lưu draft trước, commit server bằng operation ID ở bước hoàn tất.
- AuthGate khôi phục draft và thử đồng bộ lại khi app khởi động/foreground.
- Offline UI chuyển từ popup persistent sang status strip không che nội dung.
- Popup lỗi được de-duplicate theo failure window; exception/URL/UID được che khỏi release UI/log copy.
- Bỏ ellipsis tự động tại notification message và dashboard customization subtitle.
- Bỏ logic coi `RenderFlex overflow/layout` là lỗi được phép nuốt.

### Rules và CI

- Thêm `users/{uid}/onboardingDrafts/current` với field whitelist/range và owner check.
- Thêm workflow quality gates cho Flutter, Flask, gateway, hygiene và release build.
- Release build yêu cầu secret `PRODUCTION_API_BASE_URL` dạng HTTPS và build `1.1.5+115`.

## 3. Kết quả kiểm thử hiện tại

- Backend toàn bộ `web/tests`: **189 passed** (trong đó onboarding/readiness/remediation mới đều xanh).
- Smart charger gateway toàn bộ `tests`: **56 passed**.
- `python -m py_compile server.py vehicle_catalog.py`: **pass**.
- Flutter `flutter analyze --no-pub` vẫn **BLOCKED** vì không xuất output trong timeout; sau khi dọn lock, `flutter --version` và release build đã hoàn tất.
- APK staging `1.1.5+115` đã được build và ký; chưa cài/chạy được vì emulator không đăng ký ADB, nên chưa có runtime screenshot mới.
- Chưa chạy Firebase Rules Emulator.
- Chưa kiểm thử domain production, network throttling đầy đủ, thiết bị vật lý, Shelly cùng tải ≤12A/2500W, Light/Dark/font matrix.

## 4. Việc bắt buộc trước khi phát hành

### Blocker/P0

1. Cung cấp domain/cloud production và secret manager; triển khai API/Caddy với certificate hợp lệ.
2. Đặt `PRODUCTION_API_BASE_URL` trong CI và chạy smoke test `/api/health`, `/api/ready`, bootstrap, onboarding, vehicle và Shelly từ mạng ngoài.
3. Dọn hoặc khởi động lại Flutter/Dart toolchain, sau đó chạy analyze, test và build APK sạch.
4. Chạy Firebase Rules Emulator để chứng minh draft chỉ thuộc owner và client không thể tự tạo vehicle/completion server.

### P1 trước release

1. Hoàn tất migration các service còn trả Map/exception thô sang `ApiResult` hoặc mapper dùng chung.
2. Hoàn thiện status strip cho API, Firebase, Shelly và trạng thái cache trên mọi tab.
3. Xác minh retry worker sau process kill/background; hiện coordinator chưa phải Android background worker độc lập.
4. Chạy UI matrix 320–412dp, font 1.0/1.3/1.5, Light/Dark và TalkBack.
5. Kiểm tra start/stop/double-tap bằng Shelly thật; relay phải được readback và trả về trạng thái ban đầu.

## 5. Cổng nghiệm thu v1.1.5

Chỉ ký duyệt release khi đồng thời đạt:

- 0 lỗi P0/P1 mở.
- 100% luồng đăng ký, onboarding, chọn xe, sync và Smart Charging critical pass.
- Tối thiểu 95% test case thực thi được pass; không tính Blocked là pass.
- Không tạo vehicle/profile/charging session trùng sau retry hoặc mất response.
- Không popup lỗi lặp, không raw exception/hostname/token trong UI release.
- Không crash/ANR ứng dụng trong test matrix.
- Có APK hash, logcat, gfxinfo và ảnh runtime mới; có rollback backend/APK.
- QA account được purge; tài khoản thật và relay được hoàn nguyên.

## 6. Các giới hạn chưa thể che giấu

- Chưa thể tuyên bố app đã đạt `8.5/10`; hiện mới có code/test backend, chưa có build/runtime evidence.
- Chưa thể xác nhận TLS production vì chưa có domain và quyền triển khai cloud.
- Chưa thể chứng nhận an toàn relay vì chưa có hardware/load test được giám sát.
- Landscape, tablet, OTP và Bluetooth vẫn ngoài phạm vi v1.1.5.
- Firebase Admin JSON hiện không được Git track theo filename kiểm tra cục bộ, nhưng chưa thể chứng minh khóa chưa từng bị chia sẻ ngoài Git; nếu từng chia sẻ phải rotate ngay.

## Cập nhật Quick Tunnel và APK staging (21/09/2026)

Quick Tunnel do người dùng mở đã được kiểm tra từ mạng ngoài: `/api/health` và `/api/ready` đều HTTP 200, có request ID; Firebase/AI báo `ready`. APK release staging mới đã build bằng HTTPS tunnel URL:

- `com.bes.vinbatery`, `1.1.5+115`.
- SHA-256 `DC2DBA0E8FBE7FE4764DB313DB090EBE5FF0C4FA821B90C77017BE6DCFD6DE8C`.
- `apksigner` v2 và badging đạt.

Đây là bằng chứng staging tạm thời, không phải production. Quick Tunnel không có SLA; emulator vẫn lỗi ADB/lock nên APK chưa được cài sạch và chưa có runtime QA. Các blocker Flutter analyze, Rules Emulator, thiết bị thật, Shelly supervised test và custom domain/TLS production vẫn còn. Trạng thái phát hành giữ **HOLD**.

## 7. Cập nhật triển khai tiếp theo (20/09/2026)

Runtime QA update: Báo cáo mới [VinFast_Battery_Release_QA_v1.1.5_2026-09-20.md](VinFast_Battery_Release_QA_v1.1.5_2026-09-20.md) và bằng chứng [release-qa-v1.1.5-2026-09-20](docs/qa_evidence/release-qa-v1.1.5-2026-09-20/) đã được tạo. Kết luận vẫn **HOLD**: backend 189/189 và gateway 56/56 đạt; Flutter analyzer, Rules Emulator, Cloud Run staging, APK 1.1.5, thiết bị thật và Shelly chưa có bằng chứng hợp lệ. APK 1.1.4 không được tính lại.

Ngày 21/09/2026, API local chạy trực tiếp với `.env.laptop` đã trả `/api/health` và `/api/ready` HTTP 200, Firebase/AI ready. Người dùng đã mở Quick Tunnel được phê duyệt; hai endpoint tiếp tục trả HTTP 200 từ mạng ngoài. Đã bổ sung allowlist debug-only cho `http://10.0.2.2:5000`, giữ bắt buộc HTTPS ở release. APK release staging `1.1.5+115` đã build thành công; runtime vẫn HOLD do ADB/emulator.

Sau đó đã sửa hai lỗi biên dịch thực tế trong `auth_gate.dart` và `internet_connection_notice.dart`. Targeted test endpoint đạt 3/3; debug build và release compile check đã hoàn tất. Release APK compile check dùng `https://staging.invalid` chỉ để xác minh mã nguồn, không được coi là APK QA/staging hợp lệ. ADB emulator chưa đăng ký nên runtime vẫn chưa chạy.

- Đã thêm manifest Cloud Run `web/cloudrun/api-service.yaml`, Dockerfile API bind theo `${PORT}`, probe `/api/health`, Secret Manager references và hướng dẫn triển khai staging/production trong `web/cloudrun/README.md`. Google Cloud SDK 585.0.0 đã cài; chưa deploy vì OAuth trình duyệt, billing/IAM, secrets và hostname custom chưa được xác minh.
- Đã thêm workflow thủ công `.github/workflows/v115-cloudrun-deploy.yml` dùng Workload Identity Federation, build image bằng `web/Dockerfile.api`, deploy theo region `asia-southeast1` và smoke test health/readiness. Workflow chưa được chạy trên GitHub.
- Đã thêm scaffold Firebase Rules Emulator tại `web/rules_tests/` và quality-gate job (đã chỉnh peer dependency Firebase về v10 tương thích). Local `npm install`/`firebase emulators:exec` vẫn treo khi tải/chạy emulator trong môi trường hiện tại; không đánh dấu Rules đạt.
- Onboarding commit hiện kiểm tra idempotency theo cả operation và key, validate dữ liệu khảo sát trước khi ghi, và dùng transaction khi Firestore production hỗ trợ. Cần contract test trên Firestore thật/emulator để xác minh rollback và concurrent retry.
- `flutter pub get` đã hoàn tất; `flutter analyze --no-pub` vẫn không xuất output và phải dừng sau timeout. Release APK staging `1.1.5+115` đã có badging/hash/signature, nhưng chưa có runtime evidence; blocker này không được che bằng kết quả backend.
- Regression sau cập nhật: `web/tests` **189 passed**, `smart_charger_gateway/tests` **56 passed**, `py_compile` **pass**, `git diff --check` không phát hiện whitespace error. Release readiness vẫn **chưa đạt** cho tới khi Flutter/Rules/Cloud Run/runtime/Shelly gates có bằng chứng.
