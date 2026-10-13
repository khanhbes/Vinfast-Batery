import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/features/ai/models/chat_message.dart';
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
    test(
      'voice without a native adapter does not simulate recognition',
      () async {
        final service = VoiceInputService();

        final initSuccess = await service.initialize();
        expect(initSuccess, isFalse);
        expect(VoiceInputService.isSupported, isFalse);
        expect(await service.requestMicrophonePermission(), isFalse);
        expect(service.isListening, isFalse);

        String? recognizedResult;
        double? receivedLevel;

        final started = await service.startListening(
          localeId: 'vi_VN',
          onResult: (t) => recognizedResult = t,
          onSoundLevel: (lvl) => receivedLevel = lvl,
        );

        expect(started, isFalse);
        expect(service.isListening, isFalse);

        service.updateTranscript('Kiểm tra pin xe Feliz');
        expect(recognizedResult, isNull);

        // There must be no random waveform or fabricated transcript.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(receivedLevel, isNull);

        final finalTranscript = await service.stopListening();
        expect(finalTranscript, isEmpty);
        expect(service.isListening, isFalse);

        service.dispose();
      },
    );

    test('VoiceInputService cancelListening clears transcript', () async {
      final service = VoiceInputService();
      await service.startListening(onResult: (_) {});
      service.updateTranscript('Đang nói dở');
      await service.cancelListening();

      expect(service.isListening, isFalse);
      service.dispose();
    });
  });

  group('Phase 4: ChatHistoryStorage Pagination Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('supports limit and offset pagination', () async {
      final storage = ChatHistoryStorage();

      // Lưu 5 session
      for (int i = 1; i <= 5; i++) {
        await storage.saveSessionMessages('session-00$i', [
          ChatMessage(
            id: 'm-$i',
            role: ChatRole.user,
            content: 'Tin nhắn phiên $i',
            timestamp: DateTime.now(),
          ),
        ], title: 'Phiên trò chuyện số $i');
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
}
