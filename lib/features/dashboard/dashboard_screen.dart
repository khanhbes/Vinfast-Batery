import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../data/models/trip_log_model.dart';
import '../../data/services/battery_logic_service.dart';
import '../../data/services/trip_tracking_service.dart';
import '../../data/services/charge_tracking_service.dart';
import '../../data/services/maintenance_reminder_service.dart';
import '../../data/services/background_service_config.dart';
import '../../data/repositories/charge_log_repository.dart';
import '../../data/repositories/trip_log_repository.dart';
import '../../data/repositories/maintenance_repository.dart';
import '../../main.dart';
import '../home/home_screen.dart';
import 'add_manual_trip_modal.dart';
import 'ai_capacity_card.dart';
import 'route_prediction_card.dart';
import '../../core/widgets/quick_action_menu.dart';
import '../settings/guide_screen.dart';
import '../settings/ai_functions_screen.dart';
import '../charge_log/add_charge_log_modal.dart';

// =============================================================================
// Stable Dashboard Providers (thay cho inline FutureProvider)
// =============================================================================

/// Trips gần nhất cho SoH card — family provider theo vehicleId
final dashboardTripsProvider =
    FutureProvider.family<List<TripLogModel>, String>((ref, vehicleId) {
  if (vehicleId.isEmpty) return Future.value([]);
  return ref.watch(tripLogRepositoryProvider).getRecentTrips(vehicleId);
});

/// Pending maintenance tasks — family provider theo vehicleId
final dashboardMaintenanceProvider =
    FutureProvider.family<List<dynamic>, String>((ref, vehicleId) {
  if (vehicleId.isEmpty) return Future.value([]);
  return ref.watch(maintenanceRepositoryProvider).getPendingTasks(vehicleId);
});

// =============================================================================
// Dashboard Screen — Trung tâm điều khiển
// =============================================================================

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _tripService = TripTrackingService();
  final _chargeService = ChargeTrackingService();
  PayloadType _selectedPayload = PayloadType.onePerson;
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _tripService.onUpdate = () => setState(() {});
    _chargeService.onUpdate = () => setState(() {});
    // Timer refresh UI mỗi 1 giây khi tracking
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_tripService.isTracking || _chargeService.isCharging) {
        setState(() {});
      }
    });
    // Kiểm tra crash recovery sau frame đầu tiên
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRecovery());
  }

  Future<void> _checkRecovery() async {
    final recovery = ref.read(pendingRecoveryProvider);
    if (recovery == null) return;

    // Clear provider để không hiện lại
    ref.read(pendingRecoveryProvider.notifier).state = null;

    if (recovery == 'charge') {
      final hasSession = await _chargeService.checkAndRecover();
      if (hasSession && mounted) {
        _showRecoveryDialog(
          title: 'Phiên sạc chưa kết thúc',
          message: 'Phát hiện phiên sạc đang dở dang (${_chargeService.currentBattery}%). Bạn muốn tiếp tục hay hủy?',
          onResume: () {
            _chargeService.resumeCharging();
            BackgroundServiceConfig.startService().then((_) {
              BackgroundServiceConfig.sendCommand('startCharge');
            });
            setState(() {});
          },
          onDiscard: () async {
            await _chargeService.discardRecovery();
            setState(() {});
          },
        );
      }
    } else if (recovery == 'trip') {
      final hasSession = await _tripService.checkAndRecover();
      if (hasSession && mounted) {
        _showRecoveryDialog(
          title: 'Chuyến đi chưa kết thúc',
          message: 'Phát hiện chuyến đi đang dở dang. Bạn muốn tiếp tục hay hủy?',
          onResume: () async {
            final started = await _tripService.resumeTrip();
            if (started) {
              await BackgroundServiceConfig.startService();
              BackgroundServiceConfig.sendCommand('startTrip');
            }
            if (!started && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Không thể bật GPS để tiếp tục chuyến đi.'),
                  backgroundColor: AppColors.error,
                ),
              );
            }
            setState(() {});
          },
          onDiscard: () async {
            await _tripService.discardRecovery();
            setState(() {});
          },
        );
      }
    }
  }

  void _showRecoveryDialog({
    required String title,
    required String message,
    required VoidCallback onResume,
    required VoidCallback onDiscard,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.restore_rounded, color: AppColors.warning, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          ],
        ),
        content: Text(message,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            )),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onDiscard();
            },
            child: const Text('Hủy phiên',
                style: TextStyle(color: AppColors.error)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onResume();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Tiếp tục',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    final vehicleAsync = ref.watch(vehicleProvider(vehicleId));

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: QuickActionFab(
        vehicleId: vehicleId.isEmpty ? null : vehicleId,
        onAction: (action) => _handleQuickAction(action, vehicleAsync, vehicleId),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryGreen,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(vehicleProvider(vehicleId));
            ref.invalidate(dashboardTripsProvider(vehicleId));
            ref.invalidate(dashboardMaintenanceProvider(vehicleId));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                _buildHeader(),
                const SizedBox(height: 20),

                // ── Tracking Active Banner ──
                if (_tripService.isTracking) _buildTripActive(),
                if (_chargeService.isCharging) _buildChargeActive(),

                // ── SoH Card ──
                if (!_tripService.isTracking && !_chargeService.isCharging)
                  vehicleAsync.when(
                    data: (v) => v != null ? _buildSoHCard(v, vehicleId) : const SizedBox(),
                    loading: () => const LoadingSkeleton(layout: SkeletonLayout.card),
                    error: (e, __) => ErrorState.fromError(
                      error: e,
                      prefix: 'Không tải được dữ liệu xe',
                      onRetry: () => ref.invalidate(vehicleProvider(vehicleId)),
                    ),
                  ),

                // ── AI Capacity Card ──
                if (!_tripService.isTracking && !_chargeService.isCharging)
                  vehicleAsync.when(
                    data: (v) => v != null
                        ? Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: AiCapacityCard(vehicle: v),
                          )
                        : const SizedBox(),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),

                const SizedBox(height: 16),

                // ── Quick Actions ──
                if (!_tripService.isTracking && !_chargeService.isCharging) ...[
                  _buildQuickActions(vehicleAsync, vehicleId),
                  const SizedBox(height: 24),
                  // ── Route Prediction ──
                  const RoutePredictionCard(),
                  const SizedBox(height: 24),
                ],

                // ── Maintenance sắp đến ──
                _buildMaintenanceSection(vehicleId, vehicleAsync),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ──

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryGreen, AppColors.accentGreen],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.electric_bolt_rounded,
              color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dashboard',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  )),
              Text('Trung tâm điều khiển',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }

  // ── SoH Card ──

  Widget _buildSoHCard(dynamic vehicle, String vehicleId) {
    final recentTripsAsync = ref.watch(dashboardTripsProvider(vehicleId));

    return recentTripsAsync.when(
      data: (trips) {
        final soh = BatteryLogicService.calculateSoH(
          trips,
          defaultEfficiency: vehicle.defaultEfficiency,
        );
        final status = BatteryLogicService.getSoHStatus(soh);
        final efficiency = BatteryLogicService.avgEfficiency(trips);

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryGreen.withValues(alpha: 0.08),
                AppColors.card,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primaryGreen.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.monitor_heart_rounded,
                      color: AppColors.primaryGreen, size: 20),
                  const SizedBox(width: 8),
                  const Text('Sức khỏe pin (SoH)',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      )),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _sohColor(soh).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${status.emoji} ${status.label}',
                      style: TextStyle(
                        color: _sohColor(soh),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // SoH gauge
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 130,
                    height: 130,
                    child: CircularProgressIndicator(
                      value: soh / 100,
                      strokeWidth: 10,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation(_sohColor(soh)),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        '${soh.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: _sohColor(soh),
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text('SoH',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          )),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _miniStat(Icons.speed_rounded, 'ODO',
                      '${vehicle.currentOdo} km', AppColors.info),
                  _miniStat(Icons.battery_std_rounded, 'Pin',
                      '${vehicle.currentBattery}%', AppColors.primaryGreen),
                  _miniStat(Icons.trending_up_rounded, 'Hiệu suất',
                      '${efficiency.toStringAsFixed(2)} km/%',
                      AppColors.warning),
                ],
              ),
              if (trips.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Cần ít nhất 1 chuyến đi để tính SoH chính xác',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.15);
      },
      loading: () => const LoadingSkeleton(layout: SkeletonLayout.card),
      error: (e, __) => ErrorState.fromError(
        error: e,
        prefix: 'Không tải được dữ liệu SoH',
        onRetry: () => ref.invalidate(vehicleProvider(vehicleId)),
      ),
    );
  }

  Color _sohColor(double soh) {
    if (soh >= 80) return AppColors.primaryGreen;
    if (soh >= 60) return AppColors.warning;
    if (soh >= 40) return const Color(0xFFFF9800);
    return AppColors.error;
  }

  Widget _miniStat(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            )),
        Text(label,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
            )),
      ],
    );
  }

  // ── Quick Actions ──

  Widget _buildQuickActions(AsyncValue vehicleAsync, String vehicleId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Hành động nhanh',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: 12),

        // Payload selector
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.people_alt_rounded,
                  color: AppColors.textSecondary, size: 18),
              const SizedBox(width: 10),
              const Text('Tải trọng:',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  )),
              const Spacer(),
              ...PayloadType.values.map((p) {
                final isSelected = p == _selectedPayload;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedPayload = p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryGreen.withValues(alpha: 0.15)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryGreen
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        p.label,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.primaryGreen
                              : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.navigation_rounded,
                label: 'Bắt đầu đi',
                color: AppColors.info,
                onTap: () => _startTrip(vehicleAsync, vehicleId),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                icon: Icons.bolt_rounded,
                label: 'Bắt đầu sạc',
                color: AppColors.primaryGreen,
                onTap: () => _showChargeTargetDialog(vehicleAsync, vehicleId),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Manual trip button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              final vehicle = vehicleAsync.value;
              if (vehicle == null) return;
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => AddManualTripModal(vehicle: vehicle),
              ).then((_) {
                ref.invalidate(vehicleProvider(vehicleId));
              });
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.edit_note_rounded, size: 20),
            label: const Text('Nhập chuyến đi thủ công',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 300.ms);
  }

  // ── Trip Active Banner ──

  Widget _buildTripActive() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.info.withValues(alpha: 0.1),
            AppColors.card,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.navigation_rounded,
                    color: AppColors.info, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Đang di chuyển 🛵',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        )),
                    Text(_tripService.payload.label,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        )),
                  ],
                ),
              ),
              Text(_tripService.elapsedText,
                  style: const TextStyle(
                    color: AppColors.info,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  )),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _trackingStat('Quãng đường',
                  '${_tripService.totalDistance.toStringAsFixed(1)} km',
                  AppColors.info),
              _trackingStat('Pin',
                  '${_tripService.currentBattery}%',
                  AppColors.primaryGreen),
              _trackingStat('Tiêu thụ',
                  '-${_tripService.batteryConsumed}%',
                  AppColors.warning),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _stopTrip,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Kết thúc chuyến đi',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Charge Active Banner ──

  Widget _buildChargeActive() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryGreen.withValues(alpha: 0.1),
            AppColors.card,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bolt_rounded,
                    color: AppColors.primaryGreen, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Đang sạc pin ⚡',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    )),
              ),
              Text(_chargeService.elapsedText,
                  style: const TextStyle(
                    color: AppColors.primaryGreen,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  )),
            ],
          ),
          const SizedBox(height: 16),
          // Battery progress
          Stack(
            children: [
              Container(
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                height: 20,
                width: MediaQuery.of(context).size.width *
                    (_chargeService.currentBattery / 100) *
                    0.78,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryGreen, AppColors.accentGreen],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Positioned.fill(
                child: Center(
                  child: Text(
                    '${_chargeService.currentBattery}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _trackingStat('Đã nạp',
                  '+${_chargeService.batteryGained}%', AppColors.primaryGreen),
              _trackingStat('Mục tiêu',
                  '${_chargeService.targetBattery}%', AppColors.warning),
              _trackingStat('ETA',
                  _chargeService.etaText, AppColors.info),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _stopCharge,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.power_off_rounded),
              label: const Text('Ngắt sạc',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trackingStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            )),
        Text(label,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
            )),
      ],
    );
  }

  // ── Maintenance Section ──

  Widget _buildMaintenanceSection(String vehicleId, AsyncValue vehicleAsync) {
    final tasksAsync = ref.watch(dashboardMaintenanceProvider(vehicleId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.build_circle_rounded,
                color: AppColors.warning, size: 18),
            const SizedBox(width: 8),
            const Text('Bảo dưỡng sắp đến',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
        const SizedBox(height: 12),
        tasksAsync.when(
          data: (tasks) {
            final currentOdo = vehicleAsync.when(
              data: (v) => v?.currentOdo ?? 0,
              loading: () => 0,
              error: (_, __) => 0,
            );
            final dueSoon = tasks.where((t) => t.isDueSoon(currentOdo)).toList();

            if (dueSoon.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: AppColors.primaryGreen, size: 18),
                    SizedBox(width: 8),
                    Text('Không có mốc bảo dưỡng nào sắp đến',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        )),
                  ],
                ),
              );
            }

            return Column(
              children: dueSoon.map((task) {
                final remaining = task.remainingKm(currentOdo);
                final isOverdue = remaining <= 0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isOverdue
                        ? AppColors.error.withValues(alpha: 0.08)
                        : AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isOverdue
                          ? AppColors.error.withValues(alpha: 0.3)
                          : AppColors.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOverdue
                            ? Icons.warning_rounded
                            : Icons.schedule_rounded,
                        color: isOverdue ? AppColors.error : AppColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(task.title,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                )),
                            Text(
                              isOverdue
                                  ? 'Quá hạn ${(-remaining)} km!'
                                  : 'Còn $remaining km nữa',
                              style: TextStyle(
                                color: isOverdue
                                    ? AppColors.error
                                    : AppColors.warning,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${task.targetOdo} km',
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
          loading: () => _shimmer(),
          error: (e, __) => ErrorState(
            message: 'Không tải được lịch bảo dưỡng: $e',
            onRetry: () => ref.invalidate(dashboardMaintenanceProvider(vehicleId)),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 400.ms);
  }

  // ── Actions ──

  void _handleQuickAction(QuickAction action, AsyncValue vehicleAsync, String vehicleId) {
    switch (action) {
      case QuickAction.startTrip:
        _startTrip(vehicleAsync, vehicleId);
      case QuickAction.startCharge:
        _showChargeTargetDialog(vehicleAsync, vehicleId);
      case QuickAction.manualTrip:
        final vehicle = vehicleAsync.value;
        if (vehicle == null) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => AddManualTripModal(vehicle: vehicle),
        ).then((_) => ref.invalidate(vehicleProvider(vehicleId)));
      case QuickAction.addCharge:
        AddChargeLogModal.show(context, vehicleId).then((result) {
          if (result == true) {
            ref.invalidate(vehicleProvider(vehicleId));
            ref.invalidate(chargeLogsProvider(vehicleId));
          }
        });
      case QuickAction.routePrediction:
        // Scroll to RoutePredictionCard (already visible on Dashboard)
        break;
      case QuickAction.aiFunctions:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AiFunctionsScreen()),
        );
      case QuickAction.guide:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GuideScreen()),
        );
    }
  }

  Future<void> _startTrip(AsyncValue vehicleAsync, String vehicleId) async {
    final vehicle = vehicleAsync.value;
    if (vehicle == null) return;

    final started = await _tripService.startTrip(
      vehicleId: vehicleId,
      payload: _selectedPayload,
      currentBattery: vehicle.currentBattery,
      currentOdo: vehicle.currentOdo,
      defaultEfficiency: vehicle.defaultEfficiency,
    );

    if (started) {
      await BackgroundServiceConfig.startService();
      BackgroundServiceConfig.sendCommand('startTrip');
    }

    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể bật GPS. Kiểm tra quyền truy cập vị trí.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _startCharge(AsyncValue vehicleAsync, String vehicleId, {int targetPercent = 80}) async {
    final vehicle = vehicleAsync.value;
    if (vehicle == null) return;

    // Tính adaptive charge rate từ lịch sử (fallback 0.38 nếu chưa có log)
    double adaptiveRate = 0.38;
    try {
      final repo = ref.read(chargeLogRepositoryProvider);
      final logs = await repo.getChargeLogs(vehicleId);
      if (logs.isNotEmpty) {
        final calculatedRate = BatteryLogicService.avgChargeRate(logs);
        if (calculatedRate > 0) {
          adaptiveRate = calculatedRate;
        }
      }
    } catch (_) {}

    await _chargeService.startCharging(
      vehicleId: vehicleId,
      currentBattery: vehicle.currentBattery,
      currentOdo: vehicle.currentOdo,
      chargeRatePerMin: adaptiveRate,
      targetBatteryPercent: targetPercent,
    );

    await BackgroundServiceConfig.startService();
    BackgroundServiceConfig.sendCommand('startCharge');

    setState(() {});
  }

  void _showChargeTargetDialog(AsyncValue vehicleAsync, String vehicleId) {
    int selectedTarget = 80;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.bolt_rounded, color: AppColors.primaryGreen, size: 22),
              SizedBox(width: 8),
              Text('Mục tiêu sạc',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Chọn % pin mục tiêu:',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [80, 90, 100].map((t) {
                  final sel = t == selectedTarget;
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedTarget = t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.primaryGreen.withValues(alpha: 0.15) : AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: sel ? AppColors.primaryGreen : AppColors.border,
                          width: sel ? 2 : 1,
                        ),
                      ),
                      child: Text('$t%',
                        style: TextStyle(
                          color: sel ? AppColors.primaryGreen : AppColors.textSecondary,
                          fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Hủy', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _startCharge(vehicleAsync, vehicleId, targetPercent: selectedTarget);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Bắt đầu sạc',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _stopTrip() async {
    // Show confirmation
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Kết thúc chuyến đi?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _confirmRow('Quãng đường', '${_tripService.totalDistance.toStringAsFixed(1)} km'),
            _confirmRow('Pin tiêu thụ', '-${_tripService.batteryConsumed}%'),
            _confirmRow('Thời gian', _tripService.elapsedText),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Tiếp tục đi', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Kết thúc', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _tripService.stopTrip();
    BackgroundServiceConfig.sendCommand('stopTrip');
    final vehicleId = ref.read(selectedVehicleIdProvider);
    ref.invalidate(vehicleProvider(vehicleId));
    setState(() {});

    // Kiểm tra nhắc bảo dưỡng sau khi kết thúc chuyến đi
    _triggerMaintenanceCheck(vehicleId);
  }

  Future<void> _stopCharge() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Ngắt sạc?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _confirmRow('Pin hiện tại', '${_chargeService.currentBattery}%'),
            _confirmRow('Mục tiêu', '${_chargeService.targetBattery}%'),
            _confirmRow('Đã nạp', '+${_chargeService.batteryGained}%'),
            _confirmRow('Thời gian', _chargeService.elapsedText),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Tiếp tục sạc', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Ngắt sạc', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _chargeService.stopCharging();
    BackgroundServiceConfig.sendCommand('stopCharge');
    final vehicleId = ref.read(selectedVehicleIdProvider);
    ref.invalidate(vehicleProvider(vehicleId));
    ref.invalidate(chargeLogsProvider(vehicleId));
    setState(() {});

    // Kiểm tra nhắc bảo dưỡng sau khi kết thúc sạc
    _triggerMaintenanceCheck(vehicleId);
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  void _triggerMaintenanceCheck(String vehicleId) async {
    try {
      final vehicle = await ref.read(chargeLogRepositoryProvider).getVehicle(vehicleId);
      if (vehicle != null) {
        MaintenanceReminderService().checkAndNotify(
          vehicleId: vehicleId,
          currentOdo: vehicle.currentOdo,
        );
      }
    } catch (_) {}
  }

  Widget _shimmer() {
    return const LoadingSkeleton(layout: SkeletonLayout.card);
  }
}

// ── Action Button Widget ──

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.8)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }
}
