import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';
import '../models/chat_session.dart';
import '../models/function_call_action.dart';

final chatApiServiceProvider = Provider<ChatApiService>((ref) {
  final service = ChatApiService();
  ref.onDispose(service.dispose);
  return service;
});

class ChatApiException implements Exception {
  const ChatApiException(this.code, this.userMessage, {this.httpStatus});
  final String code;
  final String userMessage;
  final int? httpStatus;
  @override
  String toString() => userMessage;
}

class ChatStreamResponse {
  const ChatStreamResponse({
    required this.stream,
    required this.messageIdCompleter,
    required this.sessionIdCompleter,
    required this.functionCallCompleter,
  });

  final Stream<String> stream;
  final Completer<String> messageIdCompleter;
  final Completer<String> sessionIdCompleter;
  final Completer<FunctionCallAction?> functionCallCompleter;
}

class ChatApiService {
  ChatApiService({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 20),
    this.streamIdleTimeout = const Duration(seconds: 30),
    String? Function()? uidResolver,
    Future<String?> Function()? tokenResolver,
  }) : _client = client ?? http.Client(),
       _uidResolver = uidResolver ?? _firebaseUid,
       _tokenResolver = tokenResolver ?? _firebaseToken;
  final Duration requestTimeout;
  final Duration streamIdleTimeout;

  final http.Client _client;
  final String? Function() _uidResolver;
  final Future<String?> Function() _tokenResolver;
  static String? _firebaseUid() =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
  static Future<String?> _firebaseToken() async => Firebase.apps.isEmpty
      ? null
      : FirebaseAuth.instance.currentUser?.getIdToken();
  void dispose() => _client.close();
  void _assertAccount(String? uid) {
    if (uid != _uidResolver()) {
      throw const ChatApiException(
        'accountChanged',
        'Tài khoản đã thay đổi. Hãy mở lại trợ lý.',
      );
    }
  }

  Future<Map<String, String>> _getHeaders({bool isStream = false}) async {
    final uid = _uidResolver();
    final token = await _tokenResolver().timeout(requestTimeout);
    _assertAccount(uid);

    return {
      'Content-Type': 'application/json',
      'Accept': isStream ? 'text/event-stream' : 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Gửi tin nhắn và nhận phản hồi SSE streaming từ BatteryBot.
  ChatStreamResponse streamChat({
    required String message,
    String? sessionId,
    String? userId,
    Map<String, dynamic>? vehicleContext,
    Map<String, dynamic>? behaviorProfile,
    void Function(FunctionCallAction action)? onFunctionCall,
    void Function(Map<String, dynamic> toolCall)? onToolCall,
    void Function(Map<String, dynamic> toolResult)? onToolResult,
    void Function(Map<String, dynamic> cardData)? onRichCard,
    void Function(String text)? onTextReplace,
  }) {
    final messageIdCompleter = Completer<String>();
    final sessionIdCompleter = Completer<String>();
    final functionCallCompleter = Completer<FunctionCallAction?>();
    final ownerUid = _uidResolver();
    bool cancelled = false;
    StreamIterator<String>? input;
    final controller = StreamController<String>(
      onCancel: () async {
        cancelled = true;
        await input?.cancel();
        if (!messageIdCompleter.isCompleted) messageIdCompleter.complete('');
        if (!sessionIdCompleter.isCompleted) {
          sessionIdCompleter.complete(sessionId ?? '');
        }
        if (!functionCallCompleter.isCompleted) {
          functionCallCompleter.complete(null);
        }
      },
    );

    final uri = AppConstants.tryBuildApiUri('/api/chat/send');

    if (uri == null || !AppConstants.isApiConfigured) {
      // Chế độ mô phỏng offline hoặc API chưa được cấu hình URL
      _simulateOfflineStream(
        controller,
        message,
        vehicleContext,
        messageIdCompleter,
        sessionIdCompleter,
        functionCallCompleter,
        onFunctionCall,
        onRichCard,
        sessionId,
      );
      return ChatStreamResponse(
        stream: controller.stream,
        messageIdCompleter: messageIdCompleter,
        sessionIdCompleter: sessionIdCompleter,
        functionCallCompleter: functionCallCompleter,
      );
    }

    () async {
      try {
        final headers = await _getHeaders(
          isStream: true,
        ).timeout(requestTimeout);
        if (cancelled) return;
        _assertAccount(ownerUid);
        final request = http.Request('POST', uri)
          ..headers.addAll(headers)
          ..body = jsonEncode({
            'message': message,
            'sessionId': ?sessionId,
            'vehicleContext': ?vehicleContext,
            'behaviorProfile': ?behaviorProfile,
            'stream': true,
          });

        final streamedResponse = await _client
            .send(request)
            .timeout(requestTimeout);
        if (cancelled) {
          await streamedResponse.stream.listen((_) {}).cancel();
          return;
        }
        if (ownerUid != _uidResolver()) {
          await streamedResponse.stream.listen((_) {}).cancel();
          _assertAccount(ownerUid);
        }

        if (streamedResponse.statusCode != 200) {
          await streamedResponse.stream.listen((_) {}).cancel();
          throw ChatApiException(
            'httpError',
            streamedResponse.statusCode == 401
                ? 'Bạn cần đăng nhập lại để trò chuyện.'
                : streamedResponse.statusCode == 429
                ? 'Bạn gửi hơi nhanh. Hãy thử lại sau.'
                : 'Trợ lý chưa sẵn sàng. Bạn hãy thử lại.',
            httpStatus: streamedResponse.statusCode,
          );
        }
        bool ended = false;
        String event = '';
        final data = <String>[];
        void dispatch() {
          _assertAccount(ownerUid);
          if (data.isEmpty) {
            event = '';
            return;
          }
          final json = jsonDecode(data.join('\n')) as Map<String, dynamic>;
          switch (event) {
            case 'message_start':
              if (!messageIdCompleter.isCompleted) {
                messageIdCompleter.complete(json['messageId'] as String? ?? '');
              }
              if (!sessionIdCompleter.isCompleted) {
                sessionIdCompleter.complete(json['sessionId'] as String? ?? '');
              }
            case 'text_delta':
              controller.add(json['delta'] as String? ?? '');
            case 'text_replace':
              onTextReplace?.call(json['text'] as String? ?? '');
            case 'function_call':
              final action = FunctionCallAction.fromJson(json);
              onFunctionCall?.call(action);
              if (!functionCallCompleter.isCompleted) {
                functionCallCompleter.complete(action);
              }
            case 'tool_call':
              onToolCall?.call(json);
            case 'tool_result':
              onToolResult?.call(json);
            case 'rich_card':
              onRichCard?.call(json);
            case 'error':
              throw const ChatApiException(
                'streamFailed',
                'Trợ lý chưa trả lời được. Bạn hãy thử lại.',
              );
            case 'message_end':
              ended = true;
          }
          data.clear();
          event = '';
        }

        input = StreamIterator(
          streamedResponse.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(streamIdleTimeout),
        );
        final deadline = DateTime.now().add(const Duration(minutes: 2));
        while (!cancelled && await input!.moveNext()) {
          if (DateTime.now().isAfter(deadline)) throw TimeoutException('chat');
          final line = input!.current;
          if (line.isEmpty) {
            dispatch();
            if (ended) break;
          } else if (line.startsWith('event:')) {
            event = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            data.add(line.substring(5).trimLeft());
          }
        }
        if (!cancelled) {
          dispatch();
          if (!ended) {
            throw const ChatApiException(
              'incomplete',
              'Câu trả lời bị gián đoạn. Bạn hãy thử lại.',
            );
          }
        }
      } catch (error) {
        if (!cancelled && !controller.isClosed) {
          controller.addError(
            error is ChatApiException
                ? error
                : error is TimeoutException
                ? const ChatApiException(
                    'timeout',
                    'Trợ lý trả lời quá lâu. Bạn hãy thử lại.',
                  )
                : const ChatApiException(
                    'connectionFailed',
                    'Chưa thể kết nối trợ lý. Bạn hãy thử lại.',
                  ),
          );
        }
      } finally {
        await input?.cancel();
        if (!messageIdCompleter.isCompleted) messageIdCompleter.complete('');
        if (!sessionIdCompleter.isCompleted) {
          sessionIdCompleter.complete(sessionId ?? '');
        }
        if (!functionCallCompleter.isCompleted) {
          functionCallCompleter.complete(null);
        }
        if (!controller.isClosed) unawaited(controller.close());
      }
    }();

    return ChatStreamResponse(
      stream: controller.stream,
      messageIdCompleter: messageIdCompleter,
      sessionIdCompleter: sessionIdCompleter,
      functionCallCompleter: functionCallCompleter,
    );
  }

  void _simulateOfflineStream(
    StreamController<String> controller,
    String message,
    Map<String, dynamic>? ctx,
    Completer<String> msgIdComp,
    Completer<String> sessIdComp,
    Completer<FunctionCallAction?> fnComp,
    void Function(FunctionCallAction action)? onFunctionCall,
    void Function(Map<String, dynamic> cardData)? onRichCard,
    String? existingSessionId,
  ) {
    final mid = 'msg-local-${DateTime.now().millisecondsSinceEpoch}';
    final sid =
        existingSessionId ??
        'session-local-${DateTime.now().microsecondsSinceEpoch}';
    if (!msgIdComp.isCompleted) msgIdComp.complete(mid);
    if (!sessIdComp.isCompleted) sessIdComp.complete(sid);

    final soc = ctx?['currentSoc'] ?? ctx?['soc'];
    final model = ctx?['model'] ?? 'xe';
    final lower = message.toLowerCase();
    final reply =
        (lower.contains('pin') || lower.contains('soc')) &&
            soc is num &&
            soc.isFinite &&
            soc >= 0 &&
            soc <= 100
        ? 'Theo dữ liệu bạn đang xem, pin $model là $soc%. Chưa có kết nối để cập nhật dữ liệu mới.'
        : 'Mình đang ngoại tuyến. Bạn có thể xem pin, lịch sử hoặc kết nối Shelly trong app. Điều khiển cần kết nối máy chủ.';
    if (!fnComp.isCompleted) fnComp.complete(null);
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(reply);
        unawaited(controller.close());
      }
    });
  }

  /// Xác nhận hoặc hủy bỏ một hành động Function Calling (Human-in-the-Loop)
  Future<Map<String, dynamic>> confirmAction({
    required String sessionId,
    required String callId,
    required String toolName,
    required Map<String, dynamic> args,
    required bool confirmed,
  }) async {
    final ownerUid = _uidResolver();
    final uri = AppConstants.tryBuildApiUri('/api/chat/action/confirm');
    if (uri == null || !AppConstants.isApiConfigured) {
      return {
        'success': false,
        'status': 'error',
        'message': 'Điều khiển cần kết nối máy chủ.',
      };
    }

    try {
      final headers = await _getHeaders();
      _assertAccount(ownerUid);
      final res = await _client
          .post(
            uri,
            headers: headers,
            body: jsonEncode({
              'sessionId': sessionId,
              'callId': callId,
              'toolName': toolName,
              'args': args,
              'confirmed': confirmed,
            }),
          )
          .timeout(const Duration(seconds: 15));
      _assertAccount(ownerUid);

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'];
        final success =
            body['success'] == true && data is Map && data['success'] == true;
        return {
          'success': success,
          'data': data,
          'message': success
              ? 'Thao tác đã được xác minh.'
              : confirmed
              ? 'Chưa xác minh được thao tác. Kiểm tra trạng thái trong Sạc pin.'
              : 'Đã hủy yêu cầu.',
        };
      } else {
        return {
          'status': 'error',
          'success': false,
          'message': 'Trợ lý chưa sẵn sàng. Bạn hãy thử lại.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'status': 'error',
        'message':
            'Chưa xác minh được thao tác. Kiểm tra trạng thái trong Sạc pin.',
      };
    }
  }

  /// Lấy danh sách các session
  Future<List<ChatSession>> getSessions() async {
    final ownerUid = _uidResolver();
    final uri = AppConstants.tryBuildApiUri('/api/chat/sessions');
    if (uri == null) return [];
    try {
      final headers = await _getHeaders();
      _assertAccount(ownerUid);
      final res = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      _assertAccount(ownerUid);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        if (body['success'] != true || body['data'] is! List) {
          throw const ChatApiException(
            'historyInvalid',
            'Chưa tải được lịch sử. Hãy thử lại.',
          );
        }
        final list = body['data'] as List<dynamic>;
        return list
            .map((item) => ChatSession.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      throw const ChatApiException(
        'historyUnavailable',
        'Chưa tải được lịch sử. Hãy thử lại.',
      );
    } on ChatApiException {
      rethrow;
    } catch (_) {
      throw const ChatApiException(
        'historyUnavailable',
        'Chưa tải được lịch sử. Hãy thử lại.',
      );
    }
  }

  /// Gửi đánh giá phản hồi (like/dislike)
  Future<bool> sendFeedback({
    required String sessionId,
    required String messageId,
    required String rating,
  }) async {
    final ownerUid = _uidResolver();
    final uri = AppConstants.tryBuildApiUri('/api/chat/feedback');
    if (uri == null) return false;
    try {
      final headers = await _getHeaders();
      _assertAccount(ownerUid);
      final res = await _client
          .post(
            uri,
            headers: headers,
            body: jsonEncode({
              'sessionId': sessionId,
              'messageId': messageId,
              'rating': rating,
            }),
          )
          .timeout(const Duration(seconds: 10));
      _assertAccount(ownerUid);
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body);
      return body is Map &&
          body['success'] == true &&
          body['data'] is Map &&
          body['data']['status'] == 'received' &&
          body['data']['messageId'] == messageId;
    } catch (_) {
      return false;
    }
  }
}
