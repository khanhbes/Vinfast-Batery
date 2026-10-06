import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/app_providers.dart';
import '../core/services/notification_center_service.dart';
import '../core/theme/app_ui_colors.dart';
import '../core/widgets/app_navigation_bar.dart';
import '../core/widgets/app_popup.dart';
import '../core/widgets/app_tab_stack.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/error_state.dart';
import '../core/widgets/vehicle_picker_sheet.dart';
import '../core/widgets/vehicle_switcher.dart';
import '../core/widgets/global_charging_pill.dart';
import '../core/widgets/floating_battery_bot.dart';
import '../features/ai/smart_charge_history_screen.dart';
import '../features/ai/controllers/smart_charging_controller.dart';
import '../features/notifications/notification_center_screen.dart';
import '../core/services/guide_registry.dart';
import '../core/services/dashboard_preferences_service.dart';
import '../core/services/guide_tour_coordinator.dart';
import '../core/widgets/coach_mark_overlay.dart';
import '../features/overview/widgets/dashboard_customization_sheet.dart';
import '../features/overview/overview_screen.dart';
import '../features/charge/charge_screen.dart';
import '../features/auth/auth_providers.dart';
import '../features/more/more_screen.dart';

final guideTourCoordinatorProvider = Provider<GuideTourCoordinator>((ref) {
  final coordinator = GuideTourCoordinator();
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

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

  /// Reveal the authenticated root shell from a pushed help route. Selecting
  /// a hidden tab alone leaves Guide/BatteryBot obscuring the destination.
  /// This helper only navigates; it never dispatches charging operations.
  static bool openTab(BuildContext context, int index) {
    if (!context.mounted || index < 0 || index >= 4) return false;
    navigateToTab(context, index);
    Navigator.of(context).popUntil((route) => route.isFirst);
    return true;
  }

  static bool replayOverviewTour(BuildContext context) {
    final coordinator = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(guideTourCoordinatorProvider);
    if (!openTab(context, 0)) return false;
    coordinator.replay();
    return true;
  }
}

class _AppNavigationState extends ConsumerState<AppNavigation> {
  // Tab screens — wrap với RefreshIndicator
  late final List<Widget> _screens;
  StreamSubscription<User?>? _authSubscription;
  String? _boundUid;
  bool _guideShown = false;
  late final GuideTourCoordinator _guide;
  DashboardPreferencesService? _guidePreferences;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _boundUid = uid;
    _guide = ref.read(guideTourCoordinatorProvider);
    _guide.dismissOverlay = CoachMarkOverlay.dismissActive;
    _guide.entryIsActive = CoachMarkOverlay.isActive;
    _guide.activateAccount(uid);
    _guide.onReplay = () => unawaited(_tryShowFirstRunGuide(manual: true));
    _guidePreferences = ref.read(dashboardPreferencesProvider);
    _guidePreferences!.addListener(_onGuidePreferencesChanged);
    if (uid != null) {
      unawaited(ref.read(dashboardPreferencesProvider).initializeForUser(uid));
      unawaited(ref.read(activeChargingSessionProvider).bindUser(uid));
    }
    _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
      final nextUid = user?.uid;
      if (nextUid == _boundUid) return;
      _boundUid = nextUid;
      _guide.activateAccount(nextUid);
      _guideShown = false;
      if (nextUid != null && mounted) {
        unawaited(
          ref.read(dashboardPreferencesProvider).initializeForUser(nextUid),
        );
        unawaited(ref.read(activeChargingSessionProvider).bindUser(nextUid));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_tryShowFirstRunGuide());
        });
      }
    });
    _screens = [
      _RefreshableTab(child: OverviewScreen()), // Tab 0: Overview
      // Charge and History own their refresh indicators. Wrapping them here
      // created two simultaneous pull-to-refresh spinners.
      ChargeScreen(), // Tab 1: Charge
      _SelectedHistory(), // Tab 2: History
      _RefreshableTab(child: MoreScreen()), // Tab 3: More
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_tryShowFirstRunGuide());
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _guidePreferences?.removeListener(_onGuidePreferencesChanged);
    _guide.cancel();
    _guide.onReplay = null;
    super.dispose();
  }

  void _onGuidePreferencesChanged() {
    if (mounted) unawaited(_tryShowFirstRunGuide());
  }

  Future<void> _tryShowFirstRunGuide({bool manual = false}) async {
    if (!mounted || (!manual && _guideShown)) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final preferences = ref.read(dashboardPreferencesProvider);
    await preferences.initializeForUser(uid);
    if (!mounted ||
        _boundUid != uid ||
        FirebaseAuth.instance.currentUser?.uid != uid ||
        preferences.uid != uid ||
        (!manual &&
            (_guideShown ||
                !preferences.shouldAutoShow(GuideRegistry.overviewTourId)))) {
      return;
    }
    bool sameAccount() =>
        mounted &&
        _boundUid == uid &&
        FirebaseAuth.instance.currentUser?.uid == uid &&
        preferences.uid == uid;
    _guide.request(
      uid: uid,
      manual: manual,
      ready: () =>
          sameAccount() &&
          ModalRoute.of(context)?.isCurrent == true &&
          ref.read(currentTabProvider) == 0 &&
          !AppPopup.safetyNoticeVisible &&
          GuideRegistry.getOverviewTourSteps().every(
            (step) => step.anchorKey.currentContext != null,
          ),
      show: () {
        if (!sameAccount()) return null;
        final entry = CoachMarkOverlay.show(
          context: context,
          overlay: Navigator.of(context).overlay,
          steps: GuideRegistry.getOverviewTourSteps(),
          showDontShowAgain: !manual,
          onFinish: () {
            if (!manual && sameAccount()) {
              unawaited(
                preferences.markTourCompleted(GuideRegistry.overviewTourId),
              );
            }
          },
          onSkip: () {
            if (!manual && sameAccount()) {
              unawaited(
                preferences.markTourDismissed(GuideRegistry.overviewTourId),
              );
            }
          },
          onDontShowAgain: (dontShow) {
            if (!manual && dontShow && sameAccount()) {
              unawaited(
                preferences.markTourDismissed(GuideRegistry.overviewTourId),
              );
            }
          },
        );
        if (entry != null) _guideShown = true;
        return entry;
      },
    );
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

    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && currentIndex != 0) {
          ref.read(currentTabProvider.notifier).state = 0;
        }
      },
      child: Scaffold(
        backgroundColor: AppUiColors.of(context).background,
        appBar: _buildUnifiedAppBar(context, currentIndex),
        body: Stack(
          children: [
            AppTabStack(index: currentIndex, children: _screens),
            GlobalChargingPill(),
            const FloatingBatteryBot(),
          ],
        ),
        bottomNavigationBar: AppNavigationBar(
          selectedIndex: currentIndex,
          onSelected: (index) {
            AppPopup.clearShownErrors();
            ref.read(currentTabProvider.notifier).state = index;
          },
        ),
      ),
    );
  }

  /// Unified AppBar cho tất cả tabs — PLAN1
  PreferredSizeWidget _buildUnifiedAppBar(
    BuildContext context,
    int currentIndex,
  ) {
    final tabTitles = ['Tổng quan', 'Sạc pin', 'Lịch sử', 'Cài đặt'];
    const energyMode = true;

    return AppBar(
      backgroundColor: AppUiColors.of(context).surface,
      elevation: 0,
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          tabTitles[currentIndex],
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: AppUiColors.of(context).text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      actions: [
        if (currentIndex == 0) ...[
          IconButton(
            key: GuideRegistry.keyCustomizeDashboard,
            tooltip: 'Tùy chỉnh bố cục',
            icon: const Icon(Icons.tune_rounded, size: 21),
            color: AppUiColors.of(context).text,
            onPressed: () => DashboardCustomizationSheet.show(context),
          ),
        ],
        VehicleSwitcher(key: GuideRegistry.keyVehicleSwitcher),
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
      return EmptyState(
        icon: Icons.history_rounded,
        title: 'Chưa chọn phương tiện',
        message:
            'Vui lòng chọn xe VinFast của bạn để xem toàn bộ lịch sử sạc pin.',
        actionLabel: 'Chọn xe ngay',
        onAction: () => VehiclePickerSheet.show(context, ref),
      );
    }
    final vehicle = ref.watch(vehicleProvider(id));
    return vehicle.when(
      loading: () => Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState.fromError(
        error: e,
        prefix: 'Chưa tải được lịch sử',
        onRetry: () => ref.invalidate(vehicleProvider(id)),
      ),
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
          ownerUid: ref.watch(currentUidProvider),
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
      child: Tooltip(
        message: unreadCount > 0
            ? '$unreadCount thông báo mới'
            : 'Trung tâm thông báo',
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
                        constraints: BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
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
      ),
    );
  }
}
