import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/widgets/luxe_settings.dart';
import 'package:vinfast_battery/features/more/more_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(Widget child, {double scale = 1}) => MaterialApp(
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: c!,
    ),
    home: Scaffold(body: child),
  );

  testWidgets('luxe switch toggles by tap and reports toggled semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var value = false;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => Center(
            child: LuxeSwitch(
              value: value,
              semanticLabel: 'Tự động đồng bộ',
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byType(LuxeSwitch)),
      matchesSemantics(
        label: 'Tự động đồng bộ',
        hasToggledState: true,
        isToggled: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.byType(LuxeSwitch));
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(tester.getSize(find.byType(LuxeSwitch)).height, 48);
    handle.dispose();
  });

  testWidgets('coming-soon rows are labelled and never navigate', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        LuxeSettingsGroup(
          children: [
            LuxeSettingsRow(
              icon: Icons.fingerprint_rounded,
              title: 'Xác thực sinh trắc học',
              comingSoon: true,
              onTap: () => taps++,
            ),
            LuxeSettingsRow(
              icon: Icons.tune_rounded,
              title: 'Giao diện',
              onTap: () => taps++,
            ),
          ],
        ),
      ),
    );
    expect(find.text('Sắp có'), findsOneWidget);
    await tester.tap(find.text('Xác thực sinh trắc học'));
    await tester.tap(find.text('Giao diện'));
    expect(taps, 1);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('settings tab fits 320dp at text $scale', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(child: host(const MoreScreen(), scale: scale)),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      final list = find.byType(Scrollable).first;
      for (final text in [
        'Xe của tôi',
        'Sạc thông minh Shelly',
        'Thành tựu',
        'Bảo dưỡng xe',
        'Cài đặt hệ thống',
        'Trung tâm thông báo',
        'Đăng xuất tài khoản',
      ]) {
        await tester.scrollUntilVisible(find.text(text), 200, scrollable: list);
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull, reason: text);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
