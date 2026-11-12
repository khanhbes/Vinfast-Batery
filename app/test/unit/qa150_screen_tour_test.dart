import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/screen_tour.dart';

/// QA 150: an owner signing in again met four screen guides in a row.
void main() {
  final today = DateTime(2026, 11, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ScreenTour.preferences = SharedPreferences.getInstance;
    ScreenTour.currentUid = () => 'u1';
    ScreenTour.now = () => today;
  });

  test('a new account still gets its guides', () async {
    ScreenTour.accountCreatedAt = () =>
        today.subtract(const Duration(hours: 5));
    expect(await ScreenTour.seen(ScreenTour.charge), isFalse);
    await ScreenTour.markSeen(ScreenTour.charge);
    expect(await ScreenTour.seen(ScreenTour.charge), isTrue);
    expect(await ScreenTour.seen(ScreenTour.history), isFalse);
  });

  test('an established account does not, until it asks to see them', () async {
    ScreenTour.accountCreatedAt = () =>
        today.subtract(const Duration(days: 40));
    expect(await ScreenTour.seen(ScreenTour.overviewInstall), isTrue);
    expect(await ScreenTour.seen(ScreenTour.utilities), isTrue);
    await ScreenTour.reset();
    expect(await ScreenTour.seen(ScreenTour.utilities), isFalse);
    await ScreenTour.markSeen(ScreenTour.utilities);
    expect(await ScreenTour.seen(ScreenTour.utilities), isTrue);
  });

  test('an unknown creation date changes nothing', () async {
    ScreenTour.accountCreatedAt = () => null;
    expect(await ScreenTour.seen(ScreenTour.charge), isFalse);
  });
}
