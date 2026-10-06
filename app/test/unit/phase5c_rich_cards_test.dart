import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinfast_battery/core/constants/app_constants.dart';
import 'package:vinfast_battery/features/ai/models/chat_message.dart';
import 'package:vinfast_battery/features/ai/services/chat_api_service.dart';
import 'package:vinfast_battery/features/ai/widgets/battery_status_card.dart';
import 'package:vinfast_battery/features/ai/widgets/charging_progress_card.dart';
import 'package:vinfast_battery/features/ai/widgets/chat_message_bubble.dart';
import 'package:vinfast_battery/features/ai/widgets/quick_reply_chips.dart';
import 'package:vinfast_battery/features/ai/widgets/trip_summary_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppConstants.setCustomApiBaseUrl(null);
  });

  group('Phase 5C: ChatMessage richCards Model Tests', () {
    test('serializes and deserializes richCards correctly', () {
      final cardData = {
        'cardType': 'battery_status',
        'title': 'Trạng thái Pin',
        'data': {'soc': 85.0, 'voltage': 72.5},
      };

      final msg = ChatMessage(
        id: 'msg-test-1',
        role: ChatRole.model,
        content: 'Pin xe đang ở mức 85%',
        timestamp: DateTime.now(),
        richCards: [cardData],
      );

      final json = msg.toJson();
      expect(json['richCards'], isNotNull);
      expect((json['richCards'] as List).length, equals(1));

      final restored = ChatMessage.fromJson(json);
      expect(restored.richCards, isNotNull);
      expect(restored.richCards!.length, equals(1));
      expect(restored.richCards![0]['cardType'], equals('battery_status'));
      expect(restored.richCards![0]['data']['soc'], equals(85.0));
    });

    test('copyWith updates richCards', () {
      final msg = ChatMessage(
        id: 'msg-test-2',
        role: ChatRole.model,
        content: 'Hello',
        timestamp: DateTime.now(),
      );
      expect(msg.richCards, isNull);

      final updated = msg.copyWith(
        richCards: [
          {'cardType': 'trip_summary', 'title': 'Chuyến đi', 'data': {}},
        ],
      );
      expect(updated.richCards, isNotNull);
      expect(updated.richCards!.length, equals(1));
    });
  });

  group('Phase 5C: Rich Card Widgets Tests', () {
    testWidgets('BatteryStatusCard renders gauges and stats', (tester) async {
      final data = {
        'vehicleId': 'VF-FELIZ-S',
        'soc': 75.0,
        'soh': 98.0,
        'voltage': 72.0,
        'temperature': 28.5,
        'estimatedRangeKm': 85.0,
        'chargingStatus': 'idle',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BatteryStatusCard(data: data)),
        ),
      );

      expect(find.text('Trạng thái Pin & Xe'), findsOneWidget);
      expect(find.text('VF-FELIZ-S'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('~85 km'), findsOneWidget);
      expect(find.text('98%'), findsOneWidget);
      expect(find.text('72.0 V'), findsOneWidget);
      expect(find.text('28.5 °C'), findsOneWidget);
    });

    testWidgets('ChargingProgressCard renders progress and ≤12A safety limit', (
      tester,
    ) async {
      final data = {
        'currentSoc': 40.0,
        'targetSoc': 85.0,
        'chargingPowerW': 1850.0,
        'currentAmps': 8.4,
        'remainingMinutes': 45,
        'status': 'charging',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChargingProgressCard(data: data)),
        ),
      );

      expect(find.text('Tiến độ Sạc Thông Minh'), findsOneWidget);
      expect(find.text('Hiện tại: 40%'), findsOneWidget);
      expect(find.text('Mục tiêu: 85%'), findsOneWidget);
      // Canonical telemetry is W; 1850 W must not be mistaken for 1.85 W.
      expect(find.text('1850 W'), findsOneWidget);
      expect(find.text('8.4 A'), findsOneWidget);
      expect(find.text('~45 phút'), findsOneWidget);
      expect(find.textContaining('≤12A'), findsWidgets);
    });

    testWidgets('TripSummaryCard renders metrics and eco tips', (tester) async {
      final data = {
        'distanceKm': 24.5,
        'energyUsedWh': 735.0,
        'efficiencyWhKm': 30.0,
        'co2SavedKg': 2.1,
        'durationMinutes': 42,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TripSummaryCard(data: data)),
        ),
      );

      expect(find.text('Tóm tắt Chuyến đi & Hiệu suất'), findsOneWidget);
      expect(find.text('24.5 km'), findsOneWidget);
      expect(find.text('735 Wh'), findsOneWidget);
      expect(find.text('30.0 Wh/km'), findsOneWidget);
      expect(find.text('Giảm CO₂'), findsOneWidget);
      expect(find.text('2.1 kg'), findsOneWidget);
      // The compact card splits quantity from its semantic label; full
      // details must still expose the quantity together with its CO₂ unit.
      await tester.tap(find.text('Tóm tắt Chuyến đi & Hiệu suất'));
      await tester.pumpAndSettle();
      expect(find.text('2.10 kg CO₂'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'QuickReplyChips triggers callback on tap and adapts to context',
      (tester) async {
        String? selected;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QuickReplyChips(
                currentSoc: 15.0, // Pin yếu
                onSelect: (text) {
                  selected = text;
                },
              ),
            ),
          ),
        );

        // Pin yếu -> gợi ý sạc ngay
        expect(find.text('⚡ Bật sạc thông minh ngay'), findsOneWidget);
        await tester.tap(find.text('⚡ Bật sạc thông minh ngay'));
        await tester.pump();
        expect(selected, equals('⚡ Bật sạc thông minh ngay'));
      },
    );

    testWidgets('ChatMessageBubble renders rich cards inside bubble', (
      tester,
    ) async {
      final msg = ChatMessage(
        id: 'msg-bubble-test',
        role: ChatRole.model,
        content: 'Dưới đây là thông số pin hiện tại của bạn:',
        timestamp: DateTime.now(),
        richCards: [
          {
            'cardType': 'battery_status',
            'title': 'Trạng thái Pin',
            'data': {
              'vehicleId': 'VF-FELIZ-01',
              'soc': 80.0,
              'soh': 99.0,
              'voltage': 72.0,
              'temperature': 28.0,
              'estimatedRangeKm': 90.0,
            },
          },
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatMessageBubble(message: msg)),
        ),
      );

      expect(
        find.text('Dưới đây là thông số pin hiện tại của bạn:'),
        findsOneWidget,
      );
      expect(find.byType(BatteryStatusCard), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
    });
  });

  group('Phase 5C: ChatApiService onRichCard Integration', () {
    test(
      'offline fallback never fabricates missing rich-card readings',
      () async {
        final apiService = ChatApiService();
        Map<String, dynamic>? receivedCard;

        final res = apiService.streamChat(
          message: 'Pin xe còn bao nhiêu %?',
          vehicleContext: {'soc': 70, 'model': 'VF Feliz S'},
          onRichCard: (card) {
            receivedCard = card;
          },
        );

        await res.stream.drain();
        expect(receivedCard, isNull);
      },
    );
  });
}
