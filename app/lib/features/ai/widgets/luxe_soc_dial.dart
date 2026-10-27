import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/theme/plan_style.dart';

/// Two-knob platinum dial: the platinum knob is the battery level the user
/// reads off the scooter (there is no BMS feed), the emerald knob is the
/// level to charge to. The arc between them glows and carries energy.
///
/// Drags are claimed only when the finger lands on the ring, so the page
/// still scrolls everywhere else.
class LuxeSocDial extends StatefulWidget {
  const LuxeSocDial({
    super.key,
    required this.current,
    required this.target,
    required this.onCurrentChanged,
    required this.onTargetChanged,
    this.onEditCurrent,
    this.etaLabel,
    this.enabled = true,
  });

  final double current;
  final double target;
  final ValueChanged<double> onCurrentChanged;
  final ValueChanged<double> onTargetChanged;

  /// Precise entry for the current level (tap on its numeral).
  final VoidCallback? onEditCurrent;
  final String? etaLabel;
  final bool enabled;

  @override
  State<LuxeSocDial> createState() => _LuxeSocDialState();
}

enum _Knob { current, target }

class _LuxeSocDialState extends State<LuxeSocDial>
    with TickerProviderStateMixin {
  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  // Values glide to external changes (presets, sheet); drags are direct.
  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  final _ringKey = GlobalKey();
  late double _shownCurrent = _clampCurrent(widget.current);
  late double _shownTarget = _clampTarget(widget.target, _shownCurrent);
  double _fromCurrent = 0, _fromTarget = 0;
  _Knob? _active;
  bool _reduced = false;
  bool _started = false;

  double _clampCurrent(double v) => v.clamp(0.0, 100.0).roundToDouble();
  double _clampTarget(double v, double current) =>
      v.clamp(math.min(current + 1, 100.0), 100.0).roundToDouble();

  bool get _full => _shownCurrent >= 100;

  @override
  void initState() {
    super.initState();
    _glide.addListener(() {
      final t = Curves.easeOutCubic.transform(_glide.value);
      setState(() {
        _shownCurrent = ui.lerpDouble(
          _fromCurrent,
          _clampCurrent(widget.current),
          t,
        )!;
        _shownTarget = ui.lerpDouble(
          _fromTarget,
          _clampTarget(widget.target, _clampCurrent(widget.current)),
          t,
        )!;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (_started && reduced == _reduced) return;
    _started = true;
    _reduced = reduced;
    if (reduced) {
      _enter.value = 1;
      _flow.stop();
    } else {
      if (_enter.isDismissed) _enter.forward();
      // QA 139 (QA-13): one pass when shown; no endless decorative loop.
      _flow.forward();
    }
  }

  @override
  void didUpdateWidget(LuxeSocDial old) {
    super.didUpdateWidget(old);
    if (_active != null) return;
    final current = _clampCurrent(widget.current);
    final target = _clampTarget(widget.target, current);
    if ((current - _shownCurrent).abs() < 0.5 &&
        (target - _shownTarget).abs() < 0.5) {
      return;
    }
    if (_reduced) {
      setState(() {
        _shownCurrent = current;
        _shownTarget = target;
      });
      return;
    }
    _fromCurrent = _shownCurrent;
    _fromTarget = _shownTarget;
    _glide.forward(from: 0);
  }

  @override
  void dispose() {
    _enter.dispose();
    _flow.dispose();
    _glide.dispose();
    super.dispose();
  }

  // ── Geometry ──

  ({Offset centre, double radius})? _ring() {
    final box = _ringKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final s = box.size.shortestSide;
    return (
      centre: box.localToGlobal(box.size.center(Offset.zero)),
      radius: s * 0.39,
    );
  }

  double? _percentAt(Offset global) {
    final ring = _ring();
    if (ring == null) return null;
    final d = global - ring.centre;
    var a = math.atan2(d.dy, d.dx);
    // Normalise onto the dial's 270° sweep starting at 135°.
    var rel = a - _start;
    while (rel < 0) {
      rel += 2 * math.pi;
    }
    if (rel > _sweep) {
      // The 90° gap at the bottom: snap to the nearer end.
      rel = rel - _sweep < (2 * math.pi - _sweep) / 2 ? _sweep : 0;
    }
    a = rel;
    return (a / _sweep * 100).clamp(0.0, 100.0);
  }

  Offset _knobAt(double pct, ({Offset centre, double radius}) ring) {
    final a = _start + _sweep * pct / 100;
    return ring.centre + Offset(math.cos(a), math.sin(a)) * ring.radius;
  }

  /// Unit tangent of the ring at the knob nearest to [global].
  Offset? _tangentAt(Offset global) {
    final ring = _ring();
    if (ring == null) return null;
    final dc = (global - _knobAt(_shownCurrent, ring)).distance;
    final dt = _full
        ? double.infinity
        : (global - _knobAt(_shownTarget, ring)).distance;
    final pct = dc <= dt ? _shownCurrent : _shownTarget;
    final a = _start + _sweep * pct / 100;
    return Offset(-math.sin(a), math.cos(a));
  }

  /// Claims a drag only when it starts on (or right next to) a knob, so a
  /// swipe across the rest of the dial still scrolls the page.
  bool _onRing(Offset global) {
    if (!widget.enabled) return false;
    final ring = _ring();
    if (ring == null) return false;
    const reach = 40.0;
    if ((global - _knobAt(_shownCurrent, ring)).distance < reach) return true;
    return !_full && (global - _knobAt(_shownTarget, ring)).distance < reach;
  }

  void _grab(Offset global) {
    final p = _percentAt(global);
    if (p == null) return;
    final ring = _ring();
    if (_full || ring == null) {
      _active = _Knob.current;
    } else {
      final dc = (global - _knobAt(_shownCurrent, ring)).distance;
      final dt = (global - _knobAt(_shownTarget, ring)).distance;
      _active = dc == dt
          ? (p > _shownTarget ? _Knob.target : _Knob.current)
          : dc < dt
          ? _Knob.current
          : _Knob.target;
    }
    HapticFeedback.selectionClick();
    _glide.stop();
    _move(global);
  }

  void _move(Offset global) {
    final p = _percentAt(global);
    if (p == null || _active == null) return;
    final v = p.roundToDouble();
    if (_active == _Knob.current) {
      final next = v
          .clamp(0.0, _full ? 100.0 : math.max(0.0, _shownTarget - 1))
          .toDouble();
      if (next != _shownCurrent) {
        _tick(_shownCurrent, next);
        setState(() => _shownCurrent = next);
        widget.onCurrentChanged(next);
      }
    } else {
      final next = v
          .clamp(math.min(_shownCurrent + 1, 100.0), 100.0)
          .toDouble();
      if (next != _shownTarget) {
        _tick(_shownTarget, next);
        setState(() => _shownTarget = next);
        widget.onTargetChanged(next);
      }
    }
  }

  void _release() => setState(() => _active = null);

  void _tick(double from, double to) {
    if ((from ~/ 5) != (to ~/ 5)) {
      if (to == 80 || to == 90 || to == 100) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    }
  }

  void _stepCurrent(int delta) {
    final next = (_shownCurrent + delta)
        .clamp(0.0, _full ? 100.0 : _shownTarget - 1)
        .toDouble();
    if (next == _shownCurrent) return;
    setState(() => _shownCurrent = next);
    widget.onCurrentChanged(next);
  }

  void _stepTarget(int delta) {
    final next = (_shownTarget + delta)
        .clamp(_shownCurrent + 1, 100.0)
        .toDouble();
    if (next == _shownTarget) return;
    setState(() => _shownTarget = next);
    widget.onTargetChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final current = _shownCurrent.round();
    final target = _shownTarget.round();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, 340.0);
        return Center(
          child: SizedBox.square(
            dimension: size,
            child: RawGestureDetector(
              gestures: {
                _RingClaimRecognizer:
                    GestureRecognizerFactoryWithHandlers<_RingClaimRecognizer>(
                      () => _RingClaimRecognizer(_onRing, _tangentAt),
                      (r) => r
                        ..onDown = _grab
                        ..onMove = _move
                        ..onEnd = _release,
                    ),
              },
              child: Stack(
                key: _ringKey,
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_enter, _flow]),
                      builder: (context, _) => CustomPaint(
                        painter: LuxeDialPainter(
                          accent: PlanStyle.of(context).accentColors,
                          current: _shownCurrent,
                          target: _full ? null : _shownTarget,
                          enter: _enter.value,
                          flow: _flow.value,
                          active: _active == null
                              ? null
                              : _active == _Knob.current
                              ? 0
                              : 1,
                          enabled: widget.enabled,
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(size * 0.2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        // Rebuilds with the entrance so the readout fades in
                        // (and is never left transparent / hidden from
                        // screen readers).
                        child: AnimatedBuilder(
                          animation: _enter,
                          builder: (context, _) => _centre(current, target),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _centre(int current, int target) {
    final accent = PlanStyle.of(context).accent;
    final reveal = _reduced ? 1.0 : Curves.easeOut.transform(_enter.value);
    return Opacity(
      opacity: reveal.clamp(0.0, 1.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Semantics(
                container: true,
                slider: true,
                label: 'Mức pin hiện tại',
                value: '$current%',
                increasedValue: '${(current + 1).clamp(0, 100)}%',
                decreasedValue: '${(current - 1).clamp(0, 100)}%',
                hint: 'Nhập theo đồng hồ xe',
                onIncrease: widget.enabled ? () => _stepCurrent(1) : null,
                onDecrease: widget.enabled ? () => _stepCurrent(-1) : null,
                onTap: widget.enabled ? widget.onEditCurrent : null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.enabled ? widget.onEditCurrent : null,
                  child: ExcludeSemantics(
                    child: _reading(
                      value: current,
                      label: 'Mức pin hiện tại',
                      accent: false,
                      editable: widget.onEditCurrent != null,
                    ),
                  ),
                ),
              ),
              if (!_full) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 0, 14, 34),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: LuxeColors.dim,
                  ),
                ),
                Semantics(
                  container: true,
                  slider: true,
                  label: 'Mục tiêu sạc',
                  value: '$target%',
                  increasedValue: '${(target + 1).clamp(0, 100)}%',
                  decreasedValue: '${(target - 1).clamp(0, 100)}%',
                  onIncrease: widget.enabled ? () => _stepTarget(1) : null,
                  onDecrease: widget.enabled ? () => _stepTarget(-1) : null,
                  child: ExcludeSemantics(
                    child: _reading(
                      value: target,
                      label: 'MỤC TIÊU SẠC',
                      accent: true,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: _full ? LuxeColors.glass : accent.withValues(alpha: 0.1),
              border: Border.all(
                color: _full
                    ? LuxeColors.hairline
                    : accent.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _full ? Icons.battery_full_rounded : Icons.bolt_rounded,
                  size: 14,
                  color: _full ? LuxeColors.platinumMid : accent,
                ),
                const SizedBox(width: 6),
                Text(
                  _full
                      ? 'Pin đã đầy · kéo núm tối để sửa'
                      : '+${target - current}%${widget.etaLabel == null ? '' : ' · ${widget.etaLabel}'}',
                  style: TextStyle(
                    color: _full ? LuxeColors.muted : accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reading({
    required int value,
    required String label,
    required bool accent,
    bool editable = false,
  }) {
    final plan = PlanStyle.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (b) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: accent
                    ? [plan.accentColors[0], plan.accent]
                    : const [LuxeColors.platinum, LuxeColors.platinumLow],
              ).createShader(b),
              child: Text(
                '$value',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  height: 1.0,
                  fontWeight: FontWeight.w200,
                  letterSpacing: -1.5,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
            ),
            Text(
              '%',
              style: TextStyle(
                color: accent ? plan.accent : LuxeColors.muted,
                fontSize: 16,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              // Labels stay platinum: colour belongs to the numbers (Task 125).
              style: TextStyle(
                color: accent ? LuxeColors.platinumMid : LuxeColors.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: accent ? 1.4 : 0.3,
              ),
            ),
            if (editable) ...[
              const SizedBox(width: 4),
              const Icon(Icons.edit_rounded, size: 11, color: LuxeColors.dim),
            ],
          ],
        ),
      ],
    );
  }
}

/// Claims a drag that starts on a knob and moves along the ring. Within
/// 8px it compares the motion with the ring's tangent at that knob: along
/// the ring → the knob follows; across it (e.g. a vertical swipe on the top
/// knob) → rejected so the page keeps scrolling. Decides before the
/// scroll's own touch slop, so the winner is unambiguous.
class _RingClaimRecognizer extends OneSequenceGestureRecognizer {
  _RingClaimRecognizer(this.claims, this.tangentAt);

  final bool Function(Offset global) claims;
  final Offset? Function(Offset global) tangentAt;
  ValueChanged<Offset>? onDown;
  ValueChanged<Offset>? onMove;
  VoidCallback? onEnd;

  Offset? _origin;
  Offset? _tangent;
  bool _accepted = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!claims(event.position)) return;
    final tangent = tangentAt(event.position);
    if (tangent == null) return;
    _origin = event.position;
    _tangent = tangent;
    _accepted = false;
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      if (_accepted) {
        onMove?.call(event.position);
        return;
      }
      final d = event.position - _origin!;
      if (d.distance < 8) return;
      final along =
          (d.dx * _tangent!.dx + d.dy * _tangent!.dy).abs() / d.distance;
      if (along > 0.55) {
        _accepted = true;
        resolve(GestureDisposition.accepted);
        onDown?.call(_origin!);
        onMove?.call(event.position);
      } else {
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_accepted) {
        onEnd?.call();
      } else {
        resolve(GestureDisposition.rejected);
      }
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _accepted = false;
    _origin = null;
  }

  @override
  String get debugDescription => 'luxe dial knob';
}

/// Shared dial artwork (also used read-only while charging).
class LuxeDialPainter extends CustomPainter {
  LuxeDialPainter({
    required this.current,
    required this.target,
    required this.enter,
    required this.flow,
    this.active,
    this.enabled = true,
    this.charging = false,
    this.accent = defaultAccent,
  });

  final double current;
  final double? target;
  final double enter;
  final double flow;

  /// The target knob and the charge window (QA 139): the plan's accent
  /// (`PlanStyle.accentColors`, light to deep), never emerald, which stays
  /// for a verified charge (the read-only charging look).
  final List<Color> accent;

  static const defaultAccent = [
    LuxeColors.platinumHi,
    LuxeColors.platinum,
    Color(0xFFB9BCC1),
  ];

  /// 0 = current knob grabbed, 1 = target knob grabbed.
  final int? active;
  final bool enabled;

  /// Read-only charging look: no knobs, a live head on the fill.
  final bool charging;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final r = s * 0.39;
    final e = Curves.easeOutCubic.transform(enter.clamp(0.0, 1.0));
    final rect = Rect.fromCircle(center: c, radius: r);
    final dim = enabled ? 1.0 : 0.45;
    Offset at(double pct, [double radius = 0]) {
      final a = _start + _sweep * pct / 100;
      return c + Offset(math.cos(a), math.sin(a)) * (radius == 0 ? r : radius);
    }

    // Pool of light behind the dial.
    canvas.drawCircle(
      c,
      r * 1.2,
      Paint()
        ..shader = ui.Gradient.radial(c, r * 1.2, [
          (charging ? LuxeColors.emerald : accent[1]).withValues(
            alpha: 0.07 * e * dim,
          ),
          (charging ? LuxeColors.emerald : accent[1]).withValues(alpha: 0),
        ]),
    );

    // Outer bezel and inner hairline.
    canvas.drawCircle(
      c,
      r + s * 0.085,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = ui.Gradient.linear(c.translate(-r, -r), c.translate(r, r), [
          LuxeColors.platinumHi.withValues(alpha: 0.55 * e),
          LuxeColors.platinumLow.withValues(alpha: 0.2 * e),
        ]),
    );
    canvas.drawCircle(
      c,
      r - s * 0.07,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Color.fromRGBO(255, 255, 255, 0.07 * e),
    );

    // Ticks: every 2%, majors every 10%; lit inside the charge window.
    final sweepIn = Curves.easeInOutCubic.transform(e) * 100;
    for (var k = 0; k <= 100; k += 2) {
      if (k > sweepIn) break;
      final major = k % 10 == 0;
      final inWindow = target != null && k > current && k <= target!;
      final below = k <= current;
      final from = at(k.toDouble(), r + s * (major ? 0.035 : 0.045));
      final to = at(k.toDouble(), r + s * 0.06);
      canvas.drawLine(
        from,
        to,
        Paint()
          ..strokeWidth = major ? 1.5 : 1
          ..strokeCap = StrokeCap.round
          ..color = inWindow
              ? accent[0].withValues(alpha: (major ? 0.95 : 0.6) * dim)
              : below
              ? Color.fromRGBO(154, 158, 165, (major ? 0.7 : 0.35) * dim)
              : Color.fromRGBO(255, 255, 255, major ? 0.28 : 0.12),
      );
    }
    // Scale labels (painted, not text widgets).
    for (final k in const [0, 50, 100]) {
      final tp = TextPainter(
        text: TextSpan(
          text: '$k',
          style: TextStyle(
            fontSize: s * 0.034,
            color: Color.fromRGBO(154, 158, 165, 0.8 * e),
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = at(k.toDouble(), r + s * 0.105);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }

    // Track.
    final trackW = s * 0.042;
    canvas.drawArc(
      rect,
      _start,
      _sweep * e,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackW
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x12FFFFFF),
    );

    // Existing charge: brushed platinum 0 → current.
    final curSweep = _sweep * (current / 100) * e;
    if (curSweep > 0.001) {
      canvas.drawArc(
        rect,
        _start,
        curSweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = trackW
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.sweep(
            c,
            charging
                ? const [
                    LuxeColors.emeraldDeep,
                    LuxeColors.emerald,
                    Color(0xFFCFF7E6),
                  ]
                // Graphite: what is already in the battery, so the
                // window above it reads as the part still to charge.
                : const [
                    LuxeColors.ruleStrong,
                    LuxeColors.platinumLow,
                    LuxeColors.platinumMid,
                  ],
            const [0.0, 0.8, 1.0],
            TileMode.clamp,
            _start,
            _start + curSweep,
          ),
      );
    }

    // Charge window: the plan's accent current → target, with flowing energy.
    if (target != null && target! > current) {
      final a0 = _start + _sweep * current / 100;
      final winSweep = _sweep * (target! - current) / 100 * e;
      final shader = ui.Gradient.sweep(
        c,
        [accent[2], accent[1], accent[0]],
        const [0.0, 0.75, 1.0],
        TileMode.clamp,
        a0,
        a0 + math.max(winSweep, 0.001),
      );
      canvas.drawArc(
        rect,
        a0,
        winSweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = trackW * 1.6
          ..strokeCap = StrokeCap.round
          ..shader = shader
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9)
          ..color = Colors.white.withValues(alpha: 0.6 * dim),
      );
      canvas.drawArc(
        rect,
        a0,
        winSweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = trackW
          ..strokeCap = StrokeCap.round
          ..shader = shader,
      );
      // Energy particles running from current toward target.
      if (enabled && e > 0.9) {
        final span = target! - current;
        final n = (span / 12).clamp(1, 6).round();
        for (var k = 0; k < n; k++) {
          final t = (flow + k / n) % 1.0;
          final p = at(current + span * t);
          final fade = math.sin(t * math.pi);
          canvas.drawCircle(
            p,
            trackW * 0.55,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.45 * fade)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
          );
          canvas.drawCircle(
            p,
            trackW * 0.16,
            Paint()..color = Colors.white.withValues(alpha: 0.9 * fade),
          );
        }
      }
    }

    if (e < 0.6) return;
    final knobIn = ((e - 0.6) / 0.4).clamp(0.0, 1.0);

    if (charging) {
      // Live head on the fill, breathing.
      final head = at(current);
      final pulse = 0.5 + 0.5 * math.sin(flow * 2 * math.pi);
      canvas.drawCircle(
        head,
        s * (0.045 + 0.012 * pulse),
        Paint()
          ..color = LuxeColors.emerald.withValues(alpha: 0.5 * knobIn)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(
        head,
        s * 0.022,
        Paint()..color = LuxeColors.platinumHi,
      );
      if (target != null) _targetMark(canvas, at(target!), s, knobIn);
      return;
    }

    // Target knob (the plan's accent) then current knob (graphite) on top.
    if (target != null) {
      _knob(canvas, at(target!), s, knobIn, lit: true, grabbed: active == 1);
    }
    _knob(canvas, at(current), s, knobIn, lit: false, grabbed: active == 0);
  }

  void _targetMark(Canvas canvas, Offset p, double s, double t) {
    canvas.drawCircle(
      p,
      s * 0.02,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent[0].withValues(alpha: t),
    );
  }

  void _knob(
    Canvas canvas,
    Offset p,
    double s,
    double t, {
    required bool lit,
    required bool grabbed,
  }) {
    final r = s * 0.042 * (grabbed ? 1.18 : 1.0) * (0.6 + 0.4 * t);
    canvas.drawCircle(
      p + const Offset(0, 3),
      r * 1.1,
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, 0.55 * t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    if (lit) {
      canvas.drawCircle(
        p,
        r * (grabbed ? 2.2 : 1.7),
        Paint()
          ..color = accent[1].withValues(alpha: (grabbed ? 0.35 : 0.22) * t)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    canvas.drawCircle(
      p,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          p.translate(-r * 0.35, -r * 0.45),
          r * 1.4,
          lit
              ? accent
              : const [
                  LuxeColors.platinumMid,
                  LuxeColors.platinumLow,
                  LuxeColors.ruleStrong,
                ],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.drawCircle(
      p,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.55 * t),
    );
    canvas.drawCircle(
      p,
      r * 0.28,
      Paint()..color = lit ? PlanColors.ink : LuxeColors.background,
    );
  }

  @override
  bool shouldRepaint(LuxeDialPainter old) =>
      old.current != current ||
      old.target != target ||
      old.enter != enter ||
      old.flow != flow ||
      old.active != active ||
      old.enabled != enabled ||
      old.charging != charging ||
      !listEquals(old.accent, accent);
}
