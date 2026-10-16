import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';

void main() {
  SmartChargerStatus status({Duration? timer, DateTime? readAt}) =>
      SmartChargerStatus(
        online: true,
        relay: true,
        powerW: 400,
        voltageV: 230,
        currentA: 1.7,
        frequencyHz: 50,
        temperatureC: 30,
        energyWh: 10,
        timerRemaining: timer,
        readAt: readAt,
      );

  test('hardware timer counts down from the read time (Task 125)', () {
    final readAt = DateTime(2030, 1, 1, 10);
    final value = status(timer: const Duration(minutes: 2), readAt: readAt);
    expect(value.timerRemainingAt(readAt), const Duration(minutes: 2));
    expect(
      value.timerRemainingAt(readAt.add(const Duration(seconds: 45))),
      const Duration(seconds: 75),
    );
    expect(
      value.timerRemainingAt(readAt.add(const Duration(minutes: 5))),
      Duration.zero,
    );
    expect(status().timerRemainingAt(readAt), isNull);
  });

  test('read time survives the cached JSON round trip', () {
    final readAt = DateTime.utc(2030, 1, 1, 3);
    final restored = SmartChargerStatus.fromJson(
      status(timer: const Duration(seconds: 90), readAt: readAt).toJson(),
    );
    expect(restored.readAt!.toUtc(), readAt);
    expect(
      restored.timerRemainingAt(readAt.add(const Duration(seconds: 30))),
      const Duration(seconds: 60),
    );
  });

  test('a verified command restarts the countdown from now', () {
    final old = status(
      timer: const Duration(seconds: 5),
      readAt: DateTime(2000),
    );
    final presented = old.withVerifiedRelay(
      true,
      timerRemaining: const Duration(minutes: 1),
    );
    final left = presented.timerRemainingAt(DateTime.now())!;
    expect(left.inSeconds, inInclusiveRange(58, 60));
  });
}
