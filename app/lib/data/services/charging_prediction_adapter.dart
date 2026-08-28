import '../../core/constants/app_constants.dart';
import '../../core/services/api_service.dart';
import '../models/smart_charging_session.dart';

typedef ChargingPredictionCall =
    Future<Map<String, dynamic>> Function({
      required String vehicleId,
      required int currentBattery,
      required int targetBattery,
      double? ambientTempC,
    });

class ChargingPredictionAdapter {
  ChargingPredictionAdapter({
    ChargingPredictionCall? predictionCall,
    this.standardPowerW = 400,
    this.fastPowerW = 1000,
    this.efficiency = 0.9,
  }) : _predictionCall = predictionCall ?? ApiService().predictChargingTime;

  final ChargingPredictionCall _predictionCall;
  final double standardPowerW;
  final double fastPowerW;
  final double efficiency;

  Future<SmartChargingPlanPreview> predict(
    SmartChargingPlanDraft draft, {
    DateTime? now,
  }) async {
    final reference = now ?? DateTime.now();
    final validation = draft.validate(now: reference);
    if (validation != null) throw ArgumentError(validation);
    try {
      final response = await _predictionCall(
        vehicleId: draft.vehicleId,
        currentBattery: draft.currentSoc.round(),
        targetBattery: draft.targetSoc.round(),
      );
      if (response['success'] != true) {
        throw const FormatException('Prediction failed.');
      }
      final rawData = response['data'];
      if (rawData is! Map) {
        throw const FormatException('Prediction data missing.');
      }
      final data = Map<String, dynamic>.from(rawData);
      final duration = data['predictedDurationMin'] ?? data['estimatedMinutes'];
      final minutes = (duration as num?)?.round() ?? 0;
      if (minutes <= 0) {
        throw const FormatException('Prediction duration invalid.');
      }
      final confidenceValue = data['confidence'];
      return SmartChargingPlanPreview.fromPrediction(
        draft: draft,
        predictedMinutes: minutes,
        source: data['modelSource']?.toString() ?? 'ai_model',
        confidence: confidenceValue is num ? confidenceValue.toDouble() : null,
        now: reference,
      );
    } catch (_) {
      return physicsFallback(draft, now: reference);
    }
  }

  SmartChargingPlanPreview physicsFallback(
    SmartChargingPlanDraft draft, {
    DateTime? now,
  }) {
    final powerW = draft.chargingMode == 'fast' ? fastPowerW : standardPowerW;
    if (powerW <= 0 || efficiency <= 0 || efficiency > 1) {
      throw StateError('Cấu hình công suất/hiệu suất bộ sạc không hợp lệ.');
    }
    final capacityWh = draft.estimatedCapacityWh > 0
        ? draft.estimatedCapacityWh
        : AppConstants.defaultBatteryCapacityWh;
    final requiredWh = capacityWh * (draft.targetSoc - draft.currentSoc) / 100;
    final minutes = ((requiredWh / (powerW * efficiency)) * 60).ceil().clamp(
      1,
      1440,
    );
    return SmartChargingPlanPreview.fromPrediction(
      draft: draft,
      predictedMinutes: minutes,
      source: 'physics_fallback',
      now: now,
    );
  }
}
