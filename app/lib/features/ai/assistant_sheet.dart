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
import '../../core/theme/luxe_theme.dart';
import '../../core/utils/battery_bot_faq.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/battery_bot_mascot.dart';
import '../settings/assistant_memory_screen.dart';
import '../smart_charging/shelly_connect_screen.dart';
import '../../data/services/shelly_connection_coordinator.dart';
import 'dashboard_scan_screen.dart';
import 'models/chat_message.dart';
import 'models/chat_session.dart';
import 'models/function_call_action.dart';
import 'models/proactive_suggestion.dart';
import 'services/behavior_sync_service.dart';
import 'services/behavior_tracker.dart';
import 'services/chat_api_service.dart';
import 'services/local_chat_engine.dart';
import 'services/chat_history_storage.dart';
import 'services/suggestion_service.dart';
import 'services/voice_input_service.dart';
import 'widgets/animated_voice_waveform.dart';
import 'widgets/battery_reading_sheet.dart';
import 'widgets/chat_message_bubble.dart';
import 'widgets/quick_reply_chips.dart';

/// Bottom Sheet trò chuyện cùng trợ lý ảo BatteryBot với AI Streaming & Lịch sử
class InteractiveAssistantSheet extends ConsumerStatefulWidget {
  const InteractiveAssistantSheet({
    super.key,
    this.initialQuery,
    this.dashboardReader,
  });

  final String? initialQuery;

  /// Dashboard photo reader (Task 127); injectable for tests.
  final DashboardReadFn? dashboardReader;

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
  bool _historyOpening = false;
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
    bool idle() =>
        _isCurrent(generation) &&
        _messages.length == 1 &&
        !_isTyping &&
        _inputController.text.trim().isEmpty;
    try {
      final suggestionService = ref.read(suggestionServiceProvider);
      final canShow = await suggestionService.canShowProactiveBubble();
      if (!canShow || !idle()) return;

      final vehicle = ref.read(vehicleContextProvider).vehicle;
      final user = Firebase.apps.isEmpty
          ? null
          : FirebaseAuth.instance.currentUser;

      final suggestions = await suggestionService.fetchSuggestions(
        userId: user?.uid ?? 'guest',
        vehicleId: vehicle?.vehicleId,
        currentSoc: vehicle?.hasBatteryData == true
            ? vehicle!.currentBattery.toDouble()
            : null,
        currentSoh: vehicle?.hasSohData == true
            ? vehicle!.stateOfHealth.toDouble()
            : null,
        odoKm: vehicle?.hasOdoData == true ? vehicle!.currentOdo : null,
      );

      if (suggestions.isNotEmpty && idle()) {
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
          : (res['message'] as String? ??
                'Chưa thực hiện được. Hãy kiểm tra tại màn hình tương ứng.');

      setState(() {
        _actionLoadingMap.remove(action.callId);
        final updatedAction = action.copyWith(
          status: succeeded
              ? 'confirmed'
              : (res['status'] == 'unknown' ? 'unknown' : 'failed'),
          resultMessage: message,
        );
        _messages[msgIndex] = _messages[msgIndex].copyWith(
          actionCard: updatedAction,
        );
      });

      if (succeeded) {
        ref
            .read(behaviorTrackerProvider.notifier)
            .trackChatInteraction(topic: 'action_confirmed_${action.toolName}');
      }

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
              'Chào bạn, mình hỗ trợ về xe, pin, sạc và Shelly. Bạn muốn xem gì?',
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
    if (!_isCurrent(generation)) return;
    _isTyping = false;
    List<ChatMessage> loaded;
    try {
      loaded = await ref
          .read(chatHistoryStorageProvider)
          .loadSessionMessages(sessionId);
    } catch (_) {
      if (!mounted || !_isCurrent(generation)) return;
      setState(() => _isTyping = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa mở được cuộc trò chuyện. Hãy thử lại.'),
        ),
      );
      return;
    }
    if (!_isCurrent(generation)) return;
    if (loaded.isNotEmpty) {
      setState(() {
        _sessionId = sessionId;
        _messages.clear();
        _messages.addAll(loaded);
      });
      _scrollToBottom();
    } else {
      setState(() => _isTyping = false);
    }
  }

  Future<void> _showHistoryModal() async {
    if (_historyOpening) return;
    _historyOpening = true;
    try {
      await _openHistoryModal();
    } finally {
      _historyOpening = false;
      _historyModalContext = null;
    }
  }

  Future<void> _openHistoryModal() async {
    final generation = _generation;
    final storage = ref.read(chatHistoryStorageProvider);
    List<ChatSession> sessions;
    try {
      sessions = await storage.listSessions();
    } catch (_) {
      if (!mounted || !_isCurrent(generation)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Chưa tải được lịch sử trò chuyện.'),
          action: SnackBarAction(
            label: 'Thử lại',
            onPressed: _showHistoryModal,
          ),
        ),
      );
      return;
    }
    if (!mounted || !_isCurrent(generation)) return;

    const uiColors = _LuxePalette();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0C0D0F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: LuxeColors.hairline),
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
                    Text(
                      'Lịch sử lưu trên máy này.',
                      style: TextStyle(color: uiColors.muted),
                    ),
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
                                tooltip: 'Xóa cuộc trò chuyện trên máy này',
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: uiColors.muted,
                                ),
                                onPressed: () async {
                                  try {
                                    await storage.deleteSession(sess.id);
                                  } catch (_) {
                                    if (!ctx.mounted ||
                                        !mounted ||
                                        !_isCurrent(generation)) {
                                      return;
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Chưa xóa được lịch sử trên máy này. Hãy thử lại.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  if (!ctx.mounted ||
                                      !mounted ||
                                      !_isCurrent(generation)) {
                                    return;
                                  }
                                  setModalState(() {
                                    sessions.removeWhere(
                                      (item) => item.id == sess.id,
                                    );
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

  /// What BatteryBot remembers and the learning switch live on one screen
  /// (Task 124 server memory); the old dialog described the retired
  /// on-device tracker and a second switch (Task 125).
  Future<void> _showPersonalization() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AssistantMemoryScreen()),
    );
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

  bool _looksSensitive(String text) => BatteryBotLocalEngine.isSensitive(text);

  bool _readingDashboard = false;

  /// Task 127: read the dashboard on the phone and put the numbers in the
  /// input for the owner to check and send; BatteryBot then offers the
  /// one-tap "cập nhật pin / ODO" cards. Nothing is sent automatically.
  Future<void> _readDashboardPhoto() async {
    setState(() => _readingDashboard = true);
    try {
      final injected = widget.dashboardReader;
      final vehicle = ref.read(vehicleContextProvider).vehicle;
      final scan = injected != null
          ? injected(camera: true)
          : scanDashboard(
              context,
              lastOdoKm: vehicle?.hasOdoData == true
                  ? vehicle!.currentOdo.toDouble()
                  : null,
            );
      final reading = await scan;
      if (!mounted || reading == null) return;
      if (reading.isEmpty) {
        AppPopup.showInfo(
          'Chưa đọc được số nào',
          detail: 'Quét gần, thẳng, tránh lóa hoặc gõ số trên đồng hồ.',
        );
        return;
      }
      final odo = reading.odoKm;
      final parts = [
        if (reading.soc != null) 'pin ${reading.soc}%',
        if (odo != null)
          'ODO ${odo == odo.roundToDouble() ? odo.round() : odo.toStringAsFixed(1)} km',
      ];
      _inputController.text =
          'Đồng hồ xe đang báo ${parts.join(', ')} (quét từ đồng hồ). Cập nhật giúp mình.';
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
    } on Object {
      if (mounted) {
        AppPopup.showInfo(
          'Không đọc được ảnh',
          detail: 'Hãy thử lại hoặc gõ số trên đồng hồ.',
        );
      }
    } finally {
      if (mounted) setState(() => _readingDashboard = false);
    }
  }

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
      _activeSuggestion = null;
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
    // Task 124: every question goes to the assistant engine (Gemini with
    // the on-device basic mode as fallback); no canned FAQ short-circuit.
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
        // Basic mode (no AI): keep the offline shortcut button to the screen.
        final basicMode =
            accumulated.startsWith('Chế độ cơ bản') ||
            accumulated.startsWith('Bạn đã dùng hết lượt AI');
        final shortcut = basicMode ? BatteryBotFaq.actionFor(text) : null;
        setState(() {
          _isTyping = false;
          _messages[index] = _messages[index].copyWith(
            content: accumulated.isEmpty
                ? 'Chưa nhận được câu trả lời. Hãy thử lại.'
                : accumulated,
            isStreaming: false,
            hasError: accumulated.isEmpty,
            action: shortcut?.name,
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
    } catch (_) {
      accepted = false;
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
        .replaceChatFeedback(previous: message.userFeedback, rating: rating);
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
    final accent = isHigh ? LuxeColors.champagne : LuxeColors.emerald;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isHigh
                ? Icons.warning_amber_rounded
                : Icons.tips_and_updates_outlined,
            color: accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: LuxeColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.message,
                  style: LuxeText.caption.copyWith(fontSize: 12.5),
                ),
                if (s.action != null && s.action!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => _applySuggestion(s),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Xem gợi ý',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: accent,
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
            tooltip: 'Ẩn gợi ý',
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: LuxeColors.muted,
            ),
            onPressed: _dismissActiveSuggestion,
          ),
        ],
      ),
    );
  }

  Widget _bubble(int index, {bool showMeta = true}) {
    final message = _messages[index];
    return ChatMessageBubble(
      message: message,
      showMeta: showMeta,
      onFeedback: (rating) => _onFeedback(index, rating),
      onActionPressed: _executeAction,
      isActionLoading: _actionLoadingMap[message.actionCard?.callId] ?? false,
      onConfirmAction: (act) => _handleActionConfirm(index, act),
      onCancelAction: (act) => _handleActionCancel(index, act),
      onRetry: () => _handleRetry(index),
    );
  }

  ButtonStyle get _glassIcon => IconButton.styleFrom(
    backgroundColor: LuxeColors.glass,
    foregroundColor: LuxeColors.text,
    side: const BorderSide(color: LuxeColors.hairline),
    fixedSize: const Size(48, 48),
    minimumSize: const Size(48, 48),
  );

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
        (media.size.height - keyboard - media.padding.top) * 0.94;
    // Fresh conversation: a welcome hero with suggestion cards replaces the
    // chip row, so each suggestion appears exactly once on screen.
    final welcome = _messages.length <= 1 && !_isTyping;

    return Theme(
      data: LuxeTheme.of(context),
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Container(
          height: sheetHeight,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            color: LuxeColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            border: Border(top: BorderSide(color: LuxeColors.hairlineStrong)),
            boxShadow: [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 30,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const LuxeBackdrop(),
              LayoutBuilder(
                builder: (context, box) => Column(
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 4),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: LuxeColors.hairlineStrong,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Header: mascot, name, close; then vehicle chip + tools.
                    // Capped and scrollable so a long vehicle name, large text
                    // and the keyboard never push the input dock off screen.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: box.maxHeight * (keyboard > 0 ? 0.28 : 0.45),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 6, 10, 8),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: LuxeColors.emerald.withValues(
                                        alpha: 0.55,
                                      ),
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x2834D399),
                                        blurRadius: 16,
                                      ),
                                    ],
                                  ),
                                  child: const BatteryBotMascot(
                                    size: BatteryBotSize.avatar,
                                    displayMode: BatteryBotDisplayMode.avatar,
                                    mood: BatteryBotMood.happy,
                                    enableFloating: false,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Pinova Bot',
                                        style: TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w500,
                                          color: LuxeColors.text,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Trợ lý pin & sạc cá nhân',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: LuxeColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  key: const Key('assistant_close_button'),
                                  tooltip: 'Đóng Pinova Bot',
                                  style: _glassIcon,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                  ),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      color: LuxeColors.glass,
                                      border: Border.all(
                                        color: LuxeColors.hairline,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.two_wheeler_rounded,
                                          size: 18,
                                          color: LuxeColors.emerald,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                vehicle?.displayName ??
                                                    'Chưa chọn xe theo dõi',
                                                key: const Key(
                                                  'assistant_vehicle_label',
                                                ),
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: LuxeColors.text,
                                                ),
                                              ),
                                              Text(
                                                vehicle == null ||
                                                        !vehicle.hasBatteryData
                                                    ? 'Chưa có dữ liệu pin'
                                                    : 'Pin ${vehicle.currentBattery}% · Dữ liệu hồ sơ',
                                                key: const Key(
                                                  'assistant_battery_source',
                                                ),
                                                // User-entered, not verified:
                                                // champagne, not emerald.
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  color: LuxeColors.champagne,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  key: const Key('assistant_history_button'),
                                  tooltip: 'Lịch sử chat',
                                  style: _glassIcon,
                                  icon: const Icon(
                                    Icons.history_rounded,
                                    size: 20,
                                  ),
                                  onPressed: _showHistoryModal,
                                ),
                                IconButton(
                                  key: const Key(
                                    'assistant_personalization_button',
                                  ),
                                  tooltip: 'Cá nhân hóa và dữ liệu học',
                                  style: _glassIcon,
                                  icon: const Icon(
                                    Icons.tune_rounded,
                                    size: 20,
                                  ),
                                  onPressed: _showPersonalization,
                                ),
                                IconButton(
                                  key: const Key('assistant_new_chat_button'),
                                  tooltip: 'Đoạn chat mới',
                                  style: _glassIcon,
                                  icon: const Icon(
                                    Icons.add_comment_outlined,
                                    size: 20,
                                  ),
                                  onPressed: () => _startNewChat(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    if (keyboard == 0 && !welcome)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: QuickReplyChips(
                          customSuggestions: chips,
                          currentSoc: vehicle?.currentBattery.toDouble(),
                          isCharging:
                              ShellyConnectionCoordinator
                                  .shared
                                  .current
                                  .status
                                  ?.relay ==
                              true,
                          onSelect: (chipText) => _handleSend(chipText),
                        ),
                      ),
                    Expanded(
                      child: welcome
                          // Fresh chat: everything is built at once so the
                          // greeting and the first suggestions stay in view.
                          ? SingleChildScrollView(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                              child: Column(
                                children: [
                                  if (_activeSuggestion != null)
                                    _buildProactiveBanner(uiColors),
                                  const _WelcomeHeader(),
                                  for (var i = 0; i < _messages.length; i++)
                                    _bubble(i, showMeta: false),
                                  _SuggestionCards(
                                    suggestions: chips,
                                    onSelect: _handleSend,
                                  ),
                                ],
                              ),
                            )
                          // Soft top edge under the suggestion row: items
                          // scrolling past it fade instead of being cut in
                          // half mid-icon (QA 129).
                          : ShaderMask(
                              blendMode: BlendMode.dstIn,
                              shaderCallback: (rect) => const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black],
                                stops: [0, 0.06],
                              ).createShader(rect),
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  0,
                                  16,
                                  0,
                                  12,
                                ),
                                itemCount:
                                    _messages.length +
                                    (_activeSuggestion != null ? 1 : 0),
                                itemBuilder: (context, raw) {
                                  final banner = _activeSuggestion != null;
                                  if (banner && raw == 0) {
                                    return _buildProactiveBanner(uiColors);
                                  }
                                  return _bubble(banner ? raw - 1 : raw);
                                },
                              ),
                            ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      // The streaming reply bubble already shows the
                      // "preparing" dots; never draw a second indicator.
                      child:
                          _isTyping &&
                              !(_messages.isNotEmpty &&
                                  _messages.last.isStreaming)
                          ? const Padding(
                              padding: EdgeInsets.fromLTRB(20, 2, 20, 6),
                              child: Row(
                                children: [
                                  _TypingDot(),
                                  SizedBox(width: 10),
                                  Text(
                                    'Đang chuẩn bị câu trả lời…',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontStyle: FontStyle.italic,
                                      color: LuxeColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    // Input dock: one glass capsule holding field, mic and send.
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        6,
                        12,
                        12 + media.padding.bottom,
                      ),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF1A1B1E), Color(0xFF111214)],
                          ),
                          border: Border.all(
                            color: _isListeningVoice
                                ? LuxeColors.emerald
                                : LuxeColors.hairlineStrong,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _isListeningVoice
                                  ? SizedBox(
                                      height: 48,
                                      child: Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                              color: LuxeColors.danger,
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
                                          Expanded(
                                            child: AnimatedVoiceWaveform(
                                              isListening: true,
                                              soundLevel: _voiceSoundLevel,
                                              height: 24,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Đang nghe...',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: LuxeColors.emerald,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : TextField(
                                      key: const Key('assistant_input_field'),
                                      controller: _inputController,
                                      textInputAction: TextInputAction.send,
                                      minLines: 1,
                                      maxLines: 4,
                                      style: const TextStyle(
                                        color: LuxeColors.text,
                                        fontSize: 15,
                                      ),
                                      decoration: const InputDecoration(
                                        hintText:
                                            'Hỏi Pinova Bot về pin, sạc, xe...',
                                        hintMaxLines: 1,
                                        hintStyle: TextStyle(
                                          fontSize: 14,
                                          color: LuxeColors.dim,
                                        ),
                                        filled: false,
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                      ),
                                      onSubmitted: _handleSend,
                                    ),
                            ),
                            if (!_isListeningVoice)
                              IconButton(
                                key: const Key('assistant_photo_button'),
                                tooltip: 'Quét đồng hồ xe để đọc % pin và ODO',
                                icon: const Icon(
                                  Icons.photo_camera_outlined,
                                  color: LuxeColors.platinumMid,
                                ),
                                onPressed: _isTyping || _readingDashboard
                                    ? null
                                    : _readDashboardPhoto,
                              ),
                            if (VoiceInputService.isSupported ||
                                _isListeningVoice)
                              IconButton(
                                key: const Key('assistant_voice_button'),
                                tooltip: _isListeningVoice
                                    ? 'Dừng ghi âm'
                                    : 'Giọng nói chưa sẵn sàng. Hãy nhập bằng bàn phím.',
                                icon: Icon(
                                  _isListeningVoice
                                      ? Icons.stop_circle_rounded
                                      : Icons.mic_none_rounded,
                                  color: _isListeningVoice
                                      ? LuxeColors.danger
                                      : LuxeColors.platinumMid,
                                ),
                                onPressed: VoiceInputService.isSupported
                                    ? _toggleVoiceInput
                                    : null,
                              ),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _inputController,
                              builder: (context, value, _) {
                                final ready =
                                    value.text.trim().isNotEmpty && !_isTyping;
                                return IconButton(
                                  key: const Key('assistant_send_button'),
                                  tooltip: _isTyping
                                      ? 'Đang chờ Pinova Bot trả lời'
                                      : 'Gửi tin nhắn',
                                  style: IconButton.styleFrom(
                                    fixedSize: const Size(48, 48),
                                    backgroundColor: ready
                                        ? LuxeColors.platinumHi
                                        : const Color(0xFF232427),
                                    foregroundColor: ready
                                        ? const Color(0xFF0B0C0E)
                                        : LuxeColors.dim,
                                  ),
                                  icon: const Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 22,
                                  ),
                                  onPressed: _isTyping
                                      ? null
                                      : () =>
                                            _handleSend(_inputController.text),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Welcome header for a fresh conversation: mascot and a calm title.
class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
    child: Column(
      children: [
        LuxeReveal(
          child: BatteryBotMascot(
            size: BatteryBotSize.sm,
            mood: BatteryBotMood.happy,
          ),
        ),
        SizedBox(height: 8),
        LuxeReveal(
          index: 1,
          child: Column(
            children: [
              Text('TRỢ LÝ PIN CÁ NHÂN', style: LuxeText.eyebrow),
              SizedBox(height: 4),
              Text(
                'Mình có thể giúp gì?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: LuxeColors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One glass card per suggestion, shown under the greeting.
class _SuggestionCards extends StatelessWidget {
  const _SuggestionCards({required this.suggestions, required this.onSelect});
  final List<String> suggestions;
  final ValueChanged<String> onSelect;
  static IconData _iconFor(String text) {
    final t = text.toLowerCase();
    if (t.contains('dừng') || t.contains('tắt')) {
      return Icons.power_settings_new_rounded;
    }
    if (t.contains('shelly') || t.contains('kết nối')) {
      return Icons.power_rounded;
    }
    if (t.contains('khóa')) return Icons.lock_outline_rounded;
    if (t.contains('pin')) return Icons.battery_5_bar_rounded;
    if (t.contains('lịch') || t.contains('giờ')) return Icons.schedule_rounded;
    return Icons.auto_awesome_rounded;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    child: LayoutBuilder(
      builder: (context, box) {
        final big = MediaQuery.textScalerOf(context).scale(14) > 20;
        final columns = big || box.maxWidth < 300 ? 1 : 2;
        final w = (box.maxWidth - 10 * (columns - 1)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < suggestions.length; i++)
              SizedBox(
                width: w,
                child: LuxeReveal(
                  index: i + 2,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => onSelect(suggestions[i]),
                      child: LuxeGlass(
                        radius: 18,
                        padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _iconFor(suggestions[i]),
                              size: 20,
                              color: LuxeColors.emerald,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              suggestions[i],
                              style: const TextStyle(
                                color: LuxeColors.text,
                                fontSize: 14,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// Emerald dot that breathes while BatteryBot is preparing an answer. It is
/// only mounted during typing, so the loop never outlives the reply.
class _TypingDot extends StatefulWidget {
  const _TypingDot();

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) && !_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
    child: Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: LuxeColors.emerald,
        boxShadow: [BoxShadow(color: LuxeColors.emeraldGlow, blurRadius: 8)],
      ),
    ),
  );
}

/// Luxe colours for the history sheet (same names as [AppUiColors]).
class _LuxePalette {
  const _LuxePalette();
  Color get surface => const Color(0xFF0C0D0F);
  Color get background => const Color(0xFF17181B);
  Color get primary => LuxeColors.emerald;
  Color get text => LuxeColors.text;
  Color get muted => LuxeColors.muted;
}
