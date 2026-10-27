import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/models/chat_message.dart';
import 'package:vinfast_battery/features/ai/models/function_call_action.dart';
import 'package:vinfast_battery/features/ai/widgets/action_confirmation_card.dart';
import 'package:vinfast_battery/features/ai/widgets/breathing_bot_avatar.dart';
import 'package:vinfast_battery/features/ai/widgets/chat_message_bubble.dart';
import 'package:vinfast_battery/features/ai/widgets/typing_indicator_dots.dart';

Widget _wrapWithNarrowViewport({
  required Widget child,
  double width = 320.0,
  double height = 700.0,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      colorSchemeSeed: const Color(0xFF0072BC),
      useMaterial3: true,
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, height: height, child: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [320.0, 390.0, 412.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'Local prediction keeps units/source at $width/$brightness/font1.5',
        (tester) async {
          final message = ChatMessage(
            id: 'prediction',
            role: ChatRole.model,
            content: 'Ước tính thời gian sạc.',
            timestamp: DateTime(2026, 10, 7),
            richCards: [
              {
                'cardType': 'local_prediction',
                'title': 'Thời gian sạc ước tính',
                'data': {
                  'durationSeconds': 1801.0,
                  'source': 'model local',
                  'modelVersion': 'qa-v2',
                  'updatedAt': '2026-10-07T09:00:00',
                },
              },
            ],
          );
          await tester.pumpWidget(
            _wrapWithNarrowViewport(
              width: width,
              brightness: brightness,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: ListView(
                  children: [ChatMessageBubble(message: message)],
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.text('31 phút'), findsOneWidget);
          expect(find.text('Mô hình trên máy · qa-v2'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  group('Chatbot UI/UX 320px Responsive & Overflow Prevention Tests', () {
    testWidgets('User message bubble renders without overflow on 320px', (
      tester,
    ) async {
      final msg = ChatMessage(
        id: 'user_1',
        role: ChatRole.user,
        content:
            'Xin chào Pinova Bot, tôi muốn kiểm tra tình trạng pin xe Feliz hôm nay.',
        timestamp: DateTime(2026, 10, 2, 10, 0),
      );

      await tester.pumpWidget(
        _wrapWithNarrowViewport(
          child: ListView(children: [ChatMessageBubble(message: msg)]),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Xin chào Pinova Bot'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Bot message bubble renders without overflow on 320px', (
      tester,
    ) async {
      final msg = ChatMessage(
        id: 'bot_1',
        role: ChatRole.model,
        content:
            'Chào bạn! Mức pin hiện tại của bạn là 85%, quãng đường còn lại khoảng 95 km. Bạn có cần hỗ trợ bật sạc thông minh không?',
        timestamp: DateTime(2026, 10, 2, 10, 1),
      );

      await tester.pumpWidget(
        _wrapWithNarrowViewport(
          child: ListView(children: [ChatMessageBubble(message: msg)]),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Chào bạn!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'ActionConfirmationCard buttons wrap and fit 320px without overflow',
      (tester) async {
        final action = FunctionCallAction(
          callId: 'call_test_01',
          toolName: 'start_smart_charging',
          args: const {'vehicle_id': 'VF-FELIZ', 'target_soc': 80},
          cardData: const ActionConfirmationCardData(
            title: 'Kích hoạt Sạc Thông Minh 80%',
            description:
                'Hệ thống sẽ bật relay Shelly và tự ngắt khi đạt mốc 80%.',
            safetyNote:
                'Định mức ≤12A / 2500W. Tự động ngắt khi quá nhiệt hoặc mất kết nối.',
            estimatedTime: 'Khoảng 45 phút',
          ),
          status: 'pending',
        );

        await tester.pumpWidget(
          _wrapWithNarrowViewport(
            child: SingleChildScrollView(
              child: ActionConfirmationCard(
                action: action,
                onConfirm: () {},
                onCancel: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('XÁC NHẬN'), findsOneWidget);
        expect(find.text('HỦY'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('TypingIndicatorDots animates smoothly without exception', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithNarrowViewport(
          child: const Center(child: TypingIndicatorDots()),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('BreathingBotAvatar mounts and breathes without exception', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithNarrowViewport(
          child: const Center(child: BreathingBotAvatar(isStreaming: true)),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Complete Dark Mode rendering of all cards without overflow or crash',
      (tester) async {
        final msgWithCard = ChatMessage(
          id: 'bot_2',
          role: ChatRole.model,
          content: 'Dưới đây là thông số xe của bạn:',
          timestamp: DateTime(2026, 10, 2, 10, 2),
          richCards: const [
            {
              'cardType': 'battery_status',
              'data': {
                'soc': 70.0,
                'soh': 98.0,
                'voltage': 71.8,
                'temperature': 30.0,
                'estimatedRangeKm': 75.0,
                'chargingStatus': 'idle',
                'vehicleId': 'VF-EVO-200',
              },
            },
            {
              'cardType': 'charging_progress',
              'data': {
                'currentSoc': 70.0,
                'targetSoc': 85.0,
                'chargingPowerW': 1800.0,
                'currentAmps': 8.0,
                'remainingMinutes': 30,
                'status': 'charging',
              },
            },
          ],
        );

        await tester.pumpWidget(
          _wrapWithNarrowViewport(
            brightness: Brightness.dark,
            child: ListView(
              children: [ChatMessageBubble(message: msgWithCard)],
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // QA 139: the bot no longer sends these card types; they render
        // nothing (no crash), the message text stays.
        expect(find.text('70%'), findsNothing);
        expect(find.text('Dưới đây là thông số xe của bạn:'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
