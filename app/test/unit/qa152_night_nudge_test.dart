import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/smart_charging/night_charging_screen.dart';
import 'package:vinfast_battery/features/smart_charging/night_nudge.dart';

void main() {
  bool offer({
    required DateTime now,
    bool enabled = true,
    bool allowed = true,
    bool linked = true,
    bool hasData = true,
    num soc = 40,
    bool charging = false,
    String? dismissed,
  }) => NightNudge.shouldOffer(
    now: now,
    enabled: enabled,
    allowed: allowed,
    shellyLinked: linked,
    hasBatteryData: hasData,
    soc: soc,
    charging: charging,
    dismissedNight: dismissed,
  );

  final evening = DateTime(2026, 11, 13, 21, 30);

  test('offered in the evening window only', () {
    expect(offer(now: evening), isTrue);
    expect(offer(now: DateTime(2026, 11, 14, 1, 59)), isTrue);
    expect(offer(now: DateTime(2026, 11, 13, 20, 59)), isFalse);
    expect(offer(now: DateTime(2026, 11, 14, 2, 0)), isFalse);
    expect(offer(now: DateTime(2026, 11, 13, 12, 0)), isFalse);
  });

  test('only when a night plan could really be made', () {
    expect(offer(now: evening, allowed: false), isFalse);
    expect(offer(now: evening, linked: false), isFalse);
    expect(offer(now: evening, hasData: false), isFalse);
    expect(offer(now: evening, charging: true), isFalse);
    expect(offer(now: evening, enabled: false), isFalse);
    // 5% under the lowest target (80%) is the most the server takes.
    expect(offer(now: evening, soc: 75), isTrue);
    expect(offer(now: evening, soc: 76), isFalse);
  });

  test('"Để sau" lasts the night, past midnight, not the next evening', () {
    final night = NightNudge.nightOf(evening);
    expect(offer(now: evening, dismissed: night), isFalse);
    expect(
      offer(now: DateTime(2026, 11, 14, 0, 30), dismissed: night),
      isFalse,
    );
    expect(
      offer(now: DateTime(2026, 11, 14, 21, 30), dismissed: night),
      isTrue,
    );
  });

  test('a finished night charge is read with what it reached', () {
    final plan = NightPlan.fromMap({
      'state': 'done',
      'targetSoc': 85,
      'wakeAt': '06:30',
      'result': {'state': 'completed', 'endSoc': 85, 'energyWh': 1210},
    });
    expect(plan!.state, 'done');
    expect(plan.resultSoc, 85);
    expect(plan.armed, isFalse);
    expect(
      NightPlan.fromMap({'state': 'done', 'targetSoc': 85})!.resultSoc,
      isNull,
    );
  });
}
