import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/features/ai/controllers/smart_charging_controller.dart';
import 'package:vinfast_battery/features/ai/widgets/start_charge_confirmation_sheet.dart';
import 'package:vinfast_battery/features/ai/widgets/stop_charging_confirmation_sheet.dart';

/// QA 130, seen on the Xiaomi during the supervised no-load ON/OFF test: a
/// 30-minute timed charge showed "Mục tiêu 79% → 100%", and the first frame
/// of the running card counted down from 00:33:22.
Widget _host(Widget child, double scale) => MaterialApp(
  theme: LuxeTheme.data(),
  builder: (context, page) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: page!,
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('timed start sheet shows the estimate, not a target x$scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => StartChargeConfirmationSheet.show(
                context,
                currentSoc: 79,
                targetSoc: 87,
                estimatedMinutes: 30,
                stopTime: '17:24',
                isAiMode: false,
              ),
              child: const Text('open'),
            ),
          ),
          scale,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('ƯỚC TÍNH KHI TỰ NGẮT'), findsOneWidget);
      expect(find.text('87%'), findsOneWidget);
      expect(find.text('MỤC TIÊU'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('timed stop sheet has no target row x$scale', (tester) async {
      tester.view.physicalSize = const Size(320, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showStopChargingConfirmationSheet(
                context,
                currentSoc: 79,
                targetSoc: 100,
                remaining: const Duration(minutes: 29),
              ),
              child: const Text('open'),
            ),
          ),
          scale,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Mục tiêu'), findsNothing);
      expect(find.text('Shelly tự ngắt sau'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('a session that just started gets a fresh clock', () {
    var now = DateTime.utc(2026, 10, 18, 9, 51, 36);
    final controller = SmartChargingController(
      vehicleId: 'car',
      currentSoc: 79,
      autoInitialize: false,
      clock: () => now,
    );
    addTearDown(controller.dispose);
    // Idle: `now` is not ticking and falls minutes behind.
    now = DateTime.utc(2026, 10, 18, 9, 54, 58);
    final session = SmartChargingSession.fromJson({
      'session_id': 's1',
      'vehicle_id': 'car',
      'state': 'active',
      'strategy': 'manual_timed',
      'start_soc': 79,
      'target_soc': 100,
      'predicted_minutes': 30,
      'prediction_source': 'manual',
      'created_at': '2026-10-18T09:54:58Z',
      'updated_at': '2026-10-18T09:54:58Z',
      'started_at': '2026-10-18T09:54:58Z',
      'ai_stop_at': '2026-10-18T10:24:58Z',
      'hard_deadline_at': '2026-10-18T10:24:58Z',
      'effective_stop_at': '2026-10-18T10:24:58Z',
      'absolute_safety_stop_at': '2026-10-18T19:54:58Z',
      'relay_verified': true,
      'version': 1,
    });
    controller.state = controller.state.copyWith(session: session);
    expect(controller.state.now, now);
    expect(controller.state.displayRemaining, const Duration(minutes: 30));
  });
}
