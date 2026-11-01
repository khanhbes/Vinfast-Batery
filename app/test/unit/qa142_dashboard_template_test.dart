import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/dashboard_layout_parser.dart';
import 'package:vinfast_battery/data/services/dashboard_templates.dart';

/// QA 142: the owner lines the Feliz 2025 cluster up with its frame and
/// every number is read from its own zone.
void main() {
  const t = DashboardTemplate.feliz2025;
  // The template's glass inside a 1000 × 704 crop.
  const window = Rect.fromLTWH(0, 0, 1000, 704);

  /// A token centred in [zone] (template fractions), [index] of [count]
  /// side by side.
  OcrToken at(Rect zone, String text, {int index = 0, int count = 1}) {
    final z = Rect.fromLTRB(
      zone.left * window.width,
      zone.top * window.height,
      zone.right * window.width,
      zone.bottom * window.height,
    );
    final w = z.width / count;
    return OcrToken(
      text,
      Rect.fromLTWH(
        z.left + w * index + w * 0.1,
        z.top + z.height * 0.2,
        w * 0.8,
        z.height * 0.6,
      ),
    );
  }

  DashboardLayoutReading read(List<OcrToken> tokens, {double? lastOdoKm}) =>
      DashboardLayoutParser.parseTemplate(
        tokens,
        template: t,
        window: window,
        lastOdoKm: lastOdoKm,
      );

  test(
    'the owner\'s cluster: 68 %, ODO 48 18 → 4818, 31 °C, speed skipped',
    () {
      final r = read([
        at(t.soc, '68'),
        at(t.ignore, '00'),
        at(t.odo, '48', index: 0, count: 2),
        at(t.odo, '18', index: 1, count: 2),
        at(t.temp, '31'),
      ]);
      expect(r.soc, 68);
      expect(r.odoKm, 4818);
      expect(r.tempC, 31);
      expect(r.socConfident && r.odoConfident && r.tempConfident, isTrue);
    },
  );

  test('the full ranges: ODO 0–999 999, battery and temperature 0–100', () {
    final high = read([
      at(t.soc, '100'),
      at(t.odo, '999999'),
      at(t.temp, '100'),
    ]);
    expect([high.soc, high.odoKm, high.tempC], [100, 999999, 100]);
    final low = read([at(t.soc, '0'), at(t.odo, '0'), at(t.temp, '0')]);
    expect([low.soc, low.odoKm, low.tempC], [0, 0, 0]);
  });

  test('out of range or lost digits are not readings', () {
    final r = read([at(t.soc, '168'), at(t.odo, '1234567'), at(t.temp, '120')]);
    expect(r.soc, isNull);
    expect(r.odoKm, isNull);
    expect(r.tempC, isNull);
    // "48" of "4818": a lost digit, never an ODO that went back.
    final lost = read([at(t.odo, '48')], lastOdoKm: 4818);
    expect(lost.odoKm, isNull);
  });

  test('the frame follows the vehicle model', () {
    expect(DashboardTemplate.forModel('VinFast Feliz 2025'), t);
    expect(DashboardTemplate.forModel('feliz-2025 VinFast Feliz'), t);
    expect(DashboardTemplate.forModel('VinFast Feliz S'), isNull);
    expect(DashboardTemplate.forModel('VinFast Feliz 2022'), isNull);
    expect(DashboardTemplate.forModel('VinFast Evo200'), isNull);
    expect(DashboardTemplate.byId('feliz-2025'), t);
  });

  test('the temperature is voted but never holds the scan back', () {
    final vote = DashboardScanVote();
    for (var i = 0; i < 3; i++) {
      vote.add(
        const DashboardLayoutReading(
          soc: 68,
          odoKm: 4818,
          odoConfident: true,
          tempC: 31,
        ),
      );
    }
    expect(vote.bothLocked, isTrue);
    expect(vote.temp, 31);
  });
}
