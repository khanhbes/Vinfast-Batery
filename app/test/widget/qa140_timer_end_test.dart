import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/features/ai/widgets/active_charging_card_v2.dart';

/// QA 140 (5a): at 0:00 a timed charge says the outlet is switching off,
/// not "Đang sạc", until the server closes the session.
void main() {
  Widget card({
    required bool endsOnTimer,
    Duration remaining = Duration.zero,
  }) => MaterialApp(
    theme: LuxeTheme.data(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ActiveChargingCardV2(
            currentPercent: 63,
            targetPercent: 80,
            estimatedSoc: 63,
            remaining: remaining,
            completionTime: '09:30',
            sessionEnergyWh: 96,
            powerW: 412,
            voltageV: 231,
            currentA: 1.8,
            temperatureC: 31,
            timerVerified: true,
            endsOnTimer: endsOnTimer,
            onStop: () {},
          ),
        ),
      ),
    ),
  );

  testWidgets('a timed charge at zero is switching off', (tester) async {
    await tester.pumpWidget(card(endsOnTimer: true));
    expect(find.text('HẾT GIỜ · ĐANG NGẮT…'), findsOneWidget);
    expect(find.text('ĐANG SẠC'), findsNothing);
    expect(find.text('Dừng sạc'), findsOneWidget); // Stop stays available
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('before zero, or for a target charge, it is charging', (
    tester,
  ) async {
    await tester.pumpWidget(
      card(endsOnTimer: true, remaining: const Duration(hours: 1)),
    );
    expect(find.text('ĐANG SẠC'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(card(endsOnTimer: false));
    expect(find.text('ĐANG SẠC'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
