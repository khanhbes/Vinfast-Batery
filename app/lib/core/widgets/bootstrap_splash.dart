import 'package:flutter/material.dart';
import '../theme/cockpit_design_system.dart';

/// Professional, smooth bootstrap splash screen with emerald pulse animation
/// and VinFast Battery branding.
class BootstrapSplash extends StatefulWidget {
  const BootstrapSplash({super.key, required this.message});
  final String message;

  @override
  State<BootstrapSplash> createState() => _BootstrapSplashState();
}

class _BootstrapSplashState extends State<BootstrapSplash>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _entranceController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();

    // Breathing glow aura
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    // Coordinated entrance animation
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _logoScale = Tween<double>(begin: 0.78, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );

    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.35, 0.85, curve: Curves.easeOut),
      ),
    );

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.20),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _entranceController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: CockpitColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Ambient emerald background glow
          Center(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    CockpitColors.emeraldStrong.withValues(alpha: 0.12),
                    CockpitColors.emerald.withValues(alpha: 0.04),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // Central content
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo with concentric breathing pulse
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        _entranceController,
                        _pulseController,
                      ]),
                      builder: (context, child) {
                        final pulseVal = reducedMotion
                            ? 0.5
                            : _pulseController.value;
                        return Opacity(
                          opacity: reducedMotion ? 1.0 : _logoFade.value,
                          child: Transform.scale(
                            scale: reducedMotion ? 1.0 : _logoScale.value,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Outer breathing ring
                                Container(
                                  width: 130 + (pulseVal * 16),
                                  height: 130 + (pulseVal * 16),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: CockpitColors.emeraldStrong.withValues(
                                        alpha: 0.10 + (pulseVal * 0.15),
                                      ),
                                      width: 1.5,
                                    ),
                                  ),
                                ),

                                // Inner glowing ring
                                Container(
                                  width: 104,
                                  height: 104,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: CockpitColors.surface,
                                    border: Border.all(
                                      color: CockpitColors.emeraldStrong.withValues(
                                        alpha: 0.4 + (pulseVal * 0.3),
                                      ),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: CockpitColors.emeraldStrong.withValues(
                                          alpha: 0.20 + (pulseVal * 0.25),
                                        ),
                                        blurRadius: 24,
                                        spreadRadius: 2 + (pulseVal * 6),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.electric_bolt_rounded,
                                      size: 52,
                                      color: CockpitColors.emeraldStrong,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 36),

                    // App Title & Tagline with smooth slide + fade
                    AnimatedBuilder(
                      animation: _entranceController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: reducedMotion ? 1.0 : _textFade.value,
                          child: SlideTransition(
                            position: reducedMotion
                                ? const AlwaysStoppedAnimation(Offset.zero)
                                : _textSlide,
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'VINFAST BATTERY',
                            textAlign: TextAlign.center,
                            style: CockpitTypography.heading(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: CockpitColors.text,
                              letterSpacing: 2.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Smart Battery Management',
                            textAlign: TextAlign.center,
                            style: CockpitTypography.body(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: CockpitColors.muted,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 48),

                    // Sleek glowing progress indicator
                    Container(
                      width: 140,
                      height: 4,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: CockpitColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: CockpitColors.emeraldStrong.withValues(
                              alpha: 0.35,
                            ),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          CockpitColors.emeraldStrong,
                        ),
                        minHeight: 4,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Status Message
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: CockpitTypography.label(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: CockpitColors.dim,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Version text
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Text(
              'v2.4.0 · Pro Connected Cockpit',
              textAlign: TextAlign.center,
              style: CockpitTypography.label(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: CockpitColors.dim.withValues(alpha: 0.6),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
