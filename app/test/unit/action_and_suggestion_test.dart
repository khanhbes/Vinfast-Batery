import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/features/ai/models/chat_message.dart';
import 'package:vinfast_battery/features/ai/models/function_call_action.dart';
import 'package:vinfast_battery/features/ai/models/proactive_suggestion.dart';
import 'package:vinfast_battery/features/ai/services/suggestion_service.dart';
import 'package:vinfast_battery/features/ai/services/chat_api_service.dart';

void main() {
  group('FunctionCallAction and ActionConfirmationCardData Tests', () {
    test('ActionConfirmationCardData serialization roundtrip', () {
      final card = ActionConfirmationCardData(
        title: 'Bắt đầu sạc thông minh',
        description: 'Bật sạc xe Feliz với mục tiêu 85%',
        estimatedTime: '2 giờ 15 phút',
        safetyNote: 'Dòng sạc tối đa 10A (≤ 12A an toàn)',
        targetSoc: 85,
        maxAmps: 10.0,
      );

      final json = card.toJson();
      expect(json['title'], 'Bắt đầu sạc thông minh');
      expect(json['targetSoc'], 85);
      expect(json['maxAmps'], 10.0);

      final decoded = ActionConfirmationCardData.fromJson(json);
      expect(decoded.title, card.title);
      expect(decoded.description, card.description);
      expect(decoded.estimatedTime, card.estimatedTime);
      expect(decoded.safetyNote, card.safetyNote);
      expect(decoded.targetSoc, 85);
      expect(decoded.maxAmps, 10.0);
    });

    test('FunctionCallAction serialization and status helpers', () {
      final action = FunctionCallAction(
        callId: 'call-12345',
        toolName: 'start_smart_charging',
        args: {'target_soc': 80, 'max_amps': 10.0},
        requiresConfirmation: true,
        cardData: const ActionConfirmationCardData(
          title: 'Bắt đầu sạc',
          description: 'Sạc tới 80%',
        ),
      );

      expect(action.isPending, isTrue);
      expect(action.isConfirmed, isFalse);
      expect(action.isCancelled, isFalse);

      final json = action.toJson();
      expect(json['callId'], 'call-12345');
      expect(json['toolName'], 'start_smart_charging');
      expect(json['status'], 'pending');

      final fromJson = FunctionCallAction.fromJson(json);
      expect(fromJson.callId, 'call-12345');
      expect(fromJson.toolName, 'start_smart_charging');
      expect(fromJson.cardData?.title, 'Bắt đầu sạc');

      final confirmed = action.copyWith(
        status: 'confirmed',
        resultMessage: 'Đã bật sạc thành công',
      );
      expect(confirmed.isConfirmed, isTrue);
      expect(confirmed.isPending, isFalse);
      expect(confirmed.resultMessage, 'Đã bật sạc thành công');

      final cancelled = action.copyWith(status: 'cancelled');
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.isPending, isFalse);
    });

    test('ChatMessage includes actionCard in JSON serialization', () {
      final action = FunctionCallAction(
        callId: 'call-msg-99',
        toolName: 'schedule_charging',
        args: {'start_time': '23:00', 'target_soc': 90},
        requiresConfirmation: true,
        cardData: const ActionConfirmationCardData(
          title: 'Hẹn giờ sạc đêm',
          description: 'Bắt đầu lúc 23:00',
        ),
      );

      final message = ChatMessage(
        id: 'msg-with-action',
        role: ChatRole.model,
        content: 'Tôi đã tạo lịch sạc cho bạn.',
        timestamp: DateTime(2026, 10, 2, 22, 0),
        actionCard: action,
      );

      final json = message.toJson();
      expect(json.containsKey('actionCard'), isTrue);
      expect(json['actionCard']['callId'], 'call-msg-99');

      final restored = ChatMessage.fromJson(json);
      expect(restored.actionCard, isNotNull);
      expect(restored.actionCard?.callId, 'call-msg-99');
      expect(restored.actionCard?.toolName, 'schedule_charging');
      expect(restored.actionCard?.cardData?.title, 'Hẹn giờ sạc đêm');
    });
  });

  group('ProactiveSuggestion Model Tests', () {
    test('ProactiveSuggestion serialization roundtrip', () {
      final suggestion = ProactiveSuggestion(
        ruleId: 'R001',
        title: 'Mức pin thấp',
        message: 'Pin chỉ còn 15%. Vui lòng cắm sạc sớm.',
        priority: 'HIGH',
        action: 'start_smart_charging',
        suggestedAt: DateTime.now(),
        metadata: {'currentSoc': 15},
      );

      final json = suggestion.toJson();
      expect(json['ruleId'], 'R001');
      expect(json['priority'], 'HIGH');

      final decoded = ProactiveSuggestion.fromJson(json);
      expect(decoded.ruleId, 'R001');
      expect(decoded.title, 'Mức pin thấp');
      expect(decoded.action, 'start_smart_charging');
      expect(decoded.priority, 'HIGH');
    });
  });

  group('SuggestionService Rate Limiting & Dismiss Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('canShowProactiveBubble allows first show and blocks within 30 minutes', () async {
      final service = SuggestionService();

      // First time: allowed
      final canShow1 = await service.canShowProactiveBubble();
      expect(canShow1, isTrue);

      // Record shown
      await service.recordSuggestionShown();

      // Immediately checking again: blocked by 30-min window
      final canShow2 = await service.canShowProactiveBubble();
      expect(canShow2, isFalse);
    });

    test('dismissSuggestion stores timestamp and filters out rules', () async {
      final service = SuggestionService();
      await service.dismissSuggestion('R001');

      final prefs = await SharedPreferences.getInstance();
      final dismissedRaw = prefs.getString('vinfast_dismissed_suggestions_v1');
      expect(dismissedRaw, isNotNull);
      expect(dismissedRaw!.contains('R001'), isTrue);
    });

    test('generateLocalFallback returns R001 when battery < 20%', () async {
      final service = SuggestionService();
      final suggestions = await service.fetchSuggestions(
        userId: 'test_user',
        currentSoc: 14.0,
      );

      expect(suggestions.isNotEmpty, isTrue);
      expect(suggestions.first.ruleId, 'R001');
      expect(suggestions.first.priority, 'HIGH');
    });
  });

  group('ChatApiService Action Confirmation Tests', () {
    test('confirmAction handles simulated confirmed and cancelled execution', () async {
      final service = ChatApiService();

      final resConfirmed = await service.confirmAction(
        sessionId: 'test-session',
        callId: 'call-abc',
        toolName: 'start_smart_charging',
        args: {'target_soc': 80},
        confirmed: true,
      );

      expect(resConfirmed['status'], 'success');
      final dataConf = resConfirmed['data'] as Map<String, dynamic>;
      expect(dataConf['status'], 'confirmed');
      expect(dataConf['executed'], isTrue);

      final resCancelled = await service.confirmAction(
        sessionId: 'test-session',
        callId: 'call-abc',
        toolName: 'start_smart_charging',
        args: {'target_soc': 80},
        confirmed: false,
      );

      expect(resCancelled['status'], 'success');
      final dataCanc = resCancelled['data'] as Map<String, dynamic>;
      expect(dataCanc['status'], 'cancelled');
      expect(dataCanc['executed'], isFalse);
    });
  });
}
