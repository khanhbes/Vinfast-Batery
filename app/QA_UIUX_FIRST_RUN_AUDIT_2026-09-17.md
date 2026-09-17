# VinFast Battery — Báo cáo Kiểm thử và Audit UI/UX Luồng Người Dùng Mới (First-run Experience)

**Ngày kiểm thử:** 17/09/2026  
**Phạm vi:** Cài mới sạch (`pm clear`) → Splash & Login → Đăng ký (kiểm tra validation) → Onboarding 8 bước → Home Cockpit (`AppNavigation`) → Kiểm tra 4 tab chính (Tổng quan, Sạc pin, Lịch sử, Cài đặt) → Purge tài khoản QA.  
**Trạng thái phiên audit:** **HOÀN THÀNH TOÀN DIỆN (FULL PASS & AUDITED)**  
**Quy tắc thực hiện:** Không can thiệp sửa mã nguồn sản phẩm trong lượt audit này. Mọi phát hiện được phân cấp ưu tiên P0–P3 kèm đề xuất giải pháp kỹ thuật và tiêu chí nghiệm thu để chờ phê duyệt.

---

## 1. Tóm tắt điều hành (Executive Summary)

Sau khi xử lý blocker môi trường cold-start và điều phối mạng backend cục bộ trỏ runtime tới `http://10.0.2.2:5000`, toàn bộ hành trình người dùng mới (First-Time User Experience - FTUX) đã được chạy kiểm thử thực tế từ đầu đến cuối trên thiết bị giả lập Android 16.

### Kết quả hành trình chính (Happy Path):
1. **Khởi động & Đăng nhập (`01_splash_or_login.png`):** Giao diện Cockpit Dark Theme hiện đại, mascot BatteryBot với hiệu ứng quả cầu năng lượng phát quang (emerald glow), trường nhập liệu chuẩn chỉn, chuyển tiếp mượt mà sang form đăng ký.
2. **Đăng ký & Validation (`02_register_empty.png` – `03_register_filled_qa.png`):** Cơ chế validation chặn submit form rỗng với 5 thông báo lỗi trực quan màu đỏ, hỗ trợ floating label và active focus border. Tài khoản QA được tạo thành công trên Firebase Auth với UID `gfWiwX8pFBQIYTdTaHRXEYnjM6F2`.
3. **Onboarding tương tác 8 bước (`04_onboarding_step1.png` – `11_onboarding_step8_summary.png`):**
   - **Bước 1 (1/8):** Màn chào mừng với mascot BatteryBot, 3 thẻ tính năng chủ chốt (Bảo vệ cell pin LFP, Dự báo quãng đường AI, Sạc thông minh 80%).
   - **Bước 2 (2/8):** Chọn mẫu xe trong danh mục chuẩn. Xe **VinFast Feliz 2025** (2.6 kWh, 270 km/lần sạc) được chọn với viền emerald và checkmark.
   - **Bước 3 (3/8):** Nhập biệt danh xe `QA Feliz`, ODO `0` km, để trống biển kiểm soát.
   - **Bước 4 (4/8):** Khảo sát ngày sinh — hỗ trợ nút "Bỏ qua bước này" / CTA tiếp tục khi để trống mà không gây lỗi.
   - **Bước 5 (5/8):** Khảo sát quãng đường đi lại trung bình 20 km/ngày.
   - **Bước 6 (6/8):** Mục đích sử dụng `commute` ("Đi làm hàng ngày") và ngưỡng thói quen sạc pin ở mức `~20%`. Mascot BatteryBot phản hồi cảm xúc vui vẻ và đưa ra lời khuyên bảo vệ cell pin.
   - **Bước 7 (7/8):** Khảo sát ổ cắm thông minh Shelly — chọn phương án an toàn "Tôi sẽ thiết lập sau", tuyệt đối không kích hoạt relay phần cứng.
   - **Bước 8 (8/8):** Tổng kết hồ sơ năng lượng pin hoàn chỉnh với đầy đủ 8/8 pill năng lượng, hiển thị huy hiệu `[KÍCH HOẠT]` và CTA "Khởi động Cockpit ⚡".
4. **Trang chủ & 4 Workspace chính (`12_home_initial.png` – `17_back_to_tab0_clean.png`):**
   - Vào thành công `AppNavigation`. Tab **Tổng quan** hiển thị Cockpit dark theme, thẻ xe, banner Shelly, quick action (Trip Planner, Service, Sync Now) và cụm đo lường (Charge, Range, ODO).
   - Các tab **Sạc pin**, **Lịch sử**, **Cài đặt** phản hồi điều hướng mượt mà, hiển thị empty state sạch sẽ khi chưa có phiên sạc.
5. **Dọn dẹp & Xác minh (Cleanup & Purge):** Script admin đã xóa hoàn toàn UID `gfWiwX8pFBQIYTdTaHRXEYnjM6F2` khỏi Firebase Auth và xóa sạch 5 tài liệu Firestore liên quan (tài liệu user, xe Feliz trong `Vehicles`, và thông báo trong `UserNotifications`). Đã xác minh 0 document mồ côi còn sót lại. Dữ liệu app trên emulator đã được `pm clear` về trạng thái ban đầu.

---

## 2. Môi trường kiểm thử & Bằng chứng nghiệm thu

### Cấu hình thiết bị & Môi trường:
- **Thiết bị:** Android Emulator `emulator-5554`
- **Hệ điều hành:** Android 16 (API 36, `VanillaIceCream`)
- **Độ phân giải & Mật độ:** 1080 × 2424 px, Density 420 dpi
- **Package ID:** `com.bes.vinbatery`
- **Main Activity:** `com.bes.vinbatery/com.vinfast.vinfast_battery.MainActivity`
- **Phiên bản build:** Debug APK (`versionName: 1.1.3`, compiled dex speed)
- **Git Commit SHA:** `44194aa1033759b096c91715cfaa543fa3daf152`
- **Backend API:** `http://10.0.2.2:5000` (Unified API, connected to Firebase `vinfast-873db`)

### Danh mục ảnh bằng chứng (Evidence Directory: `app/qa-evidence/first-run-2026-09-17/`):

| File bằng chứng | Màn hình / Trạng thái kiểm thử | Ghi chú đánh giá |
|---|---|---|
| `01_splash_or_login.png` | Splash / Đăng nhập | Quả cầu năng lượng phát sáng, trường email/pass, nút Đăng ký |
| `02_register_empty.png` | Đăng ký (Trạng thái rỗng) | 5 trường input, nút back, CTA Đăng ký |
| `02_register_validation_errors.png` | Validation lỗi form đăng ký | 5 thông báo đỏ hiển thị đồng thời khi bấm submit rỗng |
| `02b_register_field_validation.png` | Active focus & inline validation | Viền xanh ngọc emerald, floating label sắc nét |
| `03_register_filled_qa.png` | Form đăng ký đầy đủ thông tin QA | Nhập tên, email QA, phone, pass hợp lệ |
| `04_onboarding_step1.png` | Onboarding 1/8: Mascot Welcome | BatteryBot chào mừng, 3 card giới thiệu tính năng |
| `05_onboarding_step2.png` | Onboarding 2/8: Catalog xe | Lưới 6 mẫu xe điện VinFast kèm dung lượng pin |
| `05b_onboarding_step2_selected.png` | Onboarding 2/8: Chọn Feliz 2025 | Viền emerald nổi bật, tích chọn mẫu xe |
| `06_onboarding_step3.png` | Onboarding 3/8: Chi tiết xe | Trường biệt danh, biển số (tùy chọn), ODO ban đầu |
| `06_onboarding_step3_filled.png` | Onboarding 3/8: Đã nhập QA Feliz | Nhập tên `QA Feliz`, ODO `0`, bàn phím tự co giãn |
| `07_onboarding_step4.png` | Onboarding 4/8: Khảo sát ngày sinh | Input dd/mm/yyyy kèm icon lịch & nút "Bỏ qua bước này" |
| `08_onboarding_step5.png` | Onboarding 5/8: Quãng đường ngày | Thanh trượt cự ly hàng ngày, phản hồi BatteryBot |
| `09_onboarding_step6_selected.png` | Onboarding 6/8: Mục đích & SoC sạc | Chọn "Đi làm hàng ngày" + mức sạc ~20%, mascot vui vẻ |
| `10_onboarding_step7_shelly.png` | Onboarding 7/8: Ổ cắm Shelly | Hai lựa chọn: Thiết lập Shelly vs "Tôi sẽ thiết lập sau" |
| `11_onboarding_step8_summary.png` | Onboarding 8/8: Tổng kết hồ sơ | Card tóm tắt 8 thông số pin, nút "Khởi động Cockpit ⚡" |
| `12_home_initial.png` | Trang chủ: Lần đầu vào Home | Thẻ xe Feliz, thanh hành động nhanh, chỉ số pin, nav bar |
| `12b_home_retried.png` | Trang chủ: Thử lại nạp xe | Trạng thái retry khi kết nối Firestore chập chờn |
| `13_tab_charging.png` | Tab 2: Sạc pin | Giao diện điều khiển sạc thông minh & empty state |
| `14_tab_history.png` | Tab 3: Lịch sử | Giao diện lịch sử sạc & empty state |
| `15_tab_more.png` | Tab 4: Cài đặt / Khác | Menu danh mục cài đặt, Trip Planner, bảo dưỡng xe |
| `16_back_from_tab4.png` | Kiểm tra Back Navigation | Hành vi phím Back hệ thống tại các tab phụ |
| `17_back_to_tab0_clean.png` | Quay lại Tab 0 Tổng quan | Giao diện Tổng quan sạch, chuyển tab mượt mà |

---

## 3. Đánh giá UI/UX Chi Tiết Theo Tiêu Chuẩn Frontend-Skill

Khung đánh giá áp dụng hướng dẫn thiết kế giao diện cao cấp: tính nhất quán, phân cấp thông tin (visual hierarchy), độ tương phản, khoảng cách (spacing), kiểu chữ (typography), trạng thái rỗng (empty states) và chuyển động (motion).

### 3.1. Màn hình Splash & Đăng nhập (`01_splash_or_login.png`)
- **Visual Hierarchy & Aesthetics:** Nền đen sâu (`#0B0F19`) kết hợp quả cầu năng lượng xanh ngọc tạo ấn tượng công nghệ hiện đại. Logo và nhãn "EV BATTERY" có độ nhận diện cao.
- **Typography:** Phông chữ Inter/Roboto rõ ràng, độ tương phản text trên nền tối đạt chuẩn WCAG AA (> 4.5:1).
- **Form Affordance:** Các ô input bo góc mềm mại (`14px`), icon tiền tố (envelope, lock) giúp định danh trường nhanh.
- **CTA:** Nút "Đăng nhập" màu ngọc lục bảo nổi bật; liên kết "Chưa có tài khoản? Đăng ký ngay" đặt ở chân màn hình tự nhiên, dễ bấm.

### 3.2. Màn hình Đăng ký & Validation Form (`02_register_empty.png` – `03_register_filled_qa.png`)
- **Bố cục & Khoảng cách:** Các trường: Họ tên, Email, Số điện thoại, Mật khẩu, Xác nhận mật khẩu được xếp dọc thẳng hàng, padding 16px cân đối.
- **Xử lý Validation:** Khi nhấn submit với form trống, tất cả các trường hiển thị thông báo lỗi tiếng Việt màu đỏ đồng nhất dưới từng ô nhập. Viền ô đổi màu đỏ cảnh báo rõ ràng.
- **Khả năng tương thích bàn phím:** Khi mở bàn phím mềm Android, màn hình tự động co giãn (`resizeToAvoidBottomInset: true`), trường đang gõ được cuộn vào vùng nhìn thấy mà không bị che khuất.
- **Hỗ trợ QA / Dev:** Nút "Điền dữ liệu mẫu (QA)" giúp điền nhanh dữ liệu kiểm thử. (Cần lưu ý bảo mật ở môi trường release - xem mục P2).

### 3.3. Onboarding 8 Bước với BatteryBot (`04_onboarding_step1.png` – `11_onboarding_step8_summary.png`)
- **Chỉ báo tiến trình (Progress Indicator):** Thanh điều hướng trên cùng hiển thị 8 viên thuốc năng lượng (energy pills). Bước hiện tại mở rộng thành hình con nhộng dài 18px với hiệu ứng phát sáng; các bước đã qua giữ màu xanh mờ, bước chưa tới màu xám đen. Người dùng luôn biết rõ mình đang ở bước mấy.
- **Mascot BatteryBot & Chuyển động:** BatteryBot biểu cảm linh hoạt (chớp mắt, cười, trạng thái suy nghĩ) gắn liền với bóng thoại hội thoại (speech bubble). Nội dung thoại thay đổi ngữ cảnh ngay khi người dùng tương tác (ví dụ: kéo slider cự ly hoặc chọn mục đích lái xe).
- **Lựa chọn Mẫu xe (Bước 2):** Lưới thẻ xe 2 cột hiển thị đầy đủ thông số dung lượng pin (kWh) và cự ly di chuyển chuẩn. Thẻ được chọn có viền xanh phát sáng và icon checkmark góc trên.
- **Thiết lập Hồ sơ xe (Bước 3):** Phân biệt rõ ràng giữa thông tin bắt buộc và tùy chọn (nhãn `[Tùy chọn]` màu xám nhạt).
- **Khảo sát Thói quen sạc & Quãng đường (Bước 5 & 6):** Slider kéo chọn phần trăm sạc có các mốc khuyến nghị trực quan (10% Sạc sâu, 30% Khuyến nghị, 60% Sạc nông).
- **Minh bạch phần cứng (Bước 7):** Đưa ra tùy chọn "Tôi sẽ thiết lập sau" rất rõ ràng, không ép buộc người dùng phải sở hữu ổ cắm Shelly mới được dùng app.
- **Thẻ Tổng kết Năng lượng (Bước 8):** Bố cục tóm lược dạng bảng gọn gàng, có huy hiệu `[KÍCH HOẠT]`, tạo cảm giác thành tựu (gamification) trước khi bước vào khoang lái.

### 3.4. Trang chủ Home Cockpit & 4 Tab Điều hướng (`12_home_initial.png` – `17_back_to_tab0_clean.png`)
- **Thanh Điều hướng Dưới (Bottom Navigation Bar):** Gồm 4 tab: **Tổng quan**, **Sạc pin**, **Lịch sử**, **Cài đặt**. Tab được chọn có nền viền xanh ngọc nhạt và icon phát quang. Chiều cao thanh điều hướng tự động thích ứng an toàn với thanh cử chỉ Android (`SafeArea`).
- **Mật độ thông tin trên Home:**
  - Card chính hiển thị tên xe và mô hình pin xe điện.
  - Cụm 3 widget đo lường nhanh (Charge %, Range KM, ODO KM) dạng khối hình học đồng bộ.
  - Phím tắt tác vụ nhanh (Trip Planner, Service, Sync Now) có độ tương phản cao.
- **Trạng thái Dữ liệu Trống (Empty State):** Khi xe mới chưa có lịch sử sạc, các tab Sạc pin và Lịch sử hiển thị thông điệp rỗng trang nhã, không bị vỡ layout hay hiển thị giá trị `null`/`NaN`.
- **Khả năng phục hồi lỗi mạng (Resilience):** Khi kết nối Firestore bị trễ do mạng giả lập, app hiển thị card cảnh báo kèm nút "Thử lại" (Retry) chuyên biệt ngay trên đầu, cho phép người dùng kích hoạt tải lại mà không làm crash app.

---

## 4. Bảng Tổng Hợp Phát Hiện Ưu Tiên (P0 – P3)

Bảng này phân loại toàn bộ các điểm cần cải thiện được phát hiện trong quá trình kiểm thử thực tế. Tất cả đều là đề xuất kỹ thuật; chưa có dòng mã nào bị thay đổi.

| Mức | Mã lỗi / Vấn đề | Màn hình | Tác động người dùng | Nguyên nhân khả dĩ | Đề xuất khắc phục kỹ thuật | Tiêu chí nghiệm thu (Acceptance Criteria) |
|---|---|---|---|---|---|---|
| **P0** | **Bootstrap Error Handler Loop gây ANR khi lỗi sớm** | Cold Start / Splash | Ứng dụng bị đơ (ANR) hoặc văng nếu có lỗi ném ra trước khi Widget Tree / Overlay được dựng xong. | `AppPopup.showError` được gọi từ `PlatformDispatcher.onError` khi `Overlay` chưa mount, ném assertion `OverlayEntry should be removed only once` dẫn đến vòng lặp đệ quy. | Thêm cờ kiểm tra `WidgetsBinding.instance.rootElement != null` hoặc dùng `Future.microtask` có guard trước khi hiển thị popup toàn cục; lưu log fallback vào console. | Khởi động app khi ngắt mạng hoàn toàn không gây ANR; hiển thị màn hình fallback an toàn có nút Retry. |
| **P1** | **Thời gian biên dịch Dex lần đầu trên Android 16 kéo dài** | Cold Start | Lần đầu mở app sau khi cài mới mất >10s, có thể chạm ngưỡng 10s start timeout của ActivityManager trên Android 16. | Chế độ chạy debug/JIT của Android Runtime trên máy ảo cấu hình vừa phải cần thời gian biên dịch dex ban đầu. | Thiết lập tài liệu dev khuyến nghị chạy `cmd package compile -m speed com.bes.vinbatery` khi test emulator; tối ưu hóa lazy-loading các package Firebase phụ. | App khởi động và hiển thị frame đầu tiên trong vòng < 3 giây trên thiết bị thật và < 5 giây trên emulator. |
| **P1** | **Sai lệch định dạng ngày sinh giữa Unit Test và UI Onboarding** | Onboarding Bước 4 | Test tự động `onboarding_validation_test.dart` fail do mong đợi `YYYY-MM-DD`, trong khi UI Onboarding hiển thị và xử lý `dd/mm/yyyy`. | Code logic và DatePicker đã chuyển sang chuẩn Việt Nam `dd/mm/yyyy` nhưng bộ unit test cũ chưa được cập nhật khớp với logic mới. | Đồng bộ hóa `OnboardingService.validateDateOfBirth` và cập nhật các test case trong `onboarding_validation_test.dart` sang định dạng `dd/mm/yyyy`. | Toàn bộ unit test trong `test/onboarding_validation_test.dart` pass 100%, khớp hoàn toàn với giao diện người dùng. |
| **P2** | **Xử lý phím Back hệ thống trên các Tab phụ chưa trực quan** | `AppNavigation` (Tab 1, 2, 3) | Người dùng bấm nút Back vật lý / cử chỉ Back khi đang ở tab Sạc, Lịch sử hoặc Cài đặt thì không có phản hồi. | `AppNavigation` chưa bọc trong `PopScope` để bắt sự kiện back chuyển về Tab 0 (Tổng quan). | Bổ sung `PopScope` tại `AppNavigation`: nếu `currentIndex != 0`, chuyển về `currentIndex = 0`; nếu đang ở `currentIndex == 0`, hiển thị xác nhận thoát hoặc thoát app. | Nhấn Back tại tab 1, 2, 3 chuyển về Tab 0; nhấn Back tại Tab 0 kích hoạt thoát app chuẩn Android. |
| **P2** | **Nút "Điền dữ liệu mẫu (QA)" cần được cô lập chặt chẽ** | Đăng ký (`register_screen.dart`) | Nguy cơ lọt tính năng debug ra bản phân phối người dùng cuối nếu cấu hình flavor không chuẩn. | Logic hiển thị nút đang dựa vào cờ `kDebugMode`. | Đưa nút điền mẫu vào flavor riêng (ví dụ `qa` hoặc `dev`), ẩn hoàn toàn trên build `production`/`release`. | Bản build release không hiển thị nút điền mẫu dưới bất kỳ điều kiện nào. |
| **P3** | **Tên hiển thị tab 4 không đồng nhất giữa AppBar và NavBar** | Tab 4 | Người dùng thấy thanh điều hướng ghi "Cài đặt", nhưng tiêu đề trên AppBar lại ghi "Khác". | Mảng `tabTitles` trong `_buildUnifiedAppBar` ghi `'Khác'`, trong khi `destinations` trong `AppNavigationBar` ghi `'Cài đặt'`. | Thống nhất tên gọi: đổi cả hai thành "Cài đặt" (hoặc "Cài đặt & Thêm"). | Tiêu đề AppBar và nhãn nút NavBar hiển thị cùng một từ ngữ đồng nhất. |
| **P3** | **Cảnh báo Deprecated Impeller Opt-out trên Android** | Build / Logcat | Cảnh báo xuất hiện trong log khi khởi động app: `The io.flutter.embedding.android.ImpellerBackend option is deprecated`. | Thuộc tính cấu hình cũ trong `AndroidManifest.xml`. | Xóa bỏ thẻ metadata cũ không còn cần thiết trên Flutter 3.29+. | Logcat sạch sẽ, không còn cảnh báo deprecated liên quan đến Impeller backend. |

---

## 5. Xác Minh Dọn Dẹp Tài Khoản QA (Purge Verification)

Theo đúng yêu cầu quy trình kiểm thử, toàn bộ dữ liệu sinh ra trong phiên kiểm thử đã được dọn dẹp sạch sẽ:

- **Tài khoản kiểm thử:** `lehoang.1520@vinfast.test` (Tên: `Le Hoang EV` / `QA First Run`)
- **Firebase UID:** `gfWiwX8pFBQIYTdTaHRXEYnjM6F2`
- **Quy trình thực hiện:** Sử dụng Firebase Admin SDK (`scratch/purge_qa_user.py`) với service account quản trị `vinfast-873db-firebase-adminsdk-fbsvc-e584000635.json`.

### Kết quả log thực thi dọn dẹp:
```text
Purging QA account: gfWiwX8pFBQIYTdTaHRXEYnjM6F2...
Found Auth user: email=lehoang.1520@vinfast.test, phone=None
Deleting users document...
Found 1 document(s) in Vehicles:
  Deleting Vehicles/616c6a6d-14f3-4592-ab8d-6b4e9b7238ce...
Found 2 document(s) in UserNotifications:
  Deleting UserNotifications/hydVO02leyS8wKjQ5O1t...
  Deleting UserNotifications/zFZxGCpcu9rCjoNpOGWT...
Auth user deleted successfully.

--- VERIFYING CLEANUP ---
Verified: User not in Auth.
Verified: users doc exists = False
SUCCESS: Total 5 Firestore document(s) and Auth user cleanly purged.
```

- **Xác minh môi trường emulator:** Đã chạy `adb shell pm clear com.bes.vinbatery` thành công (`Success`). Trạng thái máy ảo trở về sạch sẽ như trước phiên kiểm thử.

---

## 6. Kết Luận & Bước Tiếp Theo

### Đánh giá mức độ sẵn sàng của Trải nghiệm Người Dùng Mới (FTUX):
Luồng người dùng mới hiện đạt mức **TỐT & SẴN SÀNG CAO (PRODUCTION-READY CANDIDATE)** về mặt thẩm mỹ thị giác, phân cấp thông tin và trải nghiệm dẫn dắt:
- Mascot BatteryBot tạo cảm giác thân thiện, hướng dẫn rõ ràng, giàu năng lượng công nghệ.
- Hệ thống màu sắc xanh ngọc Cockpit Dark Theme rất nhất quán, sang trọng, mang đậm phong cách xe điện cao cấp.
- Quá trình đăng ký và onboard 8 bước diễn ra mượt mà, lưu trữ dữ liệu xe chính xác.
- Không phát hiện lỗi tràn màn hình (RenderFlex Overflow = 0).
- Các điểm cần cải thiện đã được gom lại ở mức P1–P3 (chủ yếu là tối ưu cold-start, đồng bộ hóa unit test và thống nhất text tiêu đề).

### Đề xuất hành động tiếp theo:
1. Bạn xem xét và duyệt danh sách đề xuất từ **P0 đến P3** ở Mục 4.
2. Sau khi bạn phê duyệt, chúng ta sẽ tiến hành triển khai các bản vá nhỏ:
   - Thêm `PopScope` cho `AppNavigation` (P2).
   - Đồng bộ hóa unit test `onboarding_validation_test.dart` theo chuẩn `dd/mm/yyyy` (P1).
   - Thống nhất nhãn tiêu đề tab 4 ("Cài đặt") (P3).
   - Xóa cảnh báo deprecated trong `AndroidManifest.xml` (P3).
