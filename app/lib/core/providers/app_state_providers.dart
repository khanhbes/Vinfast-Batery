import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_center_service.dart';

/// Current tab index provider (thay thế GlobalKey)
final currentTabProvider = StateProvider<int>((ref) => 0);

/// App refresh coordinator - quản lý pull-to-refresh toàn app
class AppRefreshCoordinator {
  final Ref ref;
  AppRefreshCoordinator(this.ref);

  /// Refresh tất cả dữ liệu app
  Future<void> refreshAll() async {
    // 1. Sync models từ server
    await NotificationCenterService().syncModels(force: true);
    
    // 2. TODO: Refetch các providers khác
    // - vehicle provider
    // - profile provider
    // - log provider
    // - maintenance provider
    // - trip provider
    
    // 3. Thông báo refresh hoàn thành
    ref.read(lastRefreshTimeProvider.notifier).state = DateTime.now();
  }
}

final appRefreshCoordinatorProvider = Provider<AppRefreshCoordinator>((ref) {
  return AppRefreshCoordinator(ref);
});

/// Thời điểm refresh gần nhất
final lastRefreshTimeProvider = StateProvider<DateTime?>((ref) => null);
