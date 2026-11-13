import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/battery_monitor/battery_health_screen.dart';
import 'package:vinfast_battery/features/battery_monitor/widgets/health_trend_chart.dart';

void main() {
  test('one odd charge does not move the trend line', () {
    // The owner's chart: steady near 99, one reading at 85, the latest at 89.
    final values = <double>[99, 98, 100, 99, 100, 85, 100, 98, 100, 89];
    final trend = HealthTrendChart.runningMedian(values);
    expect(trend, hasLength(values.length));
    expect(trend[5], greaterThanOrEqualTo(98));
    expect(trend.last, greaterThanOrEqualTo(98));
    expect(trend.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(98));
  });

  test('a real decline shows in the trend', () {
    final values = <double>[for (var i = 0; i < 12; i++) 100 - i * 1.5];
    final trend = HealthTrendChart.runningMedian(values);
    expect(trend.first - trend.last, greaterThan(12));
  });

  test('health reads the spread and the baseline; old servers still parse', () {
    final health = BatteryHealth.fromMap({
      'nominalCapacityWh': 2400,
      'estimate': {'sohPct': 99.1, 'capacityWh': 2379, 'samples': 10},
      'spread': {'perChargePct': 3.1, 'uncertaintyPct': 1.2},
      'baseline': {
        'changePct': -4.2,
        'charges': 31,
        'since': '2026-03-01T03:00:00Z',
      },
    });
    expect(health.uncertaintyPct, 1.2);
    expect(health.baseline!.charges, 31);
    final old = BatteryHealth.fromMap({'nominalCapacityWh': 2400});
    expect(old.uncertaintyPct, isNull);
    expect(old.baseline, isNull);
  });

  test('the change over time is worded by what the data can support', () {
    const drop = HealthBaseline(changePct: -4.2, charges: 31);
    expect(drop.sentence(1.2), contains('Giảm khoảng 4.2%'));
    // Inside twice the uncertainty: no clear change.
    expect(drop.sentence(3), contains('Chưa thấy thay đổi rõ'));
    const flat = HealthBaseline(changePct: -0.8, charges: 14);
    expect(flat.sentence(0.3), contains('Chưa thấy thay đổi rõ'));
    const rise = HealthBaseline(changePct: 5, charges: 20);
    expect(rise.sentence(1), contains('sai số đo'));
  });
}
