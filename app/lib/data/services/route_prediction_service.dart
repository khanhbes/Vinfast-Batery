import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/trip_log_model.dart';
import '../repositories/ai_insights_repository.dart';
import 'battery_logic_service.dart';

/// ========================================================================
/// Route Prediction Service — Dự báo tiêu hao pin cho lộ trình
/// Dữ liệu AI từ Firestore insight cache, fallback on-device
/// ========================================================================

/// Abstraction cho provider khoảng cách lộ trình.
abstract class RouteDistanceProvider {
  Future<double?> getDistance(String destination);
}

/// Mock provider: trả về distance do user tự nhập.
class MockRouteDistanceProvider implements RouteDistanceProvider {
  final double manualDistanceKm;
  MockRouteDistanceProvider({required this.manualDistanceKm});

  @override
  Future<double?> getDistance(String destination) async => manualDistanceKm;
}

/// Nguồn dự đoán
enum PredictionSource {
  aiInsight('AI insight'),
  onDeviceFallback('On-device fallback');

  final String label;
  const PredictionSource(this.label);
}

/// Kết quả dự đoán lộ trình
class RoutePredictionResult {
  final double distanceKm;
  final PayloadType payload;
  final double efficiencyUsed;
  final int estimatedBatteryDrain;
  final int remainingBattery;
  final bool isEnough;

  // AI metadata
  final PredictionSource source;
  final double? confidence;
  final String? modelSourceDetail;
  final String? insightStatus; // 'available' / 'stale' / 'missing'

  RoutePredictionResult({
    required this.distanceKm,
    required this.payload,
    required this.efficiencyUsed,
    required this.estimatedBatteryDrain,
    required this.remainingBattery,
    required this.isEnough,
    this.source = PredictionSource.onDeviceFallback,
    this.confidence,
    this.modelSourceDetail,
    this.insightStatus,
  });
}

/// Service tính toán dự báo tiêu hao pin lộ trình
class RoutePredictionService {
  /// Dự báo on-device
  static RoutePredictionResult predict({
    required double distanceKm,
    required int currentBattery,
    required PayloadType payload,
    required List<TripLogModel> trips,
    double defaultEfficiency = 1.2,
    AiVehicleInsight? insight,
  }) {
    // Lấy hiệu suất theo payload từ dữ liệu thực
    double efficiency = defaultEfficiency;

    final matchingTrips = trips.where((t) => t.payloadType == payload).toList();
    if (matchingTrips.isNotEmpty) {
      final eff = BatteryLogicService.avgEfficiency(matchingTrips);
      if (eff > 0) efficiency = eff;
    } else if (trips.isNotEmpty) {
      final eff = BatteryLogicService.avgEfficiency(trips);
      if (eff > 0) {
        efficiency = eff / payload.factor;
      }
    }

    // Nếu có insight, adjust efficiency dựa trên healthScore
    PredictionSource source = PredictionSource.onDeviceFallback;
    double? confidence;
    String? modelSourceDetail;
    String? insightStatus;

    if (insight != null && insight.hasTrained) {
      insightStatus = insight.displayStatus;
      source = PredictionSource.aiInsight;
      confidence = insight.confidence;
      modelSourceDetail = 'web-managed (v${insight.profileVersion})';

      // SoH < 100 → pin chai → hiệu suất giảm
      if (insight.healthScore < 100 && insight.healthScore > 0) {
        final sohFactor = insight.healthScore / 100;
        efficiency = efficiency * sohFactor;
      }
    } else {
      insightStatus = 'missing';
    }

    final drain = BatteryLogicService.batteryDrainForDistance(
      distanceKm,
      efficiency,
      payload,
    );

    final remaining = currentBattery - drain;

    return RoutePredictionResult(
      distanceKm: distanceKm,
      payload: payload,
      efficiencyUsed: efficiency,
      estimatedBatteryDrain: drain,
      remainingBattery: remaining,
      isEnough: remaining >= 5,
      source: source,
      confidence: confidence,
      modelSourceDetail: modelSourceDetail,
      insightStatus: insightStatus,
    );
  }
}

/// Provider cho RoutePredictionService
final routePredictionServiceProvider = Provider<RoutePredictionService>((ref) {
  return RoutePredictionService();
});
