import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ============================================================================
/// VINFAST BATTERY — V6 "PLATINUM" SPLASH
/// One 5000ms timeline: Ambient → Horizon → Engrave → Platinum → Signature.
/// A hairline horizon becomes the top edge of the V, two strokes engrave it,
/// brushed platinum fills it and a single glint crosses before the wordmark.
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
        label: 'VinFast Battery, đang khởi động',
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
                'VINFAST BATTERY',
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

  // Normalised V geometry inside the square mark area (width × width).
  static const _topY = 0.26;
  static const _outerL = Offset(0.12, _topY);
  static const _innerL = Offset(0.34, _topY);
  static const _innerR = Offset(0.66, _topY);
  static const _outerR = Offset(0.88, _topY);
  static const _innerTip = Offset(0.50, 0.55);
  static const _tip = Offset(0.50, 0.82);

  static Path markPath(double s) => Path()
    ..moveTo(_outerL.dx * s, _outerL.dy * s)
    ..lineTo(_innerL.dx * s, _innerL.dy * s)
    ..lineTo(_innerTip.dx * s, _innerTip.dy * s)
    ..lineTo(_innerR.dx * s, _innerR.dy * s)
    ..lineTo(_outerR.dx * s, _outerR.dy * s)
    ..lineTo(_tip.dx * s, _tip.dy * s)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width; // Mark occupies the top square; pedestal light below.
    Offset p(Offset n) => Offset(n.dx * s, n.dy * s);
    final topY = _topY * s;

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

    // ── I. Point of light on the future top edge ──
    if (dot > 0 && horizon < 1) {
      final o = dot * (1 - horizon);
      canvas.drawCircle(
        Offset(s / 2, topY),
        6,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, 0.35 * o)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        Offset(s / 2, topY),
        1.8 * dot,
        Paint()..color = Color.fromRGBO(255, 255, 255, o),
      );
    }

    // ── II. Horizon hairline, tapered at both ends ──
    if (horizon > 0 && fill < 1) {
      final half = (_outerR.dx - 0.5) * s * horizon;
      final left = Offset(s / 2 - half, topY);
      final right = Offset(s / 2 + half, topY);
      final fadeOut = 1 - fill;
      // The centre span (between the inner corners) dissolves as the strokes
      // start; the outer spans stay and become the V's top edges.
      final centreAlpha = (1 - horizonCentreFade) * fadeOut;
      final edgeAlpha = fadeOut;
      final edge = Color.fromRGBO(240, 241, 243, edgeAlpha);
      final centre = Color.fromRGBO(255, 255, 255, math.max(centreAlpha, 0.0));
      // Stops 0.27–0.73 are the inner corners at full width; ends taper.
      final shader = ui.Gradient.linear(
        left,
        right,
        [
          const Color(0x00FFFFFF),
          edge,
          edge,
          centre,
          centre,
          edge,
          edge,
          const Color(0x00FFFFFF),
        ],
        const [0.0, 0.06, 0.27, 0.31, 0.69, 0.73, 0.94, 1.0],
      );
      canvas.drawLine(
        left,
        right,
        Paint()
          ..shader = shader
          ..strokeWidth = 3
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      canvas.drawLine(
        left,
        right,
        Paint()
          ..shader = shader
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round,
      );
    }

    final mark = markPath(s);

    // ── IV-a. Pedestal light: a soft elliptical sheen under the tip ──
    if (fill > 0) {
      final centre = Offset(s / 2, _tip.dy * s + 14);
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
      // Light from 10 o'clock: bright upper-left wing, deeper right wing,
      // with a narrow band of reflection for a polished-metal read.
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
      // Bevel: bright top edges, darker lower edges.
      final bevelHi = Path()
        ..moveTo(_outerL.dx * s, _outerL.dy * s)
        ..lineTo(_innerL.dx * s, _innerL.dy * s)
        ..moveTo(_innerR.dx * s, _innerR.dy * s)
        ..lineTo(_outerR.dx * s, _outerR.dy * s);
      canvas.drawPath(
        bevelHi,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, 0.85 * fill)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      // Fold: the right wing sits in shade, so the V reads as two
      // stamped planes meeting on the centre crease.
      canvas.save();
      canvas.clipPath(mark);
      canvas.drawRect(
        Rect.fromLTRB(s / 2, 0, s, s),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(s / 2, _topY * s),
            Offset(s / 2, _tip.dy * s),
            [
              Color.fromRGBO(0, 0, 0, 0.16 * fill),
              Color.fromRGBO(0, 0, 0, 0.05 * fill),
            ],
          ),
      );
      canvas.restore();
    }

    // ── III. Engraving strokes (symmetric) with leading sparks ──
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
      final segments = [
        (p(_outerL), p(_tip)),
        (p(_outerR), p(_tip)),
        (p(_innerL), p(_innerTip)),
        (p(_innerR), p(_innerTip)),
      ];
      for (final (from, to) in segments) {
        final head = Offset.lerp(from, to, engrave)!;
        canvas.drawLine(from, head, glowPaint);
        canvas.drawLine(from, head, strokePaint);
        if (engrave < 1) {
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
      // Top edges stay as hairlines once the horizon has faded.
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

    // ── IV-c. One specular glint travelling 10 o'clock → 4 o'clock ──
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
