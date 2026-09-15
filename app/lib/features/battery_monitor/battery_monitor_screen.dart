import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_ui_colors.dart';
import '../../core/theme/cockpit_design_system.dart';
import '../../core/widgets/app_screen_header.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../data/models/battery_state_model.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/services/battery_state_service.dart';

class BatteryMonitorScreen extends ConsumerStatefulWidget {
  final VehicleModel vehicle;

  const BatteryMonitorScreen({super.key, required this.vehicle});

  @override
  ConsumerState<BatteryMonitorScreen> createState() =>
      _BatteryMonitorScreenState();
}

class _BatteryMonitorScreenState extends ConsumerState<BatteryMonitorScreen> {
  bool _isLoading = true;
  BatteryStateModel? _currentBatteryState;
  List<BatteryStateModel> _batteryHistory = [];
  Map<String, dynamic>? _batteryStats;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBatteryData();
  }

  Future<void> _loadBatteryData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final currentState = await BatteryStateService.getCurrentBatteryState(
        widget.vehicle.vehicleId,
      );

      final history = await BatteryStateService.getBatteryHistory(
        vehicleId: widget.vehicle.vehicleId,
        limit: 24,
        timeRange: const Duration(hours: 24),
      );

      final stats = await BatteryStateService.getBatteryStats(
        widget.vehicle.vehicleId,
      );

      if (!mounted) return;
      setState(() {
        _currentBatteryState = currentState;
        _batteryHistory = history;
        _batteryStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshData() async {
    await _loadBatteryData();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppUiColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: colors.primary,
          backgroundColor: colors.surface,
          onRefresh: _refreshData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: AppScreenHeader(
                  icon: Icons.battery_charging_full_rounded,
                  title: 'Giám sát pin',
                  subtitle: widget.vehicle.vehicleName,
                  showBackButton: true,
                  actions: [
                    IconButton(
                      tooltip: 'Làm mới',
                      onPressed: _refreshData,
                      icon: const Icon(Icons.refresh_rounded),
                      color: colors.text,
                      style: IconButton.styleFrom(
                        backgroundColor: colors.surfaceSoft.withValues(alpha: 0.6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ErrorState(
                      message: _error!,
                      onRetry: _refreshData,
                    ),
                  ),
                )
              else if (_isLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: LoadingSkeleton(layout: SkeletonLayout.card),
                  ),
                )
              else ...[
                if (_currentBatteryState != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      child: _buildCurrentBatteryCard(colors),
                    ).appFadeSlideIn(index: 2),
                  ),

                if (_batteryStats != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: _buildBatteryStatsCard(colors),
                    ).appFadeSlideIn(index: 3),
                  ),

                if (_batteryHistory.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: _buildBatteryChart(colors),
                    ).appFadeSlideIn(index: 4),
                  ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    child: _buildSOCPredictionCard(colors),
                  ).appFadeSlideIn(index: 5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentBatteryCard(AppUiColors colors) {
    final batteryState = _currentBatteryState!;
    final safePercent = batteryState.percentage.isFinite
        ? batteryState.percentage.clamp(0.0, 100.0)
        : 0.0;
    final safeSoh = batteryState.soh.isFinite
        ? batteryState.soh.clamp(0.0, 100.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(CockpitRadius.large),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.battery_full_rounded,
                color: _getBatteryColor(safePercent, colors),
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Trạng thái pin hiện tại',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                'Cập nhật: ${_formatTime(batteryState.timestamp)}',
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Battery Percentage
          Center(
            child: SizedBox(
              height: 140,
              width: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: CircularProgressIndicator(
                      value: safePercent / 100,
                      strokeWidth: 12,
                      backgroundColor: colors.surfaceSoft,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getBatteryColor(safePercent, colors),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${safePercent.toStringAsFixed(1)}%',
                        style: CockpitTypography.numbers(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: colors.text,
                        ),
                      ),
                      Text(
                        batteryState.statusText,
                        style: TextStyle(
                          color: _getBatteryColor(safePercent, colors),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Battery Details
          Row(
            children: [
              Expanded(
                child: _buildDetailItem(
                  'Sức khỏe pin',
                  '${safeSoh.toStringAsFixed(1)}%',
                  _getHealthColor(safeSoh, colors),
                  colors,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDetailItem(
                  'Tầm hoạt động',
                  '${batteryState.estimatedRange.toStringAsFixed(1)} km',
                  colors.info,
                  colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildDetailItem(
                  'Nhiệt độ',
                  '${batteryState.temp.toStringAsFixed(1)}°C',
                  _getTemperatureColor(batteryState.temp, colors),
                  colors,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDetailItem(
                  'Nguồn',
                  batteryState.source ?? 'Tiêu chuẩn',
                  colors.muted,
                  colors,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(
    String label,
    String value,
    Color accentColor,
    AppUiColors colors,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceSoft.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: CockpitTypography.numbers(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryStatsCard(AppUiColors colors) {
    final stats = _batteryStats!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(CockpitRadius.large),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_rounded, color: colors.info, size: 22),
              const SizedBox(width: 8),
              Text(
                'Thống kê pin (24h)',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'SOC trung bình',
                  '${stats['avgSOC']?.toStringAsFixed(1) ?? 'N/A'}%',
                  colors.info,
                  colors,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatItem(
                  'SOC thấp nhất',
                  '${stats['minSOC']?.toStringAsFixed(1) ?? 'N/A'}%',
                  colors.danger,
                  colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'SOC cao nhất',
                  '${stats['maxSOC']?.toStringAsFixed(1) ?? 'N/A'}%',
                  colors.emerald,
                  colors,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatItem(
                  'Nhiệt độ TB',
                  '${stats['avgTemp']?.toStringAsFixed(1) ?? 'N/A'}°C',
                  colors.amber,
                  colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'SoH TB',
                  '${stats['avgSOH']?.toStringAsFixed(1) ?? 'N/A'}%',
                  _getHealthColor(stats['avgSOH']?.toDouble() ?? 0, colors),
                  colors,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatItem(
                  'Xu hướng',
                  _getTrendText(stats['consumptionTrend']),
                  _getTrendColor(stats['consumptionTrend'], colors),
                  colors,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    Color accentColor,
    AppUiColors colors,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceSoft.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: colors.muted, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: CockpitTypography.numbers(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryChart(AppUiColors colors) {
    final validHistory = _batteryHistory
        .where((s) => s.percentage.isFinite)
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(CockpitRadius.large),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart_rounded, color: colors.emerald, size: 22),
              const SizedBox(width: 8),
              Text(
                'Biểu đồ pin (24h)',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 20,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: colors.border.withValues(alpha: 0.6),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 4,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < validHistory.length) {
                          final time = validHistory[index].timestamp;
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              '${time.hour}h',
                              style: TextStyle(fontSize: 10, color: colors.dim),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 20,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          '${value.toInt()}%',
                          style: TextStyle(fontSize: 10, color: colors.dim),
                        ),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (validHistory.length - 1).clamp(0, 999).toDouble(),
                minY: 0,
                maxY: 100,
                lineBarsData: [
                  LineChartBarData(
                    spots: validHistory.asMap().entries.map((entry) {
                      return FlSpot(
                        entry.key.toDouble(),
                        entry.value.percentage.clamp(0.0, 100.0),
                      );
                    }).toList(),
                    isCurved: true,
                    color: colors.emerald,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: validHistory.length <= 12,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 3,
                        color: colors.emerald,
                        strokeWidth: 1,
                        strokeColor: colors.surface,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.emerald.withValues(alpha: 0.3),
                          colors.emerald.withValues(alpha: 0.0),
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

  Widget _buildSOCPredictionCard(AppUiColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(CockpitRadius.large),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_graph_rounded, color: colors.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                'Dự đoán SOC AI',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Text(
            'Sử dụng mô hình AI để dự đoán trạng thái pin trong 24 giờ tiếp theo.',
            style: TextStyle(color: colors.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _predictSOC,
              icon: const Icon(Icons.psychology_rounded, size: 18),
              label: const Text(
                'Dự đoán SOC',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _predictSOC() async {
    try {
      final result = await BatteryStateService.predictSOC(
        vehicleId: widget.vehicle.vehicleId,
        currentBattery:
            _currentBatteryState?.percentage ??
            widget.vehicle.currentBattery.toDouble(),
        temperature: _currentBatteryState?.temp ?? 25.0,
        voltage: 48.0,
        current: 15.0,
        odometer: widget.vehicle.currentOdo.toDouble(),
        timeOfDay: DateTime.now().hour,
        dayOfWeek: DateTime.now().weekday,
        avgSpeed: 30.0,
        elevationGain: 50.0,
        weatherCondition: 'sunny',
      );

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppUiColors.of(context).surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CockpitRadius.large),
            ),
            title: Text(
              'Kết quả dự đoán SOC',
              style: TextStyle(
                color: AppUiColors.of(context).text,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOC dự đoán (24h): ${result['predictedSOC']?.toStringAsFixed(1) ?? 'N/A'}%',
                  style: TextStyle(
                    color: AppUiColors.of(context).text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Độ tin cậy: ${result['confidence']?.toStringAsFixed(1) ?? 'N/A'}%',
                  style: TextStyle(color: AppUiColors.of(context).muted),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sức khỏe pin: ${result['batteryHealth']?.toStringAsFixed(1) ?? 'N/A'}%',
                  style: TextStyle(color: AppUiColors.of(context).muted),
                ),
                if (result['recommendations'] != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Khuyến nghị:',
                    style: TextStyle(
                      color: AppUiColors.of(context).text,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...List<String>.from(
                    result['recommendations'],
                  ).map((rec) => Text('• $rec', style: TextStyle(color: AppUiColors.of(context).muted))),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi dự đoán SOC: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getBatteryColor(double percentage, AppUiColors colors) {
    if (percentage < 20) return colors.danger;
    if (percentage < 50) return colors.amber;
    return colors.emerald;
  }

  Color _getHealthColor(double soh, AppUiColors colors) {
    if (soh < 80) return colors.danger;
    if (soh < 90) return colors.amber;
    return colors.emerald;
  }

  Color _getTemperatureColor(double temp, AppUiColors colors) {
    if (temp > 40) return colors.danger;
    if (temp < 10) return colors.info;
    return colors.emerald;
  }

  Color _getTrendColor(dynamic trend, AppUiColors colors) {
    if (trend == null) return colors.muted;
    final trendData = trend as Map<String, dynamic>;
    final trendType = trendData['trend'] as String;
    if (trendType == 'decreasing') return colors.danger;
    if (trendType == 'increasing') return colors.emerald;
    return colors.info;
  }

  String _getTrendText(dynamic trend) {
    if (trend == null) return 'N/A';
    final trendData = trend as Map<String, dynamic>;
    final trendType = trendData['trend'] as String;
    if (trendType == 'decreasing') return 'Giảm';
    if (trendType == 'increasing') return 'Tăng';
    return 'Ổn định';
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
