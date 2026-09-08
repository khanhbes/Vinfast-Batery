import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/settings_service.dart';
import 'package:vinfast_battery/core/theme/app_theme.dart';
import 'package:vinfast_battery/core/widgets/bootstrap_splash.dart';
import 'package:vinfast_battery/features/ai/widgets/timed_charging_section_v2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('Theme preferences preserve light, system, dark and AMOLED', () async {
    SharedPreferences.setMockInitialValues({'app_theme_mode': 'light'});
    final settings = SettingsService();
    await settings.initialize();
    expect(settings.getThemeModeValue(), ThemeMode.light);
    for (final mode in AppThemeMode.values) {
      await settings.setThemeMode(mode);
      expect(
        (await SharedPreferences.getInstance()).getString('app_theme_mode'),
        mode.name,
      );
      expect(settings.getThemeModeValue(), switch (mode) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.system => ThemeMode.system,
        _ => ThemeMode.dark,
      });
    }
  });

  for (final dark in [false, true]) {
    testWidgets('Buttons have 48dp minimum in ${dark ? "dark" : "light"}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(onPressed: () {}, child: const Text('Sạc')),
                OutlinedButton(onPressed: () {}, child: const Text('Chi tiết')),
                TextButton(onPressed: () {}, child: const Text('Hủy')),
                IconButton(onPressed: () {}, icon: const Icon(Icons.settings)),
              ],
            ),
          ),
        ),
      );
      for (final type in [
        FilledButton,
        OutlinedButton,
        TextButton,
        IconButton,
      ]) {
        expect(
          tester.getSize(find.byType(type)).height,
          greaterThanOrEqualTo(48),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Splash respects reduced motion and large text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: const BootstrapSplash(
            message: 'Đang khôi phục phiên đăng nhập…',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('VinFast Battery'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Timed start submits once and restores control after completion',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: TimedChargingSectionV2(
                  readyForControl: true,
                  onOff: () {},
                  onStart: (duration) {
                    calls++;
                    expect(duration, const Duration(hours: 2));
                    return pending.future;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final button = find.byKey(const ValueKey('timed-charge-start-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      expect(calls, 1);
      expect(find.text('Đang gửi lệnh sạc…'), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Đang gửi lệnh sạc…'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
