import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/constants/app_constants.dart';
import 'package:vinfast_battery/features/ai/models/chat_message.dart';
import 'package:vinfast_battery/features/ai/services/chat_api_service.dart';
import 'package:vinfast_battery/features/ai/services/chat_history_storage.dart';
import 'package:vinfast_battery/features/ai/services/behavior_tracker.dart';
import 'package:vinfast_battery/features/ai/services/suggestion_service.dart';

class _StreamClient extends http.BaseClient {
  _StreamClient(this.events, {this.status = 200});
  final List<String> events;
  final int status;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.fromIterable(events.map(utf8.encode)),
        status,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AppConstants.setCustomApiBaseUrl(null);
  });
  tearDown(() => AppConstants.setCustomApiBaseUrl(null));

  test('SSE error stays an error and settles metadata futures', () async {
    AppConstants.setCustomApiBaseUrl('http://127.0.0.1:5000');
    final service = ChatApiService(
      client: _StreamClient([
        'event: error\ndata: {"message":"private-internal-host"}\n\n',
      ]),
    );
    final response = service.streamChat(message: 'help');
    await expectLater(
      response.stream.toList(),
      throwsA(isA<ChatApiException>()),
    );
    expect(await response.messageIdCompleter.future, isEmpty);
    expect(await response.functionCallCompleter.future, isNull);
  });

  test('EOF without message_end is not successful completion', () async {
    AppConstants.setCustomApiBaseUrl('http://127.0.0.1:5000');
    final response = ChatApiService(
      client: _StreamClient([
        'event: text_delta\ndata: {"delta":"partial"}\n\n',
      ]),
    ).streamChat(message: 'help');
    await expectLater(
      response.stream.toList(),
      throwsA(isA<ChatApiException>()),
    );
  });

  test('HTTP error never reveals response body', () async {
    AppConstants.setCustomApiBaseUrl('http://127.0.0.1:5000');
    final response = ChatApiService(
      client: _StreamClient(['internal-secret'], status: 500),
    ).streamChat(message: 'help');
    await expectLater(
      response.stream.toList(),
      throwsA(
        predicate(
          (Object error) =>
              error is ChatApiException &&
              !error.toString().contains('internal-secret'),
        ),
      ),
    );
  });

  test(
    'offline response preserves session and never manufactures a relay action',
    () async {
      final service = ChatApiService();
      final response = service.streamChat(
        message: 'Bật sạc',
        sessionId: 'local-qa',
      );
      await response.stream.drain<void>();
      expect(await response.sessionIdCompleter.future, 'local-qa');
      expect(await response.functionCallCompleter.future, isNull);
      expect(
        (await service.confirmAction(
          sessionId: 'local-qa',
          callId: 'none',
          toolName: 'start_smart_charging',
          args: {},
          confirmed: true,
        ))['success'],
        isFalse,
      );
    },
  );

  test(
    'history is encrypted-storage and UID scoped, legacy is not inherited',
    () async {
      SharedPreferences.setMockInitialValues({
        'vinfast_chat_sessions_index': '[{"sessionId":"legacy"}]',
      });
      String? uid = 'account-a';
      final storage = ChatHistoryStorage(uidResolver: () => uid);
      await storage.saveSessionMessages('same-session', [
        ChatMessage(
          id: 'm',
          role: ChatRole.user,
          content: 'Private question',
          timestamp: DateTime.now(),
        ),
      ]);
      uid = 'account-b';
      expect(await storage.listSessions(), isEmpty);
      expect(await storage.loadSessionMessages('same-session'), isEmpty);
      uid = 'account-a';
      expect(
        (await storage.loadSessionMessages('same-session')).single.content,
        'Private question',
      );
      expect((await storage.listSessions()).single.id, 'same-session');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((k) => k.startsWith('vinfast_chat_msgs_v2')),
        isEmpty,
      );
    },
  );

  test('behavior and proactive budgets reset for another account', () async {
    final tracker = BehaviorTracker();
    tracker.setIdentity(userId: 'account-a');
    tracker.trackChatInteraction(topic: 'private-topic');
    tracker.setIdentity(userId: 'account-b');
    expect(
      tracker.currentProfile.chatPreferences.topTopics,
      isNot(contains('private-topic')),
    );
    String? uid = 'account-a';
    final suggestions = SuggestionService(uidResolver: () => uid);
    await suggestions.recordSuggestionShown();
    expect(await suggestions.canShowProactiveBubble(), isFalse);
    uid = 'account-b';
    expect(await suggestions.canShowProactiveBubble(), isTrue);
    await suggestions.dismissSuggestion('R001');
    expect(
      await suggestions.fetchSuggestions(userId: 'account-b', currentSoc: 10),
      isEmpty,
    );
    tracker.dispose();
  });
}
