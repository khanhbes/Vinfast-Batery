import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../settings/vehicle_garage_screen.dart';
import '../../core/constants/beta_capabilities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/dashboard_preferences_service.dart';
import '../../core/services/guide_registry.dart';
import '../../core/theme/luxe_theme.dart';
import 'widgets/luxe_dashboard_cards.dart';
import 'widgets/luxe_vehicle_hero.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/app_error_formatter.dart';
import '../../data/models/vehicle_model.dart';
import 'widgets/range_prediction_card.dart';
import '../../data/services/range_estimator.dart';
import 'widgets/recent_charging_chart.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';
import '../trip_planner/trip_planner_wrapper.dart';
import '../maintenance/maintenance_screen.dart';
import '../../core/widgets/debug_error_sheet.dart';
import '../../core/widgets/luxe_kit.dart';
import '../battery_monitor/battery_monitor_screen.dart';
import '../ai/services/learning_flow.dart';

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
      // Task 127: once per app run, tell the owner when collected data is
      // enough to train (never trains by itself).
      final loaded = next.valueOrNull;
      if (loaded != null && loaded.vehicleId == currentId) {
        TrainingReadiness.refreshOnce(currentId);
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
                      // Single pull-to-refresh for Overview (Task 125).
                      ref.invalidate(chargeLogsProvider);
                      ref.invalidate(vehicleStatsProvider);
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
                                  child: LuxeVehicleHero(
                                    vehicle: vehicle,
                                    learned: ref
                                        .watch(learnedModelsProvider(vehicleId))
                                        .valueOrNull
                                        ?.trip,
                                  ),
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
    // One learned km/% for the hero, stats, range card and note (QA 129).
    final learned = ref
        .watch(learnedModelsProvider(vehicleId))
        .valueOrNull
        ?.trip;
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
                onTrip: BetaCapabilities.tripPlanner
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TripPlannerWrapper()),
                      )
                    : null,
                onMaintenance: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MaintenanceScreen()),
                ),
                onBatteryMonitor: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BatteryMonitorScreen(),
                  ),
                ),
                onReadDashboard: vehicleId.isEmpty
                    ? null
                    : () {
                        final vehicle = vehicleAsync.valueOrNull;
                        BatteryReadingFlow.run(
                          context,
                          vehicleId: vehicleId,
                          currentSoc: vehicle?.hasBatteryData == true
                              ? vehicle!.currentBattery.toDouble()
                              : null,
                          currentOdoKm: vehicle?.currentOdo.toDouble(),
                        );
                      },
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
                  LuxeReveal(
                index: 2,
                child: LuxeStatsStrip(vehicle: vehicle, learned: learned),
              ),
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
                  : estimateRange(vehicle, learned: learned) != null
                  ? RangePredictionCard(vehicle: vehicle, learned: learned)
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
              data: (vehicle) =>
                  LuxeEfficiencyNote(vehicle: vehicle, learned: learned),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ),
        );

      default:
        return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
  }
}

class _ShellyChecklistSliver extends StatefulWidget {
  const _ShellyChecklistSliver();

  @override
  State<_ShellyChecklistSliver> createState() => _ShellyChecklistSliverState();
}

class _ShellyChecklistSliverState extends State<_ShellyChecklistSliver> {
  // One listener per account: a new snapshots() stream on every Home rebuild
  // re-subscribed and re-read users/{uid} (Task 125).
  String? _uid;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _profile;

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

    if (_uid != user.uid || _profile == null) {
      _uid = user.uid;
      _profile = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots();
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _profile,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      decoration: BoxDecoration(
        color: LuxeColors.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LuxeColors.danger.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: LuxeColors.danger,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: LuxeText.item.copyWith(fontSize: 14.5),
                ),
              ),
              IconButton(
                onPressed: onRetry,
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: LuxeColors.platinum,
                  size: 20,
                ),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: 'Thử lại',
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 30, right: 8),
            child: Text(friendly, style: LuxeText.caption),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: GestureDetector(
                onTap: () =>
                    DebugErrorSheet.show(context, error: error, source: title),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.terminal_rounded,
                        size: 13,
                        color: LuxeColors.dim,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Xem chi tiết kỹ thuật',
                        style: LuxeText.label.copyWith(
                          fontSize: 11,
                          color: LuxeColors.dim,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
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
  // Vietnamese copy and a real way forward (it named an English menu path
  // and had no button, Task 125).
  @override
  Widget build(BuildContext context) => LuxeNotice(
    icon: Icons.electric_moped_rounded,
    color: LuxeColors.champagne,
    message: 'Bạn chưa có xe nào. Thêm xe đầu tiên để theo dõi pin và sạc.',
    action: TextButton(
      key: const ValueKey('home-add-first-vehicle'),
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const VehicleGarageScreen()),
      ),
      child: const Text('Thêm xe'),
    ),
  );
}

/// Quiet glass placeholder while a card loads (static: home loads behind
/// pull-to-refresh and tests settle on it).
class _LuxeSkeleton extends StatelessWidget {
  const _LuxeSkeleton({required this.height});
  final double height;

  // Shimmer while the vehicle is really loading (a plain empty box looked
  // like a blank card for seconds on cold start, Task 125).
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Đang tải thông tin xe',
    child: LuxeShimmer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: LuxeColors.glass,
          border: Border.all(color: LuxeColors.hairline),
        ),
      ),
    ),
  );
}
