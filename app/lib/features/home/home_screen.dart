import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/dashboard_preferences_service.dart';
import '../../core/services/guide_registry.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_ui_colors.dart';
import '../../core/theme/luxe_theme.dart';
import 'widgets/luxe_dashboard_cards.dart';
import 'widgets/luxe_vehicle_hero.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/session_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/utils/app_error_formatter.dart';
import '../../data/models/vehicle_model.dart';
import 'widgets/range_prediction_card.dart';
import 'widgets/recent_charging_chart.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';
import '../trip_planner/trip_planner_wrapper.dart';
import '../maintenance/maintenance_screen.dart';
import '../../core/widgets/debug_error_sheet.dart';
import '../battery_monitor/battery_monitor_screen.dart';

// =============================================================================
// Home Screen V4 — Modern Dashboard Design
// =============================================================================

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    final vehicleAsync = ref.watch(vehicleProvider(vehicleId));
    final allVehiclesAsync = ref.watch(allVehiclesProvider);
    final prefService = ref.watch(dashboardPreferencesProvider);
    final visibleWidgets = prefService.visibleWidgets;

    // ── Initial auto-select on frame if vehicleId is not yet selected ──
    final currentVehicles = allVehiclesAsync.valueOrNull;
    if (currentVehicles != null &&
        currentVehicles.isNotEmpty &&
        vehicleId.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final currentId = ref.read(selectedVehicleIdProvider);
        if (currentId.isEmpty) {
          String targetId = currentVehicles.first.vehicleId;
          final savedId = ref.read(restoreVehicleIdProvider).valueOrNull;
          if (savedId != null &&
              savedId.isNotEmpty &&
              currentVehicles.any((v) => v.vehicleId == savedId)) {
            targetId = savedId;
          }
          ref.read(selectedVehicleIdProvider.notifier).state = targetId;
          SessionService().setSelectedVehicleId(targetId);
        }
      });
    }

    // ── Auto-select / auto-clear vehicle ID on provider changes ─────────
    ref.listen<AsyncValue<List<VehicleModel>>>(allVehiclesProvider, (
      previous,
      next,
    ) {
      next.whenData((vehicles) {
        final currentId = ref.read(selectedVehicleIdProvider);
        if (vehicles.isNotEmpty && currentId.isEmpty) {
          String targetId = vehicles.first.vehicleId;
          final savedId = ref.read(restoreVehicleIdProvider).valueOrNull;
          if (savedId != null &&
              savedId.isNotEmpty &&
              vehicles.any((v) => v.vehicleId == savedId)) {
            targetId = savedId;
          }
          ref.read(selectedVehicleIdProvider.notifier).state = targetId;
          SessionService().setSelectedVehicleId(targetId);
        }
      });
    });

    ref.listen<AsyncValue<VehicleModel?>>(vehicleProvider(vehicleId), (
      previous,
      next,
    ) {
      final currentId = ref.read(selectedVehicleIdProvider);
      if (currentId.isNotEmpty && next.hasValue && next.value == null) {
        ref.read(selectedVehicleIdProvider.notifier).state = '';
        SessionService().setSelectedVehicleId(null);
      }
    });

    return Theme(
      data: LuxeTheme.of(context),
      child: Scaffold(
        backgroundColor: LuxeColors.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const LuxeBackdrop(),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: RefreshIndicator(
                    color: LuxeColors.emerald,
                    backgroundColor: const Color(0xFF17181B),
                    onRefresh: () async {
                      final requests = <Future<Object?>>[
                        ref.refresh(allVehiclesProvider.future),
                      ];
                      if (vehicleId.isNotEmpty) {
                        requests.add(
                          ref.refresh(vehicleProvider(vehicleId).future),
                        );
                      }
                      try {
                        await Future.wait(requests);
                      } catch (_) {
                        // The providers keep the real failure for the inline retry
                        // state. Refresh must finish without opening a second notice.
                      }
                    },
                    child: CustomScrollView(
                      physics: AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        // ── Hiển thị banner cảnh báo nếu user chưa có xe nào ──
                        if (allVehiclesAsync.hasValue &&
                            (allVehiclesAsync.value?.isEmpty ?? true))
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                              child: _NoVehicleBanner(),
                            ),
                          ),

                        // ── Hiển thị banner lỗi nếu allVehiclesProvider failed ──
                        if (allVehiclesAsync.hasError)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                              child: _InlineErrorBanner(
                                title: 'Không tải được danh sách xe',
                                error: allVehiclesAsync.error!,
                                onRetry: () =>
                                    ref.invalidate(allVehiclesProvider),
                              ),
                            ),
                          ),

                        // ── Vehicle Banner ──
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                            child: KeyedSubtree(
                              key: GuideRegistry.keyBatterySummary,
                              child: vehicleAsync.when(
                                data: (vehicle) => LuxeReveal(
                                  child: LuxeVehicleHero(vehicle: vehicle),
                                ),
                                loading: () => const _LuxeSkeleton(height: 330),
                                error: (e, _) => _InlineErrorBanner(
                                  title: 'Không tải được thông tin xe',
                                  error: e,
                                  onRetry: () => ref.invalidate(
                                    vehicleProvider(vehicleId),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // ── Shelly checklist banner if skipped in onboarding ──
                        const _ShellyChecklistSliver(),

                        // ── Dynamic Customizable Widgets ──
                        for (final id in visibleWidgets)
                          _buildDashboardWidget(
                            id: id,
                            vehicleAsync: vehicleAsync,
                            vehicleId: vehicleId,
                            context: context,
                            ref: ref,
                          ),

                        SliverToBoxAdapter(child: SizedBox(height: 100)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardWidget({
    required String id,
    required AsyncValue<VehicleModel?> vehicleAsync,
    required String vehicleId,
    required BuildContext context,
    required WidgetRef ref,
  }) {
    switch (id) {
      case DashboardWidgetId.quickActions:
        return SliverToBoxAdapter(
          key: const ValueKey('widget_quick_actions'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: LuxeReveal(
              index: 1,
              child: LuxeQuickActions(
                tripKey: GuideRegistry.keyTripPlannerAction,
                onTrip: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => TripPlannerWrapper()),
                ),
                onMaintenance: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MaintenanceScreen()),
                ),
                onSync: () => _showSyncDialog(context),
              ),
            ),
          ),
        );

      case DashboardWidgetId.batteryStatistics:
        return SliverToBoxAdapter(
          key: const ValueKey('widget_battery_statistics'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: vehicleAsync.when(
              data: (vehicle) =>
                  LuxeReveal(index: 2, child: LuxeStatsStrip(vehicle: vehicle)),
              loading: () => const _LuxeSkeleton(height: 96),
              error: (_, _) => const LuxeStatsStrip(vehicle: null),
            ),
          ),
        );

      case DashboardWidgetId.rangePrediction:
        return SliverToBoxAdapter(
          key: const ValueKey('widget_range_prediction'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: vehicleAsync.when(
              data: (vehicle) => vehicle == null
                  ? const SizedBox.shrink()
                  : vehicle.hasBatteryData &&
                        vehicle.hasSohData &&
                        vehicle.hasEfficiencyData
                  ? RangePredictionCard(vehicle: vehicle)
                  : const LuxeDataHint(
                      message: 'Cần thêm dữ liệu pin để dự đoán quãng đường',
                    ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ),
        );

      case DashboardWidgetId.batteryHealth:
        return SliverToBoxAdapter(
          key: const ValueKey('widget_battery_health'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: vehicleAsync.when(
              data: (vehicle) => LuxeReveal(
                index: 3,
                child: LuxeBatteryHealthCard(
                  key: GuideRegistry.keyBatteryHealthCard,
                  soh: vehicle?.hasSohData == true
                      ? vehicle?.stateOfHealth
                      : null,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BatteryMonitorScreen(),
                    ),
                  ),
                ),
              ),
              loading: () => const _LuxeSkeleton(height: 116),
              error: (_, _) => LuxeBatteryHealthCard(
                soh: null,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BatteryMonitorScreen(),
                  ),
                ),
              ),
            ),
          ),
        );

      case DashboardWidgetId.recentCharging:
        return SliverToBoxAdapter(
          key: const ValueKey('widget_recent_charging'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: LuxeReveal(
              index: 4,
              child: RecentChargingChart(
                onViewHistory: () =>
                    ref.read(currentTabProvider.notifier).state = 2,
              ),
            ),
          ),
        );

      case DashboardWidgetId.efficiencyReference:
        return SliverToBoxAdapter(
          key: const ValueKey('widget_efficiency_reference'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: vehicleAsync.when(
              data: (vehicle) => LuxeEfficiencyNote(vehicle: vehicle),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ),
        );

      default:
        return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
  }

  void _showSyncDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => _SyncDialog());
  }
}

class _ShellyChecklistSliver extends StatelessWidget {
  const _ShellyChecklistSliver();

  @override
  Widget build(BuildContext context) {
    // Home can be rendered by the offline shell (and by widget tests) before
    // Firebase bootstrap completes. Accessing FirebaseAuth.instance before a
    // default app exists throws and cascades into framework build-scope errors.
    if (Firebase.apps.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final shellyStatus = data?['shellyOnboardingStatus'];
        if (shellyStatus == 'skipped') {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: LuxeShellyPrompt(
                onSetup: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SmartChargerSetupHubScreen(),
                  ),
                ),
              ),
            ),
          );
        }
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      },
    );
  }
}

// =============================================================================
// Widget Classes
// =============================================================================

class _SyncDialog extends StatefulWidget {
  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog>
    with SingleTickerProviderStateMixin {
  bool _isSyncing = false;
  String _status = 'Sẵn sàng đồng bộ';
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _performSync() async {
    setState(() {
      _isSyncing = true;
      _status = 'Đang đồng bộ dữ liệu...';
    });

    final syncService = SyncService();
    final result = await syncService.performFullSync();

    setState(() {
      _isSyncing = false;
      _status = result['success'] ? 'Đồng bộ thành công!' : 'Đồng bộ thất bại';
    });

    await Future.delayed(Duration(seconds: 1));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppUiColors.of(context).surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _animationController,
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppUiColors.of(context).primarySurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.sync_rounded,
                  color: AppUiColors.of(context).primary,
                  size: 32,
                ),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Đồng bộ dữ liệu Web',
              style: TextStyle(
                color: AppUiColors.of(context).text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 8),
            Text(
              _status,
              style: TextStyle(
                color: AppUiColors.of(context).muted,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 24),
            if (_isSyncing)
              LinearProgressIndicator(
                backgroundColor: AppUiColors.of(context).elevated,
                valueColor: AlwaysStoppedAnimation(
                  AppUiColors.of(context).primary,
                ),
                borderRadius: BorderRadius.circular(4),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _AnimatedButton(
                      label: 'Hủy',
                      isSecondary: true,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _AnimatedButton(
                      label: 'Đồng bộ ngay',
                      onTap: _performSync,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // Efficiency Card Widget
  // ignore: unused_element
  Widget _buildEfficiencyCard({required double efficiency}) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppUiColors.of(context).surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppUiColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppUiColors.of(context).primary.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.speed_rounded,
                  color: AppUiColors.of(context).primary,
                  size: 18,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Hiệu suất lái xe',
                  style: TextStyle(
                    color: AppUiColors.of(context).text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${efficiency.toInt()}%',
                style: TextStyle(
                  color: AppUiColors.of(context).primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: efficiency / 100,
              backgroundColor: AppUiColors.of(context).elevated,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppUiColors.of(context).primary,
              ),
              minHeight: 8,
            ),
          ),
        ],
      ),
    ).appFadeSlideIn(index: 4);
  }

  // Achievement Card Widget
  // ignore: unused_element
  Widget _buildAchievementCard({required double efficiency}) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppUiColors.of(context).surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppUiColors.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppUiColors.of(context).primary.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.emoji_events_rounded,
                  color: AppUiColors.of(context).primary,
                  size: 18,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Thành tích lái xe',
                  style: TextStyle(
                    color: AppUiColors.of(context).text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              _buildAchievementItem(
                icon: Icons.local_florist_rounded,
                label: 'Eco Master',
                achieved: efficiency >= 85,
              ),
              SizedBox(width: 12),
              _buildAchievementItem(
                icon: Icons.bolt,
                label: 'Energy Saver',
                achieved: efficiency >= 75,
              ),
              SizedBox(width: 12),
              _buildAchievementItem(
                icon: Icons.star_rounded,
                label: 'Top Driver',
                achieved: efficiency >= 90,
              ),
            ],
          ),
        ],
      ),
    ).appFadeSlideIn(index: 5);
  }

  Widget _buildAchievementItem({
    required IconData icon,
    required String label,
    required bool achieved,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: achieved
              ? AppUiColors.of(context).primary.withAlpha(26)
              : AppUiColors.of(context).elevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: achieved
                  ? AppUiColors.of(context).primary
                  : AppUiColors.of(context).muted,
              size: 24,
            ),
            SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: achieved
                    ? AppUiColors.of(context).primary
                    : AppUiColors.of(context).muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool isSecondary;

  const _AnimatedButton({
    required this.label,
    required this.onTap,
    this.isSecondary = false,
  });

  @override
  State<_AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<_AnimatedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: widget.isSecondary
                ? AppUiColors.of(context).elevated
                : AppUiColors.of(context).primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.isSecondary
                    ? AppUiColors.of(context).text
                    : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineErrorBanner extends StatelessWidget {
  final String title;
  final Object error;
  final VoidCallback onRetry;

  const _InlineErrorBanner({
    required this.title,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final friendly = AppErrorFormatter.format(error);
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppUiColors.of(context).danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppUiColors.of(context).danger.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: AppUiColors.of(context).danger,
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppUiColors.of(context).text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: onRetry,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: AppUiColors.of(context).danger,
                  size: 20,
                ),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                tooltip: 'Thử lại',
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            friendly,
            style: TextStyle(
              color: AppUiColors.of(context).muted,
              fontSize: 12,
            ),
          ),
          if (kDebugMode) ...[
            SizedBox(height: 6),
            GestureDetector(
              onTap: () =>
                  DebugErrorSheet.show(context, error: error, source: title),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.terminal_rounded,
                      size: 13,
                      color: AppUiColors.of(context).muted,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Xem chi tiết kỹ thuật',
                      style: TextStyle(
                        color: AppUiColors.of(context).muted,
                        fontSize: 11,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoVehicleBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppUiColors.of(context).warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppUiColors.of(context).warning.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.directions_car_outlined,
            color: AppUiColors.of(context).warning,
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bạn chưa có xe nào. Vào Settings → Garage để thêm xe đầu tiên.',
              style: TextStyle(
                color: AppUiColors.of(context).text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quiet glass placeholder while a card loads.
class _LuxeSkeleton extends StatelessWidget {
  const _LuxeSkeleton({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: LuxeColors.glass,
      border: Border.all(color: LuxeColors.hairline),
    ),
  );
}
