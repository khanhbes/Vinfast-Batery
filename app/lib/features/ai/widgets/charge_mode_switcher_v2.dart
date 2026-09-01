
import 'package:flutter/material.dart';

import '../../../core/theme/cockpit_design_system.dart';

class ChargeModeSwitcherV2 extends StatefulWidget {
  const ChargeModeSwitcherV2({
    super.key,
    required this.isAiMode,
    required this.onChanged,
  });

  final bool isAiMode;
  final ValueChanged<bool> onChanged;

  @override
  State<ChargeModeSwitcherV2> createState() => _ChargeModeSwitcherV2State();
}

class _ChargeModeSwitcherV2State extends State<ChargeModeSwitcherV2>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _aiIconController;
  late final AnimationController _timerIconController;

  late final Animation<double> _pulseAnimation;
  late final Animation<double> _aiIconRotation;
  late final Animation<double> _timerIconScale;

  @override
  void initState() {
    super.initState();
    // Breathing glow animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // AI Icon slow continuous rotation (approx 15 degrees)
    _aiIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _aiIconRotation = Tween<double>(begin: -0.26, end: 0.26).animate(
      CurvedAnimation(parent: _aiIconController, curve: Curves.easeInOut),
    );

    // Timer icon scale pulse
    _timerIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _timerIconScale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _timerIconController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _aiIconController.dispose();
    _timerIconController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion ? Duration.zero : CockpitMotion.standard;
    final trailDuration = reducedMotion ? Duration.zero : const Duration(milliseconds: 400);

    return Semantics(
      label: widget.isAiMode ? 'Đang chọn sạc theo AI' : 'Đang chọn sạc hẹn giờ',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: CockpitColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: CockpitColors.emerald.withValues(alpha: .2), // Subtle outer glow border
          ),
          boxShadow: [
            BoxShadow(
              color: CockpitColors.emerald.withValues(alpha: .04),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final halfWidth = (constraints.maxWidth - 8) / 2;

            return Stack(
              children: [
                // Glow trail for sliding pill
                AnimatedPositioned(
                  duration: trailDuration,
                  curve: Curves.easeOutCubic,
                  left: widget.isAiMode ? 0 : halfWidth,
                  top: 0,
                  bottom: 0,
                  width: halfWidth,
                  child: AnimatedContainer(
                    duration: trailDuration,
                    decoration: BoxDecoration(
                      color: CockpitColors.emerald.withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: CockpitColors.emerald.withValues(alpha: .06),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),

                // Animated sliding pill background with breathing glow
                AnimatedPositioned(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  left: widget.isAiMode ? 0 : halfWidth,
                  top: 0,
                  bottom: 0,
                  width: halfWidth,
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      final double shadowOpacity = reducedMotion
                          ? 0.08
                          : 0.08 + (_pulseAnimation.value * 0.1);
                      final double spread = reducedMotion ? 0.0 : _pulseAnimation.value * 3;

                      return AnimatedContainer(
                        duration: duration,
                        decoration: BoxDecoration(
                          color: CockpitColors.emerald.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: CockpitColors.emerald.withValues(alpha: .28),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: CockpitColors.emerald.withValues(alpha: shadowOpacity),
                              blurRadius: 12,
                              spreadRadius: spread,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Tab buttons
                Row(
                  children: [
                    Expanded(
                      child: _ModeTab(
                        icon: Icons.auto_awesome_rounded,
                        label: 'Sạc theo AI',
                        isSelected: widget.isAiMode,
                        onTap: () => widget.onChanged(true),
                        reducedMotion: reducedMotion,
                        iconAnimation: _aiIconRotation,
                        isAi: true,
                      ),
                    ),
                    Expanded(
                      child: _ModeTab(
                        icon: Icons.timer_outlined,
                        label: 'Sạc hẹn giờ',
                        isSelected: !widget.isAiMode,
                        onTap: () => widget.onChanged(false),
                        reducedMotion: reducedMotion,
                        iconAnimation: _timerIconScale,
                        isAi: false,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ModeTab extends StatefulWidget {
  const _ModeTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.reducedMotion,
    required this.iconAnimation,
    required this.isAi,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool reducedMotion;
  final Animation<double> iconAnimation;
  final bool isAi;

  @override
  State<_ModeTab> createState() => _ModeTabState();
}

class _ModeTabState extends State<_ModeTab> {
  double _scale = 1.0;

  @override
  void didUpdateWidget(covariant _ModeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected && !widget.reducedMotion) {
      _triggerBounce();
    }
  }

  void _triggerBounce() async {
    setState(() => _scale = 1.05);
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) {
      setState(() => _scale = 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.reducedMotion ? Duration.zero : CockpitMotion.standard;

    Widget buildIcon() {
      if (widget.reducedMotion || !widget.isSelected) {
        return Icon(
          widget.icon,
          size: 18,
          color: widget.isSelected ? CockpitColors.emerald : CockpitColors.muted,
        );
      }

      if (widget.isAi) {
        return AnimatedBuilder(
          animation: widget.iconAnimation,
          builder: (context, child) {
            return Transform.rotate(
              angle: widget.iconAnimation.value,
              child: Icon(
                widget.icon,
                size: 18,
                color: CockpitColors.emerald,
              ),
            );
          },
        );
      } else {
        return ScaleTransition(
          scale: widget.iconAnimation,
          child: Icon(
            widget.icon,
            size: 18,
            color: CockpitColors.emerald,
          ),
        );
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: _scale,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    buildIcon(),
                    const SizedBox(width: 7),
                    Flexible(
                      child: AnimatedDefaultTextStyle(
                        duration: duration,
                        style: TextStyle(
                          color: widget.isSelected
                              ? CockpitColors.emerald
                              : CockpitColors.muted,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                // Active dot indicator
                AnimatedOpacity(
                  duration: duration,
                  opacity: widget.isSelected ? 1.0 : 0.0,
                  child: Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: CockpitColors.emerald,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
