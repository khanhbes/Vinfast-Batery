import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/widgets/power_action_button.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'Power action presses without delaying callback / reduced=$reduced',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  disableAnimations: reduced,
                  textScaler: const TextScaler.linear(2),
                ),
                child: SizedBox(
                  width: 280,
                  child: PowerActionButton(
                    onPressed: () => calls++,
                    label: 'NGẮT NGUỒN NGAY',
                  ),
                ),
              ),
            ),
          ),
        );
        final button = find.byType(FilledButton);
        final gesture = await tester.startGesture(tester.getCenter(button));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
          reduced ? 1 : .98,
        );
        await gesture.up();
        expect(calls, 1);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Stopping prevents duplicate command and shows pending text', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PowerActionButton(
            stopping: true,
            onPressed: () => calls++,
            label: 'NGẮT NGUỒN NGAY',
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FilledButton));
    expect(calls, 0);
    expect(find.text('Đang ngắt nguồn…'), findsOneWidget);
  });
}
