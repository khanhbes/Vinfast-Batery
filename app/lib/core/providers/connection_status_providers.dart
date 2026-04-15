import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// =============================================================================
// Trạng thái kết nối dùng chung toàn app
// =============================================================================

/// Trạng thái kết nối chung
enum ConnectionStatus { checking, online, offline, degraded }

/// Provider trạng thái Firebase (ping Firestore timeout an toàn)
final firebaseStatusProvider =
    StateNotifierProvider<FirebaseStatusNotifier, ConnectionStatus>((ref) {
  return FirebaseStatusNotifier();
});

class FirebaseStatusNotifier extends StateNotifier<ConnectionStatus> {
  FirebaseStatusNotifier() : super(ConnectionStatus.checking) {
    check();
  }

  Future<void> check() async {
    state = ConnectionStatus.checking;
    try {
      // Ping Firestore bằng cách đọc 1 doc nhỏ, timeout 8s
      await FirebaseFirestore.instance
          .collection('Vehicles')
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      state = ConnectionStatus.online;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('unavailable') || msg.contains('timeout')) {
        state = ConnectionStatus.offline;
      } else {
        // Có thể lỗi khác nhưng Firestore cache vẫn hoạt động
        state = ConnectionStatus.degraded;
      }
    }
  }
}

// AI API status provider đã bị loại bỏ theo PLAN1.
// App không còn gọi HTTP AI API — dữ liệu AI đọc từ Firestore AiVehicleInsights.
// Consumer cũ dùng aiApiStatusProvider nên migrate sang aiInsightProvider.

/// Extension tiện ích cho ConnectionStatus
extension ConnectionStatusX on ConnectionStatus {
  String get label {
    switch (this) {
      case ConnectionStatus.checking:
        return 'Đang kiểm tra...';
      case ConnectionStatus.online:
        return 'Đã kết nối';
      case ConnectionStatus.offline:
        return 'Ngoại tuyến';
      case ConnectionStatus.degraded:
        return 'Không ổn định';
    }
  }

  bool get isOnline => this == ConnectionStatus.online;
  bool get isOffline => this == ConnectionStatus.offline;
}
