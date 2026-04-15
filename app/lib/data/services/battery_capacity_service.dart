import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/charge_log_model.dart';
import '../models/trip_log_model.dart';
import '../models/vehicle_model.dart';
import '../models/vinfast_model_spec.dart';
import '../repositories/ai_insights_repository.dart';
import 'battery_logic_service.dart';

/// ========================================================================
/// Battery Capacity Service — Tính dung lượng pin AI (hybrid)
/// Ưu tiên SoH từ AiVehicleInsights (Firestore), fallback on-device
/// ========================================================================

/// Mức confidence cho kết quả AI capacity
enum CapacityConfidence {
  high('Cao', 'Có insight AI từ web'),
  medium('Trung bình', 'Dữ liệu đủ, fallback local'),
  low('Thấp', 'Dữ liệu ít hoặc chưa link model');

  final String label;
  final String description;
  const CapacityConfidence(this.label, this.description);
}

/// Ngưỡng cảnh báo SoH
enum SoHAlertLevel {
  none(100, 'Bình thường'),
  mild(80, 'Pin bắt đầu chai'),
  moderate(70, 'Cần theo dõi'),
  severe(60, 'Nên thay pin sớm');

  final int threshold;
  final String message;
  const SoHAlertLevel(this.threshold, this.message);

  static SoHAlertLevel fromSoH(double soh) {
    if (soh < 60) return SoHAlertLevel.severe;
    if (soh < 70) return SoHAlertLevel.moderate;
    if (soh < 80) return SoHAlertLevel.mild;
    return SoHAlertLevel.none;
  }
}

/// Kết quả tính toán capacity
class CapacityResult {
  final double nominalCapacityWh;
  final double nominalCapacityAh;
  final double nominalVoltageV;
  final double sohPercent;
  final double usableCapacityWh;
  final double usableCapacityAh;
  final double? observedChargePowerW;
  final double maxChargePowerW;
  final CapacityConfidence confidence;
  final SoHAlertLevel alertLevel;
  final bool usedAiInsight;

  CapacityResult({
    required this.nominalCapacityWh,
    required this.nominalCapacityAh,
    required this.nominalVoltageV,
    required this.sohPercent,
    required this.usableCapacityWh,
    required this.usableCapacityAh,
    this.observedChargePowerW,
    required this.maxChargePowerW,
    required this.confidence,
    required this.alertLevel,
    this.usedAiInsight = false,
  });
}

/// Service tính toán dung lượng pin hybrid
class BatteryCapacityService {
  /// Tính toán capacity đầy đủ
  ///
  /// Hybrid: ưu tiên SoH từ AiVehicleInsights (Firestore), fallback on-device
  static Future<CapacityResult?> calculate({
    required VehicleModel vehicle,
    required VinFastModelSpec spec,
    required List<ChargeLogModel> chargeLogs,
    required List<TripLogModel> trips,
    AiVehicleInsight? insight,
  }) async {
    final nomWh = spec.nominalCapacityWh;
    final nomAh = spec.nominalCapacityAh;
    final nomV = spec.nominalVoltageV;
    final maxPower = spec.maxChargePowerW;

    if (nomWh <= 0 || nomV <= 0) return null;

    // ── SoH: ưu tiên Firestore insight ──
    double soh;
    bool usedInsight = false;
    CapacityConfidence confidence;

    if (insight != null && insight.hasTrained && insight.healthScore > 0) {
      soh = insight.healthScore.clamp(0, 100);
      usedInsight = true;
      confidence = insight.isStale
          ? CapacityConfidence.medium
          : CapacityConfidence.high;
    } else {
      soh = _localSoH(trips, spec);
      confidence = trips.length >= 5
          ? CapacityConfidence.medium
          : CapacityConfidence.low;
    }

    // ── Capacity calculations ──
    final usableWh = nomWh * soh / 100;
    final usableAh = nomV > 0 ? usableWh / nomV : 0.0;

    // ── Observed charge power ──
    final observedPower = _observedChargePower(
      chargeLogs: chargeLogs,
      nominalCapacityWh: nomWh,
      maxChargePowerW: maxPower,
    );

    final alertLevel = SoHAlertLevel.fromSoH(soh);

    return CapacityResult(
      nominalCapacityWh: nomWh,
      nominalCapacityAh: nomAh,
      nominalVoltageV: nomV,
      sohPercent: soh,
      usableCapacityWh: usableWh,
      usableCapacityAh: usableAh,
      observedChargePowerW: observedPower,
      maxChargePowerW: maxPower,
      confidence: confidence,
      alertLevel: alertLevel,
      usedAiInsight: usedInsight,
    );
  }

  /// SoH on-device fallback
  static double _localSoH(List<TripLogModel> trips, VinFastModelSpec spec) {
    if (trips.isEmpty) return 100.0;
    return BatteryLogicService.calculateSoH(
      trips,
      defaultEfficiency: spec.defaultEfficiencyKmPerPercent,
    );
  }

  /// Tính công suất sạc quan sát từ charge logs
  ///
  /// energyAddedWh = nominalCapacityWh * chargeGain% / 100
  /// powerW = energyAddedWh / durationHours
  /// Trung bình có trọng số theo thời lượng, giới hạn bởi maxChargePowerW
  static double? _observedChargePower({
    required List<ChargeLogModel> chargeLogs,
    required double nominalCapacityWh,
    required double maxChargePowerW,
  }) {
    if (chargeLogs.isEmpty || nominalCapacityWh <= 0) return null;

    double totalPowerWeighted = 0;
    double totalDurationHours = 0;

    for (final log in chargeLogs) {
      final durationH = log.chargeDuration.inMinutes / 60.0;
      if (durationH <= 0 || log.chargeGain <= 0) continue;

      final energyWh = nominalCapacityWh * log.chargeGain / 100;
      final powerW = energyWh / durationH;

      // Giới hạn bởi maxChargePowerW (loại outlier)
      final clampedPower = powerW.clamp(0, maxChargePowerW * 1.2);
      totalPowerWeighted += clampedPower * durationH;
      totalDurationHours += durationH;
    }

    if (totalDurationHours <= 0) return null;
    return totalPowerWeighted / totalDurationHours;
  }
}

/// Riverpod provider
final batteryCapacityServiceProvider = Provider<BatteryCapacityService>((ref) {
  return BatteryCapacityService();
});
