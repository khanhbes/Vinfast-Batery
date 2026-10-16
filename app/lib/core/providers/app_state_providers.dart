import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/active_charging_session_coordinator.dart';
import 'app_providers.dart';

/// Current tab index provider (thay thế GlobalKey)
final currentTabProvider = StateProvider<int>((ref) => 0);

final activeChargingSessionProvider =
    ChangeNotifierProvider<ActiveChargingSessionCoordinator>((ref) {
      // ChangeNotifierProvider disposes the notifier itself; a second
      // onDispose(dispose) tripped a debug assert (Task 125).
      return ActiveChargingSessionCoordinator();
    });

/// App refresh coordinator - quản lý pull-to-refresh toàn app
class AppRefreshCoordinator {
  final Ref ref;
  AppRefreshCoordinator(this.ref);

  /// Refresh tất cả dữ liệu app
  Future<void> refreshAll() async {
    // Legacy AI model sync no longer runs here: models are not
    // auto-downloaded (AGENTS 3.7) and it cost a server call per refresh.

    // Invalidate shared vehicle-scoped caches. Family providers are
    // invalidated as a whole so a refresh cannot leave one vehicle stale.
    ref.invalidate(allVehiclesProvider);
    ref.invalidate(vehicleProvider);
    ref.invalidate(chargeLogsProvider);
    ref.invalidate(vehicleStatsProvider);

    // Thông báo refresh hoàn thành
    ref.read(lastRefreshTimeProvider.notifier).state = DateTime.now();
  }
}

final appRefreshCoordinatorProvider = Provider<AppRefreshCoordinator>((ref) {
  return AppRefreshCoordinator(ref);
});

/// Thời điểm refresh gần nhất
final lastRefreshTimeProvider = StateProvider<DateTime?>((ref) => null);
