import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../core/widgets/stat_card.dart';
import '../../data/models/charge_log_model.dart';
import '../../data/services/ai_prediction_service.dart';
import '../../data/services/battery_capacity_service.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import '../../data/repositories/trip_log_repository.dart';
import '../home/home_screen.dart';

// =============================================================================
// Statistics Screen - Biểu đồ & phân tích
// =============================================================================

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    final logsAsync = ref.watch(chargeLogsProvider(vehicleId));
    final statsAsync = ref.watch(vehicleStatsProvider(vehicleId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryGreen,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(chargeLogsProvider(vehicleId));
            ref.invalidate(vehicleStatsProvider(vehicleId));
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
            // ── Header ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.analytics_rounded,
                          color: AppColors.info, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Thống kê',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'Phân tích chu kỳ sạc & tiêu thụ',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms),
            ),

            // ── Summary Cards ──
            SliverToBoxAdapter(
              child: statsAsync.when(
                data: (stats) => _buildSummaryCards(stats),
                loading: () => const Padding(
                  padding: EdgeInsets.all(20),
                  child: LoadingSkeleton(layout: SkeletonLayout.stats),
                ),
                error: (e, _) => ErrorState.fromError(
                  error: e,
                  prefix: 'Không tải được thống kê',
                  onRetry: () {
                    ref.invalidate(vehicleStatsProvider(vehicleId));
                  },
                ),
              ),
            ),

            // ── Empty state khi chưa có dữ liệu ──
            SliverToBoxAdapter(
              child: logsAsync.when(
                data: (logs) {
                  if (logs.isEmpty) {
                    return const EmptyState(
                      icon: Icons.analytics_rounded,
                      title: 'Chưa có dữ liệu thống kê',
                      message: 'Hãy nhập ít nhất 2 lần sạc để xem biểu đồ phân tích',
                    );
                  }
                  return const SizedBox.shrink();
                },
                loading: () => const SizedBox.shrink(),
                error: (e, _) => ErrorState.fromError(
                  error: e,
                  prefix: 'Không tải được nhật ký sạc',
                  onRetry: () {
                    ref.invalidate(chargeLogsProvider(vehicleId));
                  },
                ),
              ),
            ),

            // ── Charge Trend Chart ──
            SliverToBoxAdapter(
              child: logsAsync.when(
                data: (logs) => _buildChargeTrendChart(logs),
                loading: () => const Padding(
                  padding: EdgeInsets.all(20),
                  child: LoadingSkeleton(layout: SkeletonLayout.card),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),

            // ── Battery Health Indicator ──
            SliverToBoxAdapter(
              child: logsAsync.when(
                data: (logs) => _buildBatteryHealthCard(logs),
                loading: () => const Padding(
                  padding: EdgeInsets.all(20),
                  child: LoadingSkeleton(layout: SkeletonLayout.card),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),

            // ── AI Prediction ──
            SliverToBoxAdapter(
              child: logsAsync.when(
                data: (logs) => _AiCapacityDetailPanel(
                  vehicleId: vehicleId,
                  logs: logs,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),

            // ── AI Degradation Prediction ──
            SliverToBoxAdapter(
              child: logsAsync.when(
                data: (logs) => _AiPredictionWidget(
                  vehicleId: vehicleId,
                  logs: logs,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),

            // ── Consumption Analysis ──
            SliverToBoxAdapter(
              child: logsAsync.when(
                data: (logs) => _buildConsumptionChart(logs),
                loading: () => const Padding(
                  padding: EdgeInsets.all(20),
                  child: LoadingSkeleton(layout: SkeletonLayout.card),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),

            // ── Charging Pattern ──
            SliverToBoxAdapter(
              child: logsAsync.when(
                data: (logs) => _buildChargingPatternCard(logs),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
        ),
      ),
    );
  }

  // ── Summary Cards ──
  Widget _buildSummaryCards(Map<String, dynamic> stats) {
    final totalCharges = stats['totalCharges'] as int? ?? 0;
    if (totalCharges == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ratio = constraints.maxWidth > 340 ? 1.5 : 1.3;
          return GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: ratio,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          StatCard(
            icon: Icons.battery_charging_full_rounded,
            iconColor: AppColors.primaryGreen,
            title: 'Tổng lần sạc',
            value: '$totalCharges',
          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2),
          StatCard(
            icon: Icons.trending_up_rounded,
            iconColor: AppColors.info,
            title: 'Sạc TB / lần',
            value: '${((stats['avgChargeGain'] as double?) ?? 0.0).toStringAsFixed(0)}%',
          ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2),
          StatCard(
            icon: Icons.battery_1_bar_rounded,
            iconColor: AppColors.warning,
            title: 'Pin bắt đầu TB',
            value: '${((stats['avgStartBattery'] as double?) ?? 0.0).toStringAsFixed(0)}%',
          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2),
          StatCard(
            icon: Icons.timer_outlined,
            iconColor: AppColors.error,
            title: 'Thời gian sạc TB',
            value: '${((stats['avgChargeDuration'] as double?) ?? 0.0).toStringAsFixed(1)}h',
          ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2),
        ],
      );
        },
      ),
    );
  }

  // ── Charge Trend Line Chart ──
  Widget _buildChargeTrendChart(List<ChargeLogModel> logs) {
    if (logs.length < 2) return const SizedBox.shrink();

    // Lấy 20 log gần nhất, đảo ngược để sắp theo thời gian tăng
    final recentLogs = logs.take(20).toList().reversed.toList();

    final chargeGainSpots = <FlSpot>[];
    final startBatterySpots = <FlSpot>[];

    for (int i = 0; i < recentLogs.length; i++) {
      chargeGainSpots.add(FlSpot(i.toDouble(), recentLogs[i].chargeGain.toDouble()));
      startBatterySpots.add(FlSpot(i.toDouble(), recentLogs[i].startBatteryPercent.toDouble()));
    }

    return _ChartCard(
      title: '⚡ Xu hướng sạc',
      subtitle: '${recentLogs.length} lần sạc gần nhất',
      delay: 600,
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 20,
              getDrawingHorizontalLine: (value) => FlLine(
                color: AppColors.border.withValues(alpha: 0.5),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: 20,
                  getTitlesWidget: (value, _) => Text(
                    '${value.toInt()}%',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
              bottomTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              // Charge gain line
              LineChartBarData(
                spots: chargeGainSpots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppColors.primaryGreen,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: 3,
                    color: AppColors.primaryGreen,
                    strokeWidth: 1,
                    strokeColor: Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primaryGreen.withValues(alpha: 0.3),
                      AppColors.primaryGreen.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
              // Start battery line
              LineChartBarData(
                spots: startBatterySpots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: AppColors.error,
                barWidth: 2,
                isStrokeCapRound: true,
                dashArray: [5, 3],
                dotData: const FlDotData(show: false),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => AppColors.surfaceLight,
                tooltipRoundedRadius: 8,
                getTooltipItems: (spots) {
                  return spots.map((s) {
                    final color = s.barIndex == 0 ? AppColors.primaryGreen : AppColors.error;
                    final label = s.barIndex == 0 ? 'Sạc được' : 'Pin bắt đầu';
                    return LineTooltipItem(
                      '$label: ${s.y.toInt()}%',
                      TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                    );
                  }).toList();
                },
              ),
            ),
          ),
        ),
      ),
      legend: const [
        _LegendItem(color: AppColors.primaryGreen, label: 'Sạc được (%)'),
        _LegendItem(color: AppColors.error, label: 'Pin bắt đầu (%)'),
      ],
    );
  }

  // ── Battery Health Card ──
  Widget _buildBatteryHealthCard(List<ChargeLogModel> logs) {
    if (logs.length < 5) return const SizedBox.shrink();

    // Phân tích xu hướng: so sánh tỷ lệ sạc (% / giờ) gần đây vs trước đó
    final recent5 = logs.take(5).toList();
    final older5 = logs.skip(logs.length ~/ 2).take(5).toList();

    double calcChargeRate(List<ChargeLogModel> group) {
      if (group.isEmpty) return 0;
      double totalRate = 0;
      for (final l in group) {
        final hours = l.chargeDuration.inMinutes / 60.0;
        if (hours > 0) {
          totalRate += l.chargeGain / hours;
        }
      }
      return totalRate / group.length;
    }

    final recentRate = calcChargeRate(recent5);
    final olderRate = calcChargeRate(older5);
    final degradation = olderRate > 0 ? ((recentRate - olderRate) / olderRate * 100) : 0.0;

    final healthScore = (100 + degradation).clamp(0, 100);
    final healthText = healthScore >= 80
        ? 'Tốt'
        : healthScore >= 60
            ? 'Khá'
            : healthScore >= 40
                ? 'Trung bình'
                : 'Cần kiểm tra';
    final healthColor = healthScore >= 80
        ? AppColors.primaryGreen
        : healthScore >= 60
            ? AppColors.warning
            : AppColors.error;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              healthColor.withValues(alpha: 0.1),
              AppColors.card,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: healthColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.health_and_safety_rounded, color: healthColor, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Tình trạng pin',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: healthColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    healthText,
                    style: TextStyle(
                      color: healthColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Health score bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: healthScore / 100,
                minHeight: 8,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(healthColor),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Điểm sức khỏe: ${healthScore.toStringAsFixed(0)}/100',
                  style: TextStyle(
                    color: healthColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Tốc độ sạc TB: ${recentRate.toStringAsFixed(1)}%/h',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              degradation >= 0
                  ? '📈 Hiệu suất sạc ổn định so với trước'
                  : '📉 Tốc độ sạc giảm ${degradation.abs().toStringAsFixed(1)}% — theo dõi thêm',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.2);
  }

  // ── Consumption Bar Chart ──
  Widget _buildConsumptionChart(List<ChargeLogModel> logs) {
    if (logs.length < 3) return const SizedBox.shrink();

    // Group by week
    final now = DateTime.now();
    final Map<int, List<ChargeLogModel>> weeklyLogs = {};

    for (final log in logs) {
      final weeksAgo = now.difference(log.startTime).inDays ~/ 7;
      if (weeksAgo < 8) {
        weeklyLogs.putIfAbsent(weeksAgo, () => []).add(log);
      }
    }

    final weeks = weeklyLogs.keys.toList()..sort();
    if (weeks.isEmpty) return const SizedBox.shrink();

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < weeks.length; i++) {
      final weekLogs = weeklyLogs[weeks[i]]!;
      final avgGain = weekLogs.fold<int>(0, (s, l) => s + l.chargeGain) / weekLogs.length;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: avgGain,
              width: 16,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              gradient: const LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [AppColors.info, AppColors.accentGreen],
              ),
            ),
          ],
        ),
      );
    }

    return _ChartCard(
      title: '📊 Tiêu thụ điện theo tuần',
      subtitle: 'Mức sạc trung bình mỗi tuần',
      delay: 800,
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 20,
              getDrawingHorizontalLine: (value) => FlLine(
                color: AppColors.border.withValues(alpha: 0.5),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: 20,
                  getTitlesWidget: (value, _) => Text(
                    '${value.toInt()}%',
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, _) {
                    final idx = value.toInt();
                    if (idx >= 0 && idx < weeks.length) {
                      final w = weeks[idx];
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          w == 0 ? 'Nay' : '${w}w',
                          style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            barGroups: barGroups,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.surfaceLight,
                tooltipRoundedRadius: 8,
                getTooltipItem: (group, groupIdx, rod, rodIdx) {
                  return BarTooltipItem(
                    '${rod.toY.toStringAsFixed(0)}% TB',
                    const TextStyle(
                      color: AppColors.accentGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Charging Pattern Card ──
  Widget _buildChargingPatternCard(List<ChargeLogModel> logs) {
    if (logs.length < 3) return const SizedBox.shrink();

    // Phân tích giờ sạc nhiều nhất
    final hourCounts = List.filled(24, 0);
    for (final log in logs) {
      hourCounts[log.startTime.hour]++;
    }
    final peakHour = hourCounts.indexOf(hourCounts.reduce((a, b) => a > b ? a : b));

    // Phân tích ngày sạc nhiều nhất
    final dayCounts = List.filled(7, 0);
    for (final log in logs) {
      dayCounts[log.startTime.weekday - 1]++;
    }
    final peakDay = dayCounts.indexOf(dayCounts.reduce((a, b) => a > b ? a : b));
    final dayNames = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'CN'];

    // Khoảng cách trung bình giữa các lần sạc
    double avgDaysBetween = 0;
    if (logs.length > 1) {
      final sorted = List<ChargeLogModel>.from(logs)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      double totalDays = 0;
      for (int i = 1; i < sorted.length; i++) {
        totalDays += sorted[i].startTime.difference(sorted[i - 1].startTime).inHours / 24;
      }
      avgDaysBetween = totalDays / (sorted.length - 1);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.insights_rounded, color: AppColors.warning, size: 20),
                SizedBox(width: 8),
                Text(
                  'Thói quen sạc',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _PatternTile(
              icon: Icons.access_time_rounded,
              label: 'Giờ sạc phổ biến',
              value: '${peakHour.toString().padLeft(2, '0')}:00',
              trailing: '${hourCounts[peakHour]} lần',
            ),
            _PatternTile(
              icon: Icons.calendar_today_rounded,
              label: 'Ngày sạc phổ biến',
              value: dayNames[peakDay],
              trailing: '${dayCounts[peakDay]} lần',
            ),
            _PatternTile(
              icon: Icons.loop_rounded,
              label: 'Chu kỳ sạc',
              value: 'Mỗi ${avgDaysBetween.toStringAsFixed(1)} ngày',
              trailing: '',
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 900.ms).slideY(begin: 0.2);
  }
}

// =============================================================================
// Helper Widgets
// =============================================================================

class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final int delay;
  final List<_LegendItem>? legend;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.delay,
    this.legend,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
            if (legend != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                children: legend!,
              ),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    ).animate().fadeIn(delay: delay.ms).slideY(begin: 0.2);
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }
}

class _PatternTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String trailing;

  const _PatternTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textTertiary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing.isNotEmpty)
            Text(
              trailing,
              style: const TextStyle(
                color: AppColors.primaryGreen,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// AI Prediction Widget — Gọi Flask API dự đoán chai pin
// =============================================================================

class _AiPredictionWidget extends ConsumerStatefulWidget {
  final String vehicleId;
  final List<ChargeLogModel> logs;

  const _AiPredictionWidget({required this.vehicleId, required this.logs});

  @override
  ConsumerState<_AiPredictionWidget> createState() =>
      _AiPredictionWidgetState();
}

class _AiPredictionWidgetState extends ConsumerState<_AiPredictionWidget> {
  Map<String, dynamic>? _prediction;
  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadPrediction();
  }

  Future<void> _loadPrediction() async {
    if (widget.logs.length < 3) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final service = ref.read(aiPredictionServiceProvider);
    final result = await service.predictDegradation(
      vehicleId: widget.vehicleId,
      chargeLogs: widget.logs,
    );

    if (mounted) {
      setState(() {
        _prediction = result;
        _isLoading = false;
        _hasError = result == null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.logs.length < 3) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.warning.withValues(alpha: 0.08),
              AppColors.card,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.warning.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.smart_toy_rounded,
                      color: AppColors.warning, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🤖 AI Dự đoán chai pin',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Phân tích bằng Machine Learning',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isLoading)
                  GestureDetector(
                    onTap: _loadPrediction,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.refresh_rounded,
                          color: AppColors.textSecondary, size: 16),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: AppColors.warning,
                          strokeWidth: 2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Đang phân tích...',
                        style:
                            TextStyle(color: AppColors.textTertiary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else if (_hasError)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        color: AppColors.textTertiary, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AI API chưa kết nối — chạy ai_api.py để kích hoạt',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_prediction != null)
              _buildPredictionContent(_prediction!)
            else
              const Text(
                'Nhấn refresh để phân tích',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
              ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 750.ms).slideY(begin: 0.2);
  }

  Widget _buildPredictionContent(Map<String, dynamic> pred) {
    final healthScore = (pred['healthScore'] as num?)?.toDouble() ?? 0;
    final status = pred['healthStatus'] ?? '';
    final lifeMonths = pred['estimatedLifeMonths'];
    final confidence = (pred['confidence'] as num?)?.toDouble() ?? 0;
    final factors = pred['degradationFactors'] as List? ?? [];
    final recs = pred['recommendations'] as List? ?? [];

    final healthColor = healthScore >= 80
        ? AppColors.primaryGreen
        : healthScore >= 60
            ? AppColors.warning
            : AppColors.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Health score
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${healthScore.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: healthColor,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    'Sức khỏe pin: $status',
                    style: TextStyle(
                      color: healthColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (lifeMonths != null)
                  Text(
                    '~$lifeMonths tháng',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  'Tuổi thọ còn lại',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Độ tin cậy: ${confidence.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: healthScore / 100,
            minHeight: 8,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(healthColor),
          ),
        ),

        // Factors
        if (factors.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...factors.take(3).map((f) {
            final severity = f['severity'] ?? 'low';
            final icon = severity == 'high'
                ? Icons.warning_rounded
                : severity == 'medium'
                    ? Icons.info_rounded
                    : Icons.check_circle_rounded;
            final color = severity == 'high'
                ? AppColors.error
                : severity == 'medium'
                    ? AppColors.warning
                    : AppColors.primaryGreen;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${f['factor']}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],

        // Recommendations
        if (recs.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 10),
          ...recs.take(2).map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  r.toString(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              )),
        ],
      ],
    );
  }
}

// =============================================================================
// AI Capacity Detail Panel — Nominal vs Usable, Observed Power, Degradation
// =============================================================================

class _AiCapacityDetailPanel extends ConsumerStatefulWidget {
  final String vehicleId;
  final List<ChargeLogModel> logs;

  const _AiCapacityDetailPanel({required this.vehicleId, required this.logs});

  @override
  ConsumerState<_AiCapacityDetailPanel> createState() =>
      _AiCapacityDetailPanelState();
}

class _AiCapacityDetailPanelState
    extends ConsumerState<_AiCapacityDetailPanel> {
  CapacityResult? _result;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _calculate();
  }

  Future<void> _calculate() async {
    try {
      final vehicleAsync = ref.read(vehicleProvider(widget.vehicleId));
      final vehicle = vehicleAsync.value;
      if (vehicle == null || !vehicle.hasModelLink) {
        setState(() => _loading = false);
        return;
      }

      final specRepo = ref.read(vehicleSpecRepositoryProvider);
      final spec = await specRepo.getSpec(vehicle.vinfastModelId!);
      if (spec == null) {
        setState(() => _loading = false);
        return;
      }

      final trips = await ref
          .read(tripLogRepositoryProvider)
          .getRecentTrips(widget.vehicleId);
      final aiService = ref.read(aiPredictionServiceProvider);

      final result = await BatteryCapacityService.calculate(
        vehicle: vehicle,
        spec: spec,
        chargeLogs: widget.logs,
        trips: trips,
        aiService: aiService,
      );

      if (mounted) setState(() { _result = result; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _result == null) return const SizedBox.shrink();
    final r = _result!;

    final alertColor = switch (r.alertLevel) {
      SoHAlertLevel.none => AppColors.primaryGreen,
      SoHAlertLevel.mild => AppColors.warning,
      SoHAlertLevel.moderate => const Color(0xFFFF9800),
      SoHAlertLevel.severe => AppColors.error,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.info.withValues(alpha: 0.08),
              AppColors.card,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                  child: const Icon(Icons.battery_full_rounded,
                      color: AppColors.info, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('⚡ Phân tích dung lượng AI',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          )),
                      Text('So sánh danh nghĩa vs khả dụng',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          )),
                    ],
                  ),
                ),
                _buildConfBadge(r.confidence),
              ],
            ),
            const SizedBox(height: 16),

            // Nominal vs Usable comparison
            _buildCompareRow(
              'Dung lượng (Wh)',
              r.nominalCapacityWh.toStringAsFixed(0),
              r.usableCapacityWh.toStringAsFixed(0),
              'Wh',
              r.sohPercent / 100,
              alertColor,
            ),
            const SizedBox(height: 10),
            _buildCompareRow(
              'Dung lượng (Ah)',
              r.nominalCapacityAh.toStringAsFixed(1),
              r.usableCapacityAh.toStringAsFixed(1),
              'Ah',
              r.sohPercent / 100,
              alertColor,
            ),

            // SoH bar
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('SoH: ${r.sohPercent.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: alertColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    )),
                Text(r.alertLevel.message,
                    style: TextStyle(
                      color: alertColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: r.sohPercent / 100,
                minHeight: 8,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(alertColor),
              ),
            ),

            // Observed charge power
            if (r.observedChargePowerW != null) ...[
              const SizedBox(height: 14),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.electric_bolt_rounded,
                      color: AppColors.warning, size: 16),
                  const SizedBox(width: 6),
                  const Text('Công suất sạc quan sát',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      )),
                  const Spacer(),
                  Text(
                    '${r.observedChargePowerW!.toStringAsFixed(0)}W',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    ' / ${r.maxChargePowerW.toStringAsFixed(0)}W max',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (r.observedChargePowerW! / r.maxChargePowerW)
                      .clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: AppColors.border,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.warning),
                ),
              ),
            ],

            // Source
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  r.usedAiApi
                      ? Icons.cloud_done_rounded
                      : Icons.computer_rounded,
                  color: AppColors.textTertiary,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  r.usedAiApi ? 'Nguồn: AI API' : 'Nguồn: On-device',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 750.ms).slideY(begin: 0.2);
  }

  Widget _buildCompareRow(String label, String nominal, String usable,
      String unit, double ratio, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            )),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(nominal,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.lineThrough,
                      )),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded,
                      color: AppColors.textTertiary, size: 14),
                  const SizedBox(width: 8),
                  Text('$usable $unit',
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      )),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConfBadge(CapacityConfidence c) {
    final color = switch (c) {
      CapacityConfidence.high => AppColors.primaryGreen,
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
}
