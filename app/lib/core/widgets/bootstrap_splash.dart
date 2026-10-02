import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/cockpit_design_system.dart';

/// Màn hình Splash khởi động phong cách Điện ảnh Công nghệ (Cinematic EV Awakening).
///
/// Hoạt cảnh mô phỏng phim ngắn 3 hồi:
/// 1. Tụ hội năng lượng lượng tử từ không gian sâu thẳm.
/// 2. Bùng nổ công nghệ: Tia sét điện tử kích hoạt logo VinFast cánh chim & thanh pin năng lượng.
/// 3. Sóng radar Cockpit quét mở lối và hiệu ứng phóng to (Seamless Zoom Transition) hòa nhập vào Login.
class BootstrapSplash extends StatefulWidget {
  const BootstrapSplash({super.key, required this.message, this.onFinished});

  final String message;
  final VoidCallback? onFinished;

  @override
  State<BootstrapSplash> createState() => _BootstrapSplashState();
}

class _BootstrapSplashState extends State<BootstrapSplash>
    with TickerProviderStateMixin {
  // Master timeline cho phim ngắn (2800ms)
  late final AnimationController _timelineController;
  // Ambient continuous breathing & grid movement
  late final AnimationController _ambientController;

  // Keyframe animations theo timeline 3 hồi:
  // Hồi 1 (0.0 -> 0.32): Khởi sinh & Tụ hội hạt năng lượng
  late final Animation<double> _particleConvergence;
  late final Animation<double> _coreSingularity;

  // Hồi 2 (0.30 -> 0.75): Đánh thức Logo & Tia sét V-Wing
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _lightningArcs;
  late final Animation<double> _sheenProgress;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _hudExpand;

  // Hồi 3 (0.75 -> 1.0): Nạp đầy & Phóng to chuyển cảnh vào Login
  late final Animation<double> _zoomWarp;
  late final Animation<double> _warpFade;

  // Các hạt lượng tử ngẫu nhiên
  final List<_QuantumParticle> _particles = [];
  final math.Random _random = math.Random(42);

  bool _finishedCalled = false;

  @override
  void initState() {
    super.initState();

    // Sinh 28 hạt lượng tử hội tụ
    for (int i = 0; i < 28; i++) {
      final angle = (i / 28) * 2 * math.pi + (_random.nextDouble() * 0.3);
      final radius = 130.0 + _random.nextDouble() * 140.0;
      final speed = 0.8 + _random.nextDouble() * 0.5;
      final size = 2.0 + _random.nextDouble() * 2.8;
      final isCyan = i % 2 == 0;
      _particles.add(
        _QuantumParticle(
          initialAngle: angle,
          initialRadius: radius,
          speed: speed,
          size: size,
          color: isCyan ? const Color(0xFF00F5D4) : CockpitColors.emerald,
        ),
      );
    }

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    _timelineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    // 1. Particle convergence
    _particleConvergence = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _timelineController,
        curve: const Interval(0.0, 0.40, curve: Curves.easeInCubic),
      ),
    );

    // Singularity glow
    _coreSingularity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _timelineController,
        curve: const Interval(0.05, 0.35, curve: Curves.easeOutQuad),
      ),
    );

    // 2. Logo entrance & lightning
    _logoScale = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(
        parent: _timelineController,
        curve: const Interval(0.28, 0.62, curve: Curves.easeOutBack),
      ),
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _timelineController,
        curve: const Interval(0.25, 0.48, curve: Curves.easeOut),
      ),
    );

    _lightningArcs = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _timelineController,
        curve: const Interval(0.35, 0.70, curve: Curves.easeInOutSine),
      ),
    );

    _sheenProgress = Tween<double>(begin: -0.4, end: 1.4).animate(
      CurvedAnimation(
        parent: _timelineController,
        curve: const Interval(0.48, 0.78, curve: Curves.easeInOutCubic),
      ),
    );

    _hudExpand = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _timelineController,
        curve: const Interval(0.32, 0.72, curve: Curves.easeOutCubic),
      ),
    );

    // Title & Tagline
    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _timelineController,
        curve: const Interval(0.42, 0.75, curve: Curves.easeOut),
      ),
    );

    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.20), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _timelineController,
            curve: const Interval(0.42, 0.75, curve: Curves.easeOutCubic),
          ),
        );

    // 3. Zoom warp transition to login
    _zoomWarp = Tween<double>(begin: 1.0, end: 1.45).animate(
      CurvedAnimation(
        parent: _timelineController,
        curve: const Interval(0.82, 1.0, curve: Curves.easeInCubic),
      ),
    );

    _warpFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _timelineController,
        curve: const Interval(0.88, 1.0, curve: Curves.easeIn),
      ),
    );

    _timelineController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _triggerFinish();
      }
    });

    _timelineController.forward();
  }

  void _triggerFinish() {
    if (_finishedCalled) return;
    _finishedCalled = true;
    if (mounted && widget.onFinished != null) {
      widget.onFinished!();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      if (!_timelineController.isCompleted) _timelineController.value = 1.0;
      if (_ambientController.isAnimating) _ambientController.stop();
    }
  }

  @override
  void dispose() {
    _timelineController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      // Match the Android launch theme so the hand-off never flashes white.
      backgroundColor: isDark ? const Color(0xFF0A0C10) : scheme.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Phông nền Cockpit & Lưới không gian 3D Perspective Cyber Grid
          if (!reducedMotion && isDark)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _ambientController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _CockpitGridPainter(
                      progress: _ambientController.value,
                    ),
                  );
                },
              ),
            ),

          // 2. Hào quang năng lượng trung tâm đa tầng (Ambient Aura Nebulae)
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _timelineController,
                _ambientController,
              ]),
              builder: (context, child) {
                final pulse = reducedMotion
                    ? 1.0
                    : 0.94 +
                          0.12 *
                              math.sin(_ambientController.value * 2 * math.pi);
                final coreAlpha = reducedMotion ? 0.35 : _coreSingularity.value;
                return Transform.scale(
                  scale: pulse,
                  child: Container(
                    width: 380,
                    height: 380,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF00F5D4).withValues(
                            alpha: (coreAlpha * 0.30).clamp(0.0, 1.0),
                          ),
                          CockpitColors.emerald.withValues(
                            alpha: (coreAlpha * 0.18).clamp(0.0, 1.0),
                          ),
                          const Color(0xFF0A192F).withValues(
                            alpha: (coreAlpha * 0.08).clamp(0.0, 1.0),
                          ),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.38, 0.68, 1.0],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 3. Sóng Radar Sonar & Vòng tia quét HUD
          if (!reducedMotion && isDark)
            Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _timelineController,
                  _ambientController,
                ]),
                builder: (context, _) {
                  return CustomPaint(
                    size: const Size(320, 320),
                    painter: _HudRadarPainter(
                      expandProgress: _hudExpand.value,
                      sweepProgress: _ambientController.value,
                      lightningProgress: _lightningArcs.value,
                    ),
                  );
                },
              ),
            ),

          // 4. Bão hạt lượng tử tụ hội (Quantum Particle Convergence)
          if (!reducedMotion && isDark)
            Center(
              child: AnimatedBuilder(
                animation: _timelineController,
                builder: (context, _) {
                  return CustomPaint(
                    size: const Size(340, 340),
                    painter: _QuantumParticlesPainter(
                      particles: _particles,
                      convergence: _particleConvergence.value,
                    ),
                  );
                },
              ),
            ),

          // 5. Nội dung trung tâm: Logo VinFast V-Wing + Tiêu đề + Pin nạp
          SafeArea(
            child: AnimatedBuilder(
              animation: _timelineController,
              builder: (context, child) {
                final scale = reducedMotion
                    ? 1.0
                    : (_logoScale.value * _zoomWarp.value);
                final opacity = reducedMotion ? 1.0 : _warpFade.value;

                return Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    child: Center(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 20,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo Badge với Electric Sheen Sweep
                            _buildLogoWithSheen(reducedMotion),

                            const SizedBox(height: 28),

                            // Tên thương hiệu & Tagline
                            _buildTitleAndTagline(
                              theme,
                              scheme,
                              reducedMotion,
                              isDark,
                            ),

                            const SizedBox(height: 28),

                            // Trạng thái thông điệp hệ thống
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: Text(
                                widget.message,
                                key: ValueKey(widget.message),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurfaceVariant,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            // EV Energy Progress Bar (Bắt buộc giữ cho test)
                            // No fabricated percentage: boot progress is
                            // represented by the real status message above.
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoWithSheen(bool reducedMotion) {
    return AnimatedBuilder(
      animation: Listenable.merge([_timelineController, _ambientController]),
      builder: (context, child) {
        final fade = reducedMotion ? 1.0 : _logoFade.value;
        final sheenVal = _sheenProgress.value;

        return Opacity(
          opacity: fade,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer Glowing Ring Halo
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF00F5D4).withValues(alpha: 0.35),
                      CockpitColors.emerald.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                    stops: const [0.4, 0.75, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F5D4).withValues(alpha: 0.30),
                      blurRadius: 36,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),

              // Logo Image Asset
              Container(
                width: 108,
                height: 108,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/icons/app_icon.png',
                        fit: BoxFit.contain,
                      ),
                      // Metallic Light Sheen Sweep across the logo
                      if (!reducedMotion && sheenVal > -0.3 && sheenVal < 1.3)
                        FractionallySizedBox(
                          alignment: Alignment((sheenVal * 2.0) - 1.0, 0.0),
                          widthFactor: 0.45,
                          child: Transform.rotate(
                            angle: math.pi / 4,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Colors.white.withValues(alpha: 0.55),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
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

  Widget _buildTitleAndTagline(
    ThemeData theme,
    ColorScheme scheme,
    bool reducedMotion,
    bool isDark,
  ) {
    return AnimatedBuilder(
      animation: _timelineController,
      builder: (context, child) {
        final fade = reducedMotion ? 1.0 : _titleFade.value;
        return Opacity(
          opacity: fade,
          child: SlideTransition(
            position: reducedMotion
                ? const AlwaysStoppedAnimation(Offset.zero)
                : _titleSlide,
            child: child,
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tiêu đề thương hiệu
          Text(
            'VinFast Battery',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
              letterSpacing: 2.0,
              height: 1.15,
              shadows: [
                Shadow(
                  color: const Color(0xFF00F5D4).withValues(alpha: 0.65),
                  blurRadius: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Cyber Tagline Capsule
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0D1B2A).withValues(alpha: 0.8)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.45),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00F5D4).withValues(alpha: 0.2),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Electric Pulsing Dot
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00F5D4),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF00F5D4),
                        blurRadius: 8,
                        spreadRadius: 1.5,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'QUẢN LÝ PIN VÀ SẠC XE ĐIỆN',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF00F5D4),
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CUSTOM PAINTERS: Phim ngắn điện ảnh công nghệ
// ============================================================================

/// Lưới không gian 3D Perspective Cockpit Grid
class _CockpitGridPainter extends CustomPainter {
  final double progress;
  _CockpitGridPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00F5D4).withValues(alpha: 0.05)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final centerX = size.width / 2;
    final centerY = size.height * 0.48;

    // Vẽ các đường phối cảnh tỏa ra từ tâm
    for (int i = -6; i <= 6; i++) {
      final targetX = centerX + (i * size.width * 0.16);
      canvas.drawLine(
        Offset(centerX, centerY),
        Offset(targetX, size.height),
        paint,
      );
    }

    // Các đường lưới ngang chuyển động tiến về phía trước
    final offset = (progress * 40.0) % 40.0;
    for (double y = centerY; y < size.height; y += 40.0) {
      final currentY = y + offset;
      if (currentY > size.height) continue;
      final factor = (currentY - centerY) / (size.height - centerY);
      final alpha = (factor * 0.08).clamp(0.0, 0.15);
      final horizontalPaint = Paint()
        ..color = const Color(0xFF00F5D4).withValues(alpha: alpha)
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(0, currentY),
        Offset(size.width, currentY),
        horizontalPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CockpitGridPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Sóng Radar & Vòng hiển thị HUD telemetry xung quanh logo
class _HudRadarPainter extends CustomPainter {
  final double expandProgress;
  final double sweepProgress;
  final double lightningProgress;

  _HudRadarPainter({
    required this.expandProgress,
    required this.sweepProgress,
    required this.lightningProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = 88.0 * expandProgress;

    // Vòng cung HUD telemetry nét đứt
    final hudPaint = Paint()
      ..color = const Color(0xFF00F5D4).withValues(alpha: 0.28)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, baseRadius, hudPaint);

    // 4 Vạch góc nhắm mục tiêu (Corner target brackets)
    final bracketPaint = Paint()
      ..color = const Color(0xFF00F5D4).withValues(alpha: 0.55)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final bracketRadius = baseRadius + 14.0;
    for (int i = 0; i < 4; i++) {
      final startAngle = (i * math.pi / 2) + 0.18;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: bracketRadius),
        startAngle,
        math.pi / 4,
        false,
        bracketPaint,
      );
    }

    // Sóng Radar quét 360 độ
    final sweepAngle = sweepProgress * 2 * math.pi;
    final sweepPaint = Paint()
      ..shader = ui.Gradient.sweep(
        center,
        [Colors.transparent, const Color(0xFF00F5D4).withValues(alpha: 0.18)],
        [0.75, 1.0],
        TileMode.clamp,
        sweepAngle - 0.5,
        sweepAngle,
      );
    canvas.drawCircle(center, bracketRadius + 8.0, sweepPaint);

    // Tia sét hồ quang điện tử nhỏ (Electric arcs)
    if (lightningProgress > 0.1 && lightningProgress < 0.95) {
      final arcPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;

      final rand = math.Random((lightningProgress * 100).toInt());
      for (int k = 0; k < 3; k++) {
        final a1 = rand.nextDouble() * 2 * math.pi;
        final r1 = baseRadius - 5 + rand.nextDouble() * 12;
        final p1 = center + Offset(math.cos(a1) * r1, math.sin(a1) * r1);
        final p2 =
            p1 + Offset(rand.nextDouble() * 16 - 8, rand.nextDouble() * 16 - 8);
        canvas.drawLine(p1, p2, arcPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HudRadarPainter oldDelegate) =>
      oldDelegate.expandProgress != expandProgress ||
      oldDelegate.sweepProgress != sweepProgress ||
      oldDelegate.lightningProgress != lightningProgress;
}

/// Mô hình hạt lượng tử hội tụ về tâm
class _QuantumParticle {
  final double initialAngle;
  final double initialRadius;
  final double speed;
  final double size;
  final Color color;

  _QuantumParticle({
    required this.initialAngle,
    required this.initialRadius,
    required this.speed,
    required this.size,
    required this.color,
  });
}

class _QuantumParticlesPainter extends CustomPainter {
  final List<_QuantumParticle> particles;
  final double convergence;

  _QuantumParticlesPainter({
    required this.particles,
    required this.convergence,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (convergence <= 0.01) return;

    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final currentRadius = p.initialRadius * convergence;
      final currentAngle =
          p.initialAngle + ((1.0 - convergence) * 2.2 * p.speed);
      final offset =
          center +
          Offset(
            math.cos(currentAngle) * currentRadius,
            math.sin(currentAngle) * currentRadius,
          );

      paint.color = p.color.withValues(
        alpha: (convergence * 0.75).clamp(0.0, 1.0),
      );
      canvas.drawCircle(offset, p.size * convergence, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _QuantumParticlesPainter oldDelegate) =>
      oldDelegate.convergence != convergence;
}
