import 'app_error_formatter.dart';

/// Compatibility adapter. No exception or arbitrary short string is trusted.
/// Authored UI copy belongs to [AppNoticeCopy], not this service-error mapper.
class UserFriendlyErrorMapper {
  UserFriendlyErrorMapper._();

  static String map(Object? error) => AppErrorFormatter.format(error);
}

/// A narrow compatibility boundary for existing string-based notice callers.
///
/// Only exact reviewed copy and fully anchored numeric templates may be shown.
/// A server-supplied `source`, short string or Vietnamese sentence is NOT proof
/// that its contents are safe. New authored messages must be reviewed here;
/// external errors should use AppErrorFormatter's fixed code mapping.
class AppNoticeCopy {
  AppNoticeCopy._();

  static const safetyFallback =
      'Chưa xác minh được trạng thái an toàn. Hãy kiểm tra bộ sạc trực tiếp; '
      'không coi ổ cắm đã tắt cho đến khi được xác nhận.';

  static final _approved = <String>{
    AppErrorFormatter.fallback,
    for (final code in [
      'invalid-credential',
      'email-already-in-use',
      'weak-password',
      'invalid-email',
      'too-many-requests',
      'unauthenticated',
      'permission-denied',
      'failed-precondition',
      'handshakeexception',
      'device_offline',
      'timeoutexception',
      'socketexception',
      'unavailable',
      'not-found',
    ])
      AppErrorFormatter.format(code),
    'Thao tác chưa hoàn tất',
    'Cảnh báo an toàn sạc',
    'Đang có phiên sạc trực tiếp',
    'Hãy Tắt Sạc và xác minh relay OFF trước khi đổi cấu hình.',
    'Ổ sạc chưa sẵn sàng điều khiển an toàn.',
    'Không thể bật sạc',
    'Không thể bật sạc: Chưa xác nhận được ổ sạc bật.',
    'Không thể bật sạc. Hãy kiểm tra kết nối và thử lại.',
    'Chưa xác nhận được ổ sạc đã tắt',
    'Chưa xác nhận được ổ sạc đã tắt. Hãy kiểm tra ổ sạc.',
    'Hãy kiểm tra ổ sạc trực tiếp.',
    'Chưa xác minh được Shelly trên thiết bị này; chỉ xem trạng thái đồng bộ.',
    'Thời gian sạc vượt giới hạn an toàn 10 giờ. Vui lòng chọn mức pin thấp hơn.',
    'Model AI chưa sẵn sàng. Không thể bắt đầu sạc theo AI.',
    'Không thể tính thời gian sạc. Hãy thử lại.',
    'Relay không được đánh dấu an toàn. Kiểm tra tải điện và trạng thái OFF.',
    'Test relay thất bại',
    'Relay đã test và được xác minh',
    'Safe Boot, ON không tải 5 giây và OFF/readback đạt. Đã mở khóa điều khiển an toàn.',
    'Đã bắt đầu sạc',
    'Đang sạc',
    'Đã tắt sạc',
    'Chưa hỗ trợ khởi động lại từ màn hình này. Không có lệnh nào được gửi đến Shelly.',
    'Hãy lưu cấu hình đang sửa trước khi đổi xe.',
    'Kiểm tra thất bại',
    'Kiểm tra kết nối và thử lại.',
    'Không tìm thấy thiết bị Shelly',
    'Không tìm thấy thiết bị đã cấu hình',
    'Shelly Cloud: Không tìm thấy thiết bị',
    'Vui lòng kiểm tra lại Auth Key và Device ID.',
    'Shelly Cloud: ONLINE!',
    'Shelly Cloud: OFFLINE',
    'Thiết bị có bảo mật LAN',
    'Vui lòng nhập mật khẩu local của Shelly để hoàn tất kết nối.',
    'Chưa nhập địa chỉ IP LAN',
    'Cần nhập Device ID và Cloud Auth Key',
    'Hãy kiểm tra điện thoại đã kết nối cùng mạng Wi-Fi với Shelly.',
    'Quét dải IP thất bại',
    'Không thể kết nối IP LAN',
    'Lỗi kiểm tra Shelly Cloud',
    'Kết nối LAN thành công!',
    'Đã nhận diện mã thiết bị',
    'Chạm vào thiết bị từ danh sách bên dưới để tự động điền cấu hình.',
    'Kiểm tra hoàn tất & Đã lưu cấu hình',
    'Đã lưu trên máy; sao lưu server thất bại. Chưa xác minh Safe Boot/test relay.',
    'Đã kiểm tra kết nối và lưu trên máy. Chưa xác minh Safe Boot/test relay.',
    'Không thể thu hồi cấu hình server',
    'Đã thu hồi cấu hình Shelly',
    'Đã xóa cấu hình khỏi điện thoại',
    'Giá điện chưa hợp lệ',
    'Đã xóa giá điện',
    'Đã lưu giá điện',
    'Chi phí sẽ không được ước tính.',
    'Không thể lưu giá điện',
    'Công suất sạc chưa hợp lệ',
    'Đã lưu công suất sạc',
    'Không thể lưu công suất sạc',
    'Đã bật sao lưu mã hóa',
    'Đã tắt sao lưu',
    'Thông báo chưa được bật',
    'Bạn có thể cho phép thông báo trong phần Cài đặt của thiết bị.',
    'Hãy chọn xe trước khi bật AI cá nhân',
    'Hãy chọn xe trước khi xem dữ liệu fine-tune',
    'Đã mở Developer Mode',
    'Đã bật AI cá nhân',
    'Đã tắt AI cá nhân',
    'Đã xóa dữ liệu AI cá nhân',
    'Không thể cập nhật AI cá nhân',
    'Không thể xóa dữ liệu',
    'Không thể lưu dữ liệu fine-tune',
    'Đã lưu override fine-tune',
    'Giá trị override phải là số hợp lệ',
    'Đã sao chép JSON',
    'Đã sao chép đường dẫn Firestore',
    'Đã cập nhật thông tin',
    'Đã cập nhật thông số',
    'Mật khẩu mới tối thiểu 6 ký tự',
    'Đổi mật khẩu thành công',
    'Đổi mật khẩu thất bại',
    'Đăng xuất thất bại',
    'Đăng ký thành công!',
    'Đã khôi phục xe',
    'Đã lưu trữ xe',
    'Khôi phục thất bại',
    'Lưu trữ thất bại',
    'Thêm xe thất bại',
    'Cập nhật thất bại',
    'Không tải được danh sách xe. Vui lòng thử lại.',
    'Không tải được danh sách xe',
    'Không thể lưu hồ sơ.',
    'Họ tên là bắt buộc để tiếp tục.',
    'Vui lòng chọn ít nhất một xe từ danh mục.',
    'Số ODO ban đầu không hợp lệ.',
    'Không thể tạo xe. Vui lòng thử lại.',
    'Chưa hoàn tất được onboarding.',
    'Cần cập nhật thông tin onboarding',
    'Đang chờ đồng bộ onboarding',
    'Không thể hoàn tất.',
    'Định dạng ngày sinh phải là dd/mm/yyyy',
    'Ngày sinh không thể ở tương lai',
    'Người dùng phải từ đủ 16 tuổi trở lên',
    'Tuổi không hợp lệ (vượt quá 120 tuổi)',
    'Khoảng thời gian quá dài',
    'Mỗi lần xem hoặc xuất báo cáo tối đa 12 tháng.',
    'Đã tạo báo cáo',
    'Không thể xuất báo cáo',
    'Không thể ẩn phiên',
    'Đang xem bộ đệm. Cần kết nối máy chủ để sửa dữ liệu.',
    'Cần kết nối máy chủ để thêm mẫu.',
    'Máy chủ đã ghi nhận cập nhật dataset.',
    'Chưa lưu được thay đổi. Dữ liệu máy chủ chưa được cập nhật; hãy thử lại.',
    'Máy chủ đã ghi nhận mẫu thử nghiệm (loại khỏi huấn luyện).',
    'Chưa thêm được mẫu trên máy chủ. Hãy thử lại.',
    'Fine-tune thất bại. Không có kết quả mới được ghi nhận.',
    'Máy chủ đã hoàn tất fine-tune.',
    'Không nhận được kết quả fine-tune từ máy chủ.',
    'Đang kiểm tra máy chủ...',
    'Không thấy phản hồi từ cổng sạc. Vui lòng kiểm tra server.',
  };

  // Numbers only, with a small bounded length: no arbitrary names/IDs/URLs.
  static final _numericCopy = <RegExp>[
    RegExp(r'^Dòng điện đang cao \(\d{1,3}\.\d A\)\.$'),
    RegExp(r'^Công suất đang gần giới hạn \(\d{1,6} W\)\.$'),
    RegExp(r'^Nhiệt độ Shelly đang cao \(\d{1,3}\.\d °C\)\.$'),
    RegExp(r'^Điện áp đang ngoài vùng khuyến nghị \(\d{1,4}\.\d V\)\.$'),
    RegExp(r'^Tự động tắt lúc \d{2}:\d{2}$'),
    RegExp(r'^Hẹn giờ \d{1,2} (?:giờ|phút)(?: \d{1,2} phút)?\.$'),
    RegExp(r'^Shelly sẽ tự ngắt sau \d{1,2} (?:giờ|phút)(?: \d{1,2} phút)?\.$'),
    RegExp(r'^\d{1,5} phiên · đã mở bảng chia sẻ Android\.$'),
    RegExp(r'^Chạm thêm [1-9] lần để mở Developer Mode$'),
    RegExp(r'^Đã tìm thấy \d{1,3} thiết bị Shelly$'),
  ];

  /// Null means the incoming string has no approved user-facing copy.
  static String? approved(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    if (_approved.contains(text) ||
        _numericCopy.any((pattern) => pattern.hasMatch(text))) {
      return text;
    }
    // Two legacy English safety outcomes are translated, never passed through.
    if (text == 'Charging stop failed. Check charger status.') {
      return 'Chưa xác nhận được ổ sạc đã tắt. Hãy kiểm tra ổ sạc.';
    }
    if (text == 'Charging start failed. Check connection and retry.') {
      return 'Không thể bật sạc. Hãy kiểm tra kết nối và thử lại.';
    }
    return null;
  }

  static String error(Object? value) =>
      approved(value) ?? UserFriendlyErrorMapper.map(value);

  /// Reduces changing numeric telemetry to the same reviewed failure category.
  static String category(String text) =>
      text.replaceAll(RegExp(r'\d+(?:\.\d+)?'), '#');

  static String actionLabel(String value) =>
      const {
        'MỞ',
        'CHI TIẾT',
        'MỞ CÀI ĐẶT',
        'THỬ LẠI',
        'Mở',
        'Chi tiết',
        'Mở cài đặt',
        'Thử lại',
      }.contains(value)
      ? value
      : 'Mở';
}
