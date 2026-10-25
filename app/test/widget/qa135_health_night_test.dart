import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/pinova_api.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/widgets/charge_confirm_control.dart';
import 'package:vinfast_battery/features/battery_monitor/battery_health_screen.dart';
import 'package:vinfast_battery/features/smart_charging/night_charging_screen.dart';

/// QA 135: % pin chai (Pro) and sạc đêm an toàn (Ultra) at 320 dp ×1/×2.
Future<void> _pump(
  WidgetTester tester,
  Widget home,
  double scale,
  List<Override> overrides, {
  double height = 2200,
}) async {
  await tester.binding.setSurfaceSize(Size(320, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: LuxeTheme.data(),
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: page!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1500));
}

final _health = BatteryHealth.fromMap({
  'nominalCapacityWh': 2340,
  'estimate': {
    'sohPct': 90.0,
    'capacityWh': 2106,
    'samples': 4,
    'confidence': 'medium',
  },
  'test': null,
  'trend': [
    {'at': '2026-10-10T10:00:00Z', 'sohPct': 100.0},
    {'at': '2026-10-12T10:00:00Z', 'sohPct': 90.0},
    {'at': '2026-10-14T10:00:00Z', 'sohPct': 90.0},
  ],
  'testMaxStartPct': 30,
});

class _FakeNight extends NightChargingApi {
  _FakeNight() : super(api: PinovaApi());
  NightPlan? plan;
  final armed = <Map<String, Object>>[];

  @override
  Future<NightPlan?> get(String vehicleId) async => plan;

  @override
  Future<NightPlan?> arm(
    String vehicleId, {
    required double currentSoc,
    required int targetSoc,
    required TimeOfDay wake,
  }) async {
    armed.add({'current': currentSoc, 'target': targetSoc, 'wake': wake});
    return plan = NightPlan.fromMap({
      'state': 'armed',
      'targetSoc': targetSoc,
      'wakeAt': '06:30',
      'startAt': '2026-10-25T20:10:00Z',
      'finishBy': '2026-10-25T23:10:00Z',
    });
  }

  @override
  Future<NightPlan?> cancel(String vehicleId) async =>
      plan = NightPlan.fromMap({
        'state': 'cancelled',
        'targetSoc': 85,
        'wakeAt': '06:30',
      });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('health parses the estimate, test and trend', () {
    expect(_health.estimate!.sohPct, 90);
    expect(_health.estimate!.confidenceLabel, 'Tin cậy vừa');
    expect(_health.trend, hasLength(3));
    expect(_health.test, isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('battery health fits 320 dp at ×$scale', (tester) async {
      await _pump(
        tester,
        const BatteryHealthScreen(vehicleId: 'v1'),
        scale,
        [batteryHealthProvider('v1').overrideWith((ref) async => _health)],
        height: scale == 1 ? 2200 : 4400,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('health-soh')), findsOneWidget);
      expect(find.text('90%'), findsWidgets);
      expect(find.textContaining('Đã chai khoảng 10%'), findsOneWidget);
      expect(find.textContaining('Đi xe đến khi pin còn ≤ 30%'), findsOneWidget);
    });
  }

  testWidgets('no confirmed charge asks for data instead of guessing', (
    tester,
  ) async {
    await _pump(tester, const BatteryHealthScreen(vehicleId: 'v1'), 1, [
      batteryHealthProvider('v1').overrideWith(
        (ref) async => BatteryHealth.fromMap({'nominalCapacityWh': 2340}),
      ),
    ]);
    expect(find.byKey(const ValueKey('health-need-data')), findsOneWidget);
    expect(find.byKey(const ValueKey('health-soh')), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('night form fits 320 dp at ×$scale and arms once', (
      tester,
    ) async {
      final api = _FakeNight();
      await _pump(
        tester,
        const NightChargingScreen(vehicleId: 'v1', currentSoc: 40),
        scale,
        [nightChargingApiProvider.overrideWithValue(api)],
        height: scale == 1 ? 2400 : 4800,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('night-safety')), findsOneWidget);
      final control = tester.widget<ChargeConfirmControl>(
        find.byType(ChargeConfirmControl),
      );
      expect(control.label, 'Vuốt để hẹn sạc đêm đến 85%');
      control.onConfirmed();
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.armed.single['target'], 85);
      expect(api.armed.single['current'], 40.0);
      expect(find.byKey(const ValueKey('night-plan-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('night-cancel')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('night-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('night-plan-card')), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });
  }
}
