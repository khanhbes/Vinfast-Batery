# Kế hoạch Kiểm Thử Toàn Diện Lần Cuối (Final Lead QA & UX Audit Plan) — VinFast Battery App

Kế hoạch này vạch ra quy trình kiểm thử toàn diện mọi nút bấm, tính năng, luồng giao diện và tình huống biên (edge cases) của ứng dụng VinFast Battery trên thiết bị giả lập Android (`emulator-5554`), chụp ảnh minh chứng và tổng hợp báo cáo nghiệm thu cuối cùng.

---

## 1. Mục Tiêu & Tiêu Chí Nghiệm Thu (Acceptance Criteria)
1. **Kiểm tra 100% tính năng & tương tác nút:** Từng nút bấm, thanh trượt, sheet modal, chuyển tab, và form nhập liệu được thao tác thực tế trên giả lập.
2. **Tuân thủ quy tắc Zero-Ellipsis:** Tuyệt đối không xuất hiện lỗi cắt cụt chữ `...` hoặc `Vin...` trên toàn bộ các màn hình và thẻ xe.
3. **Không lỗi Runtime / Overflow:** Không gặp hiện tượng crash, ANR hoặc RenderFlex overflow khi hiển thị dữ liệu hoặc chuyển đổi theme.
4. **Bằng chứng thị giác rõ ràng:** Chụp ảnh màn hình cho mọi luồng tính năng và lưu trữ trong thư mục báo cáo.
5. **Báo cáo nghiệm thu chuyên sâu:** Ghi nhận chi tiết kết quả từng bài test, điểm mạnh UX, và đánh giá sẵn sàng xuất bản (Production Readiness).

---

## 2. Kịch Bản Kiểm Thử Chi Tiết (Test Execution Matrix)

### Giai đoạn 1: Điều hướng cơ sở & Quản lý xe (Base Navigation & Vehicle Switching)
- [ ] **Tab 0 - Tổng quan (Home Dashboard):**
  - Kiểm tra thẻ SoC, phạm vi hoạt động (Range km), nhiệt độ, công suất tức thời.
  - Bấm nút chọn xe trên thanh App Header (`vehicle_switcher`), mở `VehiclePickerSheet`.
  - Chuyển đổi giữa các xe: *VinFast Klara S*, *VinFast Feliz S*, v.v. Đảm bảo tên xe hiển thị 100% không bị `...`.
  - Tương tác với linh vật AI Battery Bot (chạm để xem gợi ý sạc).
  - Thử nghiệm các nút Quick Action (Sạc ngay, Đặt lịch, Tìm trạm, Nhật ký).

### Giai đoạn 2: Trọng tâm Điều khiển Sạc Thông Minh AI (Smart Charging Control)
- [ ] **Tab 1 - Sạc pin:**
  - Kiểm tra tiêu đề AppBar (phải hiển thị rõ "Sạc pin", không bị rỗng).
  - Tương tác thanh trượt Chọn mức sạc mục tiêu (Target SOC: 80%, 90%, 100%).
  - Kiểm tra các chế độ sạc:
    - Sạc ngay lập tức (Immediate Charging)
    - Sạc hẹn giờ an toàn (Safe Timed Charging)
    - Tối ưu biểu giá điện thấp điểm (Off-peak TOU Optimization)
  - Bấm "Bắt đầu sạc", kiểm tra BottomSheet xác nhận an toàn (`StartChargeConfirmationSheet`).
  - Kiểm tra màn hình đếm ngược phiên sạc hoạt động (Active Charging Countdown), công suất dòng điện, và nút Dừng sạc an toàn.

### Giai đoạn 3: Lịch sử & Thống kê Sạc (Charging History & Analytics)
- [ ] **Tab 2 - Lịch sử:**
  - Kiểm tra danh sách phiên sạc (Lọc theo ngày, tuần, tháng).
  - Bấm vào một phiên sạc cụ thể để mở chi tiết (Session Detail Modal / Dialog).
  - Kiểm tra hiển thị điện năng nạp (kWh), chi phí ước tính (VNĐ), và hiệu suất.

### Giai đoạn 4: Quản trị Tài khoản & Cài đặt (Driver Profile, Garage & Settings)
- [ ] **Tab 3 - Cài đặt:**
  - Vào **Thông tin cá nhân**: Kiểm tra avatar, thông tin người dùng, nút chỉnh sửa/lưu.
  - Vào **Garage xe điện**: Kiểm tra danh sách xe sở hữu, thêm/sửa xe, thông tin biển số và dung lượng pin (kWh).
  - Vào **Cài đặt thiết bị & Kết nối**: Kiểm tra cấu hình Shelly Plug IP, cổng API backend, chế độ Offline/Online.
  - Kiểm tra chuyển đổi Theme: Giao diện Tối (Cockpit Dark) sang Sáng (Light) và ngược lại.
  - Kiểm tra nút Đổi mật khẩu và Đăng xuất (Logout Flow) đưa người dùng về Auth Gate.

### Giai đoạn 5: Xác thực & Khách hàng mới (Authentication & Onboarding)
- [ ] **Màn hình Đăng nhập (Login Screen):**
  - Kiểm tra validate form email / mật khẩu trống, định dạng sai.
  - Kiểm tra nút QA Quick Login (chỉ xuất hiện ở Debug/Dev mode).
  - Chuyển sang màn hình Đăng ký (Register Screen).
  - Kiểm tra luồng Onboarding Chat / Khởi tạo xe ban đầu.

### Giai đoạn 6: Kiểm tra Tính ổn định & Phím vật lý (Edge Cases & Stability)
- [ ] Nhấn nút Back phần cứng của Android từ Tab 1, Tab 2, Tab 3 -> Đảm bảo `PopScope` đưa về Tab 0 an toàn thay vì văng app.
- [ ] Kiểm tra thanh trạng thái (StatusBar) và Navigation Bar của Android không đè lên nội dung app.

---

## 3. Kế Hoạch Chụp Ảnh & Báo Cáo
- Sử dụng `adb shell screencap` để lưu ảnh chất lượng cao vào bộ nhớ artifacts.
- Tên ảnh được đặt theo từng tính năng chuẩn hóa:
  - `audit_01_home_dashboard.png`
  - `audit_02_vehicle_picker.png`
  - `audit_03_smart_charging.png`
  - `audit_04_charge_confirmation.png`
  - `audit_05_charge_history.png`
  - `audit_06_session_detail.png`
  - `audit_07_driver_profile.png`
  - `audit_08_vehicle_garage.png`
  - `audit_09_settings_network.png`
  - `audit_10_login_auth.png`
- Cập nhật và xuất bản tài liệu báo cáo QA chuyên sâu với đầy đủ bảng đánh giá, xếp loại và khuyến nghị.
