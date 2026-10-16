import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';

/// Which relay command is in flight.
enum RelayCommandKind { on, off, offAwaitingReadback }

/// Honest progress for a relay command (Task 122): the command is sent and
/// the relay is shown as changed only after the server's Shelly readback.
/// The elapsed counter lets the user see the command is still alive instead
/// of a frozen button. Static visuals only — no endless animation.
class CommandProgressStrip extends StatefulWidget {
  const CommandProgressStrip({super.key, required this.kind, this.clock});

  final RelayCommandKind kind;

  /// Test hook.
  final DateTime Function()? clock;

  @override
  State<CommandProgressStrip> createState() => _CommandProgressStripState();
}

class _CommandProgressStripState extends State<CommandProgressStrip> {
  late DateTime _since;
  Timer? _timer;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _since = _now();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only tick while the route is visible.
    final active = TickerMode.valuesOf(context).enabled;
    if (active && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!active) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void didUpdateWidget(CommandProgressStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind &&
        !(oldWidget.kind == RelayCommandKind.off &&
            widget.kind == RelayCommandKind.offAwaitingReadback)) {
      _since = _now();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _now().difference(_since).inSeconds.clamp(0, 999);
    final (title, step2) = switch (widget.kind) {
      RelayCommandKind.on => (
        'Đang bật sạc',
        'Chờ Shelly xác nhận relay + hẹn giờ',
      ),
      RelayCommandKind.off => ('Đang tắt sạc', 'Chờ Shelly xác nhận đã tắt'),
      RelayCommandKind.offAwaitingReadback => (
        'Đã gửi lệnh tắt',
        'Shelly Cloud chưa báo về · không gửi lại lệnh',
      ),
    };
    final sent = widget.kind == RelayCommandKind.offAwaitingReadback;
    final accent = widget.kind == RelayCommandKind.on
        ? LuxeColors.emerald
        : LuxeColors.champagne;
    return Semantics(
      liveRegion: true,
      label: '$title. $step2. $seconds giây.',
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('command-progress-strip'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$seconds giây',
                  key: const ValueKey('command-progress-elapsed'),
                  style: const TextStyle(
                    color: LuxeColors.muted,
                    fontSize: 12.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Step(label: 'Gửi lệnh', done: true, accent: accent),
            _Step(label: step2, done: sent, current: !sent, accent: accent),
            _Step(label: 'Đã xác minh', done: false, accent: accent),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.done,
    required this.accent,
    this.current = false,
  });

  final String label;
  final bool done;
  final bool current;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final color = done || current ? accent : LuxeColors.dim;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              done
                  ? Icons.check_circle_rounded
                  : current
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 15,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: done || current ? LuxeColors.text : LuxeColors.dim,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
