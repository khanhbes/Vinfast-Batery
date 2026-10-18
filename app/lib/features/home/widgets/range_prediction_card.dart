import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/luxe_theme.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/range_estimator.dart';
import '../../../data/services/trip_energy_model.dart';

/// Range left, from the same [estimateRange] as the hero, the stats strip,
/// the Battery monitor and BatteryBot (QA 129). The interval is the model's
/// own spread, never an invented confidence.
class RangePredictionCard extends StatelessWidget {
  const RangePredictionCard({super.key, required this.vehicle, this.learned});
  final VehicleModel vehicle;
  final TripModelParams? learned;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final estimate = estimateRange(vehicle, learned: learned);
    final learnedSource = estimate?.source == RangeSource.learned;
    return AppReveal(
      child: LuxeGlass(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quãng đường còn lại', style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              learnedSource
                  ? 'Ước tính từ ${estimate!.samples} chuyến thật của bạn'
                  : 'Ước tính theo thông số dòng xe',
              style: text.bodySmall,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  estimate == null
                      ? 'Chưa đủ dữ liệu'
                      : '~${estimate.km.round()} km',
                  style: text.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (estimate != null)
                  Text(
                    '${estimate.lowKm.round()}–${estimate.highKm.round()} km',
                    style: text.titleMedium,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              estimate == null
                  ? 'Nhập % pin để ước tính quãng đường.'
                  : '${estimate.kmPerPct.toStringAsFixed(2)} km cho 1% pin, '
                        'trừ ${rangeReservePercent.round()}% pin dự phòng. '
                        '${learnedSource ? 'Đi nhanh, chở thêm người hoặc trời mưa sẽ hao hơn; Lộ trình tính theo điều kiện bạn chọn.' : 'Chưa học từ chuyến đi của bạn nên sai số rộng hơn.'}',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
