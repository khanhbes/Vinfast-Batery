import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';

/// Which relay command is in flight.
enum RelayCommandKind { on, off, offAwaitingReadback }

/// The wait after a swipe/Stop (Task 122, redesigned QA 130).
///
/// Honest about what the app knows: the command went to the server, and the
/// relay counts as changed only after the server's Shelly readback (the
/// server checks safety, switches the plug with its timer and reads it back
/// in one request). A ring sweeps while — and only while — the command is
/// in flight, stepped by the same 1 s tick as the elapsed counter (no
/// endless controller, still under reduced motion); a slow Cloud gets a
/// calm note instead of a frozen look; [verified] closes the wait with an
/// emerald check.
class CommandProgressStrip extends StatefulWidget {
  const CommandProgressStrip({
    super.key,
    required this.kind,
    this.verified = false,
    this.clock,
  });

  final RelayCommandKind kind;

  /// The command finished and was read back.
  final bool verified;

  /// Test hook.
  final DateTime Function()? clock;

  /// After this the note explains the delay (ON usually takes 10–20 s).
  static const slowAfterOn = Duration(seconds: 25);
  static const slowAfterOff = Duration(seconds: 10);

  @override
  State<CommandProgressStrip> createState() => _CommandProgressStripState();
}

class _CommandProgressStripState extends State<CommandProgressStrip> {
  late DateTime _since;
  Timer? _timer;
  double _turns = 0;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _since = _now();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only tick while the route is visible and the command is in flight.
    final active = TickerMode.valuesOf(context).enabled && !widget.verified;
    if (active && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _turns += 0.35);
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
    if (widget.verified && !oldWidget.verified) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final elapsed = _now().difference(_since);
    final seconds = elapsed.inSeconds.clamp(0, 999);
    final on = widget.kind == RelayCommandKind.on;
    final verified = widget.verified;
    final accent = verified
        ? LuxeColors.emerald
        : on
        ? LuxeColors.emerald
        : LuxeColors.champagne;

    final title = verified
        ? (on ? 'Đã bật sạc · đã xác minh' : 'Đã tắt sạc · đã xác minh')
        : switch (widget.kind) {
            RelayCommandKind.on => 'Đang bật sạc',
            RelayCommandKind.off => 'Đang tắt sạc',
            RelayCommandKind.offAwaitingReadback => 'Đã gửi lệnh tắt',
          };
    final subtitle = verified
        ? (on
              ? 'Shelly báo relay bật và hẹn giờ tự ngắt đang chạy.'
              : 'Shelly báo ổ đã tắt.')
        : switch (widget.kind) {
            RelayCommandKind.on =>
              'Máy chủ kiểm tra an toàn, bật ổ kèm hẹn giờ rồi đọc lại.',
            RelayCommandKind.off => 'Chờ Shelly xác nhận ổ đã tắt.',
            RelayCommandKind.offAwaitingReadback =>
              'Shelly Cloud chưa báo về · không gửi lại lệnh.',
          };
    final steps = switch (widget.kind) {
      RelayCommandKind.on => const [
        'Gửi lệnh tới máy chủ',
        'Kiểm tra an toàn và bật ổ có hẹn giờ',
        'Đọc lại: relay bật, hẹn giờ chạy',
      ],
      RelayCommandKind.off || RelayCommandKind.offAwaitingReadback => const [
        'Gửi lệnh tắt',
        'Shelly xác nhận đã tắt',
        'Kết thúc phiên sạc',
      ],
    };
    // Index of the step in progress (all done once verified).
    final current = verified ? steps.length : 1;
    final slow =
        !verified &&
        elapsed >=
            (on
                ? CommandProgressStrip.slowAfterOn
                : CommandProgressStrip.slowAfterOff);
    final usual = on ? 'thường 10–20 giây' : 'thường 3–8 giây';

    return Semantics(
      liveRegion: true,
      label: verified
          ? '$title. $subtitle'
          : '$title. $subtitle. $seconds giây.',
      excludeSemantics: true,
      child: AnimatedContainer(
        key: ValueKey(
          verified ? 'command-progress-verified' : 'command-progress-strip',
        ),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 300),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.12),
              accent.withValues(alpha: 0.03),
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _CommandRing(
                  accent: accent,
                  turns: _turns,
                  reduceMotion: reduce,
                  verified: verified,
                  icon: on
                      ? Icons.bolt_rounded
                      : Icons.power_settings_new_rounded,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: verified
                              ? LuxeColors.emerald
                              : LuxeColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: LuxeColors.muted,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                      if (!verified) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '$seconds giây',
                              key: const ValueKey('command-progress-elapsed'),
                              style: TextStyle(
                                color: accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            Text(
                              '· $usual',
                              style: const TextStyle(
                                color: LuxeColors.dim,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < steps.length; i++)
              _Step(
                label: steps[i],
                done: i < current,
                current: i == current,
                last: i == steps.length - 1,
                accent: accent,
              ),
            if (slow) ...[
              const SizedBox(height: 8),
              Container(
                key: const ValueKey('command-progress-slow'),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: LuxeColors.champagne.withValues(alpha: 0.08),
                  border: Border.all(
                    color: LuxeColors.champagne.withValues(alpha: 0.28),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: LuxeColors.champagne,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        on
                            ? 'Shelly Cloud phản hồi chậm hơn thường lệ. App '
                                  'không gửi lại lệnh bật; kết quả sẽ tự hiện.'
                            : 'Shelly Cloud phản hồi chậm. App không gửi lại '
                                  'lệnh; ổ cũng tự tắt theo hẹn giờ.',
                        style: const TextStyle(
                          color: LuxeColors.text,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ring with a sweeping arc (in flight) or a full arc and check (verified).
class _CommandRing extends StatelessWidget {
  const _CommandRing({
    required this.accent,
    required this.turns,
    required this.reduceMotion,
    required this.verified,
    required this.icon,
  });

  final Color accent;
  final double turns;
  final bool reduceMotion;
  final bool verified;
  final IconData icon;

  static const double size = 64;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(size),
            painter: _TrackPainter(color: accent.withValues(alpha: 0.16)),
          ),
          if (verified)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: LuxeMotion.enter,
              builder: (context, t, _) => CustomPaint(
                size: const Size.square(size),
                painter: _ArcPainter(color: accent, sweep: t, start: 0),
              ),
            )
          else
            AnimatedRotation(
              turns: reduceMotion ? 0 : turns,
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(seconds: 1),
              child: CustomPaint(
                size: const Size.square(size),
                painter: _ArcPainter(color: accent, sweep: 0.28, start: 0),
              ),
            ),
          Container(
            width: size - 18,
            height: size - 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF26282C), Color(0xFF101113)],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: verified ? 0.35 : 0.18),
                  blurRadius: 16,
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                verified ? Icons.check_rounded : icon,
                key: ValueKey(verified),
                size: 24,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  const _TrackPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide / 2 - 2,
      paint,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.color != color;
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({
    required this.color,
    required this.sweep,
    required this.start,
  });

  final Color color;

  /// Fraction of the circle.
  final double sweep;
  final double start;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [color.withValues(alpha: 0), color],
        stops: const [0, 1],
        transform: const GradientRotation(-math.pi / 2),
        endAngle: math.max(0.001, sweep) * 2 * math.pi,
      ).createShader(rect);
    canvas.drawArc(
      rect,
      -math.pi / 2 + start * 2 * math.pi,
      sweep * 2 * math.pi,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.color != color || old.sweep != sweep || old.start != start;
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.done,
    required this.current,
    required this.last,
    required this.accent,
  });

  final String label;
  final bool done;
  final bool current;
  final bool last;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final lit = done || current;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          child: Column(
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? accent : Colors.transparent,
                  border: Border.all(
                    color: lit ? accent : LuxeColors.ruleStrong,
                    width: 1.6,
                  ),
                ),
                child: done
                    ? const Icon(
                        Icons.check_rounded,
                        size: 10,
                        color: Color(0xFF0B0C0E),
                      )
                    : current
                    ? Center(
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent,
                          ),
                        ),
                      )
                    : null,
              ),
              if (!last)
                Container(
                  width: 1.6,
                  height: 14,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  color: done
                      ? accent.withValues(alpha: 0.7)
                      : LuxeColors.ruleStrong,
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1, bottom: 6),
            child: Text(
              label,
              style: TextStyle(
                color: lit ? LuxeColors.text : LuxeColors.dim,
                fontSize: 13,
                fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                height: 1.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
