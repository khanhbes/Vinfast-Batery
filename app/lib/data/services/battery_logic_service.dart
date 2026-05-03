import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/trip_log_model.dart';
import '../models/charge_log_model.dart';

/// ==========================================================================
/// Battery Logic Service — Tính toán SoH, hiệu suất, tốc độ sạc
/// ==========================================================================
class BatteryLogicService {
  /// VinFast Feliz 2025: ~1.35 km per 1% battery khi mới
  static const double defaultFelizEfficiency = 1.35;

  // ── Tốc độ sạc (%/phút) ──────────────────────────────────────────────────

  /// Tính tốc độ sạc trung bình từ 1 log sạc
  /// Ví dụ: sạc từ 20% → 80% trong 150 phút => (80-20)/150 = 0.4 %/phút
  static double chargeRate(ChargeLogModel log) {
    final minutes = log.chargeDuration.inMinutes;
    if (minutes <= 0) return 0;
    return log.chargeGain / minutes;
  }

  /// Tốc độ sạc trung bình từ nhiều logs
  static double avgChargeRate(List<ChargeLogModel> logs) {
    if (logs.isEmpty) return 0;
    final rates = logs.map((l) => chargeRate(l)).where((r) => r > 0).toList();
    if (rates.isEmpty) return 0;
    return rates.reduce((a, b) => a + b) / rates.length;
  }

  /// Ước tính thời gian sạc từ X% → Y% dựa trên tốc độ TB
  /// Returns: số phút
  static double estimateChargeTime(
    int fromPercent,
    int toPercent,
    double ratePerMinute,
  ) {
    if (ratePerMinute <= 0) return 0;
    return (toPercent - fromPercent) / ratePerMinute;
  }

  // ── Hiệu suất tiêu thụ (km / 1%) ────────────────────────────────────────

  /// Tính hiệu suất từ 1 chuyến đi
  /// Ví dụ: đi 12km, tiêu 10% pin => hiệu suất = 1.2 km/1%
  static double tripEfficiency(TripLogModel trip) {
    if (trip.batteryConsumed <= 0) return 0;
    return trip.distance / trip.batteryConsumed;
  }

  /// Hiệu suất trung bình từ N chuyến gần nhất
  static double avgEfficiency(List<TripLogModel> trips, {int recentCount = 10}) {
    final recent = trips.take(recentCount).toList();
    if (recent.isEmpty) return 0;
    final effs = recent.map((t) => tripEfficiency(t)).where((e) => e > 0).toList();
    if (effs.isEmpty) return 0;
    return effs.reduce((a, b) => a + b) / effs.length;
  }

  // ── Độ chai pin (State of Health — SoH) ──────────────────────────────────

  /// Tính SoH dựa trên so sánh hiệu suất thực tế vs hiệu suất gốc
  ///
  /// Công thức:
  ///   SoH = (currentEfficiency / defaultEfficiency) × 100
  ///
  /// Ví dụ:
  ///   - Lúc mới: 1% đi được 1.2km (defaultEfficiency = 1.2)
  ///   - Hiện tại: 1% đi được 0.8km (currentEfficiency = 0.8)
  ///   - SoH = 0.8 / 1.2 × 100 = 66.7% → Pin đã chai ~33%
  ///
  /// [trips] — Danh sách chuyến đi (mới nhất trước)
  /// [defaultEfficiency] — Hiệu suất khi xe mới (km/1%)
  static double calculateSoH(
    List<TripLogModel> trips, {
    double defaultEfficiency = defaultFelizEfficiency,
    int recentCount = 10,
  }) {
    final currentEff = avgEfficiency(trips, recentCount: recentCount);
    if (currentEff <= 0 || defaultEfficiency <= 0) return 100.0;

    final soh = (currentEff / defaultEfficiency) * 100;
    return soh.clamp(0, 100);
  }

  /// Phân loại trạng thái SoH
  static SoHStatus getSoHStatus(double soh) {
    if (soh >= 80) return SoHStatus.good;
    if (soh >= 60) return SoHStatus.fair;
    if (soh >= 40) return SoHStatus.degraded;
    return SoHStatus.critical;
  }

  // ── Haversine Distance (GPS) ─────────────────────────────────────────────

  /// Tính khoảng cách giữa 2 tọa độ GPS (đơn vị: km)
  /// Sử dụng công thức Haversine chính xác cho quả cầu Trái Đất
  static double haversineDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const R = 6371.0; // Bán kính Trái Đất (km)
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _toRad(double deg) => deg * pi / 180;

  // ── Pin ảo (Simulated Battery) ───────────────────────────────────────────

  /// Tính % pin tiêu hao cho quãng đường với tải trọng
  ///
  /// Ví dụ: defaultEfficiency = 1.2 km/1%, distance = 6km, payload = 2 người
  /// Base drain = 6 / 1.2 = 5%
  /// Với payload x1.3 = 5 * 1.3 = 6.5%  →  Trả về 7 (làm tròn lên)
  static int batteryDrainForDistance(
    double distanceKm,
    double defaultEfficiency,
    PayloadType payload,
  ) {
    if (defaultEfficiency <= 0) return 0;
    final baseDrain = distanceKm / defaultEfficiency;
    final actualDrain = baseDrain * payload.factor;
    return actualDrain.ceil();
  }

  /// Tính % pin cộng thêm sau N phút sạc
  /// chargeRatePerMin = %/phút (VD: 0.38)
  static int batteryGainForDuration(double minutes, double chargeRatePerMin) {
    return (minutes * chargeRatePerMin).floor();
  }
}

/// Trạng thái sức khỏe pin
enum SoHStatus {
  good('Tốt', '✅', 80),
  fair('Khá', '⚠️', 60),
  degraded('Chai nhiều', '🔶', 40),
  critical('Cần thay pin', '🔴', 0);

  final String label;
  final String emoji;
  final double minSoH;

  const SoHStatus(this.label, this.emoji, this.minSoH);
}

// ── Riverpod Providers ─────────────────────────────────────────────────────

final batteryLogicProvider = Provider<BatteryLogicService>((ref) {
  return BatteryLogicService();
});
