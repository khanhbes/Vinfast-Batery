import 'package:flutter/material.dart';

import '../../../core/theme/plan_style.dart';
import '../../../core/widgets/battery_bot_mascot.dart';

/// Breathing Bot Avatar with pulsating soft halo animation
class BreathingBotAvatar extends StatefulWidget {
  const BreathingBotAvatar({
    super.key,
    this.size = 32.0,
    this.isStreaming = false,
    this.mood = BatteryBotMood.happy,
  });

  final double size;
  final bool isStreaming;

  /// The face shown (QA 151: Pinova Bot itself, not a generic robot
  /// icon). While the reply is being written it is always `thinking`.
  final BatteryBotMood mood;

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
      duration: const Duration(milliseconds: 1000),
    );
    // Glow only while this reply is being written (Task 125): every bubble
    // used to run its own endless ticker.
    if (widget.isStreaming) _animController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant BreathingBotAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isStreaming != widget.isStreaming) {
      if (widget.isStreaming) {
        _animController.repeat(reverse: true);
      } else {
        _animController
          ..stop()
          ..value = 0;
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
    // QA 141: the plan's colours (was the old VinFast green/blue).
    final colors = PlanStyle.of(context).accentColors;
    final first = colors.first;
    final last = colors.last;
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
                    color: first.withValues(alpha: glowAlpha),
                    blurRadius: glowRadius,
                    spreadRadius: pulseProgress * 2.0,
                  ),
                  BoxShadow(
                    color: last.withValues(alpha: glowAlpha * 0.8),
                    blurRadius: glowRadius * 1.2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),

            BatteryBotMascot(
              displayMode: BatteryBotDisplayMode.avatar,
              size: BatteryBotSize.avatar,
              customWidth: widget.size,
              mood: widget.isStreaming ? BatteryBotMood.thinking : widget.mood,
              enableFloating: false,
            ),
          ],
        );
      },
    );
  }
}
