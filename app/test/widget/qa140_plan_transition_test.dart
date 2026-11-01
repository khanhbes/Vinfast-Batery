import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/entitlement.dart';
import 'package:vinfast_battery/features/premium/plan_transition_overlay.dart';

/// QA 140 (item 7): the plan-change animation, about five seconds, skipped
/// by a tap, still for two seconds with "reduce motion".
Future<void> _pump(
  WidgetTester tester, {
  required PlanTier from,
  required PlanTier to,
  required VoidCallback onDone,
  bool reduce = false,
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 680));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: LuxeTheme.data(),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(320, 680),
          disableAnimations: reduce,
          textScaler: TextScaler.linear(scale),
        ),
        child: PlanTransitionOverlay(from: from, to: to, onDone: onDone),
      ),
    ),
  );
}

void main() {
  testWidgets('an upgrade names the plan and its benefits, then ends', (
    tester,
  ) async {
    var done = 0;
    await _pump(
      tester,
      from: PlanTier.free,
      to: PlanTier.ultra,
      onDone: () => done++,
    );
    await tester.pump(const Duration(milliseconds: 3200));
    expect(find.text('Pinova Ultra'), findsOneWidget);
    expect(find.text('ĐÃ NÂNG LÊN GÓI ULTRA'), findsOneWidget);
    expect(find.text(PremiumFeature.learningTrain.label), findsOneWidget);
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 2000));
    expect(done, 1);
  });

  testWidgets('a tap skips it', (tester) async {
    var done = 0;
    await _pump(
      tester,
      from: PlanTier.pro,
      to: PlanTier.free,
      onDone: () => done++,
    );
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('ĐÃ CHUYỂN VỀ GÓI FREE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-transition')));
    expect(done, 1);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('reduce motion: a still card for two seconds (×$scale)', (
      tester,
    ) async {
      var done = 0;
      await _pump(
        tester,
        from: PlanTier.free,
        to: PlanTier.pro,
        onDone: () => done++,
        reduce: true,
        scale: scale,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Pinova Pro'), findsOneWidget);
      await tester.pump(PlanTransitionOverlay.stillDuration);
      expect(done, 1);
    });
  }
}
