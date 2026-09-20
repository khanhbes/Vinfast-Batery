import 'dart:async';
import 'dart:io';

/// Chuyển đổi các lỗi hệ thống / backend thô thành thông điệp thân thiện
/// với người dùng, ẩn các chi tiết kỹ thuật nhạy cảm (Firestore, timeouts, stacktraces).
class UserFriendlyErrorMapper {
  UserFriendlyErrorMapper._();

  static String map(dynamic error) {
    if (error == null) return 'Đã xảy ra lỗi không xác định. Vui lòng thử lại.';

    final str = error.toString();

    // Lỗi Timeout / Mất kết nối Firestore
    if (error is TimeoutException ||
        str.contains('TimeoutException') ||
        str.contains('Firestore (8s)') ||
        str.contains('timed out')) {
      return 'Không thể kết nối máy chủ (quá thời gian chờ). Vui lòng kiểm tra mạng và thử lại.';
    }

    // Lỗi mạng không có Internet
    if (error is SocketException ||
        str.contains('SocketException') ||
        str.contains('Failed host lookup') ||
        str.contains('Network is unreachable') ||
        str.contains('Connection refused')) {
      return 'Không có kết nối Internet. Vui lòng kiểm tra Wi-Fi hoặc dữ liệu di động.';
    }

    // Lỗi kết nối SSL / Handshake
    if (str.contains('HandshakeException') || str.contains('CERTIFICATE_VERIFY_FAILED')) {
      return 'Lỗi kết nối bảo mật đến máy chủ. Vui lòng thử lại sau.';
    }

    // Lỗi Firestore / Firebase
    if (str.contains('permission-denied')) {
      return 'Bạn không có quyền thực hiện thao tác này.';
    }
    if (str.contains('unavailable')) {
      return 'Dịch vụ tạm thời gián đoạn. Vui lòng thử lại sau giây lát.';
    }
    if (str.contains('user-not-found') || str.contains('wrong-password') || str.contains('invalid-credential')) {
      return 'Email hoặc mật khẩu không chính xác.';
    }
    if (str.contains('email-already-in-use')) {
      return 'Email này đã được đăng ký tài khoản.';
    }

    // Lỗi thiết bị phần cứng Shelly
    if (str.contains('ShellyClientException') || (str.contains('Shelly') && str.contains('timeout'))) {
      return 'Không thể kết nối với bộ sạc thông minh. Vui lòng kiểm tra thiết bị.';
    }

    // Nếu thông điệp đã là chuỗi tiếng Việt rõ ràng, không chứa class exception
    final looksTechnical = str.contains('Exception') ||
        str.contains('Error:') ||
        str.contains('stackTrace') ||
        str.contains(' at ') ||
        str.contains('http://') ||
        str.contains('https://') ||
        str.contains('ts.net') ||
        str.contains('127.0.0.1') ||
        str.contains('{"');
    if (!looksTechnical) {
      return str.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    }

    return 'Đã xảy ra sự cố. Vui lòng thử lại sau.';
  }
}
