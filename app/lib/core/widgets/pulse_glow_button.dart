import 'package:flutter/material.dart';
import '../theme/cockpit_design_system.dart';

/// Interactive button / toggle featuring:
/// 1. Pulse glow: Breathing emerald ambient glow when active
/// 2. Ripple wave: Expanding radial shockwave when tapped or switched
/// 3. Smooth scale & haptic-like press animation
class PulseGlowButton extends StatefulWidget {
  const PulseGlowButton({
    super.key,
    required this.isActive,
    required this.onTap,
    this.label,
    this.activeLabel,
    this.icon,
    this.activeIcon,
    this.activeColor = CockpitColors.emeraldStrong,
    this.inactiveColor = CockpitColors.surfaceSoft,
    this.width,
    this.height = CockpitButtonTokens.height,
    this.borderRadius = CockpitRadius.medium,
    this.showGlow = true,
  });

  final bool isActive;
  final VoidCallback onTap;
  final String? label;
  final String? activeLabel;
  final IconData? icon;
  final IconData? activeIcon;
  final Color activeColor;
  final Color inactiveColor;
  final double? width;
  final double height;
  final double borderRadius;
  final bool showGlow;

  @override
  State<PulseGlowButton> createState() => _PulseGlowButtonState();
}

class _PulseGlowButtonState extends State<PulseGlowButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  late final AnimationController _rippleController;
  late final Animation<double> _rippleScaleAnimation;
  late final Animation<double> _rippleOpacityAnimation;

  late final AnimationController _pressController;
  late final Animation<double> _pressScaleAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse breathing glow
    _pulseController = AnimationController(
      vsync: this,
      duration: CockpitMotion.glowPulse,
    );
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOutSine,
    );

    if (widget.isActive && widget.showGlow) {
      _pulseController.repeat(reverse: true);
    }

    // Shockwave ripple
    _rippleController = AnimationController(
      vsync: this,
      duration: CockpitMotion.ripple,
    );
    _rippleScaleAnimation = Tween<double>(begin: 0.95, end: 1.35).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOutCubic),
    );
    _rippleOpacityAnimation = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOutCubic),
    );

    // Tap scale down
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _pressScaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(PulseGlowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        if (widget.showGlow) {
          _pulseController.repeat(reverse: true);
        }
        _rippleController.forward(from: 0.0);
      } else {
        _pulseController.stop();
        _pulseController.reset();
        _rippleController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rippleController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _pressController.forward().then((_) => _pressController.reverse());
    _rippleController.forward(from: 0.0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLabel = widget.isActive
        ? (widget.activeLabel ?? widget.label)
        : widget.label;
    final effectiveIcon = widget.isActive
        ? (widget.activeIcon ?? widget.icon)
        : widget.icon;

    return Semantics(
      button: true,
      toggled: widget.isActive,
      label: effectiveLabel ?? 'Toggle',
      child: GestureDetector(
        onTap: _handleTap,
        child: ScaleTransition(
          scale: _pressScaleAnimation,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Ripple shockwave ring on state change
              AnimatedBuilder(
                animation: _rippleController,
                builder: (context, _) {
                  if (_rippleController.value == 0 ||
                      _rippleController.isCompleted) {
                    return const SizedBox.shrink();
                  }
                  return Transform.scale(
                    scale: _rippleScaleAnimation.value,
                    child: Container(
                      width: widget.width,
                      height: widget.height,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.borderRadius + 4),
                        border: Border.all(
                          color: widget.activeColor.withValues(
                            alpha: _rippleOpacityAnimation.value,
                          ),
                          width: 2.0,
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Button Body with pulsing shadow
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  final glowFactor = widget.isActive && widget.showGlow
                      ? _pulseAnimation.value
                      : 0.0;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: widget.width,
                    height: widget.height,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: widget.isActive
                          ? widget.activeColor
                          : widget.inactiveColor,
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                      border: Border.all(
                        color: widget.isActive
                            ? widget.activeColor.withValues(alpha: 0.8)
                            : CockpitColors.borderStrong,
                        width: 1.2,
                      ),
                      boxShadow: widget.isActive
                          ? [
                              BoxShadow(
                                color: widget.activeColor.withValues(
                                  alpha: 0.25 + 0.35 * glowFactor,
                                ),
                                blurRadius: 10.0 + 14.0 * glowFactor,
                                spreadRadius: 1.0 + 3.0 * glowFactor,
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisSize: widget.width != null
                      ? MainAxisSize.max
                      : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (effectiveIcon != null) ...[
                      Icon(
                        effectiveIcon,
                        size: 20,
                        color: widget.isActive
                            ? Colors.black
                            : CockpitColors.muted,
                      ),
                      if (effectiveLabel != null) const SizedBox(width: 8),
                    ],
                    if (effectiveLabel != null)
                      Text(
                        effectiveLabel,
                        style: CockpitTypography.heading(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: widget.isActive
                              ? Colors.black
                              : CockpitColors.text,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
