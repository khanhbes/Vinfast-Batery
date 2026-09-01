import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/cockpit_design_system.dart';

/// Circular AI charge button with premium ambient pulsing halo, ripple, and shimmer animations.
class AIChargeButton extends StatefulWidget {
  const AIChargeButton({
    super.key,
    required this.onPressed,
    required this.isAiMode,
    this.enabled = true,
    this.size = 112,
  });

  final VoidCallback onPressed;
  final bool isAiMode;
  final bool enabled;
  final double size;

  @override
  State<AIChargeButton> createState() => _AIChargeButtonState();
}

class _AIChargeButtonState extends State<AIChargeButton>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late AnimationController _ringController;
  late AnimationController _rippleController;
  late AnimationController _gradientController;
  late AnimationController _shimmerController;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _ringController.dispose();
    _rippleController.dispose();
    _gradientController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Alignment _getAlignment(double value, double offset) {
    final angle = value * 2 * math.pi + offset;
    return Alignment(math.cos(angle), math.sin(angle));
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.enabled) {
      setState(() => _pressed = true);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.enabled) {
      setState(() => _pressed = false);
      widget.onPressed();
    }
  }

  void _handleTapCancel() {
    if (widget.enabled) {
      setState(() => _pressed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.enabled;
    // Ensure ripples have enough space to draw without clipping
    final boxSize = widget.size + 80;

    return SizedBox(
      width: boxSize,
      height: boxSize,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Expanding Ripple Halo
          if (enabled && !reducedMotion)
            CustomPaint(
              size: Size(boxSize, boxSize),
              painter: _RipplePainter(
                animation: _rippleController,
                color: CockpitColors.emerald,
                baseRadius: widget.size / 2,
              ),
            ),

          // Layer 1: Outer blur glow (pulsing) - Multi-layer neon
          if (enabled && !reducedMotion)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) => Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: CockpitColors.emerald.withValues(
                        alpha: .05 + _pulseController.value * .08,
                      ),
                      blurRadius: 20 + _pulseController.value * 10,
                      spreadRadius: 4 + _pulseController.value * 6,
                    ),
                    BoxShadow(
                      color: CockpitColors.emerald.withValues(
                        alpha: .10 + _pulseController.value * .15,
                      ),
                      blurRadius: 32,
                      spreadRadius: 8 + _pulseController.value * 10,
                    ),
                    BoxShadow(
                      color: CockpitColors.emerald.withValues(
                        alpha: .15 + _pulseController.value * .20,
                      ),
                      blurRadius: 45,
                      spreadRadius: 12 + _pulseController.value * 15,
                    ),
                  ],
                ),
              ),
            ),

          // Layer 2: Pulsing ring border
          if (enabled && !reducedMotion)
            AnimatedBuilder(
              animation: _ringController,
              builder: (context, _) => Container(
                width: widget.size + 8,
                height: widget.size + 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: CockpitColors.emerald.withValues(
                      alpha: .15 + _ringController.value * .25,
                    ),
                    width: 1.5,
                  ),
                ),
              ),
            ),

          // Layer 3: Particle Ring
          if (enabled && !reducedMotion)
            AnimatedBuilder(
              animation: _rotateController,
              builder: (context, _) => Transform.rotate(
                angle: _rotateController.value * 2 * math.pi,
                child: CustomPaint(
                  size: Size(widget.size + 16, widget.size + 16),
                  painter: _ParticleRingPainter(
                    color: CockpitColors.emerald,
                    rotateValue: _rotateController.value,
                  ),
                ),
              ),
            ),

          // Main button with Scale bounce
          AnimatedScale(
            scale: _pressed ? 0.92 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutBack,
            child: GestureDetector(
              onTapDown: _handleTapDown,
              onTapUp: _handleTapUp,
              onTapCancel: _handleTapCancel,
              child: AnimatedOpacity(
                duration: CockpitMotion.standard,
                opacity: enabled ? 1.0 : 0.35,
                child: AnimatedBuilder(
                  animation: _gradientController,
                  builder: (context, child) {
                    return Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: enabled
                            ? LinearGradient(
                                begin: _getAlignment(_gradientController.value, 0),
                                end: _getAlignment(_gradientController.value, math.pi),
                                colors: const [
                                  CockpitColors.emeraldStrong,
                                  CockpitColors.emerald,
                                  Color(0xFF5EEAD4),
                                ],
                              )
                            : null,
                        color: enabled ? null : CockpitColors.elevated,
                        border: Border.all(
                          color: enabled
                              ? CockpitColors.emerald.withValues(alpha: .4)
                              : CockpitColors.border,
                          width: 2,
                        ),
                      ),
                      child: child,
                    );
                  },
                  child: ClipOval(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Shimmer sweep
                        if (enabled && !reducedMotion)
                          CustomPaint(
                            size: Size(widget.size, widget.size),
                            painter: _ShimmerPainter(
                              animation: _shimmerController,
                            ),
                          ),
                        // Icon
                        Icon(
                          widget.isAiMode
                              ? Icons.auto_awesome_rounded
                              : Icons.power_settings_new_rounded,
                          size: widget.size * 0.38,
                          color: enabled
                              ? const Color(0xFF0A0A0A)
                              : CockpitColors.dim,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter({
    required this.animation,
    required this.color,
    required this.baseRadius,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final double baseRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    
    final radius = baseRadius + (maxRadius - baseRadius) * animation.value;
    final opacity = 0.3 * (1 - animation.value);
    
    if (opacity <= 0) return;
    
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
      
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_RipplePainter old) => 
      old.animation != animation || 
      old.color != color || 
      old.baseRadius != baseRadius;
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter({required this.animation}) : super(repaint: animation);
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    // Sweep from left-to-right diagonally
    final offset = -size.width + (size.width * 3) * animation.value;

    final path = Path()
      ..moveTo(offset, 0)
      ..lineTo(offset + 30, 0)
      ..lineTo(offset - 20, size.height)
      ..lineTo(offset - 50, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(_ShimmerPainter old) => old.animation != animation;
}

class _ParticleRingPainter extends CustomPainter {
  _ParticleRingPainter({required this.color, required this.rotateValue});
  final Color color;
  final double rotateValue;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    const particleCount = 40;
    const angleStep = (2 * math.pi) / particleCount;

    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < particleCount; i++) {
      final baseAngle = i * angleStep;
      // Modulate size and opacity for an organic feel
      final phase = math.sin(baseAngle * 4 + rotateValue * 2 * math.pi * 6);
      
      final pRadius = 1.0 + 1.2 * (0.5 + 0.5 * phase);
      final pOpacity = 0.15 + 0.85 * (0.5 + 0.5 * phase);
      
      paint.color = color.withValues(alpha: pOpacity);
      
      final x = center.dx + radius * math.cos(baseAngle);
      final y = center.dy + radius * math.sin(baseAngle);
      
      canvas.drawCircle(Offset(x, y), pRadius, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticleRingPainter old) => 
      old.color != color || old.rotateValue != rotateValue;
}
