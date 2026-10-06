import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/app_state_providers.dart';
import '../../core/providers/vehicle_context_provider.dart';
import '../../core/services/assistant_context_coordinator.dart';
import '../../core/theme/app_ui_colors.dart';
import '../../core/utils/battery_bot_faq.dart';
import '../../core/widgets/battery_bot_mascot.dart';
import '../smart_charging/shelly_connect_screen.dart';
import 'models/chat_message.dart';
import 'models/function_call_action.dart';
import 'models/proactive_suggestion.dart';
import 'services/behavior_sync_service.dart';
import 'services/behavior_tracker.dart';
import 'services/chat_api_service.dart';
import 'services/chat_history_storage.dart';
import 'services/suggestion_service.dart';
import 'services/voice_input_service.dart';
import 'widgets/animated_voice_waveform.dart';
import 'widgets/chat_message_bubble.dart';
import 'widgets/quick_reply_chips.dart';

/// Bottom Sheet trò chuyện cùng trợ lý ảo BatteryBot với AI Streaming & Lịch sử
class InteractiveAssistantSheet extends ConsumerStatefulWidget {
  const InteractiveAssistantSheet({super.key, this.initialQuery});

  final String? initialQuery;

  static Future<void> show(BuildContext context, {String? initialQuery}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => InteractiveAssistantSheet(initialQuery: initialQuery),
    );
  }

  @override
  ConsumerState<InteractiveAssistantSheet> createState() =>
      _InteractiveAssistantSheetState();
}

class _InteractiveAssistantSheetState
    extends ConsumerState<InteractiveAssistantSheet> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  int _generation = 0;
  String? _ownerUid;
  StreamSubscription<User?>? _authSubscription;
  Timer? _replyTimer;

  String? _currentUid() =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
  bool _isCurrent(int generation) =>
      mounted && generation == _generation && _ownerUid == _currentUid();
  String? _sessionId;
  StreamSubscription<String>? _streamSub;
  final Map<String, bool> _actionLoadingMap = {};
  final Set<String> _feedbackPending = {};
  BuildContext? _historyModalContext;
  ProactiveSuggestion? _activeSuggestion;
  VoiceInputService? _voiceService;
  bool _isListeningVoice = false;
  double _voiceSoundLevel = 0.5;

  @override
  void initState() {
    super.initState();
    _ownerUid = _currentUid();
    _startNewChat(preserveGreeting: true);
    if (Firebase.apps.isNotEmpty) {
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) {
        if (!mounted || user?.uid == _ownerUid) return;
        final historyContext = _historyModalContext;
        if (historyContext != null && historyContext.mounted) {
          Navigator.of(historyContext).pop();
        }
        _ownerUid = user?.uid;
        _inputController.clear();
        _startNewChat();
        ref
            .read(behaviorTrackerProvider.notifier)
            .setIdentity(userId: _ownerUid ?? 'guest');
      });
    }

    // Ghi nhận hành vi truy cập assistant sheet và định danh người dùng
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (Firebase.apps.isNotEmpty) {
          final user = FirebaseAuth.instance.currentUser;
          final vehicle = ref.read(vehicleContextProvider).vehicle;
          if (user != null) {
            ref
                .read(behaviorTrackerProvider.notifier)
                .setIdentity(userId: user.uid, vehicleId: vehicle?.vehicleId);
          }
        }
      } catch (_) {}
      ref
          .read(behaviorTrackerProvider.notifier)
          .trackAppUsage(tabName: 'assistant_sheet');
      _checkProactiveSuggestions();
    });

    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleSend(widget.initialQuery!);
      });
    }
  }

  String _detectTopic(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('pin') ||
        lower.contains('soc') ||
        lower.contains('soh') ||
        lower.contains('chai pin') ||
        lower.contains('battery')) {
      return 'pin';
    }
    if (lower.contains('sạc') ||
        lower.contains('sac') ||
        lower.contains('ampe') ||
        lower.contains('công suất') ||
        lower.contains('target soc')) {
      return 'sac';
    }
    if (lower.contains('shelly') ||
        lower.contains('plug') ||
        lower.contains('kết nối') ||
        lower.contains('wifi') ||
        lower.contains('mã admin')) {
      return 'shelly';
    }
    if (lower.contains('lộ trình') ||
        lower.contains('quãng đường') ||
        lower.contains('km') ||
        lower.contains('chuyến đi') ||
        lower.contains('đi xa')) {
      return 'lo_trinh';
    }
    return 'general';
  }

  Future<void> _checkProactiveSuggestions() async {
    final generation = _generation;
    try {
      final suggestionService = ref.read(suggestionServiceProvider);
      final canShow = await suggestionService.canShowProactiveBubble();
      if (!canShow || !_isCurrent(generation)) return;

      final vehicle = ref.read(vehicleContextProvider).vehicle;
      final user = FirebaseAuth.instance.currentUser;

      final suggestions = await suggestionService.fetchSuggestions(
        userId: user?.uid ?? 'guest',
        vehicleId: vehicle?.vehicleId,
        currentSoc: vehicle?.currentBattery.toDouble(),
        currentSoh: vehicle?.stateOfHealth.toDouble(),
        odoKm: vehicle?.currentOdo,
      );

      if (suggestions.isNotEmpty && _isCurrent(generation)) {
        setState(() {
          _activeSuggestion = suggestions.first;
        });
        await suggestionService.recordSuggestionShown();
      }
    } catch (_) {}
  }

  void _applySuggestion(ProactiveSuggestion suggestion) {
    final query = suggestion.action != null && suggestion.action!.isNotEmpty
        ? 'Hãy giúp tôi thực hiện: ${suggestion.title}'
        : suggestion.message;
    setState(() {
      _activeSuggestion = null;
    });
    _handleSend(query);
  }

  void _dismissActiveSuggestion() {
    if (_activeSuggestion != null) {
      ref
          .read(suggestionServiceProvider)
          .dismissSuggestion(_activeSuggestion!.ruleId);
      setState(() {
        _activeSuggestion = null;
      });
    }
  }

  Future<void> _handleActionConfirm(
    int msgIndex,
    FunctionCallAction action,
  ) async {
    if (msgIndex >= _messages.length ||
        _actionLoadingMap[action.callId] == true) {
      return;
    }
    final generation = _generation;

    setState(() {
      _actionLoadingMap[action.callId] = true;
    });

    try {
      final res = await ref
          .read(chatApiServiceProvider)
          .confirmAction(
            sessionId: _sessionId ?? 'session-local',
            callId: action.callId,
            toolName: action.toolName,
            args: action.args,
            confirmed: true,
          );

      if (!_isCurrent(generation) || msgIndex >= _messages.length) return;

      final data = (res['data'] as Map<String, dynamic>?) ?? {};
      final succeeded = res['success'] == true && data['success'] == true;
      final message = succeeded
          ? (data['message'] as String? ?? 'Đã xác nhận kết quả.')
          : 'Chưa thực hiện được. Hãy kiểm tra tại màn hình Sạc pin.';

      setState(() {
        _actionLoadingMap.remove(action.callId);
        final updatedAction = action.copyWith(
          status: succeeded ? 'confirmed' : 'failed',
          resultMessage: message,
        );
        _messages[msgIndex] = _messages[msgIndex].copyWith(
          actionCard: updatedAction,
        );
      });

      ref
          .read(behaviorTrackerProvider.notifier)
          .trackChatInteraction(topic: 'action_confirmed_${action.toolName}');

      if (_sessionId != null) {
        final storage = ref.read(chatHistoryStorageProvider);
        unawaited(storage.saveSessionMessages(_sessionId!, _messages));
        unawaited(storage.backupToCloud(_sessionId!, _messages));
      }
    } catch (_) {
      if (!mounted || !_isCurrent(generation)) return;
      setState(() {
        _actionLoadingMap.remove(action.callId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chưa thực hiện được. Hãy kiểm tra tại màn hình Sạc pin.',
          ),
        ),
      );
    }
  }

  Future<void> _handleActionCancel(
    int msgIndex,
    FunctionCallAction action,
  ) async {
    if (msgIndex >= _messages.length ||
        _actionLoadingMap[action.callId] == true) {
      return;
    }
    final generation = _generation;

    setState(() {
      final updatedAction = action.copyWith(
        status: 'cancelled',
        resultMessage: 'Đã hủy lệnh.',
      );
      _messages[msgIndex] = _messages[msgIndex].copyWith(
        actionCard: updatedAction,
      );
    });

    try {
      await ref
          .read(chatApiServiceProvider)
          .confirmAction(
            sessionId: _sessionId ?? 'session-local',
            callId: action.callId,
            toolName: action.toolName,
            args: action.args,
            confirmed: false,
          );
    } catch (_) {}

    if (_sessionId != null && _isCurrent(generation)) {
      final storage = ref.read(chatHistoryStorageProvider);
      unawaited(storage.saveSessionMessages(_sessionId!, _messages));
      unawaited(storage.backupToCloud(_sessionId!, _messages));
    }
  }

  Future<void> _toggleVoiceInput() async {
    if (_isTyping) return;
    _voiceService ??= VoiceInputService();

    if (_isListeningVoice) {
      final text = await _voiceService!.stopListening();
      if (!mounted) return;
      setState(() {
        _isListeningVoice = false;
        _voiceSoundLevel = 0.0;
      });
      if (text.trim().isNotEmpty) {
        _inputController.text = text;
        _handleSend(text);
      }
    } else {
      final success = await _voiceService!.startListening(
        localeId: 'vi_VN',
        onResult: (text) {
          if (!mounted) return;
          _voiceService!.updateTranscript(text);
          setState(() {
            _inputController.text = text;
          });
        },
        onSoundLevel: (level) {
          if (!mounted) return;
          setState(() {
            _voiceSoundLevel = level;
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _isListeningVoice = false;
            _voiceSoundLevel = 0.0;
          });
        },
      );

      if (success && mounted) {
        setState(() {
          _isListeningVoice = true;
        });
      }
    }
  }

  void _handleRetry(int msgIndex) {
    if (msgIndex >= _messages.length || _isTyping) return;
    String? userPrompt;
    for (int i = msgIndex; i >= 0; i--) {
      if (_messages[i].role == ChatRole.user) {
        userPrompt = _messages[i].content;
        break;
      }
    }
    if (userPrompt != null) {
      setState(() {
        _messages.removeAt(msgIndex);
        if (_messages.isNotEmpty && _messages.last.role == ChatRole.user) {
          _messages.removeLast();
        }
      });
      _handleSend(userPrompt);
    }
  }

  void _startNewChat({bool preserveGreeting = false}) {
    _generation++;
    _replyTimer?.cancel();
    _streamSub?.cancel();
    _isTyping = false;
    _activeSuggestion = null;
    _actionLoadingMap.clear();
    setState(() {
      _sessionId = 'session-${DateTime.now().millisecondsSinceEpoch}';
      _messages.clear();
      _messages.add(
        ChatMessage(
          id: 'msg-welcome',
          role: ChatRole.model,
          content:
              'Chào bạn! Mình là BatteryBot. Bạn cần hỗ trợ kiểm tra pin, cài đặt sạc hay kết nối thiết bị Shelly?',
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  Future<void> _loadSession(String sessionId) async {
    _generation++;
    final generation = _generation;
    _replyTimer?.cancel();
    await _streamSub?.cancel();
    _isTyping = false;
    final loaded = await ref
        .read(chatHistoryStorageProvider)
        .loadSessionMessages(sessionId);
    if (!_isCurrent(generation)) return;
    if (loaded.isNotEmpty) {
      setState(() {
        _sessionId = sessionId;
        _messages.clear();
        _messages.addAll(loaded);
      });
      _scrollToBottom();
    }
  }

  Future<void> _showHistoryModal() async {
    final generation = _generation;
    final storage = ref.read(chatHistoryStorageProvider);
    final sessions = await storage.listSessions();
    if (!mounted || !_isCurrent(generation)) return;

    final uiColors = AppUiColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: uiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        _historyModalContext = modalCtx;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.history_rounded,
                              color: uiColors.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Lịch sử trò chuyện',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: uiColors.text,
                              ),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          icon: const Icon(
                            Icons.add_comment_outlined,
                            size: 16,
                          ),
                          label: const Text('Đoạn chat mới'),
                          onPressed: () {
                            Navigator.of(modalCtx).pop();
                            _startNewChat();
                          },
                        ),
                      ],
                    ),
                    const Divider(),
                    if (sessions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'Chưa có lịch sử hội thoại nào.',
                            style: TextStyle(
                              color: uiColors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.4,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: sessions.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (itemCtx, i) {
                            final sess = sessions[i];
                            final isCurrent = sess.id == _sessionId;
                            final dateStr = DateFormat(
                              'dd/MM HH:mm',
                            ).format(sess.updatedAt);
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: isCurrent
                                    ? uiColors.primary.withValues(alpha: 0.15)
                                    : uiColors.background,
                                child: Icon(
                                  isCurrent
                                      ? Icons.chat_bubble
                                      : Icons.chat_bubble_outline,
                                  color: isCurrent
                                      ? uiColors.primary
                                      : uiColors.muted,
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                sess.title,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: uiColors.text,
                                ),
                              ),
                              subtitle: Text(
                                '$dateStr • ${sess.messageCount} tin nhắn',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: uiColors.muted,
                                ),
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: uiColors.muted,
                                ),
                                onPressed: () async {
                                  await storage.deleteSession(sess.id);
                                  if (!ctx.mounted || !mounted) return;
                                  setModalState(() {
                                    sessions.removeAt(i);
                                  });
                                  if (sess.id == _sessionId) {
                                    _startNewChat();
                                  }
                                },
                              ),
                              onTap: () {
                                Navigator.of(modalCtx).pop();
                                if (!isCurrent) {
                                  _loadSession(sess.id);
                                }
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _generation++;
    _replyTimer?.cancel();
    _authSubscription?.cancel();
    _streamSub?.cancel();
    _voiceService?.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _looksSensitive(String text) =>
      RegExp(
        r'(cloud\s*key|auth[_ -]?key|api[_ -]?key|password|mật khẩu|bearer\s+[a-z0-9._-]{16,})',
        caseSensitive: false,
      ).hasMatch(text) ||
      RegExp(r'\b[A-Za-z0-9_-]{32,}\b').hasMatch(text);

  void _handleSend(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty || _isTyping) return;
    final generation = _generation;
    _inputController.clear();
    if (_looksSensitive(text)) {
      setState(
        () => _messages.add(
          ChatMessage(
            id: 'privacy-${DateTime.now().microsecondsSinceEpoch}',
            role: ChatRole.model,
            timestamp: DateTime.now(),
            content:
                'Không gửi mật khẩu hoặc khóa truy cập trong chat. Hãy nhập tại màn hình thiết lập.',
          ),
        ),
      );
      return;
    }
    ref
        .read(behaviorTrackerProvider.notifier)
        .trackChatInteraction(topic: _detectTopic(text));
    setState(() {
      _messages.add(
        ChatMessage(
          id: 'user-${DateTime.now().microsecondsSinceEpoch}',
          role: ChatRole.user,
          content: text,
          timestamp: DateTime.now(),
        ),
      );
      _isTyping = true;
    });
    _scrollToBottom();
    final normalized = BatteryBotFaq.normalize(text);
    final wantsGuidance = RegExp(
      r'\b(o dau|huong dan|lam sao|cach|mo|ket noi|dung sac|bat dau sac|bi khoa)\b',
    ).hasMatch(normalized);
    final faqAction = wantsGuidance ? BatteryBotFaq.actionFor(text) : null;
    if (faqAction != null) {
      _replyTimer = Timer(const Duration(milliseconds: 180), () {
        if (!_isCurrent(generation)) return;
        final reply = switch (faqAction) {
          BatteryBotAction.shellySetup =>
            'Mở thiết lập Shelly để kết nối qua Wi-Fi hoặc mã quản trị 6 ký tự.',
          BatteryBotAction.guideCharging =>
            'Mở Sạc pin để kiểm tra bộ sạc và chọn thời gian sạc. Chỉ bật sạc sau khi kiểm tra an toàn.',
          BatteryBotAction.guideHistory =>
            'Mở Lịch sử để xem thời gian, điện năng và chi phí từng phiên.',
          BatteryBotAction.guideVehicle =>
            'Mở Tổng quan để chọn xe và xem mức pin. Kiểm tra nguồn và thời điểm cập nhật.',
        };
        setState(() {
          _isTyping = false;
          _messages.add(
            ChatMessage(
              id: 'faq-${DateTime.now().microsecondsSinceEpoch}',
              role: ChatRole.model,
              content: reply,
              timestamp: DateTime.now(),
              action: faqAction.name,
            ),
          );
        });
        _persistConversation();
        _scrollToBottom();
      });
      return;
    }
    final vehicle = ref.read(vehicleContextProvider).vehicle;
    final index = _messages.length;
    final id = 'reply-${DateTime.now().microsecondsSinceEpoch}';
    setState(
      () => _messages.add(
        ChatMessage(
          id: id,
          role: ChatRole.model,
          content: '',
          timestamp: DateTime.now(),
          isStreaming: true,
        ),
      ),
    );
    bool current() => _isCurrent(generation) && index < _messages.length;
    String accumulated = '';
    bool failed = false;
    void replaceText(String text) {
      if (!current()) return;
      accumulated = text;
      setState(
        () => _messages[index] = _messages[index].copyWith(content: text),
      );
    }

    final response = ref
        .read(chatApiServiceProvider)
        .streamChat(
          message: text,
          sessionId: _sessionId,
          behaviorProfile: ref.read(behaviorTrackerProvider).toJson(),
          vehicleContext: {
            if (vehicle != null) ...{
              'vehicleId': vehicle.vehicleId,
              'model': vehicle.vehicleName,
              'currentSoc': vehicle.currentBattery,
              'currentSoh': vehicle.stateOfHealth,
              'odoKm': vehicle.currentOdo,
            },
          },
          onTextReplace: replaceText,
          onFunctionCall: (action) {
            if (!current()) return;
            setState(
              () => _messages[index] = _messages[index].copyWith(
                actionCard: action,
              ),
            );
          },
          onRichCard: (card) {
            if (!current()) return;
            setState(
              () => _messages[index] = _messages[index].copyWith(
                richCards: [...?_messages[index].richCards, card],
              ),
            );
          },
        );
    response.sessionIdCompleter.future.then((sid) {
      if (current() && sid.isNotEmpty) _sessionId = sid;
    });
    response.messageIdCompleter.future.then((mid) {
      if (current() && mid.isNotEmpty) {
        setState(() => _messages[index] = _messages[index].copyWith(id: mid));
      }
    });
    _streamSub = response.stream.listen(
      (delta) {
        if (!current()) return;
        replaceText(accumulated + delta);
        _scrollToBottom();
      },
      onError: (Object error) {
        if (!current()) return;
        failed = true;
        setState(() {
          _isTyping = false;
          _messages[index] = _messages[index].copyWith(
            content: error is ChatApiException
                ? error.userMessage
                : 'Chưa nhận được câu trả lời. Hãy thử lại.',
            isStreaming: false,
            hasError: true,
          );
        });
        _scrollToBottom();
      },
      onDone: () {
        if (!current() || failed) return;
        setState(() {
          _isTyping = false;
          _messages[index] = _messages[index].copyWith(
            content: accumulated.isEmpty
                ? 'Chưa nhận được câu trả lời. Hãy thử lại.'
                : accumulated,
            isStreaming: false,
            hasError: accumulated.isEmpty,
          );
        });
        _persistConversation();
        _scrollToBottom();
      },
    );
  }

  void _persistConversation() {
    if (_sessionId == null || !_isCurrent(_generation)) return;
    final storage = ref.read(chatHistoryStorageProvider);
    final messages = List<ChatMessage>.of(_messages);
    unawaited(storage.saveSessionMessages(_sessionId!, messages));
    unawaited(storage.backupToCloud(_sessionId!, messages));
    ref.read(behaviorSyncServiceProvider).scheduleSync();
  }

  Future<void> _onFeedback(int index, String rating) async {
    if (index >= _messages.length || _sessionId == null) return;
    final generation = _generation;
    final message = _messages[index];
    if (message.userFeedback == rating || !_feedbackPending.add(message.id)) {
      return;
    }
    bool accepted;
    try {
      accepted = await ref
          .read(chatApiServiceProvider)
          .sendFeedback(
            sessionId: _sessionId!,
            messageId: message.id,
            rating: rating,
          );
    } finally {
      _feedbackPending.remove(message.id);
    }
    if (!_isCurrent(generation) || index >= _messages.length) return;
    if (!accepted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa gửi được đánh giá. Bạn hãy thử lại.'),
        ),
      );
      return;
    }
    setState(() => _messages[index] = message.copyWith(userFeedback: rating));
    ref
        .read(behaviorTrackerProvider.notifier)
        .trackChatInteraction(feedbackRating: rating);
    _persistConversation();
  }

  void _executeAction(BatteryBotAction action) {
    final navigator = Navigator.of(context);
    navigator.pop(); // Đóng bottom sheet

    switch (action) {
      case BatteryBotAction.guideVehicle:
        ref.read(currentTabProvider.notifier).state = 0;
        break;
      case BatteryBotAction.guideCharging:
        ref.read(currentTabProvider.notifier).state = 1;
        break;
      case BatteryBotAction.guideHistory:
        ref.read(currentTabProvider.notifier).state = 2;
        break;
      case BatteryBotAction.shellySetup:
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const ShellyConnectScreen()),
        );
        break;
    }
  }

  Widget _buildProactiveBanner(AppUiColors uiColors) {
    final s = _activeSuggestion;
    if (s == null) return const SizedBox.shrink();

    final isHigh = s.priority.toUpperCase() == 'HIGH';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isHigh
            ? Colors.amber.withValues(alpha: 0.12)
            : uiColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHigh
              ? Colors.amber.withValues(alpha: 0.4)
              : uiColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isHigh
                ? Icons.warning_amber_rounded
                : Icons.tips_and_updates_outlined,
            color: isHigh ? Colors.amber.shade800 : uiColors.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isHigh ? Colors.amber.shade900 : uiColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.message,
                  style: TextStyle(
                    fontSize: 11,
                    color: uiColors.text.withValues(alpha: 0.85),
                    height: 1.3,
                  ),
                ),
                if (s.action != null && s.action!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => _applySuggestion(s),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Xem gợi ý',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: uiColors.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 12,
                            color: uiColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.close, size: 16, color: uiColors.muted),
            onPressed: _dismissActiveSuggestion,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiColors = AppUiColors.of(context);
    final vehicleContext = ref.watch(vehicleContextProvider);
    final vehicle = vehicleContext.vehicle;
    final coordinator = ref.watch(assistantContextCoordinatorProvider);

    final chips = coordinator.quickActionChips.isNotEmpty
        ? coordinator.quickActionChips
        : BatteryBotFaq.suggestions;

    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final sheetHeight =
        (media.size.height - keyboard - media.padding.top) * 0.9;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        height: sheetHeight,
        decoration: BoxDecoration(
          color: uiColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Thanh kéo drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: uiColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header với Mascot và thông tin xe
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  const BatteryBotMascot(
                    size: BatteryBotSize.avatar,
                    displayMode: BatteryBotDisplayMode.avatar,
                    mood: BatteryBotMood.happy,
                    enableFloating: false,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'BatteryBot',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: uiColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          vehicle != null
                              ? '${vehicle.vehicleName} • Pin ${vehicle.currentBattery}%'
                              : 'Chưa chọn xe theo dõi',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: uiColors.muted,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('assistant_history_button'),
                    icon: Icon(
                      Icons.history_rounded,
                      color: uiColors.muted,
                      size: 20,
                    ),
                    tooltip: 'Lịch sử chat',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: _showHistoryModal,
                  ),
                  IconButton(
                    key: const Key('assistant_new_chat_button'),
                    icon: Icon(
                      Icons.add_comment_outlined,
                      color: uiColors.muted,
                      size: 20,
                    ),
                    tooltip: 'Đoạn chat mới',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => _startNewChat(),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: uiColors.muted, size: 20),
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Quick Action Chips
            if (keyboard == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: QuickReplyChips(
                  customSuggestions: chips,
                  currentSoc: vehicle?.currentBattery.toDouble(),
                  isCharging: false,
                  onSelect: (chipText) => _handleSend(chipText),
                ),
              ),

            const Divider(height: 1),

            // Banner gợi ý chủ động (Proactive Suggestion) nếu có
            if (_activeSuggestion != null) _buildProactiveBanner(uiColors),

            // Danh sách tin nhắn
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return ChatMessageBubble(
                    message: message,
                    onFeedback: (rating) => _onFeedback(index, rating),
                    onActionPressed: _executeAction,
                    isActionLoading:
                        _actionLoadingMap[message.actionCard?.callId] ?? false,
                    onConfirmAction: (act) => _handleActionConfirm(index, act),
                    onCancelAction: (act) => _handleActionCancel(index, act),
                    onRetry: () => _handleRetry(index),
                  );
                },
              ),
            ),

            if (_isTyping)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Đang chuẩn bị câu trả lời…',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: uiColors.muted,
                    ),
                  ),
                ),
              ),

            // Thanh nhập tin nhắn & Voice Input
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: 12 + media.padding.bottom,
              ),
              decoration: BoxDecoration(
                color: uiColors.surface,
                border: Border(top: BorderSide(color: uiColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _isListeningVoice
                        ? Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: uiColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: uiColors.primary,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Colors.redAccent,
                                  ),
                                  tooltip: 'Hủy ghi âm',
                                  onPressed: () {
                                    _voiceService?.cancelListening();
                                    setState(() {
                                      _isListeningVoice = false;
                                      _voiceSoundLevel = 0.0;
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AnimatedVoiceWaveform(
                                    isListening: true,
                                    soundLevel: _voiceSoundLevel,
                                    height: 24,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Đang nghe...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: uiColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : TextField(
                            key: const Key('assistant_input_field'),
                            controller: _inputController,
                            textInputAction: TextInputAction.send,
                            style: TextStyle(color: uiColors.text),
                            decoration: InputDecoration(
                              hintText: 'Hỏi BatteryBot về pin, sạc, xe...',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: uiColors.muted,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide(color: uiColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide(color: uiColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide(color: uiColors.primary),
                              ),
                            ),
                            onSubmitted: _handleSend,
                          ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    key: const Key('assistant_voice_button'),
                    tooltip: _isListeningVoice
                        ? 'Dừng ghi âm'
                        : 'Giọng nói chưa sẵn sàng. Hãy nhập bằng bàn phím.',
                    icon: Icon(
                      _isListeningVoice
                          ? Icons.stop_circle_rounded
                          : Icons.mic_rounded,
                      color: _isListeningVoice
                          ? Colors.redAccent
                          : uiColors.primary,
                    ),
                    onPressed: VoiceInputService.isSupported
                        ? _toggleVoiceInput
                        : null,
                  ),
                  IconButton(
                    key: const Key('assistant_send_button'),
                    tooltip: 'Gửi tin nhắn',
                    icon: Icon(Icons.send_rounded, color: uiColors.primary),
                    onPressed: () => _handleSend(_inputController.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
