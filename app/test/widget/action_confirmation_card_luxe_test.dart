import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/models/function_call_action.dart';
import 'package:vinfast_battery/features/ai/widgets/action_confirmation_card.dart';

/// Task 125: LUXE card, 48 dp controls, fits 320 dp at text ×1/×2.
void main() {
  FunctionCallAction action(String tool, {String status = 'pending'}) =>
      FunctionCallAction(
        callId: 'c1',
        toolName: tool,
        args: const {},
        status: status,
        cardData: const ActionConfirmationCardData(
          title: 'Xác nhận bật sạc theo thời gian',
          description: 'VinFast Feliz · Shelly 1',
          estimatedTime: '1 phút',
          safetyNote:
              'Chỉ báo bật thành công sau khi đọc lại thấy ổ đã bật và hẹn giờ đang chạy.',
        ),
      );

  Future<void> pump(
    WidgetTester tester,
    FunctionCallAction value, {
    double scale = 1,
    bool loading = false,
  }) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 900),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: ActionConfirmationCard(
                action: value,
                isLoading: loading,
                onConfirm: () {},
                onCancel: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('pending one-tap card fits 320 dp at x$scale', (tester) async {
      await pump(tester, action('app_update_battery_level'), scale: scale);
      expect(find.text('CHỜ XÁC NHẬN'), findsOneWidget);
      final confirm = tester.getSize(
        find.byKey(const Key('action_card_confirm_button')),
      );
      final cancel = tester.getSize(
        find.byKey(const Key('action_card_cancel_button')),
      );
      expect(confirm.height, greaterThanOrEqualTo(48));
      expect(cancel.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });

    testWidgets('charging card keeps slide-to-confirm at x$scale', (
      tester,
    ) async {
      await pump(tester, action('start_timed_charging'), scale: scale);
      expect(
        find.byKey(const Key('action_card_confirm_slider')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('action_card_confirm_button')), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const Key('action_card_cancel_button')))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('in-flight and failed states read clearly at x$scale', (
      tester,
    ) async {
      await pump(tester, action('stop_charging'), scale: scale, loading: true);
      expect(find.byKey(const Key('action_card_progress')), findsOneWidget);
      await pump(
        tester,
        action('stop_charging', status: 'blocked'),
        scale: scale,
      );
      expect(find.text('CHƯA THỰC HIỆN'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
