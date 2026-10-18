import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vinfast_battery/core/constants/app_constants.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/repositories/smart_charger_repository.dart';
import 'package:vinfast_battery/data/services/charge_estimator.dart';
import 'package:vinfast_battery/data/services/range_estimator.dart';
import 'package:vinfast_battery/data/services/server_smart_charger_service.dart';
import 'package:vinfast_battery/features/ai/controllers/smart_charging_controller.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'qa-122';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'qa-token';
}

class _Auth extends Fake implements FirebaseAuth {
  final user = _User();
  @override
  User? get currentUser => user;
}

/// Answers each /live request when the test completes its completer.
class _GatedClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final gates = <Completer<bool>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final gate = Completer<bool>();
    gates.add(gate);
    final relay = await gate.future;
    final body = jsonEncode({
      'success': true,
      'data': {
        'status': {'online': true, 'relay': relay},
      },
    });
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

SmartChargerStatus _status({bool relay = true}) => SmartChargerStatus(
  deviceId: 'shelly-1',
  online: true,
  relay: relay,
  powerW: 420,
  voltageV: 230,
  currentA: 1.8,
  frequencyHz: 50,
  temperatureC: 31,
  energyWh: 10,
  timerRemaining: const Duration(minutes: 3),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChargeEstimator', () {
    test('prefers live, then history, then spec, then standard power', () {
      expect(
        ChargeEstimator.pickPower(
          liveSamples: const [400, 410, 420],
          recentSessionPowers: const [300],
          specMaxPowerW: 600,
        ).source,
        ChargePowerSource.measuredLive,
      );
      final history = ChargeEstimator.pickPower(
        liveSamples: const [400], // too few live samples
        recentSessionPowers: const [300, 320, 5],
        specMaxPowerW: 600,
      );
      expect(history.source, ChargePowerSource.measuredHistory);
      expect(history.watts, 310); // idle 5 W reading ignored
      expect(
        ChargeEstimator.pickPower(specMaxPowerW: 600).source,
        ChargePowerSource.vehicleSpec,
      );
      final standard = ChargeEstimator.pickPower();
      expect(standard.source, ChargePowerSource.standard);
      expect(standard.watts, ChargeEstimator.standardPowerW);
    });

    test('top-up above 95 % is slower than the same span below it', () {
      final low = ChargeEstimator.estimate(
        currentSoc: 40,
        targetSoc: 50,
        capacityWh: 2000,
        powerW: 400,
        powerSource: ChargePowerSource.measuredLive,
      )!;
      final high = ChargeEstimator.estimate(
        currentSoc: 90,
        targetSoc: 100,
        capacityWh: 2000,
        powerW: 400,
        powerSource: ChargePowerSource.measuredLive,
      )!;
      expect(high.minutes, greaterThan(low.minutes));
      expect(low.cvMinutes, 0);
      // 200 Wh at 360 W effective = 34 min (ceil).
      expect(low.minutes, 34);
    });

    test('unknown capacity or nothing to charge gives no estimate', () {
      expect(
        ChargeEstimator.estimate(
          currentSoc: 50,
          targetSoc: 80,
          capacityWh: 0,
          powerW: 400,
          powerSource: ChargePowerSource.standard,
        ),
        isNull,
      );
      expect(
        ChargeEstimator.estimate(
          currentSoc: 80,
          targetSoc: 80,
          capacityWh: 2000,
          powerW: 400,
          powerSource: ChargePowerSource.standard,
        ),
        isNull,
      );
    });

    test('one duration wording everywhere', () {
      expect(formatChargeDuration(const Duration(minutes: 45)), '45 phút');
      expect(formatChargeDuration(const Duration(minutes: 120)), '2 giờ');
      expect(
        formatChargeDuration(const Duration(minutes: 70)),
        '1 giờ 10 phút',
      );
      expect(formatChargeDurationShort(const Duration(minutes: 70)), '1g10');
      expect(formatClock(DateTime(2026, 10, 14, 7, 5)), '07:05');
    });
  });

  group('estimateRangeKm', () {
    test('keeps a 5 % reserve and scales by SoH', () {
      final vehicle = VehicleModel(
        vehicleId: 'v1',
        currentOdo: 100,
        currentBattery: 55,
        stateOfHealth: 90,
        defaultEfficiency: 1.2,
      );
      expect(estimateRangeKm(vehicle), closeTo(50 * 1.2 * 0.9, 1e-9));
      expect(estimateRangeKm(vehicle, socOverride: 3), 0);
    });

    test('missing vehicle data gives no number instead of a guess', () {
      final vehicle = VehicleModel(
        vehicleId: 'v1',
        currentOdo: 100,
        hasEfficiencyData: false,
      );
      expect(estimateRangeKm(vehicle), isNull);
    });
  });

  group('shared /live reads', () {
    setUp(() {
      AppConstants.setCustomApiBaseUrl('https://qa.example.com');
      ServerSmartChargerService.forgetLive();
    });
    tearDown(() {
      AppConstants.setCustomApiBaseUrl(null);
      ServerSmartChargerService.forgetLive();
    });

    test('display polls share one in-flight read', () async {
      final client = _GatedClient();
      final service = ServerSmartChargerService(client: client, auth: _Auth());
      final a = service.getLive(vehicleId: 'v1', shared: true);
      final b = service.getLive(vehicleId: 'v1', shared: true);
      await Future<void>.delayed(Duration.zero);
      expect(client.requests, hasLength(1));
      client.gates.single.complete(true);
      expect((await a)['status'], (await b)['status']);
    });

    test(
      'a pre-command read in flight is never reused after forgetLive',
      () async {
        final client = _GatedClient();
        final service = ServerSmartChargerService(
          client: client,
          auth: _Auth(),
        );
        final stale = service.getLive(vehicleId: 'v1', shared: true);
        await Future<void>.delayed(Duration.zero);
        ServerSmartChargerService.forgetLive(); // a command was sent
        final fresh = service.getLive(vehicleId: 'v1', shared: true);
        await Future<void>.delayed(Duration.zero);
        expect(client.requests, hasLength(2));
        client.gates[0].complete(true); // old relay ON answer arrives late
        client.gates[1].complete(false); // post-command relay OFF
        await stale;
        expect(((await fresh)['status'] as Map)['relay'], isFalse);
        // The late pre-command answer was not cached for later display polls.
        final again = await service.getLive(vehicleId: 'v1', shared: true);
        expect((again['status'] as Map)['relay'], isFalse);
        expect(client.requests, hasLength(2));
      },
    );

    test('server mode never posts app telemetry', () async {
      final client = _GatedClient();
      final repository = ServerSmartChargerRepository(
        ServerSmartChargerService(client: client, auth: _Auth()),
      );
      expect(repository.telemetryOwner, SmartChargeTelemetryOwner.server);
      final now = DateTime.utc(2026, 10, 14);
      final session = SmartChargingSession(
        sessionId: 's-122',
        vehicleId: 'v1',
        state: ChargingSessionState.active,
        strategy: ChargingStrategy.manualTimed,
        startSoc: 40,
        targetSoc: 80,
        predictedMinutes: 2,
        predictionSource: 'manual',
        estimatedCapacityWh: 2000,
        createdAt: now,
        updatedAt: now,
        aiStopAt: now.add(const Duration(minutes: 2)),
        hardDeadlineAt: now.add(const Duration(minutes: 2)),
        effectiveStopAt: now.add(const Duration(minutes: 2)),
        absoluteSafetyStopAt: now.add(const Duration(minutes: 2)),
        shadowMode: false,
        version: 1,
      );
      await repository.recordStatusSample(session, _status());
      expect(client.requests, isEmpty);
    });
  });

  test('one controller per vehicle whatever the battery reading', () {
    const a = SmartChargingControllerArgs(vehicleId: 'v1', currentSoc: 40);
    const b = SmartChargingControllerArgs(vehicleId: 'v1', currentSoc: 41);
    const c = SmartChargingControllerArgs(vehicleId: 'v2', currentSoc: 40);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == c, isFalse);
  });

  test('verified OFF clears power and timer at once', () {
    final off = _status().withVerifiedRelay(false);
    expect(off.relay, isFalse);
    expect(off.powerW, 0);
    expect(off.currentA, 0);
    expect(off.timerRemaining, Duration.zero);
    final on = _status(
      relay: false,
    ).withVerifiedRelay(true, timerRemaining: const Duration(minutes: 2));
    expect(on.relay, isTrue);
    expect(on.timerRemaining, const Duration(minutes: 2));
  });
}
