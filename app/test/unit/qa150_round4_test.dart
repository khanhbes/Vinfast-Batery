import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/maintenance_reminder_service.dart';
import 'package:vinfast_battery/features/settings/profile_screen.dart';

/// QA 150, round 4: maintenance reminders as one line, birth date in Hồ sơ.
void main() {
  group('MaintenanceReminderSummary', () {
    test('nothing new, nothing said', () {
      expect(
        MaintenanceReminderSummary.of(titles: const [], overdue: true),
        isNull,
      );
    });

    test('one overdue task is named with how far past it is', () {
      final s = MaintenanceReminderSummary.of(
        titles: const ['Kiểm tra phanh'],
        overdue: true,
        remainingKm: -320,
      )!;
      expect(s.title, 'Bảo dưỡng đã quá hạn');
      expect(s.body, 'Kiểm tra phanh (quá 320 km).');
    });

    test('one task due soon says what is left', () {
      final s = MaintenanceReminderSummary.of(
        titles: const ['Thay dầu phanh'],
        overdue: false,
        remainingKm: 150,
      )!;
      expect(s.title, 'Bảo dưỡng sắp đến hạn');
      expect(s.body, 'Thay dầu phanh (còn 150 km).');
    });

    test('many tasks become one line, not one notification each', () {
      final s = MaintenanceReminderSummary.of(
        titles: [for (var i = 1; i <= 19; i++) 'Mốc $i'],
        overdue: true,
      )!;
      expect(s.title, '19 mốc bảo dưỡng đã quá hạn');
      expect(s.body, 'Mốc 1, Mốc 2 và 17 mốc khác.');
    });

    test('two tasks are both named', () {
      final s = MaintenanceReminderSummary.of(
        titles: const ['Lốp', 'Phanh'],
        overdue: false,
      )!;
      expect(s.body, 'Lốp, Phanh.');
    });
  });

  group('birthDateText', () {
    test('ISO dates are shown day first', () {
      expect(birthDateText('2000-12-31'), '31/12/2000');
    });
    test('day-first dates stay as stored', () {
      expect(birthDateText('05/09/1998'), '05/09/1998');
    });
    test('nothing stored shows nothing', () {
      expect(birthDateText(null), '');
      expect(birthDateText(42), '');
    });
  });
}
