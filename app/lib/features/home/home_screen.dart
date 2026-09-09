import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/cockpit_design_system.dart';
import '../../core/theme/app_ui_colors.dart';
import '../../core/widgets/responsive_card_grid.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/session_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/utils/app_error_formatter.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/services/battery_state_service.dart';
import 'widgets/range_prediction_card.dart';
import 'widgets/recent_charging_chart.dart';
import '../dashboard/dashboard_screen.dart';
import '../trip_planner/trip_planner_wrapper.dart';
import '../maintenance/maintenance_screen.dart';

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
    final restoredId = ref.watch(restoreVehicleIdProvider);

    // ── Auto-select / auto-clear vehicle ID ────────────────────────────────
    // 1. Khi danh sách xe load xong và chưa có xe được chọn → chọn xe đầu
    //    (ưu tiên ID đã lưu trong session nếu vẫn còn trong list).
    allVehiclesAsync.whenData((vehicles) {
      if (vehicles.isNotEmpty && vehicleId.isEmpty) {
        String targetId = vehicles.first.vehicleId;
        restoredId.whenData((savedId) {
          if (savedId.isNotEmpty &&
              vehicles.any((v) => v.vehicleId == savedId)) {
            targetId = savedId;
          }
        });
        Future.microtask(() {
          ref.read(selectedVehicleIdProvider.notifier).state = targetId;
          SessionService().setSelectedVehicleId(targetId);
        });
      }
    });

    // 2. Nếu vehicleId đang chọn KHÔNG resolve được (stale: xe đã xoá / không
    //    thuộc user / firestore từ chối quyền) → reset về '' để build sau
    //    tự pick lại từ allVehicles.
    if (vehicleId.isNotEmpty &&
        vehicleAsync.hasValue &&
        vehicleAsync.value == null) {
      Future.microtask(() {
        ref.read(selectedVehicleIdProvider.notifier).state = '';
        SessionService().setSelectedVehicleId(null);
      });
    }

    return Scaffold(
      backgroundColor: AppUiColors.of(context).background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RefreshIndicator(
              color: AppUiColors.of(context).primary,
          onRefresh: () async {
            ref.invalidate(allVehiclesProvider);
            if (vehicleId.isNotEmpty) {
              ref.invalidate(vehicleProvider(vehicleId));
            }
            await Future<void>.delayed(Duration(milliseconds: 300));
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
                      onRetry: () => ref.invalidate(allVehiclesProvider),
                    ),
                  ),
                ),

              // ── Vehicle Banner ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: vehicleAsync.when(
                    data: (vehicle) => _VehicleBanner(vehicle: vehicle),
                    loading: () => _VehicleBannerShimmer(),
                    error: (e, _) => _InlineErrorBanner(
                      title: 'Không tải được thông tin xe',
                      error: e,
                      onRetry: () => ref.invalidate(vehicleProvider(vehicleId)),
                    ),
                  ),
                ),
              ),

              // ── Quick Actions ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: vehicleAsync.when(
                    data: (vehicle) => _QuickActionsRow(
                      vehicleId: vehicle?.vehicleId ?? '',
                      onSync: () => _showSyncDialog(context),
                    ),
                    loading: () => _QuickActionsShimmer(),
                    error: (_, __) => _QuickActionsRow(
                      vehicleId: '',
                      onSync: () => _showSyncDialog(context),
                    ),
                  ),
                ),
              ),

              // ── Stat Cards Row ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: vehicleAsync.when(
                    data: (vehicle) => _StatCardsRow(vehicle: vehicle),
                    loading: () => _StatCardsRowShimmer(),
                    error: (_, __) => _StatCardsRow(vehicle: null),
                  ),
                ),
              ),

              // ── Range Prediction Card ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: vehicleAsync.when(
                    data: (vehicle) => vehicle == null
                        ? SizedBox.shrink()
                        : vehicle.hasBatteryData &&
                              vehicle.hasSohData &&
                              vehicle.hasEfficiencyData
                        ? RangePredictionCard(vehicle: vehicle)
                        : _MissingVehicleDataCard(
                            message:
                                'Cần thêm dữ liệu pin để dự đoán quãng đường',
                          ),
                    loading: () => SizedBox.shrink(),
                    error: (_, __) => SizedBox.shrink(),
                  ),
                ),
              ),

              // ── Battery Health Score ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: vehicleAsync.when(
                    data: (vehicle) => _BatteryHealthCard(
                      soh: vehicle?.hasSohData == true
                          ? vehicle?.stateOfHealth
                          : null,
                      vehicleId: vehicle?.vehicleId ?? '',
                    ),
                    loading: () => _BatteryHealthShimmer(),
                    error: (_, __) =>
                        _BatteryHealthCard(soh: null, vehicleId: ''),
                  ),
                ),
              ),

              // ── Recent Charging Trend Chart ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: RecentChargingChart(
                    onViewHistory: () =>
                        ref.read(currentTabProvider.notifier).state = 2,
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: vehicleAsync.when(
                    data: (vehicle) => _EfficiencyReference(vehicle: vehicle),
                    loading: () => SizedBox.shrink(),
                    error: (_, __) => SizedBox.shrink(),
                  ),
                ),
              ),

              SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }

  void _showSyncDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => _SyncDialog());
  }
}

// =============================================================================
// Widget Classes
// =============================================================================

class _VehicleBanner extends StatelessWidget {
  final VehicleModel? vehicle;

  const _VehicleBanner({this.vehicle});

  @override
  Widget build(BuildContext context) {
    final name = vehicle?.vehicleName.isNotEmpty == true
        ? vehicle!.vehicleName
        : (vehicle?.vinfastModelName?.isNotEmpty == true
            ? vehicle!.vinfastModelName!
            : 'VinFast EV');
    final plate = vehicle?.vehicleId.isNotEmpty == true
        ? vehicle!.vehicleId
        : 'VF-ECO';
    final percent = vehicle?.hasBatteryData == true
        ? vehicle?.lastBatteryPercent
        : null;

    return Container(
      height: 210,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: CockpitColors.surface,
        image: DecorationImage(
          onError: (_, __) {},
          image: const NetworkImage(
            'https://images.unsplash.com/photo-1617788138017-80ad40651399?w=800',
          ),
          fit: BoxFit.cover,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Gradient dark overlay
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.25),
                  Colors.black.withValues(alpha: 0.85),
                ],
              ),
            ),
          ),

          // Top Row: Active connection status & Model badge
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Active badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: CockpitColors.emeraldStrong.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: CockpitColors.emeraldStrong,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: CockpitColors.emeraldStrong,
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Đã kết nối',
                        style: CockpitTypography.label(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Model tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Text(
                    vehicle?.vinfastModelName?.toUpperCase() ?? 'VF COCKPIT',
                    style: CockpitTypography.label(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Row: Vehicle Name & Plate, plus Battery SOC badge
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CockpitTypography.heading(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          plate,
                          style: CockpitTypography.numbers(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Battery SOC Pill
                if (percent != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: CockpitColors.emeraldStrong.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: CockpitColors.emeraldStrong.withValues(alpha: 0.5),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: CockpitColors.emeraldStrong.withValues(alpha: 0.2),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.electric_bolt_rounded,
                          size: 18,
                          color: CockpitColors.emeraldStrong,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$percent%',
                          style: CockpitTypography.numbers(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: CockpitColors.emeraldStrong,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ).appScalePop();
  }
}

class _VehicleBannerShimmer extends StatelessWidget {
  const _VehicleBannerShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: AppUiColors.of(context).surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Center(
        child: CircularProgressIndicator(
          color: AppUiColors.of(context).primary,
          strokeWidth: 2,
        ),
      ),
    );
  }
}

class _StatCardsRow extends StatelessWidget {
  final VehicleModel? vehicle;

  const _StatCardsRow({this.vehicle});

  @override
  Widget build(BuildContext context) {
    final percent = vehicle?.hasBatteryData == true
        ? vehicle?.lastBatteryPercent
        : null;
    final efficiency = vehicle?.hasEfficiencyData == true
        ? vehicle?.defaultEfficiency
        : null;
    final range = percent != null && efficiency != null && efficiency > 0
        ? (percent * efficiency).toInt().toString()
        : '—';
    final odo = vehicle?.hasOdoData == true ? vehicle?.currentOdo : null;

    return ResponsiveCardGrid(
      maxColumns: 3,
      minCardWidth: 100,
      children: [
        _StatCard(
          icon: Icons.bolt_outlined,
          value: percent == null ? '—' : '$percent%',
          label: 'CHARGE',
          isHighlighted: false,
        ),
        _StatCard(
          icon: Icons.near_me_outlined,
          value: range,
          label: 'RANGE KM',
          isHighlighted: true,
        ),
        _StatCard(
          icon: Icons.access_time_outlined,
          value: odo == null ? '—' : '$odo',
          label: 'ODO KM',
          isHighlighted: false,
        ),
      ],
    ).appFadeSlideIn(index: 2);
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool isHighlighted;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.isHighlighted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHighlighted
            ? AppUiColors.of(context).primarySurface
            : AppUiColors.of(context).surface,
        borderRadius: BorderRadius.circular(24),
        border: isHighlighted
            ? null
            : Border.all(color: AppUiColors.of(context).border),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: isHighlighted
                ? AppUiColors.of(context).primary
                : AppUiColors.of(context).muted,
            size: 24,
          ),
          SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: AppUiColors.of(context).text,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isHighlighted
                  ? AppUiColors.of(context).primary.withValues(alpha: 0.8)
                  : AppUiColors.of(context).muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCardsRowShimmer extends StatelessWidget {
  const _StatCardsRowShimmer();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        3,
        (index) => Expanded(
          child: Container(
            margin: EdgeInsets.only(right: index < 2 ? 12 : 0),
            height: 100,
            decoration: BoxDecoration(
              color: AppUiColors.of(context).surface,
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      ),
    );
  }
}

class _BatteryHealthCard extends StatefulWidget {
  final double? soh;
  final String vehicleId;

  const _BatteryHealthCard({required this.soh, required this.vehicleId});

  @override
  State<_BatteryHealthCard> createState() => _BatteryHealthCardState();
}

class _BatteryHealthCardState extends State<_BatteryHealthCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _syncBatteryState() async {
    if (widget.vehicleId.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      // Sync battery state to web
      await BatteryStateService.syncWithWebDashboard(widget.vehicleId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Battery health synced to web dashboard'),
            backgroundColor: AppUiColors.of(context).primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: AppUiColors.of(context).danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasData = widget.soh != null && widget.soh!.isFinite;
    final score = widget.soh ?? 0;
    final isHealthy = hasData && score >= 90;

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DashboardScreen()),
        );
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
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
                      Icons.favorite_outline,
                      color: AppUiColors.of(context).primary,
                      size: 18,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Battery Health Score',
                      style: TextStyle(
                        color: AppUiColors.of(context).text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    hasData ? '${score.toInt()}%' : '—',
                    style: TextStyle(
                      color: AppUiColors.of(context).text,
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
                  value: hasData ? (score / 100).clamp(0.0, 1.0) : 0,
                  backgroundColor: AppUiColors.of(context).elevated,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isHealthy
                        ? AppUiColors.of(context).primary
                        : AppUiColors.of(context).warning,
                  ),
                  minHeight: 8,
                ),
              ),
              SizedBox(height: 12),
              Text(
                !hasData
                    ? 'Cần thêm dữ liệu xe'
                    : isHealthy
                    ? 'Excellent condition'
                    : 'Consider maintenance check',
                style: TextStyle(
                  color: !hasData
                      ? AppUiColors.of(context).muted
                      : isHealthy
                      ? AppUiColors.of(context).primary
                      : AppUiColors.of(context).warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ).appFadeSlideIn(index: 3);
  }
}

class _QuickActionsRow extends StatelessWidget {
  final String vehicleId;
  final VoidCallback onSync;

  const _QuickActionsRow({required this.vehicleId, required this.onSync});

  @override
  Widget build(BuildContext context) {
    return ResponsiveCardGrid(
      maxColumns: 3,
      minCardWidth: 100,
      children: [
        _AnimatedActionButton(
          icon: Icons.map_outlined,
          label: 'Trip Planner',
          color: AppUiColors.of(context).primary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TripPlannerWrapper()),
          ),
        ),
        _AnimatedActionButton(
          icon: Icons.build_outlined,
          label: 'Service',
          color: Color(0xFFE8A87C),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MaintenanceScreen()),
          ),
        ),
        _AnimatedActionButton(
          icon: Icons.sync_rounded,
          label: 'Sync Now',
          color: AppUiColors.of(context).primary,
          onTap: onSync,
        ),
      ],
    ).appFadeSlideIn(index: 4);
  }
}

class _AnimatedActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AnimatedActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_AnimatedActionButton> createState() => _AnimatedActionButtonState();
}

class _AnimatedActionButtonState extends State<_AnimatedActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _rotateAnimation = Tween<double>(
      begin: 0,
      end: 0.1,
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
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            color: CockpitColors.surface,
            borderRadius: BorderRadius.circular(CockpitRadius.medium),
            border: Border.all(
              color: widget.color.withValues(alpha: 0.25),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RotationTransition(
                turns: _rotateAnimation,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 20),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CockpitTypography.label(
                  color: AppUiColors.of(context).text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionsShimmer extends StatelessWidget {
  const _QuickActionsShimmer();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        3,
        (index) => Expanded(
          child: Container(
            margin: EdgeInsets.only(right: index < 2 ? 12 : 0),
            height: 80,
            decoration: BoxDecoration(
              color: AppUiColors.of(context).surface,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncDialog extends StatefulWidget {
  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog>
    with SingleTickerProviderStateMixin {
  bool _isSyncing = false;
  String _status = 'Ready to sync';
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
      _status = 'Syncing data...';
    });

    final syncService = SyncService();
    final result = await syncService.performFullSync();

    setState(() {
      _isSyncing = false;
      _status = result['success'] ? 'Sync completed!' : 'Sync failed';
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
              'Sync with Web',
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
                      label: 'Cancel',
                      isSecondary: true,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _AnimatedButton(
                      label: 'Sync Now',
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

class _BatteryHealthShimmer extends StatelessWidget {
  const _BatteryHealthShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppUiColors.of(context).surface,
        borderRadius: BorderRadius.circular(24),
      ),
    );
  }
}

// =============================================================================
// Error & Empty banners — replace shimmer-on-error to surface lỗi rõ ràng.
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
    final raw = error.toString();
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
            Text(
              raw,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppUiColors.of(context).muted.withValues(alpha: 0.8),
                fontSize: 10,
                fontFamily: 'monospace',
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

class _MissingVehicleDataCard extends StatelessWidget {
  final String message;

  const _MissingVehicleDataCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppUiColors.of(context).surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppUiColors.of(context).warning.withValues(alpha: .35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: AppUiColors.of(context).warning,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppUiColors.of(context).text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EfficiencyReference extends StatelessWidget {
  const _EfficiencyReference({this.vehicle});
  final VehicleModel? vehicle;
  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    final valid =
        v != null &&
        v.hasEfficiencyData &&
        v.defaultEfficiency.isFinite &&
        v.defaultEfficiency > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(),
        SizedBox(height: 12),
        Text(
          'Thông số quãng đường cơ sở',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: 8),
        Text(
          valid
              ? '${v.defaultEfficiency.toStringAsFixed(2)} km / 1% pin'
              : 'Chưa có dữ liệu cấu hình',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        SizedBox(height: 8),
        Text(
          'Thông số cấu hình dùng để ước tính quãng đường. '
          'Không phải hiệu suất đo thực tế hay điểm đánh giá lái xe.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
