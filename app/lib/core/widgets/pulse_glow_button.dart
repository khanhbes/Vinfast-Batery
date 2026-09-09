import 'package:flutter/material.dart';
import '../theme/cockpit_design_system.dart';

/// Explicit command states for asynchronous charging/vehicle operations.
enum CommandState {
  idle,
  sending,
  confirming,
  confirmed,
  failed,
}

/// Interactive button / toggle featuring:
/// 1. Command State Flow: sending (amber spinner) -> confirming (emerald spinner) -> confirmed / failed
/// 2. Pulse glow: Breathing emerald ambient glow when active
/// 3. Ripple wave: Expanding radial shockwave when tapped or confirmed
/// 4. Smooth scale & haptic-like press animation
/// 5. Lifecycle safe: Pauses animations when app is backgrounded
/// 6. Reduced motion aware: Respects system accessibility setting
class PulseGlowButton extends StatefulWidget {
  const PulseGlowButton({
    super.key,
    required this.isActive,
    required this.onTap,
    this.commandState = CommandState.idle,
    this.label,
    this.activeLabel,
    this.icon,
    this.activeIcon,
    this.activeColor = CockpitColors.emeraldStrong,
    this.inactiveColor,
    this.width,
    this.height = CockpitButtonTokens.height,
    this.borderRadius = CockpitRadius.medium,
    this.showGlow = true,
  });

  final bool isActive;
  final VoidCallback onTap;
  final CommandState commandState;
  final String? label;
  final String? activeLabel;
  final IconData? icon;
  final IconData? activeIcon;
  final Color activeColor;
  final Color? inactiveColor;
  final double? width;
  final double height;
  final double borderRadius;
  final bool showGlow;

  @override
  State<PulseGlowButton> createState() => _PulseGlowButtonState();
}

class _PulseGlowButtonState extends State<PulseGlowButton>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  late final AnimationController _rippleController;
  late final Animation<double> _rippleScaleAnimation;
  late final Animation<double> _rippleOpacityAnimation;

  late final AnimationController _pressController;
  late final Animation<double> _pressScaleAnimation;

  bool _isEffectiveActive(PulseGlowButton w) =>
      w.commandState == CommandState.confirmed ||
      (w.commandState == CommandState.idle && w.isActive);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Pulse breathing glow
    _pulseController = AnimationController(
      vsync: this,
      duration: CockpitMotion.glowPulse,
    );
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOutSine,
    );

    if (_isEffectiveActive(widget) && widget.showGlow) {
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isEffectiveActive(widget) && widget.showGlow) {
        _pulseController.repeat(reverse: true);
      }
    }
  }

  @override
  void didUpdateWidget(PulseGlowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isNowActive = _isEffectiveActive(widget);
    final wasActive = _isEffectiveActive(oldWidget);

    if (isNowActive != wasActive) {
      if (isNowActive) {
        if (widget.showGlow) {
          _pulseController.repeat(reverse: true);
        }
        _rippleController.forward(from: 0.0);
      } else {
        _pulseController.stop();
        _pulseController.reset();
        _rippleController.forward(from: 0.0);
      }
    } else if (widget.commandState != oldWidget.commandState) {
      if (widget.commandState == CommandState.confirmed) {
        _rippleController.forward(from: 0.0);
        if (widget.showGlow) {
          _pulseController.repeat(reverse: true);
        }
      } else if (widget.commandState == CommandState.failed) {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _rippleController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.commandState == CommandState.sending ||
        widget.commandState == CommandState.confirming) {
      return; // Disabled while in flight
    }
    _pressController.forward().then((_) => _pressController.reverse());
    _rippleController.forward(from: 0.0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.cockpit;
    final motionEnabled = CockpitMotion.enabled(context);

    final isSending = widget.commandState == CommandState.sending;
    final isConfirming = widget.commandState == CommandState.confirming;
    final isFailed = widget.commandState == CommandState.failed;
    final isBusy = isSending || isConfirming;
    final active = _isEffectiveActive(widget);

    String? effectiveLabel;
    if (isSending) {
      effectiveLabel = 'Đang gửi lệnh…';
    } else if (isConfirming) {
      effectiveLabel = 'Đang xác nhận…';
    } else if (isFailed) {
      effectiveLabel = 'Thất bại - Chạm để thử lại';
    } else if (active) {
      effectiveLabel = widget.activeLabel ?? widget.label;
    } else {
      effectiveLabel = widget.label;
    }

    final effectiveIcon = active
        ? (widget.activeIcon ?? widget.icon)
        : widget.icon;

    final baseInactiveColor = widget.inactiveColor ?? colors.surfaceSoft;

    Color buttonColor;
    Color borderColor;
    Color contentColor;

    if (isFailed) {
      buttonColor = colors.danger.withValues(alpha: 0.18);
      borderColor = colors.danger;
      contentColor = colors.danger;
    } else if (isSending) {
      buttonColor = colors.amber.withValues(alpha: 0.15);
      borderColor = colors.amber;
      contentColor = colors.amber;
    } else if (isConfirming) {
      buttonColor = widget.activeColor.withValues(alpha: 0.18);
      borderColor = widget.activeColor;
      contentColor = widget.activeColor;
    } else if (active) {
      buttonColor = widget.activeColor;
      borderColor = widget.activeColor.withValues(alpha: 0.85);
      contentColor = Colors.black;
    } else {
      buttonColor = baseInactiveColor;
      borderColor = colors.borderStrong;
      contentColor = colors.text;
    }

    return Semantics(
      button: true,
      enabled: !isBusy,
      toggled: active,
      label: effectiveLabel ?? 'Nút điều khiển',
      child: GestureDetector(
        onTap: isBusy ? null : _handleTap,
        child: ScaleTransition(
          scale: motionEnabled ? _pressScaleAnimation : const AlwaysStoppedAnimation(1.0),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Ripple shockwave ring on state change
              if (motionEnabled)
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
                          borderRadius:
                              BorderRadius.circular(widget.borderRadius + 4),
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
                  final glowFactor = active && widget.showGlow && motionEnabled
                      ? _pulseAnimation.value
                      : 0.0;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: widget.width,
                    height: widget.height,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: buttonColor,
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                      border: Border.all(
                        color: borderColor,
                        width: 1.2,
                      ),
                      boxShadow: active && motionEnabled
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
                                color: Colors.black.withValues(alpha: 0.15),
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
                    if (isBusy) ...[
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(contentColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ] else if (isFailed) ...[
                      Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: contentColor,
                      ),
                      const SizedBox(width: 8),
                    ] else if (effectiveIcon != null) ...[
                      Icon(
                        effectiveIcon,
                        size: 20,
                        color: active ? Colors.black : colors.muted,
                      ),
                      if (effectiveLabel != null) const SizedBox(width: 8),
                    ],
                    if (effectiveLabel != null)
                      Text(
                        effectiveLabel,
                        style: CockpitTypography.heading(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: contentColor,
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
