import 'package:flutter/material.dart';

/// Breathing Bot Avatar with pulsating soft halo animation
class BreathingBotAvatar extends StatefulWidget {
  const BreathingBotAvatar({
    super.key,
    this.size = 32.0,
    this.isStreaming = false,
    this.mood = 'happy',
  });

  final double size;
  final bool isStreaming;
  final String mood;

  @override
  State<BreathingBotAvatar> createState() => _BreathingBotAvatarState();
}

class _BreathingBotAvatarState extends State<BreathingBotAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.isStreaming ? 1000 : 2400),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant BreathingBotAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isStreaming != widget.isStreaming) {
      _animController.duration =
          Duration(milliseconds: widget.isStreaming ? 1000 : 2400);
      if (!_animController.isAnimating) {
        _animController.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final pulseProgress = _animController.value;
        final glowRadius = 4.0 + (pulseProgress * 6.0);
        final glowAlpha = 0.20 + (pulseProgress * 0.25);
        final scale = 1.0 + (pulseProgress * 0.04);

        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer breathing glow halo
            Container(
              width: widget.size * scale + 4,
              height: widget.size * scale + 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00C853).withValues(alpha: glowAlpha),
                    blurRadius: glowRadius,
                    spreadRadius: pulseProgress * 2.0,
                  ),
                  BoxShadow(
                    color: const Color(0xFF0072BC).withValues(alpha: glowAlpha * 0.8),
                    blurRadius: glowRadius * 1.2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),

            // Inner avatar circle with gradient
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF0072BC),
                    Color(0xFF00C853),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.smart_toy_rounded,
                color: Colors.white,
                size: widget.size * 0.56,
              ),
            ),
          ],
        );
      },
    );
  }
}
