import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/dashboard_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('guide progress is isolated by authenticated UID', () async {
    final accountA = DashboardPreferencesService();
    await accountA.initializeForUser('uid-a');
    await accountA.seedPendingAutoTour(DashboardPreferencesService.overviewTourId);
    await accountA.markTourCompleted(DashboardPreferencesService.overviewTourId);

    final accountB = DashboardPreferencesService();
    await accountB.initializeForUser('uid-b');

    expect(accountA.isTourCompleted(DashboardPreferencesService.overviewTourId), isTrue);
    expect(accountB.isTourCompleted(DashboardPreferencesService.overviewTourId), isFalse);
    expect(accountB.shouldAutoShow(DashboardPreferencesService.overviewTourId), isFalse);
  });

  test('dismissed first-run tour does not auto-show again', () async {
    final preferences = DashboardPreferencesService();
    await preferences.initializeForUser('uid-a');
    await preferences.seedPendingAutoTour(DashboardPreferencesService.overviewTourId);
    expect(preferences.shouldAutoShow(DashboardPreferencesService.overviewTourId), isTrue);
    await preferences.markTourDismissed(DashboardPreferencesService.overviewTourId);
    expect(preferences.shouldAutoShow(DashboardPreferencesService.overviewTourId), isFalse);
  });
}
