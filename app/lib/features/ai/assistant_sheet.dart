import 'package:shared_preferences/shared_preferences.dart';
import '../settings/about_screen.dart';
import '../tips/tip_library.dart';
import 'assistant_settings_screen.dart';
import 'bot_release.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_state_providers.dart';
import '../../core/providers/vehicle_context_provider.dart';
import '../../core/services/assistant_context_coordinator.dart';
import '../../core/services/voice_bridge.dart';
import '../../core/theme/app_ui_colors.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/utils/battery_bot_faq.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/battery_bot_mascot.dart';
import '../smart_charging/shelly_connect_screen.dart';
import '../../data/services/shelly_connection_coordinator.dart';
import 'dashboard_scan_screen.dart';
import 'models/chat_message.dart';
import 'models/chat_session.dart';
import 'models/function_call_action.dart';
import 'models/proactive_suggestion.dart';
import 'services/assistant_api.dart';
import 'services/behavior_sync_service.dart';
import 'services/behavior_tracker.dart';
import 'services/chat_api_service.dart';
import 'services/local_chat_engine.dart';
import 'services/chat_history_storage.dart';
import 'services/suggestion_service.dart';
import 'services/voice_input_service.dart';
import 'widgets/battery_reading_sheet.dart';
import 'widgets/chat_history_sheet.dart';
import 'widgets/chat_message_bubble.dart';
import 'widgets/quick_reply_chips.dart';
import '../../core/services/guide_registry.dart';
import '../../core/services/screen_tour.dart';
import '../premium/plan_tag.dart';
import '../premium/premium_gate.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/entitlement.dart';
import '../../core/providers/entitlement_provider.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/theme/plan_style.dart';

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
      barrierColor: luxeSheetBarrier,
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

  /// QA 150: closing the sheet and opening it again started a new chat and
  /// lost the thread. The last conversation of this account stays for 30
  /// minutes (in memory only; the saved history is unchanged).
  static ({
    String uid,
    String sessionId,
    List<ChatMessage> messages,
    DateTime at,
  })?
  _recent;
  static const _recentFor = Duration(minutes: 30);

  bool _restoreRecent() {
    final recent = _recent;
    final uid = _ownerUid;
    final query = widget.initialQuery;
    if (recent == null || uid == null || recent.uid != uid) return false;
    if (query != null && query.trim().isNotEmpty) return false;
    if (DateTime.now().difference(recent.at) > _recentFor) return false;
    _generation++;
    _sessionId = recent.sessionId;
    _messages
      ..clear()
      ..addAll(recent.messages);
    ref.read(chatApiServiceProvider).startConversation(recent.messages);
    return true;
  }

  void _keepRecent() {
    final uid = _ownerUid;
    final session = _sessionId;
    if (uid == null || session == null || _isTyping) return;
    if (!_messages.any((m) => m.role == ChatRole.user)) return;
    _recent = (
      uid: uid,
      sessionId: session,
      messages: List.of(_messages),
      at: DateTime.now(),
    );
  }

  bool _isTyping = false;

  /// QA 164: the reply being written (index in [_messages]) and what Pinova
  /// Bot is reading for it; the streamed text shows there until the final,
  /// checked reply replaces it.
  int? _liveIndex;
  String? _liveStatus;

  /// QA 164: a photo to send with the next question (Pro/Ultra), and the
  /// photos sent in this visit (memory only; never stored).
  Uint8List? _pendingImage;
  String _pendingMime = 'image/jpeg';
  final Map<String, Uint8List> _photos = {};

  /// The relay takes 512 KB bodies; base64 adds a third.
  static const _maxPhotoBytes = 340 * 1024;

  Future<void> _openAttachMenu() async {
    await showLuxeSheet<void>(
      context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LuxeSheetHeader(title: 'Gửi cho Pinova Bot'),
              LuxeSettingsGroup(
                children: [
                  LuxeSettingsRow(
                    key: const ValueKey('attach-scan'),
                    icon: Icons.document_scanner_rounded,
                    title: 'Quét đồng hồ xe',
                    subtitle: 'Đọc % pin và ODO, bạn xem lại trước khi lưu',
                    onTap: () {
                      Navigator.of(sheet).pop();
                      unawaited(_readDashboardPhoto());
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              PremiumLocked(
                feature: PremiumFeature.assistantImage,
                reserveTagSpace: true,
                child: LuxeSettingsGroup(
                  children: [
                    LuxeSettingsRow(
                      key: const ValueKey('attach-camera'),
                      icon: Icons.photo_camera_rounded,
                      title: 'Chụp ảnh hỏi Pinova Bot',
                      subtitle: 'Đèn báo trên đồng hồ, bộ sạc, ổ Shelly',
                      onTap: () {
                        Navigator.of(sheet).pop();
                        unawaited(_pickPhoto(ImageSource.camera));
                      },
                    ),
                    LuxeSettingsRow(
                      key: const ValueKey('attach-gallery'),
                      icon: Icons.photo_library_rounded,
                      title: 'Chọn ảnh có sẵn',
                      subtitle: 'Ảnh chỉ gửi kèm câu hỏi, không được lưu',
                      onTap: () {
                        Navigator.of(sheet).pop();
                        unawaited(_pickPhoto(ImageSource.gallery));
                      },
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

  Future<void> _pickPhoto(ImageSource source) async {
    XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70,
      );
    } on Object {
      file = null;
      AppPopup.showInfo('Chưa mở được máy ảnh hoặc thư viện ảnh');
    }
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > _maxPhotoBytes) {
      AppPopup.showInfo(
        'Ảnh còn quá lớn',
        detail: 'Hãy chụp lại gần hơn hoặc chọn ảnh khác.',
      );
      return;
    }
    final name = file.name.toLowerCase();
    setState(() {
      _pendingImage = bytes;
      _pendingMime = name.endsWith('.png')
          ? 'image/png'
          : name.endsWith('.webp')
          ? 'image/webp'
          : 'image/jpeg';
    });
  }

  void _onLive() {
    final index = _liveIndex;
    if (!mounted || index == null || index >= _messages.length) return;
    final message = _messages[index];
    if (!message.isStreaming) return;
    final text = AssistantSignals.liveText.value;
    final status = AssistantSignals.liveStatus.value;
    if (text == message.content && status == _liveStatus) return;
    setState(() {
      _liveStatus = status;
      _messages[index] = message.copyWith(content: text);
    });
    if (text.isNotEmpty) _scrollToBottom();
  }

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

  /// QA 163: first open of Pinova Bot on this phone (the short intro), and
  /// the bot version this phone last showed ("vừa được nâng cấp").
  bool _introSeen = true;
  bool _upgraded = false;

  /// QA 163: the questions offered under a reply, by message id.
  final Map<String, List<String>> _followUps = {};

  /// QA 151: the face in the header follows the conversation.
  BatteryBotMood get _headerMood {
    if (_isListeningVoice) return BatteryBotMood.listening;
    if (_isTyping) return BatteryBotMood.thinking;
    if (_messages.isNotEmpty && _messages.last.hasError) {
      return BatteryBotMood.sorry;
    }
    return BatteryBotMood.happy;
  }

  @override
  void initState() {
    super.initState();
    _ownerUid = _currentUid();
    AssistantSignals.liveText.addListener(_onLive);
    AssistantSignals.liveStatus.addListener(_onLive);
    unawaited(_loadFirstRun());
    if (_restoreRecent()) {
      _scrollToBottom();
    } else {
      _startNewChat(preserveGreeting: true);
    }
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
      // QA 135: the first open explains what to ask and the scan button.
      ScreenTour.maybeShow(
        context,
        ScreenTour.bot,
        GuideRegistry.botTourSteps(),
      );
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
      // QA 149: no "low battery" card while the vehicle charges.
      final live = vehicle == null
          ? null
          : ref.read(chargingEstimateProvider(vehicle.vehicleId));

      final suggestions = await suggestionService.fetchSuggestions(
        userId: user?.uid ?? 'guest',
        vehicleId: vehicle?.vehicleId,
        chargingStatus: live != null ? 'charging' : null,
        currentSoc: live != null
            ? live.toDouble()
            : vehicle?.hasBatteryData == true
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
      AppPopup.showMessage(
        'Chưa thực hiện được. Hãy kiểm tra tại màn hình Sạc pin.',
        kind: AppNoticeKind.error,
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

  /// QA 164: the system's speech screen; what was said goes into the box
  /// for the owner to check and send (a spoken command never runs alone).
  Future<void> _toggleVoiceInput() async {
    if (_isTyping || _isListeningVoice) return;
    setState(() => _isListeningVoice = true);
    String? said;
    try {
      said = await VoiceBridge.listen();
    } on VoiceUnavailable {
      AppPopup.showInfo(
        'Máy chưa nhận được giọng nói',
        detail: 'Bật ứng dụng Google trên máy để nói với Pinova Bot.',
      );
    }
    if (!mounted) return;
    setState(() => _isListeningVoice = false);
    final text = said?.trim() ?? '';
    if (text.isEmpty) return;
    final current = _inputController.text.trim();
    _inputController.text = current.isEmpty ? text : '$current $text';
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
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
    _recent = null;
    _generation++;
    _replyTimer?.cancel();
    _streamSub?.cancel();
    _isTyping = false;
    _activeSuggestion = null;
    _actionLoadingMap.clear();
    // QA 164: a new chat no longer sends the last one to the server.
    ref.read(chatApiServiceProvider).startConversation(const []);
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
      AppPopup.showMessage(
        'Chưa mở được cuộc trò chuyện. Hãy thử lại.',
        kind: AppNoticeKind.error,
      );
      return;
    }
    if (!_isCurrent(generation)) return;
    if (loaded.isNotEmpty) {
      // QA 164: an old conversation opened again is the context again.
      ref.read(chatApiServiceProvider).startConversation(loaded);
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
      AppPopup.showMessage(
        'Chưa tải được lịch sử trò chuyện.',
        kind: AppNoticeKind.error,
        action: _showHistoryModal,
      );
      return;
    }
    if (!mounted || !_isCurrent(generation)) return;
    // QA 164: search, days, rename, delete with undo (widgets/chat_history_sheet).
    await showLuxeSheet<void>(
      context,
      builder: (modalCtx) {
        _historyModalContext = modalCtx;
        return ChatHistorySheet(
          sessions: sessions,
          storage: storage,
          currentId: _sessionId,
          onOpen: (id) {
            Navigator.of(modalCtx).pop();
            if (id != _sessionId) _loadSession(id);
          },
          onNewChat: () {
            Navigator.of(modalCtx).pop();
            _startNewChat();
          },
          onDeleted: (id) {
            if (!mounted || !_isCurrent(generation)) return;
            if (id == _sessionId) _startNewChat();
          },
        );
      },
    );
  }

  @override
  void dispose() {
    AssistantSignals.liveText.removeListener(_onLive);
    AssistantSignals.liveStatus.removeListener(_onLive);
    _keepRecent();
    _generation++;
    _replyTimer?.cancel();
    _authSubscription?.cancel();
    _streamSub?.cancel();
    _voiceService?.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFirstRun() async {
    var introSeen = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      introSeen = prefs.getBool(AssistantSettingsScreen.introSeenKey) ?? false;
    } on Object {
      introSeen = true; // no storage: no intro to nag with
    }
    final seenVersion = await PinovaBotRelease.seen();
    if (!mounted) return;
    setState(() {
      _introSeen = introSeen;
      // A first-time owner gets the intro, not "upgraded".
      _upgraded =
          introSeen &&
          seenVersion != null &&
          seenVersion != PinovaBotRelease.current;
    });
    if (!introSeen || seenVersion == null) {
      unawaited(PinovaBotRelease.markSeen());
    }
  }

  Future<void> _finishIntro() async {
    setState(() => _introSeen = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AssistantSettingsScreen.introSeenKey, true);
    } on Object {
      // Shown again next time; harmless.
    }
  }

  Future<void> _openUpgradeNotes() async {
    setState(() => _upgraded = false);
    await PinovaBotRelease.markSeen();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen()));
  }

  /// QA 163: stop the reply being written; what came so far stays.
  void _stopReply() {
    if (!_isTyping) return;
    unawaited(_streamSub?.cancel());
    _streamSub = null;
    final index = _messages.lastIndexWhere((m) => m.isStreaming);
    setState(() {
      _isTyping = false;
      _liveIndex = null;
      _liveStatus = null;
      if (index >= 0) {
        final text = _messages[index].content.trim();
        _messages[index] = _messages[index].copyWith(
          content: text.isEmpty ? 'Đã dừng trả lời.' : '$text\n\n(đã dừng)',
          isStreaming: false,
        );
      }
    });
    _persistConversation();
  }

  /// QA 163: ask the last question again (the last reply is replaced).
  void _askAgain(int index) {
    if (_isTyping || index != _messages.length - 1) return;
    final question = _messages
        .take(index)
        .lastWhere(
          (m) => m.role == ChatRole.user,
          orElse: () => ChatMessage(
            id: '',
            role: ChatRole.user,
            content: '',
            timestamp: DateTime.now(),
          ),
        );
    if (question.content.trim().isEmpty) return;
    final userIndex = _messages.lastIndexOf(question);
    setState(() {
      _followUps.remove(_messages[index].id);
      _messages.removeRange(userIndex, _messages.length);
    });
    _handleSend(question.content);
  }

  /// QA 163: what a new owner is most likely to ask now, each with its own
  /// icon (they used to be guessed from the words).
  List<(String, IconData)> _starters({
    required bool hasVehicle,
    required int? battery,
    required bool charging,
  }) {
    final shelly = ShellyConnectionCoordinator.shared.current;
    final list = <(String, IconData)>[
      if (charging) ('Khi nào sạc xong?', Icons.schedule_rounded),
      if (!charging && battery != null && battery < 30)
        ('Sạc lên 80% mất bao lâu?', Icons.bolt_rounded),
      if (!shelly.isLinked) ('Kết nối Shelly', Icons.power_rounded),
      ('Mẹo đi xe tiết kiệm pin', Icons.lightbulb_rounded),
    ];
    for (final (text, icon) in const [
      ('Xem pin ở đâu?', Icons.battery_5_bar_rounded),
      ('Làm sao dừng sạc?', Icons.power_settings_new_rounded),
      ('Vì sao nút sạc bị khóa?', Icons.lock_rounded),
      ('Kết nối Shelly', Icons.power_rounded),
    ]) {
      if (list.length >= 4) break;
      if (list.every((item) => item.$1 != text)) list.add((text, icon));
    }
    return list.take(4).toList();
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
    final photo = _pendingImage;
    var text = rawText.trim();
    if (text.isEmpty && photo != null) text = 'Bạn xem giúp mình ảnh này.';
    if (text.isEmpty || _isTyping) return;
    final generation = _generation;
    _inputController.clear();
    AssistantSignals.followUps.value = const [];
    if (_looksSensitive(text)) {
      setState(() => _pendingImage = null);
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
    final userId = 'user-${DateTime.now().microsecondsSinceEpoch}';
    if (photo != null) {
      AssistantSignals.attachImage(_pendingMime, base64Encode(photo));
      _photos[userId] = photo;
    }
    setState(() {
      _activeSuggestion = null;
      _pendingImage = null;
      _messages.add(
        ChatMessage(
          id: userId,
          role: ChatRole.user,
          content: text,
          timestamp: DateTime.now(),
          hasImage: photo != null,
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
    _liveIndex = index;
    _liveStatus = null;
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
          _liveIndex = null;
          _liveStatus = null;
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
        // QA 141: the instant how-to answers keep the button too.
        final shortcut =
            basicMode || BatteryBotFaq.quickAnswers.containsKey(text.trim())
            ? BatteryBotFaq.actionFor(text)
            : null;
        setState(() {
          _isTyping = false;
          _liveIndex = null;
          _liveStatus = null;
          _messages[index] = _messages[index].copyWith(
            content: accumulated.isEmpty
                ? 'Chưa nhận được câu trả lời. Hãy thử lại.'
                : accumulated,
            isStreaming: false,
            hasError: accumulated.isEmpty,
            action: shortcut?.name,
          );
        });
        final ups = AssistantSignals.followUps.value;
        if (ups.isNotEmpty && !basicMode) {
          setState(() => _followUps[_messages[index].id] = ups);
        }
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
      AppPopup.showMessage(
        'Chưa gửi được đánh giá. Bạn hãy thử lại.',
        kind: AppNoticeKind.error,
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
        openChargeControl(ref);
        break;
      case BatteryBotAction.guideHistory:
        openChargeHistory(ref);
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
    final accent = isHigh ? LuxeColors.champagne : context.planAccent;

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
                : Icons.tips_and_updates_rounded,
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
                    fontSize: 13,
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
    final last = index == _messages.length - 1;
    final bubble = ChatMessageBubble(
      message: message,
      showMeta: showMeta,
      imageBytes: _photos[message.id],
      liveStatus: index == _liveIndex ? _liveStatus : null,
      onFeedback: (rating) => _onFeedback(index, rating),
      onActionPressed: _executeAction,
      isActionLoading: _actionLoadingMap[message.actionCard?.callId] ?? false,
      onConfirmAction: (act) => _handleActionConfirm(index, act),
      onCancelAction: (act) => _handleActionCancel(index, act),
      onRetry: () => _handleRetry(index),
      // QA 163: the last answer can be asked again.
      onAskAgain: last && message.fromBot && !_isTyping && index > 0
          ? () => _askAgain(index)
          : null,
    );
    final ups = last && !_isTyping ? _followUps[message.id] : null;
    if (ups == null || ups.isEmpty) return bubble;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bubble,
        Padding(
          key: const ValueKey('assistant-follow-ups'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final text in ups)
                ActionChip(
                  avatar: Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 16,
                    color: context.planAccent,
                  ),
                  label: Text(text),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onPressed: () => _handleSend(text),
                ),
            ],
          ),
        ),
      ],
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
    final chargingNow = vehicle == null
        ? null
        : ref.watch(chargingEstimateProvider(vehicle.vehicleId));
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
              // QA 140: the top edge in the plan's colours; on Ultra the
              // current runs along it while Pinova Bot is answering.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 2.5,
                child: _PlanEdge(active: _isTyping),
              ),
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
                    // QA 164: one header row (Pinova Bot, the vehicle and its
                    // battery, close), then the tools with their names so a
                    // new owner sees what each does. Capped and scrollable so
                    // large text and the keyboard never push the input away.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: box.maxHeight * (keyboard > 0 ? 0.28 : 0.45),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 6, 10, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: context.planAccent.withValues(
                                        alpha: 0.55,
                                      ),
                                    ),
                                  ),
                                  child: BatteryBotMascot(
                                    size: BatteryBotSize.avatar,
                                    displayMode: BatteryBotDisplayMode.avatar,
                                    mood: _headerMood,
                                    enableFloating: false,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _BotTitle(
                                    vehicle: Text(
                                      vehicle?.displayName ??
                                          'Chưa chọn xe theo dõi',
                                      key: const Key('assistant_vehicle_label'),
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: LuxeColors.text,
                                      ),
                                    ),
                                    battery: Text(
                                      vehicle != null && chargingNow != null
                                          ? 'Đang sạc · ước tính $chargingNow%'
                                          : vehicle == null ||
                                                !vehicle.hasBatteryData
                                          ? 'Chưa có dữ liệu pin'
                                          : 'Pin ${vehicle.currentBattery}%',
                                      key: const Key(
                                        'assistant_battery_source',
                                      ),
                                      // What the owner entered or the app
                                      // estimated: neither verified nor a
                                      // warning, so muted.
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: LuxeColors.muted,
                                      ),
                                    ),
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
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _ToolPill(
                                  key: const Key('assistant_history_button'),
                                  icon: Icons.history_rounded,
                                  label: 'Lịch sử',
                                  tooltip: 'Lịch sử chat',
                                  onTap: _showHistoryModal,
                                ),
                                _ToolPill(
                                  key: const Key('assistant_new_chat_button'),
                                  icon: Icons.add_comment_rounded,
                                  label: 'Chat mới',
                                  tooltip: 'Đoạn chat mới',
                                  onTap: () => _startNewChat(),
                                ),
                                // QA 163: one place for Pinova Bot's
                                // settings (style, tips, memory).
                                _ToolPill(
                                  key: const Key('assistant_settings_button'),
                                  icon: Icons.tune_rounded,
                                  label: 'Cài đặt',
                                  tooltip: 'Cài đặt Pinova Bot',
                                  onTap: () =>
                                      AssistantSettingsScreen.open(context),
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
                                  if (_upgraded)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        4,
                                        16,
                                        4,
                                      ),
                                      child: LuxeNotice(
                                        key: const ValueKey(
                                          'assistant-upgraded',
                                        ),
                                        icon: Icons.new_releases_rounded,
                                        message:
                                            'Pinova Bot vừa được nâng cấp lên '
                                            '${PinovaBotRelease.current}.',
                                        action: TextButton(
                                          key: const ValueKey(
                                            'assistant-upgraded-open',
                                          ),
                                          onPressed: _openUpgradeNotes,
                                          style: TextButton.styleFrom(
                                            minimumSize: const Size(48, 48),
                                          ),
                                          child: const Text('Có gì mới'),
                                        ),
                                      ),
                                    ),
                                  if (_introSeen)
                                    _WelcomeHeader(
                                      greeting: _messages.isEmpty
                                          ? 'Hỏi mình về xe, pin, sạc và ổ Shelly.'
                                          : _messages.first.content,
                                    )
                                  else
                                    _BotIntro(onStart: _finishIntro),
                                  // The greeting is in the header above; a
                                  // restored first answer still shows.
                                  for (
                                    var i = _introSeen ? 1 : 0;
                                    i < _messages.length;
                                    i++
                                  )
                                    _bubble(i, showMeta: false),
                                  _SuggestionCards(
                                    suggestions: _starters(
                                      hasVehicle: vehicle != null,
                                      battery:
                                          vehicle != null &&
                                              vehicle.hasBatteryData
                                          ? vehicle.currentBattery
                                          : null,
                                      charging: chargingNow != null,
                                    ),
                                    onSelect: _handleSend,
                                  ),
                                  _TodayTip(
                                    onAsk: (title) => _handleSend(
                                      'Giải thích thêm mẹo: $title',
                                    ),
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
                                    'Đang suy nghĩ…',
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
                    // QA 142: the server's lock (3 strikes), with its end.
                    ValueListenableBuilder<DateTime?>(
                      valueListenable: AssistantLock.until,
                      builder: (context, until, _) =>
                          until == null || !until.isAfter(DateTime.now())
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                              child: LuxeNotice(
                                key: const ValueKey('assistant-locked'),
                                icon: Icons.lock_clock_rounded,
                                color: LuxeColors.danger,
                                message:
                                    'Pinova Bot tạm khóa tới '
                                    '${until.hour.toString().padLeft(2, '0')}:'
                                    '${until.minute.toString().padLeft(2, '0')} '
                                    'vì vi phạm Quy tắc Cộng đồng. Tab Sạc pin '
                                    'và Trợ giúp vẫn dùng bình thường; báo '
                                    'cháy, khói vẫn được trả lời.',
                              ),
                            ),
                    ),
                    // QA 163: few messages left today: say so before they run out.
                    ValueListenableBuilder<int?>(
                      valueListenable: AssistantSignals.remainingToday,
                      builder: (context, left, _) {
                        final daily = ref.watch(
                          entitlementProvider.select(
                            (plan) => plan.assistantDaily,
                          ),
                        );
                        if (left == null ||
                            left > (daily * 0.2).ceil().clamp(2, 20)) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          key: const ValueKey('assistant-left-today'),
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                          child: Text(
                            left == 0
                                ? 'Hôm nay đã hết lượt AI, Bot trả lời ở chế độ cơ bản.'
                                : 'Hôm nay còn $left tin với Pinova Bot.',
                            style: LuxeText.caption,
                          ),
                        );
                      },
                    ),
                    if (_pendingImage case final photo?)
                      Padding(
                        key: const ValueKey('assistant-photo-preview'),
                        padding: const EdgeInsets.fromLTRB(16, 6, 12, 0),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                photo,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Ảnh sẽ gửi kèm câu hỏi của bạn',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: LuxeColors.muted,
                                ),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('assistant-photo-remove'),
                              tooltip: 'Bỏ ảnh',
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () =>
                                  setState(() => _pendingImage = null),
                            ),
                          ],
                        ),
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
                        key: GuideRegistry.keyBotInput,
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
                                ? context.planAccent
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
                                            onPressed: () => setState(
                                              () => _isListeningVoice = false,
                                            ),
                                          ),
                                          // QA 139: no waveform (voice input is
                                          // off; it looped without real audio).
                                          const Spacer(),
                                          Text(
                                            'Đang nghe…',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: context.planAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : TextField(
                                      key: const Key('assistant_input_field'),
                                      controller: _inputController,
                                      // QA 150: the keyboard offered saved
                                      // passwords above the chat field.
                                      autofillHints: const <String>[],
                                      enableSuggestions: true,
                                      keyboardType: TextInputType.multiline,
                                      textInputAction: TextInputAction.send,
                                      minLines: 1,
                                      maxLines: 4,
                                      style: const TextStyle(
                                        color: LuxeColors.text,
                                        fontSize: 15.5,
                                      ),
                                      decoration: const InputDecoration(
                                        hintText: 'Hỏi về pin, sạc, xe',
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
                                key: GuideRegistry.keyBotScan,
                                tooltip: 'Quét đồng hồ hoặc gửi ảnh',
                                icon: const Icon(
                                  Icons.photo_camera_rounded,
                                  color: LuxeColors.platinumMid,
                                ),
                                onPressed: _isTyping || _readingDashboard
                                    ? null
                                    : _openAttachMenu,
                              ),
                            if (VoiceBridge.supported && !_isListeningVoice)
                              IconButton(
                                key: const Key('assistant_voice_button'),
                                tooltip: 'Nói để hỏi Pinova Bot',
                                icon: const Icon(
                                  Icons.mic_rounded,
                                  color: LuxeColors.platinumMid,
                                ),
                                onPressed: _isTyping ? null : _toggleVoiceInput,
                              ),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _inputController,
                              builder: (context, value, _) {
                                final ready =
                                    (value.text.trim().isNotEmpty ||
                                        _pendingImage != null) &&
                                    !_isTyping;
                                // QA 163: while Pinova Bot answers, the
                                // button stops the answer.
                                if (_isTyping) {
                                  return IconButton(
                                    key: const Key('assistant_stop_button'),
                                    tooltip: 'Dừng trả lời',
                                    style: IconButton.styleFrom(
                                      fixedSize: const Size(48, 48),
                                      backgroundColor: LuxeColors.raisedHigh,
                                      foregroundColor: LuxeColors.text,
                                    ),
                                    icon: const Icon(
                                      Icons.stop_rounded,
                                      size: 22,
                                    ),
                                    onPressed: _stopReply,
                                  );
                                }
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
                                        ? LuxeColors.shell
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
  const _WelcomeHeader({required this.greeting});

  /// QA 164: the greeting is said here once (the sheet used to show the
  /// question, then the same greeting again as a message, with three faces
  /// of Pinova Bot on screen).
  final String greeting;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
    child: Column(
      children: [
        const LuxeReveal(
          child: BatteryBotMascot(
            size: BatteryBotSize.sm,
            mood: BatteryBotMood.happy,
          ),
        ),
        const SizedBox(height: 10),
        LuxeReveal(
          index: 1,
          child: Column(
            children: [
              const Text(
                'Mình có thể giúp gì?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: LuxeColors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                greeting,
                key: const ValueKey('assistant-greeting'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: LuxeColors.muted,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// QA 163: the first time Pinova Bot opens on this phone, what it can do
/// in three lines, then "Bắt đầu". It replaces the greeting once.
class _BotIntro extends StatelessWidget {
  const _BotIntro({required this.onStart});
  final VoidCallback onStart;

  static const _lines = <(IconData, String, String)>[
    (
      Icons.forum_rounded,
      'Hỏi bằng lời thường',
      'Pin, sạc, quãng đường, ổ Shelly, bảo dưỡng…',
    ),
    (
      Icons.touch_app_rounded,
      'Nhờ làm giúp',
      'Bật hoặc dừng sạc, cập nhật % pin và ODO. Bot luôn hỏi lại trước khi làm.',
    ),
    (
      Icons.lightbulb_rounded,
      'Mẹo nhỏ mỗi ngày',
      'Đi xe tiết kiệm, sạc đúng cách, giữ pin bền.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('assistant-intro'),
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
    child: LuxeGlass(
      raised: true,
      radius: 24,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: BatteryBotMascot(
              size: BatteryBotSize.sm,
              mood: BatteryBotMood.greeting,
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Chào bạn, mình là Pinova Bot',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: LuxeColors.text,
                fontSize: 19,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final (icon, title, body) in _lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: context.planAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: LuxeText.item),
                        Text(body, style: LuxeText.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'Lịch sử chat lưu trên máy này. Mỗi ngày có số tin AI theo gói; '
            'hết lượt Bot vẫn trả lời ở chế độ cơ bản.',
            style: LuxeText.caption.copyWith(color: LuxeColors.dim),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('assistant-intro-start'),
              onPressed: onStart,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Bắt đầu'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// QA 163: today's tip under the starters, when the daily tip is on.
class _TodayTip extends StatefulWidget {
  const _TodayTip({required this.onAsk});
  final ValueChanged<String> onAsk;

  @override
  State<_TodayTip> createState() => _TodayTipState();
}

class _TodayTipState extends State<_TodayTip> {
  final _library = TipLibrary.instance;

  @override
  void initState() {
    super.initState();
    _library.addListener(_changed);
    unawaited(_library.load());
  }

  @override
  void dispose() {
    _library.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_library.loaded || !_library.dailyEnabled) {
      return const SizedBox.shrink();
    }
    final tip = _library.today(now: DateTime.now());
    if (tip == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('assistant-today-tip'),
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            _library.markSeen(tip.id);
            widget.onAsk(tip.title);
          },
          child: LuxeGlass(
            quiet: true,
            radius: 18,
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_rounded,
                  size: 20,
                  color: context.planAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('MẸO HÔM NAY', style: LuxeText.eyebrow),
                      const SizedBox(height: 2),
                      Text(tip.title, style: LuxeText.item),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: LuxeColors.platinumMid,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One glass card per suggestion, shown under the greeting.
class _SuggestionCards extends StatelessWidget {
  const _SuggestionCards({required this.suggestions, required this.onSelect});

  /// QA 163: each starter with its own icon.
  final List<(String, IconData)> suggestions;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    child: LayoutBuilder(
      builder: (context, box) {
        final big = MediaQuery.textScalerOf(context).scale(14) > 20;
        final columns = big || box.maxWidth < 300 ? 1 : 2;
        // QA 141: the cards of a row share one height.
        Widget card(int i) => LuxeReveal(
          index: i + 2,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onSelect(suggestions[i].$1),
              child: LuxeGlass(
                radius: 18,
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      suggestions[i].$2,
                      size: 20,
                      color: context.planAccent,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      suggestions[i].$1,
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
        );
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < suggestions.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                card(i),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < suggestions.length; i += 2) ...[
              if (i > 0) const SizedBox(height: 10),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: card(i)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: i + 1 < suggestions.length
                          ? card(i + 1)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
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
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.planAccent,
        boxShadow: [BoxShadow(color: context.planAccentGlow, blurRadius: 8)],
      ),
    ),
  );
}

/// "Pinova Bot" with the plan's tag and the plan's daily messages (QA 136).
class _BotTitle extends StatelessWidget {
  const _BotTitle({required this.vehicle, required this.battery});

  /// QA 164: the vehicle and its battery under the name (one line when it
  /// fits), instead of a second card.
  final Widget vehicle;
  final Widget battery;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Wrap(
        spacing: 8,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
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
          CurrentPlanTag(key: ValueKey('assistant-plan-tag')),
        ],
      ),
      const SizedBox(height: 2),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          vehicle,
          const Text(
            '  ·  ',
            style: TextStyle(fontSize: 12.5, color: LuxeColors.dim),
          ),
          battery,
        ],
      ),
    ],
  );
}

/// QA 164: a tool in the header with its name (Lịch sử, Chat mới, Cài đặt).
class _ToolPill extends StatelessWidget {
  const _ToolPill({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Material(
        color: LuxeColors.glass,
        shape: const StadiumBorder(
          side: BorderSide(color: LuxeColors.hairline),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: LuxeColors.platinum),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: LuxeColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The sheet's top edge: the plan's gradient, still on Free/Pro; on Ultra
/// with effects on it flows while [active] (Pinova Bot answering) and rests
/// otherwise.
class _PlanEdge extends StatefulWidget {
  const _PlanEdge({required this.active});
  final bool active;

  @override
  State<_PlanEdge> createState() => _PlanEdgeState();
}

class _PlanEdgeState extends State<_PlanEdge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  void _sync() {
    final run = widget.active && PlanMotion.effectsOf(context);
    if (run && !_flow.isAnimating) {
      _flow.repeat();
    } else if (!run && _flow.isAnimating) {
      _flow.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_PlanEdge old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = PlanStyle.of(context);
    final colors = plan.accentColors;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _flow,
        builder: (context, _) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                for (final c in [...colors, colors.first])
                  c.withValues(alpha: _flow.isAnimating ? 0.95 : 0.45),
              ],
              // One loop slides the pattern by its own width.
              begin: Alignment(-1 + 2 * _flow.value, 0),
              end: Alignment(1 + 2 * _flow.value, 0),
              tileMode: TileMode.repeated,
            ),
          ),
        ),
      ),
    );
  }
}
