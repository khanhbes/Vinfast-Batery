import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/active_charging_session_coordinator.dart';
import 'app_providers.dart';

/// Current tab index provider (thay thế GlobalKey)
final currentTabProvider = StateProvider<int>((ref) => 0);

/// The four tabs (QA 140: Lịch sử moved into Sạc pin, its place is the new
/// Tiện ích tab; Cài đặt keeps settings only).
abstract final class AppTab {
  static const overview = 0;
  static const charge = 1;
  static const utilities = 2;
  static const settings = 3;
  static const count = 4;
}

/// What the Sạc pin tab shows (QA 140): Sạc AI | Theo giờ | Lịch sử.
enum ChargeSection { ai, timed, history }

final chargeSectionProvider = StateProvider<ChargeSection>(
  (ref) => ChargeSection.ai,
);

/// Opens Sạc pin → Lịch sử (was the History tab before QA 140). [ref] is a
/// `Ref` or a `WidgetRef`.
void openChargeHistory(dynamic ref) {
  ref.read(chargeSectionProvider.notifier).state = ChargeSection.history;
  ref.read(currentTabProvider.notifier).state = AppTab.charge;
}

/// Opens Sạc pin on its charging controls: leaves Lịch sử (a pending target
/// is only taken by the controls), and with [ai] picks Sạc AI.
void openChargeControl(dynamic ref, {bool ai = false}) {
  final section = ref.read(chargeSectionProvider.notifier);
  if (ai || section.state == ChargeSection.history) {
    section.state = ChargeSection.ai;
  }
  ref.read(currentTabProvider.notifier).state = AppTab.charge;
}

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
