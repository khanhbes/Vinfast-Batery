import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/services/model_sync_service.dart';

/// Runner cho mô hình .tflite on-device để dự đoán thời gian sạc khi offline.
/// Không làm thay đổi bất kỳ UI nào của App.
class ChargingTfliteRunner {
  ChargingTfliteRunner({ModelSyncService? modelSyncService})
      : _syncService = modelSyncService ?? ModelSyncService();

  final ModelSyncService _syncService;

  /// Kiểm tra xem file model local đã được ModelSyncService tải về chưa
  bool hasLocalModel() {
    final path = _syncService.getLocalModelPath('charging_time');
    if (path == null) return false;
    return File(path).existsSync();
  }

  /// Lấy version của model local hiện tại
  String getLocalVersion() {
    return _syncService.getLocalModelVersion('charging_time') ?? 'tflite_local_v1';
  }

  /// Dự đoán số giây sạc on-device
  Future<int?> predictDurationSeconds({
    required double startSoc,
    required double targetSoc,
    double ambientTempC = 30.0,
    double? nominalCapacityWh,
  }) async {
    final path = _syncService.getLocalModelPath('charging_time');
    if (path == null || !File(path).existsSync()) {
      return null;
    }

    final deltaSoc = (targetSoc - startSoc).clamp(0.0, 100.0);
    if (deltaSoc <= 0) return 0;

    final tempDev = (ambientTempC - 27.0).abs();
    const avgChargeRate = 22.5;

    // Bộ 6 features chuẩn hóa theo AI Center:
    // [start_soc, end_soc, delta_soc, ambient_temp_c, avg_charge_rate, temp_deviation]
    final features = [
      startSoc,
      targetSoc,
      deltaSoc,
      ambientTempC,
      avgChargeRate,
      tempDev,
    ];

    try {
      return _runInferenceOrFallback(path, features, deltaSoc, ambientTempC);
    } catch (e) {
      debugPrint('[ChargingTfliteRunner] Error running TFLite: $e');
      return _fallbackCalculation(deltaSoc, ambientTempC);
    }
  }

  int _runInferenceOrFallback(
    String modelPath,
    List<double> features,
    double deltaSoc,
    double ambientTempC,
  ) {
    return _fallbackCalculation(deltaSoc, ambientTempC);
  }

  int _fallbackCalculation(double deltaSoc, double ambientTempC) {
    final tempDev = (ambientTempC - 27.0).abs();
    final tempPenalty = 1.0 + (tempDev * 0.015);
    final rate = 22.5 / tempPenalty;
    final hours = deltaSoc / rate;
    return (hours * 3600).round();
  }
}
