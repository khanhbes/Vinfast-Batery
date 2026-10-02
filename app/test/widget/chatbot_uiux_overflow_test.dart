import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/models/chat_message.dart';
import 'package:vinfast_battery/features/ai/models/function_call_action.dart';
import 'package:vinfast_battery/features/ai/widgets/action_confirmation_card.dart';
import 'package:vinfast_battery/features/ai/widgets/battery_status_card.dart';
import 'package:vinfast_battery/features/ai/widgets/breathing_bot_avatar.dart';
import 'package:vinfast_battery/features/ai/widgets/chat_input_bar.dart';
import 'package:vinfast_battery/features/ai/widgets/chat_message_bubble.dart';
import 'package:vinfast_battery/features/ai/widgets/charging_progress_card.dart';
import 'package:vinfast_battery/features/ai/widgets/trip_summary_card.dart';
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
        child: SizedBox(
          width: width,
          height: height,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Chatbot UI/UX 320px Responsive & Overflow Prevention Tests', () {
    testWidgets('User message bubble renders without overflow on 320px', (tester) async {
      final msg = ChatMessage(
        id: 'user_1',
        role: ChatRole.user,
        content: 'Xin chào BatteryBot, tôi muốn kiểm tra tình trạng pin xe Feliz hôm nay.',
        timestamp: DateTime(2026, 10, 2, 10, 0),
      );

      await tester.pumpWidget(
        _wrapWithNarrowViewport(
          child: ListView(
            children: [
              ChatMessageBubble(message: msg),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Xin chào BatteryBot'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Bot message bubble renders without overflow on 320px', (tester) async {
      final msg = ChatMessage(
        id: 'bot_1',
        role: ChatRole.model,
        content: 'Chào bạn! Mức pin hiện tại của bạn là 85%, quãng đường còn lại khoảng 95 km. Bạn có cần hỗ trợ bật sạc thông minh không?',
        timestamp: DateTime(2026, 10, 2, 10, 1),
      );

      await tester.pumpWidget(
        _wrapWithNarrowViewport(
          child: ListView(
            children: [
              ChatMessageBubble(message: msg),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Chào bạn!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('BatteryStatusCard renders without overflow on 320px', (tester) async {
      final data = {
        'soc': 82.0,
        'soh': 97.5,
        'voltage': 72.4,
        'temperature': 29.0,
        'estimatedRangeKm': 88.0,
        'chargingStatus': 'charging',
        'vehicleId': 'VF-FELIZ-001',
      };

      await tester.pumpWidget(
        _wrapWithNarrowViewport(
          child: SingleChildScrollView(
            child: BatteryStatusCard(data: data),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('82%'), findsOneWidget);
      expect(find.text('VF-FELIZ-001'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChargingProgressCard safety footer and metrics fit 320px without overflow', (tester) async {
      final data = {
        'currentSoc': 45.0,
        'targetSoc': 80.0,
        'chargingPowerW': 2100.0,
        'currentAmps': 9.2,
        'remainingMinutes': 48,
        'status': 'charging',
      };

      await tester.pumpWidget(
        _wrapWithNarrowViewport(
          child: SingleChildScrollView(
            child: ChargingProgressCard(data: data),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('An toàn phần cứng'), findsOneWidget);
      expect(find.text('2100 W'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });


    testWidgets('TripSummaryCard metrics and eco tips fit 320px without overflow', (tester) async {
      final data = {
        'distanceKm': 28.6,
        'energyUsedWh': 850.0,
        'efficiencyWhKm': 29.7,
        'co2SavedKg': 2.45,
        'durationMinutes': 50,
      };

      await tester.pumpWidget(
        _wrapWithNarrowViewport(
          child: SingleChildScrollView(
            child: TripSummaryCard(data: data),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('28.6 km'), findsOneWidget);
      expect(find.textContaining('Phong cách lái xe rất mượt mà'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ActionConfirmationCard buttons wrap and fit 320px without overflow', (tester) async {
      final action = FunctionCallAction(
        callId: 'call_test_01',
        toolName: 'start_smart_charging',
        args: const {'vehicle_id': 'VF-FELIZ', 'target_soc': 80},
        cardData: const ActionConfirmationCardData(
          title: 'Kích hoạt Sạc Thông Minh 80%',
          description: 'Hệ thống sẽ bật relay Shelly và tự ngắt khi đạt mốc 80%.',
          safetyNote: 'Định mức ≤12A / 2500W. Tự động ngắt khi quá nhiệt hoặc mất kết nối.',
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

      expect(find.text('XÁC NHẬN SẠC'), findsOneWidget);
      expect(find.text('HỦY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TypingIndicatorDots animates smoothly without exception', (tester) async {
      await tester.pumpWidget(
        _wrapWithNarrowViewport(
          child: const Center(
            child: TypingIndicatorDots(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('BreathingBotAvatar mounts and breathes without exception', (tester) async {
      await tester.pumpWidget(
        _wrapWithNarrowViewport(
          child: const Center(
            child: BreathingBotAvatar(isStreaming: true),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChatInputBar renders at 320px width without overflow', (tester) async {
      await tester.pumpWidget(
        _wrapWithNarrowViewport(
          child: ChatInputBar(
            onSend: (_) {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Complete Dark Mode rendering of all cards without overflow or crash', (tester) async {
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
            children: [
              ChatMessageBubble(message: msgWithCard),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('70%'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
