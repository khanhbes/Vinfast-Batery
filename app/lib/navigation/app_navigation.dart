import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/app_providers.dart';
import '../core/services/notification_center_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/cockpit_design_system.dart';
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
      _RefreshableTab(child: const OverviewScreen()), // Tab 0: Overview
      _RefreshableTab(child: const ChargeScreen()), // Tab 1: Charge
      _RefreshableTab(child: const _SelectedHistory()), // Tab 2: History
      _RefreshableTab(child: const MoreScreen()), // Tab 3: More
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Restore the last selected vehicle once at the app shell boundary so all
    // tabs share the same vehicle context before rendering scoped data.
    ref.watch(vehicleContextRestoreProvider);
    final currentIndex = ref.watch(currentTabProvider);

    const energyMode = true;
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: CockpitColors.shell,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: CockpitColors.border,
      ),
    );

    return Scaffold(
      backgroundColor: CockpitColors.background,
      appBar: _buildUnifiedAppBar(context, currentIndex),
      body: Stack(
        children: [
          IndexedStack(index: currentIndex, children: _screens),
          const GlobalChargingPill(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: CockpitColors.shell.withValues(alpha: 0.98),
          border: const Border(
            top: BorderSide(color: AppColors.glassBorder, width: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: CockpitColors.emerald.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Tổng quan',
                  isSelected: currentIndex == 0,
                  energyMode: energyMode,
                  onTap: () => ref.read(currentTabProvider.notifier).state = 0,
                ),
                _NavItem(
                  icon: Icons.bolt_rounded,
                  label: 'Sạc',
                  isSelected: currentIndex == 1,
                  energyMode: energyMode,
                  onTap: () => ref.read(currentTabProvider.notifier).state = 1,
                ),
                _NavItem(
                  icon: Icons.history_rounded,
                  label: 'Lịch sử',
                  isSelected: currentIndex == 2,
                  energyMode: energyMode,
                  onTap: () => ref.read(currentTabProvider.notifier).state = 2,
                ),
                _NavItem(
                  icon: Icons.more_horiz_rounded,
                  label: 'Khác',
                  isSelected: currentIndex == 3,
                  energyMode: energyMode,
                  onTap: () => ref.read(currentTabProvider.notifier).state = 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Unified AppBar cho tất cả tabs — PLAN1
  PreferredSizeWidget _buildUnifiedAppBar(
    BuildContext context,
    int currentIndex,
  ) {
    final tabTitles = ['Tổng quan', 'Smart Charge', 'Lịch sử sạc', 'Khác'];
    const energyMode = true;

    return AppBar(
      backgroundColor: CockpitColors.shell,
      elevation: 0,
      title: Text(
        tabTitles[currentIndex],
        style: TextStyle(
          color: CockpitColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        const VehicleSwitcher(),
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
        const SizedBox(width: 8),
      ],
    );
  }

  void _openNotificationCenter(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
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
      return const Center(child: Text('Hãy chọn xe để xem lịch sử sạc'));
    }
    final vehicle = ref.watch(vehicleProvider(id));
    return vehicle.when(
      loading: () => const Center(child: CircularProgressIndicator()),
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
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      displacement: 60,
      child: child,
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool energyMode;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.energyMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.base;
    const accent = CockpitColors.emerald;
    const muted = CockpitColors.muted;
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeInOut,
            padding: EdgeInsets.symmetric(
              horizontal: isSelected ? 16 : 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? accent.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? accent.withValues(alpha: .30)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: duration,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accent.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? accent : muted,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? accent : muted,
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.5,
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
        color: CockpitColors.elevated,
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
                      ? CockpitColors.emerald
                      : CockpitColors.muted,
                  size: 22,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: CockpitColors.emerald,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: CockpitColors.elevated,
                          width: 1.5,
                        ),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Center(
                        child: Text(
                          unreadCount > 99 ? '99+' : unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
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
