import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_ui_colors.dart';

class AnimatedVoiceWaveform extends StatefulWidget {
  const AnimatedVoiceWaveform({
    super.key,
    required this.isListening,
    this.soundLevel = 0.5,
    this.barCount = 14,
    this.height = 36,
  });

  final bool isListening;
  final double soundLevel;
  final int barCount;
  final double height;

  @override
  State<AnimatedVoiceWaveform> createState() => _AnimatedVoiceWaveformState();
}

class _AnimatedVoiceWaveformState extends State<AnimatedVoiceWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiColors = AppUiColors.of(context);

    if (!widget.isListening) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        return SizedBox(
          height: widget.height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(widget.barCount, (index) {
              final phase = (index / widget.barCount) * pi;
              final wave = sin(_animController.value * 2 * pi + phase).abs();
              final heightMultiplier = (wave * 0.5 + widget.soundLevel * 0.5).clamp(0.15, 1.0);
              final barHeight = widget.height * heightMultiplier;

              return Container(
                width: 3.5,
                height: barHeight,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0072BC), Color(0xFF00E676)],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: uiColors.primary.withValues(alpha: 0.3),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
