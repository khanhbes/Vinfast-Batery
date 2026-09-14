# Kế hoạch tùy chỉnh Dashboard, onboarding và hướng dẫn trong app

## Tóm tắt

- Cho phép người dùng tùy chỉnh màn `Tổng quan`: ẩn/hiện, kéo đổi thứ tự và khôi phục bố cục mặc định.
- Tài khoản đăng ký mới phải hoàn thành hồ sơ và chọn ít nhất một xe trước khi vào app; kết nối Shelly là bước tùy chọn.
- Thêm hướng dẫn tương tác theo ngữ cảnh và thư viện hướng dẫn có thể tìm kiếm, mở lại bất kỳ lúc nào.
- Áp dụng cho Android và iOS, hỗ trợ tiếng Việt/Anh, đồng bộ cấu hình theo tài khoản và hoạt động với cache khi offline.
- Giao diện theo phong cách EV cockpit: graphite trung tính, emerald cho hành động, ít card, chuyển động ngắn và hỗ trợ reduced motion.

## Thay đổi ứng dụng

### Dashboard có thể tùy chỉnh

- Thêm nút `Tùy chỉnh` trên App Bar của màn Tổng quan, mở sheet quản lý widget.
- Cho kéo đổi thứ tự, bật/tắt và `Khôi phục mặc định` đối với:
  - Quick Actions.
  - Battery Statistics.
  - Range Prediction.
  - Battery Health.
  - Recent Charging.
  - Efficiency Reference.
- Vehicle Banner, App Bar, thông báo kết nối và Global Charging Pill luôn cố định để giữ ngữ cảnh và cảnh báo an toàn.
- Mỗi widget có ID ổn định; widget mới từ bản cập nhật được tự thêm cuối danh sách, ID cũ không còn tồn tại được bỏ qua.
- Thay đổi hiển thị ngay trên Dashboard, có animation dịch chuyển ngắn; không cho lưu bố cục không còn widget nội dung nào.
- Lưu cache local để mở app tức thời và đồng bộ bố cục qua Firestore theo UID. Xung đột nhiều thiết bị dùng bản có `updatedAt` mới nhất.

### Onboarding tài khoản mới

- Sau khi Firebase tạo tài khoản thành công, không quay lại Login; `AuthGate` chuyển thẳng vào onboarding.
- Chỉ account có `registrationFlowVersion >= 2` mới bị bắt buộc onboarding. Tài khoản cũ không bị chặn.
- Luồng gồm:
  1. Chào mừng và giải thích dữ liệu được sử dụng.
  2. Hồ sơ: họ tên bắt buộc; số điện thoại và ngày sinh đầy đủ tùy chọn.
  3. Chọn xe bắt buộc từ Global EV Catalog đã publish; cho nhập nickname, biển số và ODO ban đầu.
  4. Shelly tùy chọn: kết nối bằng setup hub hiện có hoặc chọn `Thiết lập sau`.
  5. Xem lại và hoàn tất, sau đó bắt đầu tour Tổng quan.
- Ngày sinh lưu dạng `YYYY-MM-DD`, không lưu trường tuổi vì sẽ bị lỗi thời; tuổi được tính khi hiển thị. Chặn ngày tương lai và tuổi lớn hơn 120.
- Nếu mất mạng, giữ dữ liệu từng bước và cho tiếp tục; bước tạo xe cần Internet vì backend phải xác minh catalog và giới hạn tối đa hai xe.
- Shelly không được lưu trong profile. Credential tiếp tục nằm trong secure storage và server vault; nếu kết nối thành công sẽ bind với xe vừa chọn.
- Người bỏ qua Shelly vẫn dùng toàn bộ chức năng không điều khiển relay; Dashboard hiển thị checklist nhẹ để thiết lập sau.

## Hướng dẫn sử dụng

- Tạo `GuideRegistry` dùng chung chứa ID chức năng, tiêu đề Việt/Anh, route, anchor và các bước thao tác.
- Tour lần đầu dùng spotlight/coach mark cho:
  - Chuyển xe và xem thông báo.
  - Tùy chỉnh Dashboard.
  - Xem pin, SoH, quãng đường và lịch sử.
  - Thiết lập Smart Charge, chọn SOC, bắt đầu/dừng sạc.
  - Theo dõi chuyến đi và nhập dữ liệu thủ công.
  - Garage, hồ sơ, Shelly, AI cá nhân, đồng bộ và cài đặt.
- Tour có `Tiếp`, `Quay lại`, `Bỏ qua` và `Không hiện lại`; trạng thái hoàn thành đồng bộ theo tài khoản.
- Hướng dẫn không tự kích hoạt relay, bắt đầu sạc, GPS hoặc xóa dữ liệu. Những thao tác này chỉ được minh họa và vẫn cần người dùng xác nhận thực tế.
- Nâng cấp màn Trợ giúp thành thư viện có tìm kiếm, nhóm theo `Bắt đầu`, `Xe`, `Sạc`, `Chuyến đi`, `AI`, `Tài khoản` và `Xử lý lỗi`.
- Mỗi bài có hướng dẫn từng bước, điều kiện cần, kết quả mong đợi và nút mở đúng màn hình/chạy lại tour.
- Developer Mode không nằm trong hướng dẫn người dùng thông thường.

## API, dữ liệu và bảo mật

- Thêm các interface:
  - `PATCH /api/user/profile` nhận `{name, phone?, dateOfBirth?}` và chỉ cập nhật trường cá nhân.
  - `GET /api/user/onboarding` trả tiến độ hồ sơ, xe và Shelly.
  - `POST /api/user/onboarding/complete` chỉ thành công khi hồ sơ hợp lệ và account sở hữu ít nhất một xe active.
- Profile bổ sung `dateOfBirth`, `registrationFlowVersion`, `onboardingCompletedAt` và trạng thái Shelly `connected|skipped`; các mốc hoàn tất do backend ghi.
- Preference đồng bộ tại `users/{uid}/appPreferences/ui`:
  - `dashboardOrder`
  - `hiddenDashboardWidgets`
  - `completedTours`
  - `guideSchemaVersion`
  - `updatedAt`
- Firestore Rules chỉ cho chủ account đọc/ghi preference đúng schema và giới hạn số phần tử; account disabled không được truy cập.
- Siết endpoint sync profile hiện tại bằng whitelist để client không thể gửi `accountStatus`, role, quota hoặc giả trạng thái onboarding.
- Tài khoản cũ thiếu preference sử dụng bố cục mặc định; tài khoản cũ thiếu onboarding marker tiếp tục vào app bình thường.

## Kiểm thử và nghiệm thu

- Unit test:
  - Chuẩn hóa bố cục, widget mới/cũ, ẩn/hiện, reorder, reset và giải quyết xung đột.
  - Tính tuổi từ ngày sinh, validation ngày sinh và onboarding state machine.
  - Guide registry, tiến độ tour và locale fallback.
- Widget test tại 320, 360, 393 và 412 dp; text scale 1.0–2.0; Dark/AMOLED/Light; không overflow khi reorder hoặc hiển thị coach mark.
- Integration test:
  1. Đăng ký account mới.
  2. Nhập họ tên, ngày sinh và điện thoại.
  3. Không thể hoàn tất khi chưa chọn xe.
  4. Chọn xe catalog và tạo xe đúng defaults.
  5. Bỏ qua hoặc kết nối Shelly.
  6. Hoàn tất onboarding và chạy tour.
  7. Đổi thứ tự/ẩn widget, đăng nhập thiết bị khác và nhận đúng bố cục.
  8. Offline vẫn dùng bố cục cache và đồng bộ lại khi có mạng.
- Security test xác nhận không thể sửa role/status/quota/onboarding completion, không lộ Shelly credential và giới hạn hai xe vẫn được backend thực thi.
- Chạy `flutter analyze`, toàn bộ Flutter/backend/rules tests, Android debug/release build và iOS unsigned build.

## Giả định đã chốt

- “Dashboard” là màn `Tổng quan` chính; dashboard phân tích Battery Health giữ nguyên.
- Người dùng được ẩn và sắp xếp widget, không thay dữ liệu hoặc đổi kích thước widget.
- Bố cục và tiến độ hướng dẫn được đồng bộ theo account, không theo từng xe.
- Họ tên và ít nhất một xe là bắt buộc; điện thoại, ngày sinh và Shelly có thể bỏ qua.
- Ngày sinh đầy đủ được lưu theo lựa chọn của người dùng, kèm giải thích quyền riêng tư.
- Tour và thư viện bao phủ toàn bộ chức năng dành cho người dùng, không bao gồm công cụ Developer Mode.
