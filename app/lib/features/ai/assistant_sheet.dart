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
  String? _sessionId;
  StreamSubscription<String>? _streamSub;
  final Map<String, bool> _actionLoadingMap = {};
  ProactiveSuggestion? _activeSuggestion;
  VoiceInputService? _voiceService;
  bool _isListeningVoice = false;
  double _voiceSoundLevel = 0.5;

  @override
  void initState() {
    super.initState();
    _startNewChat(preserveGreeting: true);

    // Ghi nhận hành vi truy cập assistant sheet và định danh người dùng
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    try {
      final suggestionService = ref.read(suggestionServiceProvider);
      final canShow = await suggestionService.canShowProactiveBubble();
      if (!canShow) return;

      final vehicle = ref.read(vehicleContextProvider).vehicle;
      final user = FirebaseAuth.instance.currentUser;

      final suggestions = await suggestionService.fetchSuggestions(
        userId: user?.uid ?? 'guest',
        vehicleId: vehicle?.vehicleId,
        currentSoc: vehicle?.currentBattery.toDouble(),
        currentSoh: vehicle?.stateOfHealth.toDouble(),
        odoKm: vehicle?.currentOdo,
      );

      if (suggestions.isNotEmpty && mounted) {
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
    if (msgIndex >= _messages.length) return;

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

      if (!mounted) return;

      final data = (res['data'] as Map<String, dynamic>?) ?? {};
      final message =
          data['message'] as String? ?? 'Đã kích hoạt hành động thành công.';

      setState(() {
        _actionLoadingMap.remove(action.callId);
        final updatedAction = action.copyWith(
          status: 'confirmed',
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionLoadingMap.remove(action.callId);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi khi kích hoạt: $e')));
    }
  }

  Future<void> _handleActionCancel(
    int msgIndex,
    FunctionCallAction action,
  ) async {
    if (msgIndex >= _messages.length) return;

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

    if (_sessionId != null) {
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
    if (msgIndex >= _messages.length) return;
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
      });
      _handleSend(userPrompt);
    }
  }

  void _startNewChat({bool preserveGreeting = false}) {
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
    final loaded = await ref
        .read(chatHistoryStorageProvider)
        .loadSessionMessages(sessionId);
    if (!mounted) return;
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
    final storage = ref.read(chatHistoryStorageProvider);
    final sessions = await storage.listSessions();
    if (!mounted) return;

    final uiColors = AppUiColors.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: uiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
    _streamSub?.cancel();
    _voiceService?.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
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
    final trimmed = rawText.trim();
    if (trimmed.isEmpty || _isTyping) return;

    // Ghi nhận chủ đề câu hỏi vào behavior tracker
    final topic = _detectTopic(trimmed);
    ref
        .read(behaviorTrackerProvider.notifier)
        .trackChatInteraction(topic: topic);

    _inputController.clear();
    final userMsg = ChatMessage(
      id: 'msg-user-${DateTime.now().millisecondsSinceEpoch}',
      role: ChatRole.user,
      content: trimmed,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _isTyping = true;
    });
    _scrollToBottom();

    // 1. Kiểm tra an toàn: nếu chứa thông tin nhạy cảm
    if (_looksSensitive(trimmed)) {
      Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        setState(() {
          _isTyping = false;
          _messages.add(
            ChatMessage(
              id: 'msg-bot-${DateTime.now().millisecondsSinceEpoch}',
              role: ChatRole.model,
              content:
                  'Để bảo vệ an toàn, bạn không nên gửi mật khẩu hay khóa truy cập ở đây. Hãy nhập trực tiếp trong màn hình cài đặt nhé!',
              timestamp: DateTime.now(),
            ),
          );
        });
        _scrollToBottom();
      });
      return;
    }

    // 2. Kiểm tra FAQ action — phản hồi nhanh với nút hành động tương ứng
    final faqAction = BatteryBotFaq.actionFor(trimmed);
    if (faqAction != null) {
      Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        final replyText = switch (faqAction) {
          BatteryBotAction.shellySetup =>
            'Bạn có thể vào trang kết nối Shelly để liên kết bộ sạc qua Wi-Fi hoặc nhập mã 6 ký tự Admin.',
          BatteryBotAction.guideCharging =>
            'Mở tab Sạc pin để kiểm tra trạng thái relay, đặt mức pin mục tiêu (Target SoC) và hẹn giờ sạc an toàn.',
          BatteryBotAction.guideHistory =>
            'Mở tab Lịch sử để xem lại lượng điện tiêu thụ (Wh), chi phí ước tính và thời gian các lần sạc.',
          BatteryBotAction.guideVehicle =>
            'Thông tin pin (% SoC và % SoH chai pin) hiển thị chi tiết tại màn hình Tổng quan.',
        };
        setState(() {
          _isTyping = false;
          _messages.add(
            ChatMessage(
              id: 'msg-faq-${DateTime.now().millisecondsSinceEpoch}',
              role: ChatRole.model,
              content: replyText,
              timestamp: DateTime.now(),
              action: faqAction.name,
              isStreaming: false,
            ),
          );
        });
        _scrollToBottom();

        // Lưu lại lịch sử hội thoại FAQ
        if (_sessionId != null) {
          final storage = ref.read(chatHistoryStorageProvider);
          unawaited(
            storage.saveSessionMessages(_sessionId!, _messages, title: trimmed),
          );
          unawaited(
            storage.backupToCloud(_sessionId!, _messages, title: trimmed),
          );
        }
      });
      return;
    }

    // 3. Chuẩn bị Vehicle Context
    final vehicleContext = ref.read(vehicleContextProvider);
    final vehicle = vehicleContext.vehicle;
    final Map<String, dynamic> vCtx = {
      if (vehicle != null) ...{
        'vehicleId': vehicle.vehicleId,
        'model': vehicle.vehicleName,
        'currentSoc': vehicle.currentBattery,
        'currentSoh': vehicle.stateOfHealth,
        'odoKm': vehicle.currentOdo,
      },
    };

    // 4. Tạo bot message placeholder đang streaming
    final botMsgIndex = _messages.length;
    final botMsgId = 'msg-bot-${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _messages.add(
        ChatMessage(
          id: botMsgId,
          role: ChatRole.model,
          content: '',
          timestamp: DateTime.now(),
          isStreaming: true,
        ),
      );
    });
    _scrollToBottom();

    // 5. Gọi AI Chat Service stream kèm Behavior Profile
    final behaviorProfile = ref.read(behaviorTrackerProvider);
    final chatService = ref.read(chatApiServiceProvider);
    final streamResponse = chatService.streamChat(
      message: trimmed,
      sessionId: _sessionId,
      userId: behaviorProfile.userId.isNotEmpty ? behaviorProfile.userId : null,
      behaviorProfile: behaviorProfile.toJson(),
      vehicleContext: vCtx,
      onFunctionCall: (action) {
        if (!mounted) return;
        setState(() {
          if (botMsgIndex < _messages.length) {
            _messages[botMsgIndex] = _messages[botMsgIndex].copyWith(
              actionCard: action,
            );
          }
        });
        _scrollToBottom();
      },
      onRichCard: (cardData) {
        if (!mounted) return;
        setState(() {
          if (botMsgIndex < _messages.length) {
            final currentCards = _messages[botMsgIndex].richCards != null
                ? List<Map<String, dynamic>>.from(_messages[botMsgIndex].richCards!)
                : <Map<String, dynamic>>[];
            currentCards.add(cardData);
            _messages[botMsgIndex] = _messages[botMsgIndex].copyWith(
              richCards: currentCards,
            );
          }
        });
        _scrollToBottom();
      },
    );

    streamResponse.sessionIdCompleter.future.then((sid) {
      if (sid.isNotEmpty && mounted) {
        _sessionId = sid;
      }
    });

    String accumulated = '';
    _streamSub?.cancel();
    _streamSub = streamResponse.stream.listen(
      (chunk) {
        if (!mounted) return;
        accumulated += chunk;
        setState(() {
          if (botMsgIndex < _messages.length) {
            _messages[botMsgIndex] = _messages[botMsgIndex].copyWith(
              content: accumulated,
            );
          }
        });
        _scrollToBottom();
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _isTyping = false;
          if (botMsgIndex < _messages.length) {
            // Nếu có FAQ fallback action
            final fallbackText = faqAction != null
                ? switch (faqAction) {
                    BatteryBotAction.shellySetup =>
                      'Bạn có thể vào trang kết nối Shelly để liên kết bộ sạc qua Wi-Fi hoặc nhập mã 6 ký tự Admin.',
                    BatteryBotAction.guideCharging =>
                      'Mở tab Sạc pin để kiểm tra trạng thái relay, đặt mức pin mục tiêu (Target SoC) và hẹn giờ sạc an toàn.',
                    BatteryBotAction.guideHistory =>
                      'Mở tab Lịch sử để xem lại lượng điện tiêu thụ (Wh), chi phí ước tính và thời gian các lần sạc.',
                    BatteryBotAction.guideVehicle =>
                      'Thông tin pin (% SoC và % SoH chai pin) hiển thị chi tiết tại màn hình Tổng quan.',
                  }
                : 'Đã xảy ra sự cố khi kết nối tới AI. Bạn vui lòng thử lại sau nhé!';

            _messages[botMsgIndex] = _messages[botMsgIndex].copyWith(
              content: accumulated.isNotEmpty ? accumulated : fallbackText,
              isStreaming: false,
            );
          }
        });
        _scrollToBottom();
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _isTyping = false;
          if (botMsgIndex < _messages.length) {
            // Nếu stream xong mà accumulated rỗng (ví dụ local fallback khi có FAQ)
            String finalContent = accumulated;
            if (finalContent.trim().isEmpty && faqAction != null) {
              finalContent = switch (faqAction) {
                BatteryBotAction.shellySetup =>
                  'Bạn có thể vào trang kết nối Shelly để liên kết bộ sạc qua Wi-Fi hoặc nhập mã 6 ký tự Admin.',
                BatteryBotAction.guideCharging =>
                  'Mở tab Sạc pin để kiểm tra trạng thái relay, đặt mức pin mục tiêu (Target SoC) và hẹn giờ sạc an toàn.',
                BatteryBotAction.guideHistory =>
                  'Mở tab Lịch sử để xem lại lượng điện tiêu thụ (Wh), chi phí ước tính và thời gian các lần sạc.',
                BatteryBotAction.guideVehicle =>
                  'Thông tin pin (% SoC và % SoH chai pin) hiển thị chi tiết tại màn hình Tổng quan.',
              };
            }
            _messages[botMsgIndex] = _messages[botMsgIndex].copyWith(
              content: finalContent,
              isStreaming: false,
            );
          }
        });
        _scrollToBottom();

        // Lưu session vào Local Storage & Cloud Backup
        if (_sessionId != null && _messages.isNotEmpty) {
          final storage = ref.read(chatHistoryStorageProvider);
          final firstUserMsg = _messages.firstWhere(
            (m) => m.role == ChatRole.user,
            orElse: () => _messages.first,
          );
          final title = firstUserMsg.content.length > 30
              ? '${firstUserMsg.content.substring(0, 30)}...'
              : firstUserMsg.content;

          unawaited(
            storage.saveSessionMessages(_sessionId!, _messages, title: title),
          );
          unawaited(
            storage.backupToCloud(_sessionId!, _messages, title: title),
          );
          ref.read(behaviorSyncServiceProvider).scheduleSync();
        }
      },
    );
  }

  void _onFeedback(int index, String rating) {
    if (index >= _messages.length) return;
    final msg = _messages[index];
    setState(() {
      _messages[index] = msg.copyWith(userFeedback: rating);
    });

    ref
        .read(behaviorTrackerProvider.notifier)
        .trackChatInteraction(feedbackRating: rating);

    if (_sessionId != null) {
      ref
          .read(chatApiServiceProvider)
          .sendFeedback(
            sessionId: _sessionId!,
            messageId: msg.id,
            rating: rating,
          );
      final storage = ref.read(chatHistoryStorageProvider);
      unawaited(storage.saveSessionMessages(_sessionId!, _messages));
      unawaited(storage.backupToCloud(_sessionId!, _messages));
      ref.read(behaviorSyncServiceProvider).scheduleSync();
    }
  }

  void _executeAction(BatteryBotAction action) {
    Navigator.of(context).pop(); // Đóng bottom sheet

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
        Navigator.of(context).push(
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

    final sheetHeight = MediaQuery.of(context).size.height * 0.72;

    return Container(
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'BatteryBot Copilot',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: uiColors.text,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: uiColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'AI Trợ lý',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: uiColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        vehicle != null
                            ? '${vehicle.vehicleName} • Pin ${vehicle.currentBattery}%'
                            : 'Chưa chọn xe theo dõi',
                        style: TextStyle(fontSize: 11.5, color: uiColors.muted),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('assistant_history_button'),
                  icon: Icon(Icons.history_rounded, color: uiColors.muted, size: 20),
                  tooltip: 'Lịch sử chat',
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  onPressed: _showHistoryModal,
                ),
                IconButton(
                  key: const Key('assistant_new_chat_button'),
                  icon: Icon(Icons.add_comment_outlined, color: uiColors.muted, size: 20),
                  tooltip: 'Đoạn chat mới',
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  onPressed: () => _startNewChat(),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: uiColors.muted, size: 20),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Quick Action Chips
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'BatteryBot đang suy nghĩ...',
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
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
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
                            border: Border.all(color: uiColors.primary, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
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
                            hintStyle: TextStyle(fontSize: 13, color: uiColors.muted),
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
                  tooltip: _isListeningVoice ? 'Dừng ghi âm' : 'Nhập bằng giọng nói tiếng Việt',
                  icon: Icon(
                    _isListeningVoice ? Icons.stop_circle_rounded : Icons.mic_rounded,
                    color: _isListeningVoice ? Colors.redAccent : uiColors.primary,
                  ),
                  onPressed: _toggleVoiceInput,
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
    );
  }
}
