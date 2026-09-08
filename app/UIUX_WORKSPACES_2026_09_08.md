# UI/UX — Smart Charger, AI Studio và dashboard

## Bổ sung: lịch sử và chi tiết phiên sạc

- Lịch sử/chi tiết dùng màu theo theme; các panel có tùy chọn adaptive riêng, không đổi màu các màn Smart Charge chưa được chuyển đổi.
- Tách SOC bắt đầu, SOC ước tính/xác nhận và mục tiêu. Không còn dùng targetSoc thay cho SOC cuối khi thiếu dữ liệu. Loại bỏ giá trị không hữu hạn hoặc ngoài 0–100 khỏi phần tóm tắt.
- Phần kỹ thuật thêm mã phiên, mã xe, model, nguồn, confidence và thời điểm cập nhật. Màn nhỏ xếp nhãn trên giá trị; giá trị có thể chọn/sao chép.
- Hộp nhập SOC giữ mở khi nhập sai, báo lỗi tại trường nhập, nhận dấu phẩy thập phân; controller được dispose theo vòng đời dialog.
- Kiểm chứng: 12 tests đạt (7 widget tests cho SOC/dialog/metadata, 5 unit tests năng lượng); phân tích tĩnh các file đợt này sạch; git diff --check đạt.
- Chưa kiểm thử end-to-end biểu đồ, tải telemetry và các thao tác sửa/xóa phiên trên server/thiết bị thật. Chưa build APK hoặc deploy web. Các màn Smart Charge khác vẫn cần tiếp tục kiểm tra.

## Bổ sung: bảng chọn xe

- Đã chạy xác nhận lại nhóm navigation/settings/motion: 23 tests đạt, gồm test thao tác trợ năng sau khi sửa việc dọn SemanticsHandle trong test.
- Nút đổi xe dùng TextButton có vùng chạm tối thiểu 48dp và tooltip tên xe đầy đủ; hỗ trợ focus/keyboard thay cho GestureDetector đơn thuần.
- Bảng chọn xe dùng palette sáng/tối và AppReveal ngắn, bỏ controller nhấp nháy lặp. Thông số bố trí theo độ rộng và cỡ chữ.
- Lọc xe lưu trữ giống thanh chọn xe. Dung lượng hiển thị Wh; phân biệt quãng đường công bố/cấu hình. Không mặc định loại pin LFP từ tên xe, không hiển thị giá trị cấu hình thiếu như dữ liệu thật.
- Khi chọn xe: chờ lưu phiên rồi cập nhật provider; khóa thao tác lặp trong lúc lưu. Khi lỗi có thông báo, không âm thầm đóng bảng.
- 5 widget tests chọn xe đạt ở 320dp, sáng/tối, text scale 1/2, lọc xe lưu trữ, đơn vị Wh và mở sheet. Phân tích tĩnh hai file chọn xe sạch. Chưa xác minh lưu phiên trên thiết bị thật hoặc tương tác với một phiên sạc thật đang hoạt động.
- Phạm vi chưa hoàn tất: các widget Smart Charge còn màu tối cố định, màn phân tích riêng, kiểm tra chi tiết phiên đầy đủ và phần web.

## Bổ sung: thanh điều hướng và cài đặt

- Thanh điều hướng được tách thành `AppNavigationBar`: bốn ô rộng/cao bằng nhau, nhãn được xuống dòng khi chữ lớn, giữ trạng thái chọn và animation 180ms; giảm chuyển động tắt hiệu ứng.
- Nền thanh điều hướng, app bar, thông báo và màu icon hệ thống theo theme. Giữ nguyên cơ chế chọn tab, khôi phục xe và AppTabStack; không thay routing.
- Màn Cài đặt cùng các nhóm, tiêu đề, hàng chức năng và hộp thoại dùng palette sáng/tối. Công tắc tự vẽ được thay bằng Switch.adaptive; mô tả hàng không còn bị cắt sau hai dòng.
- Nút điều hướng có semantics chọn/tab và hành động tap cho trình đọc màn hình.
- Phân tích tĩnh các file navigation/settings/shared rows: không có vấn đề. Có kiểm thử riêng cho kích thước bằng nhau, chữ lớn và thao tác trợ năng. Các màn Smart Charge khác, bộ chọn xe và web vẫn cần tiếp tục rà soát; chưa kiểm thử trực quan trên Android thật.

## Thay đổi

- Thêm palette `AppUiColors` theo Theme: nền, chữ, primary, cảnh báo, lỗi. Smart Charger và AI Studio không còn ép các màu nền tối cũ; các hộp thoại và input đi theo cùng palette.
- Giữ bố cục chức năng hiện hữu, ưu tiên tương phản và thứ bậc thông tin thay vì thêm hiệu ứng trang trí. Không thay API, credential hay cấu hình charger.
- Nút quay lại Smart Charger dùng IconButton có tooltip. Nút lưu dataset không còn bị ép chiều cao 48 khi chữ lớn; shortcut URL có vùng chạm tối thiểu 48dp.
- Nút ngắt nguồn dùng `PowerActionButton`: tối thiểu 56dp, tự tăng chiều cao theo nhãn, hiệu ứng nhấn 160ms, hỗ trợ giảm chuyển động, khóa khi controller đang dừng. Lệnh không chờ animation.
- Dashboard Home dùng palette theo theme. Bỏ hai mục “Hiệu suất lái xe”/“Thành tích lái xe” từng suy ra từ SoH; thay bằng thông số cấu hình km / 1% pin, không gọi đó là dữ liệu đo thực tế.
- Thẻ dự đoán quãng đường đổi sang bố cục Wrap cho chữ lớn, chuyển động chung AppReveal. Phân biệt máy chủ AI với công thức dự phòng; không tự gán confidence 72% hoặc khoảng dự đoán khi offline. Hiển thị độ tin cậy 0% đúng giá trị thay vì bỏ qua.
- Thẻ quãng đường kiểm tra số hữu hạn và khoảng dự đoán, xử lý lỗi API, có Thử lại. Thay xe/thay hiệu suất kích hoạt tính lại; response cũ không được ghi đè xe mới.

## Kiểm thử

Chạy các nhóm widget test: `settings_studio_layout_test`, `home_layout_test`, `range_prediction_layout_test`, `power_action_button_test`, `design_foundation_test`.

Tổng 26 test đạt: sáng/tối, màn 320dp, text scale 1/2, trạng thái offline, chống response cũ, nút ngắt nguồn disabled/reduced motion và nền tảng theme/nút.

`git diff --check` đạt. Phân tích tĩnh các file đợt này không có compile error; Home còn 4 cảnh báo unused và 6 thông báo underscore trong mã cũ. Smart Charge control còn các helper/view cũ không được dùng, chưa dọn trong đợt này.

## Giới hạn và việc tiếp theo

- Chưa kiểm chứng trực quan/FPS trên Android thật hoặc build APK. Các bài test dùng dữ liệu giả, không kích hoạt relay hoặc training thật.
- Smart Charger đã đổi palette nhưng chưa có kiểm thử tương tác đầy đủ trên thiết bị; cần kiểm tra từng tab/hộp thoại với cấu hình thực.
- Chưa hoàn tất toàn app: thanh điều hướng, một số màn cài đặt và các widget Smart Charge khác vẫn dùng palette tối cố định. Không tuyên bố toàn app đã hỗ trợ light mode hoàn chỉnh.
- Chưa hoàn tất thiết kế lại toàn bộ chi tiết phiên hay dashboard phân tích riêng (`features/dashboard`). Đợt này tập trung Home overview và các lỗi nội dung được phát hiện tại đó.
- Các chỉnh sửa web trước đây được giữ nguyên; chưa deploy hoặc hoàn tất browser QA trong đợt này.
