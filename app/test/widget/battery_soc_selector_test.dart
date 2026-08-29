import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/widgets/battery_soc_selector.dart';

void main() {
  testWidgets('battery selector exposes presets and accessibility actions', (
    tester,
  ) async {
    var value = 70.0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: BatterySocSelector(
              value: value,
              minimum: 31,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.text('80%'));
    await tester.pump();
    expect(find.text('~80%'), findsOneWidget);
  });
}
