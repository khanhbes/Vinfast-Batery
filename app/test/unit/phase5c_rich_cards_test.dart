import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinfast_battery/core/constants/app_constants.dart';
import 'package:vinfast_battery/features/ai/models/chat_message.dart';
import 'package:vinfast_battery/features/ai/services/chat_api_service.dart';
import 'package:vinfast_battery/features/ai/widgets/chat_message_bubble.dart';
import 'package:vinfast_battery/features/ai/widgets/quick_reply_chips.dart';

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
        expect(find.text('Bật sạc hẹn giờ'), findsOneWidget);
        await tester.tap(find.text('Bật sạc hẹn giờ'));
        await tester.pump();
        expect(selected, equals('Bật sạc hẹn giờ'));
      },
    );

    testWidgets('ChatMessageBubble skips retired rich cards', (tester) async {
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
      // QA 139: a retired card type renders nothing, the text stays.
      expect(find.text('80%'), findsNothing);
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
