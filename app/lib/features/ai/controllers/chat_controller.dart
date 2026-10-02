import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../models/function_call_action.dart';
import '../services/behavior_sync_service.dart';
import '../services/behavior_tracker.dart';
import '../services/chat_api_service.dart';
import '../services/chat_history_storage.dart';

@immutable
class ChatState {
  const ChatState({
    this.messages = const [],
    this.isStreaming = false,
    this.sessionId,
    this.offlineQueue = const [],
    this.isOnline = true,
    this.currentError,
  });

  final List<ChatMessage> messages;
  final bool isStreaming;
  final String? sessionId;
  final List<ChatMessage> offlineQueue;
  final bool isOnline;
  final String? currentError;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isStreaming,
    String? sessionId,
    List<ChatMessage>? offlineQueue,
    bool? isOnline,
    String? currentError,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isStreaming: isStreaming ?? this.isStreaming,
      sessionId: sessionId ?? this.sessionId,
      offlineQueue: offlineQueue ?? this.offlineQueue,
      isOnline: isOnline ?? this.isOnline,
      currentError: currentError,
    );
  }
}

final chatControllerProvider =
    StateNotifierProvider.autoDispose<ChatController, ChatState>((ref) {
  final apiService = ref.watch(chatApiServiceProvider);
  final storage = ref.watch(chatHistoryStorageProvider);
  final behaviorTracker = ref.watch(behaviorTrackerProvider.notifier);
  final behaviorSync = ref.watch(behaviorSyncServiceProvider);

  final controller = ChatController(
    apiService: apiService,
    storage: storage,
    behaviorTracker: behaviorTracker,
    behaviorSync: behaviorSync,
  );

  return controller;
});

class ChatController extends StateNotifier<ChatState> {
  ChatController({
    required ChatApiService apiService,
    required ChatHistoryStorage storage,
    required BehaviorTracker behaviorTracker,
    required BehaviorSyncService behaviorSync,
    Connectivity? connectivity,
  })  : _apiService = apiService,
        _storage = storage,
        _behaviorTracker = behaviorTracker,
        _behaviorSync = behaviorSync,
        _connectivity = connectivity ?? Connectivity(),
        super(const ChatState()) {
    _init();
  }

  final ChatApiService _apiService;
  final ChatHistoryStorage _storage;
  final BehaviorTracker _behaviorTracker;
  final BehaviorSyncService _behaviorSync;
  final Connectivity _connectivity;

  StreamSubscription<ConnectivityResult>? _connectivitySub;
  StreamSubscription<String>? _streamSub;

  Future<void> _init() async {
    startNewChat(preserveGreeting: true);
    await _checkConnectivity();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((result) {
      final online = result != ConnectivityResult.none;
      if (online != state.isOnline) {
        state = state.copyWith(isOnline: online);
        if (online && state.offlineQueue.isNotEmpty) {
          processOfflineQueue();
        }
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _streamSub?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      state = state.copyWith(isOnline: result != ConnectivityResult.none);
    } catch (_) {
      state = state.copyWith(isOnline: true);
    }
  }

  void startNewChat({bool preserveGreeting = false}) {
    final sid = 'session-${DateTime.now().millisecondsSinceEpoch}';
    final initialList = preserveGreeting
        ? [
            ChatMessage(
              id: 'msg-welcome',
              role: ChatRole.model,
              content:
                  'Chào bạn! Mình là BatteryBot. Bạn cần hỗ trợ kiểm tra pin, cài đặt sạc hay kết nối thiết bị Shelly?',
              timestamp: DateTime.now(),
            ),
          ]
        : <ChatMessage>[];

    state = state.copyWith(
      sessionId: sid,
      messages: initialList,
      isStreaming: false,
      currentError: null,
    );
  }

  Future<void> loadSession(String sessionId) async {
    final loaded = await _storage.loadSessionMessages(sessionId);
    if (loaded.isNotEmpty) {
      state = state.copyWith(
        sessionId: sessionId,
        messages: loaded,
        isStreaming: false,
        currentError: null,
      );
    }
  }

  /// Gửi tin nhắn người dùng (có hỗ trợ hàng đợi ngoại tuyến offline queue)
  Future<void> sendMessage({
    required String text,
    Map<String, dynamic>? vehicleContext,
    Map<String, dynamic>? behaviorProfile,
    void Function(FunctionCallAction action)? onFunctionCall,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isStreaming) return;

    final userMsgId = 'msg-user-${DateTime.now().millisecondsSinceEpoch}';
    final userMsg = ChatMessage(
      id: userMsgId,
      role: ChatRole.user,
      content: trimmed,
      timestamp: DateTime.now(),
      isQueued: !state.isOnline,
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isStreaming: state.isOnline,
    );

    // Nếu đang ngoại tuyến, đẩy vào hàng đợi offline queue
    if (!state.isOnline) {
      final queue = [...state.offlineQueue, userMsg];
      final offlineBotReply = ChatMessage(
        id: 'msg-bot-offline-${DateTime.now().millisecondsSinceEpoch}',
        role: ChatRole.model,
        content:
            'Đang ở chế độ ngoại tuyến. Tin nhắn của bạn đã được xếp vào hàng đợi và sẽ tự động gửi khi có kết nối mạng!',
        timestamp: DateTime.now(),
        isQueued: true,
      );
      state = state.copyWith(
        offlineQueue: queue,
        messages: [...state.messages, offlineBotReply],
        isStreaming: false,
      );
      return;
    }

    await _executeStreamSend(
      userMsg: userMsg,
      vehicleContext: vehicleContext,
      behaviorProfile: behaviorProfile,
      onFunctionCall: onFunctionCall,
    );
  }

  Future<void> _executeStreamSend({
    required ChatMessage userMsg,
    Map<String, dynamic>? vehicleContext,
    Map<String, dynamic>? behaviorProfile,
    void Function(FunctionCallAction action)? onFunctionCall,
  }) async {
    final botMsgId = 'msg-bot-${DateTime.now().millisecondsSinceEpoch}';
    final botPlaceholder = ChatMessage(
      id: botMsgId,
      role: ChatRole.model,
      content: '',
      timestamp: DateTime.now(),
      isStreaming: true,
    );

    state = state.copyWith(
      messages: [...state.messages, botPlaceholder],
      isStreaming: true,
    );

    final streamResponse = _apiService.streamChat(
      message: userMsg.content,
      sessionId: state.sessionId,
      vehicleContext: vehicleContext,
      behaviorProfile: behaviorProfile,
      onFunctionCall: (action) {
        _attachActionCard(botMsgId, action);
        onFunctionCall?.call(action);
      },
      onRichCard: (cardData) {
        _attachRichCard(botMsgId, cardData);
      },
    );

    streamResponse.sessionIdCompleter.future.then((sid) {
      if (sid.isNotEmpty) {
        state = state.copyWith(sessionId: sid);
      }
    });

    String accumulated = '';
    _streamSub?.cancel();
    _streamSub = streamResponse.stream.listen(
      (chunk) {
        accumulated += chunk;
        _updateMessageContent(botMsgId, accumulated, isStreaming: true);
      },
      onError: (err) {
        _updateMessageContent(
          botMsgId,
          accumulated.isNotEmpty
              ? accumulated
              : 'Đã xảy ra sự cố khi kết nối tới AI. Bạn có thể nhấn Thử lại bên dưới.',
          isStreaming: false,
          hasError: true,
          errorMessage: err.toString(),
        );
        state = state.copyWith(isStreaming: false);
      },
      onDone: () {
        _updateMessageContent(
          botMsgId,
          accumulated,
          isStreaming: false,
        );
        state = state.copyWith(isStreaming: false);
        _persistSession();
      },
    );
  }

  void _attachActionCard(String msgId, FunctionCallAction action) {
    final updated = state.messages.map((m) {
      if (m.id == msgId) {
        return m.copyWith(actionCard: action);
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
  }

  void _attachRichCard(String msgId, Map<String, dynamic> cardData) {
    final updated = state.messages.map((m) {
      if (m.id == msgId) {
        final currentCards = m.richCards != null
            ? List<Map<String, dynamic>>.from(m.richCards!)
            : <Map<String, dynamic>>[];
        currentCards.add(cardData);
        return m.copyWith(richCards: currentCards);
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
  }

  void _updateMessageContent(
    String msgId,
    String content, {
    bool? isStreaming,
    bool? hasError,
    String? errorMessage,
  }) {
    final updated = state.messages.map((m) {
      if (m.id == msgId) {
        return m.copyWith(
          content: content,
          isStreaming: isStreaming ?? m.isStreaming,
          hasError: hasError ?? m.hasError,
          errorMessage: errorMessage ?? m.errorMessage,
        );
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
  }

  /// Thử lại một tin nhắn bị lỗi (Retry logic)
  Future<void> retryMessage(String messageId) async {
    final index = state.messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    // Tìm tin nhắn user trước đó
    ChatMessage? targetUserMsg;
    for (int i = index; i >= 0; i--) {
      if (state.messages[i].role == ChatRole.user) {
        targetUserMsg = state.messages[i];
        break;
      }
    }

    if (targetUserMsg == null) return;

    // Bỏ tin nhắn bot bị lỗi và gửi lại
    final newMessages = List<ChatMessage>.from(state.messages)..removeAt(index);
    state = state.copyWith(messages: newMessages);

    await _executeStreamSend(userMsg: targetUserMsg);
  }

  /// Xử lý các tin nhắn trong hàng đợi offline khi kết nối trở lại
  Future<void> processOfflineQueue() async {
    if (state.offlineQueue.isEmpty || !state.isOnline) return;

    final queue = List<ChatMessage>.from(state.offlineQueue);
    state = state.copyWith(offlineQueue: const []);

    for (final queuedMsg in queue) {
      // Đổi trạng thái tin nhắn trong UI thành không còn queued
      final updated = state.messages.map((m) {
        if (m.id == queuedMsg.id) {
          return m.copyWith(isQueued: false);
        }
        return m;
      }).toList();
      state = state.copyWith(messages: updated);

      await _executeStreamSend(userMsg: queuedMsg);
    }
  }

  /// Xác nhận hoặc hủy hành động Action Card
  Future<bool> confirmAction({
    required String callId,
    required String toolName,
    required Map<String, dynamic> args,
    required bool confirmed,
  }) async {
    final res = await _apiService.confirmAction(
      sessionId: state.sessionId ?? 'session-local',
      callId: callId,
      toolName: toolName,
      args: args,
      confirmed: confirmed,
    );

    final data = (res['data'] as Map<String, dynamic>?) ?? {};
    final resultMsg = data['message'] as String? ??
        (confirmed ? 'Đã kích hoạt thành công.' : 'Đã hủy lệnh.');

    final updated = state.messages.map((m) {
      if (m.actionCard?.callId == callId) {
        final newAction = m.actionCard!.copyWith(
          status: confirmed ? 'confirmed' : 'cancelled',
          resultMessage: resultMsg,
        );
        return m.copyWith(actionCard: newAction);
      }
      return m;
    }).toList();

    state = state.copyWith(messages: updated);
    _persistSession();
    return true;
  }

  /// Gửi feedback 👍/👎
  Future<void> sendFeedback(String messageId, String rating) async {
    final updated = state.messages.map((m) {
      if (m.id == messageId) {
        return m.copyWith(userFeedback: rating);
      }
      return m;
    }).toList();

    state = state.copyWith(messages: updated);
    _behaviorTracker.trackChatInteraction(feedbackRating: rating);

    if (state.sessionId != null) {
      await _apiService.sendFeedback(
        sessionId: state.sessionId!,
        messageId: messageId,
        rating: rating,
      );
      _persistSession();
    }
  }

  void _persistSession() {
    if (state.sessionId != null && state.messages.isNotEmpty) {
      final firstUser = state.messages.firstWhere(
        (m) => m.role == ChatRole.user,
        orElse: () => state.messages.first,
      );
      final title = firstUser.content.length > 30
          ? '${firstUser.content.substring(0, 30)}...'
          : firstUser.content;

      unawaited(_storage.saveSessionMessages(state.sessionId!, state.messages, title: title));
      unawaited(_storage.backupToCloud(state.sessionId!, state.messages, title: title));
      _behaviorSync.scheduleSync();
    }
  }
}
