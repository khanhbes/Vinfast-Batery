import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../premium/premium_screen.dart';
import '../settings/about_screen.dart';
import '../settings/assistant_memory_screen.dart';
import '../tips/tip_library.dart';
import '../tips/tips_screen.dart';
import 'bot_release.dart';
import 'services/assistant_api.dart';
import 'services/chat_history_storage.dart';

/// "Cài đặt Pinova Bot" (QA 163, owner's choice): like the settings of
/// Claude or ChatGPT. The style, length, how to be called, what the bot
/// should know and the follow-up questions live on the server (the prompt
/// reads them); the daily tip and the morning greeting are this phone's.
class AssistantSettingsScreen extends ConsumerStatefulWidget {
  const AssistantSettingsScreen({super.key, this.api, this.tips});

  /// Tests.
  final AssistantApi? api;
  final TipLibrary? tips;

  static const introSeenKey = 'assistant.intro_seen.v1';

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AssistantSettingsScreen()),
  );

  /// The styles, in order: id, name, one line that shows the difference.
  static const personas = <(String, String, String)>[
    (
      'companion',
      'Thân thiện',
      'Mình tính rồi nè: sạc lên 80% mất khoảng 1 giờ 40 phút nhé.',
    ),
    ('concise', 'Ngắn gọn', 'Khoảng 1 giờ 40 phút để lên 80%.'),
    (
      'expert',
      'Chuyên sâu kỹ thuật',
      'Cần khoảng 1.2 kWh ở 440 W: khoảng 1 giờ 40 phút để lên 80%.',
    ),
    (
      'concierge',
      'Lịch thiệp',
      'Dạ, em ước tính anh/chị cần khoảng 1 giờ 40 phút để pin lên 80% ạ.',
    ),
  ];

  static const lengths = <(String, String)>[
    ('short', 'Ngắn'),
    ('medium', 'Vừa'),
    ('long', 'Chi tiết'),
  ];

  static String lengthExample(String id) => switch (id) {
    'short' => 'Hai, ba câu: đủ ý chính.',
    'long' => 'Giải thích kỹ hơn và nêu lý do, câu đầu vẫn là câu trả lời.',
    _ => 'Câu trả lời trước, thêm vài ý khi cần.',
  };

  @override
  ConsumerState<AssistantSettingsScreen> createState() =>
      _AssistantSettingsScreenState();
}

class _AssistantSettingsScreenState
    extends ConsumerState<AssistantSettingsScreen> {
  late final AssistantApi _api = widget.api ?? AssistantApi();
  late final TipLibrary _tips = widget.tips ?? TipLibrary.instance;
  final _callMe = TextEditingController();
  final _aboutMe = TextEditingController();
  AssistantSettings? _settings;
  bool _loading = true;
  bool _saving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _tips.addListener(_changed);
    unawaited(_tips.load());
    unawaited(_load());
  }

  @override
  void dispose() {
    _tips.removeListener(_changed);
    _callMe.dispose();
    _aboutMe.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final settings = await _api.settings();
      if (!mounted) return;
      _callMe.text = settings.callMe;
      _aboutMe.text = settings.aboutMe;
      setState(() {
        _settings = settings;
        _loading = false;
        _failed = false;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _save(Map<String, dynamic> patch, {String? done}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final settings = await _api.updateSettings(patch);
      if (!mounted) return;
      setState(() => _settings = settings);
      if (done != null) AppPopup.showSuccess(done);
    } on AssistantUnavailable catch (error) {
      AppPopup.showWarning(
        error.code == 'premiumRequired'
            ? 'Giọng Lịch thiệp có ở gói Pro và Ultra'
            : 'Chưa lưu được cài đặt',
        detail: error.code == 'premiumRequired'
            ? null
            : 'Kiểm tra kết nối rồi thử lại.',
        userInitiated: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearHistory() async {
    final ok = await showLuxeConfirm(
      context,
      title: 'Xóa toàn bộ lịch sử chat?',
      message:
          'Mọi đoạn chat lưu trên máy này sẽ bị xóa. Điều Pinova Bot ghi nhớ '
          'về bạn không bị xóa (xem ở "Pinova Bot đang nhớ gì").',
      confirmLabel: 'Xóa lịch sử',
    );
    if (ok != true || !mounted) return;
    final storage = ref.read(chatHistoryStorageProvider);
    try {
      final sessions = await storage.listSavedSessions(limit: 500);
      for (final session in sessions) {
        await storage.deleteSession(session.id);
      }
      AppPopup.showSuccess('Đã xóa lịch sử chat trên máy này');
    } on Object {
      AppPopup.showWarning('Chưa xóa được lịch sử', userInitiated: true);
    }
  }

  Future<void> _replayIntro() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AssistantSettingsScreen.introSeenKey);
    } on Object {
      // Shown anyway next time the phone can read it.
    }
    AppPopup.showMessage('Lần mở Pinova Bot tới sẽ có phần giới thiệu');
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    final online = s != null;
    return LuxeScaffold(
      title: 'Cài đặt Pinova Bot',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
          if (_failed)
            LuxeNotice(
              key: const ValueKey('bot-settings-offline'),
              icon: Icons.cloud_off_rounded,
              color: LuxeColors.champagne,
              message:
                  'Chưa tải được cài đặt trên máy chủ (mất mạng hoặc máy chủ chưa '
                  'cập nhật). Mẹo mỗi ngày và lời chào vẫn chỉnh được.',
            ),
          const LuxeSectionLabel('Giọng trả lời'),
          LuxeSettingsGroup(
            children: [
              for (final (id, name, example)
                  in AssistantSettingsScreen.personas)
                LuxeSettingsRow(
                  key: ValueKey('bot-persona-$id'),
                  icon: s?.persona == id
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  title: id == 'concierge' ? '$name · Pro/Ultra' : name,
                  subtitle: '"$example"',
                  trailing:
                      id == 'concierge' && s != null && !s.conciergeAllowed
                      ? const Icon(
                          Icons.lock_rounded,
                          size: 18,
                          color: LuxeColors.platinumMid,
                        )
                      : null,
                  onTap: !online || _saving
                      ? null
                      : id == 'concierge' && !s.conciergeAllowed
                      ? () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PremiumScreen(),
                          ),
                        )
                      : () => _save({'persona': id}),
                ),
            ],
          ),
          const LuxeSectionLabel('Độ dài câu trả lời'),
          LuxeSegmented<String>(
            key: const ValueKey('bot-length'),
            segments: AssistantSettingsScreen.lengths,
            selected: s?.length ?? 'medium',
            onChanged: (value) {
              if (online && !_saving) _save({'length': value});
            },
          ),
          const SizedBox(height: 8),
          Text(
            AssistantSettingsScreen.lengthExample(s?.length ?? 'medium'),
            style: LuxeText.caption,
          ),
          const LuxeSectionLabel('Về bạn'),
          TextField(
            key: const ValueKey('bot-call-me'),
            controller: _callMe,
            enabled: online,
            maxLength: 30,
            autofillHints: const <String>[],
            style: const TextStyle(color: LuxeColors.text, fontSize: 15.5),
            decoration: const InputDecoration(
              labelText: 'Pinova Bot gọi bạn là',
              hintText: 'Ví dụ: anh Khánh',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('bot-about-me'),
            controller: _aboutMe,
            enabled: online,
            maxLength: 500,
            minLines: 3,
            maxLines: 6,
            autofillHints: const <String>[],
            style: const TextStyle(color: LuxeColors.text, fontSize: 15.5),
            decoration: const InputDecoration(
              labelText: 'Điều Pinova Bot nên biết về bạn',
              hintText:
                  'Ví dụ: tôi đi làm 18 km mỗi ngày, hay chở con, sạc ở nhà '
                  'buổi tối.',
              alignLabelWithHint: true,
            ),
          ),
          Text(
            'Bot dùng để trả lời sát hơn; không thay đổi được quy tắc an toàn. '
            'Đừng ghi mật khẩu hay mã vào đây.',
            style: LuxeText.caption,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('bot-about-save'),
              onPressed: !online || _saving
                  ? null
                  : () => _save({
                      'callMe': _callMe.text.trim(),
                      'aboutMe': _aboutMe.text.trim(),
                    }, done: 'Đã lưu'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Lưu'),
            ),
          ),
          const LuxeSectionLabel('Chủ động'),
          LuxeSettingsGroup(
            children: [
              LuxeSettingsRow(
                icon: Icons.lightbulb_rounded,
                title: 'Mẹo mỗi ngày',
                subtitle: 'Một mẹo nhỏ cạnh nút Pinova Bot mỗi ngày',
                trailing: LuxeSwitch(
                  key: const ValueKey('bot-daily-tip'),
                  value: _tips.dailyEnabled,
                  onChanged: (on) => _tips.setDailyEnabled(on),
                  semanticLabel: 'Mẹo mỗi ngày',
                ),
              ),
              LuxeSettingsRow(
                icon: Icons.wb_twilight_rounded,
                title: 'Chào buổi sáng',
                subtitle: 'Lời chào kèm mức pin lúc 6–9 giờ',
                trailing: LuxeSwitch(
                  value: _tips.morningEnabled,
                  onChanged: (on) => _tips.setMorningEnabled(on),
                  semanticLabel: 'Chào buổi sáng',
                ),
              ),
              LuxeSettingsRow(
                icon: Icons.quickreply_rounded,
                title: 'Câu hỏi gợi ý',
                subtitle: 'Gợi ý câu hỏi tiếp theo dưới câu trả lời',
                trailing: LuxeSwitch(
                  key: const ValueKey('bot-follow-ups'),
                  value: s?.followUps ?? true,
                  onChanged: !online || _saving
                      ? null
                      : (on) => _save({'followUps': on}),
                  semanticLabel: 'Câu hỏi gợi ý',
                ),
              ),
              LuxeSettingsRow(
                icon: Icons.tips_and_updates_rounded,
                title: 'Mẹo nhỏ',
                subtitle: 'Xem mọi mẹo đi xe, sạc và giữ pin',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const TipsScreen()),
                ),
              ),
            ],
          ),
          const LuxeSectionLabel('Bộ nhớ & lịch sử'),
          LuxeSettingsGroup(
            children: [
              LuxeSettingsRow(
                icon: Icons.psychology_rounded,
                title: 'Học từ điều bạn kể',
                subtitle: 'Bot ghi nhớ thói quen để trả lời sát hơn',
                trailing: LuxeSwitch(
                  value: s?.learningEnabled ?? true,
                  onChanged: !online || _saving
                      ? null
                      : (on) => _save({'learningEnabled': on}),
                  semanticLabel: 'Học từ điều bạn kể',
                ),
              ),
              LuxeSettingsRow(
                icon: Icons.bookmarks_rounded,
                title: 'Pinova Bot đang nhớ gì',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AssistantMemoryScreen(),
                  ),
                ),
              ),
              LuxeSettingsRow(
                key: const ValueKey('bot-clear-history'),
                icon: Icons.delete_sweep_rounded,
                title: 'Xóa toàn bộ lịch sử chat',
                subtitle: 'Các đoạn chat lưu trên máy này',
                onTap: _clearHistory,
              ),
              if (s?.quotaLeft != null)
                LuxeSettingsRow(
                  key: const ValueKey('bot-quota'),
                  icon: Icons.chat_rounded,
                  title: 'Hôm nay còn ${s!.quotaLeft}/${s.quotaLimit} tin',
                  subtitle: 'Hết lượt thì Bot trả lời ở chế độ cơ bản',
                ),
            ],
          ),
          const LuxeSectionLabel('Phiên bản'),
          LuxeSettingsGroup(
            children: [
              LuxeSettingsRow(
                key: const ValueKey('bot-version'),
                icon: Icons.new_releases_rounded,
                title: 'Pinova Bot ${PinovaBotRelease.current}',
                subtitle: 'Xem có gì mới',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
                ),
              ),
              LuxeSettingsRow(
                icon: Icons.slideshow_rounded,
                title: 'Xem lại phần giới thiệu',
                onTap: _replayIntro,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
