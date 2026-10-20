import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ============================================================================
/// PINOVA — "PLATINUM" SPLASH (V6 timeline, Pinova mark since QA 133)
/// One 5000ms timeline: Ambient → Guide → Engrave → Platinum → Signature.
/// A hairline traces the dial, one stroke engraves the P up its stem and
/// round the dial, brushed platinum fills it, the charge lights emerald and a
/// single glint crosses before the wordmark.
/// After the timeline the mark keeps a slow, subtle breath while AuthGate
/// resolves startup, so a hold never looks frozen or needs a spinner.
/// ============================================================================

/// Finite PLATINUM animation; AuthGate owns startup work and navigation.
class BootstrapSplash extends StatefulWidget {
  const BootstrapSplash({
    super.key,
    required this.message,
    this.onFinished,
    this.animate = true,
  });
  static const background = Color(0xFF050506);
  static const duration = Duration(milliseconds: 5000);

  /// Exit used by route owners when the splash hands over to the app: the
  /// mark drifts forward while it fades, the destination settles in beneath.
  static const exitDuration = Duration(milliseconds: 560);
  static Widget exitTransition(
    Widget child,
    Animation<double> animation, {
    required bool isSplash,
  }) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: isSplash ? 1.06 : 0.985,
          end: 1.0,
        ).animate(curved),
        child: child,
      ),
    );
  }

  final String message;
  final VoidCallback? onFinished;
  final bool animate;
  @override
  State<BootstrapSplash> createState() => _BootstrapSplashState();
}

// ── Platinum palette ──
const _platinumHi = Color(0xFFF7F7F5);
const _platinum = Color(0xFFD6D8DB);
const _platinumMid = Color(0xFF9EA2A8);
const _platinumLow = Color(0xFF5E6268);
const _silverText = Color(0xFF8E9298);
const _emerald = Color(0xFF34D399);

class _BootstrapSplashState extends State<BootstrapSplash>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ctrl;
  late final AnimationController _breath;
  bool _started = false, _reduced = false, _finished = false;
  bool _resume = false, _slow = false;
  Timer? _slowTimer;

  bool _hasFiredHapticFill = false;
  bool _hasFiredHapticGlint = false;

  Animation<double> _interval(
    double begin,
    double end, {
    Curve curve = Curves.easeOutCubic,
  }) => CurvedAnimation(
    parent: _ctrl,
    curve: Interval(begin, end, curve: curve),
  );

  // Whole scene: slow cinematic dolly-in.
  late final Animation<double> _dollyIn = Tween<double>(
    begin: 1.0,
    end: 1.025,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine));

  // ── I. Ambient (0 → 1000ms): light gathers behind the mark ──
  late final Animation<double> _ambient = _interval(
    0.0,
    0.20,
    curve: Curves.easeInOutSine,
  );
  late final Animation<double> _dot = _interval(0.04, 0.14);

  // ── II. Horizon (700 → 1500ms): hairline opens to the V's width ──
  late final Animation<double> _horizon = _interval(
    0.14,
    0.30,
    curve: Curves.easeInOutCubic,
  );

  // ── III. Engrave (1700 → 2800ms): symmetric strokes draw the V ──
  late final Animation<double> _engrave = _interval(
    0.34,
    0.56,
    curve: const Cubic(0.65, 0.0, 0.35, 1.0),
  );
  late final Animation<double> _horizonCentreFade = _interval(
    0.34,
    0.46,
    curve: Curves.easeIn,
  );

  // ── IV. Platinum (2700 → 3900ms): brushed fill, fold, glint ──
  late final Animation<double> _fill = _interval(
    0.54,
    0.66,
    curve: Curves.easeOut,
  );
  late final Animation<double> _glint = _interval(
    0.64,
    0.78,
    curve: const Cubic(0.33, 0.0, 0.2, 1.0),
  );

  // ── V. Signature (3200 → 4000ms): wordmark settles, then tagline ──
  late final Animation<double> _typoOpacity = _interval(
    0.64,
    0.76,
    curve: Curves.easeOut,
  );
  late final Animation<double> _tracking = Tween<double>(
    begin: 0.46,
    end: 0.30,
  ).animate(_interval(0.64, 0.80, curve: const Cubic(0.22, 1.0, 0.36, 1.0)));
  late final Animation<double> _divider = _interval(
    0.68,
    0.78,
    curve: Curves.easeInOutCubic,
  );
  late final Animation<double> _taglineOpacity = _interval(
    0.70,
    0.80,
    curve: Curves.easeOut,
  );

  // Hold the final brand while AuthGate resolves startup. The route owner
  // fades the splash out only when the destination is actually ready.

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    _ctrl =
        AnimationController(
          vsync: this,
          duration: BootstrapSplash.duration,
          animationBehavior: AnimationBehavior.preserve,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && !_finished) {
            _finished = true;
            _startBreath();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onFinished?.call();
            });
          }
        });
    _ctrl.addListener(_handleMilestoneHaptics);
    _slowTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  void _startBreath() {
    if (!_reduced && !_breath.isAnimating) _breath.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (!_started) {
      _started = true;
      _reduced = reduced;
      if (!widget.animate) {
        _ctrl.value = 1;
      } else if (reduced) {
        // A nearly static one-second hold uses the lifecycle-aware ticker,
        // rather than a delayed callback that could finish in the background.
        _ctrl.value = 0.80;
        _ctrl.animateTo(0.81, duration: const Duration(seconds: 1));
      } else {
        _ctrl.forward();
      }
    } else if (reduced != _reduced) {
      _reduced = reduced;
      if (reduced) {
        _breath.stop();
        if (!_finished) {
          _ctrl.value = 0.80;
          _ctrl.animateTo(0.81, duration: const Duration(seconds: 1));
        }
      } else if (_ctrl.isAnimating) {
        _ctrl.forward();
      } else if (_finished) {
        _startBreath();
      }
    }
  }

  /// Fire haptic feedback at key animation milestones.
  void _handleMilestoneHaptics() {
    if (_reduced || !widget.animate) return;
    // ~2700ms: soft impact as the engraved V closes and platinum flows in.
    if (_ctrl.value >= 0.54 && !_hasFiredHapticFill) {
      _hasFiredHapticFill = true;
      HapticFeedback.lightImpact();
    }
    // ~3550ms: the faintest tick as the glint crosses the centre.
    if (_ctrl.value >= 0.71 && !_hasFiredHapticGlint) {
      _hasFiredHapticGlint = true;
      HapticFeedback.selectionClick();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_resume && !_finished) {
        if (_reduced) {
          _ctrl.animateTo(0.81, duration: const Duration(seconds: 1));
        } else {
          _ctrl.forward();
        }
      }
      if (_finished) _startBreath();
      _resume = false;
    } else {
      _resume = _resume || _ctrl.isAnimating;
      _ctrl.stop(canceled: false);
      _breath.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _slowTimer?.cancel();
    _ctrl.removeListener(_handleMilestoneHaptics);
    _ctrl.dispose();
    _breath.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD — Ambient → Mark (+ pedestal light) → Signature → Slow-network note
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: BootstrapSplash.background,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: BootstrapSplash.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
    child: Scaffold(
      backgroundColor: BootstrapSplash.background,
      body: Semantics(
        label: 'Pinova, đang khởi động',
        liveRegion: true,
        child: AnimatedBuilder(
          animation: Listenable.merge([_ctrl, _breath]),
          builder: (context, _) {
            final breath = Curves.easeInOutSine.transform(_breath.value);
            return Stack(
              fit: StackFit.expand,
              children: [
                // ── Ambient light: a soft cool pool behind the mark ──
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.0, -0.18),
                        radius: 0.95,
                        colors: [
                          Color.lerp(
                            BootstrapSplash.background,
                            const Color(0xFF17181B),
                            _ambient.value,
                          )!,
                          BootstrapSplash.background,
                        ],
                        stops: const [0.0, 0.78],
                      ),
                    ),
                  ),
                ),
                // ── Vignette: a true radial falloff (no visible box edge) ──
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          radius: 1.15,
                          colors: [Color(0x00000000), Color(0x8C000000)],
                          stops: [0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Mark + signature, composed as one centred group ──
                Align(
                  alignment: const Alignment(0, -0.12),
                  child: Transform.scale(
                    scale: _dollyIn.value,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RepaintBoundary(
                            child: CustomPaint(
                              size: const Size(176, 186),
                              painter: _PlatinumMarkPainter(
                                ambient: _ambient.value,
                                dot: _dot.value,
                                horizon: _horizon.value,
                                horizonCentreFade: _horizonCentreFade.value,
                                engrave: _engrave.value,
                                fill: _fill.value,
                                glint: _glint.value,
                                breath: _finished ? breath : 0.0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),
                          _signature(),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Slow network note, quietly at the bottom ──
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 40,
                  child: SafeArea(
                    top: false,
                    child: Visibility(
                      visible: _slow,
                      maintainSize: true,
                      maintainState: true,
                      maintainAnimation: true,
                      child: const Text(
                        'Đang kết nối…',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _silverText,
                          fontSize: 13,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _signature() => Opacity(
    opacity: _typoOpacity.value,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // APP NAME — brushed platinum with a settling letter-spacing.
        ExcludeSemantics(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_platinumHi, _platinum, _platinumMid],
                stops: [0.0, 0.55, 1.0],
              ).createShader(bounds),
              child: Text(
                'PINOVA',
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 17 * _tracking.value,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Hairline divider opening from the centre.
        SizedBox(
          height: 1,
          width: 44 * _divider.value,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0x00FFFFFF),
                  Color(0x66FFFFFF),
                  Color(0x00FFFFFF),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // TAGLINE in muted silver.
        ExcludeSemantics(
          child: Opacity(
            opacity: _taglineOpacity.value,
            child: const Text(
              'Hiểu pin · Sạc thông minh',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _silverText,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                letterSpacing: 2.0,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAINTER: HORIZON → ENGRAVED V → BRUSHED PLATINUM, FOLD, GLINT & PEDESTAL LIGHT
// ═══════════════════════════════════════════════════════════════════════════════

class _PlatinumMarkPainter extends CustomPainter {
  _PlatinumMarkPainter({
    required this.ambient,
    required this.dot,
    required this.horizon,
    required this.horizonCentreFade,
    required this.engrave,
    required this.fill,
    required this.glint,
    required this.breath,
  });

  final double ambient;
  final double dot;
  final double horizon;
  final double horizonCentreFade;
  final double engrave;
  final double fill;
  final double glint;
  final double breath;

  // Normalised Pinova "P" geometry inside the square mark area (width × width):
  // a dial ring (the app's charge dial) on a stem, the last stretch of the
  // ring lit emerald as the charge, a white knob at its end (QA 133).
  static const _cx = 0.50;
  static const _cy = 0.41;
  static const _r = 0.215;
  static const _t = 0.09; // stroke
  static const _stemX = _cx - _r;
  static const _stemBottom = 0.805;
  static const _ringSweep = 310 * math.pi / 180; // 180° → 130° clockwise
  static const _knobAngle = 130 * math.pi / 180;
  static const _chargeFrom = 40 * math.pi / 180;

  static Offset _onRing(double s, double angle) => Offset(
    (_cx + _r * math.cos(angle)) * s,
    (_cy + _r * math.sin(angle)) * s,
  );

  /// The P's centre line: stem from the foot up, then round the ring.
  static Path spinePath(double s) => Path()
    ..moveTo(_stemX * s, _stemBottom * s)
    ..lineTo(_stemX * s, _cy * s)
    ..arcTo(
      Rect.fromCircle(center: Offset(_cx * s, _cy * s), radius: _r * s),
      math.pi,
      _ringSweep,
      false,
    );

  /// The filled P (ring band + round end + stem), for fills and clips.
  static Path markPath(double s) {
    final c = Offset(_cx * s, _cy * s);
    final r = _r * s, t = _t * s;
    final band = Path()
      ..arcTo(
        Rect.fromCircle(center: c, radius: r + t / 2),
        math.pi,
        _ringSweep,
        true,
      )
      ..arcTo(
        Rect.fromCircle(center: c, radius: r - t / 2),
        math.pi + _ringSweep,
        -_ringSweep,
        false,
      )
      ..close();
    final cap = Path()
      ..addOval(Rect.fromCircle(center: _onRing(s, _knobAngle), radius: t / 2));
    final stem = Path()
      ..addRRect(
        RRect.fromLTRBR(
          _stemX * s - t / 2,
          c.dy - t / 2,
          _stemX * s + t / 2,
          _stemBottom * s + t / 2,
          Radius.circular(t / 2),
        ),
      );
    return Path.combine(
      PathOperation.union,
      Path.combine(PathOperation.union, band, cap),
      stem,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width; // Mark occupies the top square; pedestal light below.
    final c = Offset(_cx * s, _cy * s);
    final ring = Rect.fromCircle(center: c, radius: _r * s);
    final t = _t * s;

    // ── Halo behind the mark: appears with the metal, breathes on hold ──
    final haloStrength =
        (0.35 * ambient + 0.65 * fill) * (0.85 + 0.15 * breath);
    if (haloStrength > 0) {
      canvas.drawCircle(
        Offset(s / 2, s * 0.50),
        s * 0.62,
        Paint()
          ..shader = ui.Gradient.radial(Offset(s / 2, s * 0.50), s * 0.62, [
            Color.fromRGBO(255, 255, 255, 0.075 * haloStrength),
            const Color(0x00FFFFFF),
          ]),
      );
    }

    // ── I. Point of light at the top of the future dial ──
    final top = Offset(c.dx, c.dy - _r * s);
    if (dot > 0 && horizon < 1) {
      final o = dot * (1 - horizon);
      canvas.drawCircle(
        top,
        6,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, 0.35 * o)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        top,
        1.8 * dot,
        Paint()..color = Color.fromRGBO(255, 255, 255, o),
      );
    }

    // ── II. Hairline guide: the dial traced once round from the top ──
    if (horizon > 0 && fill < 1) {
      final fadeOut = (1 - fill) * (1 - 0.6 * horizonCentreFade);
      final guide = Paint()
        ..color = Color.fromRGBO(240, 241, 243, 0.55 * fadeOut)
        ..strokeWidth = 1.1
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(ring, -math.pi / 2, 2 * math.pi * horizon, false, guide);
      canvas.drawArc(
        ring,
        -math.pi / 2,
        2 * math.pi * horizon,
        false,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, 0.22 * fadeOut)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
    }

    final mark = markPath(s);

    // ── IV-a. Pedestal light: a soft elliptical sheen under the stem ──
    if (fill > 0) {
      final centre = Offset(s / 2, _stemBottom * s + t / 2 + 14);
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(1, 0.18);
      canvas.drawCircle(
        Offset.zero,
        s * 0.42,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, s * 0.42, [
            Color.fromRGBO(255, 255, 255, 0.10 * fill),
            const Color(0x00FFFFFF),
          ]),
      );
      canvas.restore();
    }

    // ── IV-b. Brushed platinum body ──
    if (fill > 0) {
      canvas.drawPath(
        mark.shift(const Offset(0, 6)),
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, 0.55 * fill)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
      // Light from 10 o'clock: bright upper-left, deeper lower-right, with a
      // narrow band of reflection for a polished-metal read.
      canvas.drawPath(
        mark,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(s * 0.10, s * 0.18),
            Offset(s * 0.86, s * 0.86),
            [
              _platinumHi.withValues(alpha: fill),
              _platinum.withValues(alpha: fill),
              _platinumMid.withValues(alpha: fill),
              _platinum.withValues(alpha: fill),
              _platinumLow.withValues(alpha: fill),
            ],
            const [0.0, 0.30, 0.52, 0.66, 1.0],
          ),
      );
      // Bevel: a bright hairline along the top of the dial.
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: _r * s + t / 2 - 0.6),
        200 * math.pi / 180,
        130 * math.pi / 180,
        false,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, 0.85 * fill)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      // The right side falls into shade so the metal reads as turned (a
      // soft horizontal ramp: a hard edge showed as a seam on the dial).
      canvas.save();
      canvas.clipPath(mark);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, s, s),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(s * 0.40, 0),
            Offset(s * 0.85, 0),
            [const Color(0x00000000), Color.fromRGBO(0, 0, 0, 0.16 * fill)],
          ),
      );
      canvas.restore();
    }

    // ── III. Engraving: one stroke runs up the stem and round the dial ──
    if (engrave > 0) {
      final strokeAlpha = 1 - 0.55 * fill;
      final strokePaint = Paint()
        ..color = Color.fromRGBO(244, 245, 247, strokeAlpha)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final glowPaint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, 0.28 * strokeAlpha)
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      for (final metric in spinePath(s).computeMetrics()) {
        final length = metric.length * engrave;
        final drawn = metric.extractPath(0, length);
        canvas.drawPath(drawn, glowPaint);
        canvas.drawPath(drawn, strokePaint);
        final head = metric.getTangentForOffset(length)?.position;
        if (engrave < 1 && head != null) {
          final spark = math.sin(engrave * math.pi);
          canvas.drawCircle(
            head,
            5,
            Paint()
              ..color = Color.fromRGBO(255, 255, 255, 0.55 * spark)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
          );
          canvas.drawCircle(
            head,
            1.4,
            Paint()..color = Color.fromRGBO(255, 255, 255, spark),
          );
        }
      }
      if (fill > 0) {
        canvas.drawPath(
          mark,
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, 0.35 * fill)
            ..strokeWidth = 0.8
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    // ── IV-c. The charge: the last stretch of the dial lights emerald ──
    final charge = ((fill - 0.4) / 0.6).clamp(0.0, 1.0);
    if (charge > 0) {
      final sweep = (_knobAngle - _chargeFrom) * charge;
      final start = _knobAngle - sweep;
      canvas.drawArc(
        ring,
        start,
        sweep,
        false,
        Paint()
          ..color = _emerald.withValues(
            alpha: 0.45 * charge * (0.85 + 0.15 * breath),
          )
          ..strokeWidth = t
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
      canvas.drawArc(
        ring,
        start,
        sweep,
        false,
        Paint()
          ..color = _emerald.withValues(alpha: charge)
          ..strokeWidth = t
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        _onRing(s, _knobAngle),
        t * 0.37,
        Paint()..color = _platinumHi.withValues(alpha: charge),
      );
    }

    // ── IV-d. One specular glint travelling 10 o'clock → 4 o'clock ──
    if (glint > 0 && glint < 1) {
      canvas.save();
      canvas.clipPath(mark);
      final x = ui.lerpDouble(-0.4 * s, 1.4 * s, glint)!;
      final band = s * 0.22;
      final intensity = math.sin(glint * math.pi);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, s, s),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
            Offset(x - band, 0),
            Offset(x + band, s * 0.6),
            [
              const Color(0x00FFFFFF),
              Color.fromRGBO(255, 255, 255, 0.85 * intensity),
              const Color(0x00FFFFFF),
            ],
            const [0.0, 0.5, 1.0],
          ),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PlatinumMarkPainter old) =>
      old.ambient != ambient ||
      old.dot != dot ||
      old.horizon != horizon ||
      old.horizonCentreFade != horizonCentreFade ||
      old.engrave != engrave ||
      old.fill != fill ||
      old.glint != glint ||
      old.breath != breath;
}
