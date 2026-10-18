import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/luxe_theme.dart';

/// What could not be reached.
enum ConnectionIssue {
  /// The phone has no Internet.
  internet,

  /// The app server did not answer.
  server,

  /// The server answered; the Shelly plug is offline.
  charger,

  /// A charge is running and the server lost the plug for a while: the
  /// plug's own timer still switches it off.
  chargerWhileCharging,
}

/// One way to say "connection lost" everywhere (the app bar strip, the
/// Charge tab, a running charge): same icon language, wording, retry button
/// and automatic retry countdown. Before, each place had its own strip,
/// notice or popup (QA 130).
///
/// Motion is tied to real activity only: the retry spinner runs while a
/// retry is in flight, and the countdown ticks while the notice is visible.
class LuxeConnectionNotice extends StatefulWidget {
  const LuxeConnectionNotice({
    super.key,
    required this.issue,
    this.title,
    this.detail,
    this.onRetry,
    this.autoRetry = true,
    this.nextRetryAt,
    this.lastGoodAt,
    this.compact = false,
    this.clock,
  });

  final ConnectionIssue issue;
  final String? title;
  final String? detail;

  /// Manual "Thử lại ngay" and, with [autoRetry], the automatic retries.
  final Future<void> Function()? onRetry;

  /// Retry by itself with backoff (5, 15, 30, 60 s) while shown.
  final bool autoRetry;

  /// When the owner already schedules retries, show its countdown instead.
  final DateTime? nextRetryAt;

  /// The last good reading, so the owner knows how old the screen is.
  final DateTime? lastGoodAt;

  /// Slim strip for the top of the app.
  final bool compact;

  /// Test hook.
  final DateTime Function()? clock;

  static const backoff = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  static (String, String, IconData) copyFor(ConnectionIssue issue) =>
      switch (issue) {
        ConnectionIssue.internet => (
          'Mất kết nối Internet',
          'Điện thoại đang không có mạng. Dữ liệu gần nhất vẫn được giữ; '
              'app tự kết nối lại khi có mạng.',
          Icons.wifi_off_rounded,
        ),
        ConnectionIssue.server => (
          'Chưa liên lạc được máy chủ',
          'Bật sạc tạm khóa cho tới khi đọc lại được trạng thái ổ. '
              'Tắt sạc vẫn luôn gửi được.',
          Icons.cloud_off_rounded,
        ),
        ConnectionIssue.charger => (
          'Ổ Shelly đang ngoại tuyến',
          'Kiểm tra ổ còn điện và Wi-Fi nhà vẫn hoạt động (đèn trên ổ).',
          Icons.power_off_rounded,
        ),
        ConnectionIssue.chargerWhileCharging => (
          'Tạm mất liên lạc với ổ sạc',
          'Xe vẫn sạc theo hẹn giờ cài sẵn trên ổ, ổ tự tắt khi hết giờ.',
          Icons.sync_problem_rounded,
        ),
      };

  @override
  State<LuxeConnectionNotice> createState() => _LuxeConnectionNoticeState();
}

class _LuxeConnectionNoticeState extends State<LuxeConnectionNotice> {
  Timer? _ticker;
  DateTime? _autoAt;
  int _attempt = 0;
  bool _retrying = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  bool get _auto => widget.autoRetry && widget.onRetry != null;

  @override
  void initState() {
    super.initState();
    if (_auto) _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Tick only while visible (another tab, a pushed route: paused).
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else if (!visible) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _schedule() {
    final delays = LuxeConnectionNotice.backoff;
    _autoAt = _now().add(delays[_attempt.clamp(0, delays.length - 1)]);
  }

  void _tick() {
    if (!mounted) return;
    final due = _autoAt;
    if (_auto && !_retrying && due != null && !_now().isBefore(due)) {
      unawaited(_retry(automatic: true));
      return;
    }
    if (due != null || widget.nextRetryAt != null) setState(() {});
  }

  Future<void> _retry({bool automatic = false}) async {
    final retry = widget.onRetry;
    if (retry == null || _retrying) return;
    if (!automatic) HapticFeedback.selectionClick();
    setState(() {
      _retrying = true;
      _autoAt = null;
    });
    try {
      await retry();
    } on Object {
      // Still offline: the notice stays and the next attempt is scheduled.
    } finally {
      if (mounted) {
        setState(() {
          _retrying = false;
          _attempt++;
          if (_auto) _schedule();
        });
      }
    }
  }

  String? _countdown() {
    final at = _auto ? _autoAt : widget.nextRetryAt;
    if (at == null) return null;
    final seconds = at.difference(_now()).inSeconds;
    return seconds <= 0 ? 'Sắp thử lại…' : 'Tự thử lại sau $seconds giây';
  }

  static String _clock(DateTime at) {
    final local = at.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final (baseTitle, baseDetail, icon) = LuxeConnectionNotice.copyFor(
      widget.issue,
    );
    final title = widget.title ?? baseTitle;
    final detail = widget.detail ?? baseDetail;
    final status = _retrying ? 'Đang kết nối lại…' : _countdown();
    final lastGood = widget.lastGoodAt;
    const accent = LuxeColors.champagne;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    // Large text: stack the footer, icon-only button in the slim strip.
    final large = MediaQuery.textScalerOf(context).scale(10) / 10 > 1.3;

    final button = widget.onRetry == null
        ? null
        : _RetryButton(
            retrying: _retrying,
            reduceMotion: reduce,
            compact: widget.compact,
            iconOnly: widget.compact && large,
            onPressed: _retrying ? null : () => _retry(),
          );

    if (widget.compact) {
      return Semantics(
        container: true,
        liveRegion: true,
        label: '$title. ${status ?? ''}',
        child: Container(
          key: const ValueKey('connection-notice-compact'),
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: LuxeColors.sheet,
            border: Border(
              bottom: BorderSide(color: accent.withValues(alpha: 0.35)),
            ),
          ),
          child: Row(
            children: [
              _IssueIcon(icon: icon, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: LuxeColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (status != null)
                      ExcludeSemantics(
                        child: Text(
                          status,
                          key: const ValueKey('connection-notice-status'),
                          style: const TextStyle(
                            color: LuxeColors.muted,
                            fontSize: 11.5,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ?button,
            ],
          ),
        ),
      );
    }

    final statusBlock = ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status != null)
            Text(
              status,
              key: const ValueKey('connection-notice-status'),
              style: const TextStyle(
                color: LuxeColors.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          if (lastGood != null)
            Text(
              'Lần đọc tốt gần nhất ${_clock(lastGood)}',
              style: const TextStyle(color: LuxeColors.dim, fontSize: 12),
            ),
        ],
      ),
    );

    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $detail',
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.10),
              accent.withValues(alpha: 0.03),
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.32)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IssueIcon(icon: icon, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: LuxeColors.text,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          detail,
                          style: const TextStyle(
                            color: LuxeColors.muted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(height: 1, color: accent.withValues(alpha: 0.16)),
            const SizedBox(height: 8),
            if (large) ...[
              statusBlock,
              if (button != null) ...[
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight, child: button),
              ],
            ] else
              Row(
                children: [
                  Expanded(child: statusBlock),
                  if (button != null) ...[const SizedBox(width: 12), button],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _IssueIcon extends StatelessWidget {
  const _IssueIcon({required this.icon, required this.size});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2A2C30), Color(0xFF111214)],
      ),
      border: Border.all(color: LuxeColors.champagne.withValues(alpha: 0.45)),
    ),
    child: Icon(icon, size: size * 0.46, color: LuxeColors.champagne),
  );
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({
    required this.retrying,
    required this.reduceMotion,
    required this.compact,
    required this.onPressed,
    this.iconOnly = false,
  });

  final bool retrying;
  final bool reduceMotion;
  final bool compact;
  final bool iconOnly;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final leading = retrying && !reduceMotion
        ? const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: LuxeColors.text,
            ),
          )
        : const Icon(Icons.refresh_rounded, size: 17);
    return Semantics(
      button: true,
      label: retrying ? 'Đang thử lại' : 'Thử lại ngay',
      excludeSemantics: true,
      child: TextButton(
        key: const ValueKey('connection-notice-retry'),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: LuxeColors.text,
          disabledForegroundColor: LuxeColors.muted,
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
          shape: const StadiumBorder(
            side: BorderSide(color: LuxeColors.hairlineStrong),
          ),
        ),
        child: iconOnly
            ? leading
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  leading,
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      retrying
                          ? 'Đang thử'
                          : (compact ? 'Thử lại' : 'Thử lại ngay'),
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
