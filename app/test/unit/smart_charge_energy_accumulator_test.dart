import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/services/smart_charge_energy_accumulator.dart';

void main() {
  test('1.6 kWh raises a 22% SOC with a verified capacity', () {
    final session = _session(effectiveCapacityWh: 3500);
    final meter = SmartChargeEnergyAccumulator.ingest(session, 1600);
    final estimate = SmartChargeEnergyAccumulator.estimate(
      session.copyWith(
        energyUsedWh: meter.energyUsedWh,
        lastMeterEnergyWh: meter.lastMeterEnergyWh,
      ),
    );

    expect(meter.energyUsedWh, 1600);
    expect(estimate.soc, closeTo(63.14, .01));
  });

  test('zero baseline, jitter and meter reset preserve positive energy', () {
    var session = _session(baselineEnergyWh: 0, lastMeterEnergyWh: 0);
    for (final meter in [100.0, 96.0, 300.0, 2.0, 52.0]) {
      final update = SmartChargeEnergyAccumulator.ingest(session, meter);
      session = session.copyWith(
        baselineEnergyWh: update.baselineEnergyWh,
        lastMeterEnergyWh: update.lastMeterEnergyWh,
        energyUsedWh: update.energyUsedWh,
        energyQuality: update.energyQuality,
      );
    }
    expect(session.energyUsedWh, 350);
    expect(session.energyQuality, 'meter_reset');
  });

  test('missing capacity never manufactures an SOC estimate', () {
    final estimate = SmartChargeEnergyAccumulator.estimate(
      _session(effectiveCapacityWh: 0).copyWith(energyUsedWh: 1600),
    );
    expect(estimate.available, isFalse);
    expect(estimate.soc, isNull);
  });
}

SmartChargingSession _session({
  double effectiveCapacityWh = 3500,
  double? baselineEnergyWh = 0,
  double? lastMeterEnergyWh = 0,
}) {
  final now = DateTime.utc(2026, 9, 13);
  return SmartChargingSession(
    sessionId: 'test-session',
    vehicleId: 'test-vehicle',
    state: ChargingSessionState.active,
    strategy: ChargingStrategy.aiTarget,
    startSoc: 22,
    targetSoc: 80,
    predictedMinutes: 60,
    predictionSource: 'test',
    estimatedCapacityWh: effectiveCapacityWh,
    effectiveCapacityWh: effectiveCapacityWh,
    createdAt: now,
    updatedAt: now,
    aiStopAt: now.add(const Duration(hours: 1)),
    hardDeadlineAt: now.add(const Duration(hours: 10)),
    effectiveStopAt: now.add(const Duration(hours: 1)),
    absoluteSafetyStopAt: now.add(const Duration(hours: 10)),
    shadowMode: false,
    version: 1,
    baselineEnergyWh: baselineEnergyWh,
    lastMeterEnergyWh: lastMeterEnergyWh,
  );
}
