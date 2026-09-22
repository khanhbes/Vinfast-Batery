# Rà soát và hoàn thiện UI/UX toàn bộ Flutter app

## 1. Mục tiêu và nguyên tắc thiết kế

Đánh giá từng màn hình, thành phần và trạng thái tương tác; sửa lỗi trước, sau đó tinh gọn bố cục và thống nhất hiệu ứng.

Hướng thiết kế đã chốt:

- Giữ bốn tab **Tổng quan – Sạc – Lịch sử – Khác** và các chức năng hiện có.
- Giữ màu nhấn xanh emerald; hỗ trợ sáng, tối, theo hệ thống và AMOLED.
- Ưu tiên trạng thái hiện tại, thông tin quan trọng và hành động tiếp theo; chuyển nội dung kỹ thuật xuống phần mở rộng.
- Các màn thông thường chuyển động nhẹ; màn sạc nổi bật hơn nhưng không gây hiểu nhầm trạng thái thiết bị.
- Không xây lại hệ thống theme/motion đã có. Mở rộng và thống nhất cách sử dụng chúng.

Phạm vi đợt này là app. Không triển khai web, đổi backend, xoay vòng credential hoặc điều khiển thiết bị thật.

## 2. Kiểm kê và đánh giá có bằng chứng

### Bao phủ toàn bộ giao diện

Lập danh mục từ mã nguồn và đường điều hướng thực tế, bao gồm:

| Nhóm | Nội dung cần kiểm tra |
|---|---|
| Khởi động và tài khoản | Splash, đăng nhập, đăng ký, phục hồi phiên, đăng xuất |
| Điều hướng | Bốn tab, AppBar, chọn xe, thông báo, nút nổi, Back, liên kết thông báo |
| Tổng quan và phân tích | Home, dashboard phân tích riêng, pin, quãng đường, biểu đồ, hành động nhanh |
| Sạc | Chọn chế độ, SOC, hẹn giờ, dự đoán, xác nhận ON/OFF, kết nối, phiên đang chạy |
| Lịch sử | Danh sách, bộ lọc, chi tiết phiên, biểu đồ, xác nhận SOC, sửa/xóa |
| Cài đặt | Tài khoản, giao diện, garage, thông số xe, trợ giúp, cập nhật APK |
| Smart Charger | Thiết lập, khám phá thiết bị, QR, kết nối, xác minh, lưu và thông báo lỗi |
| AI | Dự đoán, danh sách model, Personal AI, dữ liệu huấn luyện, Developer AI Studio |
| Chức năng bổ trợ | Nhật ký sạc, nhập chuyến đi, lập hành trình, bản đồ, thống kê, bảo dưỡng |

Mỗi màn phải bao gồm các dialog, bottom sheet, menu, trường nhập và thành phần dùng chung. Phân biệt màn đang được sử dụng với mã giao diện không còn đường truy cập; không tự xóa chỉ vì tìm kiếm chưa thấy tham chiếu.

### Hồ sơ từng vấn đề

Mỗi phát hiện ghi:

- Mã lỗi, màn/widget và vị trí mã nguồn.
- Điều kiện tái hiện: dữ liệu, kích thước, theme, cỡ chữ, thao tác.
- Kết quả thực tế, kết quả mong đợi và ảnh/video nếu đã chạy được.
- Ảnh hưởng tới người dùng, mức P0–P3.
- Phương án sửa, kiểm thử hồi quy và kết quả sau sửa.
- Nhãn **đã xác nhận / nghi vấn / chưa kiểm chứng**.

Ưu tiên P0/P1 cho thông tin sạc gây hiểu nhầm, thao tác quan trọng bị che hoặc không dùng được; P2 cho bố cục, trợ năng và tính nhất quán; P3 cho chi tiết thẩm mỹ. Không biến sở thích thiết kế thành lỗi chức năng.

## 3. Các thay đổi sẽ thực hiện

### Nền tảng giao diện

- Chuẩn hóa màu theo vai trò: nền, bề mặt, chữ, viền, hành động, cảnh báo, lỗi. Chuyển các màn còn màu tối cố định sang theme thích ứng.
- Dùng thống nhất kiểu chữ hiện có; quy định cấp tiêu đề, nội dung, chú thích và số liệu. Không thu nhỏ chữ hoặc khóa text scale để che lỗi.
- Chuẩn hóa khoảng cách theo thang 4/8/12/16/24/32dp; bỏ viền, bóng và card lồng nhau không có tác dụng.
- Nút thao tác tối thiểu 48dp; nút icon vùng chạm 48×48dp; ON/OFF tối thiểu 56dp. Chiều cao được tăng khi chữ lớn.
- Các nút ngang hàng có kích thước đồng đều; không ép mọi nút toàn app cùng chiều rộng.
- Đồng nhất trạng thái nhấn, focus, disabled, loading và lỗi; bổ sung tooltip/semantics cho nút chỉ có icon.

### Bố cục và nội dung

- **Tổng quan:** ưu tiên xe đang chọn → SOC và độ mới dữ liệu → phiên sạc/chuyến đi đang hoạt động → dự đoán quãng đường → thao tác nhanh → lịch sử ngắn. Không lặp KPI trong nhiều card.
- **Dashboard phân tích:** giữ dữ liệu chuyên sâu, bộ lọc thời gian và giải thích biểu đồ; tránh trở thành bản sao Tổng quan.
- **Chi tiết phiên sạc:** chia thành tóm tắt trạng thái, SOC, thời gian–năng lượng–chi phí, biểu đồ, thông tin kỹ thuật. Phân biệt SOC mục tiêu, ước tính và xác nhận.
- **Cài đặt:** nhóm tài khoản, xe, sạc, AI, giao diện và hỗ trợ; mô tả ngắn bằng tiếng Việt, tên gọi thống nhất.
- **Smart Charger:** bố cục theo trình tự chọn phương thức → cấu hình → kiểm tra → lưu; trạng thái kết nối và bước còn thiếu hiển thị rõ.
- **Developer AI Studio:** tách cấu hình kết nối, dữ liệu, huấn luyện và kết quả/model; đưa log và thông tin kỹ thuật vào phần mở rộng. Nút không khả dụng phải giải thích lý do.
- **Form và sheet:** lỗi tại trường nhập, giữ dữ liệu khi lỗi mạng, bàn phím không che hành động, không đóng hộp thoại khi validation thất bại.
- Dùng W và Wh làm đơn vị mặc định; phân biệt nhập tay, Shelly, AI và công thức dự phòng. Không tự tạo confidence, số liệu hoặc thông báo thành công.

### Hiệu ứng

- Dùng chung token `AppMotion`: phản hồi nhấn khoảng 180ms, chuyển trạng thái 260ms, chuyển màn tối đa 380ms.
- Splash phản ánh khởi tạo thật, không thêm thời gian chờ chỉ để trình diễn.
- Màn sạc có một hiệu ứng năng lượng chính, chu kỳ nhẹ khoảng 2–3 giây; chỉ chạy khi dữ liệu xác nhận đang sạc và còn hợp lệ.
- Phân biệt rõ **đang gửi lệnh → chờ xác nhận → đã xác nhận / thất bại / chưa xác định**. Không phát hiệu ứng thành công ngay khi người dùng nhấn.
- Dừng hiệu ứng lặp khi rời màn, app vào nền, bật giảm chuyển động hoặc mất xác nhận trạng thái. Trạng thái chữ vẫn phải đầy đủ.
- Không phát lại animation toàn màn sau mỗi lần polling; không trì hoãn lệnh OFF vì animation.
- Kiểm tra controller, subscription, haptic và rebuild; cô lập vùng animation khi đo đạc cho thấy cần thiết.

### Interface và tương thích

Không thay API, schema telemetry, dữ liệu lưu hay quy tắc điều khiển sạc trong đợt UI này. Component dùng chung nhận rõ trạng thái loading, enabled, lỗi và nguồn dữ liệu từ state hiện có; không tự suy đoán trạng thái thiết bị bên trong widget.

Nếu phát hiện thiếu dữ liệu phía backend khiến UI không thể trình bày đúng, ghi thành blocker riêng thay vì giả lập thông tin.

## 4. Kiểm thử và tiêu chí nghiệm thu

### Ma trận bắt buộc

- Điện thoại: 320×568, 360×640, 375×812, 412×915; thêm xoay ngang.
- Tablet: 800×1280 và 1280×800.
- Text scale: 1.0, 1.15, 1.3, 1.5 và 2.0.
- Sáng/tối cho mọi màn; kiểm tra bổ sung AMOLED và thay đổi theme hệ thống.
- Trạng thái: khởi tạo, tải, thành công, rỗng, lỗi, offline, dữ liệu cũ, thiếu một phần, thiếu quyền, hết phiên đăng nhập.
- Dữ liệu biên: tên xe dài, ID dài, số lớn, thiếu giá trị, tiếng Việt có dấu và nhãn tiếng Anh đang được hỗ trợ.

### Kiểm thử tự động

- Chạy baseline `flutter analyze` và bộ test hiện có; phân biệt lỗi cũ với lỗi phát sinh.
- Bổ sung widget test cho overflow, kích thước vùng chạm, semantics, form/keyboard và reduced motion.
- Golden test cho các màn chính và trạng thái dễ vỡ; cố định font, thời gian và dữ liệu kiểm thử.
- Kiểm thử nhấn nhanh nhiều lần, đổi xe khi request đang chạy, đóng sheet giữa request, Back, phục hồi scroll và trạng thái tab.
- Dùng gateway/API giả lập; không bật relay, huấn luyện model hay xóa dữ liệu thật.

### Kiểm chứng Android

- Kiểm tra TalkBack, bàn phím, safe area, điều hướng cử chỉ/ba nút và chuyển nền–trở lại.
- Profile luồng cuộn dashboard, biểu đồ, mở sheet và màn sạc đang cập nhật; ghi build/raster frame time, tỷ lệ khung hình chậm và thiết bị đo.
- Đánh giá theo ngân sách khung hình của thiết bị; không kết luận “mượt” từ debug mode hoặc widget test.

Nghiệm thu khi không còn P0/P1 chưa xử lý; không có overflow hoặc hành động bị che trong ma trận đã chạy; thông tin sạc/AI không gây hiểu nhầm; test hồi quy đạt và không phát sinh lỗi phân tích tĩnh mới. P2/P3 còn lại phải có lý do và phạm vi ảnh hưởng rõ ràng.

## 5. Trình tự và báo cáo bàn giao

Thực hiện theo thứ tự:

1. Kiểm kê, baseline và tái hiện lỗi.
2. Theme, typography, nút, điều hướng và component dùng chung.
3. Tổng quan, Smart Charge và chi tiết phiên.
4. Cài đặt, Smart Charger và AI Studio.
5. Các màn còn lại, trợ năng và hiệu năng.
6. Chạy lại kiểm thử và tổng kết.

Cập nhật báo cáo QA app thành nguồn tổng hợp chính: bảng bao phủ từng màn, danh sách lỗi chi tiết, ảnh trước/sau, thay đổi thiết kế, kết quả test và vấn đề tồn đọng. Dùng checklist UI/UX trong tài liệu master audit hiện có để đối chiếu.

Hiện chưa có Android kết nối, nên kết quả TalkBack và hiệu năng thiết bị sẽ được đánh dấu **chưa kiểm chứng** đến khi có thiết bị phù hợp. Giữ nguyên bốn file đang sửa dở, credential và dữ liệu runtime; không ghi đè thay đổi hiện hữu hoặc tuyên bố hoàn tất toàn app chỉ dựa trên kiểm tra mã nguồn.
