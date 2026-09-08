import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/cockpit_design_system.dart';

/// Modern recent charging activity and power trend chart component for Mobile Dashboard.
class RecentChargingChart extends StatelessWidget {
  const RecentChargingChart({
    super.key,
    this.onViewHistory,
  });

  final VoidCallback? onViewHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CockpitColors.surface,
        borderRadius: BorderRadius.circular(CockpitRadius.large),
        border: Border.all(color: CockpitColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: CockpitColors.emerald.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.insights_rounded,
                      size: 20,
                      color: CockpitColors.emeraldStrong,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Xu hướng sạc gần đây',
                        style: CockpitTypography.heading(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: CockpitColors.text,
                        ),
                      ),
                      Text(
                        'Công suất nạp thực tế theo thời gian',
                        style: CockpitTypography.label(
                          fontSize: 11,
                          color: CockpitColors.dim,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (onViewHistory != null)
                InkWell(
                  onTap: onViewHistory,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          'Xem tất cả',
                          style: CockpitTypography.label(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: CockpitColors.emeraldStrong,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: CockpitColors.emeraldStrong,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 20),

          // Mini Metric Badges
          Row(
            children: [
              _MiniStat(
                label: 'Công suất đỉnh',
                value: '3.45 kW',
                color: CockpitColors.emeraldStrong,
              ),
              const SizedBox(width: 12),
              _MiniStat(
                label: 'Hiệu suất TB',
                value: '94.2%',
                color: CockpitColors.info,
              ),
              const SizedBox(width: 12),
              _MiniStat(
                label: 'Điện nạp (7 ngày)',
                value: '68.5 kWh',
                color: CockpitColors.amber,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Line Chart with Emerald gradient
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 4.0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (val) => FlLine(
                    color: CockpitColors.border,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (val, _) {
                        if (val == 0 || val == 2.0 || val == 4.0) {
                          return Text(
                            '${val.toInt()}k',
                            style: CockpitTypography.label(
                              fontSize: 10,
                              color: CockpitColors.dim,
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (val, _) {
                        const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
                        final idx = val.toInt();
                        if (idx >= 0 && idx < days.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              days[idx],
                              style: CockpitTypography.label(
                                fontSize: 10,
                                color: CockpitColors.dim,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (items) => items
                        .map(
                          (item) => LineTooltipItem(
                            '${item.y.toStringAsFixed(2)} kW',
                            CockpitTypography.numbers(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 1.8),
                      FlSpot(1, 2.4),
                      FlSpot(2, 3.2),
                      FlSpot(3, 2.1),
                      FlSpot(4, 3.45),
                      FlSpot(5, 2.9),
                      FlSpot(6, 3.1),
                    ],
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: CockpitColors.emeraldStrong,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: index == 4 ? 5 : 3,
                        color: index == 4 ? Colors.white : CockpitColors.emeraldStrong,
                        strokeWidth: 2,
                        strokeColor: CockpitColors.emeraldStrong,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          CockpitColors.emeraldStrong.withValues(alpha: 0.28),
                          CockpitColors.emeraldStrong.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: CockpitColors.surfaceSoft,
          borderRadius: BorderRadius.circular(CockpitRadius.medium),
          border: Border.all(color: CockpitColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CockpitTypography.label(
                fontSize: 10,
                color: CockpitColors.muted,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CockpitTypography.numbers(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
