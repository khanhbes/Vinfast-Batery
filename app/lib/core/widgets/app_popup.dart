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
  static final Set<String> _shownSignatures = <String>{};

  static void showSuccess(
    String title, {
    String? detail,
    VoidCallback? action,
  }) => _show(AppNoticeKind.success, title, detail, action);

  static void showError(
    String title, {
    String? detail,
    VoidCallback? action,
    bool userInitiated = false,
  }) => _show(
    AppNoticeKind.error,
    title,
    detail,
    action,
    userInitiated: userInitiated,
  );

  static void showWarning(
    String title, {
    String? detail,
    VoidCallback? action,
    String actionLabel = 'MỞ',
    bool persistent = false,
    bool userInitiated = false,
  }) => _show(
    AppNoticeKind.warning,
    title,
    detail,
    action,
    actionLabel: actionLabel,
    persistent: persistent,
    userInitiated: userInitiated,
  );

  static void showInfo(String title, {String? detail, VoidCallback? action}) =>
      _show(AppNoticeKind.info, title, detail, action);

  /// Xóa bộ nhớ đệm các lỗi đã hiển thị (gọi khi đổi tab, đổi xe hoặc kéo refresh).
  static void clearShownErrors() {
    _shownSignatures.clear();
  }

  /// Đặt lại một lỗi cụ thể để có thể hiển thị lại nếu cần.
  static void resetError(String title, {String? detail}) {
    _shownSignatures.remove('${AppNoticeKind.error}|$title|$detail');
    _shownSignatures.remove('${AppNoticeKind.warning}|$title|$detail');
  }

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
    VoidCallback? action, {
    String actionLabel = 'MỞ',
    bool persistent = false,
    bool userInitiated = false,
  }) {
    final signature = '$kind|$title|$detail';
    final now = DateTime.now();

    // Chống spam: Nếu là lỗi hoặc cảnh báo và không phải do người dùng chủ động bấm,
    // chỉ hiển thị 1 lần duy nhất cho đến khi clearShownErrors() hoặc user bấm lại.
    if ((kind == AppNoticeKind.error || kind == AppNoticeKind.warning) && !userInitiated) {
      if (_shownSignatures.contains(signature)) {
        return;
      }
    }

    if (_lastSignature == signature &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastSignature = signature;
    _lastShownAt = now;

    if (kind == AppNoticeKind.error || kind == AppNoticeKind.warning) {
      _shownSignatures.add(signature);
    }
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
        actionLabel: actionLabel,
        onDismiss: dismiss,
      ),
    );
    overlay.insert(_entry!);
    if (!persistent) {
      _timer = Timer(
        kind == AppNoticeKind.error
            ? const Duration(seconds: 6)
            : const Duration(seconds: 4),
        dismiss,
      );
    }
  }
}

class _NoticeOverlay extends StatelessWidget {
  const _NoticeOverlay({
    required this.kind,
    required this.title,
    required this.detail,
    required this.action,
    required this.actionLabel,
    required this.onDismiss,
  });
  final AppNoticeKind kind;
  final String title;
  final String? detail;
  final VoidCallback? action;
  final String actionLabel;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (color, icon) = switch (kind) {
      AppNoticeKind.success => (
        const Color(0xFF15803D),
        Icons.check_circle_rounded,
      ),
      // In-app failures use a calm amber accent. Red remains reserved for
      // emergency OFF and hardware danger controls, not routine notices.
      AppNoticeKind.error => (
        const Color(0xFFF59E0B),
        Icons.error_outline_rounded,
      ),
      AppNoticeKind.warning => (
        const Color(0xFFB45309),
        Icons.warning_amber_rounded,
      ),
      AppNoticeKind.info => (colors.primary, Icons.info_rounded),
    };
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 10,
      left: 16,
      right: 16,
      child: SafeArea(
        bottom: false,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, -10 * (1 - value)),
              child: child,
            ),
          ),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Icon(icon, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          if (detail != null)
                            Text(
                              detail!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    if (action != null)
                      TextButton(onPressed: action, child: Text(actionLabel)),
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
      ),
    );
  }
}
