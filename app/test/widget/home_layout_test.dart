import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/providers/app_providers.dart';
import 'package:vinfast_battery/features/home/home_screen.dart';

void main() {
  for (final variant in [
    (1.0, Brightness.light),
    (2.0, Brightness.light),
    (1.0, Brightness.dark),
    (2.0, Brightness.dark),
  ]) {
    final (scale, brightness) = variant;
    testWidgets('Home empty state scrolls at 320dp / $scale / $brightness', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allVehiclesProvider.overrideWith((ref) async => []),
            restoreVehicleIdProvider.overrideWith((ref) async => ''),
            vehicleProvider.overrideWith((ref, id) async => null),
          ],
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const HomeScreen(),
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
      expect(find.text('Hiệu suất lái xe'), findsNothing);
      expect(find.text('Thành tích lái xe'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
