import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/trip_log_model.dart';
import 'battery_logic_service.dart';

/// ========================================================================
/// Route Prediction Service — Dự báo tiêu hao pin cho lộ trình
/// ========================================================================

/// Abstraction cho provider khoảng cách lộ trình.
/// Mock bản đầu, có thể thay bằng Google Maps API sau.
abstract class RouteDistanceProvider {
  /// Trả về khoảng cách (km) cho tuyến đường.
  /// [destination]: mô tả điểm đến (text).
  Future<double?> getDistance(String destination);
}

/// Mock provider: trả về distance do user tự nhập.
class MockRouteDistanceProvider implements RouteDistanceProvider {
  final double manualDistanceKm;

  MockRouteDistanceProvider({required this.manualDistanceKm});

  @override
  Future<double?> getDistance(String destination) async {
    return manualDistanceKm;
  }
}

/// Kết quả dự đoán lộ trình
class RoutePredictionResult {
  final double distanceKm;
  final PayloadType payload;
  final double efficiencyUsed;
  final int estimatedBatteryDrain;
  final int remainingBattery;
  final bool isEnough;

  RoutePredictionResult({
    required this.distanceKm,
    required this.payload,
    required this.efficiencyUsed,
    required this.estimatedBatteryDrain,
    required this.remainingBattery,
    required this.isEnough,
  });
}

/// Service tính toán dự báo tiêu hao pin lộ trình
class RoutePredictionService {
  /// Dự báo tiêu hao pin cho lộ trình
  ///
  /// [distanceKm]: khoảng cách (km)
  /// [currentBattery]: % pin hiện tại
  /// [payload]: tải trọng
  /// [trips]: danh sách chuyến đi gần đây (để lấy hiệu suất thực tế)
  /// [defaultEfficiency]: hiệu suất mặc định khi thiếu dữ liệu trip
  static RoutePredictionResult predict({
    required double distanceKm,
    required int currentBattery,
    required PayloadType payload,
    required List<TripLogModel> trips,
    double defaultEfficiency = 1.2,
  }) {
    // Lấy hiệu suất theo payload từ dữ liệu thực
    double efficiency = defaultEfficiency;

    final matchingTrips = trips.where((t) => t.payloadType == payload).toList();
    if (matchingTrips.isNotEmpty) {
      final eff = BatteryLogicService.avgEfficiency(matchingTrips);
      if (eff > 0) efficiency = eff;
    } else if (trips.isNotEmpty) {
      // Fallback: dùng tất cả trips + adjust theo hệ số payload
      final eff = BatteryLogicService.avgEfficiency(trips);
      if (eff > 0) {
        // Nếu trips phần lớn 1 người, điều chỉnh cho 2 người
        efficiency = eff / payload.factor;
      }
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
      isEnough: remaining >= 5, // Giữ buffer 5%
    );
  }
}

/// Provider cho RoutePredictionService
final routePredictionServiceProvider = Provider<RoutePredictionService>((ref) {
  return RoutePredictionService();
});
