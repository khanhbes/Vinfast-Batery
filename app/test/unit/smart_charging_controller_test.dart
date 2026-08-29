import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';
import 'package:vinfast_battery/data/models/smart_charger_capabilities.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/services/charging_prediction_adapter.dart';
import 'package:vinfast_battery/data/services/smart_charger_service.dart';
import 'package:vinfast_battery/features/ai/controllers/smart_charging_controller.dart';

void main() {
  final now = DateTime.parse('2030-01-01T03:00:00Z');

  SmartChargingController build(
    FakeSmartChargerService service, {
    bool successfulPrediction = true,
  }) => SmartChargingController(
    vehicleId: 'VF-001',
    currentSoc: 20,
    estimatedCapacityWh: 3000,
    service: service,
    predictionAdapter: ChargingPredictionAdapter(
      predictionCall:
          ({
            required vehicleId,
            required currentBattery,
            required targetBattery,
            ambientTempC,
            bool strictAi = false,
          }) async => successfulPrediction
          ? {
              'success': true,
              'data': {
                'predictedDurationMin': 60,
                'modelSource': 'ai_model',
                'confidence': 80,
              },
            }
          : throw Exception('AI offline'),
    ),
    clock: () => now,
    autoInitialize: false,
  );

  test('initialize restores active session from gateway', () async {
    final service = FakeSmartChargerService()..current = session();
    final controller = build(service);
    await controller.initialize();
    expect(controller.state.phase, SmartChargingViewPhase.active);
    expect(controller.state.session?.sessionId, 'session-1');
    expect(service.statusCalls, 1);
    expect(service.currentCalls, 1);
    controller.dispose();
  });

  test('gateway offline does not block plan editing', () async {
    final service = FakeSmartChargerService()..offline = true;
    final controller = build(service);
    await controller.initialize();
    expect(controller.state.phase, SmartChargingViewPhase.editing);
    expect(controller.state.gatewayError, contains('offline'));
    controller.dispose();
  });

  test('unexpected polling error stays inside Smart Charge UI', () async {
    final service = FakeSmartChargerService()..unexpectedFailure = true;
    final controller = build(service);

    await expectLater(controller.initialize(), completes);

    expect(controller.state.phase, SmartChargingViewPhase.editing);
    expect(controller.state.gatewayError, isNotNull);
    controller.dispose();
  });

  test('preview still works while gateway is offline', () async {
    final service = FakeSmartChargerService()..offline = true;
    final controller = build(service);
    await controller.initialize();
    await controller.createPreview();
    expect(controller.state.preview?.predictionSource, 'ai_model');
    expect(controller.state.gatewayError, isNotNull);
    controller.dispose();
  });

  test(
    'AI failure sets error phase and does not silently fall back to physics',
    () async {
      final controller = build(
        FakeSmartChargerService(),
        successfulPrediction: false,
      );
      await controller.createPreview();
      expect(controller.state.phase, SmartChargingViewPhase.error);
      expect(controller.state.preview, isNull);
      expect(controller.state.actionError, isNotNull);
      controller.dispose();
    },
  );

  test('draft mutation clears stale preview', () async {
    final controller = build(FakeSmartChargerService());
    await controller.createPreview();
    controller.updateDraft(targetSoc: 90);
    expect(controller.state.preview, isNull);
    expect(controller.state.draft.targetSoc, 90);
    controller.dispose();
  });

  test('target SOC preview refreshes its relative ten-hour safety window', () async {
    final controller = build(FakeSmartChargerService());
    controller.updateDraft(
      hardDeadlineAt: now.add(const Duration(hours: 4)),
      strategy: ChargingStrategy.targetSoc,
    );

    await controller.createPreview();

    expect(
      controller.state.draft.hardDeadlineAt,
      now.add(SmartChargerService.maxSessionDuration),
    );
    expect(controller.state.preview, isNotNull);
    controller.dispose();
  });

  test('invalid SOC does not call prediction', () async {
    final controller = build(FakeSmartChargerService());
    controller.updateDraft(currentSoc: 90, targetSoc: 80);
    await controller.createPreview();
    expect(controller.state.preview, isNull);
    expect(controller.state.actionError, contains('cao hơn'));
    controller.dispose();
  });

  test('start requires explicit confirmation', () async {
    final service = FakeSmartChargerService();
    final controller = build(service);
    await controller.initialize();
    await controller.createPreview();
    expect(await controller.start(confirmed: false), isFalse);
    expect(service.startCalls, 0);
    controller.dispose();
  });

  test('confirmed start sends acknowledgement and becomes active', () async {
    final service = FakeSmartChargerService();
    final controller = build(service);
    await controller.initialize();
    await controller.createPreview();
    expect(await controller.start(confirmed: true), isTrue);
    expect(service.startCalls, 1);
    expect(service.lastStartRequest?.acknowledgeEstimatedSoc, isTrue);
    expect(service.lastIdempotencyKey, isNotEmpty);
    expect(controller.state.phase, SmartChargingViewPhase.active);
    controller.dispose();
  });

  test('typed start error returns to preview', () async {
    final service = FakeSmartChargerService()..startError = true;
    final controller = build(service);
    await controller.initialize();
    await controller.createPreview();
    expect(await controller.start(confirmed: true), isFalse);
    expect(controller.state.phase, SmartChargingViewPhase.preview);
    expect(controller.state.actionError, contains('version conflict'));
    controller.dispose();
  });

  test('stop sends expected version and updates history', () async {
    final service = FakeSmartChargerService()..current = session();
    final controller = build(service);
    await controller.initialize();
    expect(await controller.stop(), isTrue);
    expect(service.stoppedVersion, 2);
    expect(
      controller.state.history.first.state,
      ChargingSessionState.cancelled,
    );
    controller.dispose();
  });

  test('manual OFF remains available without a session', () async {
    final service = FakeSmartChargerService();
    final controller = build(service);
    expect(await controller.manualOff(), isTrue);
    expect(service.offCalls, 1);
    controller.dispose();
  });
}

class FakeSmartChargerService extends SmartChargerService {
  FakeSmartChargerService()
    : super(baseUrl: 'http://gateway', tokenProvider: _emptyToken);

  bool offline = false;
  bool unexpectedFailure = false;
  bool startError = false;
  SmartChargingSession? current;
  int statusCalls = 0;
  int currentCalls = 0;
  int startCalls = 0;
  int offCalls = 0;
  int? stoppedVersion;
  SmartChargingSessionRequest? lastStartRequest;
  String? lastIdempotencyKey;

  @override
  Future<SmartChargerCapabilities> capabilities() async =>
      const SmartChargerCapabilities(
        canReadStatus: true,
        canManualOn: true,
        canManualOff: true,
        supportsDeviceTimer: true,
        canReadPower: true,
        canConfigureSafeBoot: true,
        cloudAvailable: true,
        lanAvailable: true,
        safeBootVerified: true,
        noLoadTestVerified: true,
        readyForControl: true,
      );

  @override
  Future<SmartChargerStatus> getStatus() async {
    statusCalls++;
    if (unexpectedFailure) throw const FormatException('invalid cloud body');
    if (offline) throw const SmartChargerException('Gateway offline');
    return const SmartChargerStatus(
      online: true,
      relay: false,
      powerW: 0,
      voltageV: 230,
      currentA: 0,
      frequencyHz: 50,
      temperatureC: null,
      energyWh: 100,
    );
  }

  @override
  Future<SmartChargingSession?> getCurrentSession() async {
    currentCalls++;
    if (unexpectedFailure) throw const FormatException('invalid session body');
    if (offline) throw const SmartChargerException('Gateway offline');
    return current;
  }

  @override
  Future<List<SmartChargingSession>> getSessionHistory({int limit = 20}) async {
    if (unexpectedFailure) throw const FormatException('invalid history body');
    if (offline) throw const SmartChargerException('Gateway offline');
    return const [];
  }

  @override
  Future<SmartChargingSession> startAutomaticSession(
    SmartChargingSessionRequest request, {
    required String idempotencyKey,
  }) async {
    startCalls++;
    lastStartRequest = request;
    lastIdempotencyKey = idempotencyKey;
    if (startError) {
      throw const SmartChargerException(
        'version conflict',
        code: 'VERSION_CONFLICT',
        statusCode: 409,
      );
    }
    return current = session();
  }

  @override
  Future<SmartChargingSession> stopSession(
    String sessionId, {
    int? expectedVersion,
  }) async {
    stoppedVersion = expectedVersion;
    return current = session(state: 'cancelled', stopReason: 'manual');
  }

  @override
  Future<SmartChargerCommandResult> turnOff() async {
    offCalls++;
    return const SmartChargerCommandResult(
      success: true,
      relay: false,
      previousState: true,
    );
  }
}

Future<String?> _emptyToken() async => 'token';

SmartChargingSession session({String state = 'active', String? stopReason}) =>
    SmartChargingSession.fromJson({
      'session_id': 'session-1',
      'vehicle_id': 'VF-001',
      'state': state,
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
      'stop_reason': stopReason,
      'relay_verified': true,
      'energy_used_wh': 120,
      'energy_quality': 'good',
      'estimated_soc': 25,
      'shadow_mode': true,
      'version': 2,
    });
