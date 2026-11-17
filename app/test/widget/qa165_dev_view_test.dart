import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/dev_view.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/features/battery_monitor/battery_health_screen.dart';

/// QA 165 (17/11/2026, owner's choice): "Chế độ develop" behind seven taps
/// on the version and a switch; owners see as little text as possible.
BatteryHealth _health() => BatteryHealth.fromMap({
  'nominalCapacityWh': 2400,
  'estimate': {
    'sohPct': 98.8,
    'capacityWh': 2371,
    'samples': 6,
    'confidence': 'high',
  },
  'spread': {
    'uncertaintyPct': 2.2,
    'lowPct': 96.6,
    'highPct': 101.0,
    'totalPct': 4.0,
  },
  'trend': [
    {'at': '2026-09-12T00:00:00Z', 'sohPct': 98.9},
    {'at': '2026-10-16T00:00:00Z', 'sohPct': 97.8},
    {'at': '2026-11-06T00:00:00Z', 'sohPct': 98.3},
  ],
  'charges': [
    {
      'at': '2026-11-06T00:00:00Z',
      'startPct': 9,
      'endPct': 81,
      'sohPct': 98.3,
      'used': true,
      'trust': 'high',
    },
  ],
  'full': true,
  'tracking': {'status': 'building', 'needCharges': 2, 'needDays': 0},
});

Future<void> _pump(WidgetTester tester, double scale) async {
  await tester.binding.setSurfaceSize(Size(320, scale == 1 ? 2400 : 4800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        batteryHealthProvider('v1').overrideWith((ref) async => _health()),
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DevView.instance.debugSet(unlocked: false, on: false);
  });

  test('seven taps within the window unlock and turn it on', () {
    final view = DevView();
    final t0 = DateTime(2026, 11, 17, 10);
    for (var i = 0; i < 6; i++) {
      expect(
        view.tapVersion(now: t0.add(Duration(milliseconds: 300 * i))),
        6 - i,
      );
    }
    expect(view.tapVersion(now: t0.add(const Duration(milliseconds: 1900))), 0);
    expect(view.unlocked, isTrue);
    expect(view.on, isTrue);
    expect(view.tapVersion(), isNull);
  });

  test('slow taps start the count again', () {
    final view = DevView();
    final t0 = DateTime(2026, 11, 17, 10);
    for (var i = 0; i < 5; i++) {
      view.tapVersion(now: t0.add(Duration(milliseconds: 300 * i)));
    }
    expect(view.tapVersion(now: t0.add(const Duration(seconds: 10))), 6);
    expect(view.unlocked, isFalse);
  });

  test('the switch only works once unlocked, and is remembered', () async {
    final view = DevView();
    await view.setOn(true);
    expect(view.on, isFalse);
    for (var i = 0; i < 7; i++) {
      view.tapVersion();
    }
    await view.setOn(false);
    expect(view.on, isFalse);
    final again = DevView();
    await again.load();
    expect(again.unlocked, isTrue);
    expect(again.on, isFalse);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'battery health for owners: the figure and one line (x$scale)',
      (tester) async {
        await _pump(tester, scale);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('health-soh')), findsOneWidget);
        expect(
          find.text('Cần thêm 2 lần sạc để bắt đầu theo dõi'),
          findsOneWidget,
        );
        // None of the explanations.
        expect(find.byKey(const ValueKey('health-capacity')), findsNothing);
        expect(find.byKey(const ValueKey('health-method')), findsNothing);
        expect(find.byKey(const ValueKey('health-technical')), findsNothing);
        expect(find.byKey(const ValueKey('health-trend-note')), findsNothing);
        expect(find.text('TỪNG LẦN SẠC'), findsNothing);
        // The test is one row that starts it.
        expect(find.text('Làm bài kiểm tra pin'), findsOneWidget);
        expect(find.textContaining('App tính dung lượng'), findsNothing);
      },
    );

    testWidgets('battery health in develop mode adds the detail (x$scale)', (
      tester,
    ) async {
      DevView.instance.debugSet(unlocked: true, on: true);
      addTearDown(() => DevView.instance.debugSet(unlocked: false, on: false));
      await _pump(tester, scale);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('health-technical')), findsOneWidget);
      expect(find.text('CHI TIẾT KỸ THUẬT'), findsOneWidget);
      expect(find.byKey(const ValueKey('health-method')), findsOneWidget);
      expect(find.text('TỪNG LẦN SẠC'), findsOneWidget);
    });
  }
}
