import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/app_providers.dart';
import '../core/services/assistant_context_coordinator.dart';
import '../core/theme/luxe_theme.dart';
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
      // Overview, Charge and History own their refresh indicators. Wrapping
      // them here created two simultaneous pull-to-refresh spinners.
      OverviewScreen(), // Tab 0: Overview
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
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppNavigationBar.railColor,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: AppNavigationBar.railColor,
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
        backgroundColor: LuxeColors.background,
        appBar: _buildUnifiedAppBar(context, currentIndex),
        body: Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (scrollInfo) {
                if (scrollInfo is UserScrollNotification) {
                  if (scrollInfo.direction == ScrollDirection.reverse) {
                    ref
                        .read(assistantContextCoordinatorProvider)
                        .setDocked(true);
                  } else if (scrollInfo.direction == ScrollDirection.forward ||
                      scrollInfo.metrics.pixels <= 20) {
                    ref
                        .read(assistantContextCoordinatorProvider)
                        .setDocked(false);
                  }
                }
                return false;
              },
              child: AppTabStack(index: currentIndex, children: _screens),
            ),
            GlobalChargingPill(),
            const FloatingBatteryBot(),
          ],
        ),
        bottomNavigationBar: AppNavigationBar(
          selectedIndex: currentIndex,
          onSelected: (index) {
            if (currentIndex != index) {
              HapticFeedback.selectionClick();
            }
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

    final titleSwap = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 360);

    return AppBar(
      backgroundColor: LuxeColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 20,
      // The title crossfades and rises with the tab, like the content below.
      title: AnimatedSwitcher(
        duration: titleSwap,
        switchInCurve: LuxeMotion.enter,
        switchOutCurve: LuxeMotion.exit,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: FittedBox(
          key: ValueKey('shell-title-$currentIndex'),
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            tabTitles[currentIndex],
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              color: LuxeColors.text,
              fontSize: 21,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
        ),
      ),
      actions: [
        if (currentIndex == 0) ...[
          _GlassAction(
            key: GuideRegistry.keyCustomizeDashboard,
            tooltip: 'Tùy chỉnh bố cục',
            icon: Icons.tune_rounded,
            onTap: () => DashboardCustomizationSheet.show(context),
          ),
          const SizedBox(width: 6),
        ],
        VehicleSwitcher(key: GuideRegistry.keyVehicleSwitcher),
        // Notification bell with badge
        // Shared provider (Task 125): the Notification Center invalidates it
        // after read/delete, so the badge drops at once instead of a new
        // one-shot stream on every app-bar rebuild.
        Consumer(
          builder: (context, ref, _) {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            final unreadCount = uid == null
                ? 0
                : ref.watch(unreadCountProvider(uid)).valueOrNull ?? 0;
            return _NotificationBell(
              unreadCount: unreadCount,
              energyMode: energyMode,
              onTap: () => _openNotificationCenter(context),
            );
          },
        ),
        const SizedBox(width: 14),
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
        final history = ref.watch(
          smartChargingControllerProvider(args).select((s) => s.history),
        );
        final controller = ref.read(
          smartChargingControllerProvider(args).notifier,
        );
        return SmartChargeHistoryScreen(
          controller: controller,
          ownerUid: ref.watch(currentUidProvider),
          initialItems: history,
          embedded: true,
          initialSessionId: pending?.sessionId,
          onStartCharging: () => AppNavigation.navigateToTab(context, 1),
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
      color: LuxeColors.emerald,
      backgroundColor: LuxeColors.raised,
      displacement: 60,
      child: child,
    );
  }
}

/// Round glass action in the shell bar (48dp target, hairline rim).
class _GlassAction extends StatelessWidget {
  const _GlassAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconColor = LuxeColors.platinum,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color iconColor;
  final Widget? badge;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      type: MaterialType.transparency,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: LuxeColors.glass,
            border: Border.all(color: LuxeColors.hairline),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 21, color: iconColor),
              if (badge != null) Positioned(top: 7, right: 7, child: badge!),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Notification bell with an emerald unread badge that pops in once.
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
    final pop = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 320);
    return Semantics(
      button: true,
      label: unreadCount > 0 ? 'Thông báo, $unreadCount chưa đọc' : 'Thông báo',
      excludeSemantics: true,
      onTap: onTap,
      child: _GlassAction(
        icon: unreadCount > 0
            ? Icons.notifications_rounded
            : Icons.notifications_none_rounded,
        iconColor: unreadCount > 0 ? LuxeColors.text : LuxeColors.platinum,
        tooltip: unreadCount > 0
            ? '$unreadCount thông báo mới'
            : 'Trung tâm thông báo',
        onTap: onTap,
        badge: AnimatedScale(
          duration: pop,
          curve: Curves.easeOutBack,
          scale: unreadCount > 0 ? 1 : 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            decoration: BoxDecoration(
              color: LuxeColors.emerald,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: LuxeColors.background, width: 1.5),
              boxShadow: const [
                BoxShadow(color: LuxeColors.emeraldGlow, blurRadius: 8),
              ],
            ),
            child: Center(
              child: Text(
                unreadCount > 99 ? '99+' : '$unreadCount',
                style: const TextStyle(
                  color: Color(0xFF04140D),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
