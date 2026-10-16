import 'package:flutter/material.dart';

import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../ai/services/assistant_api.dart';

/// "BatteryBot đang nhớ gì" (Task 124): what the assistant remembers about
/// this account, a learning switch and delete controls. Synced per account.
class AssistantMemoryScreen extends StatefulWidget {
  const AssistantMemoryScreen({super.key, this.api});

  /// Test hook.
  final AssistantApi? api;

  @override
  State<AssistantMemoryScreen> createState() => _AssistantMemoryScreenState();
}

class _AssistantMemoryScreenState extends State<AssistantMemoryScreen> {
  late final AssistantApi _api = widget.api ?? AssistantApi();
  AssistantMemorySnapshot? _snapshot;
  String? _error;
  bool _busy = false;

  static const _categoryLabels = {
    'habit': 'Thói quen',
    'preference': 'Sở thích',
    'vehicle': 'Xe',
    'trip': 'Đi lại',
    'personal': 'Cá nhân',
    'other': 'Khác',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await _api.memory();
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    } on Object {
      if (!mounted) return;
      setState(() => _error = 'Chưa tải được. Kiểm tra kết nối rồi thử lại.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
      await _load();
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Chưa lưu được thay đổi. Hãy thử lại.';
      });
    }
  }

  Future<void> _clearAll() async {
    final ok = await showLuxeConfirm(
      context,
      title: 'Xóa mọi điều BatteryBot nhớ?',
      message:
          'BatteryBot sẽ quên mọi điều bạn đã kể. Lịch sử sạc và dữ liệu xe không bị ảnh hưởng.',
      confirmLabel: 'Xóa hết',
    );
    if (ok == true) await _run(_api.forgetAll);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return LuxeScaffold(
      appBar: const LuxeAppBar(),
      body: RefreshIndicator(
        color: LuxeColors.emerald,
        backgroundColor: LuxeColors.raised,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            const LuxePageHeaderText(
              eyebrow: 'TRỢ LÝ AI',
              title: 'BatteryBot đang nhớ gì',
              caption:
                  'Những điều bạn kể giúp BatteryBot trả lời sát với bạn hơn. Bạn xem, xóa hoặc tắt bất cứ lúc nào.',
            ),
            const SizedBox(height: 12),
            const LuxeNotice(
              key: ValueKey('assistant-privacy-note'),
              message:
                  'Câu hỏi và thông tin xe cần thiết được xử lý bởi Google Gemini qua máy chủ VinFast Battery. Không gửi mật khẩu hay mã truy cập; toàn bộ cuộc trò chuyện không được lưu trên máy chủ.',
              icon: Icons.shield_outlined,
            ),
            const SizedBox(height: 18),
            if (_error != null) ...[
              LuxeNotice(
                message: _error!,
                icon: Icons.wifi_off_rounded,
                color: LuxeColors.danger,
              ),
              const SizedBox(height: 14),
            ],
            LuxeSettingsGroup(
              children: [
                LuxeSettingsRow(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Học từ cuộc trò chuyện',
                  subtitle: snapshot == null
                      ? 'Đang tải…'
                      : snapshot.learningEnabled
                      ? 'Đang bật · ghi nhớ điều hữu ích bạn kể'
                      : 'Đang tắt · BatteryBot không ghi nhớ thêm',
                  trailing: LuxeSwitch(
                    value: snapshot?.learningEnabled ?? true,
                    semanticLabel: 'Học từ cuộc trò chuyện',
                    onChanged: snapshot == null || _busy
                        ? null
                        : (value) => _run(() => _api.setLearning(value)),
                  ),
                ),
                if (snapshot != null)
                  LuxeSettingsRow(
                    icon: Icons.forum_outlined,
                    title: 'Lượt AI hôm nay',
                    subtitle:
                        '${snapshot.usedToday}/${snapshot.dailyLimit} tin · hết lượt sẽ dùng chế độ cơ bản',
                  ),
              ],
            ),
            const SizedBox(height: 22),
            const LuxeSectionLabel('Điều BatteryBot nhớ'),
            if (snapshot == null && _busy)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snapshot != null && snapshot.facts.isEmpty)
              LuxeGlass(
                child: Text(
                  'Chưa có gì. Hãy kể với BatteryBot, ví dụ "Mình đi làm 12 km mỗi ngày" hoặc "Mình hay sạc buổi tối".',
                  style: LuxeText.body,
                ),
              )
            else if (snapshot != null)
              LuxeSettingsGroup(
                children: [
                  for (final fact in snapshot.facts.reversed)
                    LuxeSettingsRow(
                      key: ValueKey('memory-fact-${fact.id}'),
                      icon: Icons.bookmark_outline_rounded,
                      title: fact.text,
                      subtitle: _categoryLabels[fact.category] ?? 'Khác',
                      trailing: IconButton(
                        tooltip: 'Quên điều này',
                        icon: const Icon(
                          Icons.close_rounded,
                          color: LuxeColors.muted,
                        ),
                        onPressed: _busy
                            ? null
                            : () => _run(() => _api.forget(fact.id)),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 24),
            if (snapshot != null && snapshot.facts.isNotEmpty)
              LuxeDangerButton(
                label: 'Xóa mọi điều đã nhớ',
                icon: Icons.delete_outline_rounded,
                onPressed: _busy ? null : _clearAll,
              ),
          ],
        ),
      ),
    );
  }
}
