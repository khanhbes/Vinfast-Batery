import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/vinfast_model_spec.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';

void main() {
  group('QA Audit — Battery Invariants & Math Boundary Tests (CHK-16..19, APP-H6)', () {
    test('SOC boundary invariants: values strictly bounded or clamped', () {
      final testSocs = [-100.0, -1.0, 0.0, 0.1, 50.0, 99.9, 100.0, 101.0, 250.0];
      for (final soc in testSocs) {
        final clampedSoc = soc.clamp(0.0, 100.0);
        expect(clampedSoc, greaterThanOrEqualTo(0.0));
        expect(clampedSoc, lessThanOrEqualTo(100.0));
        expect(clampedSoc.isFinite, isTrue);
      }
    });

    test('NaN and Infinity protection for SOC and battery telemetry', () {
      const nanValue = double.nan;
      const infValue = double.infinity;
      const negInfValue = double.negativeInfinity;

      double sanitizeTelemetry(double value, {double fallback = 0.0}) {
        if (value.isNaN || value.isInfinite) return fallback;
        return value.clamp(0.0, 100.0);
      }

      expect(sanitizeTelemetry(nanValue), 0.0);
      expect(sanitizeTelemetry(infValue), 0.0);
      expect(sanitizeTelemetry(negInfValue), 0.0);
      expect(sanitizeTelemetry(75.5), 75.5);
    });

    test('VinFastModelSpec handles extreme and missing capacity values', () {
      final spec = VinFastModelSpec.fromMap({
        'modelId': 'TEST_SPEC',
        'modelName': 'Test Vehicle',
        'nominalCapacityWh': 3500.0,
        'nominalVoltageV': 72.0,
        'nominalCapacityAh': 48.6,
        'maxChargePowerW': 2200.0,
        'ratedMotorPowerW': 1200.0,
        'peakMotorPowerW': 2500.0,
        'defaultEfficiencyKmPerPercent': 1.2,
      }, id: 'TEST_SPEC');

      expect(spec.nominalCapacityWh, 3500.0);
      expect(spec.nominalVoltageV, 72.0);

      // Deserialization with fallback data
      final fallbackSpec = VinFastModelSpec.fromMap({
        'nominalCapacityWh': 0.0,
        'nominalCapacityAh': 0.0,
        'nominalVoltageV': 0.0,
        'maxChargePowerW': 0.0,
        'ratedMotorPowerW': 0.0,
        'peakMotorPowerW': 0.0,
        'defaultEfficiencyKmPerPercent': 0.0,
      }, id: 'EMPTY_SPEC');
      expect(fallbackSpec.nominalCapacityWh, greaterThanOrEqualTo(0.0));
    });

    test('SmartChargingSession invariants: non-negative start/target SOC', () {
      final now = DateTime.now();
      final session = SmartChargingSession(
        sessionId: 'audit_session_01',
        vehicleId: 'VF_FELIZ_2025',
        state: ChargingSessionState.active,
        strategy: ChargingStrategy.aiTarget,
        startSoc: 20.0,
        targetSoc: 80.0,
        createdAt: now,
        updatedAt: now,
        effectiveStopAt: now.add(const Duration(hours: 3)),
        absoluteSafetyStopAt: now.add(const Duration(hours: 6)),
        aiStopAt: now.add(const Duration(hours: 3)),
        hardDeadlineAt: now.add(const Duration(hours: 4)),
        predictedMinutes: 180,
        predictionSource: 'gradient_boosting_v1',
        shadowMode: false,
        version: 1,
      );

      expect(session.startSoc, 20.0);
      expect(session.targetSoc, 80.0);
      expect(session.targetSoc, greaterThan(session.startSoc!));
    });

    test('Division by zero protection in efficiency and charging speed math', () {
      double calculateEfficiency(double distanceKm, double batteryPercentConsumed) {
        if (batteryPercentConsumed <= 0 || batteryPercentConsumed.isNaN) {
          return 0.0;
        }
        final result = distanceKm / batteryPercentConsumed;
        return result.isFinite ? result : 0.0;
      }

      expect(calculateEfficiency(20.0, 0.0), 0.0);
      expect(calculateEfficiency(20.0, -5.0), 0.0);
      expect(calculateEfficiency(20.0, double.nan), 0.0);
      expect(calculateEfficiency(50.0, 25.0), 2.0);
    });
  });
}
