import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/app_providers.dart';
import '../core/services/notification_center_service.dart';
import '../core/theme/app_ui_colors.dart';
import '../core/widgets/app_navigation_bar.dart';
import '../core/widgets/app_popup.dart';
import '../core/widgets/app_tab_stack.dart';
import '../core/widgets/vehicle_switcher.dart';
import '../core/widgets/global_charging_pill.dart';
import '../features/ai/smart_charge_history_screen.dart';
import '../features/ai/controllers/smart_charging_controller.dart';
import '../features/notifications/notification_center_screen.dart';
import '../features/overview/overview_screen.dart';
import '../features/charge/charge_screen.dart';
import '../features/more/more_screen.dart';

/// Unified App Navigation — PLAN1 sync
/// - Unified AppBar với notification bell
/// - Riverpod tab state (thay GlobalKey)
/// - Pull-to-refresh coordinator
class AppNavigation extends ConsumerStatefulWidget {
  const AppNavigation({super.key});

  @override
  ConsumerState<AppNavigation> createState() => _AppNavigationState();

  /// Navigate to V4 tab (0: Overview, 1: Charge, 2: History, 3: More).
  /// Dùng context để truy cập Riverpod
  static void navigateToTab(BuildContext context, int index) {
    if (index >= 0 && index < 4) {
      // Sử dụng ProviderScope container để update state
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(currentTabProvider.notifier).state = index;
    }
  }
}

class _AppNavigationState extends ConsumerState<AppNavigation> {
  // Tab screens — wrap với RefreshIndicator
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      _RefreshableTab(child: OverviewScreen()), // Tab 0: Overview
      // Charge and History own their refresh indicators. Wrapping them here
      // created two simultaneous pull-to-refresh spinners.
      ChargeScreen(), // Tab 1: Charge
      _SelectedHistory(), // Tab 2: History
      _RefreshableTab(child: MoreScreen()), // Tab 3: More
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Restore the last selected vehicle once at the app shell boundary so all
    // tabs share the same vehicle context before rendering scoped data.
    ref.watch(vehicleContextRestoreProvider);
    final currentIndex = ref.watch(currentTabProvider);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarColor: AppUiColors.of(context).surface,
        systemNavigationBarIconBrightness:
            Theme.of(context).brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarDividerColor: AppUiColors.of(context).border,
      ),
    );

    return Scaffold(
      backgroundColor: AppUiColors.of(context).background,
      appBar: _buildUnifiedAppBar(context, currentIndex),
      body: Stack(
        children: [
          AppTabStack(index: currentIndex, children: _screens),
          GlobalChargingPill(),
        ],
      ),
      bottomNavigationBar: AppNavigationBar(
        selectedIndex: currentIndex,
        onSelected: (index) {
          AppPopup.clearShownErrors();
          ref.read(currentTabProvider.notifier).state = index;
        },
      ),
    );
  }

  /// Unified AppBar cho tất cả tabs — PLAN1
  PreferredSizeWidget _buildUnifiedAppBar(
    BuildContext context,
    int currentIndex,
  ) {
    final tabTitles = ['Tổng quan', '', 'Lịch sử sạc', 'Khác'];
    const energyMode = true;

    return AppBar(
      backgroundColor: AppUiColors.of(context).surface,
      elevation: 0,
      // The Charge workspace already has its own contextual heading. Keeping
      // another "Smart Charge" here caused truncation beside the vehicle pill.
      title: currentIndex == 1
          ? null
          : Text(
              tabTitles[currentIndex],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppUiColors.of(context).text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
      actions: [
        VehicleSwitcher(),
        // Notification bell with badge
        StreamBuilder<int>(
          stream: NotificationCenterService().watchUnreadCount(),
          builder: (context, snapshot) {
            final unreadCount = snapshot.data ?? 0;
            return _NotificationBell(
              unreadCount: unreadCount,
              energyMode: energyMode,
              onTap: () => _openNotificationCenter(context),
            );
          },
        ),
        SizedBox(width: 8),
      ],
    );
  }

  void _openNotificationCenter(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NotificationCenterScreen()),
    );
  }
}

class _SelectedHistory extends ConsumerWidget {
  const _SelectedHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedVehicleIdProvider);
    final pending = ref.watch(pendingSmartChargeTargetProvider);
    final id = pending?.vehicleId ?? selectedId;
    if (id.isEmpty) {
      return Center(child: Text('Hãy chọn xe để xem lịch sử sạc'));
    }
    final vehicle = ref.watch(vehicleProvider(id));
    return vehicle.when(
      loading: () => Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Không thể tải lịch sử: $e')),
      data: (value) {
        final args = SmartChargingControllerArgs(
          vehicleId: id,
          currentSoc: (value?.currentBattery ?? 0).toDouble(),
        );
        final state = ref.watch(smartChargingControllerProvider(args));
        final controller = ref.read(
          smartChargingControllerProvider(args).notifier,
        );
        return SmartChargeHistoryScreen(
          controller: controller,
          initialItems: state.history,
          embedded: true,
          initialSessionId: pending?.sessionId,
          onPendingTargetConsumed: pending == null
              ? null
              : () =>
                    ref.read(pendingSmartChargeTargetProvider.notifier).state =
                        null,
        );
      },
    );
  }
}

/// Widget wrap tab content với pull-to-refresh — PLAN1
class _RefreshableTab extends ConsumerWidget {
  final Widget child;

  const _RefreshableTab({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refreshCoordinator = ref.watch(appRefreshCoordinatorProvider);

    return RefreshIndicator(
      onRefresh: () => refreshCoordinator.refreshAll(),
      color: AppUiColors.of(context).primary,
      backgroundColor: AppUiColors.of(context).surface,
      displacement: 60,
      child: child,
    );
  }
}

/// Notification bell icon with unread badge
class _NotificationBell extends StatelessWidget {
  final int unreadCount;
  final bool energyMode;
  final VoidCallback onTap;

  const _NotificationBell({
    required this.unreadCount,
    required this.energyMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: unreadCount > 0 ? 'Thông báo, $unreadCount chưa đọc' : 'Thông báo',
      child: Material(
        color: AppUiColors.of(context).elevated,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.notifications_outlined,
                  color: unreadCount > 0
                      ? AppUiColors.of(context).primary
                      : AppUiColors.of(context).muted,
                  size: 22,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppUiColors.of(context).primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppUiColors.of(context).elevated,
                          width: 1.5,
                        ),
                      ),
                      constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Center(
                        child: Text(
                          unreadCount > 99 ? '99+' : unreadCount.toString(),
                          style: TextStyle(
                            color: AppUiColors.of(context).onPrimary,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
