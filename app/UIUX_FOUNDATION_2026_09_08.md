# UI/UX — đợt nền tảng 08/09/2026

## Lựa chọn đã chốt

- Ưu tiên Flutter app, hoàn thiện web sau.
- Hỗ trợ sáng, tối và theo hệ thống; giữ AMOLED.
- Nút thao tác tối thiểu 48dp, icon 48×48dp; ON/OFF lớn hơn.
- Chiều cao được phép tăng khi chữ lớn hoặc nhãn xuống dòng để tránh cắt chữ.

## Đã triển khai trong đợt này

- Sửa SettingsService trước đây lưu `light`/`system` thành `dark` và MaterialApp ép ThemeMode.dark.
- Theme chung cho Filled/Elevated/Outlined/Text/IconButton; điểm nhấn xanh ở cả light/dark.
- Thêm lựa chọn sáng/hệ thống ở hai điểm cài đặt giao diện; màn Giao diện & Ngôn ngữ dùng màu theo Theme.
- Splash có thương hiệu, thông báo khởi tạo thật, entrance ngắn, không thêm timer trì hoãn; chữ lớn cuộn được và giảm chuyển động không chạy progress animation.
- Nút bật sạc hẹn giờ có hiệu ứng nhấn, giữ glow nhẹ, dừng controller khi disabled/reduced-motion; khóa gửi lặp khi chờ callback, xử lý callback lỗi và khôi phục thao tác.
- Chi tiết phiên: nhóm chỉ số co giãn theo chiều rộng thực tế/chữ lớn; trạng thái phân biệt đầy đủ vòng đời; lỗi telemetry có Thử lại, xóa lỗi khi phục hồi, tránh polling chồng nhau.

## Kiểm chứng

- `flutter test --no-pub test/widget/design_foundation_test.dart test/widget/app_motion_test.dart test/widget/responsive_cards_test.dart`: 28 tests đạt.
- Phân tích tĩnh các file nền tảng và chi tiết phiên: không có lỗi biên dịch; hai lint nhỏ đã được sửa sau lần chạy đầu.
- `git diff --check`: đạt (Git có cảnh báo LF/CRLF).
- Không gửi lệnh Shelly thật, không thay đổi Firebase credential, không deploy hay build APK trong đợt này.

## Còn phải làm — chưa phải hoàn tất toàn bộ yêu cầu

- Chuyển các màn còn hardcode AppColors/CockpitColors sang palette theo context. ThemeMode hoạt động nhưng chưa đồng nghĩa toàn app đã có giao diện sáng hoàn chỉnh.
- Rà soát style override và control tự viết trên mọi màn; theme chung chưa bảo đảm tất cả nút/nav hiện hữu đều đúng 48dp.
- Hoàn thiện hiệu ứng nút TẮT ở trạng thái đang sạc; hiện đợt này chỉ cập nhật nút BẬT hẹn giờ.
- Thiết kế lại đầy đủ dashboard, Smart Charger, Developer AI Studio và phần chi tiết phiên; giữ nguyên ý nghĩa dữ liệu thật/ước tính.
- Kiểm thử trực quan trên Android, cả hai theme, màn nhỏ, chữ lớn; kiểm tra contrast, focus, hiệu năng và cold-start native splash.
- Hoàn thiện và kiểm thử trình duyệt cho web sau app. Các chỉnh sửa web từ đợt trước vẫn được giữ nguyên, chưa xác nhận đã hoàn tất.
