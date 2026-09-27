/// Maps untrusted service errors to fixed, user-facing copy.
/// Even a short exception can contain a key, UID or internal hostname.
class AppErrorFormatter {
  AppErrorFormatter._();

  static const fallback = 'Chưa thể thực hiện thao tác. Vui lòng thử lại.';

  static String format(Object? error) {
    if (error == null) return fallback;
    final message = error.toString().toLowerCase();
    bool hasAny(List<String> codes) => codes.any(message.contains);

    if (hasAny(['invalid-credential', 'wrong-password', 'user-not-found'])) {
      return 'Email hoặc mật khẩu không chính xác.';
    }
    if (message.contains('email-already-in-use')) {
      return 'Email này đã được đăng ký. Bạn có thể đăng nhập hoặc đặt lại mật khẩu.';
    }
    if (message.contains('weak-password')) {
      return 'Mật khẩu chưa đủ mạnh. Vui lòng chọn mật khẩu khác.';
    }
    if (message.contains('invalid-email')) {
      return 'Email chưa đúng định dạng. Vui lòng kiểm tra lại.';
    }
    if (hasAny(['too-many-requests', 'resource-exhausted', 'rate_limit'])) {
      return 'Có quá nhiều yêu cầu. Vui lòng đợi một lát rồi thử lại.';
    }
    if (hasAny([
      'requires-recent-login',
      'unauthenticated',
      'user-token-expired',
    ])) {
      return 'Vui lòng đăng nhập lại để tiếp tục.';
    }
    if (hasAny(['permission-denied', 'permission_denied'])) {
      return 'Chưa thể truy cập dữ liệu. Vui lòng thử lại hoặc liên hệ hỗ trợ.';
    }
    if (hasAny([
      'failed-precondition',
      'failed_precondition',
      'requires an index',
      'indexes?create_composite',
    ])) {
      return 'Dữ liệu tạm chưa khả dụng. Vui lòng thử lại hoặc liên hệ hỗ trợ.';
    }
    if (hasAny(['handshakeexception', 'certificate_verify_failed'])) {
      return 'Chưa thể kết nối bảo mật. Vui lòng thử lại sau.';
    }
    if (hasAny([
      'shellyclientexception',
      'device_offline',
      'charger_offline',
    ])) {
      return 'Chưa thể đọc trạng thái bộ sạc. Kiểm tra kết nối và thử lại.';
    }
    if (hasAny(['timeoutexception', 'deadline-exceeded', 'timed out'])) {
      return 'Chưa nhận được phản hồi. Vui lòng kiểm tra kết nối và thử lại.';
    }
    if (hasAny([
      'socketexception',
      'network-request-failed',
      'network is unreachable',
      'failed host lookup',
      'connection refused',
    ])) {
      return 'Chưa thể kết nối dịch vụ. Vui lòng kiểm tra mạng và thử lại.';
    }
    if (message.contains('unavailable')) {
      return 'Dịch vụ tạm chưa khả dụng. Vui lòng thử lại sau.';
    }
    if (hasAny(['not-found', 'not_found'])) {
      return 'Không tìm thấy dữ liệu cần hiển thị.';
    }
    return fallback;
  }
}
