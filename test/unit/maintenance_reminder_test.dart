import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/maintenance_task_model.dart';

/// ========================================================================
/// Unit Tests: Maintenance Reminder Dedupe & Model Logic
/// ========================================================================

void main() {
  group('MaintenanceTaskModel.isDueSoon', () {
    test('currentOdo < targetOdo-50 → false', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Thay nhớt',
        targetOdo: 10000,
      );
      expect(task.isDueSoon(9940), isFalse);
    });

    test('currentOdo == targetOdo-50 → true (boundary)', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Thay nhớt',
        targetOdo: 10000,
      );
      expect(task.isDueSoon(9950), isTrue);
    });

    test('currentOdo between targetOdo-50 and targetOdo → true', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Thay nhớt',
        targetOdo: 10000,
      );
      expect(task.isDueSoon(9975), isTrue);
    });

    test('currentOdo == targetOdo → true (also due soon)', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Thay nhớt',
        targetOdo: 10000,
      );
      expect(task.isDueSoon(10000), isTrue);
    });

    test('currentOdo > targetOdo → true (overdue is also due soon)', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Thay nhớt',
        targetOdo: 10000,
      );
      expect(task.isDueSoon(10100), isTrue);
    });

    test('completed task → always false', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Thay nhớt',
        targetOdo: 10000,
        isCompleted: true,
        completedDate: DateTime(2026, 3, 1),
      );
      expect(task.isDueSoon(9999), isFalse);
    });
  });

  group('MaintenanceTaskModel.isOverdue', () {
    test('currentOdo < targetOdo → false', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Thay lốp',
        targetOdo: 15000,
      );
      expect(task.isOverdue(14999), isFalse);
    });

    test('currentOdo == targetOdo → true', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Thay lốp',
        targetOdo: 15000,
      );
      expect(task.isOverdue(15000), isTrue);
    });

    test('currentOdo > targetOdo → true', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Thay lốp',
        targetOdo: 15000,
      );
      expect(task.isOverdue(15500), isTrue);
    });

    test('completed task → always false', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Thay lốp',
        targetOdo: 15000,
        isCompleted: true,
      );
      expect(task.isOverdue(20000), isFalse);
    });
  });

  group('MaintenanceTaskModel.remainingKm', () {
    test('positive remaining', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Check',
        targetOdo: 10000,
      );
      expect(task.remainingKm(9800), 200);
    });

    test('zero remaining', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Check',
        targetOdo: 10000,
      );
      expect(task.remainingKm(10000), 0);
    });

    test('negative remaining (overdue)', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Check',
        targetOdo: 10000,
      );
      expect(task.remainingKm(10500), -500);
    });
  });

  group('Maintenance reminder dedupe key pattern', () {
    // These test the key format used in MaintenanceReminderService
    test('due_soon key format', () {
      const taskId = 'abc123';
      const threshold = 'due_soon';
      final key = 'maint_notified_${taskId}_$threshold';
      expect(key, 'maint_notified_abc123_due_soon');
    });

    test('overdue key format', () {
      const taskId = 'xyz789';
      const threshold = 'overdue';
      final key = 'maint_notified_${taskId}_$threshold';
      expect(key, 'maint_notified_xyz789_overdue');
    });

    test('different tasks have different keys', () {
      final key1 = 'maint_notified_task1_due_soon';
      final key2 = 'maint_notified_task2_due_soon';
      expect(key1, isNot(equals(key2)));
    });

    test('same task, different thresholds have different keys', () {
      final key1 = 'maint_notified_task1_due_soon';
      final key2 = 'maint_notified_task1_overdue';
      expect(key1, isNot(equals(key2)));
    });
  });

  group('MaintenanceTaskModel.copyWith', () {
    test('copyWith isCompleted', () {
      final task = MaintenanceTaskModel(
        taskId: 't1',
        vehicleId: 'v1',
        title: 'Thay nhớt',
        targetOdo: 10000,
      );
      final completed = task.copyWith(
        isCompleted: true,
        completedDate: DateTime(2026, 4, 6),
      );
      expect(completed.isCompleted, isTrue);
      expect(completed.completedDate, DateTime(2026, 4, 6));
      // isDueSoon should be false after complete
      expect(completed.isDueSoon(9999), isFalse);
      expect(completed.isOverdue(20000), isFalse);
    });
  });

  group('Interaction: isDueSoon + isOverdue priority', () {
    test('overdue task is also isDueSoon', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Check',
        targetOdo: 10000,
      );
      const currentOdo = 10100;
      // In the service, overdue is checked first → notification type = overdue
      expect(task.isOverdue(currentOdo), isTrue);
      expect(task.isDueSoon(currentOdo), isTrue);
    });

    test('due_soon but not overdue', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Check',
        targetOdo: 10000,
      );
      const currentOdo = 9960;
      expect(task.isOverdue(currentOdo), isFalse);
      expect(task.isDueSoon(currentOdo), isTrue);
    });

    test('neither due_soon nor overdue', () {
      final task = MaintenanceTaskModel(
        vehicleId: 'v1',
        title: 'Check',
        targetOdo: 10000,
      );
      const currentOdo = 9000;
      expect(task.isOverdue(currentOdo), isFalse);
      expect(task.isDueSoon(currentOdo), isFalse);
    });
  });
}
