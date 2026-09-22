# VinFast Battery v1.1.5 — Runtime QA report

Date: 20/09/2026  
Source: `feature/ios-platform`, requested commit `41b5922a`  
Evidence: [release-qa-v1.1.5-2026-09-20](docs/qa_evidence/release-qa-v1.1.5-2026-09-20/)  
Baseline: [QA v1.1.4](VinFast_Battery_Release_QA_2026-09-20.md)  

## Executive result

**Release is not approved.** A staging APK `1.1.5+115` is now built and API smoke-tested through a temporary Quick Tunnel, but it has not been installed or exercised because the emulator has no ADB device. Runtime claims, screen-map completion, UI scores, Shelly safety sign-off and the 8.5/10 target cannot be asserted. The installed APK `1.1.4+114` remains historical only and is not new evidence.

The source SHA is recorded, but source changes are not treated as fixes until a release APK is built and tested. Backend and gateway regression suites are green; Flutter analyzer, Rules Emulator, Cloud Run, release build and all three runtime QA roles remain blocked.

On 21/09/2026 the API was smoke-tested locally with the ignored laptop configuration: `/api/health` and `/api/ready` both returned HTTP 200, with Firebase and AI ready. This proves only local process health; it does not replace an authenticated HTTPS staging endpoint or runtime APK evidence. Cloudflare Quick Tunnel was installed but not publicly opened by the agent without explicit exposure approval.

For safer local-only emulator QA, `AppConstants` was updated to allow the Android host bridge `http://10.0.2.2:5000` only in debug/profile builds; release builds remain HTTPS-only. The targeted unit test passed `3/3`, and a debug APK was built successfully with package `com.bes.vinbatery`, version `1.1.5+115`, SHA-256 `B6BDE2D366A905A4AB618AA52FBFC4D609220EDA4C6B1116BD09D930B197E948`. The AVD launched but did not register with ADB, so no install or runtime pass is claimed.

The release compiler now completes with a placeholder HTTPS URL: APK badging is `com.bes.vinbatery`, `1.1.5`, code `115`, and APK signature v2 verification passes. Hash `0B7C10A5D978FA60A998FA5775EF1187F9C2F43B386C5EC7B73A82DB5541DFAE` is compile-only evidence; the APK was not accepted for QA because `staging.invalid` is not a real backend.

## Environment

- Target package/version: `com.bes.vinbatery`, `1.1.5+115` (not built).
- Emulator available: API 36, `emulator-5554`, 1080×2424, density 420.
- Flutter dependency resolution: passed (`flutter pub get`).
- Physical Android device: not connected/verified in this run.
- Shelly supervised load test: not run; no relay state was changed.
- Cloud Run staging URL/API revision: none.

## Gate summary

| Area | Pass | Fail | Blocked/N/A | Release interpretation |
|---|---:|---:|---:|---|
| Automated backend | 189 | 0 | 0 | Green regression evidence |
| Gateway | 56 | 0 | 0 | Green simulated/gateway evidence; not hardware sign-off |
| Flutter analyze | 0 | 0 | 1 | Cannot certify compile or APK |
| Rules Emulator | 0 | 0 | 1 | Ownership/range rules unverified locally |
| Cloud Run/TLS | 0 | 0 | 1 | Temporary Quick Tunnel smoke only; no Cloud Run/custom-domain evidence |
| Runtime critical flows | 0 | 0 | 1 | Valid staging APK exists, but ADB/emulator blocks install and runtime |
| Release readiness | — | — | — | **Not rateable; release hold** |

Detailed command results are in [gate-results.md](docs/qa_evidence/release-qa-v1.1.5-2026-09-20/gate-results.md).

## Screen map and interaction ledger

Not executed against the staging APK because no ADB device was available. The prior 1.1.4 report remains historical; copying its results here would be misleading. The following remains blocked: splash/login, registration, onboarding steps, vehicle management, dashboard, battery/history/cost, Shelly setup and control, profile/settings, notification/appearance, dialogs/sheets/menus, permission branches, loading/success/empty/error states, keyboard paths, back/gesture paths and portrait-lock behavior.

## Issues and blockers

### [Nghiêm trọng] → Product Lead → Flutter compile gate (partially resolved)

**Mô tả:** Debug compilation initially failed because `_AuthenticatedRootState` used undeclared onboarding draft fields and `InternetConnectionNotice` had an invalid `Stack` children list.  
**Bằng chứng:** Both source errors were corrected; a debug APK `1.1.5+115` then built successfully.  
**Nguyên nhân:** incomplete merge of local-first onboarding state and a malformed UI syntax change.  
**Cách sửa:** fields now live in `_AuthenticatedRootState`; the status-strip widget has balanced children syntax.  
**Acceptance:** targeted test passed `3/3`; release `analyze`, full Flutter suite and release APK with a real HTTPS endpoint still remain required.

### [Nghiêm trọng] → Product Lead → Release pipeline / Flutter analyzer

**Mô tả:** `flutter analyze --no-pub` remained at `Analyzing app...` without a result and was stopped after a bounded timeout. Release compilation now succeeds, but analyzer and runtime evidence remain open.  
**Bằng chứng:** [gate-results.md](docs/qa_evidence/release-qa-v1.1.5-2026-09-20/gate-results.md).  
**Nguyên nhân:** chưa xác định; có dấu hiệu Dart/Flutter process hoặc SDK/toolchain bị treo.  
**Cách sửa:** xác định đúng SDK/process, chạy `flutter doctor -v`, rebuild SDK cache hoặc cài SDK sạch; đặt timeout CI và lưu log.  
**Acceptance:** analyze/test/build hoàn tất trong timeout; APK badging là 1.1.5/115 và được cài sạch trên API 36.

### [Nghiêm trọng] → Product Lead → Cloud Run/TLS staging

**Mô tả:** `gcloud` 585.0.0 đã cài nhưng project/IAM/secrets chưa được xác minh, nên chưa có HTTPS `run.app` để smoke test.  
**Bằng chứng:** `gcloud auth login --update-adc --no-launch-browser` yêu cầu mã xác minh trình duyệt; không có deployment URL.  
**Nguyên nhân:** cần chủ tài khoản hoàn tất Cloud OAuth và cấp quyền project.  
**Cách sửa:** hoàn tất installer, `gcloud auth login`, chọn `vinfast-873db`, cấp IAM tối thiểu, nạp secrets từ Secret Manager mà không log giá trị, deploy revision staging và kiểm tra `/api/health`/`/api/ready`.  
**Acceptance:** HTTPS hợp lệ, readiness/health đạt từ mạng ngoài, error envelope có request ID và không lộ secret/hostname nội bộ.

### [Nghiêm trọng] → Product Lead → Firestore Rules

**Mô tả:** Rules tests không chạy trực tiếp vì thiếu emulator host/port; chưa chứng minh user chỉ đọc draft của mình và client không tự tạo vehicle/completion.  
**Bằng chứng:** direct `npm.cmd test` trả lỗi yêu cầu Firestore emulator.  
**Nguyên nhân:** Firebase Emulator Suite chưa khởi chạy/tải được.  
**Cách sửa:** cài/chạy emulator trong CI hoặc local, chạy `firebase emulators:exec` với timeout và lưu log.  
**Acceptance:** toàn bộ Rules tests xanh, gồm cross-UID, field/type/range và Vehicles/onboardingCompletedAt denial.

### [Nghiêm trọng] → Ba vai trò → Runtime QA

**Mô tả:** chưa thể test onboarding local-first, retry/idempotency, permissions, responsive/font/theme, offline, Smart Charging hoặc Shelly trên APK mới.  
**Bằng chứng:** không có APK 1.1.5 hoặc staging URL.  
**Nguyên nhân:** phụ thuộc build và hạ tầng ở trên.  
**Cách sửa:** sau khi các blocker được giải quyết, build APK mới với HTTPS staging URL, ghi hash, cài sạch và chạy lại toàn bộ critical matrix; mọi source sửa sau đó phải tạo hash mới và rerun affected cases.  
**Acceptance:** 100% critical pass, ≥95% executable pass, 0 P0/P1 mở, không crash/ANR/overflow/meaning-loss ellipsis.

## Vai trò và friction points

- Product Lead: friction lớn nhất hiện tại là không có bằng chứng runtime hợp lệ để xác minh design system, trạng thái lỗi và release safety.
- Người dùng mới: chưa thể kết luận; cần kiểm tra đăng ký, draft resume và empty state trên APK mới. Không được suy đoán từ source.
- Người dùng lâu năm: chưa thể kết luận; cần kiểm tra số tap, đồng bộ và start/stop readback với Shelly thật. Gateway tests không thay thế hardware sign-off.

## UI/UX and industry benchmark

Chưa chấm điểm UI/UX v1.1.5 vì chưa có runtime. Các nhận định trong báo cáo 1.1.4 chỉ là baseline lịch sử. Không nâng điểm dựa trên source diff, unit tests hoặc kế hoạch.

## Release roadmap

- **P0/blocker:** khôi phục Flutter toolchain; tạo APK 1.1.5; hoàn tất Rules Emulator; deploy Cloud Run HTTPS staging; verify secrets/IAM/readiness.
- **P1 trước release:** chạy ba vai trò + ma trận mạng/font/theme; physical device; Shelly supervised readback/idempotency/safe-stop; sửa mọi lỗi runtime phát hiện.
- **P2:** AI degraded paths, richer empty states, performance/reduced-motion, export/route/maintenance regression.
- **P3:** feedback/rating, analytics funnel, benchmark sâu hơn.

## Re-test checklist

- ⚠️ `flutter analyze` hoàn tất trong timeout.
- ✅ Backend tests: 189/189.
- ✅ Gateway tests: 56/56.
- ❌ Rules Emulator ownership/range suite.
- ❌ Cloud Run `/api/health` + `/api/ready` HTTPS smoke.
- ✅ APK `1.1.5+115` badging/hash/signature (staging build; runtime install still blocked).
- ❌ Clean install API 36 và cold start.
- ❌ Product Lead screen map/control ledger.
- ❌ New-user registration/onboarding/offline resume.
- ❌ Long-term user sync/multi-vehicle/settings.
- ❌ 320/360–390/412dp, Light/Dark, font 1.0/1.3/1.5.
- ❌ Physical-device smoke.
- ❌ Shelly supervised load/readback/safe-stop.
- N/A OTP/Bluetooth nếu sản phẩm không có các flow này (xác nhận lại khi runtime).

## Cập nhật staging Quick Tunnel — 21/09/2026

Người dùng đã tự mở Quick Tunnel Cloudflare được phê duyệt tới API local. Smoke test từ mạng ngoài đạt: `/api/health` và `/api/ready` đều HTTP 200, có request ID; Firebase/AI báo `ready`.

Đã build APK staging mới bằng HTTPS hostname tạm thời (không phải production): package `com.bes.vinbatery`, version `1.1.5+115`, SHA-256 `DC2DBA0E8FBE7FE4764DB313DB090EBE5FF0C4FA821B90C77017BE6DCFD6DE8C`; `apksigner` v2 và badging/target SDK đạt.

Kết quả này chỉ chứng minh build và API staging smoke test. Emulator vẫn không đăng ký ADB, vì vậy chưa được tính là clean install/runtime evidence; screen map, interaction ledger, 3 vai trò QA, ma trận font/theme/mạng, thiết bị thật và Shelly vẫn **Blocked**. Release readiness vẫn **HOLD**, không chấm điểm mới.

Sau khi xử lý hai lock rỗng của Flutter SDK, unit test allowlist endpoint đạt `3/3`. Analyzer được chạy lại với timeout khoảng 60 giây nhưng vẫn dừng ở `Analyzing app...`; gate này tiếp tục **Blocked**.

## Runtime smoke update — 21/09/2026

Emulator API 36 đã hoạt động (`emulator-5554`, 1080×2424, density 420). APK staging `1.1.5+115` được cài sạch thành công. Firebase login mở được dashboard, không phát hiện crash hoặc ANR trong logcat mẫu. Các màn hình đã thao tác và chụp bằng chứng gồm login, dashboard/cache, Sạc pin, Sạc hẹn giờ, Lịch sử, Cài đặt, Cài đặt hệ thống và Trung tâm thông báo.

Trong lúc smoke test, Quick Tunnel tạm thời mất DNS từ emulator. App chuyển sang cache, giữ navigation hoạt động và hiển thị status strip; đồng thời hiển thị card “Kết nối bị gián đoạn” và lỗi tải danh sách xe. Đây là bằng chứng offline/error state có thể truy cập, nhưng cũng là blocker cho online onboarding/sync vì tunnel không ổn định. Không phát lệnh relay Shelly.

Issue runtime mới: khi offline, hai card lỗi đồng bộ (`Kết nối bị gián đoạn` và `Kết nối Shelly chưa ổn định`) xuất hiện chồng cùng vị trí. Đóng một card vẫn còn card kia che phần đầu nội dung; đây là P1 UX/deduplication candidate. Bằng chứng: `15-dismiss-error-card.png`, `16-dismiss-second-card.png`, `settings2.xml`.

`dumpsys gfxinfo` trong cùng phiên ghi nhận 67–71% janky frames, p90 85–150ms và một sample p99 4950ms. Đây là tín hiệu performance cần điều tra (đặc biệt khi error/notification cards cùng rebuild), chưa phải benchmark pass; chi tiết ở `gfxinfo-smoke.txt`.

Đã đưa app ra nền rồi mở lại bằng launcher; app vẫn khởi động lại trên dashboard và không ghi nhận FATAL/ANR trong logcat mẫu. Quick Tunnel hiện đã hết DNS (`No such host is known`), do đó online flow không thể tiếp tục với hostname tạm thời.

Ảnh mới: `01-cold-start.png`, `02-login-after-permission.png`, `05-fields-filled.png`, `07-login-after-wait.png`, `09-charging-tab.png`, `10-scheduled-charging.png`, `11-history.png`, `12-settings.png`, `13-system-settings.png`, `14-notification-center.png` trong thư mục evidence. Release readiness vẫn **HOLD**.

## Required next inputs/actions

1. Hoàn tất hộp thoại cài Google Cloud SDK (nếu Windows hiển thị) và đăng nhập project `vinfast-873db`.
2. Cung cấp/thiết lập quyền deploy Cloud Run, billing và các secret đã được quản trị trong Secret Manager; không gửi secret qua chat.
3. Kết nối thiết bị Android vật lý và xác nhận Shelly + tải thử an toàn có người giám sát.

Cho đến khi ba điều kiện trên và các gate kỹ thuật hoàn tất, trạng thái phát hành vẫn là **HOLD — chưa đủ bằng chứng**.
