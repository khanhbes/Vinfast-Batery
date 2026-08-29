import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charge_history.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/services/smart_charger_service.dart';

void main() {
  group('Smart Charge energy summary', () {
    test('separates grid energy, stored energy, end SOC and remaining Wh', () {
      final value = SmartChargeEnergySummary.calculate(
        session: _session(energyUsedWh: 1000),
        points: const [],
      );

      expect(value.gridEnergyWh, 1000);
      expect(value.estimatedStoredWh, 900);
      expect(value.estimatedEndSoc, closeTo(50, 0.001));
      expect(value.estimatedRemainingWh, closeTo(1500, 0.001));
      expect(value.estimatedUsableCapacityWh, isNull);
    });

    test('counter reset sums only positive deltas and marks data partial', () {
      final start = DateTime.utc(2026, 8, 29);
      final value = SmartChargeEnergySummary.calculate(
        session: _session(energyUsedWh: 0),
        points: [
          _point(start, 100),
          _point(start.add(const Duration(seconds: 30)), 150),
          _point(start.add(const Duration(seconds: 60)), 10),
          _point(start.add(const Duration(seconds: 90)), 35),
        ],
      );

      expect(value.gridEnergyWh, 75);
      expect(value.energyQuality, 'partial');
    });

    test('publishes usable capacity only with independent qualified SOC', () {
      final start = DateTime.utc(2026, 8, 29);
      final points = List.generate(
        40,
        (index) => _point(
          start.add(Duration(seconds: index * 30)),
          index * (1000 / 39),
        ),
      );
      final value = SmartChargeEnergySummary.calculate(
        session: _session(energyUsedWh: 1000),
        points: points,
        confirmedEndSoc: 50,
      );

      expect(value.coverageRatio, 1);
      expect(value.estimatedUsableCapacityWh, closeTo(3000, 0.001));
    });
  });

  test('absolute Smart Charge limit is ten hours', () {
    expect(SmartChargerService.maxSessionDuration, const Duration(hours: 10));
  });
}

SmartChargingSession _session({required double energyUsedWh}) {
  final start = DateTime.utc(2026, 8, 29);
  return SmartChargingSession(
    sessionId: 'session-1',
    vehicleId: 'vehicle-1',
    state: ChargingSessionState.completed,
    strategy: ChargingStrategy.aiTarget,
    startSoc: 20,
    targetSoc: 80,
    predictedMinutes: 20,
    predictionSource: 'model',
    createdAt: start,
    updatedAt: start.add(const Duration(minutes: 20)),
    startedAt: start,
    stoppedAt: start.add(const Duration(minutes: 20)),
    aiStopAt: start.add(const Duration(minutes: 20)),
    hardDeadlineAt: start.add(const Duration(hours: 10)),
    effectiveStopAt: start.add(const Duration(minutes: 20)),
    absoluteSafetyStopAt: start.add(const Duration(hours: 10)),
    shadowMode: false,
    version: 1,
    estimatedCapacityWh: 3000,
    energyUsedWh: energyUsedWh,
  );
}

SmartChargeTelemetryPoint _point(DateTime timestamp, double energyWh) =>
    SmartChargeTelemetryPoint(
      timestamp: timestamp,
      elapsedSeconds: timestamp.difference(DateTime.utc(2026, 8, 29)).inSeconds,
      powerAverageW: 500,
      powerMinimumW: 480,
      powerMaximumW: 520,
      voltageV: 230,
      currentA: 2.2,
      temperatureC: 31,
      energyWh: energyWh,
      estimatedSoc: null,
      relay: true,
      timerRemainingSeconds: 600,
      transport: 'cloud',
    );
