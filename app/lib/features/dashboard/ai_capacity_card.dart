import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/services/battery_capacity_service.dart';
import '../../data/repositories/ai_insights_repository.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import '../../data/repositories/charge_log_repository.dart';
import '../../data/repositories/trip_log_repository.dart';

/// ========================================================================
/// AI Capacity Card — Dashboard widget hiển thị dung lượng pin AI
/// ========================================================================
class AiCapacityCard extends ConsumerStatefulWidget {
  final VehicleModel vehicle;
  const AiCapacityCard({super.key, required this.vehicle});

  @override
  ConsumerState<AiCapacityCard> createState() => _AiCapacityCardState();
}

class _AiCapacityCardState extends ConsumerState<AiCapacityCard> {
  CapacityResult? _result;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _calculate();
  }

  @override
  void didUpdateWidget(covariant AiCapacityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vehicle.vehicleId != widget.vehicle.vehicleId ||
        oldWidget.vehicle.vinfastModelId != widget.vehicle.vinfastModelId) {
      _calculate();
    }
  }

  Future<void> _calculate() async {
    if (!widget.vehicle.hasModelLink) {
      setState(() {
        _loading = false;
        _error = false;
        _result = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = false;
    });

    try {
      final specRepo = ref.read(vehicleSpecRepositoryProvider);
      final spec = await specRepo.getSpec(widget.vehicle.vinfastModelId!);
      if (spec == null) {
        setState(() { _loading = false; _error = true; });
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

      if (mounted) {
        setState(() {
          _result = result;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _loading = false; _error = true; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Chưa link model → CTA
    if (!widget.vehicle.hasModelLink) {
      return _buildCtaCard();
    }

    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecoration(AppColors.info),
        child: const Center(
          child: SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(
              color: AppColors.info, strokeWidth: 2),
          ),
        ),
      );
    }

    if (_error || _result == null) {
      return const SizedBox.shrink();
    }

    return _buildCapacityCard(_result!);
  }

  Widget _buildCtaCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.link_rounded,
                color: AppColors.warning, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Liên kết model VinFast',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    )),
                Text('Để xem dung lượng pin AI chính xác',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    )),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textSecondary, size: 20),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildCapacityCard(CapacityResult r) {
    final alertColor = _alertColor(r.alertLevel);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(AppColors.info),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.battery_charging_full_rounded,
                    color: AppColors.info, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Dung lượng pin AI',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    )),
              ),
              _buildConfidenceBadge(r.confidence),
            ],
          ),
          const SizedBox(height: 16),

          // Main stats
          Row(
            children: [
              Expanded(child: _buildStatCell(
                '${r.usableCapacityWh.toStringAsFixed(0)} Wh',
                'Khả dụng',
                AppColors.primary,
              )),
              Container(width: 1, height: 40, color: AppColors.border),
              Expanded(child: _buildStatCell(
                '${r.usableCapacityAh.toStringAsFixed(1)} Ah',
                'Khả dụng',
                AppColors.info,
              )),
              Container(width: 1, height: 40, color: AppColors.border),
              Expanded(child: _buildStatCell(
                '${r.sohPercent.toStringAsFixed(1)}%',
                'SoH',
                alertColor,
              )),
            ],
          ),

          // Alert banner if needed
          if (r.alertLevel != SoHAlertLevel.none) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: alertColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: alertColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: alertColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(r.alertLevel.message,
                        style: TextStyle(
                          color: alertColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                ],
              ),
            ),
          ],

          // Observed charge power
          if (r.observedChargePowerW != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Công suất sạc quan sát',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    )),
                Text(
                  '${r.observedChargePowerW!.toStringAsFixed(0)}W / ${r.maxChargePowerW.toStringAsFixed(0)}W',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],

          // AI source indicator
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(
                r.usedAiInsight ? Icons.cloud_done_rounded : Icons.computer_rounded,
                color: AppColors.textTertiary,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                r.usedAiInsight ? 'AI insight' : 'On-device',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }

  Widget _buildConfidenceBadge(CapacityConfidence c) {
    final color = switch (c) {
      CapacityConfidence.high => AppColors.primary,
      CapacityConfidence.medium => AppColors.warning,
      CapacityConfidence.low => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(c.label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          )),
    );
  }

  Widget _buildStatCell(String value, String label, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            )),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            )),
      ],
    );
  }

  BoxDecoration _cardDecoration(Color accent) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: 0.06),
          AppColors.card,
        ],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accent.withValues(alpha: 0.15)),
    );
  }

  Color _alertColor(SoHAlertLevel level) {
    return switch (level) {
      SoHAlertLevel.none => AppColors.primary,
      SoHAlertLevel.mild => AppColors.warning,
      SoHAlertLevel.moderate => const Color(0xFFFF9800),
      SoHAlertLevel.severe => AppColors.error,
    };
  }
}
