import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vinfast_battery/core/constants/app_constants.dart';
import 'package:vinfast_battery/features/ai/models/chat_message.dart';
import 'package:vinfast_battery/features/ai/models/chat_session.dart';
import 'package:vinfast_battery/features/ai/services/chat_api_service.dart';

void main() {
  group('ChatMessage model tests', () {
    test('serializes and deserializes user message correctly', () {
      final now = DateTime(2026, 10, 2, 12, 0);
      final msg = ChatMessage(
        id: 'msg-001',
        role: ChatRole.user,
        content: 'Pin xe của tôi còn bao nhiêu?',
        timestamp: now,
      );

      expect(msg.fromBot, isFalse);
      final json = msg.toJson();
      expect(json['id'], 'msg-001');
      expect(json['role'], 'user');
      expect(json['content'], 'Pin xe của tôi còn bao nhiêu?');

      final fromJson = ChatMessage.fromJson(json);
      expect(fromJson.id, msg.id);
      expect(fromJson.role, ChatRole.user);
      expect(fromJson.content, msg.content);
    });

    test('serializes bot message with feedback and action', () {
      final now = DateTime(2026, 10, 2, 12, 5);
      final msg = ChatMessage(
        id: 'msg-002',
        role: ChatRole.model,
        content: 'Pin của bạn còn 85%.',
        timestamp: now,
        action: 'guideCharging',
        userFeedback: 'like',
      );

      expect(msg.fromBot, isTrue);
      final json = msg.toJson();
      expect(json['role'], 'model');
      expect(json['action'], 'guideCharging');
      expect(json['userFeedback'], 'like');

      final copy = msg.copyWith(userFeedback: 'dislike');
      expect(copy.userFeedback, 'dislike');
      expect(copy.action, 'guideCharging');
    });
  });

  group('ChatSession model tests', () {
    test('serializes and deserializes ChatSession', () {
      final now = DateTime(2026, 10, 2, 12, 0);
      final session = ChatSession(
        sessionId: 'sess-123',
        title: 'Tư vấn pin Feliz S',
        createdAt: now,
        updatedAt: now,
        messageCount: 4,
        lastMessage: 'Bạn có thể sạc thêm khoảng 30 phút.',
      );

      final json = session.toJson();
      expect(json['sessionId'], 'sess-123');
      expect(json['title'], 'Tư vấn pin Feliz S');
      expect(json['messageCount'], 4);

      final fromJson = ChatSession.fromJson(json);
      expect(fromJson.sessionId, session.sessionId);
      expect(fromJson.title, session.title);
      expect(fromJson.messageCount, 4);
    });
  });

  group('ChatApiService offline simulation tests', () {
    test('streamChat produces offline fallback stream when API unconfigured', () async {
      final service = ChatApiService();
      final streamResponse = service.streamChat(
        message: 'Pin của tôi còn bao nhiêu?',
        vehicleContext: {'model': 'Feliz S', 'currentSoc': 70},
      );

      final chunks = <String>[];
      await for (final chunk in streamResponse.stream) {
        chunks.add(chunk);
      }

      final fullResponse = chunks.join('');
      expect(fullResponse, contains('Feliz S'));
      expect(fullResponse, contains('70%'));
    });

    test('streamChat handles tool_call and tool_result SSE events', () async {
      AppConstants.setCustomApiBaseUrl('http://127.0.0.1:5000');
      try {
        final mockClient = _MockStreamClient([
          'event: message_start\ndata: {"messageId":"m1","sessionId":"s1"}\n\n',
          'event: tool_call\ndata: {"callId":"c1","toolName":"get_battery_status","status":"executing"}\n\n',
          'event: tool_result\ndata: {"callId":"c1","toolName":"get_battery_status","result":{"soc":80.0}}\n\n',
          'event: text_delta\ndata: {"delta":"Pin còn 80%"}\n\n',
          'event: message_end\ndata: {"messageId":"m1"}\n\n',
        ]);
        final service = ChatApiService(client: mockClient);
        Map<String, dynamic>? receivedToolCall;
        Map<String, dynamic>? receivedToolResult;

        final res = service.streamChat(
          message: 'Pin thế nào?',
          onToolCall: (tc) => receivedToolCall = tc,
          onToolResult: (tr) => receivedToolResult = tr,
        );

        final chunks = await res.stream.toList();
        expect(chunks.join(''), 'Pin còn 80%');
        expect(receivedToolCall?['toolName'], 'get_battery_status');
        expect(receivedToolCall?['status'], 'executing');
        expect(receivedToolResult?['toolName'], 'get_battery_status');
        expect(receivedToolResult?['result']?['soc'], 80.0);
      } finally {
        AppConstants.setCustomApiBaseUrl(null);
      }
    });
  });
}

class _MockStreamClient extends http.BaseClient {
  _MockStreamClient(this.chunks);
  final List<String> chunks;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stream = Stream<List<int>>.fromIterable(
      chunks.map((c) => utf8.encode(c)),
    );
    return http.StreamedResponse(stream, 200);
  }
}
