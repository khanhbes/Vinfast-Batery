import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/notification_service.dart';

void main() {
  test('charge reminder ids are per vehicle and stable (Task 125)', () {
    final feliz = NotificationService.chargeReminderIdFor('VF-FELIZ-001');
    expect(NotificationService.chargeReminderIdFor('VF-FELIZ-001'), feliz);
    expect(NotificationService.chargeReminderIdFor('VF-EVO-002'), isNot(feliz));
    expect(feliz, inInclusiveRange(2100, 2899));
    expect(
      NotificationService.chargeReminderIdFor(null),
      NotificationService.idChargeReminder,
    );
  });
}
