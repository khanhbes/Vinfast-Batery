import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/services/battery_capacity_service.dart';
import '../../data/repositories/ai_insights_repository.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import '../../data/repositories/charge_log_repository.dart';
import '../../data/repositories/trip_log_repository.dart';

/// ========================================================================
/// VehicleDetailSheet — Bottom sheet chi tiết xe tái sử dụng
/// Dùng cho: Cài đặt (tap xe) + Trang chủ (tap xe)
/// ========================================================================
class VehicleDetailSheet extends ConsumerStatefulWidget {
  final VehicleModel vehicle;
  final VoidCallback? onSelect;

  const VehicleDetailSheet({super.key, required this.vehicle, this.onSelect});

  static Future<void> show(BuildContext context, VehicleModel vehicle,
      {VoidCallback? onSelect}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VehicleDetailSheet(vehicle: vehicle, onSelect: onSelect),
    );
  }

  @override
  ConsumerState<VehicleDetailSheet> createState() =>
      _VehicleDetailSheetState();
}

class _VehicleDetailSheetState extends ConsumerState<VehicleDetailSheet> {
  CapacityResult? _capacityResult;
  bool _loadingCapacity = true;

  @override
  void initState() {
    super.initState();
    _loadCapacity();
  }

  Future<void> _loadCapacity() async {
    if (!widget.vehicle.hasModelLink) {
      setState(() => _loadingCapacity = false);
      return;
    }
    try {
      final specRepo = ref.read(vehicleSpecRepositoryProvider);
      final spec = await specRepo.getSpec(widget.vehicle.vinfastModelId!);
      if (spec == null) {
        setState(() => _loadingCapacity = false);
        return;
      }
      final chargeLogs = await ref
          .read(chargeLogRepositoryProvider)
          .getChargeLogs(widget.vehicle.vehicleId);
      final trips = await ref
          .read(tripLogRepositoryProvider)
          .getRecentTrips(widget.vehicle.vehicleId);
      // Get AI insight from Firestore cache
      final insight = await ref
          .read(aiInsightsRepositoryProvider)
          .getInsight(widget.vehicle.vehicleId);
      final result = await BatteryCapacityService.calculate(
        vehicle: widget.vehicle,
        spec: spec,
        chargeLogs: chargeLogs,
        trips: trips,
        insight: insight,
      );
      if (mounted) setState(() { _capacityResult = result; _loadingCapacity = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingCapacity = false);
    }
  }

  Color get _avatarColor {
    final hex = widget.vehicle.avatarColor ?? '#00C853';
    try {
      return Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Avatar + Name
            Row(
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_avatarColor, _avatarColor.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _avatarColor.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.electric_moped_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.vehicleName.isNotEmpty ? v.vehicleName : v.vehicleId,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (v.hasModelLink)
                        Row(
                          children: [
                            const Icon(Icons.link_rounded,
                                color: AppColors.info, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              v.vinfastModelName ?? v.vinfastModelId ?? '',
                              style: const TextStyle(
                                color: AppColors.info,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      if (!v.hasModelLink)
                        const Text('Chưa liên kết model VinFast',
                            style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 12,
                            )),
                    ],
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 300.ms),

            const SizedBox(height: 20),

            // Main stats grid
            Row(
              children: [
                _buildStatTile(Icons.battery_std_rounded, '${v.lastBatteryPercent}%',
                    'Pin hiện tại',
                    v.lastBatteryPercent > 50 ? AppColors.primary
                        : v.lastBatteryPercent > 20 ? AppColors.warning
                        : AppColors.error),
                const SizedBox(width: 10),
                _buildStatTile(Icons.speed_rounded, '${v.currentOdo} km',
                    'ODO', AppColors.info),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildStatTile(Icons.battery_charging_full_rounded,
                    '${v.totalCharges} lần', 'Tổng sạc', AppColors.primary),
                const SizedBox(width: 10),
                _buildStatTile(Icons.route_rounded, '${v.totalTrips} lần',
                    'Tổng chuyến', AppColors.warning),
              ],
            ).animate().fadeIn(delay: 100.ms),

            // SoH / Capacity
            if (_loadingCapacity) ...[
              const SizedBox(height: 16),
              const Center(
                child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: AppColors.info, strokeWidth: 2)),
              ),
            ] else if (_capacityResult != null) ...[
              const SizedBox(height: 16),
              _buildCapacitySection(_capacityResult!),
            ],

            // Select button
            if (widget.onSelect != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    widget.onSelect!();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 20),
                  label: const Text('Chọn xe này',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ).animate().fadeIn(delay: 200.ms),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value,
                        style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                  Text(label,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapacitySection(CapacityResult r) {
    final alertColor = switch (r.alertLevel) {
      SoHAlertLevel.none => AppColors.primary,
      SoHAlertLevel.mild => AppColors.warning,
      SoHAlertLevel.moderate => const Color(0xFFFF9800),
      SoHAlertLevel.severe => AppColors.error,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.info.withValues(alpha: 0.06), AppColors.card],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.battery_full_rounded,
                  color: AppColors.info, size: 18),
              const SizedBox(width: 8),
              const Text('Dung lượng pin AI',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
              const Spacer(),
              Text('SoH ${r.sohPercent.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: alertColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: r.sohPercent / 100,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(alertColor),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Khả dụng: ${r.usableCapacityWh.toStringAsFixed(0)} Wh',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  )),
              if (r.observedChargePowerW != null)
                Text('Sạc: ${r.observedChargePowerW!.toStringAsFixed(0)}W',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    )),
            ],
          ),
          if (r.alertLevel != SoHAlertLevel.none) ...[
            const SizedBox(height: 8),
            Text(r.alertLevel.message,
                style: TextStyle(
                  color: alertColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 150.ms);
  }
}
