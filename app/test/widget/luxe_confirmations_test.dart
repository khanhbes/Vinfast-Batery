import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/widgets/luxe_slide_to_confirm.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/features/ai/models/function_call_action.dart';
import 'package:vinfast_battery/features/ai/widgets/action_confirmation_card.dart';
import 'package:vinfast_battery/features/ai/widgets/start_charge_confirmation_sheet.dart';
import 'package:vinfast_battery/features/ai/widgets/stop_charging_confirmation_sheet.dart';

void main() {
  final knob = find.byKey(LuxeSlideToConfirm.knobKey);

  Widget host(Widget child, {double width = 360, double scale = 1}) =>
      MaterialApp(
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: c!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      );

  testWidgets('partial slide springs back; full slide confirms once', (
    tester,
  ) async {
    var confirmed = 0;
    await tester.pumpWidget(
      host(LuxeSlideToConfirm(label: 'Vuốt', onConfirmed: () => confirmed++)),
    );
    await tester.drag(knob, const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(confirmed, 0);
    expect(
      tester.getTopLeft(knob).dx,
      lessThan(tester.getTopLeft(find.byType(LuxeSlideToConfirm)).dx + 10),
    );

    await tester.drag(knob, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(confirmed, 1);
    await tester.drag(knob, const Offset(-600, 0));
    await tester.drag(knob, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(confirmed, 1, reason: 'a completed slide never fires twice');
  });

  testWidgets('locked slider ignores drags and shows the locked label', (
    tester,
  ) async {
    var confirmed = 0;
    await tester.pumpWidget(
      host(
        LuxeSlideToConfirm(
          label: 'Vuốt',
          lockedLabel: 'Khóa',
          enabled: false,
          onConfirmed: () => confirmed++,
        ),
      ),
    );
    expect(find.text('Khóa'), findsOneWidget);
    await tester.drag(knob, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(confirmed, 0);
  });

  testWidgets('screen readers confirm with a semantic tap', (tester) async {
    final handle = tester.ensureSemantics();
    var confirmed = 0;
    await tester.pumpWidget(
      host(
        LuxeSlideToConfirm(
          label: 'Vuốt để sạc',
          onConfirmed: () => confirmed++,
        ),
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('Vuốt để sạc'));
    await tester.pumpAndSettle();
    expect(confirmed, 1);
    handle.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('start sheet needs acknowledgement then a slide ($scale)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await StartChargeConfirmationSheet.show(
                  context,
                  currentSoc: 22,
                  targetSoc: 85,
                  estimatedMinutes: 70,
                  stopTime: '21:40',
                  isAiMode: true,
                  personalizationLabel: 'Điều chỉnh theo thói quen sạc tối',
                );
              },
              child: const Text('open'),
            ),
          ),
          width: 320,
          scale: scale,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('1 giờ 10 phút'), findsOneWidget);
      expect(find.text('21:40'), findsOneWidget);

      await tester.ensureVisible(knob);
      await tester.drag(knob, const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(result, isNull, reason: 'locked until acknowledged');

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.ensureVisible(knob);
      await tester.drag(knob, const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stop sheet returns the chosen reason at text $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      StopChargingDecision? decision;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                decision = await showStopChargingConfirmationSheet(
                  context,
                  currentSoc: 64,
                  targetSoc: 85,
                  remaining: const Duration(minutes: 35),
                  targetMode: true,
                );
              },
              child: const Text('open'),
            ),
          ),
          width: 320,
          scale: scale,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('35 phút'), findsOneWidget);
      // QA 129: the card's time to the target, and the % is an estimate.
      expect(find.text('Còn tới mục tiêu'), findsOneWidget);
      expect(find.text('~64%'), findsOneWidget);
      await tester.ensureVisible(find.text('Pin đã đủ'));
      await tester.tap(find.text('Pin đã đủ'));
      await tester.pump();
      final stop = find.byKey(const ValueKey('stop-charge-confirm'));
      await tester.ensureVisible(stop);
      await tester.tap(stop);
      await tester.pumpAndSettle();
      expect(decision?.reason, UserStopReason.enoughCharge);
    });
  }

  FunctionCallAction action(String tool) => FunctionCallAction(
    callId: 'c1',
    toolName: tool,
    args: const {},
    cardData: const ActionConfirmationCardData(
      title: 'Bật sạc 30 phút',
      description: 'Shelly tự ngắt sau 30 phút.',
    ),
    status: 'pending',
  );

  testWidgets('chat ON proposal needs a slide; other tools keep buttons', (
    tester,
  ) async {
    var confirmed = 0;
    await tester.pumpWidget(
      host(
        ActionConfirmationCard(
          action: action(ActionConfirmationCard.energizingTool),
          onConfirm: () => confirmed++,
          onCancel: () {},
        ),
        width: 320,
      ),
    );
    expect(find.byKey(const Key('action_card_confirm_button')), findsNothing);
    expect(find.byKey(const Key('action_card_cancel_button')), findsOneWidget);
    await tester.tap(knob);
    await tester.pumpAndSettle();
    expect(confirmed, 0, reason: 'a tap never energizes');
    await tester.drag(knob, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(confirmed, 1);

    await tester.pumpWidget(
      host(
        ActionConfirmationCard(
          action: action('stop_charging'),
          onConfirm: () {},
          onCancel: () {},
        ),
        width: 320,
      ),
    );
    expect(find.byKey(const Key('action_card_confirm_button')), findsOneWidget);
    expect(knob, findsNothing);
  });
}
