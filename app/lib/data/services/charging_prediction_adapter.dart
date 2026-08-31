import '../../core/services/api_service.dart';
import '../../core/services/app_error_reporter.dart';
import '../../core/constants/app_constants.dart';
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
  }) : _predictionCall = predictionCall ?? ApiService().previewSmartCharge;

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
        final errorMsg =
            response['error']?.toString() ??
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
          endpoint: '/api/smart-charging/preview',
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
      // V4 canonical contract is seconds + rounded display minutes. Accept
      // the legacy minute fields as a compatibility fallback, but never
      // reject a valid V4 response merely because minutes were omitted.
      final durationSecondsValue =
          (data['predictedDurationSeconds'] as num?)?.round() ??
          (data['predictedDurationSec'] as num?)?.round();
      final duration =
          data['predictedMinutes'] ??
          data['predictedDurationMin'] ??
          data['estimatedMinutes'] ??
          (durationSecondsValue == null ? null : durationSecondsValue / 60);
      final minutes = (duration as num?)?.round() ?? 0;
      if (minutes <= 0) {
        throw SmartChargePredictionException(
          message: 'Thời gian sạc dự đoán không hợp lệ (<= 0 phút).',
          debugCode: 'INVALID_DURATION',
        );
      }

      final confidenceValue = data['confidence'];
      final source = data['modelSource']?.toString() ?? 'ai_model';
      // The server is authoritative for eligibility.  Older deployments did
      // not include the boolean and used `ai_model` as the source marker;
      // retain that compatibility rule without misclassifying a
      // personalized/adapter source as a physics fallback.
      final eligibilityValue = data['aiChargeEligible'];
      final aiChargeEligible = eligibilityValue is bool
          ? eligibilityValue
          : source == 'ai_model';
      final durationSeconds =
          durationSecondsValue ??
          minutes * 60;
      final base = SmartChargingPlanPreview.fromPrediction(
        draft: draft,
        predictedMinutes: minutes,
        source: source,
        confidence: confidenceValue is num ? confidenceValue.toDouble() : null,
        predictedDurationSeconds: durationSeconds,
        now: reference,
      );

      return SmartChargingPlanPreview(
        draft: base.draft,
        predictedMinutes: base.predictedMinutes,
        aiStopAt: base.aiStopAt,
        effectiveStopAt: base.effectiveStopAt,
        predictionSource: source,
        predictionConfidence: base.predictionConfidence,
        isPhysicsFallback: !aiChargeEligible ||
            source == 'physics_fallback' ||
            source == 'heuristic',
        isImpossible: base.isImpossible,
        warning: base.warning,
        predictedDurationSeconds: durationSeconds,
        modelKey: 'charging_time',
        modelVersion: data['modelVersion']?.toString() ?? 'unknown',
        runtimeHealth: data['runtimeHealth']?.toString() ??
            (aiChargeEligible ? 'loaded' : 'fallback'),
        warnings: ((data['warnings'] as List?) ?? const [])
            .map((item) => item.toString())
            .toList(),
        fallbackReason: aiChargeEligible
            ? null
            : (data['fallbackReason']?.toString() ?? source),
        analyzedAt:
            DateTime.tryParse(data['analyzedAt']?.toString() ?? '') ??
            reference,
        aiChargeEligible: aiChargeEligible,
      );
    } on SmartChargePredictionException {
      rethrow;
    } catch (e, stack) {
      AppErrorReporter.report(
        e,
        stack,
        source: 'SmartChargePrediction',
        endpoint: '/api/smart-charging/preview',
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
    final capacityWh = draft.estimatedCapacityWh;
    if (capacityWh <= 0) {
      throw StateError(
        'Chưa có dữ liệu dung lượng pin để dùng dự đoán vật lý dự phòng.',
      );
    }
    final requiredWh = capacityWh * (draft.targetSoc - draft.currentSoc) / 100;
    final minutes = ((requiredWh / (powerW * efficiency)) * 60).ceil().clamp(
      1,
      AppConstants.smartChargeMaxMinutes,
    );
    return SmartChargingPlanPreview.fromPrediction(
      draft: draft,
      predictedMinutes: minutes,
      source: 'physics_fallback',
      now: now,
    );
  }
}
