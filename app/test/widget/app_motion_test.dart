import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/app_motion.dart';
import 'package:vinfast_battery/core/widgets/app_tab_stack.dart';

void main() {
  testWidgets(
    'Reveal is interactive immediately and does not replay on rebuild',
    (tester) async {
      var taps = 0;
      Widget page() => MaterialApp(
        home: Center(
          child: AppReveal(
            delay: const Duration(seconds: 5),
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('Action'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.tap(find.text('Action'));
      expect(taps, 1);
      await tester.pumpAndSettle();
      await tester.pumpWidget(page());
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(AppReveal),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 1);
      expect(tester.hasRunningAnimations, isFalse);
    },
  );

  testWidgets('Reduced motion shows reveals immediately', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Column(
            children: [const Text('Ready').appFadeSlideIn(index: 99)],
          ),
        ),
      ),
    );
    expect(find.text('Ready'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  for (final reduce in [false, true]) {
    testWidgets('Tabs retain state and mute hidden tickers (reduced=$reduce)', (
      tester,
    ) async {
      final first = GlobalKey<_CounterTabState>();
      final second = GlobalKey<_CounterTabState>();
      Widget page(int index) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: AppTabStack(
            index: index,
            children: [
              _CounterTab(key: first),
              _CounterTab(key: second),
            ],
          ),
        ),
      );
      await tester.pumpWidget(page(0));
      final original = first.currentState;
      await tester.tap(find.text('Count 0').hitTestable());
      await tester.pump();
      expect(first.currentState!.count, 1);
      await tester.pumpWidget(page(1));
      expect(TickerMode.valuesOf(first.currentContext!).enabled, isFalse);
      expect(TickerMode.valuesOf(second.currentContext!).enabled, isTrue);
      if (reduce) expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpAndSettle();
      await tester.pumpWidget(page(0));
      await tester.pumpAndSettle();
      expect(first.currentState, same(original));
      expect(find.text('Count 1').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('AppTactileBounce handles tap, scale compression, and rebounds', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: const Text(
            'Bounce Target',
          ).appTactile(pressScale: 0.96, onTap: () => taps++),
        ),
      ),
    );

    // Initial state: scale 1.0
    final scaleFinder = find.byType(ScaleTransition);
    expect(scaleFinder, findsOneWidget);
    var scaleTransition = tester.widget<ScaleTransition>(scaleFinder);
    expect(scaleTransition.scale.value, 1.0);

    // Press down
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Bounce Target')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    scaleTransition = tester.widget<ScaleTransition>(scaleFinder);
    expect(scaleTransition.scale.value, closeTo(0.96, 0.02));

    // Release
    await gesture.up();
    await tester.pumpAndSettle();
    scaleTransition = tester.widget<ScaleTransition>(scaleFinder);
    expect(scaleTransition.scale.value, 1.0);
    expect(taps, 1);
  });

  testWidgets('Tactile reduced motion keeps tap without scale animation', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Center(
          child: const Text(
            'Reduced target',
          ).appTactile(onTap: () => taps++, enableHaptic: false),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Reduced target')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value,
      1,
    );
    expect(tester.hasRunningAnimations, isFalse);
    await gesture.up();
    await tester.pump();
    expect(taps, 1);
  });
}

class _CounterTab extends StatefulWidget {
  const _CounterTab({super.key});
  @override
  State<_CounterTab> createState() => _CounterTabState();
}

class _CounterTabState extends State<_CounterTab> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('Count $count'),
    ),
  );
}
