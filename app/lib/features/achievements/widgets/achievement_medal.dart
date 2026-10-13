import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../models/achievement.dart';

/// Minted 2D medal: coin-edged metallic rim in the rarity's metal, a sunken
/// face with an engraved ring, the icon struck in metal. Locked medals are
/// dark graphite with an emerald progress arc; secret ones show "?".
class AchievementMedal extends StatelessWidget {
  const AchievementMedal({
    super.key,
    required this.rarity,
    required this.icon,
    this.unlocked = true,
    this.progress = 0,
    this.secret = false,
    this.size = 72,
    this.shine = -1,
  });

  final AchievementRarity rarity;
  final IconData icon;
  final bool unlocked;
  final double progress;
  final bool secret;
  final double size;

  /// Sweep position −1..2 (outside 0..1 = no sweep).
  final double shine;

  @override
  Widget build(BuildContext context) {
    final metal = rarity.metal;
    final hidden = secret && !unlocked;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _MedalPainter(
              metal: metal,
              unlocked: unlocked,
              progress: progress,
              laurel:
                  unlocked &&
                  (rarity == AchievementRarity.platinum ||
                      rarity == AchievementRarity.emerald),
            ),
          ),
          // Struck icon: metal gradient when unlocked, faint engraving when not.
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (b) => LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: unlocked
                  ? [metal[0], metal[1], metal[2]]
                  : const [Color(0xFF5A5D63), Color(0xFF34363B)],
            ).createShader(b),
            child: hidden
                ? Text(
                    '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.34,
                      fontWeight: FontWeight.w300,
                    ),
                  )
                : Icon(icon, size: size * 0.34, color: Colors.white),
          ),
          if (unlocked && shine > -0.5 && shine < 1.5)
            ClipOval(
              child: SizedBox.square(
                dimension: size * 0.92,
                child: CustomPaint(painter: _ShinePainter(shine)),
              ),
            ),
          if (!unlocked)
            Positioned(
              right: size * 0.04,
              bottom: size * 0.04,
              child: Container(
                width: size * 0.26,
                height: size * 0.26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF17181B),
                  border: Border.all(color: LuxeColors.hairlineStrong),
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: size * 0.14,
                  color: LuxeColors.platinumMid,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MedalPainter extends CustomPainter {
  _MedalPainter({
    required this.metal,
    required this.unlocked,
    required this.progress,
    required this.laurel,
  });

  final List<Color> metal;
  final bool unlocked;
  final double progress;
  final bool laurel;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final r = s * 0.42;

    if (unlocked) {
      // Halo in the medal's own metal.
      canvas.drawCircle(
        c,
        r * 1.18,
        Paint()
          ..shader = ui.Gradient.radial(c, r * 1.18, [
            metal[1].withValues(alpha: 0.28),
            metal[1].withValues(alpha: 0),
          ]),
      );
    }
    // Drop shadow.
    canvas.drawCircle(
      c.translate(0, s * 0.03),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.05),
    );

    // Locked medals keep a faint tint of their metal, so the rarity is
    // readable before it is earned.
    Color dark(Color c, double k) => Color.lerp(c, const Color(0xFF1A1B1E), k)!;
    final rimColors = unlocked
        ? [metal[0], metal[1], metal[2], metal[1]]
        : [
            dark(metal[0], 0.72),
            dark(metal[1], 0.8),
            dark(metal[2], 0.85),
            dark(metal[1], 0.8),
          ];

    // Coin edge: notched outline.
    final edge = Path();
    const teeth = 36;
    for (var i = 0; i <= teeth * 2; i++) {
      final a = i / (teeth * 2) * 2 * math.pi;
      final rr = i.isEven ? r : r * 0.965;
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? edge.moveTo(p.dx, p.dy) : edge.lineTo(p.dx, p.dy);
    }
    edge.close();
    canvas.drawPath(
      edge,
      Paint()
        ..shader = ui.Gradient.sweep(
          c,
          rimColors,
          const [0.0, 0.35, 0.7, 1.0],
          TileMode.clamp,
          -math.pi * 0.75,
          math.pi * 1.25,
        ),
    );
    // Bevel ring.
    canvas.drawCircle(
      c,
      r * 0.86,
      Paint()
        ..shader = ui.Gradient.linear(
          c.translate(-r, -r),
          c.translate(r, r),
          unlocked
              ? [metal[2], metal[0]]
              : const [Color(0xFF16171A), Color(0xFF3A3C41)],
        ),
    );
    // Sunken face.
    canvas.drawCircle(
      c,
      r * 0.8,
      Paint()
        ..shader = ui.Gradient.radial(
          c.translate(-r * 0.25, -r * 0.3),
          r * 1.1,
          unlocked
              ? [
                  Color.lerp(metal[2], const Color(0xFF0B0C0E), 0.55)!,
                  Color.lerp(metal[2], const Color(0xFF050506), 0.85)!,
                ]
              : const [Color(0xFF1B1C1F), Color(0xFF0A0A0C)],
        ),
    );
    // Engraved inner ring.
    canvas.drawCircle(
      c,
      r * 0.68,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, s * 0.01)
        ..color = unlocked
            ? metal[0].withValues(alpha: 0.35)
            : const Color(0x1FFFFFFF),
    );
    // Rim highlight from 10 o'clock.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.98),
      math.pi * 1.05,
      math.pi * 0.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, s * 0.012)
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: unlocked ? 0.75 : 0.12),
    );

    if (laurel) {
      // Laurel leaves along the lower face.
      final leaf = Paint()..color = metal[0].withValues(alpha: 0.7);
      for (var side = -1; side <= 1; side += 2) {
        for (var k = 0; k < 5; k++) {
          final a = math.pi / 2 + side * (0.45 + k * 0.22);
          final p = c + Offset(math.cos(a), math.sin(a)) * r * 0.6;
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(a + side * 0.6);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: s * 0.06,
              height: s * 0.028,
            ),
            leaf,
          );
          canvas.restore();
        }
      }
    }

    if (!unlocked && progress > 0) {
      final rect = Rect.fromCircle(center: c, radius: r * 1.12);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.025
          ..color = const Color(0x14FFFFFF),
      );
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.025
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.sweep(
            c,
            const [LuxeColors.emeraldDeep, LuxeColors.emerald],
            null,
            TileMode.clamp,
            -math.pi / 2,
            -math.pi / 2 + 2 * math.pi * progress.clamp(0.01, 1.0),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_MedalPainter old) =>
      old.unlocked != unlocked ||
      old.progress != progress ||
      old.metal != metal ||
      old.laurel != laurel;
}

class _ShinePainter extends CustomPainter {
  _ShinePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final x = ui.lerpDouble(-0.6 * w, 1.6 * w, t)!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(x - w * 0.25, 0),
          Offset(x + w * 0.25, size.height * 0.7),
          [
            const Color(0x00FFFFFF),
            Colors.white.withValues(alpha: 0.55),
            const Color(0x00FFFFFF),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_ShinePainter old) => old.t != t;
}
