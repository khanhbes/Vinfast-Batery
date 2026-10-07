import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/services/local_personal_calibration.dart';

List<CalibrationSample> samples({bool perfect = false}) => List.generate(
  60,
  (i) => CalibrationSample(
    sessionId: 'session-$i',
    recordedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
    baseSeconds: 1200.0 + (i % 10) * 300,
    actualSeconds: (1200.0 + (i % 10) * 300) * (perfect ? 1 : 1.15),
    verified: true,
  ),
);
void main() {
  test('insufficient samples never activate adapter', () {
    expect(
      LocalPersonalCalibration.train(samples().take(30).toList()).promoted,
      false,
    );
  });
  test('future-heldout adapter can improve measured error', () {
    final candidate = LocalPersonalCalibration.train(samples());
    expect(candidate.promoted, true);
    expect(candidate.testCount, 20);
  });
  test('perfect base cannot be degraded or advertised as improvement', () {
    expect(
      LocalPersonalCalibration.train(samples(perfect: true)).promoted,
      false,
    );
  });
  test('duplicate sessions cannot inflate sample eligibility', () {
    final data = samples();
    expect(LocalPersonalCalibration.train([...data, ...data]).promoted, false);
  });
  test('unverified labels never train', () {
    final data = samples()
        .map(
          (s) => CalibrationSample(
            sessionId: s.sessionId,
            recordedAt: s.recordedAt,
            baseSeconds: s.baseSeconds,
            actualSeconds: s.actualSeconds,
            verified: false,
          ),
        )
        .toList();
    expect(LocalPersonalCalibration.train(data).promoted, false);
  });
}
