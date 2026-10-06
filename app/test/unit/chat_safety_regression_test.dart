import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

class _ByteStreamClient extends http.BaseClient {
  _ByteStreamClient(this.bytes);
  final Stream<List<int>> bytes;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(bytes, 200);
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

  test(
    'feedback requires semantic acknowledgment, not only HTTP 200',
    () async {
      AppConstants.setCustomApiBaseUrl('http://127.0.0.1:5000');
      for (final body in [
        '{"success":false}',
        '{}',
        'malformed',
        '{"success":true,"data":{"status":"received","messageId":"other"}}',
      ]) {
        final service = ChatApiService(
          client: MockClient((_) async => http.Response(body, 200)),
        );
        expect(
          await service.sendFeedback(
            sessionId: 'qa',
            messageId: 'm',
            rating: 'like',
          ),
          isFalse,
        );
        service.dispose();
      }
      final service = ChatApiService(
        client: MockClient(
          (_) async => http.Response(
            '{"success":true,"data":{"status":"received","messageId":"m"}}',
            200,
          ),
        ),
      );
      expect(
        await service.sendFeedback(
          sessionId: 'qa',
          messageId: 'm',
          rating: 'like',
        ),
        isTrue,
      );
      service.dispose();
    },
  );

  test(
    'account switch while waiting for token sends no old-account request',
    () async {
      AppConstants.setCustomApiBaseUrl('http://127.0.0.1:5000');
      String? uid = 'qa-a';
      final token = Completer<String?>();
      var requests = 0;
      final service = ChatApiService(
        uidResolver: () => uid,
        tokenResolver: () => token.future,
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      final result = service.sendFeedback(
        sessionId: 'qa-a-session',
        messageId: 'm',
        rating: 'like',
      );
      uid = 'qa-b';
      token.complete('fake-token');
      expect(await result, isFalse);
      expect(requests, 0);
      service.dispose();
    },
  );

  test('server history failure does not become empty history', () async {
    AppConstants.setCustomApiBaseUrl('http://127.0.0.1:5000');
    final service = ChatApiService(
      client: MockClient((_) async => http.Response('{"success":false}', 200)),
    );
    await expectLater(service.getSessions(), throwsA(isA<ChatApiException>()));
    service.dispose();
  });

  test(
    'SSE parses Vietnamese UTF-8 split at every byte and multiline data',
    () async {
      AppConstants.setCustomApiBaseUrl('http://127.0.0.1:5000');
      final events =
          ': heartbeat\r\nevent: message_start\r\ndata: {"messageId":"m",\r\ndata: "sessionId":"s"}\r\n\r\n'
          'event: text_delta\ndata: {"delta":"Chào bạn, pin 0%"}\n\n'
          'event: message_end\ndata: {}\n\n';
      final service = ChatApiService(
        client: _ByteStreamClient(
          Stream.fromIterable(utf8.encode(events).map((byte) => [byte])),
        ),
      );
      final response = service.streamChat(message: 'QA');
      expect((await response.stream.toList()).join(), 'Chào bạn, pin 0%');
      expect(await response.messageIdCompleter.future, 'm');
      expect(await response.sessionIdCompleter.future, 's');
      service.dispose();
    },
  );

  test(
    'hung token acquisition is bounded before any network request',
    () async {
      AppConstants.setCustomApiBaseUrl('http://127.0.0.1:5000');
      var requests = 0;
      final service = ChatApiService(
        requestTimeout: const Duration(milliseconds: 20),
        tokenResolver: () => Completer<String?>().future,
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      expect(
        await service.sendFeedback(
          sessionId: 's',
          messageId: 'm',
          rating: 'like',
        ),
        isFalse,
      );
      expect(requests, 0);
      service.dispose();
    },
  );

  test(
    'account change during SSE discards remaining text and fails closed',
    () async {
      AppConstants.setCustomApiBaseUrl('http://127.0.0.1:5000');
      String? uid = 'qa-a';
      final input = StreamController<List<int>>();
      final service = ChatApiService(
        uidResolver: () => uid,
        client: _ByteStreamClient(input.stream),
      );
      final response = service.streamChat(message: 'QA');
      final result = expectLater(
        response.stream.toList(),
        throwsA(isA<ChatApiException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      uid = 'qa-b';
      input.add(
        utf8.encode(
          'event: text_delta\ndata: {"delta":"private account-a"}\n\n',
        ),
      );
      await result;
      await input.close();
      service.dispose();
    },
  );

  test('local vote replacement does not inflate feedback statistics', () {
    final tracker = BehaviorTracker();
    tracker.setIdentity(userId: 'qa');
    tracker.replaceChatFeedback(rating: 'up');
    tracker.replaceChatFeedback(previous: 'up', rating: 'like');
    tracker.replaceChatFeedback(previous: 'like', rating: 'down');
    final stats = tracker.currentProfile.chatPreferences.feedbackStats;
    expect(stats['totalThumbsUp'], 0);
    expect(stats['totalThumbsDown'], 1);
    tracker.dispose();
  });

  test(
    'corrupt local history is an error and is not silently erased',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'vinfast_chat_sessions_index_v2_qa': 'broken',
      });
      final storage = ChatHistoryStorage(uidResolver: () => 'qa');
      await expectLater(
        storage.listSessions(),
        throwsA(isA<ChatHistoryException>()),
      );
      await expectLater(
        storage.deleteSession('m'),
        throwsA(isA<ChatHistoryException>()),
      );
      expect(
        await const FlutterSecureStorage().read(
          key: 'vinfast_chat_sessions_index_v2_qa',
        ),
        'broken',
      );
      storage.dispose();
    },
  );
}
