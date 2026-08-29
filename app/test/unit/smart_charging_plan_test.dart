import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/services/charging_prediction_adapter.dart';

void main() {
  final now = DateTime.parse('2030-01-01T10:00:00+07:00');

  SmartChargingPlanDraft draft({
    double current = 20,
    double target = 80,
    int deadlineMinutes = 120,
    ChargingStrategy strategy = ChargingStrategy.smartCombined,
  }) => SmartChargingPlanDraft(
    vehicleId: 'VF-001',
    currentSoc: current,
    targetSoc: target,
    hardDeadlineAt: now.add(Duration(minutes: deadlineMinutes)),
    strategy: strategy,
    estimatedCapacityWh: 3000,
  );

  test('strategy enum uses explicit JSON values', () {
    expect(ChargingStrategy.targetSoc.wireValue, 'target_soc');
    expect(ChargingStrategy.deadline.wireValue, 'deadline');
    expect(ChargingStrategy.smartCombined.wireValue, 'smart_combined');
  });

  test('strategy parser rejects unknown values', () {
    expect(() => ChargingStrategy.fromJson('magic'), throwsFormatException);
  });

  test('session state terminal mapping is explicit', () {
    expect(ChargingSessionState.fromJson('active').isTerminal, isFalse);
    expect(ChargingSessionState.fromJson('completed').isTerminal, isTrue);
    expect(ChargingSessionState.fromJson('failed').isTerminal, isTrue);
  });

  test('stop reason parser handles null and known values', () {
    expect(ChargingStopReason.fromJson(null), isNull);
    expect(ChargingStopReason.fromJson('manual'), ChargingStopReason.manual);
  });

  test('draft requires vehicle', () {
    final value = SmartChargingPlanDraft(
      vehicleId: '',
      currentSoc: 20,
      targetSoc: 80,
      hardDeadlineAt: now.add(const Duration(hours: 1)),
    );
    expect(value.validate(now: now), contains('chọn xe'));
  });

  test('draft validates current SOC range', () {
    expect(draft(current: -1).validate(now: now), contains('0–100'));
    expect(draft(current: 101, target: 100).validate(now: now), isNotNull);
  });

  test('draft rejects target not greater than current', () {
    expect(
      draft(current: 80, target: 80).validate(now: now),
      contains('cao hơn'),
    );
  });

  test('draft rejects past deadline', () {
    expect(
      draft(deadlineMinutes: -1).validate(now: now),
      contains('tương lai'),
    );
  });

  test('real AI preview does not require battery capacity metadata', () {
    final value = SmartChargingPlanDraft(
      vehicleId: 'VF-001',
      currentSoc: 20,
      targetSoc: 80,
      hardDeadlineAt: now.add(const Duration(hours: 2)),
      estimatedCapacityWh: 0,
    );
    expect(value.validate(now: now), isNull);
  });

  test('target strategy uses AI ETA', () {
    final preview = SmartChargingPlanPreview.fromPrediction(
      draft: draft(strategy: ChargingStrategy.targetSoc),
      predictedMinutes: 60,
      source: 'ai_model',
      now: now,
    );
    expect(preview.effectiveStopAt, now.add(const Duration(minutes: 60)));
  });

  test('hard deadline caps target strategy', () {
    final preview = SmartChargingPlanPreview.fromPrediction(
      draft: draft(strategy: ChargingStrategy.targetSoc, deadlineMinutes: 20),
      predictedMinutes: 60,
      source: 'ai_model',
      now: now,
    );
    expect(preview.effectiveStopAt, now.add(const Duration(minutes: 20)));
  });

  test('deadline strategy uses hard deadline', () {
    final preview = SmartChargingPlanPreview.fromPrediction(
      draft: draft(strategy: ChargingStrategy.deadline),
      predictedMinutes: 60,
      source: 'ai_model',
      now: now,
    );
    expect(preview.effectiveStopAt, now.add(const Duration(minutes: 120)));
  });

  test('combined strategy picks earlier cutoff', () {
    final preview = SmartChargingPlanPreview.fromPrediction(
      draft: draft(deadlineMinutes: 40),
      predictedMinutes: 60,
      source: 'ai_model',
      now: now,
    );
    expect(preview.effectiveStopAt, now.add(const Duration(minutes: 40)));
  });

  test('insufficient time produces explicit warning', () {
    final preview = SmartChargingPlanPreview.fromPrediction(
      draft: draft(deadlineMinutes: 20),
      predictedMinutes: 60,
      source: 'ai_model',
      now: now,
    );
    expect(preview.isImpossible, isTrue);
    expect(preview.warning, contains('Không đủ thời gian'));
  });

  test('AI result preserves source and confidence', () async {
    final adapter = ChargingPredictionAdapter(
      predictionCall:
          ({
            required vehicleId,
            required currentBattery,
            required targetBattery,
            ambientTempC,
            bool strictAi = false,
          }) async => {
            'success': true,
            'data': {
              'predictedDurationMin': 45.4,
              'modelSource': 'tflite',
              'confidence': 91,
            },
          },
    );
    final preview = await adapter.predict(draft(), now: now);
    expect(preview.predictedMinutes, 45);
    expect(preview.predictionSource, 'tflite');
    expect(preview.predictionConfidence, 91);
  });

  test(
    'API failure in strict AI mode throws SmartChargePredictionException',
    () async {
      final adapter = ChargingPredictionAdapter(
        predictionCall:
            ({
              required vehicleId,
              required currentBattery,
              required targetBattery,
              ambientTempC,
              bool strictAi = false,
            }) async => {
              'success': false,
              'statusCode': 503,
              'error': 'Model AI hiện chưa khả dụng.',
              'debugCode': 'AI_MODEL_UNAVAILABLE',
            },
      );
      expect(
        () => adapter.predict(draft(current: 20, target: 30), now: now),
        throwsA(isA<SmartChargePredictionException>()),
      );
    },
  );

  test(
    'API failure uses Wh-dimensional physics fallback when allowPhysicsFallback is true',
    () async {
      final adapter = ChargingPredictionAdapter(
        standardPowerW: 400,
        efficiency: 1,
        allowPhysicsFallback: true,
        predictionCall:
            ({
              required vehicleId,
              required currentBattery,
              required targetBattery,
              ambientTempC,
              bool strictAi = false,
            }) async => throw Exception('offline'),
      );
      final preview = await adapter.predict(
        draft(current: 20, target: 30),
        now: now,
      );
      // 300 Wh / 400 W = 0.75 h = 45 minutes.
      expect(preview.predictedMinutes, 45);
      expect(preview.predictionSource, 'physics_fallback');
      expect(preview.isPhysicsFallback, isTrue);
    },
  );

  test('physics fallback rejects invalid charger configuration', () {
    final adapter = ChargingPredictionAdapter(standardPowerW: 0);
    expect(() => adapter.physicsFallback(draft(), now: now), throwsStateError);
  });

  test('automatic request serializes UTC and acknowledgement', () {
    final request = SmartChargingSessionRequest(
      vehicleId: 'VF-001',
      startSoc: 20,
      targetSoc: 80,
      predictedMinutes: 60,
      startedAt: now,
      predictedFullAt: now.add(const Duration(hours: 1)),
      chargingMode: 'standard',
      hardDeadlineAt: now.add(const Duration(hours: 2)),
      acknowledgeEstimatedSoc: true,
    ).toAutomaticJson();
    expect(request['strategy'], 'smart_combined');
    expect(request['acknowledge_estimated_soc'], isTrue);
    expect(request['hard_deadline_at'], endsWith('Z'));
  });

  test('session parser keeps timezone-aware timestamps', () {
    final session = SmartChargingSession.fromJson(sessionJson());
    expect(session.effectiveStopAt.isUtc, isTrue);
    expect(session.state, ChargingSessionState.active);
    expect(session.shadowMode, isTrue);
  });

  test('session remaining never becomes negative', () {
    final session = SmartChargingSession.fromJson(sessionJson());
    expect(
      session.remaining(DateTime.parse('2030-01-01T13:00:00Z')),
      Duration.zero,
    );
  });

  test('malformed session is rejected', () {
    expect(
      () => SmartChargingSession.fromJson({'session_id': ''}),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> sessionJson() => {
  'session_id': 'session-1',
  'vehicle_id': 'VF-001',
  'state': 'active',
  'strategy': 'smart_combined',
  'start_soc': 20,
  'target_soc': 80,
  'predicted_minutes': 60,
  'prediction_source': 'ai_model',
  'created_at': '2030-01-01T03:00:00Z',
  'updated_at': '2030-01-01T03:00:00Z',
  'started_at': '2030-01-01T03:00:00Z',
  'ai_stop_at': '2030-01-01T04:00:00Z',
  'hard_deadline_at': '2030-01-01T05:00:00Z',
  'effective_stop_at': '2030-01-01T04:00:00Z',
  'absolute_safety_stop_at': '2030-01-01T07:00:00Z',
  'relay_verified': true,
  'energy_used_wh': 120,
  'energy_quality': 'good',
  'estimated_soc': 25,
  'shadow_mode': true,
  'version': 2,
};
