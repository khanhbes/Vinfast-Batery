import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/providers/app_providers.dart';
import 'package:vinfast_battery/features/statistics/statistics_screen.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('Statistics summaries fit 320dp / $scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chargeLogsProvider.overrideWith((ref, id) async => []),
            vehicleStatsProvider.overrideWith(
              (ref, id) async => {
                'totalCharges': 12345,
                'avgChargeGain': 45.0,
                'avgStartBattery': 25.0,
                'avgChargeDuration': 12.5,
              },
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const StatisticsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
