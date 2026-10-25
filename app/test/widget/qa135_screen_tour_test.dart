import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/guide_registry.dart';
import 'package:vinfast_battery/core/services/screen_tour.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/widgets/coach_mark_overlay.dart';

/// QA 135: each screen's first-run guide shows once per account on this
/// install, after the Overview guide, and only with its targets on screen.
final _a = GlobalKey(debugLabel: 'a');
final _b = GlobalKey(debugLabel: 'b');

List<CoachMarkStep> _steps() => [
  CoachMarkStep(
    id: 'a',
    titleVi: 'Bước A',
    titleEn: 'Bước A',
    descriptionVi: 'Mô tả A',
    descriptionEn: 'A',
    anchorKey: _a,
  ),
  CoachMarkStep(
    id: 'b',
    titleVi: 'Bước B',
    titleEn: 'Bước B',
    descriptionVi: 'Mô tả B',
    descriptionEn: 'B',
    anchorKey: _b,
  ),
];

Future<BuildContext> _pump(WidgetTester tester, {bool withB = true}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: LuxeTheme.data(),
      home: Scaffold(
        body: Column(
          children: [
            SizedBox(key: _a, height: 80, child: const Text('đích A')),
            if (withB)
              SizedBox(key: _b, height: 80, child: const Text('đích B')),
          ],
        ),
      ),
    ),
  );
  return tester.element(find.text('đích A'));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ScreenTour.currentUid = () => 'u1';
  });
  tearDown(CoachMarkOverlay.dismissActive);

  testWidgets('waits for the Overview guide, then shows once', (tester) async {
    final context = await _pump(tester);
    late bool shown;
    await tester.runAsync(() async {
      shown = await ScreenTour.maybeShow(context, ScreenTour.charge, _steps());
    });
    expect(shown, isFalse, reason: 'Overview first');
    await tester.runAsync(
      () => ScreenTour.markSeen(ScreenTour.overviewInstall),
    );
    await tester.runAsync(() async {
      shown = await ScreenTour.maybeShow(context, ScreenTour.charge, _steps());
    });
    expect(shown, isTrue);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Bước A'), findsOneWidget);
    // Finishing marks it seen: it never shows again on this install.
    CoachMarkOverlay.dismissActive();
    await tester.runAsync(() => ScreenTour.markSeen(ScreenTour.charge));
    await tester.runAsync(() async {
      shown = await ScreenTour.maybeShow(context, ScreenTour.charge, _steps());
    });
    expect(shown, isFalse);
    // "Xem lại hướng dẫn" forgets every screen guide.
    await tester.runAsync(() => ScreenTour.reset());
    expect(
      await tester.runAsync(() => ScreenTour.seen(ScreenTour.charge)),
      isFalse,
    );
  });

  testWidgets('steps whose target is not built yet are left out', (
    tester,
  ) async {
    final context = await _pump(tester, withB: false);
    await tester.runAsync(
      () => ScreenTour.markSeen(ScreenTour.overviewInstall),
    );
    late bool shown;
    await tester.runAsync(() async {
      shown = await ScreenTour.maybeShow(context, ScreenTour.history, _steps());
    });
    expect(shown, isTrue);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Bước A'), findsOneWidget);
    expect(find.text('Bước B'), findsNothing);
  });

  testWidgets('no account, no guide', (tester) async {
    ScreenTour.currentUid = () => null;
    final context = await _pump(tester);
    late bool shown;
    await tester.runAsync(() async {
      shown = await ScreenTour.maybeShow(context, ScreenTour.charge, _steps());
    });
    expect(shown, isFalse);
  });

  test('every screen guide has steps', () {
    for (final steps in [
      GuideRegistry.chargeTourSteps(),
      GuideRegistry.historyTourSteps(),
      GuideRegistry.settingsTourSteps(),
      GuideRegistry.premiumTourSteps(),
      GuideRegistry.botTourSteps(),
      GuideRegistry.scanTourSteps(),
    ]) {
      expect(steps, isNotEmpty);
      expect({for (final s in steps) s.anchorKey}.length, steps.length);
    }
  });
}
