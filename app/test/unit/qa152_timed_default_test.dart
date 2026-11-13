import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/widgets/timed_charging_section_v2.dart';

void main() {
  Duration lengthOf(TimeOfDay end, DateTime now) =>
      TimedChargingSectionV2.stopAtFor(end, now).difference(now);

  test('a timed charge is 7 hours at most', () {
    expect(TimedChargingSectionV2.maxLength, const Duration(hours: 7));
  });

  test('the offered end is never past the limit', () {
    // Seen on the owner's phone: 600 minutes remembered, opened at 01:20:30,
    // the end rounded up to 11:25 and the button was refused at once.
    for (final minutes in [5, 120, 415, 420, 600]) {
      for (var second = 0; second < 300; second += 7) {
        final now = DateTime(
          2026,
          11,
          13,
          1,
          20,
        ).add(Duration(seconds: second));
        final end = TimedChargingSectionV2.defaultEnd(minutes, now);
        final length = lengthOf(end, now);
        expect(
          length <= TimedChargingSectionV2.maxLength,
          isTrue,
          reason: '$minutes min at +${second}s gave $length',
        );
        expect(length >= TimedChargingSectionV2.minLength, isTrue);
      }
    }
  });

  test('a short remembered length is kept as it was', () {
    final now = DateTime(2026, 11, 13, 22, 0);
    expect(
      TimedChargingSectionV2.defaultEnd(120, now),
      const TimeOfDay(hour: 0, minute: 0),
    );
  });
}
