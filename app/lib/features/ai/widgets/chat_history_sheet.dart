import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/theme/plan_style.dart';
import '../../../core/utils/battery_bot_faq.dart';
import '../../../core/widgets/app_popup.dart';
import '../models/chat_session.dart';
import '../services/chat_history_storage.dart';

/// Pinova Bot's conversations on this phone (QA 164: like a modern chat
/// app): search, grouped by day, the last line of each, rename, delete with
/// undo. Opening one gives Pinova Bot that conversation back as context.
class ChatHistorySheet extends StatefulWidget {
  const ChatHistorySheet({
    super.key,
    required this.sessions,
    required this.storage,
    required this.currentId,
    required this.onOpen,
    required this.onNewChat,
    required this.onDeleted,
    this.now,
  });

  final List<ChatSession> sessions;
  final ChatHistoryStorage storage;
  final String? currentId;
  final ValueChanged<String> onOpen;
  final VoidCallback onNewChat;

  /// A conversation was deleted (the open one starts a new chat).
  final ValueChanged<String> onDeleted;

  /// Tests.
  final DateTime? now;

  @override
  State<ChatHistorySheet> createState() => _ChatHistorySheetState();
}

class _ChatHistorySheetState extends State<ChatHistorySheet> {
  late final List<ChatSession> _sessions = List.of(widget.sessions);
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _group(DateTime at, DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    final d = DateTime(at.year, at.month, at.day);
    final days = day.difference(d).inDays;
    if (days <= 0) return 'Hôm nay';
    if (days == 1) return 'Hôm qua';
    if (days < 7) return '7 ngày qua';
    if (days < 30) return '30 ngày qua';
    return 'Cũ hơn';
  }

  static String _time(DateTime at, DateTime now) {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return sameDay
        ? '${two(local.hour)}:${two(local.minute)}'
        : '${local.day}/${local.month}';
  }

  Future<void> _delete(ChatSession session) async {
    final messages = await widget.storage
        .loadSessionMessages(session.id)
        .catchError((_) => const <Never>[]);
    try {
      await widget.storage.deleteSession(session.id);
    } on Object {
      AppPopup.showMessage(
        'Chưa xóa được lịch sử trên máy này. Hãy thử lại.',
        kind: AppNoticeKind.error,
      );
      return;
    }
    if (!mounted) return;
    final index = _sessions.indexWhere((s) => s.id == session.id);
    setState(() => _sessions.removeWhere((s) => s.id == session.id));
    widget.onDeleted(session.id);
    AppPopup.showMessage(
      'Đã xóa cuộc trò chuyện',
      kind: AppNoticeKind.success,
      actionLabel: 'Hoàn tác',
      action: messages.isEmpty
          ? null
          : () async {
              await widget.storage.saveSessionMessages(
                session.id,
                messages,
                title: session.title,
              );
              if (session.renamed) {
                await widget.storage.renameSession(session.id, session.title);
              }
              if (!mounted) return;
              setState(
                () =>
                    _sessions.insert(index.clamp(0, _sessions.length), session),
              );
            },
    );
  }

  Future<void> _rename(ChatSession session) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: session.title),
    );
    final clean = title?.trim() ?? '';
    if (clean.isEmpty || clean == session.title || !mounted) return;
    void show(ChatSession value) => setState(() {
      final index = _sessions.indexWhere((s) => s.id == session.id);
      if (index >= 0) _sessions[index] = value;
    });
    // The new name shows at once; a failed save puts the old one back.
    show(
      ChatSession(
        sessionId: session.sessionId,
        title: clean,
        createdAt: session.createdAt,
        updatedAt: session.updatedAt,
        messageCount: session.messageCount,
        lastMessage: session.lastMessage,
        renamed: true,
      ),
    );
    try {
      await widget.storage.renameSession(session.id, clean);
    } on Object {
      if (!mounted) return;
      show(session);
      AppPopup.showMessage(
        'Chưa đổi được tên. Hãy thử lại.',
        kind: AppNoticeKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();
    final query = BatteryBotFaq.normalize(_search.text);
    final shown = [
      for (final s in _sessions)
        if (query.isEmpty ||
            BatteryBotFaq.normalize(
              '${s.title} ${s.lastMessage ?? ''}',
            ).contains(query))
          s,
    ];
    final rows = <Widget>[];
    String? group;
    for (final session in shown) {
      final name = _group(session.updatedAt.toLocal(), now);
      if (name != group) {
        group = name;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            child: Text(name.toUpperCase(), style: LuxeText.eyebrow),
          ),
        );
      }
      rows.add(_row(session, now));
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history_rounded,
                      color: context.planAccent,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Lịch sử trò chuyện',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: LuxeColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  key: const ValueKey('history-new-chat'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: const Icon(Icons.add_comment_rounded, size: 18),
                  label: const Text('Đoạn chat mới'),
                  onPressed: widget.onNewChat,
                ),
              ],
            ),
            const Text(
              'Lịch sử lưu trên máy này.',
              style: TextStyle(color: LuxeColors.muted, fontSize: 13),
            ),
            if (_sessions.length > 3) ...[
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('history-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                autofillHints: const <String>[],
                decoration: const InputDecoration(
                  hintText: 'Tìm trong lịch sử',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ],
            if (_sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    'Chưa có lịch sử hội thoại nào.',
                    style: TextStyle(color: LuxeColors.muted, fontSize: 13),
                  ),
                ),
              )
            else if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    'Không có cuộc trò chuyện nào khớp.',
                    key: ValueKey('history-none'),
                    style: TextStyle(color: LuxeColors.muted, fontSize: 13),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView(shrinkWrap: true, children: rows),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(ChatSession session, DateTime now) {
    final current = session.id == widget.currentId;
    final last = (session.lastMessage ?? '').replaceAll(RegExp(r'\s+'), ' ');
    return Material(
      key: ValueKey('history-${session.id}'),
      color: current
          ? context.planAccent.withValues(alpha: 0.10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => widget.onOpen(session.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
            child: Row(
              children: [
                Icon(
                  current
                      ? Icons.chat_bubble_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 18,
                  color: current ? context.planAccent : LuxeColors.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: current
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: LuxeColors.text,
                        ),
                      ),
                      if (last.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: LuxeColors.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _time(session.updatedAt, now),
                  style: const TextStyle(fontSize: 11.5, color: LuxeColors.dim),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('history-menu-${session.id}'),
                  tooltip: 'Tùy chọn cuộc trò chuyện',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: LuxeColors.muted,
                  ),
                  color: LuxeColors.sheet,
                  onSelected: (value) =>
                      value == 'rename' ? _rename(session) : _delete(session),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('Đổi tên'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('Xóa trên máy này'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Owns its text controller, so closing the dialog (an animation) never
/// uses a disposed one.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: LuxeColors.sheet,
    title: const Text('Đổi tên cuộc trò chuyện'),
    content: TextField(
      key: const ValueKey('history-rename-field'),
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      textInputAction: TextInputAction.done,
      onSubmitted: (value) => Navigator.of(context).pop(value),
      decoration: const InputDecoration(hintText: 'Tên mới'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        child: const Text('Hủy'),
      ),
      FilledButton(
        key: const ValueKey('history-rename-save'),
        onPressed: () => Navigator.of(context).pop(_controller.text),
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
        child: const Text('Lưu'),
      ),
    ],
  );
}
