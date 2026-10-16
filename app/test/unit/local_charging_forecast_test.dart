import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/repositories/smart_charger_repository.dart';
import 'package:vinfast_battery/data/services/charging_prediction_adapter.dart';
import 'package:vinfast_battery/data/services/charging_tflite_runner.dart';
import 'package:vinfast_battery/data/services/charging_training_sync_service.dart';
import 'package:vinfast_battery/data/services/server_smart_charger_service.dart';
import 'package:vinfast_battery/data/services/smart_charger_service.dart';
import 'package:vinfast_battery/features/ai/controllers/smart_charging_controller.dart';

class _Runner extends ChargingTfliteRunner {
  _Runner({this.seconds = 1801, this.available = true});
  final int? seconds;
  final bool available;
  @override
  bool hasLocalModel() => available;
  @override
  String getLocalVersion() => 'qa-local';
  @override
  Future<int?> predictDurationSeconds({
    required double startSoc,
    required double targetSoc,
    double ambientTempC = 30,
    double? nominalCapacityWh,
  }) async => seconds;
}

class _Auth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Auth accessed');
}

class _Server extends ServerSmartChargerService {
  _Server() : super(auth: _Auth());
  int remotePredictions = 0;
  int timedCalls = 0;
  int trainingCalls = 0;
  int historyConfirmations = 0;
  Duration? requestedTimer;
  @override
  Future<Map<String, dynamic>> ingestPersonalTraining(String sessionId) async {
    trainingCalls++;
    throw StateError('Cloud training attempted');
  }

  @override
  Future<SmartChargingSession> confirmActualSoc(
    String sessionId,
    double soc,
  ) async {
    historyConfirmations++;
    throw const SmartChargerException('QA history offline', code: 'qaHistory');
  }

  @override
  Future<SmartChargingPlanPreview> createPreview(
    SmartChargingPlanDraft draft,
  ) async {
    remotePredictions++;
    throw StateError('Remote prediction called');
  }

  @override
  Future<SmartChargingSession> manualOn(
    Duration duration, {
    required String idempotencyKey,
    required String vehicleId,
    required double currentSoc,
    String? expectedDeviceId,
    double? targetSoc,
  }) async {
    timedCalls++;
    requestedTimer = duration;
    throw const SmartChargerException('QA sentinel', code: 'qaTimer');
  }
}

class _Direct extends SmartChargerService {
  int starts = 0;
  @override
  Future<SmartChargingSession> startAutomaticSession(
    SmartChargingSessionRequest request, {
    String? idempotencyKey,
  }) async {
    starts++;
    throw StateError('ON attempted');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2030, 1, 1);
  SmartChargingPlanDraft draft({
    double current = 20,
    double target = 80,
    int deadlineMinutes = 120,
  }) => SmartChargingPlanDraft(
    vehicleId: 'qa-vehicle',
    currentSoc: current,
    targetSoc: target,
    hardDeadlineAt: now.add(Duration(minutes: deadlineMinutes)),
    estimatedCapacityWh: 3000,
  );

  ChargingPredictionAdapter local({_Runner? runner, bool physics = false}) =>
      ChargingPredictionAdapter(
        tfliteRunner: runner ?? _Runner(),
        allowPhysicsFallback: physics,
        predictionCall:
            ({
              required vehicleId,
              required currentBattery,
              required targetBattery,
              ambientTempC,
              bool strictAi = true,
            }) async => throw StateError('Cloud AI attempted'),
      );

  test(
    'default forecasting runs locally, preserves seconds and grants no control',
    () async {
      final preview = await local().predict(draft(), now: now);
      expect(preview.predictedDurationSeconds, 1801);
      expect(preview.predictedMinutes, 31);
      expect(preview.aiStopAt, now.add(const Duration(seconds: 1801)));
      expect(preview.predictionConfidence, isNull);
      expect(preview.aiChargeEligible, isFalse);
      expect(preview.isDisplayOnly, isTrue);
      expect(preview.previewId, isNull);
      expect(preview.modelVersion, 'qa-local');
    },
  );

  test(
    'short local forecast never displays zero minutes and keeps deadline warning',
    () async {
      final short = await local(
        runner: _Runner(seconds: 20),
      ).predict(draft(), now: now);
      expect(short.predictedMinutes, 1);
      final long = await local().predict(draft(deadlineMinutes: 10), now: now);
      expect(long.isImpossible, isTrue);
      expect(long.warning, isNotNull);
    },
  );

  test(
    'missing, invalid or excessive model output does not call cloud AI',
    () async {
      for (final runner in [
        _Runner(available: false),
        _Runner(seconds: null),
        _Runner(seconds: 0),
        _Runner(seconds: 36001),
      ]) {
        await expectLater(
          local(runner: runner).predict(draft(), now: now),
          throwsA(
            isA<SmartChargePredictionException>().having(
              (error) => error.debugCode,
              'code',
              'LOCAL_MODEL_UNAVAILABLE',
            ),
          ),
        );
      }
    },
  );

  test('explicit physics estimate remains labelled and display-only', () async {
    final preview = await local(
      runner: _Runner(available: false),
      physics: true,
    ).predict(draft(), now: now);
    expect(preview.predictionSource, 'physics_fallback');
    expect(preview.isPhysicsFallback, isTrue);
    expect(preview.isDisplayOnly, isTrue);
    expect(preview.aiChargeEligible, isFalse);
  });

  test('nonfinite SOC cannot enter prediction contract', () async {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      await expectLater(
        local().predict(draft(current: value), now: now),
        throwsArgumentError,
      );
      await expectLater(
        local().predict(draft(target: value), now: now),
        throwsArgumentError,
      );
    }
  });

  test(
    'server repository forecasts locally while timed control stays server-owned',
    () async {
      final service = _Server();
      final repository = ServerSmartChargerRepository(
        service,
        predictor: local(),
      );
      final preview = await repository.preview(draft());
      expect(preview.isDisplayOnly, isTrue);
      expect(service.remotePredictions, 0);
      await expectLater(
        repository.start(preview, 'qa-operation'),
        throwsA(
          isA<SmartChargerException>().having(
            (error) => error.code,
            'code',
            'previewMissing',
          ),
        ),
      );
      await expectLater(
        repository.manualOn(
          const Duration(minutes: 5),
          'qa-timer',
          vehicleId: 'qa-vehicle',
          currentSoc: 20,
        ),
        throwsA(
          isA<SmartChargerException>().having(
            (error) => error.code,
            'code',
            'qaTimer',
          ),
        ),
      );
      expect(service.timedCalls, 1);
      expect(service.requestedTimer, const Duration(minutes: 5));
    },
  );

  test(
    'direct repository cannot energize from a display-only forecast',
    () async {
      final service = _Direct();
      final repository = DirectSmartChargerRepository(
        service,
        local(),
        previewService: _Server(),
      );
      final preview = await repository.preview(draft());
      await expectLater(
        repository.start(preview, 'qa-operation'),
        throwsA(
          isA<SmartChargerException>().having(
            (error) => error.code,
            'code',
            'forecastDisplayOnly',
          ),
        ),
      );
      expect(service.starts, 0);
    },
  );

  test(
    'controller explicitly rejects confirmed local forecast before relay call',
    () async {
      final service = _Direct();
      final controller = SmartChargingController(
        vehicleId: 'qa-vehicle',
        currentSoc: 20,
        estimatedCapacityWh: 3000,
        clock: () => now,
        autoInitialize: false,
        repository: DirectSmartChargerRepository(service, local()),
      );
      addTearDown(controller.dispose);
      await controller.createPreview();
      expect(controller.state.preview?.isDisplayOnly, isTrue);
      expect(await controller.start(confirmed: true), isFalse);
      expect(controller.state.actionError, contains('tham khảo'));
      expect(service.starts, 0);
    },
  );

  test(
    'cloud training disabled preserves legacy queue and adds no upload task',
    () async {
      SharedPreferences.setMockInitialValues({
        'smart_charge.training_queue.v3': ['legacy-qa-session'],
      });
      final server = _Server();
      final sync = ChargingTrainingSyncService(server: server);
      await sync.enqueue('new-qa-session');
      expect(await sync.flush(), 0);
      expect(server.trainingCalls, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('smart_charge.training_queue.v3'), [
        'legacy-qa-session',
      ]);
    },
  );

  test(
    'end-SOC history confirmation remains retryable without cloud training',
    () async {
      SharedPreferences.setMockInitialValues({});
      final server = _Server();
      final sync = ChargingTrainingSyncService(server: server);
      await sync.enqueueActualSoc('qa-session', 50);
      expect(await sync.flush(), 0);
      expect(server.historyConfirmations, 1);
      expect(server.trainingCalls, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('smart_charge.actual_soc_queue.v1'),
        contains('qa-session'),
      );
    },
  );
}
