import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/providers/appearance_provider.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/widgets/charge_confirm_control.dart';
import 'package:vinfast_battery/data/models/app_appearance.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/features/ai/widgets/active_charging_card_v2.dart';
import 'package:vinfast_battery/features/ai/widgets/soc_range_input.dart';
import 'package:vinfast_battery/features/home/widgets/dashboard_style_heroes.dart';
import 'package:vinfast_battery/features/settings/appearance_screen.dart';

/// QA 131: appearance choices (Overview, Charge tab, how ON is confirmed),
/// every new layout at 320 dp with text ×1 and ×2.
Future<void> _pump(
  WidgetTester tester,
  Widget child,
  double scale, {
  double height = 1400,
  bool scroll = true,
  List<Override> overrides = const [],
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
        home: scroll
            ? Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: child,
                ),
              )
            : child,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1500));
}

final _feliz = VehicleModel(
  vehicleId: 'v1',
  vehicleName: 'VinFast Feliz',
  currentOdo: 4818,
  currentBattery: 68,
  stateOfHealth: 96,
  batteryCapacityWh: 3500,
  hasBatteryData: true,
  hasOdoData: true,
  hasSohData: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('appearance round-trips and falls back to the defaults', () {
    const a = AppAppearance(
      dashboard: DashboardStyle.lcd,
      charge: ChargeStyle.bar,
      confirm: ChargeConfirmStyle.hold,
    );
    expect(AppAppearance.fromMap(a.toMap()), a);
    expect(
      AppAppearance.fromMap({'dashboardStyle': 'nope'}),
      const AppAppearance(),
    );
    expect(
      ChargeConfirmControl.reword(
        'Vuốt để sạc đến 80%',
        ChargeConfirmStyle.hold,
      ),
      'Giữ để sạc đến 80%',
    );
    expect(
      ChargeConfirmControl.reword('Vuốt để bật sạc', ChargeConfirmStyle.tap),
      'Bật sạc',
    );
  });

  test('the choice is cached per account and survives a restart', () async {
    final store = AppearanceStore();
    const choice = AppAppearance(dashboard: DashboardStyle.minimal);
    await store.save('uid-1', choice);
    expect(await store.cached('uid-1'), choice);
    expect(await store.cached('uid-2'), const AppAppearance());
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('Giao diện screen picks every option x$scale', (tester) async {
      await _pump(
        tester,
        const AppearanceScreen(),
        scale,
        height: 900,
        scroll: false,
      );
      expect(tester.takeException(), isNull);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppearanceScreen)),
      );
      Future<void> pick(String key) async {
        final finder = find.byKey(ValueKey(key));
        await tester.scrollUntilVisible(
          finder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await pick('appearance-dashboard-lcd');
      await pick('appearance-charge-detail');
      await pick('appearance-confirm-tap');
      expect(container.read(appearanceProvider).dashboard, DashboardStyle.lcd);
      expect(container.read(appearanceProvider).charge, ChargeStyle.detail);
      expect(
        container.read(appearanceProvider).confirm,
        ChargeConfirmStyle.tap,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('appearance-tap-warning')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Overview layouts fit and show only real data x$scale', (
      tester,
    ) async {
      var charged = 0;
      await _pump(
        tester,
        Column(
          children: [
            LcdClusterHero(vehicle: _feliz),
            const SizedBox(height: 12),
            CompactMetricsHero(vehicle: _feliz),
            const SizedBox(height: 12),
            MinimalHero(vehicle: _feliz, onCharge: () => charged++),
            const SizedBox(height: 12),
            // No data entered: dashes, never a made-up 100%.
            CompactMetricsHero(
              vehicle: VehicleModel(
                vehicleId: 'v2',
                vehicleName: 'VinFast Evo',
                currentOdo: 0,
                currentBattery: 100,
                hasBatteryData: false,
                hasSohData: false,
                hasOdoData: false,
              ),
            ),
          ],
        ),
        scale,
        height: 2600,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('68%'), findsWidgets);
      expect(find.textContaining('4 818'), findsOneWidget);
      expect(find.text('100%'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('dashboard-minimal-charge')),
      );
      await tester.tap(find.byKey(const ValueKey('dashboard-minimal-charge')));
      expect(charged, 1);
    });

    for (final style in ChargeStyle.values) {
      testWidgets('active charge card "${style.id}" fits x$scale', (
        tester,
      ) async {
        var stopped = 0;
        await _pump(
          tester,
          ActiveChargingCardV2(
            style: style,
            currentPercent: 63,
            targetPercent: 80,
            estimatedSoc: 63,
            remaining: const Duration(minutes: 38),
            completionTime: '10:30',
            sessionEnergyWh: 96,
            powerW: 412,
            voltageV: 231,
            currentA: 1.8,
            temperatureC: 31,
            timerVerified: true,
            onStop: () => stopped++,
          ),
          scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('session-countdown')), findsOneWidget);
        final stop = find.text('Dừng sạc');
        await tester.ensureVisible(stop);
        await tester.tap(stop);
        expect(stopped, 1);
      });
    }

    for (final style in [
      ChargeStyle.bar,
      ChargeStyle.lcd,
      ChargeStyle.detail,
    ]) {
      testWidgets('range input "${style.id}" moves both values x$scale', (
        tester,
      ) async {
        double? current, target;
        await _pump(
          tester,
          SocRangeInput(
            style: style,
            current: 40,
            target: 80,
            etaLabel: '≈ 1g10',
            onCurrentChanged: (v) => current = v,
            onTargetChanged: (v) => target = v,
            onEditCurrent: () {},
          ),
          scale,
          height: 900,
        );
        expect(tester.takeException(), isNull);
        final slider = find.byKey(const ValueKey('soc-range-input'));
        final box = tester.getRect(slider);
        // Drag the target thumb (at 80%) towards 95%.
        final track = box.width - 48;
        await tester.dragFrom(
          Offset(box.left + 24 + track * 0.8, box.center.dy),
          Offset(track * 0.15, 0),
        );
        expect(target, isNotNull);
        expect(target!, greaterThan(80));
        // And the current thumb (at 40%) down.
        await tester.dragFrom(
          Offset(box.left + 24 + track * 0.4, box.center.dy),
          Offset(-track * 0.1, 0),
        );
        expect(current, isNotNull);
        expect(current!, lessThan(40));
      });
    }

    testWidgets(
      'hold-to-confirm needs a full second; tap needs one tap x$scale',
      (tester) async {
        var held = 0, tapped = 0;
        await _pump(
          tester,
          Column(
            children: [
              ChargeConfirmControl(
                style: ChargeConfirmStyle.hold,
                label: 'Vuốt để bật sạc',
                onConfirmed: () => held++,
              ),
              const SizedBox(height: 12),
              ChargeConfirmControl(
                style: ChargeConfirmStyle.tap,
                label: 'Vuốt để bật sạc',
                onConfirmed: () => tapped++,
              ),
            ],
          ),
          scale,
          height: 700,
        );
        expect(tester.takeException(), isNull);
        final hold = find.byKey(LuxeHoldToConfirm.buttonKey);
        // A quick tap does nothing.
        await tester.tap(hold);
        await tester.pump(const Duration(milliseconds: 1200));
        expect(held, 0);
        // Holding for a second confirms once.
        final gesture = await tester.startGesture(tester.getCenter(hold));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(held, 0);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await gesture.up();
        expect(held, 1);
        await tester.tap(find.byKey(const ValueKey('charge-confirm-tap')));
        expect(tapped, 1);
      },
    );
  }
}
