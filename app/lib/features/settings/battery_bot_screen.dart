import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/services/guide_registry.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_ui_colors.dart';
import '../../core/utils/battery_bot_faq.dart';
import '../../core/widgets/battery_bot_mascot.dart';
import '../../navigation/app_navigation.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';

class _BotMessage {
  const _BotMessage({required this.text, required this.fromBot, this.action});
  final String text;
  final bool fromBot;
  final BatteryBotAction? action;
  Map<String, dynamic> toJson() => {
    'text': text,
    'fromBot': fromBot,
    'action': action?.name,
  };
  factory _BotMessage.fromJson(Map<String, dynamic> json) {
    final actionName = json['action']?.toString();
    BatteryBotAction? action;
    for (final candidate in BatteryBotAction.values) {
      if (candidate.name == actionName) action = candidate;
    }
    return _BotMessage(
      text: json['text']?.toString() ?? '',
      fromBot: json['fromBot'] == true,
      action: action,
    );
  }
}

class BatteryBotScreen extends StatefulWidget {
  const BatteryBotScreen({
    super.key,
    this.auth,
    this.storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
  });

  final FirebaseAuth? auth;
  final FlutterSecureStorage storage;
  @override
  State<BatteryBotScreen> createState() => _BatteryBotScreenState();
}

class _BatteryBotScreenState extends State<BatteryBotScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _latestMessageKey = GlobalKey();
  final _messages = <_BotMessage>[];
  StreamSubscription<User?>? _authSubscription;
  String? _uid;
  bool _ready = false;
  bool _persistenceAvailable = true;
  int _accountRevision = 0;
  int _replyScrollRevision = 0;
  late final FirebaseAuth _auth;

  @override
  void initState() {
    super.initState();
    _auth = widget.auth ?? FirebaseAuth.instance;
    _uid = _auth.currentUser?.uid;
    unawaited(_load());
    _authSubscription = _auth.userChanges().listen((user) {
      final nextUid = user?.uid;
      if (!mounted || nextUid == _uid) return;
      setState(() {
        _accountRevision++;
        _uid = nextUid;
        _input.clear();
        _messages.clear();
        _ready = false;
        _persistenceAvailable = true;
      });
      unawaited(_load());
    });
  }

  String _key(String uid) => 'battery_bot_history_v1_$uid';

  Future<void> _load() async {
    final uid = _uid;
    final revision = _accountRevision;
    String? value;
    var storageAvailable = true;
    try {
      value = uid == null ? null : await widget.storage.read(key: _key(uid));
    } catch (_) {
      // An unreadable history must not prevent offline help or get overwritten.
      storageAvailable = false;
    }
    if (!mounted || uid != _uid || revision != _accountRevision) return;
    _persistenceAvailable = storageAvailable;
    if (value != null) {
      try {
        final decoded = jsonDecode(value) as List;
        _messages
          ..clear()
          ..addAll(
            decoded
                .whereType<Map>()
                .map(
                  (item) =>
                      _BotMessage.fromJson(Map<String, dynamic>.from(item)),
                )
                .take(50),
          );
      } catch (_) {
        _messages.clear();
      }
    }
    if (_messages.isEmpty) {
      _messages.add(
        const _BotMessage(
          text:
              'Mình là BatteryBot, giúp bạn tìm chức năng trong app. Bạn có thể hỏi về pin, lịch sử hoặc kết nối Shelly. Mình không tự bật hay tắt bộ sạc.',
          fromBot: true,
        ),
      );
    }
    setState(() => _ready = true);
  }

  Future<bool> _saveForUid(String uid) async {
    if (!_persistenceAvailable || uid != _uid) return false;
    final revision = _accountRevision;
    final bounded = _messages.length > 50
        ? _messages.sublist(_messages.length - 50)
        : _messages;
    try {
      await widget.storage.write(
        key: _key(uid),
        value: jsonEncode(bounded.map((message) => message.toJson()).toList()),
      );
      return true;
    } catch (_) {
      if (mounted && uid == _uid && revision == _accountRevision) {
        setState(() => _persistenceAvailable = false);
      }
      return false;
    }
  }

  bool _looksSensitive(String text) =>
      RegExp(
        r'(cloud\s*key|auth[_ -]?key|api[_ -]?key|password|mật khẩu|bearer\s+[a-z0-9._-]{16,})',
        caseSensitive: false,
      ).hasMatch(text) ||
      RegExp(r'\b[A-Za-z0-9_-]{32,}\b').hasMatch(text);

  _BotMessage _answer(String raw) {
    if (_looksSensitive(raw)) {
      return const _BotMessage(
        text:
            'Để bảo vệ thiết bị, bạn đừng gửi mật khẩu hoặc khóa truy cập tại đây. Hãy nhập chúng trực tiếp trong màn hình kết nối Shelly.',
        fromBot: true,
      );
    }
    final action = BatteryBotFaq.actionFor(raw);
    return _BotMessage(
      text: switch (action) {
        BatteryBotAction.shellySetup =>
          'Mở thiết lập Shelly để kết nối bộ sạc. Ưu tiên cùng Wi-Fi; app chỉ mở điều khiển sau khi xác minh thiết bị và an toàn.',
        BatteryBotAction.guideCharging =>
          'Mở tab Sạc pin để xem trạng thái và chọn dừng sạc. Nếu nút bật sạc đang khóa, hãy kiểm tra kết nối và hoàn tất xác minh Shelly trước nhé.',
        BatteryBotAction.guideHistory =>
          'Mở tab Lịch sử, chọn khoảng thời gian nếu cần rồi chạm một phiên để xem chi tiết.',
        BatteryBotAction.guideVehicle =>
          'Mức pin nằm ở màn hình Tổng quan. Chạm tên xe phía trên nếu bạn muốn chuyển sang xe khác.',
        null =>
          'Mình chưa hiểu câu này. Bạn có thể hỏi về xem pin, dừng sạc, lịch sử hoặc kết nối Shelly.',
      },
      fromBot: true,
      action: action,
    );
  }

  Future<void> _send([String? suggestion]) async {
    final value = (suggestion ?? _input.text).trim();
    if (value.isEmpty || !_ready || _auth.currentUser?.uid != _uid) return;
    final sendingUid = _uid;
    final revision = _accountRevision;
    _input.clear();
    setState(
      () => _messages.add(
        _BotMessage(
          text: _looksSensitive(value) ? 'Nội dung riêng tư đã được ẩn' : value,
          fromBot: false,
        ),
      ),
    );
    final answer = _answer(value);
    setState(() => _messages.add(answer));
    if (_messages.length > 50) {
      _messages.removeRange(0, _messages.length - 50);
    }
    if (sendingUid != null) await _saveForUid(sendingUid);
    if (!mounted || sendingUid != _uid || revision != _accountRevision) return;
    _revealLatestReply(sendingUid, revision);
  }

  void _revealLatestReply(String? sendingUid, int accountRevision) {
    final scrollRevision = ++_replyScrollRevision;
    bool isCurrent() =>
        mounted &&
        sendingUid == _uid &&
        accountRevision == _accountRevision &&
        scrollRevision == _replyScrollRevision &&
        _scroll.hasClients &&
        ModalRoute.of(context)?.isCurrent != false;

    void afterLayout(int remaining) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!isCurrent()) return;
        final latestContext = _latestMessageKey.currentContext;
        if (latestContext != null) {
          // The last bubble can be taller than the lazy list's estimate.
          // Reveal its real layout, not a previously estimated scroll extent.
          await Scrollable.ensureVisible(
            latestContext,
            alignment: 1,
            duration: AppMotion.durationFor(context, AppMotion.fast),
            curve: AppMotion.enter,
          );
          return;
        }
        if (remaining == 0) return;
        final end = _scroll.position.maxScrollExtent;
        if (AppMotion.enabled(context)) {
          await _scroll.animateTo(
            end,
            duration: AppMotion.fast,
            curve: AppMotion.enter,
          );
        } else {
          _scroll.jumpTo(end);
        }
        if (isCurrent()) afterLayout(remaining - 1);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }

    // At most 50 history items exist. Recheck after layout, never via timers.
    afterLayout(_messages.length);
  }

  Future<void> _clear() async {
    final clearingUid = _uid;
    final revision = _accountRevision;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEn ? 'Clear conversation?' : 'Xóa trò chuyện?'),
        content: Text(
          isEn
              ? 'This clears BatteryBot messages stored on this device.'
              : 'Các tin nhắn BatteryBot đã lưu trên thiết bị này sẽ bị xóa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(isEn ? 'Cancel' : 'Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isEn ? 'Clear' : 'Xóa'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        clearingUid != _uid ||
        revision != _accountRevision) {
      return;
    }
    _messages.clear();
    _messages.add(
      const _BotMessage(
        text: 'Mình đã xóa cuộc trò chuyện. Bạn cần giúp gì tiếp theo?',
        fromBot: true,
      ),
    );
    final saved = clearingUid == null || await _saveForUid(clearingUid);
    if (!mounted || clearingUid != _uid || revision != _accountRevision) return;
    if (!saved) {
      _messages
        ..clear()
        ..add(
          const _BotMessage(
            text:
                'Chưa xóa được lịch sử đã lưu. Bạn có thể thử lại khi mở lại cuộc trò chuyện.',
            fromBot: true,
          ),
        );
    }
    setState(() {});
  }

  void _open(BatteryBotAction action) {
    if (!_ready || _auth.currentUser?.uid != _uid) return;
    if (action == BatteryBotAction.shellySetup) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SmartChargerSetupHubScreen(),
        ),
      );
      return;
    }
    final id = switch (action) {
      BatteryBotAction.guideVehicle => 'guide_vehicle_battery',
      BatteryBotAction.guideCharging => 'guide_charging',
      BatteryBotAction.guideHistory => 'guide_history',
      BatteryBotAction.shellySetup => 'guide_shelly_setup',
    };
    final tab = GuideRegistry.items
        .singleWhere((item) => item.id == id)
        .destination
        .tabIndex;
    if (tab != null) AppNavigation.openTab(context, tab);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final ui = AppUiColors.of(context);
    return Scaffold(
      backgroundColor: ui.background,
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          children: [
            const TickerMode(
              enabled: false,
              child: BatteryBotMascot(
                size: BatteryBotSize.avatar,
                customWidth: 36,
                customHeight: 36,
                enableFloating: false,
                mood: BatteryBotMood.happy,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'BatteryBot',
                style: TextStyle(color: ui.text, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: isEn ? 'Clear conversation' : 'Xóa trò chuyện',
            onPressed: _ready && _persistenceAvailable ? _clear : null,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_persistenceAvailable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                isEn
                    ? 'Conversation history is unavailable. New messages will only stay in this session.'
                    : 'Lịch sử trò chuyện tạm thời không khả dụng. Tin nhắn mới chỉ giữ trong lần mở này.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: !_ready
                ? const Center(child: CircularProgressIndicator())
                : NotificationListener<ScrollStartNotification>(
                    onNotification: (notification) {
                      // A person dragging history takes precedence over auto-scroll.
                      if (notification.dragDetails != null) {
                        _replyScrollRevision++;
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      itemCount:
                          _messages.length + (_messages.length <= 2 ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return LayoutBuilder(
                            builder: (context, constraints) => Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final prompt in BatteryBotFaq.suggestions)
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: 48,
                                      maxWidth: constraints.maxWidth,
                                    ),
                                    child: ActionChip(
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.padded,
                                      label: Text(prompt, softWrap: true),
                                      onPressed: () => _send(prompt),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }
                        final isLatest = index == _messages.length - 1;
                        return Padding(
                          key: isLatest ? _latestMessageKey : null,
                          padding: EdgeInsets.only(bottom: isLatest ? 10 : 0),
                          child: _MessageBubble(
                            message: _messages[index],
                            onOpen: _open,
                          ),
                        );
                      },
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: isEn ? 'Ask a question' : 'Nhập câu hỏi…',
                        filled: true,
                        fillColor: ui.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: ui.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: ui.border),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: isEn ? 'Send' : 'Gửi',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: _ready ? () => _send() : null,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onOpen});
  final _BotMessage message;
  final ValueChanged<BatteryBotAction> onOpen;
  @override
  Widget build(BuildContext context) {
    final ui = AppUiColors.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final bg = message.fromBot ? ui.surface : ui.primary.withValues(alpha: .12);
    return Align(
      alignment: message.fromBot ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .84,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(color: ui.text, height: 1.4),
                  ),
                  if (message.action != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => onOpen(message.action!),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(switch (message.action!) {
                        BatteryBotAction.guideVehicle =>
                          isEn ? 'Open overview' : 'Mở Tổng quan',
                        BatteryBotAction.guideCharging =>
                          isEn ? 'Open charging' : 'Mở Sạc pin',
                        BatteryBotAction.guideHistory =>
                          isEn ? 'Open history' : 'Mở lịch sử',
                        BatteryBotAction.shellySetup =>
                          isEn ? 'Open Shelly setup' : 'Mở thiết lập Shelly',
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
