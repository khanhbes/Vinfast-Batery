import 'package:flutter/material.dart';

import '../../../core/theme/app_ui_colors.dart';
import '../theme/chatbot_glass_theme.dart';

/// Thẻ trực quan hiển thị tiến độ sạc thông minh và công suất thời gian thực
class ChargingProgressCard extends StatelessWidget {
  const ChargingProgressCard({
    super.key,
    required this.data,
    this.title = 'Tiến độ Sạc Thông Minh',
  });

  final Map<String, dynamic> data;
  final String title;

  void _showFullDetails(
    BuildContext context,
    AppUiColors uiColors,
    Color accentColor,
    double currentSoc,
    double targetSoc,
    double powerW,
    double amps,
    int remainingMin,
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
            child: SingleChildScrollView(
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
                      Icon(Icons.bolt_rounded, color: accentColor, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Chi tiết Phiên Sạc Thông Minh',
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
                    'Trạng thái relay:',
                    isCharging ? 'ĐANG CẤP ĐIỆN' : 'NGẮT NGUỒN',
                    uiColors,
                    valueColor: accentColor,
                  ),
                  _buildDetailRow(
                    'Mức pin hiện tại:',
                    '${currentSoc.toStringAsFixed(1)}%',
                    uiColors,
                  ),
                  _buildDetailRow(
                    'Mục tiêu ngắt sạc:',
                    '${targetSoc.toStringAsFixed(0)}%',
                    uiColors,
                  ),
                  _buildDetailRow(
                    'Công suất đo được:',
                    '${powerW.toStringAsFixed(0)} W',
                    uiColors,
                  ),
                  _buildDetailRow(
                    'Cường độ dòng điện:',
                    '${amps.toStringAsFixed(1)} A (Định mức ≤12A)',
                    uiColors,
                  ),
                  _buildDetailRow(
                    'Thời gian ước tính đầy:',
                    '$remainingMin phút',
                    uiColors,
                  ),
                  _buildDetailRow(
                    'Bảo vệ an toàn phần cứng:',
                    'Kích hoạt (Watchdog 60s)',
                    uiColors,
                    valueColor: Colors.green,
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
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    AppUiColors uiColors, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: uiColors.muted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: valueColor ?? uiColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiColors = AppUiColors.of(context);
    final currentSoc = (data['currentSoc'] as num?)?.toDouble() ?? 75.0;
    final targetSoc = (data['targetSoc'] as num?)?.toDouble() ?? 85.0;
    final powerW = (data['chargingPowerW'] as num?)?.toDouble() ?? 1850.0;
    final amps = (data['currentAmps'] as num?)?.toDouble() ?? 8.4;
    final remainingMin = (data['remainingMinutes'] as num?)?.toInt() ?? 35;
    final status = data['status'] as String? ?? 'charging';

    final isCharging = status == 'charging';
    final accentColor = isCharging ? const Color(0xFF00E676) : uiColors.primary;

    return InkWell(
      onTap: () => _showFullDetails(
        context,
        uiColors,
        accentColor,
        currentSoc,
        targetSoc,
        powerW,
        amps,
        remainingMin,
        isCharging,
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: ChatbotGlassTheme.cardDecoration(
          context,
          accentColor: accentColor,
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
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.electric_bolt_rounded,
                    color: accentColor,
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
                        isCharging
                            ? 'Đang cấp nguồn relay Shelly'
                            : 'Sẵn sàng kích hoạt sạc',
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
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isCharging ? 'Đang sạc' : 'Chờ lệnh',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isCharging
                          ? const Color(0xFF00B050)
                          : uiColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Progress Bar with Current and Target indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Hiện tại: ${currentSoc.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Mục tiêu: ${targetSoc.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: uiColors.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0.0,
                  end: (currentSoc / 100.0).clamp(0.0, 1.0),
                ),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    backgroundColor: uiColors.border.withValues(alpha: 0.35),
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // Metrics 3 Columns
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    context: context,
                    label: 'Công suất',
                    value: '${powerW.toStringAsFixed(0)} W',
                    icon: Icons.flash_on_rounded,
                    color: Colors.amber.shade700,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMetricTile(
                    context: context,
                    label: 'Dòng điện',
                    value: '${amps.toStringAsFixed(1)} A',
                    subValue: 'An toàn ≤12A',
                    icon: Icons.power_rounded,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMetricTile(
                    context: context,
                    label: 'Ước tính',
                    value: remainingMin > 0 ? '~$remainingMin phút' : 'Sắp đầy',
                    icon: Icons.timer_outlined,
                    color: Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Safety Footer - Overflow-proof with Expanded
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.security_rounded,
                  size: 13,
                  color: Colors.green.shade700,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'An toàn phần cứng: Tự ngắt khi đạt mốc ${targetSoc.toStringAsFixed(0)}% hoặc >12A / 2500W',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: uiColors.muted,
                    ),
                    softWrap: true,
                  ),
                ),
              ],
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
    String? subValue,
    required IconData icon,
    required Color color,
  }) {
    final uiColors = AppUiColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                  style: TextStyle(fontSize: 9.5, color: uiColors.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subValue != null) ...[
            Text(
              subValue,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w500,
                color: Colors.green.shade700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
