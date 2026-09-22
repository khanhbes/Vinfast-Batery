# VinFast Battery v1.1.4 — Release QA/UX report

Ngày chạy: 20/09/2026  
APK: `VinFast_Battery_v1.1.4_Release.apk` · package `com.bes.vinbatery` · `1.1.4+114`  
Thiết bị chính: Android Emulator Pixel 9a, API 36, 1080×2424, dọc, dark theme mặc định.  
Phạm vi: kiểm thử runtime bằng APK release; không sửa mã nguồn, API hoặc schema.

## 1. Kết luận điều hành

**Release readiness: 3.5/10 — chưa đủ điều kiện phát hành.** Đăng nhập Firebase bằng tài khoản hiện có thành công và dashboard có dữ liệu, nhưng endpoint API mặc định không hoàn tất TLS handshake. Vì vậy onboarding không thể hoàn tất, Shelly không đồng bộ, phiên sạc không đồng bộ và các luồng phụ thuộc server không thể sign-off. Logcat ghi rõ `HandshakeException: Connection terminated during handshake` cho các request `/api/user/onboarding`, bootstrap và Shelly.

QA account tạm dùng cho đăng ký/onboarding đã được xoá bằng Firebase Admin; xác minh cuối: Auth không còn user và Firestore `users` không còn document tương ứng. Mật khẩu, email đầy đủ, UID, device/Cloud key không ghi trong báo cáo.

### Số liệu runtime

| Chỉ số | Kết quả |
|---|---:|
| Màn hình/overlay thực sự mở | 22 |
| Lượt control tap/back/keyboard/swipe đã thử | 86 |
| Test case đã chạy | 50 |
| Pass | 28 (56%) |
| Fail | 5 (10% trên tổng case; 22% trên case thực thi không bị block) |
| Blocked/N/A | 17 |
| Crash app/ANR của app | 0 quan sát được; có System UI ANR của emulator lúc cold start |

`Blocked` không được tính là pass. OTP và Bluetooth là N/A theo phạm vi đã chốt. Các màn hình code-discovered nhưng không mở được vì server được liệt kê riêng ở screen map.

## 2. Screen map runtime

| # | Màn hình/overlay | Trạng thái đã quan sát | Bằng chứng |
|---:|---|---|---|
| 1 | Splash/cold start | Pass có thể thao tác sau khoảng 8–12 s; emulator từng hiện System UI ANR | [PL-01-systemui-anr.png](docs/qa_evidence/release-qa-2026-09-20/PL-01-systemui-anr.png) |
| 2 | Android notification permission | Từ chối được, app tiếp tục vào login | [PL-03-login-permission.png](docs/qa_evidence/release-qa-2026-09-20/PL-03-login-permission.png) |
| 3 | Đăng nhập | Validation rỗng/sai; reset password hiển thị xác nhận gửi email (ảnh kết quả không lưu vì có địa chỉ email) | [PL-04-login.png](docs/qa_evidence/release-qa-2026-09-20/PL-04-login.png), [PL-05-forgot-password.png](docs/qa_evidence/release-qa-2026-09-20/PL-05-forgot-password.png) |
| 4 | Đăng ký | Form rỗng, email/phone/mật khẩu sai, keyboard resize | [NEW-02-register-empty.png](docs/qa_evidence/release-qa-2026-09-20/NEW-02-register-empty.png), [NEW-03-register-validation.png](docs/qa_evidence/release-qa-2026-09-20/NEW-03-register-validation.png), [NEW-04-register-keyboard-invalid.png](docs/qa_evidence/release-qa-2026-09-20/NEW-04-register-keyboard-invalid.png), [NEW-05-register-invalid-validation.png](docs/qa_evidence/release-qa-2026-09-20/NEW-05-register-invalid-validation.png) |
| 5 | Onboarding 1/8 | Đăng ký QA thành công, màn hình chào mừng | [NEW-14-register-submit.png](docs/qa_evidence/release-qa-2026-09-20/NEW-14-register-submit.png) |
| 6 | Onboarding 2/8 — chọn xe | Card Feliz/Evo và nút tiếp tục | [NEW-15-onboarding-step2.png](docs/qa_evidence/release-qa-2026-09-20/NEW-15-onboarding-step2.png) |
| 7 | Onboarding 3/8 — nickname/BSX/ODO | Keyboard tự mở; continue và skip đều lỗi TLS | [NEW-16-onboarding-step3.png](docs/qa_evidence/release-qa-2026-09-20/NEW-16-onboarding-step3.png), [NEW-18-onboarding-skip-default.png](docs/qa_evidence/release-qa-2026-09-20/NEW-18-onboarding-skip-default.png), [NEW-19-onboarding-tls-error.png](docs/qa_evidence/release-qa-2026-09-20/NEW-19-onboarding-tls-error.png) |
| 8 | Tổng quan/dashboard | Dữ liệu xe, pin 100%, range, quick actions; banner lỗi server | [VET-02-existing-login-submitted.png](docs/qa_evidence/release-qa-2026-09-20/VET-02-existing-login-submitted.png), [VET-15-overview-after-back.png](docs/qa_evidence/release-qa-2026-09-20/VET-15-overview-after-back.png) |
| 9 | Sạc pin — AI | Target SOC, slider, preset; không bật relay | [VET-03-charge.png](docs/qa_evidence/release-qa-2026-09-20/VET-03-charge.png) |
| 10 | Sạc hẹn giờ | 0/30 phút/1/2/4/6 giờ; chưa gửi lệnh relay | [VET-04-scheduled-charge.png](docs/qa_evidence/release-qa-2026-09-20/VET-04-scheduled-charge.png) |
| 11 | Lịch sử | Empty 7 ngày, filter xe, date picker, loại phiên | [VET-05-history.png](docs/qa_evidence/release-qa-2026-09-20/VET-05-history.png), [VET-06-history-date-picker.png](docs/qa_evidence/release-qa-2026-09-20/VET-06-history-date-picker.png), [VET-07-history-date-applied.png](docs/qa_evidence/release-qa-2026-09-20/VET-07-history-date-applied.png) |
| 12 | Cài đặt | Section phương tiện, AI, hỗ trợ; scroll list | [VET-08-settings.png](docs/qa_evidence/release-qa-2026-09-20/VET-08-settings.png) |
| 13 | Hồ sơ cá nhân | Đã mở và chỉ đọc; không sửa dữ liệu thật | Không lưu ảnh vì viewport có UID/email thật |
| 14 | Garage xe | Xe hiện có, thêm xe bottom sheet, lưu trữ icon | [VET-10-garage.png](docs/qa_evidence/release-qa-2026-09-20/VET-10-garage.png), [VET-10-garage-clean.png](docs/qa_evidence/release-qa-2026-09-20/VET-10-garage-clean.png), [NEW-21-add-vehicle.png](docs/qa_evidence/release-qa-2026-09-20/NEW-21-add-vehicle.png) |
| 15 | Smart Charger/Shelly | Cloud/LAN/đo tải/Safe Boot, kiểm tra kết nối; không đổi cấu hình, không relay | Bằng chứng có thông tin thiết bị nhạy cảm đã loại khỏi thư mục công khai |
| 16 | Chi tiết lỗi Shelly | Bottom sheet lỗi, copy/đóng; lỗi TLS hiển thị rõ | Log đã giữ ở [PL-12-logcat-final.txt](docs/qa_evidence/release-qa-2026-09-20/PL-12-logcat-final.txt) |
| 17 | Chọn xe đang kết nối | Bottom sheet chỉ có xe hiện tại | [VET-19-vehicle-selector.png](docs/qa_evidence/release-qa-2026-09-20/VET-19-vehicle-selector.png) |
| 18 | Thông báo | Danh sách 13 chưa đọc, mark-all/read/delete icon | [VET-16-notifications.png](docs/qa_evidence/release-qa-2026-09-20/VET-16-notifications.png) |
| 19 | Chi tiết notification | Bottom sheet Model AI, nút xem chi tiết | [VET-17-notification-detail.png](docs/qa_evidence/release-qa-2026-09-20/VET-17-notification-detail.png) |
| 20 | Tuỳ chỉnh dashboard | Toggle và reorder; đã bật/tắt lại trạng thái ban đầu | [PL-08-layout-customization.png](docs/qa_evidence/release-qa-2026-09-20/PL-08-layout-customization.png), [PL-09-layout-restored.png](docs/qa_evidence/release-qa-2026-09-20/PL-09-layout-restored.png) |
| 21 | Error banner dùng chung | Lặp lại trên dashboard/charge/history/settings khi server fail | [VET-02-existing-login-submitted.png](docs/qa_evidence/release-qa-2026-09-20/VET-02-existing-login-submitted.png) |
| 22 | Offline/orientation probe | Offline screenshot; app giữ portrait 1080×2424 khi ép landscape | [PL-11-offline-state.png](docs/qa_evidence/release-qa-2026-09-20/PL-11-offline-state.png), [PL-10-landscape-attempt.png](docs/qa_evidence/release-qa-2026-09-20/PL-10-landscape-attempt.png) |

Code map còn các nhánh chưa đạt được trong runtime: AI predictor/models/history/control, maintenance, route planner/live map, charge log/manual trip, appearance/theme, guide, developer AI studio, personal AI training, vehicle spec detail, QR scanner dialog và các confirm sheet start/stop charge. Lý do: onboarding/API/TLS và an toàn tài khoản thật; không tự suy đoán pass.

## 3. Vấn đề phát hiện

### P0 — backend TLS chặn onboarding và đồng bộ

**[Mức độ: Nghiêm trọng/P0] → Người dùng mới + Product Lead → Onboarding bước 3, dashboard và Shelly sync →** nhấn “Tiếp tục” hoặc “Bỏ qua & dùng thông tin mặc định” đều ở lại bước 3 và hiện “Lỗi kết nối bảo mật đến máy chủ”. Tài khoản hiện có đăng nhập được nhưng dashboard báo không đồng bộ phiên/Shelly. **Bằng chứng:** [NEW-19-onboarding-tls-error.png](docs/qa_evidence/release-qa-2026-09-20/NEW-19-onboarding-tls-error.png), [NEW-19-onboarding-tls-error-log.txt](docs/qa_evidence/release-qa-2026-09-20/NEW-19-onboarding-tls-error-log.txt), [PL-12-logcat-final.txt](docs/qa_evidence/release-qa-2026-09-20/PL-12-logcat-final.txt). **Root cause đã đủ bằng chứng:** API mặc định trả `HandshakeException: Connection terminated during handshake` trên các request onboarding/bootstrap/Shelly; cần xác nhận cert/proxy/Tailscale ở máy chủ. **Sửa:** khôi phục chứng thư/chain và endpoint health, kiểm thử từ emulator; thêm preflight health + retry/backoff + thông báo hành động được. **Acceptance:** health, bootstrap và onboarding POST hoàn tất qua mạng sạch; retry không tạo record trùng; dashboard chuyển success và Shelly sync không banner lỗi.

### P1 — lỗi trạng thái/feedback

**[Mức độ: Trung bình/P1] → Product Lead + người dùng lâu năm → Error banner toàn app →** banner lỗi server che phần lớn nội dung và tự xuất hiện lại ngay sau khi đóng; “CHI TIẾT” mở sheet nhưng không có hành động phục hồi ngoài thử lại rải rác. **Root cause:** runtime cho thấy lỗi được phát từ sync nền; nguyên nhân UI tự re-emit chưa kết luận từ code. **Sửa:** gom lỗi theo phiên, backoff có giới hạn, banner không che control chính, nút “Thử lại” và “Mở cài đặt mạng” rõ ràng. **Acceptance:** đóng banner không tái hiện liên tục trong cùng một failure window; màn hình vẫn thao tác được.

**[Mức độ: Trung bình/P1] → Product Lead + người dùng mới → Notification cards và dashboard customization →** nhiều mô tả bị cắt `...` (“đã triển khai và sẵn sà…”, mô tả card “…”) làm mất nghĩa; yêu cầu zero-ellipsis không đạt. **Bằng chứng:** [VET-16-notifications.png](docs/qa_evidence/release-qa-2026-09-20/VET-16-notifications.png), [PL-08-layout-customization.png](docs/qa_evidence/release-qa-2026-09-20/PL-08-layout-customization.png). **Root cause:** chưa đủ bằng chứng để kết luận widget nào; cần trace Text/constraints. **Sửa:** wrap theo chiều cao card, hoặc rút gọn có chủ ý kèm “Xem thêm”; kiểm tra font scale 1.3/1.5. **Acceptance:** không có ellipsis tự động trong title/description quan trọng ở 320dp và font scale lớn.

**[Mức độ: Nhỏ/P2] → Người dùng mới → Register →** keyboard tự mở ở onboarding details và ở màn đăng ký làm viewport ngắn; nút tiếp tục vẫn nhìn thấy nhưng trường dưới dễ bị che. **Bằng chứng:** [NEW-04-register-keyboard-invalid.png](docs/qa_evidence/release-qa-2026-09-20/NEW-04-register-keyboard-invalid.png), [NEW-16-onboarding-step3.png](docs/qa_evidence/release-qa-2026-09-20/NEW-16-onboarding-step3.png). **Sửa:** scroll-to-focused-field, `viewInsets`/focus traversal rõ ràng, test font scale. **Acceptance:** mọi field và CTA hiện đủ khi IME mở.

### Harness/không tính lỗi app

- Emulator có System UI “isn't responding” trong cold start; app process sau đó vẫn sống và vào permission/login. Cần tái kiểm trên thiết bị vật lý trước khi gán lỗi app. [PL-01-systemui-anr.png](docs/qa_evidence/release-qa-2026-09-20/PL-01-systemui-anr.png)
- OTP và Bluetooth: **N/A** theo phạm vi được phê duyệt.
- Không thực hiện relay, không đổi password/xoá tài khoản thật; thông số tải ≤12A/2500W vì backend không cho phép tạo phiên an toàn.

## 4. Đánh giá theo vai trò

**Product Lead (4/10):** cấu trúc dashboard, bottom navigation và design language có chủ đích; error state hiển thị khá rõ. Điểm nghẽn lớn nhất là server failure lan toàn app và làm các feature chính không thể release-sign-off. Survey/feedback/rating không thấy entry point runtime; ghi nhận feature gap, chưa kết luận không tồn tại trong nhánh bị block.

**Người dùng mới (3/10):** form validation dễ hiểu và đăng ký Firebase đi được đến onboarding. Friction lớn nhất là onboarding không có đường thoát có ích: Continue/Skip cùng thất bại do TLS, người dùng không biết sửa gì tiếp theo. Empty state vehicle/history có hướng dẫn tương đối tốt.

**Người dùng lâu năm (4/10):** dashboard và các tab chính truy cập nhanh; history có filter/date và preset sạc hẹn giờ. Friction lớn nhất là mọi thao tác lặp lại đều bị phủ bởi banner sync lỗi, khiến không biết dữ liệu nào là cache và lệnh nào đã thực sự tới Shelly. Không kiểm tra start/stop relay để tránh tác động tải thật.

## 5. UI/UX, accessibility và benchmark

- Bố cục dọc 1080×2424 ổn, touch target chính rộng; contrast dark theme tốt ở title/CTA. Không quan sát được Light mode, tablet, font scale lớn hoặc landscape layout thích ứng; landscape probe cho thấy app giữ portrait — cần product decision (lock portrait hay hỗ trợ responsive).
- Điều hướng 4 tab nhất quán: Tổng quan / Sạc pin / Lịch sử / Cài đặt. Thuật ngữ “Sạc pin”, “Lịch sử”, “Garage xe”, “Shelly” nhất quán trong nhánh đã mở; “trạm sạc”/route chưa đạt runtime.
- Chuẩn ngành đặt kỳ vọng vào trạng thái realtime, hành động start/stop ít bước và thông báo rõ: VinFast mô tả theo dõi pin/sạc, trạm và lịch sử trên app chính thức ([VinFast E‑Scooter](https://vinfastauto.com/vn_vi/gioi-thieu-chi-tiet-cac-tinh-nang-tren-app-vinfast-e-scooter)); Tesla cho phép theo dõi tiến trình và giới hạn sạc trong app ([Tesla Support](https://www.tesla.com/support/charging/supercharging)); ChargePoint nhấn mạnh tìm trạm, start/stop một chạm, availability realtime và history ([ChargePoint Drivers](https://www.chargepoint.com/drivers)). Bản build này có khung tính năng tương đương nhưng reliability server và zero-ellipsis chưa đạt kỳ vọng đó.

## 6. Roadmap ưu tiên

1. **Blocker/P0:** sửa TLS/cert/proxy endpoint; thêm health check và smoke test từ emulator; chặn release cho đến khi onboarding + bootstrap + Shelly sync xanh.
2. **P1 trước release:** error state không che UI và không lặp; retry/backoff; xác định cache-vs-server; bỏ ellipsis tự động; test notification permission “không hỏi lại”.
3. **P2:** keyboard/IME scroll; accessibility semantics cho icon-only; quyết định portrait lock/responsive; chạy light/dark/font/tablet matrix.
4. **P3:** survey/feedback/rating nếu yêu cầu sản phẩm; richer empty states, widget/quick action và benchmark sâu hơn với Dat Bike/Selex.

## 7. Checklist tái kiểm thử

- [x] Cài sạch APK, clear data, cold start và permission.
- [x] Login đúng/sai, form rỗng, forgot password request.
- [x] Register validation: email/phone/mật khẩu yếu/thiếu, double-submit probe.
- [x] Tạo QA account và purge Auth/Firestore sau test.
- [ ] OTP nhập sai/hết hạn/resend — **N/A** theo phạm vi.
- [ ] Bluetooth pairing — **N/A** theo phạm vi.
- [x] Onboarding vehicle picker, nickname/BSX/ODO, back/skip.
- [ ] Onboarding hoàn tất — **Blocked: TLS handshake**.
- [x] Dashboard, bottom tabs, history empty/filter/date picker.
- [x] Charge AI/timed UI; không gửi relay.
- [x] Vehicle selector, garage, add-vehicle sheet (không commit xe mới).
- [x] Shelly screen, menu, check/error detail; không đổi Cloud/LAN/relay.
- [x] Notifications list/detail; ghi nhận truncation.
- [x] Dashboard customization toggle/reorder surface và restore.
- [ ] Start/stop charge, double-tap relay — **Blocked/safety gate**.
- [ ] Data sync/logout/re-login after mutation — **Blocked: backend TLS**.
- [x] Offline probe, logcat và gfxinfo capture.
- [ ] Network throttle chậm/khôi phục đầy đủ — **Blocked by endpoint/harness time**.
- [ ] Light mode, font scale lớn, 320dp, 412dp, tablet — **Blocked/not available in this run**.
- [x] Orientation probe; app giữ portrait.
- [ ] Survey/feedback/rating submit — **N/A/không thấy entry point ở nhánh runtime**.

Evidence directory: [`docs/qa_evidence/release-qa-2026-09-20/`](docs/qa_evidence/release-qa-2026-09-20/).  
Không có thay đổi source/public API/schema trong lượt QA này.
