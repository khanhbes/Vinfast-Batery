import '../../core/constants/app_constants.dart';
import '../../core/services/api_service.dart';
import '../../core/services/app_error_reporter.dart';
import '../models/smart_charging_session.dart';

typedef ChargingPredictionCall =
    Future<Map<String, dynamic>> Function({
      required String vehicleId,
      required int currentBattery,
      required int targetBattery,
      double? ambientTempC,
      bool strictAi,
    });

/// Exception thrown when Smart Charge AI prediction fails
class SmartChargePredictionException implements Exception {
  SmartChargePredictionException({
    required this.message,
    this.statusCode,
    this.debugCode,
    this.debugDetail,
  });

  final String message;
  final int? statusCode;
  final String? debugCode;
  final String? debugDetail;

  @override
  String toString() => message;
}

class ChargingPredictionAdapter {
  ChargingPredictionAdapter({
    ChargingPredictionCall? predictionCall,
    this.standardPowerW = 400,
    this.fastPowerW = 1000,
    this.efficiency = 0.9,
    this.strictAi = true,
    this.allowPhysicsFallback = false,
  }) : _predictionCall = predictionCall ?? ApiService().predictChargingTime;

  final ChargingPredictionCall _predictionCall;
  final double standardPowerW;
  final double fastPowerW;
  final double efficiency;
  final bool strictAi;
  final bool allowPhysicsFallback;

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
        strictAi: strictAi,
      );

      if (response['success'] != true) {
        final errorMsg = response['error']?.toString() ??
            'Không thể tính thời gian sạc từ AI model.';
        final debugCode = response['debugCode']?.toString();
        final debugDetail = response['debugDetail']?.toString();
        final statusCode = response['statusCode'] as int?;

        final exc = SmartChargePredictionException(
          message: errorMsg,
          statusCode: statusCode,
          debugCode: debugCode,
          debugDetail: debugDetail,
        );

        AppErrorReporter.report(
          exc,
          StackTrace.current,
          source: 'SmartChargePrediction',
          endpoint: '/api/ai/predict-charging-time',
          statusCode: statusCode,
          debugCode: debugCode,
          debugDetail: debugDetail,
        );

        if (allowPhysicsFallback) {
          return physicsFallback(draft, now: reference);
        }
        throw exc;
      }

      final rawData = response['data'];
      if (rawData is! Map) {
        throw SmartChargePredictionException(
          message: 'Dữ liệu dự đoán thời gian sạc không hợp lệ.',
          debugCode: 'INVALID_AI_RESPONSE',
        );
      }

      final data = Map<String, dynamic>.from(rawData);
      final duration = data['predictedDurationMin'] ?? data['estimatedMinutes'];
      final minutes = (duration as num?)?.round() ?? 0;
      if (minutes <= 0) {
        throw SmartChargePredictionException(
          message: 'Thời gian sạc dự đoán không hợp lệ (<= 0 phút).',
          debugCode: 'INVALID_DURATION',
        );
      }

      final confidenceValue = data['confidence'];
      final source = data['modelSource']?.toString() ?? 'ai_model';
      final base = SmartChargingPlanPreview.fromPrediction(
        draft: draft,
        predictedMinutes: minutes,
        source: source,
        confidence: confidenceValue is num ? confidenceValue.toDouble() : null,
        now: reference,
      );

      return SmartChargingPlanPreview(
        draft: base.draft,
        predictedMinutes: base.predictedMinutes,
        aiStopAt: base.aiStopAt,
        effectiveStopAt: base.effectiveStopAt,
        predictionSource: source,
        predictionConfidence: base.predictionConfidence,
        isPhysicsFallback: source != 'ai_model',
        isImpossible: base.isImpossible,
        warning: base.warning,
        predictedDurationSeconds:
            (data['predictedDurationSec'] as num?)?.round() ?? minutes * 60,
        modelKey: 'charging_time',
        modelVersion: data['modelVersion']?.toString() ?? 'unknown',
        runtimeHealth: source == 'ai_model' ? 'loaded' : 'fallback',
        warnings: ((data['warnings'] as List?) ?? const [])
            .map((item) => item.toString())
            .toList(),
        fallbackReason: source == 'ai_model' ? null : source,
        analyzedAt: DateTime.tryParse(data['analyzedAt']?.toString() ?? '') ??
            reference,
        aiChargeEligible: source == 'ai_model',
      );
    } on SmartChargePredictionException {
      rethrow;
    } catch (e, stack) {
      AppErrorReporter.report(
        e,
        stack,
        source: 'SmartChargePrediction',
        endpoint: '/api/ai/predict-charging-time',
        debugCode: 'PREDICTION_EXCEPTION',
      );
      if (allowPhysicsFallback) {
        return physicsFallback(draft, now: reference);
      }
      throw SmartChargePredictionException(
        message: 'Không thể tính thời gian sạc: $e',
        debugCode: 'PREDICTION_EXCEPTION',
      );
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
