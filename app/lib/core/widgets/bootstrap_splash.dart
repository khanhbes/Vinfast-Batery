import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ============================================================================
/// VINFAST BATTERY — V5 "KHẮC BẰNG ÁNH SÁNG" (LIGHT ENGRAVING SPLASH)
/// Architecture: Single AnimationController (5000ms) with Interval Mappings
/// 5 Nhịp: Khởi nguồn → Đường sáng → Khắc logo → Phản quang & Typography → Exit
/// ============================================================================

/// Finite LIGHT ENGRAVING animation; AuthGate owns startup work and navigation.
class BootstrapSplash extends StatefulWidget {
  const BootstrapSplash({
    super.key,
    required this.message,
    this.onFinished,
    this.animate = true,
  });
  static const background = Color(0xFF060908);
  static const duration = Duration(milliseconds: 5000);
  final String message;
  final VoidCallback? onFinished;
  final bool animate;
  @override
  State<BootstrapSplash> createState() => _BootstrapSplashState();
}

class _BootstrapSplashState extends State<BootstrapSplash>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ctrl;
  bool _started = false, _reduced = false, _finished = false;
  bool _resume = false, _slow = false;
  Timer? _slowTimer;

  // ── Haptic milestone flags ──
  bool _hasFiredHapticStroke = false;
  bool _hasFiredHapticSweep = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERVAL MAPPINGS — 14 Animations on Single Controller (5000ms)
  // ═══════════════════════════════════════════════════════════════════════════

  // Entire Scene: Slow cinematic dolly-in (scale 1.00 -> 1.03)
  late final Animation<double> _dollyIn = Tween<double>(
    begin: 1.00,
    end: 1.03,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  // ── NHỊP 1: Khởi Nguồn (150ms → 750ms) — Dot Fade-in & Radius ──
  late final Animation<double> _dotOpacity = Tween<double>(begin: 0.0, end: 1.0)
      .animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.030, 0.150, curve: Curves.easeOutCubic),
        ),
      );

  late final Animation<double> _dotRadius = Tween<double>(begin: 0.0, end: 2.2)
      .animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.030, 0.150, curve: Curves.easeOutCubic),
        ),
      );

  // ── NHỊP 2: Đường Sáng (750ms → 1625ms) — Line Expansion & Breathing ──
  late final Animation<double> _lineWidth =
      Tween<double>(begin: 0.0, end: 160.0).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.150, 0.325, curve: Curves.easeInOutCubic),
        ),
      );

  late final Animation<double> _lineBreathOpacity =
      TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(begin: 0.85, end: 1.0),
          weight: 50,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 0.85),
          weight: 50,
        ),
      ]).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.200, 0.325, curve: Curves.easeInOut),
        ),
      );

  // ── NHỊP 3: Khắc Logo (1775ms → 3125ms) — Stroke Drawing & Fill ──
  late final Animation<double> _strokeDrawProgress =
      Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(
            0.355,
            0.525,
            curve: Cubic(0.65, 0.0, 0.35, 1.0),
          ),
        ),
      );

  late final Animation<double> _fillGradientOpacity =
      Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.555, 0.625, curve: Curves.easeOut),
        ),
      );

  // ── NHỊP 4: Phản Quang & Typography (3125ms → 4060ms) ──
  late final Animation<double> _specularSweepOffset =
      Tween<double>(begin: -1.5, end: 2.0).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(
            0.625,
            0.762,
            curve: Cubic(0.22, 1.0, 0.36, 1.0),
          ),
        ),
      );

  late final Animation<double> _rimLightIntensity =
      TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(begin: 0.25, end: 0.95),
          weight: 40,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: 0.95, end: 0.25),
          weight: 60,
        ),
      ]).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(
            0.625,
            0.762,
            curve: Cubic(0.22, 1.0, 0.36, 1.0),
          ),
        ),
      );

  // Tracking Settle: letter-spacing 22% → 14%
  late final Animation<double> _trackingAnimation =
      Tween<double>(begin: 0.22, end: 0.14).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(
            0.650,
            0.812,
            curve: Cubic(0.22, 1.0, 0.36, 1.0),
          ),
        ),
      );

  // Typography "VINFAST BATTERY" fade-in
  late final Animation<double> _typoOpacity =
      Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.650, 0.750, curve: Curves.easeOut),
        ),
      );

  // Tagline "Hiểu pin · Sạc thông minh" champagne fade-in
  late final Animation<double> _taglineOpacity =
      Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.687, 0.812, curve: Curves.easeOut),
        ),
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
    _ctrl =
        AnimationController(
          vsync: this,
          duration: BootstrapSplash.duration,
          animationBehavior: AnimationBehavior.preserve,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && !_finished) {
            _finished = true;
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
      if (reduced && !_finished) {
        _ctrl.value = 0.80;
        _ctrl.animateTo(0.81, duration: const Duration(seconds: 1));
      } else if (_ctrl.isAnimating) {
        _ctrl.forward();
      }
    }
  }

  /// Fire haptic feedback at key animation milestones.
  void _handleMilestoneHaptics() {
    if (_reduced || !widget.animate) return;
    // ~2625ms (Interval 0.525): Soft impact khi nét vẽ logo vừa khép
    if (_ctrl.value >= 0.525 && !_hasFiredHapticStroke) {
      _hasFiredHapticStroke = true;
      HapticFeedback.lightImpact();
    }
    // ~3435ms (Interval 0.687): Nhịp rung siêu nhẹ khi vệt phản quang qua tâm
    if (_ctrl.value >= 0.687 && !_hasFiredHapticSweep) {
      _hasFiredHapticSweep = true;
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
      _resume = false;
    } else {
      _resume = _resume || _ctrl.isAnimating;
      _ctrl.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _slowTimer?.cancel();
    _ctrl.removeListener(_handleMilestoneHaptics);
    _ctrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD — 4-Layer Stack: Vignette → Logo → Specular → Typography
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
          animation: _ctrl,
          builder: (context, _) {
            return Opacity(
              // Never hide the loading surface before navigation resolves.
              opacity: 1.0,
              child: Transform.scale(
                scale: _dollyIn.value,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // ── LAYER 1: Radial Gradient Background ──
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(0.0, -0.08),
                            radius: 0.9,
                            colors: [Color(0xFF0E1412), Color(0xFF060908)],
                            stops: [0.0, 0.72],
                          ),
                        ),
                      ),
                    ),

                    // ── LAYER 2: Vignette 35% at 4 Corners ──
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 100,
                              spreadRadius: 20,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── LAYER 3: Center — Engraving Logo & Specular ──
                    Center(
                      child: RepaintBoundary(
                        child: SizedBox(
                          width: 140,
                          height: 140,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // AURA GLOW (Emerald #2FBF86, breathing)
                              if (_ctrl.value >= 0.150)
                                Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color.fromRGBO(
                                      47,
                                      191,
                                      134,
                                      0.12 * _lineBreathOpacity.value,
                                    ),
                                  ),
                                ),

                              // CUSTOM PAINTER: Dot → Line → Logo
                              CustomPaint(
                                size: const Size(140, 140),
                                painter: _LightEngravingPainter(
                                  progress: _ctrl.value,
                                  dotOpacity: _dotOpacity.value,
                                  dotRadius: _dotRadius.value,
                                  lineWidth: _lineWidth.value,
                                  strokeProgress: _strokeDrawProgress.value,
                                  fillOpacity: _fillGradientOpacity.value,
                                  rimLightIntensity: _rimLightIntensity.value,
                                ),
                              ),

                              // SPECULAR SWEEP via ShaderMask
                              if (_ctrl.value >= 0.625 && _ctrl.value <= 0.850)
                                Positioned.fill(
                                  child: ClipPath(
                                    clipper: _VinFastLogoClipper(),
                                    child: ShaderMask(
                                      blendMode: BlendMode.srcATop,
                                      shaderCallback: (bounds) {
                                        return LinearGradient(
                                          begin: Alignment(
                                            _specularSweepOffset.value - 0.6,
                                            -1.0,
                                          ),
                                          end: Alignment(
                                            _specularSweepOffset.value + 0.6,
                                            1.0,
                                          ),
                                          colors: [
                                            Colors.transparent,
                                            const Color(
                                              0xFFD9C8A0,
                                            ).withValues(alpha: 0.20),
                                            const Color(
                                              0xFFFFF6E5,
                                            ).withValues(alpha: 0.70),
                                            Colors.transparent,
                                          ],
                                          stops: const [0.0, 0.4, 0.6, 1.0],
                                        ).createShader(bounds);
                                      },
                                      child: Container(color: Colors.white),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── LAYER 4: Bottom — Typography & Tagline ──
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 56,
                      child: SafeArea(
                        top: false,
                        child: Opacity(
                          opacity: _typoOpacity.value,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // APP NAME with tracking settle
                              ExcludeSemantics(
                                child: Text(
                                  'VINFAST BATTERY',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: const Color(0xFFF2EFE8),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing:
                                        18 * _trackingAnimation.value,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // TAGLINE in Champagne #D9C8A0
                              ExcludeSemantics(
                                child: Opacity(
                                  opacity: _taglineOpacity.value,
                                  child: const Text(
                                    'Hiểu pin · Sạc thông minh',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFFD9C8A0),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w300,
                                      letterSpacing: 1.2,
                                      fontFamily: 'Inter',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // SLOW NETWORK FALLBACK
                              Visibility(
                                visible: _slow,
                                maintainSize: true,
                                maintainState: true,
                                maintainAnimation: true,
                                child: Text(
                                  'Đang kết nối…',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFA9B4AD),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER: DUAL-LAYER CORE / AURA, PATHMETRIC STROKE & RIM LIGHT
// ═══════════════════════════════════════════════════════════════════════════════

class _LightEngravingPainter extends CustomPainter {
  final double progress;
  final double dotOpacity;
  final double dotRadius;
  final double lineWidth;
  final double strokeProgress;
  final double fillOpacity;
  final double rimLightIntensity;

  _LightEngravingPainter({
    required this.progress,
    required this.dotOpacity,
    required this.dotRadius,
    required this.lineWidth,
    required this.strokeProgress,
    required this.fillOpacity,
    required this.rimLightIntensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // ── NHỊP 1: Chấm sáng nhỏ ở tâm (Lõi #BFF5DE) ──
    if (progress < 0.150) {
      final corePaint = Paint()
        ..color = Color.fromRGBO(191, 245, 222, dotOpacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, dotRadius, corePaint);
      return;
    }

    // ── NHỊP 2: Đường sáng ngang 160px thon hai đầu ──
    if (progress >= 0.150 && progress < 0.355) {
      final halfW = lineWidth / 2;
      final linePaint = Paint()
        ..color = const Color(0xFFBFF5DE)
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(center.dx - halfW, center.dy),
        Offset(center.dx + halfW, center.dy),
        linePaint,
      );
      return;
    }

    // ── NHỊP 3+: Logo nét vẽ PathMetric (VinFast Winged V) ──
    if (progress >= 0.355) {
      final logoPath = _createVinFastLogoPath(size);

      // A. Fill Gradient theo hướng 10 giờ
      if (fillOpacity > 0.0) {
        final fillPaint = Paint()
          ..shader = ui.Gradient.linear(
            Offset(size.width * -0.8, 0),
            Offset(size.width * 0.8, size.height),
            [
              Color.fromRGBO(123, 232, 188, 0.16 * fillOpacity),
              Color.fromRGBO(31, 122, 84, 0.04 * fillOpacity),
            ],
          )
          ..style = PaintingStyle.fill;
        canvas.drawPath(logoPath, fillPaint);
      }

      // B. Hairline Base Outline (1.2px) — shown after fill completes
      final basePaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, size.height),
          const [Color(0xFF7BE8BC), Color(0xFF2FBF86), Color(0xFF1E7A54)],
          const [0.0, 0.5, 1.0],
        )
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (fillOpacity >= 1.0) {
        // Fill complete → draw full base outline
        canvas.drawPath(logoPath, basePaint);
      } else {
        // C. Stroke Draw theo PathMetric kèm Trailing Falloff
        for (final metric in logoPath.computeMetrics()) {
          final extract = metric.extractPath(
            0.0,
            metric.length * strokeProgress,
          );
          final strokePaint = Paint()
            ..color = const Color(0xFFBFF5DE)
            ..strokeWidth = 1.4
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;
          canvas.drawPath(extract, strokePaint);
        }
      }

      // D. Rim Light Cạnh Trên-Trái (Đồng bộ hướng sáng 10h)
      final rimPath = Path()
        ..moveTo(size.width * 0.16, size.height * 0.33)
        ..lineTo(size.width * 0.33, size.height * 0.33)
        ..lineTo(size.width * 0.50, size.height * 0.58);

      final rimPaint = Paint()
        ..color = Color.fromRGBO(255, 246, 229, rimLightIntensity)
        ..strokeWidth = rimLightIntensity > 0.5 ? 2.0 : 0.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(rimPath, rimPaint);
    }
  }

  /// VinFast Winged V logo path on a normalized canvas.
  Path _createVinFastLogoPath(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.16, h * 0.33)
      ..lineTo(w * 0.50, h * 0.78)
      ..lineTo(w * 0.84, h * 0.33)
      ..lineTo(w * 0.67, h * 0.33)
      ..lineTo(w * 0.50, h * 0.58)
      ..lineTo(w * 0.33, h * 0.33)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _LightEngravingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.fillOpacity != fillOpacity ||
        oldDelegate.rimLightIntensity != rimLightIntensity;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLIPPER FOR SHADERMASK SPECULAR LIGHT SWEEP
// ═══════════════════════════════════════════════════════════════════════════════

class _VinFastLogoClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.16, h * 0.33)
      ..lineTo(w * 0.50, h * 0.78)
      ..lineTo(w * 0.84, h * 0.33)
      ..lineTo(w * 0.67, h * 0.33)
      ..lineTo(w * 0.50, h * 0.58)
      ..lineTo(w * 0.33, h * 0.33)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
