import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/settings_service.dart';
import 'package:vinfast_battery/core/theme/app_theme.dart';
import 'package:vinfast_battery/core/widgets/bootstrap_splash.dart';
import 'package:vinfast_battery/features/ai/widgets/timed_charging_section_v2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LUXE renders dark for every stored theme preference', () async {
    SharedPreferences.setMockInitialValues({'app_theme_mode': 'light'});
    final settings = SettingsService();
    await settings.initialize();
    expect(settings.getThemeModeValue(), ThemeMode.dark);
    for (final mode in AppThemeMode.values) {
      await settings.setThemeMode(mode);
      expect(
        (await SharedPreferences.getInstance()).getString('app_theme_mode'),
        mode.name,
      );
      expect(settings.getThemeModeValue(), ThemeMode.dark);
    }
    expect(AppTheme.darkTheme.brightness, Brightness.dark);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('Buttons have 48dp minimum at text x$scale', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
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
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Pinova'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
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
