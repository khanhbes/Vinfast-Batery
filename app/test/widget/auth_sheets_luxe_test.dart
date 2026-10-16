import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/dashboard_preferences_service.dart'
    show dashboardPreferencesProvider;
import 'package:vinfast_battery/core/theme/app_theme.dart';
import 'package:vinfast_battery/core/widgets/luxe_settings.dart';
import 'package:vinfast_battery/features/ai/widgets/edit_current_battery_sheet.dart';
import 'package:vinfast_battery/features/auth/login_screen.dart';
import 'package:vinfast_battery/features/auth/register_screen.dart';
import 'package:vinfast_battery/features/auth/widgets/luxe_auth_widgets.dart';
import 'package:vinfast_battery/features/overview/widgets/dashboard_customization_sheet.dart';

/// Task 118 — LUXE auth screens and sheets.
void _phone(WidgetTester tester, {double height = 640}) {
  tester.view.physicalSize = Size(320, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget home, {double scale = 1}) => MaterialApp(
  theme: AppTheme.darkTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
    child: child!,
  ),
  home: home,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Password strength scores length and character mix', () {
    expect(LuxePasswordStrength.score(''), 0);
    expect(LuxePasswordStrength.score('abc'), 1);
    expect(LuxePasswordStrength.score('abcdefgh'), 1);
    expect(LuxePasswordStrength.score('abcdefghijk'), 2);
    expect(LuxePasswordStrength.score('Abcdefghijk'), 3);
    expect(LuxePasswordStrength.score('Abcdefgh1!jk'), 4);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('Login is LUXE and fits 320dp at x$scale', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(const LoginScreen(), scale: scale));
      await tester.pumpAndSettle();
      expect(find.byType(LuxeAuthEmblem), findsOneWidget);
      expect(find.text('Chào mừng trở lại'), findsOneWidget);
      final submit = find.byType(FilledButton);
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(find.text('Nhập email'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Register strength meter follows typing at x$scale', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_app(const RegisterScreen(), scale: scale));
      await tester.pumpAndSettle();
      final password = find.widgetWithText(TextFormField, 'Mật khẩu');
      await tester.ensureVisible(password);
      await tester.enterText(password, 'Abcdefgh1!jk');
      await tester.pump();
      expect(find.text('Rất mạnh'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Edit battery sheet steps, presets and saves at x$scale', (
      tester,
    ) async {
      _phone(tester, height: 760);
      double? saved;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => EditCurrentBatterySheet.show(
                  context,
                  initialPercent: 41,
                  onSave: (v) => saved = v,
                ),
                child: const Text('open'),
              ),
            ),
          ),
          scale: scale,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('41'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Tăng 1%'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tăng 1%'));
      await tester.pump();
      expect(find.text('42'), findsOneWidget);
      await tester.ensureVisible(find.text('50%'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('50%'));
      await tester.pump();
      final confirm = find.text('Xác nhận mức pin');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(saved, 50);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Dashboard sheet toggles with LuxeSwitch and keeps one visible', (
    tester,
  ) async {
    _phone(tester, height: 760);
    await tester.pumpWidget(
      ProviderScope(
        child: _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => DashboardCustomizationSheet.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Customize Dashboard'), findsOneWidget);
    final switches = find.byType(LuxeSwitch);
    // The list is lazy; at least the first rows are built.
    expect(switches, findsWidgets);
    await tester.tap(switches.first);
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DashboardCustomizationSheet)),
    );
    final service = container.read(dashboardPreferencesProvider);
    expect(service.isVisible(service.order.first), isFalse);
    expect(tester.takeException(), isNull);
  });
}
