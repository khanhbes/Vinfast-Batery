import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/services/luxe_feedback.dart';
import '../../../core/theme/luxe_theme.dart';
import '../../../core/theme/plan_style.dart';
import '../../../core/widgets/luxe_kit.dart';

/// The two moments of a charge (QA 151, owner's choice): the plug answering
/// ON, and a session that finished. Each plays once, forward only, over the
/// screen; neither takes touches away from Stop for longer than it plays
/// (the start one takes none at all). With "Giảm chuyển động" nothing is
/// drawn: only the haptic and the chime remain.
///
/// Emerald here is the verified state (relay read back ON / session ended
/// normally), per the LUXE colour rules.
abstract final class ChargeCeremony {
  static OverlayEntry? _entry;

  /// True while one is on screen (tests, and so two never stack).
  static bool get isPlaying => _entry?.mounted ?? false;

  static void _remove() {
    final entry = _entry;
    _entry = null;
    // The overlay may be gone already (screen closed mid-scene).
    if (entry != null && entry.mounted) entry.remove();
  }

  /// Relay verified ON: a current runs up into a ring that closes and
  /// pulses once. 1.5 s, does not block touches.
  static void started(BuildContext context) {
    LuxeFeedback.chargeStarted();
    if (luxeReduceMotion(context) || isPlaying) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final colors = PlanStyle.of(context).accentColors;
    _entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: _Play(
          duration: const Duration(milliseconds: 1500),
          onDone: _remove,
          builder: (t) => CustomPaint(
            size: Size.infinite,
            painter: _StartPainter(t: t, colors: colors),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  /// A session that ended normally: the ring fills to the level reached,
  /// the tick draws itself, energy and time count up. 2.4 s; a tap skips.
  /// Completes when it is gone, so what follows (the "% trên xe" sheet)
  /// does not open underneath.
  static Future<void> finished(
    BuildContext context, {
    required double startPercent,
    required double endPercent,
    required double energyKwh,
    required String durationText,
  }) {
    LuxeFeedback.chargeDone();
    if (luxeReduceMotion(context) || isPlaying) return Future.value();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return Future.value();
    final colors = PlanStyle.of(context).accentColors;
    final done = Completer<void>();
    void close() {
      _remove();
      if (!done.isCompleted) done.complete();
    }

    _entry = OverlayEntry(
      builder: (_) => Semantics(
        liveRegion: true,
        label:
            'Đã sạc xong, khoảng ${endPercent.round()} phần trăm, '
            '${energyKwh.toStringAsFixed(2)} ki lô oát giờ, $durationText',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: close,
          child: _Play(
            duration: const Duration(milliseconds: 2400),
            onDone: close,
            builder: (t) => _FinishedScene(
              t: t,
              colors: colors,
              startPercent: startPercent.clamp(0, 100).toDouble(),
              endPercent: endPercent.clamp(0, 100).toDouble(),
              energyKwh: energyKwh,
              durationText: durationText,
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
    return done.future;
  }

  /// Tests and screens that are going away.
  static void dismiss() => _remove();
}

/// One forward run of [duration], then [onDone].
class _Play extends StatefulWidget {
  const _Play({
    required this.duration,
    required this.onDone,
    required this.builder,
  });

  final Duration duration;
  final VoidCallback onDone;
  final Widget Function(double t) builder;

  @override
  State<_Play> createState() => _PlayState();
}

class _PlayState extends State<_Play> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenCompleteOrCancel(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => widget.builder(_c.value),
  );
}

double _seg(double t, double from, double to, [Curve curve = Curves.linear]) =>
    curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

Paint _glow(Color color, double width, double blur) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeWidth = width
  ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

class _StartPainter extends CustomPainter {
  _StartPainter({required this.t, required this.colors});

  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final fade = 1 - _seg(t, 0.82, 1, Curves.easeIn);
    final veil = _seg(t, 0, 0.18, Curves.easeOut) * fade;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.38 * veil),
    );
    final centre = Offset(size.width / 2, size.height * 0.42);
    const radius = 62.0;
    final accent = colors[colors.length ~/ 2];

    // 1. The current: a bright head with a fading tail, from the slider up
    //    into the bottom of the ring.
    final rise = _seg(t, 0, 0.36, LuxeMotion.enter);
    if (rise > 0 && t < 0.5) {
      final from = Offset(size.width / 2, size.height * 0.9);
      final to = centre + const Offset(0, radius);
      final head = Offset.lerp(from, to, rise)!;
      final tail = Offset.lerp(from, to, math.max(0, rise - 0.28))!;
      final out = 1 - _seg(t, 0.36, 0.5);
      final shader = ui.Gradient.linear(tail, head, [
        accent.withValues(alpha: 0),
        Colors.white.withValues(alpha: 0.95 * out),
      ]);
      canvas.drawLine(tail, head, _glow(accent, 10, 12)..shader = shader);
      canvas.drawLine(
        tail,
        head,
        Paint()
          ..shader = shader
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3,
      );
    }

    // 2. The ring closes from the bottom, both ways, then pulses once.
    final close = _seg(t, 0.3, 0.66, Curves.easeOutCubic);
    if (close > 0) {
      final pulse = math.sin(_seg(t, 0.62, 0.9) * math.pi);
      final r = radius + 10 * pulse;
      final rect = Rect.fromCircle(center: centre, radius: r);
      final sweep = math.pi * close;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4
        ..shader = SweepGradient(
          colors: [...colors, colors.first],
          transform: const GradientRotation(math.pi / 2),
        ).createShader(rect);
      ring.color = Colors.white.withValues(alpha: fade);
      final bloom = _glow(
        accent.withValues(alpha: (0.35 + 0.4 * pulse) * fade),
        10,
        18 + 14 * pulse,
      );
      for (final dir in const [1.0, -1.0]) {
        canvas.drawArc(rect, math.pi / 2, sweep * dir, false, bloom);
        canvas.drawArc(rect, math.pi / 2, sweep * dir, false, ring);
      }
    }

    // 3. The bolt lands in the middle: verified, so emerald.
    final land = _seg(t, 0.5, 0.74, Curves.easeOutBack);
    if (land > 0) {
      final icon = Icons.bolt_rounded;
      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: 56 * land,
            color: LuxeColors.emerald.withValues(alpha: fade),
            shadows: [
              Shadow(
                color: LuxeColors.emerald.withValues(alpha: 0.6 * fade),
                blurRadius: 22,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        centre - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_StartPainter old) => old.t != t;
}

class _FinishedScene extends StatelessWidget {
  const _FinishedScene({
    required this.t,
    required this.colors,
    required this.startPercent,
    required this.endPercent,
    required this.energyKwh,
    required this.durationText,
  });

  final double t;
  final List<Color> colors;
  final double startPercent;
  final double endPercent;
  final double energyKwh;
  final String durationText;

  @override
  Widget build(BuildContext context) {
    final fade = 1 - _seg(t, 0.88, 1, Curves.easeIn);
    final veil = _seg(t, 0, 0.14, Curves.easeOut) * fade;
    final fill = _seg(t, 0.06, 0.5, Curves.easeInOutCubic);
    final percent = startPercent + (endPercent - startPercent) * fill;
    final lines = _seg(t, 0.52, 0.74, LuxeMotion.enter);
    final count = _seg(t, 0.52, 0.82, Curves.easeOutCubic);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.62 * veil),
      child: Opacity(
        opacity: fade,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 188,
                  child: CustomPaint(
                    painter: _FinishPainter(
                      t: t,
                      colors: colors,
                      from: startPercent / 100,
                      to: percent / 100,
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 26),
                        child: Text(
                          '${percent.round()}%',
                          style: const TextStyle(
                            color: LuxeColors.text,
                            fontSize: 40,
                            height: 1,
                            fontWeight: FontWeight.w200,
                            fontFeatures: [ui.FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Opacity(
                  opacity: lines,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - lines)),
                    child: Column(
                      children: [
                        const Text(
                          'Đã sạc xong',
                          textAlign: TextAlign.center,
                          style: LuxeText.title,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${(energyKwh * count).toStringAsFixed(2)} kWh · '
                          '$durationText',
                          textAlign: TextAlign.center,
                          style: LuxeText.caption.copyWith(
                            fontFeatures: const [
                              ui.FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Mức pin là ước tính',
                          textAlign: TextAlign.center,
                          style: LuxeText.caption,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FinishPainter extends CustomPainter {
  _FinishPainter({
    required this.t,
    required this.colors,
    required this.from,
    required this.to,
  });

  final double t;
  final List<Color> colors;
  final double from;
  final double to;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 10;
    final rect = Rect.fromCircle(center: centre, radius: radius);
    const top = -math.pi / 2;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = LuxeColors.hairlineStrong,
    );
    // What was already there, quiet; what this charge added, lit.
    final had = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6
      ..color = LuxeColors.platinumLow;
    canvas.drawArc(rect, top, 2 * math.pi * from, false, had);
    final added = 2 * math.pi * math.max(0, to - from);
    if (added > 0) {
      final settle = math.sin(_seg(t, 0.46, 0.72) * math.pi);
      final accent = colors[colors.length ~/ 2];
      canvas.drawArc(
        rect,
        top + 2 * math.pi * from,
        added,
        false,
        _glow(
          accent.withValues(alpha: 0.4 + 0.4 * settle),
          12,
          14 + 12 * settle,
        ),
      );
      canvas.drawArc(
        rect,
        top + 2 * math.pi * from,
        added,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 6
          ..shader = SweepGradient(
            colors: [...colors, colors.first],
            transform: const GradientRotation(top),
          ).createShader(rect),
      );
    }
    // The tick draws itself above the number once the ring has arrived.
    final draw = _seg(t, 0.44, 0.66, Curves.easeOutCubic);
    if (draw > 0) {
      final o = centre + const Offset(0, -34);
      final path = Path()
        ..moveTo(o.dx - 13, o.dy + 1)
        ..lineTo(o.dx - 4, o.dy + 10)
        ..lineTo(o.dx + 14, o.dy - 9);
      final metric = path.computeMetrics().first;
      final part = metric.extractPath(0, metric.length * draw);
      canvas.drawPath(
        part,
        _glow(LuxeColors.emerald.withValues(alpha: 0.5), 6, 8),
      );
      canvas.drawPath(
        part,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 3.5
          ..color = LuxeColors.emerald,
      );
    }
  }

  @override
  bool shouldRepaint(_FinishPainter old) =>
      old.t != t || old.to != to || old.from != from;
}
