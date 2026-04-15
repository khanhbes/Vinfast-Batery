import '../models/charge_log_model.dart';

/// ========================================================================
/// Smart Charging Service — ETA sạc dựa trên lịch sử (bucketed curve)
/// ========================================================================
class SmartChargingService {
  /// Ước tính thời gian sạc từ [fromPercent] đến [toPercent]
  /// dựa trên lịch sử charge logs (bucketed curve).
  ///
  /// Chia pin thành bucket 10% (0-10, 10-20, ..., 90-100).
  /// Mỗi bucket lấy tốc độ sạc trung bình từ các log đã cover khoảng đó.
  /// Fallback: dùng linear rate nếu dữ liệu ít (< 3 logs).
  ///
  /// Returns: số phút ước tính, hoặc null nếu không tính được.
  static double? estimateChargeMinutes({
    required int fromPercent,
    required int toPercent,
    required List<ChargeLogModel> chargeLogs,
    double fallbackRatePerMin = 0.38,
  }) {
    if (fromPercent >= toPercent) return 0;

    // Nếu dữ liệu ít → fallback linear
    if (chargeLogs.length < 3) {
      return _linearEstimate(
        fromPercent: fromPercent,
        toPercent: toPercent,
        logs: chargeLogs,
        fallbackRate: fallbackRatePerMin,
      );
    }

    // Tạo bucket rates: tốc độ sạc trung bình (%/phút) cho mỗi khoảng 10%
    final bucketRates = _buildBucketRates(chargeLogs);

    double totalMinutes = 0;
    for (int bucketStart = (fromPercent ~/ 10) * 10;
        bucketStart < toPercent;
        bucketStart += 10) {
      final bucketEnd = (bucketStart + 10).clamp(0, 100);
      final effectiveStart = fromPercent > bucketStart ? fromPercent : bucketStart;
      final effectiveEnd = toPercent < bucketEnd ? toPercent : bucketEnd;
      final percentInBucket = effectiveEnd - effectiveStart;

      if (percentInBucket <= 0) continue;

      final bucketIndex = bucketStart ~/ 10;
      final rate = bucketRates[bucketIndex] ?? fallbackRatePerMin;
      if (rate <= 0) {
        totalMinutes += percentInBucket / fallbackRatePerMin;
      } else {
        totalMinutes += percentInBucket / rate;
      }
    }

    return totalMinutes;
  }

  /// Ước tính thời gian hoàn thành sạc
  /// Returns: DateTime dự kiến hoàn thành
  static DateTime? estimateCompleteAt({
    required int currentPercent,
    required int targetPercent,
    required List<ChargeLogModel> chargeLogs,
    double fallbackRatePerMin = 0.38,
  }) {
    final minutes = estimateChargeMinutes(
      fromPercent: currentPercent,
      toPercent: targetPercent,
      chargeLogs: chargeLogs,
      fallbackRatePerMin: fallbackRatePerMin,
    );
    if (minutes == null || minutes <= 0) return null;
    return DateTime.now().add(Duration(minutes: minutes.ceil()));
  }

  /// Tính linear estimate khi dữ liệu ít
  static double _linearEstimate({
    required int fromPercent,
    required int toPercent,
    required List<ChargeLogModel> logs,
    required double fallbackRate,
  }) {
    double rate = fallbackRate;
    if (logs.isNotEmpty) {
      final rates = logs
          .map((l) {
            final min = l.chargeDuration.inMinutes;
            return min > 0 ? l.chargeGain / min : 0.0;
          })
          .where((r) => r > 0)
          .toList();
      if (rates.isNotEmpty) {
        rate = rates.reduce((a, b) => a + b) / rates.length;
      }
    }
    if (rate <= 0) rate = fallbackRate;
    return (toPercent - fromPercent) / rate;
  }

  /// Build bucket rates (%/phút) cho mỗi khoảng 10%
  /// Index 0 = 0-10%, index 1 = 10-20%, ..., index 9 = 90-100%
  static Map<int, double> _buildBucketRates(List<ChargeLogModel> logs) {
    // bucketIndex → list of rates (%/min)
    final Map<int, List<double>> bucketData = {};

    for (final log in logs) {
      final minutes = log.chargeDuration.inMinutes;
      if (minutes <= 0 || log.chargeGain <= 0) continue;

      final overallRate = log.chargeGain / minutes;
      final startBucket = log.startBatteryPercent ~/ 10;
      final endBucket = ((log.endBatteryPercent - 1).clamp(0, 99)) ~/ 10;

      for (int b = startBucket; b <= endBucket && b < 10; b++) {
        bucketData.putIfAbsent(b, () => []);
        bucketData[b]!.add(overallRate);
      }
    }

    final Map<int, double> rates = {};
    for (final entry in bucketData.entries) {
      if (entry.value.isNotEmpty) {
        rates[entry.key] =
            entry.value.reduce((a, b) => a + b) / entry.value.length;
      }
    }
    return rates;
  }

  /// Format phút thành text dạng "Xh Ym"
  static String formatMinutes(double minutes) {
    if (minutes <= 0) return 'Đã xong';
    final h = minutes ~/ 60;
    final m = (minutes % 60).ceil();
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
