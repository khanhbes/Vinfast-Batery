import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:vinfast_battery/core/theme/cockpit_design_system.dart';

/// ---------------------------------------------------------------------------
/// EvEnergyOrb: A dynamic emerald energy sphere with rotating particles,
/// inner plasma glow, and subtle breathing pulse. Replaces generic icons.
/// ---------------------------------------------------------------------------
class EvEnergyOrb extends StatefulWidget {
  final double size;
  final bool showParticles;
  final Color? primaryColor;
  final Color? glowColor;
  final VoidCallback? onTap;

  const EvEnergyOrb({
    super.key,
    this.size = 48.0,
    this.showParticles = true,
    this.primaryColor,
    this.glowColor,
    this.onTap,
  });

  @override
  State<EvEnergyOrb> createState() => _EvEnergyOrbState();
}

class _EvEnergyOrbState extends State<EvEnergyOrb>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _orbitCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!CockpitMotion.enabled(context)) {
      if (_pulseCtrl.isAnimating) _pulseCtrl.stop();
      if (_orbitCtrl.isAnimating) _orbitCtrl.stop();
    } else {
      if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat(reverse: true);
      if (!_orbitCtrl.isAnimating) _orbitCtrl.repeat();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _orbitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool animationsEnabled = CockpitMotion.enabled(context);
    final primary = widget.primaryColor ?? CockpitColors.emeraldStrong;
    final glow = widget.glowColor ?? CockpitColors.emerald;

    Widget orb = SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseCtrl, _orbitCtrl]),
        builder: (context, _) {
          return CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _EnergyOrbPainter(
              pulseVal: animationsEnabled ? _pulseCtrl.value : 0.5,
              orbitAngle: animationsEnabled
                  ? _orbitCtrl.value * 2 * math.pi
                  : 0.0,
              primaryColor: primary,
              glowColor: glow,
              showParticles: widget.showParticles,
            ),
          );
        },
      ),
    );

    if (widget.onTap != null) {
      return GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: orb,
      );
    }
    return orb;
  }
}

class _EnergyOrbPainter extends CustomPainter {
  final double pulseVal;
  final double orbitAngle;
  final Color primaryColor;
  final Color glowColor;
  final bool showParticles;

  _EnergyOrbPainter({
    required this.pulseVal,
    required this.orbitAngle,
    required this.primaryColor,
    required this.glowColor,
    required this.showParticles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    final coreRadius = maxRadius * 0.42;

    // 1. Outer diffuse glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          glowColor.withValues(alpha: 0.28 + pulseVal * 0.12),
          glowColor.withValues(alpha: 0.08 + pulseVal * 0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(
        Rect.fromCircle(center: center, radius: maxRadius),
      );
    canvas.drawCircle(center, maxRadius, glowPaint);

    // 2. Orbital subtle ring
    if (showParticles && size.width >= 32) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = glowColor.withValues(alpha: 0.15 + pulseVal * 0.1);
      canvas.drawCircle(center, maxRadius * 0.76, ringPaint);

      // 3. Orbiting energy particles
      final pCount = size.width >= 64 ? 4 : 2;
      for (int i = 0; i < pCount; i++) {
        final angle = orbitAngle + (i * 2 * math.pi / pCount);
        final pRadius = maxRadius * (0.72 + 0.06 * math.sin(angle * 2));
        final px = center.dx + pRadius * math.cos(angle);
        final py = center.dy + pRadius * math.sin(angle);
        final pSize = 1.6 + 0.8 * math.sin(pulseVal * math.pi + i);

        final pPaint = Paint()
          ..color = primaryColor.withValues(alpha: 0.75 + 0.25 * math.cos(angle))
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(px, py), pSize, pPaint);
      }
    }

    // 4. Inner core gradient
    final corePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.3),
        colors: [
          const Color(0xFFA7F3D0), // Bright emerald highlight
          primaryColor,
          const Color(0xFF047857), // Deep emerald shadow
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: center,
          radius: coreRadius * (0.95 + pulseVal * 0.08),
        ),
      );
    canvas.drawCircle(
      center,
      coreRadius * (0.95 + pulseVal * 0.08),
      corePaint,
    );

    // 5. Specular highlight
    final specPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55 + pulseVal * 0.2)
      ..style = PaintingStyle.fill;
    final specOffset = Offset(
      center.dx - coreRadius * 0.3,
      center.dy - coreRadius * 0.35,
    );
    canvas.drawCircle(specOffset, coreRadius * 0.22, specPaint);
  }

  @override
  bool shouldRepaint(covariant _EnergyOrbPainter oldDelegate) =>
      oldDelegate.pulseVal != pulseVal ||
      oldDelegate.orbitAngle != orbitAngle ||
      oldDelegate.primaryColor != primaryColor;
}

/// ---------------------------------------------------------------------------
/// EvChargingWave: A flowing emerald wave curve with animated phase and glow.
/// Ideal for loading bars, bottom borders, or energy telemetry indicators.
/// ---------------------------------------------------------------------------
class EvChargingWave extends StatefulWidget {
  final double height;
  final double? width;
  final Color? color;
  final Color? glowColor;
  final double strokeWidth;

  const EvChargingWave({
    super.key,
    this.height = 10.0,
    this.width,
    this.color,
    this.glowColor,
    this.strokeWidth = 2.0,
  });

  @override
  State<EvChargingWave> createState() => _EvChargingWaveState();
}

class _EvChargingWaveState extends State<EvChargingWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!CockpitMotion.enabled(context)) {
      if (_controller.isAnimating) _controller.stop();
    } else {
      if (!_controller.isAnimating) _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool animated = CockpitMotion.enabled(context);
    final waveColor = widget.color ?? CockpitColors.emeraldStrong;

    return SizedBox(
      width: widget.width ?? double.infinity,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _ChargingWavePainter(
              phase: animated ? _controller.value * 2 * math.pi : 0.0,
              color: waveColor,
              strokeWidth: widget.strokeWidth,
            ),
          );
        },
      ),
    );
  }
}

class _ChargingWavePainter extends CustomPainter {
  final double phase;
  final Color color;
  final double strokeWidth;

  _ChargingWavePainter({
    required this.phase,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final path = Path();
    final midY = size.height / 2;
    final amplitude = (size.height / 2) * 0.75;
    const wavelength = 65.0;

    path.moveTo(0, midY + amplitude * math.sin(phase));

    for (double x = 1; x <= size.width; x += 2) {
      final y = midY + amplitude * math.sin((x / wavelength) * 2 * math.pi + phase);
      path.lineTo(x, y);
    }

    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.1),
          color.withValues(alpha: 0.9),
          color,
          color.withValues(alpha: 0.9),
          color.withValues(alpha: 0.1),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(path, wavePaint);
  }

  @override
  bool shouldRepaint(covariant _ChargingWavePainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}

/// ---------------------------------------------------------------------------
/// EvPulseDot: 3 minimalist emerald dots pulsing sequentially without icons.
/// Replaces generic typing indicators.
/// ---------------------------------------------------------------------------
class EvPulseDot extends StatefulWidget {
  final double size;
  final double spacing;
  final Color? color;

  const EvPulseDot({
    super.key,
    this.size = 6.0,
    this.spacing = 5.0,
    this.color,
  });

  @override
  State<EvPulseDot> createState() => _EvPulseDotState();
}

class _EvPulseDotState extends State<EvPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool animated = CockpitMotion.enabled(context);
    final dotColor = widget.color ?? CockpitColors.emeraldStrong;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            double progress = _controller.value;
            if (animated) {
              progress = (_controller.value - (index * 0.22)) % 1.0;
              if (progress < 0) progress += 1.0;
            } else {
              progress = 0.5;
            }

            // Sine peak around 0.5
            final scale = 0.7 + 0.5 * math.sin(progress * math.pi);
            final alpha = 0.35 + 0.65 * math.sin(progress * math.pi);

            return Container(
              margin: EdgeInsets.symmetric(horizontal: widget.spacing / 2),
              width: widget.size * scale,
              height: widget.size * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor.withValues(alpha: alpha.clamp(0.0, 1.0)),
                boxShadow: [
                  BoxShadow(
                    color: dotColor.withValues(alpha: (alpha * 0.4).clamp(0.0, 1.0)),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            );
          },
        );
      }),
    );
  }
}

/// ---------------------------------------------------------------------------
/// EvGlowLine: A sleek horizontal separator with sweeping emerald shimmer glow.
/// Replaces generic Material Dividers across the application.
/// ---------------------------------------------------------------------------
class EvGlowLine extends StatefulWidget {
  final double height;
  final Color? color;
  final Duration duration;

  const EvGlowLine({
    super.key,
    this.height = 1.5,
    this.color,
    this.duration = const Duration(milliseconds: 2600),
  });

  @override
  State<EvGlowLine> createState() => _EvGlowLineState();
}

class _EvGlowLineState extends State<EvGlowLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool animated = CockpitMotion.enabled(context);
    final glow = widget.color ?? CockpitColors.emeraldStrong;

    return SizedBox(
      height: widget.height + 4.0,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size(double.infinity, widget.height),
            painter: _GlowLinePainter(
              progress: animated ? _controller.value : 0.5,
              glowColor: glow,
              height: widget.height,
            ),
          );
        },
      ),
    );
  }
}

class _GlowLinePainter extends CustomPainter {
  final double progress;
  final Color glowColor;
  final double height;

  _GlowLinePainter({
    required this.progress,
    required this.glowColor,
    required this.height,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baseLinePaint = Paint()
      ..color = CockpitColors.border
      ..strokeWidth = height;

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      baseLinePaint,
    );

    // Dynamic sweeping glow segment
    final glowWidth = size.width * 0.35;
    final glowStart = (size.width + glowWidth) * progress - glowWidth;

    final glowPaint = Paint()
      ..strokeWidth = height + 1.2
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          glowColor.withValues(alpha: 0.8),
          const Color(0xFFA7F3D0), // Bright white-emerald core
          glowColor.withValues(alpha: 0.8),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(glowStart, 0, glowWidth, size.height));

    canvas.drawLine(
      Offset(math.max(0, glowStart), size.height / 2),
      Offset(math.min(size.width, glowStart + glowWidth), size.height / 2),
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GlowLinePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.glowColor != glowColor;
}

/// ---------------------------------------------------------------------------
/// EvSuccessRipple: Concentric emerald ripples expanding and fading outward.
/// Perfect for confirming a successful step or action.
/// ---------------------------------------------------------------------------
class EvSuccessRipple extends StatefulWidget {
  final double size;
  final Widget? child;
  final Color? color;

  const EvSuccessRipple({
    super.key,
    this.size = 80.0,
    this.child,
    this.color,
  });

  @override
  State<EvSuccessRipple> createState() => _EvSuccessRippleState();
}

class _EvSuccessRippleState extends State<EvSuccessRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rippleColor = widget.color ?? CockpitColors.emeraldStrong;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _RipplePainter(
                  progress: _controller.value,
                  color: rippleColor,
                ),
              );
            },
          ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double progress;
  final Color color;

  _RipplePainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress + (i * 0.33)) % 1.0;
      final currentRadius = maxR * (0.3 + ringProgress * 0.7);
      final alpha = (1.0 - ringProgress).clamp(0.0, 1.0) * 0.5;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8 * (1.0 - ringProgress * 0.5)
        ..color = color.withValues(alpha: alpha);

      canvas.drawCircle(center, currentRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// ---------------------------------------------------------------------------
/// EvBatteryFillAnim: Sleek 2D EV battery silhouette with liquid energy fill
/// level and oscillating wave surface. Minimal and professional.
/// ---------------------------------------------------------------------------
class EvBatteryFillAnim extends StatefulWidget {
  final double width;
  final double height;
  final double fillPercentage; // 0.0 to 1.0
  final bool isCharging;
  final Color? fillColor;

  const EvBatteryFillAnim({
    super.key,
    this.width = 44.0,
    this.height = 80.0,
    this.fillPercentage = 0.82,
    this.isCharging = true,
    this.fillColor,
  });

  @override
  State<EvBatteryFillAnim> createState() => _EvBatteryFillAnimState();
}

class _EvBatteryFillAnimState extends State<EvBatteryFillAnim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveCtrl;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!CockpitMotion.enabled(context)) {
      if (_waveCtrl.isAnimating) _waveCtrl.stop();
    } else {
      if (!_waveCtrl.isAnimating) _waveCtrl.repeat();
    }
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool animated = CockpitMotion.enabled(context);
    final primary = widget.fillColor ?? CockpitColors.emeraldStrong;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _waveCtrl,
        builder: (context, _) {
          return CustomPaint(
            size: Size(widget.width, widget.height),
            painter: _BatteryFillPainter(
              wavePhase: animated ? _waveCtrl.value * 2 * math.pi : 0.0,
              fillPercentage: widget.fillPercentage.clamp(0.05, 1.0),
              isCharging: widget.isCharging,
              fillColor: primary,
            ),
          );
        },
      ),
    );
  }
}

class _BatteryFillPainter extends CustomPainter {
  final double wavePhase;
  final double fillPercentage;
  final bool isCharging;
  final Color fillColor;

  _BatteryFillPainter({
    required this.wavePhase,
    required this.fillPercentage,
    required this.isCharging,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final capHeight = size.height * 0.08;
    final capWidth = size.width * 0.38;
    final bodyHeight = size.height - capHeight - 2;
    const strokeW = 2.0;

    // 1. Draw top terminal cap
    final capRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(
        (size.width - capWidth) / 2,
        0,
        capWidth,
        capHeight,
      ),
      topLeft: const Radius.circular(3),
      topRight: const Radius.circular(3),
    );
    final capPaint = Paint()
      ..color = CockpitColors.borderStrong
      ..style = PaintingStyle.fill;
    canvas.drawRRect(capRect, capPaint);

    // 2. Battery outer casing
    final bodyRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, capHeight + 2, size.width, bodyHeight),
      const Radius.circular(8),
    );

    final bgPaint = Paint()
      ..color = CockpitColors.surface
      ..style = PaintingStyle.fill;
    canvas.drawRRect(bodyRRect, bgPaint);

    final borderPaint = Paint()
      ..color = CockpitColors.borderStrong
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(bodyRRect, borderPaint);

    // 3. Liquid fill path with wavy surface
    final innerRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeW + 1,
        capHeight + 2 + strokeW + 1,
        size.width - (strokeW + 1) * 2,
        bodyHeight - (strokeW + 1) * 2,
      ),
      const Radius.circular(6),
    );

    canvas.save();
    canvas.clipRRect(innerRRect);

    final fillH = innerRRect.height * fillPercentage;
    final fillTop = innerRRect.top + (innerRRect.height - fillH);

    final wavePath = Path();
    wavePath.moveTo(innerRRect.left, innerRRect.bottom);
    wavePath.lineTo(innerRRect.left, fillTop);

    // Draw wavy liquid crest
    const waveAmp = 2.2;
    for (double x = innerRRect.left; x <= innerRRect.right; x += 1) {
      final relX = (x - innerRRect.left) / innerRRect.width;
      final y = fillTop + waveAmp * math.sin(relX * 2 * math.pi + wavePhase);
      wavePath.lineTo(x, y);
    }

    wavePath.lineTo(innerRRect.right, innerRRect.bottom);
    wavePath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          fillColor.withValues(alpha: 0.85),
          fillColor,
          const Color(0xFFA7F3D0), // Surface foam/shine
        ],
        stops: const [0.0, 0.85, 1.0],
      ).createShader(innerRRect.outerRect);

    canvas.drawPath(wavePath, fillPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BatteryFillPainter oldDelegate) =>
      oldDelegate.wavePhase != wavePhase ||
      oldDelegate.fillPercentage != fillPercentage ||
      oldDelegate.fillColor != fillColor;
}

/// ---------------------------------------------------------------------------
/// EvLottieSuccessCheck: High quality animated checkmark backed by Lottie,
/// with automatic CustomPainter fallback if asset resolution encounters delays.
/// ---------------------------------------------------------------------------
class EvLottieSuccessCheck extends StatelessWidget {
  final double size;
  final bool repeat;

  const EvLottieSuccessCheck({
    super.key,
    this.size = 72.0,
    this.repeat = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        'assets/lottie/success_check.json',
        repeat: repeat,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback to custom ripple with emerald check
          return EvSuccessRipple(
            size: size,
            child: Icon(
              Icons.check_circle_rounded,
              size: size * 0.6,
              color: CockpitColors.emeraldStrong,
            ),
          );
        },
      ),
    );
  }
}
