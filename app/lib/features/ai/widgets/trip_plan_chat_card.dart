import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';

/// BatteryBot trip estimate (Task 126). Estimate colours only: steel = enough,
/// champagne = tight, rose = not enough (emerald is reserved for verified
/// states). Data comes from the server's `estimate_trip` tool.
class TripPlanChatCard extends StatelessWidget {
  const TripPlanChatCard({super.key, required this.title, required this.data});

  final String title;
  final Map<String, dynamic> data;

  double _n(String key) => (data[key] as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    final verdict = data['verdict']?.toString() ?? '';
    final color = switch (verdict) {
      'comfortable' => LuxeColors.steel,
      'tight' => LuxeColors.champagne,
      _ => LuxeColors.danger,
    };
    final label = switch (verdict) {
      'comfortable' => 'Đủ pin, thoải mái',
      'tight' => 'Đi được nhưng sát',
      _ => 'Không đủ pin',
    };
    final arrival = _n('arrivalSoc');
    final suggestions = [
      for (final item in (data['suggestions'] as List?) ?? const [])
        if (item is Map) _suggestionText(Map<String, dynamic>.from(item)),
    ].whereType<String>().toList();
    final source = data['kmPerPctSource'];
    return Semantics(
      container: true,
      child: Container(
        key: const ValueKey('trip-plan-card'),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LuxeColors.raised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.isEmpty ? 'Ước tính chuyến đi' : title,
              style: const TextStyle(
                color: LuxeColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Hao ~${_n('usePct').round()}% '
              '(${_n('useLowPct').round()}–${_n('useHighPct').round()}%) · '
              '${arrival < 0 ? 'hết pin trước khi tới' : 'tới nơi ~${arrival.round()}%'}',
              style: const TextStyle(color: LuxeColors.text, fontSize: 14),
            ),
            if (data['carMinutes'] is num) ...[
              const SizedBox(height: 4),
              Text(
                '${_n('distanceKm').toStringAsFixed(1)} km · '
                '~${data['carMinutes']} phút (ô tô)',
                style: const TextStyle(color: LuxeColors.muted, fontSize: 12.5),
              ),
            ],
            for (final text in suggestions) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 15,
                      color: LuxeColors.platinumMid,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: LuxeColors.text,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(switch (source) {
              'model' =>
                'Ước tính theo mô hình đã huấn luyện từ các chuyến đi của bạn.',
              'odo' ||
              'personal' => 'Ước tính theo km/1% học từ ODO của xe bạn.',
              _ =>
                'Ước tính theo định mức dòng xe; nhập ODO sau sạc để sát hơn.',
            }, style: const TextStyle(color: LuxeColors.dim, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }

  static String? _suggestionText(Map<String, dynamic> item) {
    num? n(String key) => item[key] as num?;
    return switch (item['kind']) {
      'charge_first' => 'Sạc lên ${n('targetSoc')?.round()}% trước khi đi.',
      'charge_on_the_way' =>
        'Cần sạc giữa đường khoảng ${n('stops')?.round()} lần.',
      'charge_at_destination' => 'Sạc ở điểm đến trước khi quay về.',
      'ride_eco' => 'Chạy chậm lại tiết kiệm ~${n('savedPct')?.round()}% pin.',
      'shorter_route' =>
        'Tuyến ${n('distanceKm')} km ngắn hơn, tiết kiệm ~${n('savedPct')?.round()}%.',
      _ => null,
    };
  }
}
