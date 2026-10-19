import 'package:flutter/material.dart';

import '../theme/luxe_theme.dart';

/// Seven-segment LCD digits like the VinFast Feliz cluster (QA 131): lit
/// segments in [color], unlit ones faintly visible, a slight italic. Digits,
/// space, "-" and ":" are drawn; anything else is skipped. Static (no
/// animation); the semantics label is the plain [text].
class SevenSegmentText extends StatelessWidget {
  const SevenSegmentText(
    this.text, {
    super.key,
    this.height = 40,
    this.color = LuxeColors.platinumHi,
    this.ghost = true,
    this.semanticsLabel,
  });

  final String text;
  final double height;
  final Color color;

  /// Show unlit segments faintly ("88" behind the digits), like a real LCD.
  final bool ghost;
  final String? semanticsLabel;

  static double widthOf(String text, double height) {
    var w = 0.0;
    for (final ch in text.split('')) {
      w += ch == ':' ? height * 0.22 : height * 0.62;
    }
    return w + height * 0.12;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel ?? text,
    excludeSemantics: true,
    child: CustomPaint(
      size: Size(widthOf(text, height), height),
      painter: _SevenSegmentPainter(text, color, ghost),
    ),
  );
}

class _SevenSegmentPainter extends CustomPainter {
  _SevenSegmentPainter(this.text, this.color, this.ghost);

  final String text;
  final Color color;
  final bool ghost;

  // a b c d e f g
  static const _map = <String, List<bool>>{
    '0': [true, true, true, true, true, true, false],
    '1': [false, true, true, false, false, false, false],
    '2': [true, true, false, true, true, false, true],
    '3': [true, true, true, true, false, false, true],
    '4': [false, true, true, false, false, true, true],
    '5': [true, false, true, true, false, true, true],
    '6': [true, false, true, true, true, true, true],
    '7': [true, true, true, false, false, false, false],
    '8': [true, true, true, true, true, true, true],
    '9': [true, true, true, true, false, true, true],
    '-': [false, false, false, false, false, false, true],
    ' ': [false, false, false, false, false, false, false],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final cellW = h * 0.62;
    final t = h * 0.105; // stroke
    final w = cellW - h * 0.14; // digit width
    const slant = 0.1;
    final lit = Paint()..color = color;
    final dim = Paint()..color = color.withValues(alpha: 0.07);
    var x = h * 0.08;
    for (final ch in text.split('')) {
      if (ch == ':') {
        final dot = Paint()..color = color;
        final cx = x + h * 0.1;
        for (final cy in [h * 0.32, h * 0.7]) {
          canvas.drawCircle(
            Offset(cx + slant * (h / 2 - cy), cy),
            t * 0.55,
            dot,
          );
        }
        x += h * 0.22;
        continue;
      }
      final on = _map[ch];
      if (on == null) {
        x += cellW;
        continue;
      }
      Offset p(double px, double py) =>
          Offset(x + px + slant * (h / 2 - py), py);
      final half = h / 2;
      final g = t * 0.18; // gap between segments
      Path horizontal(double y) => Path()
        ..moveTo(p(g + t / 2, y).dx, y)
        ..lineTo(p(g + t, y - t / 2).dx, y - t / 2)
        ..lineTo(p(w - g - t, y - t / 2).dx, y - t / 2)
        ..lineTo(p(w - g - t / 2, y).dx, y)
        ..lineTo(p(w - g - t, y + t / 2).dx, y + t / 2)
        ..lineTo(p(g + t, y + t / 2).dx, y + t / 2)
        ..close();
      Path vertical(double px, double y0, double y1) {
        final a = p(px, y0 + g + t / 2);
        final b = p(px + t / 2, y0 + g + t);
        final c = p(px + t / 2, y1 - g - t);
        final d = p(px, y1 - g - t / 2);
        final e = p(px - t / 2, y1 - g - t);
        final f = p(px - t / 2, y0 + g + t);
        return Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(c.dx, c.dy)
          ..lineTo(d.dx, d.dy)
          ..lineTo(e.dx, e.dy)
          ..lineTo(f.dx, f.dy)
          ..close();
      }

      final top = t / 2, bottom = h - t / 2;
      final segments = [
        horizontal(top), // a
        vertical(w - t / 2, top, half), // b
        vertical(w - t / 2, half, bottom), // c
        horizontal(bottom), // d
        vertical(t / 2, half, bottom), // e
        vertical(t / 2, top, half), // f
        horizontal(half), // g
      ];
      for (var i = 0; i < 7; i++) {
        if (on[i]) {
          canvas.drawPath(segments[i], lit);
        } else if (ghost) {
          canvas.drawPath(segments[i], dim);
        }
      }
      x += cellW;
    }
  }

  @override
  bool shouldRepaint(_SevenSegmentPainter old) =>
      old.text != text || old.color != color || old.ghost != ghost;
}
