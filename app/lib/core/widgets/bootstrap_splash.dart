import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pinova_brand.dart';
import '../../core/theme/luxe_theme.dart';

/// ============================================================================
/// PINOVA — "PLATINUM" SPLASH (V6 timeline, Pinova mark since QA 133)
/// One 5000ms timeline: Ambient → Guide → Engrave → Platinum → Signature.
/// A hairline traces the dial, one stroke engraves the P up its stem and
/// round the dial, then the owner's metal logo (real artwork) fades in, its
/// emerald charge runs from the knob along the track, a soft glint crosses
/// and the drawn "PINOVA" wordmark settles (QA 133, 20/10/2026).
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
  // The emerald charge runs along the real logo's track (1200 ms).
  late final Animation<double> _charge = _interval(
    0.60,
    0.84,
    curve: Curves.easeInOutCubic,
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
                            LuxeColors.raised,
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
                          RepaintBoundary(child: _mark(breath)),
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

  /// The real logo: the prelude painter underneath, then the metal art and
  /// the emerald charge revealed along the track from the knob.
  Widget _mark(double breath) {
    const box = Size(176, 186);
    final logo = _PlatinumMarkPainter.logoRect(box.width);
    final fill = _fill.value;
    final charge = _charge.value;
    final glint = _glint.value;
    return SizedBox.fromSize(
      size: box,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _PlatinumMarkPainter(
                ambient: _ambient.value,
                dot: _dot.value,
                horizon: _horizon.value,
                horizonCentreFade: _horizonCentreFade.value,
                engrave: _engrave.value,
                fill: fill,
                glint: glint,
                breath: _finished ? breath : 0.0,
              ),
            ),
          ),
          if (fill > 0)
            Positioned.fromRect(
              rect: logo,
              child: Opacity(
                opacity: fill,
                child: Transform.scale(
                  scale: 0.96 + 0.04 * fill,
                  child: ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (bounds) {
                      final x = -0.6 + 2.2 * glint;
                      final on = glint > 0 && glint < 1;
                      return LinearGradient(
                        begin: Alignment(x - 0.5, -1),
                        end: Alignment(x + 0.5, 1),
                        colors: [
                          const Color(0x00FFFFFF),
                          Color.fromRGBO(
                            255,
                            255,
                            255,
                            on ? 0.38 * math.sin(glint * math.pi) : 0,
                          ),
                          const Color(0x00FFFFFF),
                        ],
                        stops: const [0.35, 0.5, 0.65],
                      ).createShader(bounds);
                    },
                    child: Image.asset(
                      PinovaLogoAssets.metal,
                      key: const ValueKey('splash-logo-metal'),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
            ),
          if (charge > 0)
            Positioned.fromRect(
              rect: logo,
              child: Opacity(
                opacity: (0.88 + 0.12 * (_finished ? breath : 1)).clamp(
                  0.0,
                  1.0,
                ),
                child: ClipPath(
                  clipper: _ChargeSweepClipper(charge),
                  child: Image.asset(
                    PinovaLogoAssets.charge,
                    key: const ValueKey('splash-logo-charge'),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _signature() => Opacity(
    opacity: _typoOpacity.value,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The drawn "PINOVA" wordmark; its tracking settles and the O's
        // emerald arc fills with the charge.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: PinovaWordmark(
            key: const ValueKey('pinova-wordmark'),
            height: 22,
            tracking: 0.30 + _tracking.value,
            charge: _charge.value,
          ),
        ),
        const SizedBox(height: 18),
        // Hairline opening from the centre.
        SizedBox(
          height: 1,
          width: 56 * _divider.value,
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
      ],
    ),
  );
}

/// A wedge from the logo's dial centre, opening clockwise-back from just past
/// the knob towards the track's far end: the charge runs knob → right.
class _ChargeSweepClipper extends CustomClipper<Path> {
  _ChargeSweepClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    final k = size.width / 1024;
    final c = PinovaLogoAssets.ringCentre * k;
    const start = PinovaLogoAssets.knobAngle + 0.45; // glow round the knob
    const end = PinovaLogoAssets.trackEndAngle - 0.35; // and past the tip
    final sweep = (end - start) * progress;
    return Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(
        Rect.fromCircle(center: c, radius: size.width),
        start,
        sweep,
        false,
      )
      ..close();
  }

  @override
  bool shouldReclip(_ChargeSweepClipper old) => old.progress != progress;
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

  // The prelude (point of light, dial guide, engraving) is drawn on the
  // geometry of the owner's metal logo; the metal and its emerald charge are
  // the real artwork (PinovaLogoAssets), laid over it by the splash.

  /// Where the logo art sits in the painter's box: its mark fitted to 86 %
  /// of the width-high, top at 5 %.
  static Rect logoRect(double s) {
    final box = PinovaLogoAssets.markBox;
    final l = 0.86 * s * 1024 / box.height;
    return Rect.fromLTWH(
      s / 2 - box.center.dx * l / 1024,
      0.05 * s - box.top * l / 1024,
      l,
      l,
    );
  }

  static Offset _p(double s, double x, double y) {
    final r = logoRect(s);
    return Offset(r.left + x * r.width / 1024, r.top + y * r.height / 1024);
  }

  static double _scale(double s) => logoRect(s).width / 1024;

  /// The P's centre line: stem from the foot up, then round the dial.
  static Path spinePath(double s) {
    const c = PinovaLogoAssets.ringCentre;
    const r = PinovaLogoAssets.ringRadius;
    final foot = _p(s, c.dx - r, PinovaLogoAssets.stemFoot);
    final joint = _p(s, c.dx - r, c.dy);
    return Path()
      ..moveTo(foot.dx, foot.dy)
      ..lineTo(joint.dx, joint.dy)
      ..arcTo(
        Rect.fromCircle(center: _p(s, c.dx, c.dy), radius: r * _scale(s)),
        math.pi,
        2 * math.pi - (math.pi - PinovaLogoAssets.knobAngle),
        false,
      );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    const rc = PinovaLogoAssets.ringCentre;
    final c = _p(s, rc.dx, rc.dy);
    final radius = PinovaLogoAssets.ringRadius * _scale(s);
    final ring = Rect.fromCircle(center: c, radius: radius);
    final foot = _p(
      s,
      rc.dx - PinovaLogoAssets.ringRadius,
      PinovaLogoAssets.stemFoot,
    );

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
    final top = Offset(c.dx, c.dy - radius);
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

    // ── II. Hairline guide round the dial; it yields to the engraving ──
    if (horizon > 0 && fill < 1 && engrave < 1) {
      final fadeOut =
          (1 - fill) * (1 - 0.6 * horizonCentreFade) * (1 - engrave);
      canvas.drawArc(
        ring,
        -math.pi / 2,
        2 * math.pi * horizon,
        false,
        Paint()
          ..color = Color.fromRGBO(240, 241, 243, 0.55 * fadeOut)
          ..strokeWidth = 1.1
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
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

    // ── Pedestal light under the stem, with the metal ──
    if (fill > 0) {
      final centre = Offset(s / 2, foot.dy + 28);
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

    // ── III. Engraving: one stroke up the stem and round the dial; it is
    // gone once the metal is a third in. ──
    if (engrave > 0 && fill < 0.34) {
      final strokeAlpha = (1 - 3 * fill).clamp(0.0, 1.0);
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
