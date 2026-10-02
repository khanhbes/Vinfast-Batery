import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';
import '../models/chat_session.dart';
import '../models/function_call_action.dart';

final chatApiServiceProvider = Provider<ChatApiService>((ref) {
  return ChatApiService();
});

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
  ChatApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, String>> _getHeaders({bool isStream = false}) async {
    String? token;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        token = await user.getIdToken();
      }
    } catch (_) {}

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
  }) {
    final messageIdCompleter = Completer<String>();
    final sessionIdCompleter = Completer<String>();
    final functionCallCompleter = Completer<FunctionCallAction?>();
    final controller = StreamController<String>();

    final uri =
        AppConstants.tryBuildApiUri('/api/chat/send') ??
        Uri.tryParse('${AppConstants.apiBaseUrl}/api/chat/send');

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
        final headers = await _getHeaders(isStream: true);
        final request = http.Request('POST', uri)
          ..headers.addAll(headers)
          ..body = jsonEncode({
            'message': message,
            'sessionId': ?sessionId,
            'userId': ?userId,
            'vehicleContext': ?vehicleContext,
            'behaviorProfile': ?behaviorProfile,
            'stream': true,
          });

        final streamedResponse = await _client
            .send(request)
            .timeout(const Duration(seconds: 45));

        if (streamedResponse.statusCode != 200) {
          final errorBody = await streamedResponse.stream.bytesToString();
          controller.addError(
            'Lỗi kết nối máy chủ (${streamedResponse.statusCode}): $errorBody',
          );
          await controller.close();
          if (!messageIdCompleter.isCompleted) messageIdCompleter.complete('');
          if (!sessionIdCompleter.isCompleted) sessionIdCompleter.complete('');
          if (!functionCallCompleter.isCompleted)
            functionCallCompleter.complete(null);
          return;
        }

        String currentEvent = '';
        final lines = streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        await for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          if (trimmed.startsWith('event:')) {
            currentEvent = trimmed.substring(6).trim();
          } else if (trimmed.startsWith('data:')) {
            final dataStr = trimmed.substring(5).trim();
            try {
              final json = jsonDecode(dataStr) as Map<String, dynamic>;

              if (currentEvent == 'message_start') {
                final mid = json['messageId'] as String? ?? '';
                final sid = json['sessionId'] as String? ?? '';
                if (!messageIdCompleter.isCompleted)
                  messageIdCompleter.complete(mid);
                if (!sessionIdCompleter.isCompleted)
                  sessionIdCompleter.complete(sid);
              } else if (currentEvent == 'text_delta') {
                final delta = json['delta'] as String? ?? '';
                if (delta.isNotEmpty) {
                  controller.add(delta);
                }
              } else if (currentEvent == 'function_call') {
                final action = FunctionCallAction.fromJson(json);
                onFunctionCall?.call(action);
                if (!functionCallCompleter.isCompleted) {
                  functionCallCompleter.complete(action);
                }
              } else if (currentEvent == 'message_end') {
                // Kết thúc hội thoại
              }
            } catch (_) {
              // Bỏ qua dòng json không parse được
            }
          }
        }

        if (!functionCallCompleter.isCompleted) {
          functionCallCompleter.complete(null);
        }
        await controller.close();
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError('Không thể kết nối trợ lý AI: $e');
          await controller.close();
        }
        if (!messageIdCompleter.isCompleted) messageIdCompleter.complete('');
        if (!sessionIdCompleter.isCompleted) sessionIdCompleter.complete('');
        if (!functionCallCompleter.isCompleted)
          functionCallCompleter.complete(null);
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
  ) {
    final mid = 'msg-local-${DateTime.now().millisecondsSinceEpoch}';
    final sid = 'session-local';
    if (!msgIdComp.isCompleted) msgIdComp.complete(mid);
    if (!sessIdComp.isCompleted) sessIdComp.complete(sid);

    final soc = ctx?['currentSoc'] ?? ctx?['soc'] ?? 75;
    final model = ctx?['model'] ?? 'xe VinFast';

    String reply;
    final lower = message.toLowerCase();
    FunctionCallAction? triggeredAction;

    if (lower.contains('pin') || lower.contains('soc')) {
      reply =
          'Hiện tại pin chiếc **$model** của bạn đang ở mức **$soc%**.\n\n'
          '- Quãng đường ước tính di chuyển còn lại: **~${(soc * 1.8).round()} km**.\n'
          '- Để pin LFP bền bỉ, bạn nên sạc khi mức pin dưới 20% nhé! 🔋';
    } else if (lower.contains('sạc') &&
        (lower.contains('bật') || lower.contains('bắt đầu'))) {
      reply =
          'Tôi đã chuẩn bị lệnh sạc thông minh cho xe **$model** với mục tiêu pin 80% (tối đa 10A / 2200W).\n\n'
          'Vui lòng xác nhận hành động bên dưới để bắt đầu sạc an toàn:';
      triggeredAction = FunctionCallAction(
        callId: 'call-${DateTime.now().millisecondsSinceEpoch}',
        toolName: 'start_smart_charging',
        args: {'target_soc': 80, 'max_amps': 10.0},
        requiresConfirmation: true,
        cardData: const ActionConfirmationCardData(
          title: 'Bắt đầu sạc thông minh',
          description:
              'Cắm sạc qua Shelly Plug S Gen3. Mục tiêu: 80% SoC, dòng sạc tối đa: 10A.',
          safetyNote: 'Đảm bảo dòng điện ≤ 12A / 2500W',
          targetSoc: 80,
          maxAmps: 10.0,
        ),
      );
    } else if (lower.contains('sạc') || lower.contains('shelly')) {
      reply =
          'Để sạc xe an toàn qua ổ cắm thông minh **Shelly Plug S Gen3**:\n\n'
          '1. Cắm sạc và kiểm tra đèn tín hiệu trên ổ cắm.\n'
          '2. Dòng sạc được giới hạn an toàn dưới **10A / 2200W**.\n'
          '3. Bạn có thể đặt mức pin ngắt tự động (Target SoC) ở tab Sạc pin.';
    } else {
      reply =
          'Chào bạn! BatteryBot đã nhận được câu hỏi: *"$message"*.\n\n'
          'Chiếc **$model** của bạn đang có **$soc% pin**. Bạn cần mình hỗ trợ kiểm tra pin, hẹn giờ sạc hay mẹo tiết kiệm điện không?';
    }

    if (triggeredAction != null) {
      onFunctionCall?.call(triggeredAction);
      if (!fnComp.isCompleted) fnComp.complete(triggeredAction);
    } else {
      if (!fnComp.isCompleted) fnComp.complete(null);
    }

    final words = reply.split(' ');
    int index = 0;
    Timer.periodic(const Duration(milliseconds: 35), (timer) {
      if (index < words.length) {
        controller.add('${words[index]}${index < words.length - 1 ? " " : ""}');
        index++;
      } else {
        timer.cancel();
        controller.close();
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
    final uri = AppConstants.tryBuildApiUri('/api/chat/action/confirm');
    if (uri == null || !AppConstants.isApiConfigured) {
      return {
        'status': 'success',
        'data': {
          'callId': callId,
          'toolName': toolName,
          'status': confirmed ? 'confirmed' : 'cancelled',
          'executed': confirmed,
          'message': confirmed
              ? 'Đã xác nhận thực hiện hành động thành công (mô phỏng).'
              : 'Đã hủy hành động.',
        },
      };
    }

    try {
      final headers = await _getHeaders();
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

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else {
        return {
          'status': 'error',
          'message': 'Lỗi máy chủ (${res.statusCode}): ${res.body}',
        };
      }
    } catch (e) {
      return {'status': 'error', 'message': 'Không thể kết nối máy chủ: $e'};
    }
  }

  /// Lấy danh sách các session
  Future<List<ChatSession>> getSessions() async {
    final uri = AppConstants.tryBuildApiUri('/api/chat/sessions');
    if (uri == null) return [];
    try {
      final headers = await _getHeaders();
      final res = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = body['data'] as List<dynamic>? ?? [];
        return list
            .map((item) => ChatSession.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Gửi đánh giá phản hồi (like/dislike)
  Future<bool> sendFeedback({
    required String sessionId,
    required String messageId,
    required String rating,
  }) async {
    final uri = AppConstants.tryBuildApiUri('/api/chat/feedback');
    if (uri == null) return true;
    try {
      final headers = await _getHeaders();
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
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
