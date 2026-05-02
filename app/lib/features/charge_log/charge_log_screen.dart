import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/charge_log_model.dart';
import '../../data/repositories/charge_log_repository.dart';
import 'add_charge_log_modal.dart';

// =============================================================================
// Charge Log Screen - Lịch sử sạc đầy đủ
// =============================================================================

class ChargeLogScreen extends ConsumerWidget {
  const ChargeLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    final logsAsync = ref.watch(chargeLogsProvider(vehicleId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lịch sử sạc',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Tất cả nhật ký sạc điện',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Add button
                  IconButton(
                    onPressed: () async {
                      final result = await AddChargeLogModal.show(
                        context,
                        vehicleId,
                      );
                      if (result == true) {
                        ref.invalidate(chargeLogsProvider(vehicleId));
                        ref.invalidate(vehicleStatsProvider(vehicleId));
                        ref.invalidate(vehicleProvider(vehicleId));
                      }
                    },
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms),

            const SizedBox(height: 8),

            // ── Summary Bar ──
            logsAsync.when(
              data: (logs) => _buildSummaryBar(logs),
              loading: () => const SizedBox(height: 50),
              error: (_, _) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 8),

            // ── Log List ──
            Expanded(
              child: logsAsync.when(
                data: (logs) {
                  if (logs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.battery_alert_rounded,
                            color: AppColors.textTertiary,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Chưa có nhật ký sạc',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Bắt đầu ghi lại chu kỳ sạc của bạn',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.surface,
                    onRefresh: () async {
                      ref.invalidate(chargeLogsProvider(vehicleId));
                    },
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final showDate =
                            index == 0 ||
                            _isDifferentDay(
                              logs[index - 1].startTime,
                              log.startTime,
                            );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showDate)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: index == 0 ? 4 : 16,
                                  bottom: 8,
                                ),
                                child: Text(
                                  _formatDateHeader(log.startTime),
                                  style: const TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            _ChargeLogDetailCard(
                                  log: log,
                                  onDelete: () => _confirmDelete(
                                    context,
                                    ref,
                                    log,
                                    vehicleId,
                                  ),
                                )
                                .animate()
                                .fadeIn(delay: (100 + index * 50).ms)
                                .slideX(begin: 0.1),
                          ],
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Lỗi: $e',
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar(List<ChargeLogModel> logs) {
    final totalGain = logs.fold<int>(0, (s, l) => s + l.chargeGain);
    final avgDuration = logs.isEmpty
        ? 0.0
        : logs.fold<double>(
                0,
                (s, l) => s + l.chargeDuration.inMinutes / 60.0,
              ) /
              logs.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SummaryItem(
            label: 'Tổng lần',
            value: '${logs.length}',
            icon: Icons.repeat_rounded,
          ),
          Container(width: 1, height: 30, color: AppColors.border),
          _SummaryItem(
            label: 'Tổng nạp',
            value: '$totalGain%',
            icon: Icons.bolt_rounded,
          ),
          Container(width: 1, height: 30, color: AppColors.border),
          _SummaryItem(
            label: 'Sạc TB',
            value: '${avgDuration.toStringAsFixed(1)}h',
            icon: Icons.timer_outlined,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2);
  }

  bool _isDifferentDay(DateTime a, DateTime b) {
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);

    if (dateDay == today) return 'HÔM NAY';
    if (dateDay == today.subtract(const Duration(days: 1))) return 'HÔM QUA';
    return DateFormat('dd MMMM yyyy').format(date).toUpperCase();
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ChargeLogModel log,
    String vehicleId,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Xóa nhật ký sạc?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Bạn có chắc muốn xóa nhật ký sạc ${log.startBatteryPercent}% → ${log.endBatteryPercent}%?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Huỷ',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(chargeLogRepositoryProvider)
                  .deleteChargeLog(log.logId!);
              ref.invalidate(chargeLogsProvider(vehicleId));
              ref.invalidate(vehicleStatsProvider(vehicleId));
            },
            child: const Text('Xóa', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Summary Item
// =============================================================================

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 16),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
        ),
      ],
    );
  }
}

// =============================================================================
// Detail Card
// =============================================================================

class _ChargeLogDetailCard extends StatelessWidget {
  final ChargeLogModel log;
  final VoidCallback onDelete;

  const _ChargeLogDetailCard({required this.log, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');
    final chargeGain = log.chargeGain;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Top row
          Row(
            children: [
              // Battery progress visual
              _BatteryProgressBar(
                start: log.startBatteryPercent,
                end: log.endBatteryPercent,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${log.startBatteryPercent}%',
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: AppColors.textTertiary,
                            size: 16,
                          ),
                        ),
                        Text(
                          '${log.endBatteryPercent}%',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '+$chargeGain%',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Time info
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          color: AppColors.textTertiary,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${timeFormat.format(log.startTime)} — ${timeFormat.format(log.endTime)}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            log.durationText,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 10),

          // Bottom row
          Row(
            children: [
              const Icon(Icons.speed_rounded, color: AppColors.info, size: 16),
              const SizedBox(width: 6),
              Text(
                'ODO: ${log.odoAtCharge} km',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.error,
                        size: 14,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Xóa',
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Battery Progress Bar (compact)
// =============================================================================

class _BatteryProgressBar extends StatelessWidget {
  final int start;
  final int end;

  const _BatteryProgressBar({required this.start, required this.end});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 50,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: end / 100,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [AppColors.error, AppColors.warning, AppColors.primary],
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}
