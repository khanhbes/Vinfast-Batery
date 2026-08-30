import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/widgets/charging_battery_animation.dart';
import 'package:vinfast_battery/features/ai/widgets/horizontal_battery_target_selector.dart';

void main() {
  testWidgets('horizontal battery exposes presets and semantic step actions', (
    tester,
  ) async {
    var value = 70.0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: HorizontalBatteryTargetSelector(
              value: value,
              currentSoc: 40,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );

    expect(find.text('80%'), findsOneWidget);
    await tester.tap(find.text('80%'));
    await tester.pump();
    expect(value, 80);

    final semantics = tester.getSemantics(
      find.byType(HorizontalBatteryTargetSelector),
    );
    expect(semantics.label, contains('Mức pin muốn sạc'));
    expect(semantics.value, contains('80'));
  });

  testWidgets('charging battery changes only for a new telemetry revision', (
    tester,
  ) async {
    Widget app(double soc, int revision, {bool reducedMotion = false}) =>
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reducedMotion),
            child: Scaffold(
              body: ChargingBatteryAnimationV3(
                currentSoc: soc,
                targetSoc: 90,
                sampleRevision: revision,
              ),
            ),
          ),
        );

    await tester.pumpWidget(app(50, 1));
    expect(find.text('50%'), findsOneWidget);

    await tester.pumpWidget(app(55, 1));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('50%'), findsOneWidget);

    await tester.pumpWidget(app(55, 2, reducedMotion: true));
    await tester.pump();
    expect(find.text('55%'), findsOneWidget);
    expect(find.text('Mục tiêu 90%'), findsOneWidget);
  });
}
