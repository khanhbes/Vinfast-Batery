import 'dart:async';

import 'package:flutter/material.dart';

enum AppNoticeKind { success, error, warning, info }

class AppPopup {
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();
  static final navigatorKey = GlobalKey<NavigatorState>();
  static OverlayEntry? _entry;
  static Timer? _timer;
  static String? _lastSignature;
  static DateTime? _lastShownAt;

  static void showSuccess(String title, {String? detail, VoidCallback? action}) =>
      _show(AppNoticeKind.success, title, detail, action);
  static void showError(String title, {String? detail, VoidCallback? action}) =>
      _show(AppNoticeKind.error, title, detail, action);
  static void showWarning(String title, {String? detail, VoidCallback? action}) =>
      _show(AppNoticeKind.warning, title, detail, action);
  static void showInfo(String title, {String? detail, VoidCallback? action}) =>
      _show(AppNoticeKind.info, title, detail, action);

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  static void _show(
    AppNoticeKind kind,
    String title,
    String? detail,
    VoidCallback? action,
  ) {
    final signature = '$kind|$title|$detail';
    final now = DateTime.now();
    if (_lastSignature == signature &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastSignature = signature;
    _lastShownAt = now;
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(detail == null ? title : '$title\n$detail')),
      );
      return;
    }
    dismiss();
    _entry = OverlayEntry(
      builder: (context) => _NoticeOverlay(
        kind: kind,
        title: title,
        detail: detail,
        action: action,
        onDismiss: dismiss,
      ),
    );
    overlay.insert(_entry!);
    _timer = Timer(
      kind == AppNoticeKind.error
          ? const Duration(seconds: 6)
          : const Duration(seconds: 4),
      dismiss,
    );
  }
}

class _NoticeOverlay extends StatelessWidget {
  const _NoticeOverlay({
    required this.kind,
    required this.title,
    required this.detail,
    required this.action,
    required this.onDismiss,
  });
  final AppNoticeKind kind;
  final String title;
  final String? detail;
  final VoidCallback? action;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (color, icon) = switch (kind) {
      AppNoticeKind.success => (const Color(0xFF15803D), Icons.check_circle_rounded),
      AppNoticeKind.error => (colors.error, Icons.error_rounded),
      AppNoticeKind.warning => (const Color(0xFFB45309), Icons.warning_amber_rounded),
      AppNoticeKind.info => (colors.primary, Icons.info_rounded),
    };
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 10,
      left: 16,
      right: 16,
      child: SafeArea(
        bottom: false,
        child: Material(
          color: colors.surface,
          elevation: 10,
          shadowColor: Colors.black45,
          borderRadius: BorderRadius.circular(16),
          child: Semantics(
            liveRegion: true,
            label: detail == null ? title : '$title. $detail',
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border(left: BorderSide(color: color, width: 4)),
              ),
              child: Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                        if (detail != null)
                          Text(detail!, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (action != null)
                    TextButton(onPressed: action, child: const Text('MỞ')),
                  IconButton(
                    tooltip: 'Đóng thông báo',
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
