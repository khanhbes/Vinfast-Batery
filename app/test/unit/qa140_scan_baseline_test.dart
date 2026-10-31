import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/dashboard_scan_screen.dart';

/// QA 140 (item 8): every scanner reads ODO against the same baseline, the
/// higher of what the caller passed and the vehicle's latest ODO.
void main() {
  test('the higher known ODO is the baseline', () {
    expect(odoBaseline(4800, 4818), 4818); // a trip's start vs. now
    expect(odoBaseline(null, 4818), 4818); // the % sheet passed none
    expect(odoBaseline(4818, null), 4818);
    expect(odoBaseline(0, null), isNull);
    expect(odoBaseline(double.nan, -3), isNull);
  });
}
