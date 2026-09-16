import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/cockpit_design_system.dart';

/// Các trạng thái biểu cảm (mood) của mascot BatteryBot
enum BatteryBotMood {
  idle,
  greeting,
  happy,
  thinking,
  charging,
  listening,
}

/// Kích thước chuẩn cho mascot BatteryBot
enum BatteryBotSize {
  avatar(width: 40, height: 40),
  sm(width: 48, height: 60),
  md(width: 80, height: 100),
  lg(width: 120, height: 150),
  hero(width: 160, height: 200);

  final double width;
  final double height;
  const BatteryBotSize({required this.width, required this.height});
}

/// Chế độ hiển thị mascot: toàn thân (full) hoặc avatar thu nhỏ (avatar)
enum BatteryBotDisplayMode {
  full,
  avatar,
}

/// Mascot 2D thông minh - BatteryBot
/// Được vẽ 100% vector mượt mà bằng CustomPainter theo phong cách Tech-Cute.
/// Hỗ trợ nhiều biểu cảm anime, hiệu ứng nạp năng lượng, bóng bay lời thoại glassmorphic.
class BatteryBotMascot extends StatefulWidget {
  final BatteryBotMood mood;
  final BatteryBotSize size;
  final BatteryBotDisplayMode displayMode;
  final double? customWidth;
  final double? customHeight;
  final bool showSpeechBubble;
  final String? speechText;
  final BubblePosition bubblePosition;
  final VoidCallback? onTap;
  final bool enableFloating;

  const BatteryBotMascot({
    super.key,
    this.mood = BatteryBotMood.idle,
    this.size = BatteryBotSize.md,
    this.displayMode = BatteryBotDisplayMode.full,
    this.customWidth,
    this.customHeight,
    this.showSpeechBubble = false,
    this.speechText,
    this.bubblePosition = BubblePosition.top,
    this.onTap,
    this.enableFloating = true,
  });

  @override
  State<BatteryBotMascot> createState() => _BatteryBotMascotState();
}

enum BubblePosition { top, right, bottom }

class _BatteryBotMascotState extends State<BatteryBotMascot>
    with TickerProviderStateMixin {
  late final AnimationController _floatCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _blinkCtrl;
  late final AnimationController _tapCtrl;

  final List<_SparkleParticle> _particles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();

    // Dao động lơ lửng bồng bềnh
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    // Xung nhịp năng lượng pin & antenna
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    // Chớp mắt ngẫu nhiên tự nhiên
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    // Hiệu ứng nảy và bung hạt khi chạm (Tap interaction)
    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _pulseCtrl.dispose();
    _blinkCtrl.dispose();
    _tapCtrl.dispose();
    super.dispose();
  }

  void _triggerTap() {
    if (widget.onTap != null) widget.onTap!();
    _tapCtrl.forward(from: 0.0);

    // Tạo các hạt sao năng lượng bung ra
    _particles.clear();
    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * 2 * math.pi + (_random.nextDouble() * 0.4);
      final dist = 25.0 + _random.nextDouble() * 25.0;
      _particles.add(
        _SparkleParticle(
          dx: math.cos(angle) * dist,
          dy: math.sin(angle) * dist,
          size: 3.0 + _random.nextDouble() * 3.5,
          color: i % 2 == 0
              ? CockpitColors.emerald
              : CockpitColors.emeraldGlow,
        ),
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final motionEnabled = CockpitMotion.enabled(context);
    final isAvatar = widget.displayMode == BatteryBotDisplayMode.avatar ||
        widget.size == BatteryBotSize.avatar;

    if (isAvatar) {
      final avatarSize = widget.customWidth ?? widget.size.width;
      Widget avatarGraphic = AnimatedBuilder(
        animation: Listenable.merge([_floatCtrl, _pulseCtrl, _blinkCtrl, _tapCtrl]),
        builder: (context, _) {
          final floatVal = (motionEnabled && widget.enableFloating)
              ? math.sin(_floatCtrl.value * math.pi) * 3.0
              : 0.0;
          final pulseVal = motionEnabled ? _pulseCtrl.value : 0.5;

          double eyeOpenRatio = 1.0;
          final blinkProgress = _blinkCtrl.value;
          if (blinkProgress > 0.88 && blinkProgress < 0.96) {
            final p = (blinkProgress - 0.88) / 0.08;
            eyeOpenRatio = (p < 0.5) ? (1.0 - p * 2) : ((p - 0.5) * 2);
          }

          double tapScale = 1.0;
          if (_tapCtrl.isAnimating) {
            final t = _tapCtrl.value;
            tapScale = 1.0 + (math.sin(t * math.pi) * 0.14);
          }

          return Transform.translate(
            offset: Offset(0, -floatVal),
            child: Transform.scale(
              scale: tapScale,
              child: CustomPaint(
                size: Size(avatarSize, avatarSize),
                painter: _BatteryBotAvatarPainter(
                  mood: widget.mood,
                  pulse: pulseVal,
                  eyeOpen: eyeOpenRatio,
                ),
              ),
            ),
          );
        },
      );

      if (widget.onTap != null) {
        avatarGraphic = GestureDetector(
          onTap: _triggerTap,
          behavior: HitTestBehavior.opaque,
          child: avatarGraphic,
        );
      }
      return avatarGraphic;
    }

    final width = widget.customWidth ?? widget.size.width;
    final height = widget.customHeight ?? widget.size.height;

    Widget botGraphic = AnimatedBuilder(
      animation: Listenable.merge([_floatCtrl, _pulseCtrl, _blinkCtrl, _tapCtrl]),
      builder: (context, _) {
        final floatVal = (motionEnabled && widget.enableFloating)
            ? math.sin(_floatCtrl.value * math.pi) * 6.0
            : 0.0;
        final pulseVal = motionEnabled ? _pulseCtrl.value : 0.5;

        // Tính chu kỳ chớp mắt (nhắm mắt nhanh ở 90-95% chu kỳ)
        double eyeOpenRatio = 1.0;
        final blinkProgress = _blinkCtrl.value;
        if (blinkProgress > 0.88 && blinkProgress < 0.96) {
          final p = (blinkProgress - 0.88) / 0.08;
          eyeOpenRatio = (p < 0.5) ? (1.0 - p * 2) : ((p - 0.5) * 2);
        }

        // Tap scale & bounce
        double tapScale = 1.0;
        if (_tapCtrl.isAnimating) {
          final t = _tapCtrl.value;
          // Hiệu ứng squash & stretch
          tapScale = 1.0 + (math.sin(t * math.pi) * 0.12);
        }

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Bóng đổ mềm mại dưới mặt sàn phản chiếu
            Positioned(
              bottom: 2,
              child: Opacity(
                opacity: (0.4 - (floatVal / 30.0)).clamp(0.15, 0.6),
                child: Container(
                  width: width * (0.65 - (floatVal / 50.0)),
                  height: 7,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: CockpitColors.emerald.withValues(alpha: 0.35),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Thân Robot
            Transform.translate(
              offset: Offset(0, -floatVal),
              child: Transform.scale(
                scale: tapScale,
                child: CustomPaint(
                  size: Size(width, height),
                  painter: _BatteryBotPainter(
                    mood: widget.mood,
                    pulse: pulseVal,
                    eyeOpen: eyeOpenRatio,
                    particles: _tapCtrl.isAnimating ? _particles : const [],
                    particleProgress: _tapCtrl.value,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (widget.onTap != null) {
      botGraphic = GestureDetector(
        onTap: _triggerTap,
        behavior: HitTestBehavior.opaque,
        child: botGraphic,
      );
    }

    if (!widget.showSpeechBubble || widget.speechText == null) {
      return botGraphic;
    }

    // Wrap với Speech Bubble phong cách Glassmorphism
    return _buildWithBubble(botGraphic, width);
  }

  Widget _buildWithBubble(Widget botGraphic, double width) {
    final bubble = _SpeechBubbleWidget(
      text: widget.speechText!,
      position: widget.bubblePosition,
      maxWidth: width * 2.4,
    );

    switch (widget.bubblePosition) {
      case BubblePosition.top:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            bubble,
            const SizedBox(height: 8),
            botGraphic,
          ],
        );
      case BubblePosition.bottom:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            botGraphic,
            const SizedBox(height: 8),
            bubble,
          ],
        );
      case BubblePosition.right:
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            botGraphic,
            const SizedBox(width: 12),
            Flexible(child: bubble),
          ],
        );
    }
  }
}

class _SparkleParticle {
  final double dx;
  final double dy;
  final double size;
  final Color color;

  _SparkleParticle({
    required this.dx,
    required this.dy,
    required this.size,
    required this.color,
  });
}

/// CustomPainter vẽ toàn bộ nhân vật Robot Pin BatteryBot
class _BatteryBotPainter extends CustomPainter {
  final BatteryBotMood mood;
  final double pulse;
  final double eyeOpen;
  final List<_SparkleParticle> particles;
  final double particleProgress;

  _BatteryBotPainter({
    required this.mood,
    required this.pulse,
    required this.eyeOpen,
    required this.particles,
    required this.particleProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Tỉ lệ hình học chính
    final centerX = w / 2;
    final bodyW = w * 0.72;
    final bodyH = h * 0.72;
    final bodyTop = h * 0.20;
    final bodyRect = Rect.fromCenter(
      center: Offset(centerX, bodyTop + bodyH / 2),
      width: bodyW,
      height: bodyH,
    );
    final bodyRadius = Radius.circular(bodyW * 0.28);

    _drawAntennas(canvas, size, centerX, bodyTop, bodyW);
    _drawLandingPads(canvas, size, centerX, bodyRect.bottom, bodyW);
    _drawBody(canvas, bodyRect, bodyRadius);
    _drawVisorScreen(canvas, bodyRect, bodyW);
    _drawEyes(canvas, bodyRect, bodyW);
    _drawBatteryGauges(canvas, bodyRect, bodyW);
    _drawChestEmblem(canvas, bodyRect, bodyW);
    _drawTapParticles(canvas, centerX, bodyRect.center.dy);
  }

  /// 1. Vẽ hai cọc ăng-ten năng lượng phát sáng
  void _drawAntennas(
    Canvas canvas,
    Size size,
    double centerX,
    double bodyTop,
    double bodyW,
  ) {
    final antennaSpacing = bodyW * 0.32;
    final leftX = centerX - antennaSpacing;
    final rightX = centerX + antennaSpacing;
    final rodTop = bodyTop - (size.height * 0.12);

    final rodPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = (bodyW * 0.06).clamp(2.0, 4.5)
      ..strokeCap = StrokeCap.round;

    // Que ăng-ten trái & phải
    canvas.drawLine(Offset(leftX, bodyTop + 2), Offset(leftX, rodTop), rodPaint);
    canvas.drawLine(Offset(rightX, bodyTop + 2), Offset(rightX, rodTop), rodPaint);

    // Đỉnh cực pin ở giữa (Cap terminal)
    final capRect = Rect.fromCenter(
      center: Offset(centerX, bodyTop - 3),
      width: bodyW * 0.28,
      height: bodyW * 0.10,
    );
    final capPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF64748B), Color(0xFF1E293B)],
      ).createShader(capRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(capRect, Radius.circular(capRect.height / 2)),
      capPaint,
    );

    // Viên ngọc năng lượng ở 2 đầu ăng-ten
    final glowRadius = (bodyW * 0.08) * (1.0 + pulse * 0.22);
    final glowColor = (mood == BatteryBotMood.charging)
        ? CockpitColors.emeraldGlow
        : CockpitColors.emerald;

    for (final x in [leftX, rightX]) {
      // Vầng hào quang
      final glowPaint = Paint()
        ..color = glowColor.withValues(alpha: 0.35 + pulse * 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius * 1.4);
      canvas.drawCircle(Offset(x, rodTop), glowRadius, glowPaint);

      // Viên bi năng lượng
      final orbPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white,
            glowColor,
            const Color(0xFF047857),
          ],
          stops: const [0.1, 0.6, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(x, rodTop), radius: glowRadius));
      canvas.drawCircle(Offset(x, rodTop), glowRadius * 0.75, orbPaint);
    }
  }

  /// 2. Vẽ đế đáp nam châm / bánh đệm
  void _drawLandingPads(
    Canvas canvas,
    Size size,
    double centerX,
    double bodyBottom,
    double bodyW,
  ) {
    final padW = bodyW * 0.22;
    final padH = bodyW * 0.09;
    final spacing = bodyW * 0.26;

    for (final dir in [-1, 1]) {
      final padRect = Rect.fromCenter(
        center: Offset(centerX + dir * spacing, bodyBottom + padH * 0.4),
        width: padW,
        height: padH,
      );
      final padPaint = Paint()..color = const Color(0xFF1E293B);
      canvas.drawRRect(
        RRect.fromRectAndRadius(padRect, Radius.circular(padH / 2)),
        padPaint,
      );
      // Ánh sáng phản chiếu của chân
      final glowStrip = Paint()
        ..color = CockpitColors.emerald.withValues(alpha: 0.5)
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(padRect.left + 3, padRect.bottom - 1),
        Offset(padRect.right - 3, padRect.bottom - 1),
        glowStrip,
      );
    }
  }

  /// 3. Vẽ thân robot - Vỏ Titanium Emerald siêu mượt
  void _drawBody(Canvas canvas, Rect bodyRect, Radius bodyRadius) {
    // Viền phát sáng ngọc ngoài thân
    final outerGlow = Paint()
      ..color = CockpitColors.emerald.withValues(alpha: 0.22 + pulse * 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, bodyRadius), outerGlow);

    // Khối thân chính với gradient công nghệ hiện đại
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF1E293B), // Titanium slate
          Color(0xFF0F172A), // Dark slate
          Color(0xFF064E3B), // Deep emerald shade
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(bodyRect);
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, bodyRadius), bodyPaint);

    // Viền kim loại mạ điện
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF34D399), // Emerald sáng trên đỉnh
          Color(0xFF10B981),
          Color(0xFF0F172A), // Tối dần xuống dưới
        ],
      ).createShader(bodyRect);
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, bodyRadius), borderPaint);

    // Vệt sáng lướt qua thân (Specular highlight)
    final highlightPath = Path()
      ..moveTo(bodyRect.left + bodyRect.width * 0.2, bodyRect.top + 3)
      ..lineTo(bodyRect.right - bodyRect.width * 0.2, bodyRect.top + 3);
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(highlightPath, highlightPaint);
  }

  /// 4. Màn hình visor hiển thị mắt (OLED Visor)
  void _drawVisorScreen(Canvas canvas, Rect bodyRect, double bodyW) {
    final visorRect = Rect.fromLTWH(
      bodyRect.left + bodyW * 0.08,
      bodyRect.top + bodyRect.height * 0.14,
      bodyW * 0.84,
      bodyRect.height * 0.46,
    );
    final visorRadius = Radius.circular(bodyW * 0.18);

    // Nền visor siêu đen sâu
    final visorPaint = Paint()..color = const Color(0xFF020617);
    canvas.drawRRect(RRect.fromRectAndRadius(visorRect, visorRadius), visorPaint);

    // Viền visor tinh xảo
    final visorBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = CockpitColors.emerald.withValues(alpha: 0.35);
    canvas.drawRRect(RRect.fromRectAndRadius(visorRect, visorRadius), visorBorder);
  }

  /// 5. Vẽ đôi mắt biểu cảm Anime Tech-Cute
  void _drawEyes(Canvas canvas, Rect bodyRect, double bodyW) {
    final visorCenterY = bodyRect.top + bodyRect.height * 0.36;
    final eyeSpacing = bodyW * 0.22;
    final centerX = bodyRect.center.dx;

    final leftEyeCenter = Offset(centerX - eyeSpacing, visorCenterY);
    final rightEyeCenter = Offset(centerX + eyeSpacing, visorCenterY);

    final eyeColor = (mood == BatteryBotMood.charging)
        ? const Color(0xFF38BDF8) // Sky cyan khi sạc
        : const Color(0xFF34D399); // Emerald rực rỡ thường

    switch (mood) {
      case BatteryBotMood.happy:
        _drawHappyEyes(canvas, leftEyeCenter, rightEyeCenter, bodyW, eyeColor);
        _drawBlush(canvas, leftEyeCenter, rightEyeCenter, bodyW);
        break;

      case BatteryBotMood.greeting:
        _drawSparkleEyes(canvas, leftEyeCenter, rightEyeCenter, bodyW, eyeColor);
        _drawBlush(canvas, leftEyeCenter, rightEyeCenter, bodyW);
        break;

      case BatteryBotMood.thinking:
        _drawThinkingEyes(canvas, leftEyeCenter, rightEyeCenter, bodyW, eyeColor);
        break;

      case BatteryBotMood.charging:
        _drawChargingEyes(canvas, leftEyeCenter, rightEyeCenter, bodyW, eyeColor);
        break;

      case BatteryBotMood.listening:
        _drawListeningEyes(canvas, leftEyeCenter, rightEyeCenter, bodyW, eyeColor);
        break;

      case BatteryBotMood.idle:
        _drawNormalEyes(canvas, leftEyeCenter, rightEyeCenter, bodyW, eyeColor);
        break;
    }
  }

  /// Mắt bình thường với chớp mắt tự nhiên
  void _drawNormalEyes(
    Canvas canvas,
    Offset left,
    Offset right,
    double bodyW,
    Color color,
  ) {
    final eyeRadiusX = bodyW * 0.10;
    final eyeRadiusY = (bodyW * 0.12) * eyeOpen.clamp(0.08, 1.0);

    for (final center in [left, right]) {
      final rect = Rect.fromCenter(
        center: center,
        width: eyeRadiusX * 2,
        height: eyeRadiusY * 2,
      );

      // Quầng sáng mắt
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawOval(rect, glowPaint);

      // Đồng tử chính
      final eyePaint = Paint()..color = color;
      canvas.drawOval(rect, eyePaint);

      // Đốm sáng phản chiếu anime (Sparkle glint) khi mắt mở
      if (eyeOpen > 0.4) {
        final glintPaint = Paint()..color = Colors.white;
        canvas.drawCircle(
          Offset(center.dx - eyeRadiusX * 0.3, center.dy - eyeRadiusY * 0.3),
          eyeRadiusX * 0.35,
          glintPaint,
        );
        canvas.drawCircle(
          Offset(center.dx + eyeRadiusX * 0.3, center.dy + eyeRadiusY * 0.2),
          eyeRadiusX * 0.18,
          glintPaint,
        );
      }
    }
  }

  /// Mắt cười hình cung vui sướng (^_^)
  void _drawHappyEyes(
    Canvas canvas,
    Offset left,
    Offset right,
    double bodyW,
    Color color,
  ) {
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (bodyW * 0.05).clamp(2.5, 4.5)
      ..strokeCap = StrokeCap.round;

    final arcRadius = bodyW * 0.09;

    for (final center in [left, right]) {
      final rect = Rect.fromCircle(center: center, radius: arcRadius);
      canvas.drawArc(rect, math.pi * 1.15, math.pi * 0.7, false, arcPaint);
    }
  }

  /// Mắt long lanh hình ngôi sao (✦_✦) chào mừng
  void _drawSparkleEyes(
    Canvas canvas,
    Offset left,
    Offset right,
    double bodyW,
    Color color,
  ) {
    for (final center in [left, right]) {
      // Vòng sáng tròn phía sau
      final haloPaint = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(center, bodyW * 0.11, haloPaint);

      // Vẽ hình sao 4 cánh lấp lánh
      final starPath = Path();
      final r = bodyW * 0.11;
      final inner = r * 0.3;

      for (int i = 0; i < 4; i++) {
        final a1 = (i * math.pi / 2);
        final a2 = a1 + (math.pi / 4);
        if (i == 0) {
          starPath.moveTo(center.dx + math.cos(a1) * r, center.dy + math.sin(a1) * r);
        } else {
          starPath.lineTo(center.dx + math.cos(a1) * r, center.dy + math.sin(a1) * r);
        }
        starPath.lineTo(center.dx + math.cos(a2) * inner, center.dy + math.sin(a2) * inner);
      }
      starPath.close();

      canvas.drawPath(starPath, Paint()..color = color);
      canvas.drawCircle(center, inner * 0.6, Paint()..color = Colors.white);
    }
  }

  /// Mắt liếc đang suy nghĩ (◑_◑)
  void _drawThinkingEyes(
    Canvas canvas,
    Offset left,
    Offset right,
    double bodyW,
    Color color,
  ) {
    final r = bodyW * 0.10;
    for (final center in [left, right]) {
      canvas.drawCircle(center, r, Paint()..color = color.withValues(alpha: 0.25));

      // Tròng mắt nhìn lên góc trên bên phải
      final pupilCenter = Offset(center.dx + r * 0.35, center.dy - r * 0.35);
      canvas.drawCircle(pupilCenter, r * 0.65, Paint()..color = color);
      canvas.drawCircle(
        Offset(pupilCenter.dx - 1, pupilCenter.dy - 1),
        r * 0.25,
        Paint()..color = Colors.white,
      );
    }
  }

  /// Mắt năng lượng sạc (>_<) hoặc tia chớp
  void _drawChargingEyes(
    Canvas canvas,
    Offset left,
    Offset right,
    double bodyW,
    Color color,
  ) {
    final boltPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final center in [left, right]) {
      final bW = bodyW * 0.12;
      final bH = bodyW * 0.16;
      final path = Path()
        ..moveTo(center.dx + bW * 0.2, center.dy - bH * 0.5)
        ..lineTo(center.dx - bW * 0.4, center.dy)
        ..lineTo(center.dx, center.dy)
        ..lineTo(center.dx - bW * 0.2, center.dy + bH * 0.5)
        ..lineTo(center.dx + bW * 0.4, center.dy)
        ..lineTo(center.dx, center.dy)
        ..close();
      canvas.drawPath(path, boltPaint);
    }
  }

  /// Mắt lắng nghe chăm chú
  void _drawListeningEyes(
    Canvas canvas,
    Offset left,
    Offset right,
    double bodyW,
    Color color,
  ) {
    _drawNormalEyes(canvas, left, right, bodyW, color);
    // Vẽ thêm gợn sóng radar nhỏ phía trên tai
    final ringPaint = Paint()
      ..color = color.withValues(alpha: (0.6 - pulse * 0.4).clamp(0.1, 0.6))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawArc(
      Rect.fromCircle(center: left, radius: bodyW * 0.16 + pulse * 4),
      -math.pi * 0.7,
      math.pi * 0.4,
      false,
      ringPaint,
    );
  }

  /// Má hồng dễ thương anime
  void _drawBlush(Canvas canvas, Offset left, Offset right, double bodyW) {
    final blushPaint = Paint()
      ..color = const Color(0xFFFB7185).withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final r = bodyW * 0.055;
    canvas.drawCircle(Offset(left.dx - bodyW * 0.04, left.dy + bodyW * 0.09), r, blushPaint);
    canvas.drawCircle(Offset(right.dx + bodyW * 0.04, right.dy + bodyW * 0.09), r, blushPaint);
  }

  /// 6. Các vạch LED dung lượng pin dưới ngực
  void _drawBatteryGauges(Canvas canvas, Rect bodyRect, double bodyW) {
    final gaugeY = bodyRect.top + bodyRect.height * 0.70;
    final gaugeW = bodyW * 0.58;
    final gaugeH = bodyW * 0.07;
    final startX = bodyRect.center.dx - gaugeW / 2;

    final numBars = 4;
    final barSpacing = 3.0;
    final singleBarW = (gaugeW - (numBars - 1) * barSpacing) / numBars;

    // Vạch chạy theo nhịp khi sạc
    final activeCount = (mood == BatteryBotMood.charging)
        ? ((pulse * 4).floor() % 4) + 1
        : 3;

    for (int i = 0; i < numBars; i++) {
      final x = startX + i * (singleBarW + barSpacing);
      final barRect = Rect.fromLTWH(x, gaugeY, singleBarW, gaugeH);
      final isActive = i < activeCount;

      final barColor = isActive
          ? (i == 0 && activeCount == 1
              ? const Color(0xFFF59E0B)
              : CockpitColors.emerald)
          : const Color(0xFF1E293B);

      final barPaint = Paint()..color = barColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, const Radius.circular(2)),
        barPaint,
      );

      if (isActive) {
        final glow = Paint()
          ..color = barColor.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(barRect, const Radius.circular(2)),
          glow,
        );
      }
    }
  }

  /// 7. Biểu tượng tia chớp VinFast tinh tế ở bụng
  void _drawChestEmblem(Canvas canvas, Rect bodyRect, double bodyW) {
    final emblemY = bodyRect.top + bodyRect.height * 0.84;
    final centerX = bodyRect.center.dx;
    final eSize = bodyW * 0.08;

    final emblemPaint = Paint()
      ..color = CockpitColors.emerald.withValues(alpha: 0.4 + pulse * 0.3)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(centerX - eSize * 0.4, emblemY - eSize * 0.3)
      ..lineTo(centerX, emblemY)
      ..lineTo(centerX + eSize * 0.4, emblemY - eSize * 0.3);

    canvas.drawPath(path, emblemPaint);
  }

  /// 8. Bung các hạt lấp lánh khi người dùng chạm vào mascot
  void _drawTapParticles(Canvas canvas, double cx, double cy) {
    if (particleProgress <= 0.0 || particleProgress >= 1.0) return;

    for (final p in particles) {
      final currentX = cx + p.dx * particleProgress;
      final currentY = cy + p.dy * particleProgress;
      final currentOpacity = (1.0 - particleProgress).clamp(0.0, 1.0);
      final currentSize = p.size * (1.0 - particleProgress * 0.5);

      final pPaint = Paint()
        ..color = p.color.withValues(alpha: currentOpacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawCircle(Offset(currentX, currentY), currentSize, pPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BatteryBotPainter oldDelegate) {
    return oldDelegate.mood != mood ||
        oldDelegate.pulse != pulse ||
        oldDelegate.eyeOpen != eyeOpen ||
        oldDelegate.particleProgress != particleProgress;
  }
}

/// Widget Bong bóng thoại Glassmorphic cho BatteryBot
class _SpeechBubbleWidget extends StatelessWidget {
  final String text;
  final BubblePosition position;
  final double maxWidth;

  const _SpeechBubbleWidget({
    required this.text,
    required this.position,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth.clamp(140.0, 320.0)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CockpitColors.emerald.withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: CockpitColors.emerald.withValues(alpha: 0.12),
            blurRadius: 16,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: CockpitColors.text,
          height: 1.35,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

/// CustomPainter vẽ avatar BatteryBot tròn gọn gàng và tinh tế
class _BatteryBotAvatarPainter extends CustomPainter {
  final BatteryBotMood mood;
  final double pulse;
  final double eyeOpen;

  _BatteryBotAvatarPainter({
    required this.mood,
    required this.pulse,
    required this.eyeOpen,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;

    // 1. Viền ngoài phát sáng ngọc nhẹ
    final glowPaint = Paint()
      ..color = CockpitColors.emerald.withValues(alpha: 0.25 + pulse * 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center, radius - 1, glowPaint);

    // 2. Nền khung avatar kim loại tối màu
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF1E293B),
          Color(0xFF0F172A),
          Color(0xFF064E3B),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius - 1.5, bgPaint);

    // 3. Viền neon công nghệ
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF34D399),
          Color(0xFF10B981),
          Color(0xFF047857),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius - 1.5, borderPaint);

    // 4. Màn hình Visor OLED
    final visorRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + 1),
      width: w * 0.76,
      height: h * 0.52,
    );
    final visorRadius = Radius.circular(visorRect.height * 0.45);
    final visorPaint = Paint()..color = const Color(0xFF020617);
    canvas.drawRRect(RRect.fromRectAndRadius(visorRect, visorRadius), visorPaint);

    final visorBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = CockpitColors.emerald.withValues(alpha: 0.35);
    canvas.drawRRect(RRect.fromRectAndRadius(visorRect, visorRadius), visorBorder);

    // 5. Đôi mắt anime dễ thương
    final eyeSpacing = w * 0.18;
    final eyeCenterY = visorRect.center.dy;
    final leftEye = Offset(center.dx - eyeSpacing, eyeCenterY);
    final rightEye = Offset(center.dx + eyeSpacing, eyeCenterY);

    final eyeColor = (mood == BatteryBotMood.charging)
        ? const Color(0xFF38BDF8)
        : const Color(0xFF34D399);

    final eyeRadiusX = w * 0.085;
    final eyeRadiusY = (h * 0.10) * eyeOpen.clamp(0.12, 1.0);

    if (mood == BatteryBotMood.happy) {
      final archPaint = Paint()
        ..color = eyeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      for (final pt in [leftEye, rightEye]) {
        final path = Path()
          ..moveTo(pt.dx - eyeRadiusX, pt.dy + 1)
          ..quadraticBezierTo(pt.dx, pt.dy - eyeRadiusY * 1.5, pt.dx + eyeRadiusX, pt.dy + 1);
        canvas.drawPath(path, archPaint);
      }
    } else {
      final eyePaint = Paint()..color = eyeColor;
      for (final pt in [leftEye, rightEye]) {
        canvas.drawOval(
          Rect.fromCenter(center: pt, width: eyeRadiusX * 2, height: eyeRadiusY * 2),
          eyePaint,
        );
        if (eyeOpen > 0.6) {
          final glintPaint = Paint()..color = Colors.white;
          canvas.drawCircle(
            Offset(pt.dx - eyeRadiusX * 0.3, pt.dy - eyeRadiusY * 0.3),
            eyeRadiusX * 0.35,
            glintPaint,
          );
        }
      }
    }

    // Má hồng biểu cảm khi vui vẻ hoặc chào
    if (mood == BatteryBotMood.happy || mood == BatteryBotMood.greeting) {
      final blushPaint = Paint()
        ..color = const Color(0xFFF43F5E).withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawCircle(Offset(leftEye.dx - 2, eyeCenterY + 5), 2.5, blushPaint);
      canvas.drawCircle(Offset(rightEye.dx + 2, eyeCenterY + 5), 2.5, blushPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BatteryBotAvatarPainter oldDelegate) {
    return oldDelegate.mood != mood ||
        oldDelegate.pulse != pulse ||
        oldDelegate.eyeOpen != eyeOpen;
  }
}

