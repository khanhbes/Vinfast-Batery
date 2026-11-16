import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/dashboard_layout_parser.dart';
import 'package:vinfast_battery/data/services/dashboard_templates.dart';

/// QA 160: with 2.1.6 the owner's scans read the % better and no longer
/// found the ODO or the temperature. The QA 159 lost-digit mark now drops
/// only the %; the ODO and the temperature keep their own guards.
void main() {
  const window = Rect.fromLTWH(0, 0, 1420, 1000);
  const lost = DashboardLayoutParser.lostGlyph;
  const unread = DashboardLayoutParser.unreadGlyph;

  List<OcrToken> cluster({
    String socText = '37',
    String? leftOfSoc,
    String? leftOfOdo,
    String? leftOfTemp,
  }) => [
    OcrToken(socText, const Rect.fromLTWH(330, 270, 110, 90)),
    if (leftOfSoc != null)
      OcrToken(leftOfSoc, const Rect.fromLTWH(270, 270, 54, 90)),
    const OcrToken('5494', Rect.fromLTWH(300, 610, 260, 90)),
    if (leftOfOdo != null)
      OcrToken(leftOfOdo, const Rect.fromLTWH(237, 610, 54, 90)),
    const OcrToken('22', Rect.fromLTWH(600, 770, 100, 80)),
    if (leftOfTemp != null)
      OcrToken(leftOfTemp, const Rect.fromLTWH(544, 770, 48, 80)),
  ];

  DashboardLayoutReading read(List<OcrToken> tokens) =>
      DashboardLayoutParser.parseTemplate(
        tokens,
        template: DashboardTemplate.feliz2025,
        window: window,
        lastOdoKm: 5480,
      );

  test('the clean cluster reads all three', () {
    final r = read(cluster());
    expect([r.soc, r.odoKm, r.tempC], [37, 5494, 22]);
  });

  test('a lost-digit mark drops the % only', () {
    final r = read(cluster(socText: '7', leftOfSoc: lost));
    expect(r.soc, isNull);
    expect([r.odoKm, r.tempC], [5494, 22]);
  });

  test('a lost-digit mark beside the ODO or the temperature drops neither', () {
    final r = read(cluster(leftOfOdo: lost, leftOfTemp: lost));
    expect([r.soc, r.odoKm, r.tempC], [37, 5494, 22]);
  });

  test('an unread digit still drops the number next to it (QA 156)', () {
    final r = read(cluster(leftOfOdo: unread));
    expect(r.odoKm, isNull);
    expect(r.soc, 37);
  });

  test('the window fit ignores both marks', () {
    final tokens = cluster(leftOfOdo: lost, leftOfTemp: unread);
    final fit = DashboardLayoutParser.fitWindowScored(
      [tokens],
      template: DashboardTemplate.feliz2025,
      window: window,
    );
    expect(
      fit.window,
      DashboardLayoutParser.fitWindow(
        [tokens],
        template: DashboardTemplate.feliz2025,
        window: window,
      ),
    );
    expect(fit.score, greaterThan(2));
  });
}
