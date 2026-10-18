import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/dashboard_layout_parser.dart';

/// The owner's VinFast Feliz cluster (photo 18/10/2026, QA 131), measured
/// in image pixels: "68 %", speed "00 KM/H", "ODO" over "48 18" with "KM"
/// below, "ECO", "31°C". Seven-segment digits come back as letters and the
/// ODO gap splits it in two.
List<OcrToken> feliz({
  String soc = '68',
  String percent = '%',
  String speed = '00',
  String odoA = '48',
  String odoB = '18',
  String temp = '31°C',
  bool odoLabel = true,
  bool kmLabel = true,
  bool speedLabel = true,
}) => [
  OcrToken(soc, const Rect.fromLTWH(410, 880, 120, 70)),
  if (percent.isNotEmpty)
    OcrToken(percent, const Rect.fromLTWH(550, 928, 28, 28)),
  OcrToken(speed, const Rect.fromLTWH(645, 935, 250, 175)),
  if (speedLabel) const OcrToken('KM/H', Rect.fromLTWH(925, 980, 60, 20)),
  if (odoLabel) const OcrToken('ODO', Rect.fromLTWH(352, 1128, 62, 22)),
  OcrToken(odoA, const Rect.fromLTWH(443, 1172, 90, 70)),
  OcrToken(odoB, const Rect.fromLTWH(612, 1172, 80, 70)),
  if (kmLabel) const OcrToken('KM', Rect.fromLTWH(640, 1260, 40, 20)),
  const OcrToken('ECO', Rect.fromLTWH(818, 1178, 85, 32)),
  OcrToken(temp, const Rect.fromLTWH(603, 1302, 270, 75)),
];

void main() {
  test('reads the Feliz cluster: 68 % and ODO 4818 (split "48 18")', () {
    final r = DashboardLayoutParser.parse(feliz());
    expect(r.soc, 68);
    expect(r.socConfident, isTrue);
    expect(r.odoKm, 4818);
    expect(r.odoConfident, isTrue);
    expect(r.odoBox, const Rect.fromLTRB(443, 1172, 692, 1242));
  });

  test('seven-segment letters are read as digits', () {
    final r = DashboardLayoutParser.parse(
      feliz(soc: '6B', speed: 'OO', odoA: '4B', odoB: 'IB', temp: '3I°C'),
    );
    expect(r.soc, 68);
    expect(r.odoKm, 4818);
  });

  test('"68%" in one token, ODO label read as 0D0', () {
    final tokens = feliz(soc: '68%', percent: '', odoLabel: false)
      ..add(const OcrToken('0D0', Rect.fromLTWH(352, 1128, 62, 22)));
    final r = DashboardLayoutParser.parse(tokens);
    expect(r.soc, 68);
    expect(r.odoKm, 4818);
    expect(r.odoConfident, isTrue);
  });

  test('speed, temperature and ECO are never taken for % or ODO', () {
    final r = DashboardLayoutParser.parse(
      feliz(percent: '', odoLabel: false, kmLabel: false, speedLabel: false),
    );
    expect(r.soc, isNull, reason: 'no % next to any number');
    expect(r.socCandidates, isNot(contains(31)));
    expect(r.odoCandidates, isNot(contains(31)));
    expect(r.odoCandidates, isNot(contains(0)));
  });

  test('without labels the last ODO anchors the reading', () {
    final r = DashboardLayoutParser.parse(
      feliz(odoLabel: false, kmLabel: false),
      lastOdoKm: 4804,
    );
    expect(r.odoKm, 4818);
    expect(r.odoConfident, isTrue);
  });

  test('an ODO below the last reading is rejected', () {
    final r = DashboardLayoutParser.parse(feliz(), lastOdoKm: 5200);
    expect(r.odoKm, isNull);
  });

  test('an unlabelled 2-digit number is not an ODO', () {
    final r = DashboardLayoutParser.parse([
      const OcrToken('42', Rect.fromLTWH(100, 100, 60, 40)),
    ]);
    expect(r.isEmpty, isTrue);
  });

  group('frames vote', () {
    DashboardLayoutReading frame(int? soc, double? odo) =>
        DashboardLayoutReading(soc: soc, odoKm: odo, odoConfident: odo != null);

    test('locks after three agreeing frames', () {
      final vote = DashboardScanVote()
        ..add(frame(68, 4818))
        ..add(frame(68, 4818));
      expect(vote.anyLocked, isFalse);
      vote.add(frame(68, 4818));
      expect(vote.socLocked, 68);
      expect(vote.odoLocked, 4818);
      expect(vote.bothLocked, isTrue);
    });

    test('a glare misread does not win', () {
      final vote = DashboardScanVote()
        ..add(frame(68, 4818))
        ..add(frame(88, 4318))
        ..add(frame(68, 4818))
        ..add(frame(null, null));
      expect(vote.anyLocked, isFalse);
      vote.add(frame(68, 4818));
      expect(vote.socLocked, 68);
      expect(vote.odoLocked, 4818);
    });

    test('unanchored ODO values do not vote', () {
      final vote = DashboardScanVote();
      for (var i = 0; i < 4; i++) {
        vote.add(const DashboardLayoutReading(soc: 68, odoKm: 18));
      }
      expect(vote.socLocked, 68);
      expect(vote.odoLocked, isNull);
      expect(vote.odoSeen, 18);
    });
  });
}
