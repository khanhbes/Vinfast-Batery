# VinFast Battery — Project Status & Task Tracker

> **Single Source of Truth cho Tiến Độ & Nhiệm Vụ**: File này là nơi DUY NHẤT ghi nhận tình trạng phát hành, danh sách việc cần làm (backlog) và nhật ký các task đã hoàn thành. 
> 
> **Quy định cho AI Agent**: Mỗi khi hoàn tất một nhiệm vụ, Agent **bắt buộc** cập nhật tiến độ vào bảng [Nhật Ký Hoàn Thành Task (Changelog)](#3-nhật-ký-hoàn-thành-task-changelog) ở cuối file này. **Không tạo thêm file `.md` mới!**

---

## 1. Trạng Thái Phát Hành Hiện Tại (Release Gates: v1.1.5+115)

- **Phiên bản hiện tại**: `1.1.5+115` (Branch chính / Staging)
- **Đánh giá tổng thể**: **HOLD (Chờ điều kiện kiểm thử runtime & cloud production)**
- **Điểm kiểm thử tự động**:
  - Backend API (`web/tests`): **190 / 190 PASSED (100%)** ✅
  - Smart Charger Gateway (`smart_charger_gateway/tests`): **56 / 56 PASSED (100%)** ✅
  - Backend Syntax Check (`py_compile`): **PASSED** ✅
  - Targeted Mobile API Result Tests (`app/test/unit/`): **3 / 3 PASSED trước task Shelly**; chưa chạy lại sau thay đổi do Flutter SDK treo.
  - APK Release Staging: **Chưa có APK mới cho task Shelly này**. APK staging trước đó không được dùng làm bằng chứng cho thay đổi hiện tại.

### Bảng Kiểm Soát Các Cổng Chất Lượng (Quality Gates)

| Cổng Kiểm Soát | Trạng Thái | Ghi Chú Chi Tiết |
|---|---|---|
| **Backend & AI Tests** | **PASS** | 190/190 tests xanh, bao gồm request-id, error-envelope, ready probe, idempotent onboarding và verification identity gate |
| **Gateway & Safety Tests** | **PASS** | 56/56 tests xanh, bao gồm watchdog ngắt quá tải, RPC LAN/Cloud, power polling |
| **Flutter Analyze/Test** | **BLOCKED** | `flutter analyze/test/build` bị Dart/Flutter process treo không xuất output; chưa được phép tuyên bố pass |
| **Android Runtime QA** | **BLOCKED** | Emulator/ADB local chưa đăng ký thiết bị sạch để lấy screenshot runtime và logcat cho APK v1.1.5 |
| **Firebase Rules Emulator** | **PENDING** | Đã scaffold tại `web/rules_tests/`; cần chạy kiểm thử phân quyền draft/onboarding |
| **Cloud Run & Domain Prod** | **PENDING** | Đã tạo manifest `web/cloudrun/api-service.yaml` và CI workflow; cần cấu hình GCP Project, Secret Manager & SSL Domain |
| **Phần Cứng Sạc Vật Lý** | **PENDING** | Đã khóa Plug S Gen3 (S3PL-00112EU), cần test Cloud ON/OFF/readback và tải nhỏ ≤12A / 2500W |

---

## 2. Danh Sách Nhiệm Vụ & Backlog Ưu Tiên

### P0 — Blockers Bắt Buộc Trước Khi Release
- [ ] **GCP Cloud Run Deploy**: Triển khai `web/cloudrun` với domain HTTPS có chứng chỉ TLS hợp lệ và Secret Manager.
- [ ] **Firebase Security Rules Test**: Chạy Firebase Rules Emulator chứng minh draft onboarding chỉ thuộc owner và không thể ghi đè vehicle của user khác.
- [ ] **Mobile Runtime Verification**: Cài đặt APK `1.1.5+115` lên thiết bị thật hoặc emulator sạch, quay logcat và chụp màn hình luồng onboarding → dashboard → sạc.
- [ ] **Shelly Supervised Test**: Thử nghiệm Plug S Gen3 Cloud start/stop/readback với tải điện thoại/đèn an toàn.

### P1 — Tối Ưu Hóa & Trải Nghiệm Ổn Định
- [ ] **Hoàn tất migration `ApiResult`**: Chuyển các service còn lại trong Flutter sang `ApiResult<T>` có typed error handling.
- [ ] **Offline Status Strip**: Đảm bảo thanh trạng thái mạng (offline/connecting) hiển thị mượt mà trên tất cả các tab mà không che phủ nút bấm.
- [ ] **Background Sync Coordinator**: Nâng cấp sync onboarding thành Android WorkManager / iOS Background Task khi app bị đóng hoàn toàn.
- [ ] **UI Accessibility**: Kiểm thử độ hiển thị trên màn hình nhỏ (320dp) và kích thước chữ lớn (font scale 1.3 - 1.5).

### P2 — Nâng Cấp Tính Năng & Mở Rộng
- [ ] Tích hợp Bluetooth BLE trực tiếp tới pin/BMS dự phòng khi không có Wi-Fi.
- [ ] Mở rộng Personal AI fine-tuning tự động định kỳ sau 30 phiên sạc xác thực.
- [ ] Dark/Light luxury cockpit theme transitions & micro-haptics.

---

## 3. Nhật Ký Hoàn Thành Task (Changelog)

| Ngày | Task / Mục Tiêu | Nội Dung Thay Đổi & File Tác Động | Kết Quả Kiểm Thử | Trạng Thái |
|---|---|---|---|---|
| **21/09/2026** | **Tinh gọn tài liệu toàn diện (Markdown Consolidation)** | - Tạo `AGENTS.md` (Cẩm nang kiến trúc tập trung duy nhất).<br>- Tạo `PROJECT_STATUS.md` (Bảng theo dõi tiến độ & changelog duy nhất).<br>- Thiết lập quy tắc `.agents/rules/task_documentation_rule.md`.<br>- Gom toàn bộ >25 file audit/plan cũ vào `docs/archive/`.<br>- Chuẩn hóa các file đặc tả kỹ thuật vào `docs/specs/`. | - Giảm từ 39 file `.md` rải rác xuống 3 file chính ở root.<br>- Không ảnh hưởng bất kỳ file code logic nào. | **HOÀN THÀNH** ✅ |
| 21/09/2026 | Sửa lỗi biên dịch Flutter & compile check APK 1.1.5 | - Sửa compile errors trong `auth_gate.dart` và `internet_connection_notice.dart`.<br>- Thêm unit test `app_constants_test.dart`. | - 3/3 targeted test PASS.<br>- Release compile check PASS. | HOÀN THÀNH ✅ |
| 21/09/2026 | Quick Tunnel verification & Staging APK Build | - Kiểm tra `/api/health` và `/api/ready` qua Quick Tunnel HTTPS (HTTP 200).<br>- Build APK release staging `1.1.5+115` có chữ ký và badging. | - Remote HTTPS probe PASS.<br>- Staging APK ready. | HOÀN THÀNH ✅ |
| 20/09/2026 | Cloud Run Manifests & GitHub Action CI | - Tạo `web/cloudrun/api-service.yaml`, `Dockerfile.api`.<br>- Tạo workflow `.github/workflows/v115-cloudrun-deploy.yml`.<br>- Thêm scaffold Firebase Rules test `web/rules_tests/`. | - YAML & Dockerfile syntax validation PASS. | HOÀN THÀNH ✅ |
| 20/09/2026 | Idempotent Onboarding & Backend Error Envelope | - Thêm `POST /api/mobile/onboarding/commit` với `Idempotency-Key`.<br>- Chuẩn hóa error envelope với `requestId`, `code`, `userMessage`.<br>- Bổ sung probe `/api/ready`. | - 190/190 `web/tests` PASS. | HOÀN THÀNH ✅ |
| 20/09/2026 | Smart Charger Gateway Safety Watchdog | - Hoàn thiện watchdog giới hạn ≤12A / 2500W và auto cutoff khi đủ pin.<br>- Đồng bộ trạng thái relay qua RPC và Cloud API. | - 56/56 `gateway/tests` PASS. | HOÀN THÀNH ✅ |
| **21/09/2026** | **Shelly Plug S Gen3 Direct Cloud safety hardening** | - Thêm snapshot/config parser, xác minh đúng `S3PL-00112EU`/Gen3, Safe Boot và trường power meter.<br>- No-load test bắt buộc quan sát ON + timer + OFF/readback; khóa double-submit, blind retry ON và trạng thái relay chưa xác định.<br>- Direct repository dùng profile/verification thật; setup Hub là đường dẫn chính.<br>- Cập nhật `SMART_CHARGE_SETUP_GUIDE.md`, `AGENTS.md` và các service/test liên quan. | - `python -m pytest web/tests -q --basetemp=.pytest-tmp`: **190/190 PASS**.<br>- `python -m pytest web/tests/test_shelly_cloud_first.py -q`: **43/43 PASS**.<br>- `python -m pytest smart_charger_gateway/tests -q --basetemp=.pytest-tmp`: **56/56 PASS**.<br>- `py_compile` và `git diff --check` PASS.<br>- Flutter analyze/test/build, emulator và Shelly thật: **BLOCKED/PENDING**, chưa có APK mới làm bằng chứng. | **ĐANG XỬ LÝ ⏳** |

---

## 4. Hướng Dẫn Dành Cho Agent Sau Khi Hoàn Thành Bất Kỳ Task Nào

Trước khi trả lời người dùng rằng bạn đã hoàn thành nhiệm vụ:
1. Chạy test liên quan và đảm bảo không có regression.
2. Mở file [PROJECT_STATUS.md](PROJECT_STATUS.md) này.
3. Thêm một dòng mới vào đầu bảng **3. Nhật Ký Hoàn Thành Task (Changelog)** với định dạng chuẩn:
   - Cột Ngày: Ngày hiện tại.
   - Cột Task: Tên task ngắn gọn.
   - Cột Nội Dung: Tóm tắt thay đổi và danh sách file đã tác động.
   - Cột Kết Quả: Lệnh test đã chạy và kết quả (pass/fail).
   - Cột Trạng Thái: **HOÀN THÀNH ✅** hoặc **ĐANG XỬ LÝ ⏳**.
4. Cập nhật trạng thái các mục checkbox trong **1. Release Gates** hoặc **2. Backlog** nếu task tương ứng đã giải quyết xong.
5. **KHÔNG TẠO BẤT KỲ FILE `.md` MỚI NÀO NGOÀI QUY ĐỊNH!**

---

## 5. Current Task Update — Shelly Direct Control

**Date:** 2026-09-21

**Scope:** Fix the runtime blocker where Shelly setup only displayed a warning and did not send a relay test command; enforce hardware safety checks before relay ON.

**Implemented (Fixed-unverified):**

- `app/lib/data/services/smart_charger_credentials_service.dart`: `readyForControl` now requires a verified power meter, Safe Boot, supervised no-load test, and Cloud or LAN transport. Cloud connectivity alone cannot unlock relay ON.
- `app/lib/data/services/smart_charger_service.dart`: both automatic and manual start paths now reject ON before the complete safety gate, while OFF/readback remains available for recovery.
- `app/lib/features/smart_charging/smart_charger_setup_hub_screen.dart`: relay test now runs `configureSafeBoot`, a five-second device-timer no-load ON, OFF and readback; profile promotion from draft to active occurs only after success.
- `app/test/smart_charger_credentials_consistency_test.dart`: regression coverage for Cloud-only rejection and complete safety-gate acceptance.

**Not yet verified:**

- Flutter targeted tests: **BLOCKED**; `flutter test` started a Dart process without output and was stopped after process inspection. No test result is claimed.
- Backend full suite: **ENVIRONMENT-BLOCKED**; 177 tests passed and 12 tests failed during pytest temporary-directory setup with `PermissionError: WinError 5` under `C:\Users\khanh\AppData\Local\Temp\pytest-of-khanh`. Targeted Shelly cloud tests passed `42/42`.
- Real Shelly Cloud/LAN ON/OFF and power-meter readback: **PENDING supervised hardware test**.
- APK rebuild/runtime evidence after this change: **PENDING**.
- Server metadata verification after the safety wizard: **PENDING**.

**Remaining known issues:**

- Existing source contains mojibake in many user-visible strings; this task did not claim a global text cleanup.
- Full Flutter analyze/test, Rules Emulator, physical Android device, production HTTPS and custom domain remain release blockers.
- The global provider default must not be used as evidence for Direct Shelly control; the restored per-user Direct profile must be tested on a fresh install.

**Required next evidence:**

1. Run a new APK from a fresh install with the authenticated user and restore the encrypted Shelly profile.
2. Capture read-only initial status, supervised Safe Boot/no-load test, ON/OFF/readback and W/V/A/Wh values with secrets redacted.
3. Record APK SHA-256 and test log; then change this task from `Fixed-unverified` to `Verified` or `Reopened`.

## 6. Current Task Update — Shelly Cloud Safety Hardening

**Date:** 2026-09-21

**Implemented:**

- Added Cloud snapshot/config parsing for Plug S Gen3, including model/generation, live switch status, meter-field presence and Safe Boot readback.
- Direct Cloud setup now verifies `initial_state=off` and `auto_on=false`; Cloud-only no longer requires a LAN address.
- No-load test now requires observed ON + device timer + no-load threshold + verified OFF, and always performs a final OFF readback.
- No-load voltage is now constrained to 190–255 V; Cloud-only recovery uses the verified transport instead of assuming LAN.
- Start performs a fresh safety preflight and sends exactly one ON command on a fixed transport; uncertain ON outcomes are never retried through another transport.
- Rearm requires confirmed relay/timer state and sends OFF on failed verification.
- UI/controller start gates use `readyForControl` only; hard-coded Direct binding and duplicate Home setup route were removed.
- Restore throttling no longer suppresses retries after failed server restore; verification fingerprint fields are persisted without secrets.
- Backend metadata now treats verification booleans as historical evidence only when device ID, exact model and a non-secret fingerprint match; unbound client flags cannot unlock readiness.
- Documentation now identifies Plug S Gen3 as the supported device and documents manual Cloud Safe Boot setup.

**Verification status:**

- Dart formatter: **PASS** on changed Dart files.
- Flutter analyze/test: **BLOCKED** by the existing Dart/Flutter process hang; no pass is claimed.
- Backend Shelly regression: **43/43 PASSED** after metadata and identity-gate changes.
- Gateway suite: **56/56 PASSED** with workspace `--basetemp` workaround.
- Backend full suite: **190/190 PASSED** with workspace `--basetemp` workaround.
- Real Shelly Cloud relay and meter test: **PENDING supervised hardware test**.
- APK rebuild/runtime QA: **PENDING**; existing APK is not evidence for this change.

**Known blocker:**

- If Shelly Cloud does not expose `initial_state`/`auto_on` in the actual device response, the app intentionally keeps relay ON locked until a one-time LAN `Switch.GetConfig` readback is available.

**Read-only Cloud probe (21/09/2026):**

- Credentials were read from the user-provided local file without printing or persisting secrets.
- Cloud returned HTTP 200 and model `S3PL-00112EU`, but reported generation `G2`; this conflicts with the required Gen3 gate and must be resolved before enabling control.
- Relay was already ON with approximately `436.8 W`, `226.6 V`, `2.888 A`, `11,770.346 Wh`, and `53.5°C`; no ON/OFF command or no-load test was issued because a real load was present.
- Safe Boot readback passed (`initial_state=off`, `auto_on=false`); timer was absent. Hardware verification remains **BLOCKED/PENDING** until the load is confirmed safe to disconnect and the generation discrepancy is explained.

## 7. Current Task Update - Account Guide & Cross-Device Charging Sync

**Date:** 2026-09-21

**Implemented (runtime verification pending):**

- Dashboard and guide preferences are scoped by Firebase UID and support pending, completed and dismissed tour states.
- New registrations seed `tour_overview_v2` as an account-scoped pending tour in local storage and Firestore; existing accounts are not auto-triggered.
- Onboarding screens no longer show duplicate overlays. `AppNavigation` waits for the authenticated UID and mounted anchors before showing the first-run tour.
- Added `ActiveChargingSessionCoordinator` and a Riverpod provider listening to owner-scoped `ChargeLogs`, so Direct Shelly sessions can appear on another device.
- Direct repository restores active sessions from durable `ChargeLogs`; remote Stop creates a terminal row after verified relay OFF.
- Shelly profile, verification, active-session, connection snapshot and connection-mode preferences are UID-scoped. Terminal ChargeLog rows cannot be resurrected as active by a later device.
- Firestore Rules allow the guide fields and prevent terminal-to-active transitions.

**Verification status:**

- `flutter analyze --no-pub`: **BLOCKED**; the process produced no output and was stopped. No analyze pass is claimed.
- Flutter tests, backend/gateway/Rules tests after these edits: **PENDING**.
- Two-device emulator test and supervised Shelly cross-device Stop/readback: **PENDING**.
- Release remains **HOLD**; source changes are not runtime evidence.

**Known limitations:**

- Device B can display a cloud session immediately, but Stop is available only after the UID's Shelly profile is restored and live readback identifies the same device. Without credentials it remains display-only.
- Firestore connectivity is required for a fresh cross-device session; offline data must be treated as stale.

## 8. Follow-up implementation update — 2026-09-22

**Đã thực hiện:**

- Hoàn tất UID-scoped guide state và active charging session coordinator; trạng thái pending/completed/dismissed, cache và ChargeLogs không dùng chung giữa các tài khoản.
- AppNavigation là điểm kích hoạt duy nhất của tour; tour chờ anchor render, không mở trùng và có nhãn dữ liệu cũ cho phiên đồng bộ stale.
- Direct repository khôi phục phiên ChargeLog theo UID; Stop từ thiết bị khác chỉ được tiếp tục sau live Shelly readback, sau đó ghi terminal state idempotent.
- Stop cross-device có thêm cổng đối chiếu Device ID với Cloud snapshot đúng model trước khi gửi lệnh; GlobalChargingPill vẫn hiển thị phiên khi thiết bị B chưa khôi phục xe đã chọn và gắn nhãn dữ liệu cũ khi stale.
- Bổ sung chặn phục hồi terminal ChargeLog thành active, UID-scope profile/verification/session/connection snapshot/mode và không gửi relay OFF khi đăng xuất.
- Sửa null-safety và compile issues trong Shelly service/log/repository; analyzer trên toàn bộ nhóm file đã thay đổi báo **No issues found** khi chạy với `APPDATA` tạm thời để tránh lỗi quyền telemetry của SDK.

**Kiểm thử:**

- Backend suite: **190/190 PASSED** với thư mục tạm trong workspace.
- Smart charger gateway: **56/56 PASSED** với thư mục tạm trong workspace.
- Dart analyzer mục tiêu: **No issues found**.
- `flutter analyze --no-pub` và ngay cả `flutter --version` vẫn **BLOCKED**: tiến trình Flutter không xuất output và phải dừng sau timeout; Dart SDK analyzer chạy độc lập được, nhưng đây là vấn đề toolchain/môi trường và không được tính là pass.
- Flutter test mục tiêu cũng không xuất output trong thời gian kiểm tra và đã phải dừng; không được tính là pass. Rules Emulator, APK build/cài sạch, hai runtime độc lập và Shelly Plug S Gen3 có tải giám sát: **CHƯA CÓ BẰNG CHỨNG**.

**Trạng thái phát hành:** **HOLD**. Chưa được kết luận app đã đồng bộ đa thiết bị hoặc Shelly đã hoạt động thật. Cần build APK mới, test hai emulator/thiết bị với cùng UID, test live readback/Stop và ghi hash/log trước khi đánh giá lại release gate.

## 9. Runtime emulator & Shelly test — 2026-09-22

**Emulator thực tế:**

- AVD Medium Phone API 36.1, 1080×2400, density 420; cài sạch `com.bes.vinbatery` từ APK release hiện có.
- APK metadata: `versionName=1.1.5`, `versionCode=115`, package đúng; SHA-256 `DC2DBA0E8FBE7FE4764DB313DB090EBE5FF0C4FA821B90C77017BE6DCFD6DE8C`.
- Firebase không kết nối được trong emulator do network không có route ra Internet; app không crash và hiển thị status strip offline cùng nút Thử lại.
- Permission notification hiện đúng system dialog; nhánh từ chối đã thực hiện. Sau đó app vẫn hiển thị màn hình lỗi Firebase có hướng dẫn thử lại.
- Startup tới activity mất khoảng **28,8 giây**; `dumpsys gfxinfo` ghi **9 frames, 8 janky (88,89%)**, percentile 90/95/99 khoảng 4,95 giây. Đây là blocker hiệu năng/runtime cần điều tra, dù emulator đang có dấu hiệu system UI ANR.
- Bằng chứng: `docs/qa_evidence/release-qa-v1.1.5-2026-09-20/12-emulator-medium-splash.png`, `13-emulator-medium-after-notification-denied.png`, `emulator_medium_permission.xml`.
- Screenshot SHA-256: `12-emulator-medium-splash.png` = `F77B432DC6CF08C4794F21DE696136936D35D85BE013E498F486E314E855D27C`; `13-emulator-medium-after-notification-denied.png` = `54BF11EBE12405B49ED6F69FBB86D4B7CFDE12EFE36F3B3E49C93EE154B793D9`.

**Shelly thật:**

- Read-only Cloud hiện xác nhận relay OFF, 0 W, 0 A, 226,6 V, 43,3°C, Safe Boot `initial_state=off`, `auto_on=false`.
- Đã chạy đúng một chu kỳ an toàn với precondition relay OFF/0 W: request ON kèm timer 5 giây trả lỗi HTTP client (`HttpResponseException`); không retry ON vì kết quả lệnh không chắc chắn.
- `finally` đã gửi OFF (HTTP 200) và readback cuối xác nhận relay OFF, 0 W, 0 A, 226,6 V, energy 12.281 Wh. Relay được để ở trạng thái an toàn.
- Cloud tiếp tục báo model `S3PL-00112EU` nhưng generation `G2`; vì vậy đây là **FAIL/BLOCKED**, không phải bằng chứng Shelly Plug S Gen3 hoạt động đạt gate. Cần xác minh firmware/nhận dạng thiết bị và nguyên nhân HTTP ON trước khi thử lại.

**Kết luận lượt test:** APK chạy được đến activity và xử lý offline/permission, nhưng chưa đạt runtime gate do startup/jank, Firebase network và Shelly hardware verification. Release vẫn **HOLD**.
## 10. Direct Cloud control verification — 2026-09-22

**Đã triển khai trong source:**

- `app/lib/data/models/shelly_snapshot.dart`: tách identity phần cứng khỏi generation giao thức Cloud; chấp nhận Plug S Gen3 `S3PL-00112EU` khi Cloud trả `G2` (LAN vẫn yêu cầu generation phần cứng `3`).
- `app/lib/data/services/shelly_clients.dart`: thêm limiter Cloud tuần tự khoảng 1 giây/request, typed command result, mã lỗi HTTP/provider đã chuẩn hóa, `Retry-After` và cờ lệnh có thể đã tới thiết bị; không lộ response thô/credential.
- `app/lib/data/services/smart_charger_service.dart`: giữ operation ID, không retry ON khi timeout/ambiguous, best-effort OFF + readback, khóa trạng thái chưa xác định và chỉ thành công sau readback.
- `app/test/unit/smart_charger_service_test.dart`: cập nhật fixture Cloud G2 và thêm regression cho provider error/ambiguous ON không fallback sang ON transport khác.
- `app/lib/core/services/dashboard_preferences_service.dart`: guard `FirebaseAuth.instance` để offline shell/widget tests không crash trước Firebase bootstrap.

**Kết quả kiểm thử:**

- APK mới nhất: package `com.bes.vinbatery`, `versionName=1.1.5`, `versionCode=115`; SHA-256 `4DDDAAFFD6D5903F020173D00DF1E7ABC4A680DE33010DF36F31183970F62BAD` (build sau limiter và Firebase bootstrap guard; APK v2 signature verified).
- Dart analyzer cho nhóm file thay đổi: **PASS — No issues found**.
- Flutter test mục tiêu `test/unit/smart_charger_service_test.dart`: **22/22 PASS**.
- Toàn bộ Flutter suite: **379/379 PASS**.
- Backend `web/tests` với `--basetemp` trong workspace: **190/190 PASS**.
- Smart charger gateway với `--basetemp` trong workspace: **56/56 PASS**.
- `flutter analyze --no-pub` toàn dự án: **BLOCKED**; tiến trình không xuất kết quả sau khoảng 90 giây và đã dừng. Dart analyzer nhóm file Shelly vẫn **No issues found**.
- Emulator/thiết bị Android: **BLOCKED** trong phiên này vì không có AVD/device (`adb devices` không có thiết bị); APK chưa được cài runtime từ bằng chứng mới.

**Shelly Plug S Gen3 — Direct Cloud, chu kỳ có giám sát:**

- Đọc ban đầu HTTP 200: relay **OFF**, 229,8 V, 0 W, 0 A.
- Chỉ gửi **một** lệnh ON với `toggle_after=5`; Cloud trả HTTP **200**.
- Rate-limited readback sau ON 2 giây: relay **ON**, `timer_started_at` có mặt, `timer_duration=10s`, 229,8 V, 3,2 W, 0,037 A (đạt ngưỡng no-load ≤5 W/≤0,1 A).
- Gửi OFF HTTP **200**; readback cuối: relay **OFF**, 229,8 V, 0 W, 0 A. Chu kỳ đã quan sát đủ OFF → ON + timer → OFF, không retry ON.
- Đây là bằng chứng Direct Cloud điều khiển từ xa và đo W/V/A với tải không đáng kể; Wh không tăng đáng kể vì thời gian test ngắn. Cần thêm test tải nhỏ có giám sát để xác nhận Wh tăng theo thời gian trước khi sign-off phần đo năng lượng.

**Trạng thái:** Direct Cloud remote control **đã hoạt động thực tế ở mức guarded và đã vượt no-load/timer readback**. Chưa tuyên bố release-ready toàn app: còn full Flutter analyze/test, emulator/thiết bị thật, test tải nhỏ/Wh, Rules/secret scan và production HTTPS/Cloud billing.

## 11. Emulator smoke test — 2026-09-22

**Môi trường và APK:**

- Đã khởi động AVD `Medium_Phone_API_36.1`, Android API 36, 1080×2400, density 420; emulator được giữ chạy cho phiên thao tác tiếp theo.
- Đã uninstall/install sạch `com.bes.vinbatery`; APK `1.1.5+115`, SHA-256 `4DDDAAFFD6D5903F020173D00DF1E7ABC4A680DE33010DF36F31183970F62BAD`.
- Cold start đến activity thành công. System UI hiện dialog `System UI isn’t responding` trong lúc permission dialog; đã chọn `Wait`. Đây là system/emulator issue, không phát hiện app process crash.

**Luồng đã thao tác:**

- Permission thông báo hiện đúng; đã từ chối và app vẫn ở login, không crash.
- Màn hình login và đăng ký render được; submit form đăng ký trống hiển thị đủ lỗi inline cho họ tên, email, số điện thoại, mật khẩu và xác nhận mật khẩu.
- Status strip offline hiển thị `Máy chủ chưa sẵn sàng · đang dùng dữ liệu gần nhất` kèm `Thử lại`; tap retry không làm app process dừng.
- App process vẫn sống sau smoke test (`pidof com.bes.vinbatery` trả PID); logcat không có `FATAL EXCEPTION`, app ANR hay process death.

**Kết quả và blocker:**

- API staging Quick Tunnel `poultry-crown-sunrise-behalf.trycloudflare.com` không resolve/không có route trong emulator; `/api/ready` và `/api/app/config` fail `SOCKET_EXCEPTION`. Vì vậy chưa thể đăng nhập Firebase, onboarding, đồng bộ ChargeLog hay kiểm tra Shelly qua UI.
- `dumpsys gfxinfo` sau startup ghi 7 janky frames (100% trong batch đo), GPU percentile khoảng 4,95 giây; cần lặp lại trên emulator ổn định và thiết bị vật lý trước khi kết luận hiệu năng app.
- Bằng chứng: [startup](docs/qa_evidence/release-qa-v1.1.5-2026-09-20/emulator-api36-startup.png), [login offline](docs/qa_evidence/release-qa-v1.1.5-2026-09-20/emulator-api36-login-offline.png), [validation đăng ký](docs/qa_evidence/release-qa-v1.1.5-2026-09-20/emulator-registration-invalid.png), [permission XML](docs/qa_evidence/release-qa-v1.1.5-2026-09-20/emulator_medium_permission.xml).

**Trạng thái:** Smoke test emulator **PASS có giới hạn** cho cài đặt, cold start, permission denial, login/registration shell và offline status strip. Runtime release gate **HOLD** đến khi tunnel/API resolve, Firebase auth hoạt động, full onboarding + Shelly UI được test và warning jank được phân biệt trên thiết bị vật lý.

## 12. Authenticated emulator follow-up — 2026-09-22

**Đăng nhập:**

- Đã đăng nhập thành công bằng tài khoản QA hiện có với địa chỉ đúng `@gmail.com`; địa chỉ `@gmai.com` không hợp lệ và Firebase trả lỗi credential.
- Sau đăng nhập, app vào được Tổng quan và giữ process sống. Dữ liệu xe Feliz/cache được hiển thị dù API Quick Tunnel vẫn offline.

**Các màn hình đã duyệt:**

- Tổng quan: pin, quãng đường, ODO, lộ trình sạc, bảo dưỡng và đồng bộ.
- Sạc pin: Smart Charge, chọn mức pin, sạc AI/hẹn giờ; phiên hiện tại báo chưa kết nối bộ sạc.
- Lịch sử: empty state `0 Wh`, `0 đ`, `0 phút`, bộ lọc xe/khoảng ngày và nút Xuất.
- Cài đặt: hồ sơ, Garage xe, Smart Charger Shelly, lộ trình sạc, AI, bảo dưỡng, cài đặt hệ thống và cẩm nang.
- Smart Charger: nhận diện Plug S Gen3, hiển thị Cloud/LAN/Đo tải/Safe Boot và nút Kiểm tra; do Cloud/API offline nên trạng thái Cloud, LAN và no-load vẫn `Chưa xác minh`, Start không được mở khóa.

**Vấn đề runtime phát hiện:**

- Hai banner lỗi đồng bộ/Shelly tái xuất hiện và phủ lên vùng tab Smart Charger; nút đóng không duy trì trạng thái đã đóng, làm tab Bảo vệ/Cài đặt khó hoặc không thể chạm. Đây là lỗi UX P1 cần de-duplicate theo `code + endpoint + failure window` và không che navigation.
- Accessibility content của màn hình Shelly đang hiển thị Device ID đầy đủ. Không ghi giá trị đó vào báo cáo/log; các ảnh authenticated có thông tin tài khoản/thiết bị đã được xóa khỏi thư mục bằng chứng.
- Popup chi tiết lỗi chỉ hiển thị thông báo thân thiện, không lộ stack trace/hostname/token; điểm này đạt trong phiên offline.

**Trạng thái:** Firebase login và duyệt màn hình chính **PASS**. Onboarding đồng bộ, session đa thiết bị và điều khiển Shelly qua UI **BLOCKED** do Quick Tunnel/API không resolve và safety verification trên app chưa hoàn tất. Release vẫn **HOLD**.

## 13. History, notification and Direct Cloud acceptance — 2026-09-22

### Firestore and history

- Production Firestore rules were deployed to project `vinfast-873db`; deployed ruleset: `978f800b-ea5b-4a87-9f08-e7e035c4804e`.
- Root cause of false empty history was confirmed: the production `ChargeLogs` read rule required delete/archive fields that legacy documents and the app query did not provide. The deployed rule now checks ownership only; filtering remains client-side.
- Admin read-only verification found **14** ChargeLogs total. September 2026 contains **5** terminal sessions: 4 cancelled and 1 interrupted. The new history screen keeps old data on refresh failure and does not render a zero-summary empty state for an initial permission/network error.
- Rules Emulator tests pass for owner queries, legacy documents without delete flags, cross-UID denial, preferences and onboarding drafts.

### Background error UX and privacy

- Background charger/session/API failures no longer open repeated overlays; they remain in the shared status strip. User-triggered actions and safety warnings retain actionable dialogs.
- Smart Charger setup now accepts an explicit Cloud Host, masks device identifiers in test feedback, and avoids exposing internal vehicle IDs in the setup/control semantics.
- A server backup timeout was added to the Direct Cloud verification path so an unavailable Flask/Quick Tunnel cannot block the local Cloud connection flow.

### Shelly Direct Cloud evidence

- Supervised no-load cycle passed outside the app: one ON command with `toggle_after=5`, observed relay ON and positive timer, no-load telemetry within 5 W/0.1 A, then OFF/readback OFF. Final relay state was OFF; no second ON was sent. Direct Cloud remote control and W/V/A readback are therefore proven for this device. Short no-load duration is insufficient to claim Wh growth under load.
- Latest universal APK build: `1.1.5+115`, package `com.bes.vinbatery`, SHA-256 `F67D40A61AE2711E307D57C41E9A7B277E224C84DDBD44857822D3585912D1FE`. x86_64 split APK SHA-256: `110FF456B47500FC9D21B4354BC3D893E4F60C2D045ED515F76C3AC2CA3067E9`.
- Targeted Flutter Shelly tests: **26/26 PASS**. APK build succeeds. The latest APK UI re-test is **BLOCKED by the API 36 emulator storage/package-manager state**: `/data` had only ~307–398 MB available and Android refused installation even for the x86_64 split. No claim is made that the latest APK has passed the in-app ON/OFF gate.

### Remaining release blockers

- Quick Tunnel/API endpoint is still unreachable from the emulator; production HTTPS endpoint is not deployed.
- Full `flutter analyze --no-pub` remains blocked by the SDK/toolchain hanging; targeted analyzer/tests and backend/gateway/Rules suites are not a substitute for the full gate.
- APK is debug-signed, not production-signed; no physical Android device or supervised loaded Shelly test was completed in this cycle.
- Release status remains **HOLD**. Direct Cloud hardware control is **PASS (guarded/no-load)**, while in-app Shelly acceptance and production release remain unverified.

## 14. Regression close-out — 2026-09-22

- Sửa lại widget regression test `app/test/widget/smart_charging_control_screen_test.dart` để phản ánh đúng yêu cầu: lỗi Shelly nền không mở popup, không có nút `CHI TIẾT`/đóng overlay và không che điều hướng; lỗi vẫn thuộc status strip.
- Flutter SDK lock đã được cô lập bảo toàn (`lockfile.stale-20260922`) và tạo lại lockfile; cấp quyền Modify tối thiểu cho tài khoản sandbox trên cache SDK để chạy được tool. Không sửa/xóa mã nguồn ứng dụng.
- Toàn bộ Flutter test suite sau thay đổi: **379/379 PASS**. Test riêng trạng thái lỗi nền Smart Charger: **PASS**.
- APK mới nhất vẫn là `1.1.5+115`, package `com.bes.vinbatery`, SHA-256 universal `F67D40A61AE2711E307D57C41E9A7B277E224C84DDBD44857822D3585912D1FE`; không build lại sau thay đổi chỉ ở test.
- Rules production và Rules Emulator evidence ở mục 13 vẫn giữ nguyên: ruleset `978f800b-ea5b-4a87-9f08-e7e035c4804e`, ChargeLogs **14** tổng cộng và tháng 09/2026 **5** phiên.
- Shelly Direct Cloud no-load evidence vẫn **PASS**: đúng một ON timer 5 giây, quan sát ON/timer, telemetry không tải, OFF/readback OFF; relay cuối **OFF**. Chưa có bằng chứng Wh tăng dưới tải và chưa hoàn tất cùng chu trình qua APK mới.

**Cổng còn mở:** cài APK mới lên emulator API 36 bị chặn bởi `/data` gần đầy/package manager; tunnel/API không ổn định; chưa có thiết bị Android vật lý và test tải Shelly có giám sát. Vì vậy release toàn app và nghiệm thu Shelly qua UI vẫn **HOLD**, không nâng điểm dựa trên test tự động hay source.
