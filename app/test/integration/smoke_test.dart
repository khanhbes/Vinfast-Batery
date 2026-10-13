import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/charge_log_model.dart';
import 'package:vinfast_battery/data/models/maintenance_task_model.dart';

/// ========================================================================
/// Integration Smoke Tests
/// Kiểm tra luồng: charge target → log fields, mốc bảo dưỡng theo ODO
/// (chạy offline, không cần Firebase thật)
/// ========================================================================

/// Helper builders
ChargeLogModel _makeCharge({
  required int start,
  required int end,
  required int minutes,
  int? target,
}) {
  final now = DateTime(2026, 4, 1, 10, 0);
  return ChargeLogModel(
    vehicleId: 'v1',
    startTime: now,
    endTime: now.add(Duration(minutes: minutes)),
    startBatteryPercent: start,
    endBatteryPercent: end,
    odoAtCharge: 5000,
    targetBatteryPercent: target,
    estimatedCompleteAt: target != null
        ? now.add(Duration(minutes: minutes + 10))
        : null,
  );
}

void main() {
  group('Smoke: Charge target 80% → log lưu đúng', () {
    test('charge log with target has targetBatteryPercent', () {
      final log = _makeCharge(start: 30, end: 80, minutes: 125, target: 80);
      expect(log.targetBatteryPercent, 80);
      expect(log.estimatedCompleteAt, isNotNull);
      expect(log.chargeGain, 50);
    });

    test('charge log without target has null target fields', () {
      final log = _makeCharge(start: 30, end: 80, minutes: 125);
      expect(log.targetBatteryPercent, isNull);
      expect(log.estimatedCompleteAt, isNull);
    });

    test('charge toFirestore includes target fields', () {
      final log = _makeCharge(start: 30, end: 80, minutes: 125, target: 90);
      final map = log.toFirestore();
      expect(map['targetBatteryPercent'], 90);
      expect(map['estimatedCompleteAt'], isNotNull);
    });

    test('charge toMap includes target fields', () {
      final log = _makeCharge(start: 30, end: 80, minutes: 125, target: 100);
      final map = log.toMap();
      expect(map['targetBatteryPercent'], 100);
      expect(map['estimatedCompleteAt'], isNotNull);
    });
  });

  group('Smoke: Maintenance integration', () {
    test('overdue task detected at correct ODO', () {
      final task = MaintenanceTaskModel(
        taskId: 'maint_1',
        vehicleId: 'v1',
        title: 'Thay nhớt',
        targetOdo: 10000,
      );

      // Before due
      expect(task.isDueSoon(9000), isFalse);
      expect(task.isOverdue(9000), isFalse);

      // Due soon (within 50km)
      expect(task.isDueSoon(9960), isTrue);
      expect(task.isOverdue(9960), isFalse);

      // Overdue
      expect(task.isDueSoon(10100), isTrue);
      expect(task.isOverdue(10100), isTrue);

      // After completion
      final completed = task.copyWith(isCompleted: true);
      expect(completed.isDueSoon(10100), isFalse);
      expect(completed.isOverdue(10100), isFalse);
    });
  });
}
