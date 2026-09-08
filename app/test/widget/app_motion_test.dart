import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/app_motion.dart';
import 'package:vinfast_battery/core/widgets/app_tab_stack.dart';
import 'package:vinfast_battery/core/widgets/animated_battery_gauge.dart';
import 'package:vinfast_battery/core/widgets/premium_card.dart';

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

  testWidgets('Reduced motion shows reveals and battery value immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Column(
            children: [
              const Text('Ready').appFadeSlideIn(index: 99),
              const Text('Badge').appScalePop(),
              const AnimatedBatteryGauge(batteryPercent: 68),
            ],
          ),
        ),
      ),
    );
    expect(find.text('68%'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('Battery reports target SOC during decorative interpolation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AnimatedBatteryGauge(batteryPercent: 68)),
    );
    expect(find.text('68%'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(
      const MaterialApp(home: AnimatedBatteryGauge(batteryPercent: 73)),
    );
    expect(find.text('73%'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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

  testWidgets('Premium card supports pointer and keyboard activation', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PremiumCard(onTap: () => taps++, child: const Text('Open')),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(taps, 2);
    expect(tester.takeException(), isNull);
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
