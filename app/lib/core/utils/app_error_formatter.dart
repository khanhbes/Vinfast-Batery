/// Chuyển đổi lỗi kỹ thuật dài thành thông báo thân thiện cho người dùng.
class AppErrorFormatter {
  AppErrorFormatter._();

  /// Format lỗi thành message ngắn gọn cho UI
  static String format(Object error) {
    final msg = error.toString();

    // Firestore index errors
    if (_isIndexError(msg)) {
      return 'Dữ liệu đang được đồng bộ. Vui lòng thử lại.';
    }

    // Firestore permission errors
    if (msg.contains('permission-denied') || msg.contains('PERMISSION_DENIED')) {
      return 'Không có quyền truy cập dữ liệu.';
    }

    // Network errors
    if (msg.contains('unavailable') ||
        msg.contains('network') ||
        msg.contains('SocketException') ||
        msg.contains('TimeoutException')) {
      return 'Không có kết nối mạng. Vui lòng kiểm tra internet.';
    }

    // Firebase not initialized
    if (msg.contains('Firebase') && msg.contains('initialize')) {
      return 'Lỗi khởi tạo Firebase. Vui lòng khởi động lại ứng dụng.';
    }

    // Firestore not found
    if (msg.contains('not-found') || msg.contains('NOT_FOUND')) {
      return 'Không tìm thấy dữ liệu.';
    }

    // Generic Firestore errors - truncate URL
    if (msg.contains('cloud_firestore') || msg.contains('firestore')) {
      return 'Lỗi tải dữ liệu. Vui lòng thử lại.';
    }

    // If message is too long, truncate
    if (msg.length > 80) {
      // Try to extract meaningful part
      final colonIdx = msg.indexOf(':');
      if (colonIdx > 0 && colonIdx < 60) {
        return msg.substring(colonIdx + 1).trim().length > 60
            ? 'Đã xảy ra lỗi. Vui lòng thử lại.'
            : msg.substring(colonIdx + 1).trim();
      }
      return 'Đã xảy ra lỗi. Vui lòng thử lại.';
    }

    return msg;
  }

  static bool _isIndexError(String msg) {
    final lower = msg.toLowerCase();
    return lower.contains('failed-precondition') ||
        lower.contains('failed_precondition') ||
        lower.contains('requires an index') ||
        lower.contains('indexes?create_composite');
  }
}
