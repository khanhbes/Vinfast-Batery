import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/services/server_charge_monitor.dart';
import 'package:vinfast_battery/features/ai/widgets/confirm_actual_soc_sheet.dart';
import 'package:vinfast_battery/features/ai/widgets/prediction_card_v2.dart';
import 'package:vinfast_battery/features/ai/widgets/trip_plan_chat_card.dart';

SmartChargingSession _session({
  double? estimated = 58,
  double energy = 1000,
  String stopMode = 'target',
}) {
  final now = DateTime.utc(2026, 10, 16, 8);
  return SmartChargingSession(
    sessionId: 's1',
    vehicleId: 'car',
    state: ChargingSessionState.active,
    strategy: ChargingStrategy.targetSoc,
    startSoc: 20,
    targetSoc: 80,
    predictedMinutes: 213,
    predictionSource: 'personal_physics',
    createdAt: now,
    updatedAt: now,
    aiStopAt: now.add(const Duration(minutes: 213)),
    hardDeadlineAt: now.add(const Duration(hours: 10)),
    effectiveStopAt: now.add(const Duration(minutes: 276)),
    absoluteSafetyStopAt: now.add(const Duration(hours: 10)),
    shadowMode: false,
    version: 2,
    estimatedSoc: estimated,
    energyUsedWh: energy,
    stopMode: stopMode,
    targetEnergyWh: 1560,
    modelWhPerPct: 26,
    averagePowerW: 440,
  );
}

SmartChargerStatus _status(double power) => SmartChargerStatus.fromJson({
  'online': true,
  'relay': true,
  'power_w': power,
  'voltage_v': 230,
  'current_a': power / 230,
  'energy_wh': 0,
  'timer_remaining': 16000,
});

Widget _host(Widget child, double scale) => MaterialApp(
  theme: LuxeTheme.data(),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(320, 640),
      textScaler: TextScaler.linear(scale),
    ),
    child: Scaffold(body: child),
  ),
);

void main() {
  group('ConfirmActualSocSheet', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('320 dp, text x$scale: estimate, steps, ODO check', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        ActualSocReading? result;
        await tester.pumpWidget(
          _host(
            Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async {
                    result = await ConfirmActualSocSheet.show(
                      context,
                      estimatedSoc: 79.4,
                      startSoc: 22,
                      currentOdoKm: 1200,
                    );
                  },
                  child: const Text('Mở'),
                ),
              ),
            ),
            scale,
          ),
        );
        await tester.tap(find.text('Mở'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Pre-filled with the rounded estimate.
        expect(find.text('Lưu 79%'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('actual-soc-plus')),
        );
        await tester.tap(find.byKey(const ValueKey('actual-soc-plus')));
        await tester.pumpAndSettle();
        final odo = find.byKey(const ValueKey('actual-soc-odo'));
        await tester.ensureVisible(odo);
        await tester.enterText(odo, '1100');
        await tester.ensureVisible(
          find.byKey(const ValueKey('actual-soc-save')),
        );
        await tester.tap(find.byKey(const ValueKey('actual-soc-save')));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(find.textContaining('ODO không thể nhỏ hơn'), findsOneWidget);
        await tester.enterText(odo, '1234,5');
        await tester.ensureVisible(
          find.byKey(const ValueKey('actual-soc-save')),
        );
        await tester.tap(find.byKey(const ValueKey('actual-soc-save')));
        await tester.pumpAndSettle();
        expect(result?.soc, 80); // estimate 79 + one step
        expect(result?.odoKm, 1234.5);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ongoing charge notification text', () {
    final now = DateTime.utc(2026, 10, 16, 10);

    test('target charge: %, power and time to the target', () {
      final content = ServerChargeNotificationContent.from(
        session: _session(),
        status: _status(440),
        now: now,
      );
      expect(content.title, 'Đang sạc ~58% → 80%');
      expect(content.text, contains('440 W'));
      expect(content.text, contains('còn ~'));
      expect(content.text, contains('xong ~'));
      // 22 % x 26 Wh / 440 W = 78 min.
      final left = ServerChargeNotificationContent.remaining(
        session: _session(),
        status: _status(440),
        now: now,
      )!;
      expect(left.inMinutes, 78);
    });

    test('scooter not drawing power says so', () {
      final content = ServerChargeNotificationContent.from(
        session: _session(),
        status: _status(2),
        now: now,
      );
      expect(content.text, contains('Xe chưa nhận điện'));
    });

    test('server ride-through: the gap is explained, not an error', () {
      final content = ServerChargeNotificationContent.from(
        session: _session(),
        now: now,
        linkLost: true,
      );
      expect(content.text, contains('Tạm mất kết nối với ổ'));
      expect(content.text, contains('vẫn sạc'));
    });

    test('failed reads keep the safety ceiling visible', () {
      final content = ServerChargeNotificationContent.from(
        session: _session(),
        now: now,
        failedReads: 3,
      );
      expect(content.text, contains('Shelly vẫn tự tắt muộn nhất'));
    });

    test('unknown battery % never shows a made-up number', () {
      final content = ServerChargeNotificationContent.from(
        session: _session(estimated: null, stopMode: 'timer'),
        status: _status(440),
        now: now,
      );
      expect(content.title, 'Đang sạc —');
    });
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('prediction card shows the range at 320 dp x$scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _host(
          const SingleChildScrollView(
            child: PredictionCardV2(
              durationMinutes: 213,
              stopTime: '11:33',
              fromSoc: 20,
              toSoc: 80,
              personalizationLabel: 'Học từ 2 lần sạc · sai số ~±0.8%',
              rangeLabel: '3 giờ 1 phút – 4 giờ 5 phút',
              stopLine: 'Đạt ~80% lúc 11:33 · máy chủ tự ngắt',
            ),
          ),
          scale,
        ),
      );
      expect(find.byKey(const ValueKey('prediction-range')), findsOneWidget);
      expect(find.textContaining('máy chủ tự ngắt'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('BatteryBot trip card at 320 dp x$scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _host(
          const SingleChildScrollView(
            child: TripPlanChatCard(
              title: 'Đi Sân bay Nội Bài',
              data: {
                'usePct': 40.0,
                'useLowPct': 32.0,
                'useHighPct': 48.0,
                'arrivalSoc': -10.0,
                'distanceKm': 18.0,
                'carMinutes': 35,
                'verdict': 'insufficient',
                'kmPerPctSource': 'catalog',
                'suggestions': [
                  {'kind': 'charge_first', 'targetSoc': 70},
                  {'kind': 'shorter_route', 'distanceKm': 16.2, 'savedPct': 4},
                ],
              },
            ),
          ),
          scale,
        ),
      );
      expect(find.text('Không đủ pin'), findsOneWidget);
      expect(find.textContaining('hết pin trước khi tới'), findsOneWidget);
      expect(find.textContaining('Sạc lên 70%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
