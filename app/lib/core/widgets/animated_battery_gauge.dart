import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// Widget vẽ gauge pin với animation xoay tròn
class AnimatedBatteryGauge extends StatefulWidget {
  final int batteryPercent;
  final double size;
  final Duration animationDuration;

  const AnimatedBatteryGauge({
    super.key,
    required this.batteryPercent,
    this.size = 200,
    this.animationDuration = AppMotion.ambient,
  });

  @override
  State<AnimatedBatteryGauge> createState() => _AnimatedBatteryGaugeState();
}

class _AnimatedBatteryGaugeState extends State<AnimatedBatteryGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  double get _target => widget.batteryPercent.clamp(0, 100) / 100.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotion.enabled(context)) _controller.value = 1;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _animation = Tween<double>(
      begin: 0,
      end: _target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedBatteryGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.animationDuration;
    if (oldWidget.batteryPercent != widget.batteryPercent) {
      _animation = Tween<double>(begin: _animation.value, end: _target).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
      if (AppMotion.enabled(context)) {
        _controller.forward(from: 0);
      } else {
        _controller.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getBatteryColor(double percent) {
    if (percent >= 0.7) return AppColors.batteryFull;
    if (percent >= 0.4) return AppColors.batteryMedium;
    if (percent >= 0.2) return AppColors.batteryLow;
    return AppColors.batteryCritical;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final value = _animation.value;
        final color = _getBatteryColor(value);

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background arc
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _GaugeBackgroundPainter(),
              ),
              // Filled arc
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _GaugeFillPainter(value: value, color: color),
              ),
              // Glow effect
              Container(
                width: widget.size * 0.65,
                height: widget.size * 0.65,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.15),
                      blurRadius: 40,
                      spreadRadius: 5,
                    ),
                  ],
                ),
              ),
              // Center content with overflow protection for large text scaling
              Padding(
                padding: EdgeInsets.all(widget.size * 0.12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        color: color,
                        size: widget.size * 0.15,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.batteryPercent.clamp(0, 100)}%',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: widget.size * 0.18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      Text(
                        'Pin',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: widget.size * 0.07,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GaugeBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 24) / 2;

    final paint = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GaugeFillPainter extends CustomPainter {
  final double value;
  final Color color;

  _GaugeFillPainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 24) / 2;

    if (value > 0.001) {
      // Gradient stroke
      final paint = Paint()
        ..shader = SweepGradient(
          startAngle: math.pi * 0.75,
          endAngle: math.pi * 0.75 + math.pi * 1.5 * value,
          colors: [color.withValues(alpha: 0.6), color],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        math.pi * 0.75,
        math.pi * 1.5 * value,
        false,
        paint,
      );
    }

    // Glow at tip
    if (value > 0.01) {
      final tipAngle = math.pi * 0.75 + math.pi * 1.5 * value;
      final tipX = center.dx + radius * math.cos(tipAngle);
      final tipY = center.dy + radius * math.sin(tipAngle);

      canvas.drawCircle(
        Offset(tipX, tipY),
        6,
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaugeFillPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}
