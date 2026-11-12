import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/luxe_theme.dart';

/// Pinova Bot's expressions. QA 151 added `worried`, `sorry`, `celebrating`
/// and `sleepy`; every mood now has a mouth, and the full-body mascot and
/// the round avatar draw the same face ([BotFace]).
enum BatteryBotMood {
  idle,
  greeting,
  happy,
  thinking,
  charging,
  listening,

  /// Something needs the rider's attention (low battery).
  worried,

  /// The bot could not do or answer something.
  sorry,

  /// Something real went well (a finished charge, a verified action).
  celebrating,

  /// Late at night with nothing going on.
  sleepy,
}

/// One face for every size (QA 151): eyes, brows, mouth and the small extras
/// (blush, sweat drop, sparkles, "z"). All measures derive from the eye
/// radius [r], so it stays crisp from the 24 dp chat avatar to the 200 dp
/// hero.
abstract final class BotFace {
  /// Moods whose eyes are ovals, so a blink ([eyeOpen]) shows.
  static const _blinking = {
    BatteryBotMood.idle,
    BatteryBotMood.listening,
    BatteryBotMood.worried,
    BatteryBotMood.sorry,
  };

  /// [left]/[right] are the eye centres of a mouthless face; with [mouth]
  /// the eyes move up a little to make room. [phase] (0–1, back and forth)
  /// moves the thinking pupils; [pulse] the listening rings and sparkles.
  static void paint(
    Canvas canvas, {
    required Offset left,
    required Offset right,
    required double r,
    required BatteryBotMood mood,
    required Color color,
    double eyeOpen = 1,
    double pulse = 0,
    double phase = 0,
    bool mouth = true,
  }) {
    if (mouth) {
      left = left.translate(0, -r * 0.4);
      right = right.translate(0, -r * 0.4);
    }
    final open = _blinking.contains(mood) ? eyeOpen.clamp(0.1, 1.0) : 1.0;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (r * 0.5).clamp(1.5, 4.5)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final thin = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (r * 0.34).clamp(1.2, 3.2)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (mood) {
      case BatteryBotMood.idle:
        _ovals(canvas, left, right, r, r * 1.2 * open, color);
      case BatteryBotMood.listening:
        _ovals(canvas, left, right, r * 1.12, r * 1.34 * open, color);
        canvas.drawArc(
          Rect.fromCircle(center: left, radius: r * 1.7 + pulse * r * 0.4),
          -math.pi * 0.7,
          math.pi * 0.4,
          false,
          Paint()
            ..color = color.withValues(alpha: (0.6 - pulse * 0.4))
            ..style = PaintingStyle.stroke
            ..strokeWidth = (r * 0.14).clamp(0.8, 1.4),
        );
      case BatteryBotMood.happy:
      case BatteryBotMood.celebrating:
        for (final c in [left, right]) {
          canvas.drawArc(
            Rect.fromCircle(center: c.translate(0, r * 0.3), radius: r * 0.95),
            math.pi * 1.15,
            math.pi * 0.7,
            false,
            stroke,
          );
        }
      case BatteryBotMood.sleepy:
        for (final c in [left, right]) {
          canvas.drawArc(
            Rect.fromCircle(center: c.translate(0, -r * 0.5), radius: r * 0.95),
            math.pi * 0.15,
            math.pi * 0.7,
            false,
            stroke,
          );
        }
      case BatteryBotMood.greeting:
        for (final c in [left, right]) {
          _glow(canvas, c, r * 1.1, color);
          canvas.drawPath(_star(c, r * 1.15), Paint()..color = color);
          canvas.drawCircle(c, r * 0.2, Paint()..color = Colors.white);
        }
      case BatteryBotMood.thinking:
        // Looking up, the gaze drifting from one side to the other.
        final angle = -math.pi / 2 + (phase - 0.5) * 1.5;
        final look = Offset(math.cos(angle), math.sin(angle)) * (r * 0.36);
        for (final c in [left, right]) {
          canvas.drawCircle(
            c,
            r,
            Paint()..color = color.withValues(alpha: 0.25),
          );
          canvas.drawCircle(c + look, r * 0.64, Paint()..color = color);
          canvas.drawCircle(
            c + look - Offset(r * 0.14, r * 0.14),
            r * 0.22,
            Paint()..color = Colors.white,
          );
        }
      case BatteryBotMood.charging:
        for (final c in [left, right]) {
          canvas.drawPath(_bolt(c, r * 1.2, r * 1.6), Paint()..color = color);
        }
      case BatteryBotMood.worried:
        _ovals(canvas, left, right, r * 0.9, r * 1.1 * open, color);
        _brows(canvas, left, right, r, thin);
        _sweat(canvas, right.translate(r * 1.55, -r * 1.2), r * 0.42);
      case BatteryBotMood.sorry:
        // Half-closed lids: only the lower part of each eye shows.
        for (final c in [left, right]) {
          canvas.save();
          canvas.clipRect(
            Rect.fromLTRB(
              c.dx - r * 2,
              c.dy - r * 0.2,
              c.dx + r * 2,
              c.dy + r * 2,
            ),
          );
          _oval(canvas, c, r, r * 1.2 * open, color, glint: false);
          canvas.restore();
          canvas.drawLine(
            c.translate(-r, -r * 0.2),
            c.translate(r, -r * 0.2),
            thin,
          );
        }
        _brows(canvas, left, right, r, thin);
    }

    if (mood == BatteryBotMood.happy ||
        mood == BatteryBotMood.greeting ||
        mood == BatteryBotMood.celebrating) {
      final blush = Paint()
        ..color = LuxeColors.danger.withValues(alpha: 0.42)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.3);
      canvas.drawCircle(left.translate(-r * 0.5, r * 1.15), r * 0.5, blush);
      canvas.drawCircle(right.translate(r * 0.5, r * 1.15), r * 0.5, blush);
    }
    if (mood == BatteryBotMood.celebrating) {
      final shine = Paint()..color = Colors.white.withValues(alpha: 0.9);
      final k = 0.85 + pulse * 0.15;
      canvas.drawPath(
        _star(left.translate(-r * 1.4, -r * 1.35), r * 0.5 * k),
        shine,
      );
      canvas.drawPath(
        _star(right.translate(r * 1.5, -r * 1.1), r * 0.36 * k),
        shine,
      );
    }
    if (mood == BatteryBotMood.sleepy) {
      _z(canvas, right.translate(r * 0.9, -r * 1.5), r * 0.5, thin, 0.9);
      _z(canvas, right.translate(r * 1.7, -r * 2.2), r * 0.34, thin, 0.55);
    }
    if (mouth) {
      final at = Offset((left.dx + right.dx) / 2, left.dy + r * 1.9);
      _mouth(canvas, at, r, mood, color, stroke, thin);
    }
  }

  static void _mouth(
    Canvas canvas,
    Offset m,
    double r,
    BatteryBotMood mood,
    Color color,
    Paint stroke,
    Paint thin,
  ) {
    final w = r * 1.05;
    switch (mood) {
      case BatteryBotMood.idle:
      case BatteryBotMood.charging:
        canvas.drawPath(
          Path()
            ..moveTo(m.dx - w, m.dy - r * 0.1)
            ..quadraticBezierTo(m.dx, m.dy + r * 0.7, m.dx + w, m.dy - r * 0.1),
          thin,
        );
      case BatteryBotMood.happy:
      case BatteryBotMood.greeting:
      case BatteryBotMood.celebrating:
        final k = mood == BatteryBotMood.celebrating ? 1.25 : 1.0;
        canvas.drawPath(
          Path()
            ..moveTo(m.dx - w * k, m.dy - r * 0.2)
            ..lineTo(m.dx + w * k, m.dy - r * 0.2)
            ..quadraticBezierTo(
              m.dx,
              m.dy + r * 1.35 * k,
              m.dx - w * k,
              m.dy - r * 0.2,
            )
            ..close(),
          Paint()..color = color,
        );
      case BatteryBotMood.thinking:
        canvas.drawLine(
          m.translate(-r * 0.2, r * 0.1),
          m.translate(r * 0.9, r * 0.1),
          thin,
        );
      case BatteryBotMood.listening:
        canvas.drawCircle(m.translate(0, r * 0.15), r * 0.34, thin);
      case BatteryBotMood.sleepy:
        canvas.drawCircle(m.translate(0, r * 0.15), r * 0.24, thin);
      case BatteryBotMood.worried:
        canvas.drawPath(
          Path()
            ..moveTo(m.dx - w, m.dy + r * 0.15)
            ..quadraticBezierTo(
              m.dx - w / 2,
              m.dy - r * 0.4,
              m.dx,
              m.dy + r * 0.15,
            )
            ..quadraticBezierTo(
              m.dx + w / 2,
              m.dy + r * 0.7,
              m.dx + w,
              m.dy + r * 0.15,
            ),
          thin,
        );
      case BatteryBotMood.sorry:
        canvas.drawPath(
          Path()
            ..moveTo(m.dx - w * 0.8, m.dy + r * 0.45)
            ..quadraticBezierTo(
              m.dx,
              m.dy - r * 0.4,
              m.dx + w * 0.8,
              m.dy + r * 0.45,
            ),
          thin,
        );
    }
  }

  static void _glow(Canvas canvas, Offset c, double radius, Color color) {
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.38)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.4),
    );
  }

  static void _ovals(
    Canvas canvas,
    Offset left,
    Offset right,
    double rx,
    double ry,
    Color color,
  ) {
    _oval(canvas, left, rx, ry, color);
    _oval(canvas, right, rx, ry, color);
  }

  static void _oval(
    Canvas canvas,
    Offset c,
    double rx,
    double ry,
    Color color, {
    bool glint = true,
  }) {
    final rect = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
    canvas.drawOval(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rx * 0.4),
    );
    canvas.drawOval(rect, Paint()..color = color);
    if (!glint || ry < rx * 0.6) return;
    final white = Paint()..color = Colors.white;
    canvas.drawCircle(c.translate(-rx * 0.3, -ry * 0.3), rx * 0.34, white);
    canvas.drawCircle(c.translate(rx * 0.3, ry * 0.2), rx * 0.17, white);
  }

  /// Brows with the inner ends raised.
  static void _brows(
    Canvas canvas,
    Offset left,
    Offset right,
    double r,
    Paint paint,
  ) {
    canvas.drawLine(
      left.translate(-r * 0.9, -r * 1.55),
      left.translate(r * 0.7, -r * 2.0),
      paint,
    );
    canvas.drawLine(
      right.translate(r * 0.9, -r * 1.55),
      right.translate(-r * 0.7, -r * 2.0),
      paint,
    );
  }

  static void _sweat(Canvas canvas, Offset at, double s) {
    canvas.drawPath(
      Path()
        ..moveTo(at.dx, at.dy - s * 1.4)
        ..quadraticBezierTo(at.dx + s, at.dy + s * 0.2, at.dx, at.dy + s * 0.9)
        ..quadraticBezierTo(at.dx - s, at.dy + s * 0.2, at.dx, at.dy - s * 1.4)
        ..close(),
      Paint()..color = LuxeColors.steel,
    );
  }

  static void _z(Canvas canvas, Offset at, double s, Paint base, double alpha) {
    canvas.drawPath(
      Path()
        ..moveTo(at.dx - s, at.dy - s)
        ..lineTo(at.dx + s, at.dy - s)
        ..lineTo(at.dx - s, at.dy + s)
        ..lineTo(at.dx + s, at.dy + s),
      Paint()
        ..color = base.color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = base.strokeWidth * 0.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// A four-point star.
  static Path _star(Offset c, double r) {
    final inner = r * 0.3;
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 - math.pi / 2;
      final b = a + math.pi / 4;
      final tip = c + Offset(math.cos(a), math.sin(a)) * r;
      if (i == 0) {
        path.moveTo(tip.dx, tip.dy);
      } else {
        path.lineTo(tip.dx, tip.dy);
      }
      path.lineTo(c.dx + math.cos(b) * inner, c.dy + math.sin(b) * inner);
    }
    return path..close();
  }

  static Path _bolt(Offset c, double w, double h) => Path()
    ..moveTo(c.dx + w * 0.2, c.dy - h * 0.5)
    ..lineTo(c.dx - w * 0.4, c.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(c.dx - w * 0.2, c.dy + h * 0.5)
    ..lineTo(c.dx + w * 0.4, c.dy)
    ..lineTo(c.dx, c.dy)
    ..close();
}
