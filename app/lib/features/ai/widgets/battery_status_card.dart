import 'package:flutter/material.dart';

import '../../../core/theme/app_ui_colors.dart';
import '../theme/chatbot_glass_theme.dart';

/// Thẻ trực quan hiển thị trạng thái Pin và Xe thời gian thực
class BatteryStatusCard extends StatelessWidget {
  const BatteryStatusCard({
    super.key,
    required this.data,
    this.title = 'Trạng thái Pin & Xe',
  });

  final Map<String, dynamic> data;
  final String title;

  void _showBatteryDiagnosticSheet(
    BuildContext context,
    AppUiColors uiColors,
    Color primaryColor,
    double soc,
    double soh,
    double voltage,
    double temp,
    double estRange,
    String vehicleId,
    bool isCharging,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: uiColors.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: uiColors.glassBorder),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: uiColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.battery_charging_full_rounded,
                      color: primaryColor,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Chẩn Đoán Pin Chi Tiết • $vehicleId',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: uiColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDetailRow(
                  'Mức pin (SoC):',
                  '${soc.toStringAsFixed(1)}%',
                  uiColors,
                  valueColor: primaryColor,
                ),
                _buildDetailRow(
                  'Độ khỏe cell pin (SoH):',
                  '${soh.toStringAsFixed(1)}%',
                  uiColors,
                  valueColor: Colors.teal,
                ),
                _buildDetailRow(
                  'Điện áp pack pin:',
                  '${voltage.toStringAsFixed(1)} V',
                  uiColors,
                ),
                _buildDetailRow(
                  'Nhiệt độ pack pin:',
                  '${temp.toStringAsFixed(1)} °C',
                  uiColors,
                  valueColor: temp > 40 ? Colors.red : null,
                ),
                _buildDetailRow(
                  'Quãng đường ước tính:',
                  '~${estRange.toStringAsFixed(0)} km',
                  uiColors,
                ),
                _buildDetailRow(
                  'Nguồn dữ liệu:',
                  'Ngữ cảnh trong app · Chưa xác minh BMS trực tiếp',
                  uiColors,
                ),
                _buildDetailRow(
                  'Chế độ sạc hiện tại:',
                  isCharging ? 'Đang sạc relay' : 'Nghỉ (Chờ sạc)',
                  uiColors,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: uiColors.primary,
                      foregroundColor: uiColors.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Đóng'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildDetailRow(
    String label,
    String value,
    AppUiColors uiColors, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: uiColors.muted)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: valueColor ?? uiColors.text,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiColors = AppUiColors.of(context);
    final soc = (data['soc'] as num?)?.toDouble() ?? 75.0;
    final soh = (data['soh'] as num?)?.toDouble() ?? 98.0;
    final voltage = (data['voltage'] as num?)?.toDouble() ?? 72.0;
    final temp = (data['temperature'] as num?)?.toDouble() ?? 28.5;
    final estRange = (data['estimatedRangeKm'] as num?)?.toDouble() ?? 85.0;
    final chargingStatus = data['chargingStatus'] as String? ?? 'idle';
    final vehicleId = data['vehicleId'] as String? ?? 'VF-FELIZ';

    final isCharging = chargingStatus == 'charging';
    final isLow = soc < 20.0;
    final isHot = temp > 40.0;

    final primaryColor = isLow
        ? Colors.amber.shade700
        : (isCharging ? const Color(0xFF00E676) : const Color(0xFF0072BC));

    return InkWell(
      onTap: () => _showBatteryDiagnosticSheet(
        context,
        uiColors,
        primaryColor,
        soc,
        soh,
        voltage,
        temp,
        estRange,
        vehicleId,
        isCharging,
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: ChatbotGlassTheme.cardDecoration(
          context,
          accentColor: primaryColor,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isCharging
                        ? Icons.bolt_rounded
                        : Icons.battery_charging_full_rounded,
                    color: primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        vehicleId,
                        style: TextStyle(fontSize: 11.5, color: uiColors.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isCharging
                        ? const Color(0xFF00E676).withValues(alpha: 0.15)
                        : (isLow
                              ? Colors.orange.withValues(alpha: 0.15)
                              : uiColors.primary.withValues(alpha: 0.1)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isCharging ? 'Đang sạc' : (isLow ? 'Pin yếu' : 'Sẵn sàng'),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isCharging
                          ? const Color(0xFF00B050)
                          : (isLow ? Colors.orange.shade800 : uiColors.primary),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Body: Gauge + Stats Grid with LayoutBuilder (Overflow-proof)
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 275;
                final gaugeDimension = isNarrow ? 70.0 : 86.0;
                final indicatorDimension = isNarrow ? 62.0 : 76.0;
                final strokeW = isNarrow ? 6.0 : 7.5;
                final fontSize = isNarrow ? 16.0 : 19.0;
                final gap = isNarrow ? 10.0 : 14.0;

                return Row(
                  children: [
                    // Animated Mini Circle Gauge
                    SizedBox(
                      width: gaugeDimension,
                      height: gaugeDimension,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: 0.0,
                              end: (soc / 100.0).clamp(0.0, 1.0),
                            ),
                            duration: const Duration(milliseconds: 1000),
                            curve: Curves.easeOutCubic,
                            builder: (context, animValue, _) {
                              return SizedBox(
                                width: indicatorDimension,
                                height: indicatorDimension,
                                child: CircularProgressIndicator(
                                  value: animValue,
                                  strokeWidth: strokeW,
                                  backgroundColor: uiColors.border.withValues(
                                    alpha: 0.35,
                                  ),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    primaryColor,
                                  ),
                                  strokeCap: StrokeCap.round,
                                ),
                              );
                            },
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${soc.toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontSize: fontSize,
                                  fontWeight: FontWeight.w800,
                                  color: primaryColor,
                                ),
                              ),
                              Text(
                                'SoC',
                                style: TextStyle(
                                  fontSize: isNarrow ? 9.0 : 10.0,
                                  fontWeight: FontWeight.w600,
                                  color: uiColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: gap),

                    // Metrics 2x2
                    Expanded(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricTile(
                                  context: context,
                                  label: 'Quãng đường',
                                  value: '~${estRange.toStringAsFixed(0)} km',
                                  icon: Icons.navigation_rounded,
                                  iconColor: const Color(0xFF0072BC),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _buildMetricTile(
                                  context: context,
                                  label: 'Độ khỏe',
                                  value: '${soh.toStringAsFixed(0)}%',
                                  icon: Icons.favorite_rounded,
                                  iconColor: Colors.teal,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricTile(
                                  context: context,
                                  label: 'Điện áp',
                                  value: '${voltage.toStringAsFixed(1)} V',
                                  icon: Icons.electrical_services_rounded,
                                  iconColor: Colors.deepPurple,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _buildMetricTile(
                                  context: context,
                                  label: 'Nhiệt độ',
                                  value: '${temp.toStringAsFixed(1)} °C',
                                  icon: Icons.thermostat_rounded,
                                  iconColor: isHot
                                      ? Colors.red
                                      : Colors.blueGrey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            if (isLow || isHot) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: (isHot ? Colors.red : Colors.orange).withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: isHot ? Colors.red : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isHot
                            ? 'Nhiệt độ pin cao (>40°C). Hãy để pin nguội bớt trước khi sạc công suất lớn.'
                            : 'Mức pin dưới 20%. Bạn nên sạc thông minh sớm để bảo vệ tuổi thọ cell pin.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isHot
                              ? Colors.red.shade900
                              : Colors.orange.shade900,
                        ),
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    final uiColors = AppUiColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: uiColors.border.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: iconColor),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 9.0, color: uiColors.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
