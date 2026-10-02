import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/features/ai/controllers/chat_controller.dart';
import 'package:vinfast_battery/features/ai/models/chat_message.dart';
import 'package:vinfast_battery/features/ai/models/function_call_action.dart';
import 'package:vinfast_battery/features/ai/services/behavior_sync_service.dart';
import 'package:vinfast_battery/features/ai/services/behavior_tracker.dart';
import 'package:vinfast_battery/features/ai/services/chat_api_service.dart';
import 'package:vinfast_battery/features/ai/services/chat_history_storage.dart';
import 'package:vinfast_battery/features/ai/services/voice_input_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4: ChatMessage Offline & Error State Tests', () {
    test('serializes and deserializes isQueued and hasError fields', () {
      final msg = ChatMessage(
        id: 'msg-queued-1',
        role: ChatRole.user,
        content: 'Bật sạc xe khi nào mạng có lại nhé',
        timestamp: DateTime(2026, 10, 2, 17, 30),
        isQueued: true,
        hasError: false,
      );

      final json = msg.toJson();
      expect(json['isQueued'], isTrue);
      expect(json['hasError'], isNull);

      final restored = ChatMessage.fromJson(json);
      expect(restored.isQueued, isTrue);
      expect(restored.hasError, isFalse);

      final errorMsg = restored.copyWith(
        hasError: true,
        errorMessage: 'Mất kết nối máy chủ',
      );
      final errorJson = errorMsg.toJson();
      expect(errorJson['hasError'], isTrue);
      expect(errorJson['errorMessage'], 'Mất kết nối máy chủ');

      final errorRestored = ChatMessage.fromJson(errorJson);
      expect(errorRestored.hasError, isTrue);
      expect(errorRestored.errorMessage, 'Mất kết nối máy chủ');
    });
  });

  group('Phase 4: VoiceInputService Tests', () {
    test('VoiceInputService lifecycle and sound level stream', () async {
      final service = VoiceInputService();

      final initSuccess = await service.initialize();
      expect(initSuccess, isTrue);
      expect(service.isListening, isFalse);

      String? recognizedResult;
      double? receivedLevel;

      final started = await service.startListening(
        localeId: 'vi_VN',
        onResult: (t) => recognizedResult = t,
        onSoundLevel: (lvl) => receivedLevel = lvl,
      );

      expect(started, isTrue);
      expect(service.isListening, isTrue);

      service.updateTranscript('Kiểm tra pin xe Feliz');
      expect(recognizedResult, 'Kiểm tra pin xe Feliz');

      // Đợi ngắn để timer sound level phát
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(receivedLevel, isNotNull);

      final finalTranscript = await service.stopListening();
      expect(finalTranscript, 'Kiểm tra pin xe Feliz');
      expect(service.isListening, isFalse);

      service.dispose();
    });

    test('VoiceInputService cancelListening clears transcript', () async {
      final service = VoiceInputService();
      await service.startListening(
        onResult: (_) {},
      );
      service.updateTranscript('Đang nói dở');
      await service.cancelListening();

      expect(service.isListening, isFalse);
      service.dispose();
    });
  });

  group('Phase 4: ChatHistoryStorage Pagination Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('supports limit and offset pagination', () async {
      final storage = ChatHistoryStorage();

      // Lưu 5 session
      for (int i = 1; i <= 5; i++) {
        await storage.saveSessionMessages(
          'session-00$i',
          [
            ChatMessage(
              id: 'm-$i',
              role: ChatRole.user,
              content: 'Tin nhắn phiên $i',
              timestamp: DateTime.now(),
            ),
          ],
          title: 'Phiên trò chuyện số $i',
        );
      }

      // Lấy trang 1: limit 2, offset 0
      final page1 = await storage.listSessions(limit: 2, offset: 0);
      expect(page1.length, 2);

      // Lấy trang 2: limit 2, offset 2
      final page2 = await storage.listSessions(limit: 2, offset: 2);
      expect(page2.length, 2);
      expect(page2.first.sessionId != page1.first.sessionId, isTrue);

      // Lấy trang 3: limit 2, offset 4
      final page3 = await storage.listSessions(limit: 2, offset: 4);
      expect(page3.length, 1);

      // Offset vượt quá
      final pageEmpty = await storage.listSessions(limit: 2, offset: 10);
      expect(pageEmpty.isEmpty, isTrue);
    });
  });

  group('Phase 4: ChatController Offline Queue & Retry Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('offline queuing: queues messages when offline and drains on processOfflineQueue', () async {
      final apiService = ChatApiService();
      final storage = ChatHistoryStorage();
      final tracker = BehaviorTracker();
      final sync = BehaviorSyncService(tracker: tracker);

      final controller = ChatController(
        apiService: apiService,
        storage: storage,
        behaviorTracker: tracker,
        behaviorSync: sync,
      );

      // Ban đầu có tin nhắn chào mừng
      expect(controller.state.messages.isNotEmpty, isTrue);

      // Giả lập trạng thái offline
      controller.state = controller.state.copyWith(isOnline: false);

      // Gửi tin nhắn khi offline
      await controller.sendMessage(text: 'Sạc đầy cho tôi nhé');

      // Phải có trong offlineQueue
      expect(controller.state.offlineQueue.length, 1);
      expect(controller.state.offlineQueue.first.content, 'Sạc đầy cho tôi nhé');

      // Trong danh sách tin nhắn có thông báo offline
      final lastMsg = controller.state.messages.last;
      expect(lastMsg.content.contains('ngoại tuyến'), isTrue);

      // Giả lập online trở lại và xả hàng đợi
      controller.state = controller.state.copyWith(isOnline: true);
      await controller.processOfflineQueue();

      // Hàng đợi offline được làm rỗng
      expect(controller.state.offlineQueue.isEmpty, isTrue);
    });

    test('confirmAction updates message actionCard status', () async {
      final apiService = ChatApiService();
      final storage = ChatHistoryStorage();
      final tracker = BehaviorTracker();
      final sync = BehaviorSyncService(tracker: tracker);

      final controller = ChatController(
        apiService: apiService,
        storage: storage,
        behaviorTracker: tracker,
        behaviorSync: sync,
      );

      final action = FunctionCallAction(
        callId: 'call-ctrl-1',
        toolName: 'start_smart_charging',
        args: {'target_soc': 80},
        cardData: const ActionConfirmationCardData(
          title: 'Sạc thông minh',
          description: 'Sạc tới 80%',
        ),
      );

      controller.state = controller.state.copyWith(
        messages: [
          ChatMessage(
            id: 'bot-msg-1',
            role: ChatRole.model,
            content: 'Tôi đã tạo lệnh sạc.',
            timestamp: DateTime.now(),
            actionCard: action,
          ),
        ],
      );

      final success = await controller.confirmAction(
        callId: 'call-ctrl-1',
        toolName: 'start_smart_charging',
        args: {'target_soc': 80},
        confirmed: true,
      );

      expect(success, isTrue);
      final updatedMsg = controller.state.messages.first;
      expect(updatedMsg.actionCard?.isConfirmed, isTrue);
      expect(updatedMsg.actionCard?.status, 'confirmed');
    });
  });
}
