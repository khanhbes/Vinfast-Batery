import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/models/battery_state_model.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/services/battery_state_service.dart';

class BatteryMonitorScreen extends ConsumerStatefulWidget {
  final VehicleModel vehicle;

  const BatteryMonitorScreen({
    super.key,
    required this.vehicle,
  });

  @override
  ConsumerState<BatteryMonitorScreen> createState() => _BatteryMonitorScreenState();
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
      // Load current battery state
      final currentState = await BatteryStateService.getCurrentBatteryState(widget.vehicle.vehicleId);
      
      // Load battery history (last 24 hours)
      final history = await BatteryStateService.getBatteryHistory(
        vehicleId: widget.vehicle.vehicleId,
        limit: 24,
        timeRange: const Duration(hours: 24),
      );
      
      // Load battery statistics
      final stats = await BatteryStateService.getBatteryStats(widget.vehicle.vehicleId);

      setState(() {
        _currentBatteryState = currentState;
        _batteryHistory = history;
        _batteryStats = stats;
        _isLoading = false;
      });
    } catch (e) {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Giám sát pin'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current Battery Status
              if (_currentBatteryState != null) ...[
                _buildCurrentBatteryCard(),
                const SizedBox(height: 16),
              ],
              
              // Battery Statistics
              if (_batteryStats != null) ...[
                _buildBatteryStatsCard(),
                const SizedBox(height: 16),
              ],
              
              // Battery Chart
              if (_batteryHistory.isNotEmpty) ...[
                _buildBatteryChart(),
                const SizedBox(height: 16),
              ],
              
              // Error Message
              if (_error != null) ...[
                Card(
                  color: Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                        IconButton(onPressed: _refreshData, icon: const Icon(Icons.refresh)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Loading Indicator
              if (_isLoading) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 16),
              ],
              
              // SOC Prediction Button
              _buildSOCPredictionCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentBatteryCard() {
    final batteryState = _currentBatteryState!;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.battery_full,
                  color: _getBatteryColor(batteryState.percentage),
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Trạng thái pin hiện tại',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  'Cập nhật: ${_formatTime(batteryState.timestamp)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Battery Percentage
            SizedBox(
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: batteryState.percentage / 100,
                      strokeWidth: 12,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getBatteryColor(batteryState.percentage),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${batteryState.percentage.toStringAsFixed(1)}%',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _getBatteryColor(batteryState.percentage),
                        ),
                      ),
                      Text(
                        batteryState.statusText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _getBatteryColor(batteryState.percentage),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Battery Details
            Row(
              children: [
                Expanded(
                  child: _buildDetailItem(
                    'Sức khỏe pin',
                    '${batteryState.soh.toStringAsFixed(1)}%',
                    _getHealthColor(batteryState.soh),
                  ),
                ),
                Expanded(
                  child: _buildDetailItem(
                    'Tầm hoạt động',
                    '${batteryState.estimatedRange.toStringAsFixed(1)} km',
                    Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildDetailItem(
                    'Nhiệt độ',
                    '${batteryState.temp.toStringAsFixed(1)}°C',
                    _getTemperatureColor(batteryState.temp),
                  ),
                ),
                Expanded(
                  child: _buildDetailItem(
                    'Nguồn',
                    batteryState.source ?? 'Unknown',
                    Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryStatsCard() {
    final stats = _batteryStats!;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics,
                  color: Colors.blue,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Thống kê pin (24h)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
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
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'SOC thấp nhất',
                    '${stats['minSOC']?.toStringAsFixed(1) ?? 'N/A'}%',
                    Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'SOC cao nhất',
                    '${stats['maxSOC']?.toStringAsFixed(1) ?? 'N/A'}%',
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Nhiệt độ TB',
                    '${stats['avgTemp']?.toStringAsFixed(1) ?? 'N/A'}°C',
                    Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'SoH TB',
                    '${stats['avgSOH']?.toStringAsFixed(1) ?? 'N/A'}%',
                    _getHealthColor(stats['avgSOH']?.toDouble() ?? 0),
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Xu hướng',
                    _getTrendText(stats['consumptionTrend']),
                    _getTrendColor(stats['consumptionTrend']),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.show_chart,
                  color: Colors.blue,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Biểu đồ pin (24h)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
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
                    drawVerticalLine: true,
                    horizontalInterval: 20,
                    verticalInterval: 2,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey[300],
                        strokeWidth: 1,
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: Colors.grey[300],
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 4,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < _batteryHistory.length) {
                            final time = _batteryHistory[index].timestamp;
                            return SideTitleWidget(
                              meta: meta,
                              child: Text(
                                '${time.hour}h',
                                style: const TextStyle(fontSize: 10),
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
                        reservedSize: 40,
                        interval: 20,
                        getTitlesWidget: (value, meta) {
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              '${value.toInt()}%',
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  minX: 0,
                  maxX: (_batteryHistory.length - 1).toDouble(),
                  minY: 0,
                  maxY: 100,
                  lineBarsData: [
                    LineChartBarData(
                      spots: _batteryHistory.asMap().entries.map((entry) {
                        return FlSpot(entry.key.toDouble(), entry.value.percentage);
                      }).toList(),
                      isCurved: true,
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.withOpacity(0.8),
                          Colors.blue.withOpacity(0.2),
                        ],
                      ),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 3,
                            color: Colors.blue,
                            strokeWidth: 1,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            Colors.blue.withOpacity(0.3),
                            Colors.blue.withOpacity(0.1),
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
      ),
    );
  }

  Widget _buildSOCPredictionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_graph,
                  color: Colors.purple,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Dự đoán SOC AI',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Text(
              'Sử dụng AI model để dự đoán trạng thái pin trong 24 giờ tiếp theo',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _predictSOC,
                icon: const Icon(Icons.psychology),
                label: const Text('Dự đoán SOC'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _predictSOC() async {
    try {
      final result = await BatteryStateService.predictSOC(
        vehicleId: widget.vehicle.vehicleId,
        currentBattery: _currentBatteryState?.percentage ?? widget.vehicle.currentBattery.toDouble(),
        temperature: _currentBatteryState?.temp ?? 25.0,
        voltage: 48.0, // Default voltage
        current: 15.0, // Default current
        odometer: widget.vehicle.currentOdo.toDouble(),
        timeOfDay: DateTime.now().hour,
        dayOfWeek: DateTime.now().weekday,
        avgSpeed: 30.0, // Default average speed
        elevationGain: 50.0, // Default elevation gain
        weatherCondition: 'sunny',
      );

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Kết quả dự đoán SOC'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SOC dự đoán (24h): ${result['predictedSOC']?.toStringAsFixed(1) ?? 'N/A'}%'),
                const SizedBox(height: 8),
                Text('Độ tin cậy: ${result['confidence']?.toStringAsFixed(1) ?? 'N/A'}%'),
                const SizedBox(height: 8),
                Text('Sức khỏe pin: ${result['batteryHealth']?.toStringAsFixed(1) ?? 'N/A'}%'),
                if (result['recommendations'] != null) ...[
                  const SizedBox(height: 16),
                  const Text('Khuyến nghị:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...List<String>.from(result['recommendations']).map((rec) => Text('• $rec')),
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

  Color _getBatteryColor(double percentage) {
    if (percentage < 10) return Colors.red;
    if (percentage < 20) return Colors.orange;
    if (percentage < 50) return Colors.blue;
    return Colors.green;
  }

  Color _getHealthColor(double soh) {
    if (soh < 80) return Colors.red;
    if (soh < 90) return Colors.orange;
    return Colors.green;
  }

  Color _getTemperatureColor(double temp) {
    if (temp > 35) return Colors.red;
    if (temp < 10) return Colors.blue;
    return Colors.green;
  }

  Color _getTrendColor(dynamic trend) {
    if (trend == null) return Colors.grey;
    final trendData = trend as Map<String, dynamic>;
    final trendType = trendData['trend'] as String;
    if (trendType == 'decreasing') return Colors.red;
    if (trendType == 'increasing') return Colors.green;
    return Colors.blue;
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
