import 'package:flutter/material.dart';

import '../../../core/theme/app_ui_colors.dart';
import '../theme/chatbot_glass_theme.dart';

/// Thẻ trực quan hiển thị tóm tắt chuyến đi, tiêu hao năng lượng và lượng CO₂ giảm thải
class TripSummaryCard extends StatelessWidget {
  const TripSummaryCard({
    super.key,
    required this.data,
    this.title = 'Tóm tắt Chuyến đi & Hiệu suất',
  });

  final Map<String, dynamic> data;
  final String title;

  void _showTripBreakdown(
    BuildContext context,
    AppUiColors uiColors,
    double distanceKm,
    double energyWh,
    double efficiency,
    double co2Saved,
    int durationMin,
    bool isEfficient,
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
                    const Icon(Icons.two_wheeler_rounded, color: Color(0xFF0072BC), size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Phân Tích Chi Tiết Chuyến Đi',
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
                _buildDetailRow('Tổng quãng đường:', '${distanceKm.toStringAsFixed(1)} km', uiColors),
                _buildDetailRow('Thời gian di chuyển:', '$durationMin phút', uiColors),
                _buildDetailRow(
                  'Tổng điện năng tiêu thụ:',
                  energyWh >= 1000
                      ? '${(energyWh / 1000).toStringAsFixed(2)} kWh'
                      : '${energyWh.toStringAsFixed(0)} Wh',
                  uiColors,
                ),
                _buildDetailRow('Suất tiêu hao trung bình:', '${efficiency.toStringAsFixed(1)} Wh/km', uiColors, valueColor: isEfficient ? Colors.green : Colors.amber.shade800),
                _buildDetailRow('CO₂ đã cắt giảm:', '${co2Saved.toStringAsFixed(2)} kg CO₂', uiColors, valueColor: Colors.green),
                _buildDetailRow('Đánh giá phong cách lái:', isEfficient ? 'Tối ưu năng lượng (Eco Champion)' : 'Cần điều tiết tay ga đều hơn', uiColors),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: uiColors.primary,
                      foregroundColor: uiColors.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  static Widget _buildDetailRow(String label, String value, AppUiColors uiColors, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: uiColors.muted)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: valueColor ?? uiColors.text)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiColors = AppUiColors.of(context);
    final distanceKm = (data['distanceKm'] as num?)?.toDouble() ?? 24.5;
    final energyWh = (data['energyUsedWh'] as num?)?.toDouble() ?? 735.0;
    final efficiency = (data['efficiencyWhKm'] as num?)?.toDouble() ?? 30.0;
    final co2Saved = (data['co2SavedKg'] as num?)?.toDouble() ?? 2.1;
    final durationMin = (data['durationMinutes'] as num?)?.toInt() ?? 42;

    final isEfficient = efficiency <= 35.0;

    return InkWell(
      onTap: () => _showTripBreakdown(
        context,
        uiColors,
        distanceKm,
        energyWh,
        efficiency,
        co2Saved,
        durationMin,
        isEfficient,
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: ChatbotGlassTheme.cardDecoration(
          context,
          accentColor: const Color(0xFF0072BC),
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
                    color: const Color(0xFF0072BC).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.two_wheeler_rounded,
                    color: Color(0xFF0072BC),
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
                        'Thời gian: ~$durationMin phút',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: uiColors.muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isEfficient ? Colors.green : Colors.orange)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isEfficient ? 'Tiết kiệm điện' : 'Tiêu thụ cao',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isEfficient ? Colors.green.shade800 : Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 4 Metrics Grid: Quãng đường, Điện tiêu thụ, Suất tiêu thụ, Giảm CO2
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    context: context,
                    label: 'Quãng đường',
                    value: '${distanceKm.toStringAsFixed(1)} km',
                    icon: Icons.alt_route_rounded,
                    color: const Color(0xFF0072BC),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMetricTile(
                    context: context,
                    label: 'Điện năng',
                    value: energyWh >= 1000
                        ? '${(energyWh / 1000).toStringAsFixed(2)} kWh'
                        : '${energyWh.toStringAsFixed(0)} Wh',
                    icon: Icons.offline_bolt_rounded,
                    color: Colors.amber.shade800,
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
                    label: 'Hiệu suất',
                    value: '${efficiency.toStringAsFixed(1)} Wh/km',
                    icon: Icons.eco_rounded,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMetricTile(
                    context: context,
                    label: 'Giảm CO₂',
                    value: '${co2Saved.toStringAsFixed(1)} kg',
                    icon: Icons.forest_rounded,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Eco Tip Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.energy_savings_leaf_rounded,
                    size: 14,
                    color: Colors.green.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isEfficient
                          ? 'Phong cách lái xe rất mượt mà và tiết kiệm điện năng.'
                          : 'Giữ tốc độ ổn định 35-40 km/h sẽ giúp tăng 15% tầm hoạt động.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.green.shade900,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),
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
    required Color color,
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
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: uiColors.muted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
