import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// ========================================================================
/// Session Summary Modal V2 — Tóm tắt sau mỗi chuyến đi/sạc
/// Thiết kế rounded 40px, nền trắng, gợi ý hành động tiếp theo
/// ========================================================================

class SessionSummaryData {
  final String type; // 'drive' | 'charge'
  final double? distance;
  final int? energyConsumed;
  final int? energyGained;
  final int duration; // minutes
  final DateTime timestamp;
  final double? efficiency; // Wh/km

  const SessionSummaryData({
    required this.type,
    this.distance,
    this.energyConsumed,
    this.energyGained,
    required this.duration,
    required this.timestamp,
    this.efficiency,
  });
}

class SessionSummaryModal extends StatelessWidget {
  final SessionSummaryData summary;
  final VoidCallback onClose;

  const SessionSummaryModal({
    super.key,
    required this.summary,
    required this.onClose,
  });

  static Future<void> show(BuildContext context, SessionSummaryData summary) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: AppColors.textPrimary.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (ctx, a1, a2, child) {
        return Transform.scale(
          scale: 0.9 + (0.1 * Curves.easeOutBack.transform(a1.value)),
          child: Opacity(
            opacity: a1.value,
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, a1, a2) => Center(
        child: SessionSummaryModal(
          summary: summary,
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDrive = summary.type == 'drive';

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.successBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    isDrive
                        ? Icons.navigation_rounded
                        : Icons.bolt_rounded,
                    color: AppColors.success,
                    size: 28,
                  ),
                ),
                GestureDetector(
                  onTap: onClose,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.close_rounded,
                      color: AppColors.textTertiary,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Title
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isDrive ? 'Chuyến đi hoàn tất!' : 'Đã sạc xong!',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lúc ${_formatTime(summary.timestamp)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Stats grid
            Row(
              children: [
                if (isDrive) ...[
                  Expanded(
                    child: _StatItem(
                      icon: Icons.navigation_rounded,
                      label: 'Quãng đường',
                      value: '${summary.distance?.toStringAsFixed(1) ?? "0"} km',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StatItem(
                      icon: Icons.bolt_rounded,
                      label: 'Tiêu thụ',
                      value: '${summary.energyConsumed ?? 0}%',
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: _StatItem(
                      icon: Icons.bolt_rounded,
                      label: 'Đã sạc',
                      value: '${summary.energyGained ?? 0}%',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StatItem(
                      icon: Icons.timer_rounded,
                      label: 'Thời gian',
                      value: '${summary.duration} phút',
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatItem(
                    icon: Icons.timer_rounded,
                    label: 'Thời gian',
                    value: '${summary.duration} phút',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _StatItem(
                    icon: Icons.trending_up_rounded,
                    label: 'Hiệu suất',
                    value: '${summary.efficiency?.toStringAsFixed(0) ?? "N/A"} Wh/km',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Suggestion card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.vinfastBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.vinfastBlue.withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GỢI Ý TIẾP THEO',
                    style: TextStyle(
                      color: AppColors.vinfastBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isDrive
                        ? 'Chuyến đi hiệu quả! Bạn nên sạc pin lên 80% để sẵn sàng cho chuyến tiếp theo.'
                        : 'Pin đã đầy! Hãy rút sạc để bảo vệ tuổi thọ pin lâu dài.',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Close button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.vinfastBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Tuyệt vời',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min';
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.textTertiary, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
