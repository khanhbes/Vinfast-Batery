import 'package:flutter/material.dart';

/// 3-dots bounce typing indicator (replaces italic status text)
class TypingIndicatorDots extends StatefulWidget {
  const TypingIndicatorDots({
    super.key,
    this.dotColor,
    this.dotSize = 7.0,
    this.spacing = 4.0,
  });

  final Color? dotColor;
  final double dotSize;
  final double spacing;

  @override
  State<TypingIndicatorDots> createState() => _TypingIndicatorDotsState();
}

class _TypingIndicatorDotsState extends State<TypingIndicatorDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        widget.dotColor ?? Theme.of(context).colorScheme.primary;

    return Semantics(
      label: 'BatteryBot đang soạn câu trả lời...',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // Staggered sine wave for each dot
                final delay = index * 0.22;
                final progress = (_controller.value - delay) % 1.0;
                final double bounce;
                if (progress < 0.5) {
                  bounce = Curves.easeInOut.transform(progress * 2);
                } else {
                  bounce = Curves.easeInOut.transform((1.0 - progress) * 2);
                }

                // Vertical translation up to 6px and opacity variation
                final translateY = -bounce * 6.0;
                final opacity = 0.35 + (0.65 * bounce);
                final scale = 0.85 + (0.25 * bounce);

                return Transform.translate(
                  offset: Offset(0, translateY),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: widget.spacing / 2),
                      width: widget.dotSize,
                      height: widget.dotSize,
                      decoration: BoxDecoration(
                        color: effectiveColor.withValues(alpha: opacity),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: effectiveColor.withValues(alpha: opacity * 0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}
