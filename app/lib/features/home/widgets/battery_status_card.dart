import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/vehicle_model.dart';

/// ========================================================================
/// Battery Status Card V2 — Thẻ pin chính lấy cảm hứng từ Battery Pro
/// Thiết kế màu xanh đậm nổi bật, hiển thị % pin + quãng đường dự kiến
/// ========================================================================

class BatteryStatusCard extends StatelessWidget {
  final VehicleModel vehicle;

  const BatteryStatusCard({super.key, required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final percent = vehicle.lastBatteryPercent;
    final estimatedRange = (percent * vehicle.defaultEfficiency).toStringAsFixed(0);

    return Column(
      children: [
        // ── Main Battery Card ──
        Container(
          width: double.infinity,
          height: 240,
          decoration: BoxDecoration(
            color: AppColors.vinfastBlue,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: AppColors.vinfastBlue.withValues(alpha: 0.25),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Abstract background circles
              Positioned(
                top: -40,
                right: -30,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                bottom: -30,
                left: -30,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.vinfastRed.withValues(alpha: 0.15),
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TRẠNG THÁI PIN',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              percent >= 50 ? 'Sẵn sàng' : 'Pin yếu',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            percent < 20
                                ? Icons.battery_alert_rounded
                                : Icons.battery_full_rounded,
                            color: percent < 20
                                ? AppColors.vinfastRed
                                : Colors.white,
                            size: 28,
                          ),
                        ),
                      ],
                    ),

                    // Bottom row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$percent',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 64,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -3,
                                height: 1,
                              ),
                            ),
                            Text(
                              '%',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'QUÃNG ĐƯỜNG',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '~$estimatedRange',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'km',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.95, 0.95)),

        const SizedBox(height: 16),

        // ── Quick Stats Row ──
        Row(
          children: [
            Expanded(
              child: _QuickStat(
                icon: Icons.thermostat_rounded,
                label: 'Nhiệt độ',
                value: '32°C',
                color: Colors.orange,
                bgColor: AppColors.warningBg,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickStat(
                icon: Icons.shield_rounded,
                label: 'Sức khỏe',
                value: '${vehicle.stateOfHealth.toStringAsFixed(0)}%',
                color: AppColors.success,
                bgColor: AppColors.successBg,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickStat(
                icon: Icons.speed_rounded,
                label: 'ODO',
                value: '${vehicle.currentOdo} km',
                color: AppColors.info,
                bgColor: AppColors.infoBg,
              ),
            ),
          ],
        ).animate().fadeIn(delay: 300.ms),
      ],
    );
  }
}

class _QuickStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color bgColor;

  const _QuickStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
