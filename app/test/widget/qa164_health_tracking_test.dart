import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/utils/number_text.dart';
import 'package:vinfast_battery/features/battery_monitor/battery_health_screen.dart';

/// QA 164 (owner's choice, 17/11/2026): the main figure of Sức khỏe pin is
/// the battery against the first months the app followed it (the charger
/// efficiency cancels out); the absolute capacity is the second line with
/// the efficiency's doubt in its range; months for the battery's life.
BatteryHealth _health({
  Map<String, Object?>? tracking,
  bool stale = false,
  double soh = 98.8,
}) => BatteryHealth.fromMap({
  'nominalCapacityWh': 2400,
  'estimate': {
    'sohPct': soh,
    'capacityWh': 2400 * soh / 100,
    'samples': 8,
    'confidence': stale ? 'low' : 'high',
    if (stale) 'stale': true,
    if (stale) 'asOf': '2026-10-20T08:00:00Z',
  },
  'spread': {
    'uncertaintyPct': 2.2,
    'lowPct': soh - 2.2,
    'highPct': soh + 2.2,
    'totalPct': 4.0,
  },
  'trend': const [],
  'charges': const [],
  'full': true,
  'tracking': tracking,
});

const _ready = {
  'status': 'ready',
  'relativePct': 99.4,
  'uncertaintyPct': 2.8,
  'since': '2026-09-12T17:00:00Z',
  'until': '2026-10-31T11:00:00Z',
  'monthly': [
    {'month': '2026-09', 'relativePct': 100.2, 'charges': 1},
    {'month': '2026-10', 'relativePct': 99.8, 'charges': 3},
    {'month': '2026-11', 'relativePct': 99.4, 'charges': 4},
  ],
};

Future<void> _pump(
  WidgetTester tester,
  BatteryHealth health,
  double scale,
) async {
  await tester.binding.setSurfaceSize(Size(320, scale == 1 ? 2400 : 4800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        batteryHealthProvider('v1').overrideWith((ref) async => health),
      ],
      child: MaterialApp(
        theme: LuxeTheme.data(),
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: page!,
        ),
        home: const BatteryHealthScreen(vehicleId: 'v1'),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1500));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('HealthVerdict (QA 164)', () {
    test('the main figure is against the start once it is fixed', () {
      final v = HealthVerdict.of(_health(tracking: _ready))!;
      expect(v.relative, isTrue);
      expect(v.pct, 99.4);
      expect(v.unit, 'so với lúc đầu');
      expect(v.label, 'Pin giữ như lúc đầu');
      expect(
        v.detail,
        'Chưa thấy giảm rõ so với lúc bắt đầu theo dõi (9–10/2026).',
      );
      expect(v.short, '±3% · so với 9–10/2026');
      // The absolute range carries the charger efficiency's doubt (±4).
      expect(
        v.capacityText,
        'khoảng ${groupThousands(2280)}–${groupThousands(2470)} Wh / '
        '${groupThousands(2400)} Wh danh định',
      );
    });

    test('a loss beyond the error is said plainly', () {
      final v = HealthVerdict.of(
        _health(tracking: {..._ready, 'relativePct': 91.0}),
      )!;
      expect(v.label, 'Pin giảm nhẹ');
      expect(
        v.detail,
        'Giảm khoảng 9% so với lúc bắt đầu theo dõi (9–10/2026).',
      );
      final more = HealthVerdict.of(
        _health(tracking: {..._ready, 'relativePct': 85.0}),
      )!;
      expect(more.label, 'Pin giảm rõ, nên theo dõi');
    });

    test('service advice still follows the rated capacity', () {
      final v = HealthVerdict.of(
        _health(soh: 68, tracking: {..._ready, 'relativePct': 97.0}),
      )!;
      expect(v.label, 'Pin chai nhiều, nên đưa xe đi kiểm tra');
    });

    test('while the reference is built the rated figure shows, said so', () {
      final v = HealthVerdict.of(
        _health(
          tracking: const {
            'status': 'building',
            'needCharges': 2,
            'needDays': 10,
          },
        ),
      )!;
      expect(v.relative, isFalse);
      expect(v.pct, 98.8);
      expect(v.unit, 'dung lượng hãng');
      expect(
        v.building,
        'Đang lập mốc theo dõi · Cần thêm 2 lần sạc và 10 ngày',
      );
      // The error shown includes the charger efficiency.
      expect(v.basis, 'Dựa trên 8 lần sạc · sai số ±4%');
    });

    test('an older server (no tracking) keeps the QA 162 reading', () {
      final v = HealthVerdict.of(_health())!;
      expect(v.relative, isFalse);
      expect(v.building, isNull);
    });
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('tracking hero and months at 320 dp, text ×$scale', (
      tester,
    ) async {
      await _pump(tester, _health(tracking: _ready), scale);
      expect(find.byKey(const ValueKey('health-soh')), findsOneWidget);
      expect(find.text('99%'), findsOneWidget);
      expect(find.byKey(const ValueKey('health-unit')), findsOneWidget);
      expect(find.byKey(const ValueKey('health-capacity')), findsOneWidget);
      expect(find.byKey(const ValueKey('health-monthly')), findsOneWidget);
      expect(find.text('Theo tháng'.toUpperCase()), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a stale figure says how old it is, text ×$scale', (
      tester,
    ) async {
      await _pump(tester, _health(tracking: _ready, stale: true), scale);
      expect(find.textContaining('đây là số tháng 10/2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('building the reference, text ×$scale', (tester) async {
      await _pump(
        tester,
        _health(tracking: const {'status': 'building', 'needCharges': 2}),
        scale,
      );
      expect(find.byKey(const ValueKey('health-building')), findsOneWidget);
      expect(find.byKey(const ValueKey('health-monthly')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
