import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_ui_colors.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/loading_skeleton.dart';
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
    final colors = AppUiColors.of(context);
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    final logsAsync = ref.watch(chargeLogsProvider(vehicleId));

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            AppScreenHeader(
              icon: Icons.history_rounded,
              title: 'Lịch sử sạc',
              subtitle: 'Tất cả nhật ký sạc điện',
              iconColor: colors.emerald,
              actions: [
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
                      color: colors.primary,
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

            const SizedBox(height: 8),

            // ── Summary Bar ──
            logsAsync.when(
              data: (logs) => _buildSummaryBar(context, logs),
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
                      child: EmptyState(
                        icon: Icons.history_rounded,
                        title: 'Chưa có nhật ký sạc',
                        message: 'Bắt đầu ghi lại chu kỳ sạc của bạn',
                        actionLabel: 'Thêm nhật ký sạc',
                        onAction: () async {
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
                                  style: TextStyle(
                                    color: colors.muted,
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
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: LoadingSkeleton(layout: SkeletonLayout.list),
                ),
                error: (e, _) => ErrorState.fromError(
                  error: e,
                  prefix: 'Không tải được nhật ký sạc',
                  onRetry: () => ref.invalidate(chargeLogsProvider(vehicleId)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar(BuildContext context, List<ChargeLogModel> logs) {
    final colors = AppUiColors.of(context);
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
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SummaryItem(
            label: 'Tổng lần',
            value: '${logs.length}',
            icon: Icons.repeat_rounded,
          ),
          Container(width: 1, height: 30, color: colors.border),
          _SummaryItem(
            label: 'Tổng nạp',
            value: '$totalGain%',
            icon: Icons.bolt_rounded,
          ),
          Container(width: 1, height: 30, color: colors.border),
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
    final colors = AppUiColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Xóa nhật ký sạc?',
          style: TextStyle(color: colors.text, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Bạn có chắc muốn xóa nhật ký sạc ${log.startBatteryPercent}% → ${log.endBatteryPercent}%?',
          style: TextStyle(color: colors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Huỷ',
              style: TextStyle(color: colors.muted),
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
            child: Text(
              'Xóa',
              style: TextStyle(
                color: colors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
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
    final colors = AppUiColors.of(context);
    return Column(
      children: [
        Icon(icon, color: colors.emerald, size: 16),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: colors.text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: colors.muted, fontSize: 11),
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
    final colors = AppUiColors.of(context);
    final timeFormat = DateFormat('HH:mm');
    final chargeGain = log.chargeGain;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
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
                          style: TextStyle(
                            color: colors.danger,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: colors.muted,
                            size: 16,
                          ),
                        ),
                        Text(
                          '${log.endBatteryPercent}%',
                          style: TextStyle(
                            color: colors.emerald,
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
                            color: colors.emerald.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '+$chargeGain%',
                            style: TextStyle(
                              color: colors.emerald,
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
                        Icon(
                          Icons.schedule_rounded,
                          color: colors.muted,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${timeFormat.format(log.startTime)} — ${timeFormat.format(log.endTime)}',
                          style: TextStyle(
                            color: colors.muted,
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
                            color: colors.border.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            log.durationText,
                            style: TextStyle(
                              color: colors.text,
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
          Divider(color: colors.border, height: 1),
          const SizedBox(height: 10),

          // Bottom row
          Row(
            children: [
              Icon(Icons.speed_rounded, color: colors.info, size: 16),
              const SizedBox(width: 6),
              Text(
                'ODO: ${log.odoAtCharge} km',
                style: TextStyle(
                  color: colors.muted,
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
                    color: colors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        color: colors.danger,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Xóa',
                        style: TextStyle(
                          color: colors.danger,
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
    final colors = AppUiColors.of(context);
    return Container(
      width: 8,
      height: 50,
      decoration: BoxDecoration(
        color: colors.border,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: (end / 100).clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [colors.danger, colors.amber, colors.emerald],
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}
