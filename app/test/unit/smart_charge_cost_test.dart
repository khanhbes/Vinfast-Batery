import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charge_cost.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';

void main() {
  group('SmartChargeCostSnapshot', () {
    test('keeps cost unavailable when no tariff is configured', () {
      final snapshot = SmartChargeCostSnapshot.calculate(
        gridEnergyWh: 1800,
        terminal: false,
      );

      expect(snapshot.gridEnergyWh, 1800);
      expect(snapshot.costVnd, isNull);
      expect(snapshot.quality, SmartChargeCostQuality.unavailable);
    });

    test('calculates provisional and final cost from measured energy', () {
      final active = SmartChargeCostSnapshot.calculate(
        gridEnergyWh: 1800,
        tariffVndPerKwh: 3000,
        terminal: false,
      );
      final terminal = SmartChargeCostSnapshot.calculate(
        gridEnergyWh: 1800,
        tariffVndPerKwh: 3000,
        terminal: true,
      );

      expect(active.costVnd, closeTo(5400, 0.001));
      expect(active.quality, SmartChargeCostQuality.provisional);
      expect(terminal.quality, SmartChargeCostQuality.finalValue);
    });
  });

  test('monthly summary excludes active sessions from terminal totals', () {
    final start = DateTime(2026, 8, 29, 16, 11);
    final completed = _session(
      id: 'completed',
      state: ChargingSessionState.completed,
      strategy: ChargingStrategy.aiTarget,
      start: start,
      duration: const Duration(hours: 4),
      energyWh: 2400,
      costVnd: 7200,
    );
    final active = _session(
      id: 'active',
      state: ChargingSessionState.active,
      strategy: ChargingStrategy.manualTimed,
      start: start,
      duration: const Duration(hours: 2),
      energyWh: 1000,
      costVnd: 3000,
    );

    final summary = SmartChargeHistorySummary.calculate(
      [completed, active],
      from: DateTime(2026, 8),
      to: DateTime(2026, 9),
    );

    expect(summary.completedSessions, 1);
    expect(summary.totalGridEnergyWh, 2400);
    expect(summary.totalCostVnd, 7200);
  });
}

SmartChargingSession _session({
  required String id,
  required ChargingSessionState state,
  required ChargingStrategy strategy,
  required DateTime start,
  required Duration duration,
  required double energyWh,
  required double costVnd,
}) {
  final stop = start.add(duration);
  return SmartChargingSession(
    sessionId: id,
    vehicleId: 'vehicle-1',
    deviceId: 'shelly-1',
    state: state,
    strategy: strategy,
    startSoc: 30,
    targetSoc: 80,
    predictedMinutes: duration.inMinutes,
    predictionSource: 'test',
    createdAt: start,
    updatedAt: state.isTerminal ? stop : start,
    startedAt: start,
    stoppedAt: state.isTerminal ? stop : null,
    aiStopAt: stop,
    hardDeadlineAt: stop,
    effectiveStopAt: stop,
    absoluteSafetyStopAt: stop,
    shadowMode: false,
    version: 1,
    energyUsedWh: energyWh,
    estimatedCostVnd: costVnd,
    costQuality: state.isTerminal
        ? SmartChargeCostQuality.finalValue.wireValue
        : SmartChargeCostQuality.provisional.wireValue,
  );
}
