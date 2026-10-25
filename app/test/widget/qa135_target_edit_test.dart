import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/widgets/charge_confirm_control.dart';
import 'package:vinfast_battery/features/ai/widgets/confirm_actual_soc_sheet.dart';
import 'package:vinfast_battery/features/ai/widgets/edit_target_sheet.dart';

/// QA 135: change the target while charging; every save shows progress.
Future<void> _pump(
  WidgetTester tester,
  Widget sheet,
  double scale, {
  double height = 1100,
}) async {
  await tester.binding.setSurfaceSize(Size(320, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: LuxeTheme.data(),
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: page!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: sheet)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scale in [1.0, 2.0]) {
    testWidgets('raising asks the ON confirmation at ×$scale', (tester) async {
      final asked = <double>[];
      await _pump(
        tester,
        EditTargetSheet(
          currentSoc: 50,
          currentTarget: 80,
          onSubmit: (t) async {
            asked.add(t);
            return null;
          },
        ),
        scale,
        height: scale == 1 ? 1100 : 2200,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('80%'), findsWidgets);
      await tester.tap(find.widgetWithText(ChoiceChip, '90%'));
      await tester.pump();
      expect(find.byKey(const ValueKey('edit-target-value')), findsOneWidget);
      expect(find.text('90%'), findsWidgets);
      // Higher = charging longer: the owner's ON confirmation, not a tap.
      final control = tester.widget<ChargeConfirmControl>(
        find.byType(ChargeConfirmControl),
      );
      expect(control.label, 'Vuốt để sạc đến 90%');
      expect(find.byKey(const ValueKey('edit-target-lower')), findsNothing);
      control.onConfirmed();
      await tester.pump();
      expect(asked, [90]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('edit-target-done')), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('lowering is a plain button; a refusal keeps the sheet open', (
    tester,
  ) async {
    final asked = <double>[];
    await _pump(
      tester,
      EditTargetSheet(
        currentSoc: 50,
        currentTarget: 90,
        onSubmit: (t) async {
          asked.add(t);
          return 'Chưa đổi được mục tiêu. Mục tiêu cũ vẫn giữ nguyên.';
        },
      ),
      1,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '80%'));
    await tester.pump();
    expect(find.byType(ChargeConfirmControl), findsNothing);
    await tester.tap(find.byKey(const ValueKey('edit-target-lower')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(asked, [80]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('edit-target-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-target-lower')), findsOneWidget);
  });

  testWidgets('the target can never be set below the current charge', (
    tester,
  ) async {
    await _pump(
      tester,
      EditTargetSheet(
        currentSoc: 87,
        currentTarget: 90,
        onSubmit: (_) async => null,
      ),
      1,
    );
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('edit-target-slider')),
    );
    expect(slider.min, 89);
    expect(find.widgetWithText(ChoiceChip, '80%'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '85%'), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('actual % sheet saves in place at ×$scale', (tester) async {
      var calls = 0;
      await _pump(
        tester,
        ConfirmActualSocSheet(
          estimatedSoc: 79,
          startSoc: 20,
          onSave: (reading) async {
            calls++;
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return calls == 1 ? 'Không thể kết nối tới máy chủ.' : null;
          },
        ),
        scale,
        height: scale == 1 ? 1300 : 2600,
      );
      expect(tester.takeException(), isNull);
      final save = find.byKey(const ValueKey('actual-soc-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('submit-busy')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('actual-soc-error')), findsOneWidget);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 2);
      expect(find.byKey(const ValueKey('submit-done')), findsOneWidget);
      expect(find.byKey(const ValueKey('actual-soc-error')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
