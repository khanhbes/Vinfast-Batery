import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/assistant_context_coordinator.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/widgets/app_popup.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/features/battery_monitor/widgets/health_trend_chart.dart';
import 'package:vinfast_battery/features/home/widgets/luxe_vehicle_hero.dart';

/// QA 149, found on the owner's phone while a charge ran: a notice stuck on
/// screen for good, the Overview kept the % from before the charge, and
/// Pinova Bot offered to plan a charge for it.
void main() {
  Widget app(Widget home) => MaterialApp(
    navigatorKey: AppPopup.navigatorKey,
    scaffoldMessengerKey: AppPopup.messengerKey,
    theme: LuxeTheme.data(),
    home: home,
  );

  setUp(AppPopup.resetForTesting);
  tearDown(AppPopup.dismiss);

  group('notices', () {
    testWidgets('a notice replaced before it was drawn does not stay', (
      tester,
    ) async {
      await tester.pumpWidget(app(const Scaffold()));
      // Two notices in the same frame: the first is inserted, not built.
      AppPopup.showSuccess('Đã bắt đầu sạc');
      AppPopup.showSuccess('Đã tắt sạc');
      await tester.pump();
      expect(find.text('Đã bắt đầu sạc'), findsNothing);
      expect(find.text('Đã tắt sạc'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 3200));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Đã tắt sạc'), findsNothing);
    });

    testWidgets('a notice\'s close button removes that notice', (tester) async {
      await tester.pumpWidget(app(const Scaffold()));
      AppPopup.showSuccess('Đã bắt đầu sạc');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Đã bắt đầu sạc'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(find.text('Đã bắt đầu sạc'), findsNothing);
    });

    testWidgets('success notices go by themselves', (tester) async {
      await tester.pumpWidget(app(const Scaffold()));
      AppPopup.showSuccess('Đã bắt đầu sạc');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Đã bắt đầu sạc'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Đã bắt đầu sạc'), findsNothing);
    });
  });

  // QA 149: the phone's chart read "120 %" for one charge's gauge error.
  for (final scale in [1.0, 2.0]) {
    testWidgets('battery health per charge stops at 100 % x$scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app(
          MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 640),
              textScaler: TextScaler.linear(scale),
            ),
            child: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: HealthTrendChart(
                  points: [
                    (null, 99.0),
                    (null, 121.0),
                    (null, 86.0),
                    (null, 99.4),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('điểm rỗng là lần đo vượt 100%'),
        findsOneWidget,
      );
    });
  }

  group('while a charge runs', () {
    final car = VehicleModel(
      vehicleId: 'car',
      ownerUid: 'u',
      vehicleName: 'VinFast Feliz',
      currentBattery: 9,
      currentOdo: 5398,
    );

    test('Pinova Bot does not offer to plan a charge', () {
      final bot = AssistantContextCoordinator();
      addTearDown(bot.dispose);
      final noon = DateTime(2026, 11, 8, 12);
      expect(
        bot.evaluateContext(vehicle: car, now: noon, charging: true),
        isFalse,
      );
      expect(bot.evaluateContext(vehicle: car, now: noon), isTrue);
    });

    testWidgets('the Overview names the % as the charge\'s estimate', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SingleChildScrollView(
              child: LuxeVehicleHero(
                vehicle: car.copyWith(currentBattery: 28),
                charging: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Đang sạc · ước tính'), findsOneWidget);
      expect(find.text('Pin hiện tại'), findsNothing);
    });
  });
}
