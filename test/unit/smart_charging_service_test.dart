import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/charge_log_model.dart';
import 'package:vinfast_battery/data/services/smart_charging_service.dart';

/// ========================================================================
/// Unit Tests: SmartChargingService — ETA sạc bucketed curve
/// ========================================================================

/// Helper: tạo ChargeLogModel nhanh cho test
ChargeLogModel _makeLog({
  required int startPercent,
  required int endPercent,
  required int durationMinutes,
}) {
  final now = DateTime(2026, 4, 1, 10, 0);
  return ChargeLogModel(
    vehicleId: 'test_v',
    startTime: now,
    endTime: now.add(Duration(minutes: durationMinutes)),
    startBatteryPercent: startPercent,
    endBatteryPercent: endPercent,
    odoAtCharge: 5000,
  );
}

void main() {
  group('estimateChargeMinutes', () {
    test('fromPercent == toPercent → 0', () {
      final result = SmartChargingService.estimateChargeMinutes(
        fromPercent: 50,
        toPercent: 50,
        chargeLogs: [],
      );
      expect(result, 0);
    });

    test('fromPercent > toPercent → 0', () {
      final result = SmartChargingService.estimateChargeMinutes(
        fromPercent: 80,
        toPercent: 50,
        chargeLogs: [],
      );
      expect(result, 0);
    });

    test('no logs → fallback linear with default rate', () {
      final result = SmartChargingService.estimateChargeMinutes(
        fromPercent: 20,
        toPercent: 80,
        chargeLogs: [],
        fallbackRatePerMin: 0.5,
      );
      // 60% / 0.5 = 120 minutes
      expect(result, closeTo(120.0, 0.1));
    });

    test('1 log → fallback linear using that log rate', () {
      final log = _makeLog(startPercent: 20, endPercent: 80, durationMinutes: 150);
      // rate = 60% / 150min = 0.4%/min
      // 40% / 0.4 = 100 min
      final result = SmartChargingService.estimateChargeMinutes(
        fromPercent: 40,
        toPercent: 80,
        chargeLogs: [log],
      );
      expect(result, closeTo(100.0, 0.1));
    });

    test('2 logs → still fallback linear (< 3)', () {
      final logs = [
        _makeLog(startPercent: 20, endPercent: 80, durationMinutes: 150),
        _makeLog(startPercent: 30, endPercent: 90, durationMinutes: 120),
      ];
      // rates: 0.4, 0.5 → avg 0.45
      // 50% / 0.45 = ~111.1
      final result = SmartChargingService.estimateChargeMinutes(
        fromPercent: 30,
        toPercent: 80,
        chargeLogs: logs,
      );
      expect(result, closeTo(111.1, 1.0));
    });

    test('3+ logs → bucketed curve', () {
      final logs = [
        _makeLog(startPercent: 10, endPercent: 50, durationMinutes: 100),
        _makeLog(startPercent: 20, endPercent: 60, durationMinutes: 80),
        _makeLog(startPercent: 50, endPercent: 90, durationMinutes: 200),
      ];
      final result = SmartChargingService.estimateChargeMinutes(
        fromPercent: 20,
        toPercent: 80,
        chargeLogs: logs,
      );
      expect(result, isNotNull);
      expect(result!, greaterThan(0));
    });

    test('3+ logs — sạc ngắn (target gần) → thời gian nhỏ', () {
      final logs = [
        _makeLog(startPercent: 10, endPercent: 50, durationMinutes: 100),
        _makeLog(startPercent: 20, endPercent: 60, durationMinutes: 80),
        _makeLog(startPercent: 50, endPercent: 90, durationMinutes: 200),
      ];
      final shortResult = SmartChargingService.estimateChargeMinutes(
        fromPercent: 75,
        toPercent: 80,
        chargeLogs: logs,
      );
      final longResult = SmartChargingService.estimateChargeMinutes(
        fromPercent: 20,
        toPercent: 80,
        chargeLogs: logs,
      );
      expect(shortResult, isNotNull);
      expect(longResult, isNotNull);
      expect(shortResult!, lessThan(longResult!));
    });

    test('logs with zero duration are skipped in bucket building', () {
      final logs = [
        _makeLog(startPercent: 20, endPercent: 80, durationMinutes: 0), // zero
        _makeLog(startPercent: 10, endPercent: 50, durationMinutes: 100),
        _makeLog(startPercent: 20, endPercent: 60, durationMinutes: 80),
        _makeLog(startPercent: 50, endPercent: 90, durationMinutes: 200),
      ];
      // Should not crash, zero-duration log should be ignored
      final result = SmartChargingService.estimateChargeMinutes(
        fromPercent: 20,
        toPercent: 80,
        chargeLogs: logs,
      );
      expect(result, isNotNull);
      expect(result!, greaterThan(0));
    });

    test('full range 0→100', () {
      final logs = [
        _makeLog(startPercent: 0, endPercent: 50, durationMinutes: 125),
        _makeLog(startPercent: 50, endPercent: 100, durationMinutes: 250),
        _makeLog(startPercent: 0, endPercent: 100, durationMinutes: 380),
      ];
      final result = SmartChargingService.estimateChargeMinutes(
        fromPercent: 0,
        toPercent: 100,
        chargeLogs: logs,
      );
      expect(result, isNotNull);
      expect(result!, greaterThan(0));
    });
  });

  group('estimateCompleteAt', () {
    test('returns null when fromPercent >= toPercent', () {
      final result = SmartChargingService.estimateCompleteAt(
        currentPercent: 80,
        targetPercent: 80,
        chargeLogs: [],
      );
      expect(result, isNull);
    });

    test('returns DateTime in the future', () {
      final log = _makeLog(startPercent: 20, endPercent: 80, durationMinutes: 150);
      final result = SmartChargingService.estimateCompleteAt(
        currentPercent: 50,
        targetPercent: 80,
        chargeLogs: [log],
      );
      expect(result, isNotNull);
      expect(result!.isAfter(DateTime.now()), isTrue);
    });
  });

  group('Edge cases', () {
    test('custom fallbackRatePerMin is respected', () {
      // With rate 1.0 %/min: 50% / 1.0 = 50 min
      final result = SmartChargingService.estimateChargeMinutes(
        fromPercent: 30,
        toPercent: 80,
        chargeLogs: [],
        fallbackRatePerMin: 1.0,
      );
      expect(result, closeTo(50.0, 0.1));
    });

    test('very slow charge rate → large ETA', () {
      final log = _makeLog(startPercent: 40, endPercent: 42, durationMinutes: 60);
      // rate = 2% / 60min = 0.033%/min
      // 50% / 0.033 = ~1500 min
      final result = SmartChargingService.estimateChargeMinutes(
        fromPercent: 30,
        toPercent: 80,
        chargeLogs: [log],
      );
      expect(result, isNotNull);
      expect(result!, greaterThan(1000));
    });
  });
}
