import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/features/ai/widgets/active_charging_card_v2.dart';
import 'package:vinfast_battery/features/ai/widgets/command_progress_strip.dart';

Future<void> _pump(WidgetTester tester, Widget child, double scale) async {
  await tester.binding.setSurfaceSize(const Size(320, 760));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: LuxeTheme.data(),
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: page!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('command strip fits 320dp at text x$scale', (tester) async {
      var now = DateTime(2026, 10, 14, 9);
      await _pump(
        tester,
        CommandProgressStrip(kind: RelayCommandKind.on, clock: () => now),
        scale,
      );
      expect(find.text('Đang bật sạc'), findsOneWidget);
      expect(find.text('0 giây'), findsOneWidget);
      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('3 giây'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pending OFF says the command will not be resent at x$scale', (
      tester,
    ) async {
      await _pump(
        tester,
        const CommandProgressStrip(kind: RelayCommandKind.offAwaitingReadback),
        scale,
      );
      expect(find.text('Đã gửi lệnh tắt'), findsOneWidget);
      expect(find.textContaining('không gửi lại lệnh'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('active card shows hardware timer and estimate at x$scale', (
      tester,
    ) async {
      await _pump(
        tester,
        ActiveChargingCardV2(
          currentPercent: 40,
          targetPercent: 80,
          estimatedSoc: 52,
          remaining: const Duration(minutes: 90),
          completionTime: '10:30',
          sessionEnergyWh: 120,
          powerW: 420,
          voltageV: 230,
          currentA: 1.8,
          temperatureC: 31,
          timerVerified: true,
          estimateNote:
              'Đạt 80% sau khoảng 1 giờ 10 phút · khoảng 10:10 (420 W đo thực tế)',
          onStop: () {},
        ),
        scale,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Shelly tự ngắt sau · lúc 10:30'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-estimate-note')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending OFF readback replaces the status label', (tester) async {
    await _pump(
      tester,
      ActiveChargingCardV2(
        currentPercent: 40,
        targetPercent: 80,
        remaining: const Duration(minutes: 1),
        completionTime: '10:30',
        sessionEnergyWh: 0,
        powerW: 0,
        voltageV: 230,
        currentA: 0,
        temperatureC: null,
        timerVerified: true,
        isStopping: true,
        stopAwaitingReadback: true,
        onStop: () {},
      ),
      1,
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('ĐÃ GỬI LỆNH TẮT · CHỜ XÁC NHẬN'), findsOneWidget);
  });
}
