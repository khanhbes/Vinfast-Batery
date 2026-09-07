import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/app_colors.dart';
import 'package:vinfast_battery/core/theme/app_theme.dart';
import 'package:vinfast_battery/core/widgets/animated_battery_gauge.dart';

void main() {
  group('QA Audit — Responsive Viewports, Text Scaling & Dark Theme (CHK-51..54, CHK-56, APP-UX-H16)', () {
    Widget buildTestHost({
      required Widget child,
      required Size size,
      double textScale = 1.0,
      ThemeData? theme,
    }) {
      return MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: child,
          ),
        ),
      );
    }

    testWidgets('CHK-51 & APP-UX-H16: Battery Gauge renders without overflow at 320x568 (iPhone SE)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestHost(
          size: const Size(320, 568),
          child: const Center(
            child: AnimatedBatteryGauge(
              batteryPercent: 78,
              size: 160,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AnimatedBatteryGauge), findsOneWidget);
    });

    testWidgets('CHK-54: Battery Gauge at 1.5x and 2.0x text scaling remains layout-stable', (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Test 1.5x text scale
      await tester.pumpWidget(
        buildTestHost(
          size: const Size(375, 812),
          textScale: 1.5,
          child: const Center(
            child: AnimatedBatteryGauge(
              batteryPercent: 45,
              size: 180,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Test 2.0x extreme text scale
      await tester.pumpWidget(
        buildTestHost(
          size: const Size(375, 812),
          textScale: 2.0,
          child: const Center(
            child: AnimatedBatteryGauge(
              batteryPercent: 100,
              size: 180,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('CHK-56: Dark Luxury Cockpit theme background and surface colors match specifications', (tester) async {
      final theme = AppTheme.darkTheme;

      expect(theme.scaffoldBackgroundColor, AppColors.background);
      expect(AppColors.background, const Color(0xFF050505));
      expect(AppColors.accentGreen, const Color(0xFF10B981));
    });
  });
}
