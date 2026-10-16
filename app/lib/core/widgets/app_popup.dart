import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/luxe_theme.dart';
import '../utils/error_mapper.dart';

enum AppNoticeKind { success, error, warning, info }

class AppPopup {
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();
  static final navigatorKey = GlobalKey<NavigatorState>();
  static OverlayEntry? _entry;
  static Timer? _timer;
  static bool _safetyNoticeVisible = false;
  static bool get safetyNoticeVisible => _safetyNoticeVisible;
  static String? _lastSignature;
  static DateTime? _lastShownAt;
  static final Map<String, DateTime> _shownSignatures = <String, DateTime>{};
  static const _failureWindow = Duration(seconds: 60);
  static DateTime Function() _clock = DateTime.now;

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
    String actionLabel = 'Thử lại',
    dynamic error,
    StackTrace? stackTrace,
  }) {
    final friendlyTitle =
        AppNoticeCopy.approved(title) ??
        UserFriendlyErrorMapper.map(error ?? title);
    final friendlyDetail = (detail != null && detail.isNotEmpty)
        ? AppNoticeCopy.error(detail)
        : error != null
        ? UserFriendlyErrorMapper.map(error)
        : null;

    _show(
      AppNoticeKind.error,
      friendlyTitle,
      friendlyDetail == friendlyTitle ? null : friendlyDetail,
      action,
      actionLabel: actionLabel,
      userInitiated: userInitiated,
    );
  }

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
    final cutoff = _clock().subtract(_failureWindow);
    _shownSignatures.removeWhere((_, shownAt) => shownAt.isBefore(cutoff));
  }

  /// Đặt lại một lỗi cụ thể để có thể hiển thị lại nếu cần.
  static void resetError(String title, {String? detail}) {
    for (final kind in [AppNoticeKind.error, AppNoticeKind.warning]) {
      final copy = _safeCopy(kind, title, detail);
      final signature = _signature(kind, copy.$1, copy.$2);
      _shownSignatures.remove(signature);
      if (_lastSignature == signature) {
        _lastSignature = null;
        _lastShownAt = null;
      }
    }
  }

  @visibleForTesting
  static void resetForTesting({DateTime Function()? clock}) {
    dismiss();
    _shownSignatures.clear();
    _lastSignature = null;
    _lastShownAt = null;
    _clock = clock ?? DateTime.now;
  }

  static (String, String?) _safeCopy(
    AppNoticeKind kind,
    String title,
    String? detail,
  ) {
    final approvedTitle = AppNoticeCopy.approved(title);
    final isFailure =
        kind == AppNoticeKind.error || kind == AppNoticeKind.warning;
    final safeTitle =
        approvedTitle ?? (isFailure ? AppNoticeCopy.error(title) : 'Thông báo');
    final safeDetail = detail == null || detail.trim().isEmpty
        ? null
        : AppNoticeCopy.approved(detail) ??
              (title == 'Cảnh báo an toàn sạc'
                  ? AppNoticeCopy.safetyFallback
                  : isFailure
                  ? AppNoticeCopy.error(detail)
                  : null);
    return (safeTitle, safeDetail == safeTitle ? null : safeDetail);
  }

  static String _signature(AppNoticeKind kind, String title, String? detail) =>
      '$kind|${AppNoticeCopy.category(title)}|${AppNoticeCopy.category(detail ?? '')}';

  static void dismiss() {
    _safetyNoticeVisible = false;
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) {
      try {
        entry.remove();
      } catch (_) {
        // Guard against double removal or unmounted race condition
      }
    }
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
    if (WidgetsBinding.instance.rootElement == null) return;

    // This boundary covers success/info too: some legacy callers interpolate
    // device IDs, hostnames or server response text into otherwise friendly copy.
    final copy = _safeCopy(kind, title, detail);
    title = copy.$1;
    detail = copy.$2;
    actionLabel = AppNoticeCopy.actionLabel(actionLabel);
    final signature = _signature(kind, title, detail);
    final now = _clock();
    clearShownErrors();

    // Chống spam: Nếu là lỗi hoặc cảnh báo và không phải do người dùng chủ động bấm,
    // chỉ hiển thị lại khi lỗi phục hồi/reset hoặc failure window đã hết.
    if ((kind == AppNoticeKind.error || kind == AppNoticeKind.warning) &&
        !userInitiated) {
      final shownAt = _shownSignatures[signature];
      if (shownAt != null && now.difference(shownAt) < _failureWindow) {
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
      _shownSignatures[signature] = now;
    }
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      try {
        messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(detail == null ? title : '$title\n$detail')),
        );
      } catch (_) {}
      return;
    }
    dismiss();
    _safetyNoticeVisible = persistent && kind == AppNoticeKind.warning;
    final newEntry = OverlayEntry(
      builder: (context) => _NoticeOverlay(
        kind: kind,
        title: title,
        detail: detail,
        action: action,
        actionLabel: actionLabel,
        onDismiss: dismiss,
        toastKey: signature,
      ),
    );
    _entry = newEntry;

    void insertOverlay() {
      if (!identical(_entry, newEntry) || newEntry.mounted) return;
      final currentOverlay = navigatorKey.currentState?.overlay;
      if (currentOverlay == null) {
        if (identical(_entry, newEntry)) dismiss();
        return;
      }
      try {
        currentOverlay.insert(newEntry);
        if (!persistent) {
          _timer = Timer(
            kind == AppNoticeKind.error
                ? const Duration(milliseconds: 3500)
                : const Duration(milliseconds: 3000),
            dismiss,
          );
        }
      } catch (_) {
        // Guard against any lifecycle or insertion race condition
        if (identical(_entry, newEntry)) dismiss();
      }
    }

    final schedulerPhase = SchedulerBinding.instance.schedulerPhase;
    if (schedulerPhase == SchedulerPhase.persistentCallbacks ||
        schedulerPhase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => insertOverlay());
    } else {
      insertOverlay();
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
    required this.toastKey,
  });
  final AppNoticeKind kind;
  final String title;
  final String? detail;
  final VoidCallback? action;
  final String actionLabel;
  final VoidCallback onDismiss;
  final String toastKey;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Keep the navigation and safety controls below usable, even on a compact
    // device with large text/IME. Only the notice surface intercepts touches.
    final noticeHeight =
        (media.size.height -
                media.padding.vertical -
                media.viewInsets.bottom -
                112)
            .clamp(80.0, 420.0);
    // In-app failures use calm champagne. Rose remains reserved for
    // emergency OFF and hardware danger controls, not routine notices.
    final (color, icon) = switch (kind) {
      AppNoticeKind.success => (LuxeColors.emerald, Icons.check_rounded),
      AppNoticeKind.error => (
        LuxeColors.champagne,
        Icons.error_outline_rounded,
      ),
      AppNoticeKind.warning => (
        const Color(0xFFF0A46B),
        Icons.warning_amber_rounded,
      ),
      AppNoticeKind.info => (LuxeColors.steel, Icons.info_outline_rounded),
    };
    return Positioned(
      top: 0,
      left: 16,
      right: 16,
      child: SafeArea(
        bottom: false,
        minimum: const EdgeInsets.only(top: 10),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 420),
          curve: LuxeMotion.enter,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, -14 * (1 - value)),
              child: Transform.scale(scale: 0.97 + 0.03 * value, child: child),
            ),
          ),
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < -100) {
                onDismiss();
              }
            },
            child: Material(
              type: MaterialType.transparency,
              child: Semantics(
                liveRegion: true,
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: 64,
                    maxHeight: noticeHeight,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xF5141518),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: LuxeColors.hairlineStrong),
                    boxShadow: [
                      const BoxShadow(
                        color: Color(0xB3000000),
                        blurRadius: 28,
                        offset: Offset(0, 10),
                      ),
                      BoxShadow(
                        color: color.withValues(alpha: 0.10),
                        blurRadius: 24,
                        spreadRadius: -6,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color.withValues(alpha: 0.12),
                                  border: Border.all(
                                    color: color.withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Icon(icon, color: color, size: 17),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 13),
                                child: Text(
                                  title,
                                  style: LuxeText.item.copyWith(fontSize: 14.5),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Đóng thông báo',
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              onPressed: onDismiss,
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 19,
                                color: LuxeColors.platinumMid,
                              ),
                            ),
                          ],
                        ),
                        if (detail != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(44, 0, 14, 8),
                            child: Text(
                              detail!,
                              style: LuxeText.caption.copyWith(
                                fontSize: 13.5,
                                height: 1.45,
                              ),
                            ),
                          ),
                        if (action != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                foregroundColor: LuxeColors.emerald,
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              onPressed: action,
                              child: Text(actionLabel),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
