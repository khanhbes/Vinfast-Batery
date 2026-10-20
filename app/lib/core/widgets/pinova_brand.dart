import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/luxe_theme.dart';

/// Image layers cut from the owner's metal Pinova logo (QA 133): the metal
/// (with the white knob) and the emerald charge track + glow, so the splash
/// can run the charge along the real artwork. 1024-px art, transparent.
abstract final class PinovaLogoAssets {
  static const metal = 'assets/icons/pinova_logo_metal.png';
  static const charge = 'assets/icons/pinova_logo_charge.png';
  static const full = 'assets/icons/pinova_logo_full.png';

  /// Geometry of the art, in its 1024-px space: the dial ring and the box
  /// the mark occupies (stem foot included).
  static const ringCentre = Offset(512, 421);
  static const ringRadius = 219.0; // stroke centre-line
  static const ringStroke = 94.0;
  static const stemFoot = 823.0; // centre of the stem's round end
  static const markBox = Rect.fromLTRB(246, 155, 778, 869);
  static const knobAngle = 128 * math.pi / 180;
  static const trackEndAngle = 38 * math.pi / 180;
}

/// The "PINOVA" wordmark, drawn rather than typeset: thin geometric capitals
/// in brushed platinum with wide tracking; the O carries the logo's emerald
/// charge arc and knob. [tracking] is the letter gap in cap heights.
class PinovaWordmark extends StatelessWidget {
  const PinovaWordmark({
    super.key,
    this.height = 22,
    this.tracking = 0.42,
    this.charge = 1,
  });

  /// Cap height in logical pixels.
  final double height;
  final double tracking;

  /// How much of the O's emerald arc is lit (0–1).
  final double charge;

  static double widthFor(double height, double tracking) =>
      height * (_letterWidths.reduce((a, b) => a + b) + tracking * 5) +
      height * 0.1;

  static const _letterWidths = [0.58, 0.0, 0.70, 1.0, 0.76, 0.76];

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Pinova',
    excludeSemantics: true,
    child: CustomPaint(
      size: Size(widthFor(height, tracking), height * 1.1),
      painter: _WordmarkPainter(height, tracking, charge),
    ),
  );
}

class _WordmarkPainter extends CustomPainter {
  _WordmarkPainter(this.h, this.tracking, this.charge);

  final double h;
  final double tracking;
  final double charge;

  @override
  void paint(Canvas canvas, Size size) {
    final t = math.max(1.3, h * 0.072); // stroke
    final top = (size.height - h) / 2;
    final metal = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = t
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          LuxeColors.platinumHi,
          LuxeColors.platinum,
          LuxeColors.platinumMid,
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(Offset(0, top) & Size(size.width, h));
    var x = h * 0.05 + t / 2;
    double y(double v) => top + v * h;

    // P: stem + a bowl to mid-height.
    final bowlR = h * 0.27;
    final p = Path()
      ..moveTo(x, y(1))
      ..lineTo(x, y(0) + t / 2)
      ..lineTo(x + h * 0.58 - bowlR - t / 2, y(0) + t / 2)
      ..arcTo(
        Rect.fromCircle(
          center: Offset(x + h * 0.58 - bowlR - t / 2, y(0) + t / 2 + bowlR),
          radius: bowlR,
        ),
        -math.pi / 2,
        math.pi,
        false,
      )
      ..lineTo(x, y(0) + t / 2 + 2 * bowlR);
    canvas.drawPath(p, metal);
    x += h * (0.58 + tracking);

    // I
    canvas.drawLine(Offset(x, y(0)), Offset(x, y(1)), metal);
    x += h * tracking;

    // N
    canvas.drawPath(
      Path()
        ..moveTo(x, y(1))
        ..lineTo(x, y(0))
        ..lineTo(x + h * 0.70, y(1))
        ..lineTo(x + h * 0.70, y(0)),
      metal,
    );
    x += h * (0.70 + tracking);

    // O: a dial, with the logo's charge arc and knob.
    final oCentre = Offset(x + h * 0.5, y(0.5));
    final oRect = Rect.fromCircle(center: oCentre, radius: h * 0.5 - t / 2);
    canvas.drawOval(oRect, metal);
    if (charge > 0) {
      const from = 128 * math.pi / 180;
      const span = (128 - 38) * math.pi / 180;
      canvas.drawArc(
        oRect,
        from,
        -span * charge,
        false,
        Paint()
          ..color = LuxeColors.emerald.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = t * 2.2
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, t * 1.4),
      );
      canvas.drawArc(
        oRect,
        from,
        -span * charge,
        false,
        Paint()
          ..color = LuxeColors.emerald
          ..style = PaintingStyle.stroke
          ..strokeWidth = t * 1.15
          ..strokeCap = StrokeCap.round,
      );
      final knob =
          oCentre + Offset(math.cos(from), math.sin(from)) * (h * 0.5 - t / 2);
      canvas.drawCircle(knob, t * 0.95, Paint()..color = Colors.white);
    }
    x += h * (1.0 + tracking);

    // V
    canvas.drawPath(
      Path()
        ..moveTo(x, y(0))
        ..lineTo(x + h * 0.38, y(1))
        ..lineTo(x + h * 0.76, y(0)),
      metal,
    );
    x += h * (0.76 + tracking);

    // A, without a bar (a clean chevron).
    canvas.drawPath(
      Path()
        ..moveTo(x, y(1))
        ..lineTo(x + h * 0.38, y(0))
        ..lineTo(x + h * 0.76, y(1)),
      metal,
    );
  }

  @override
  bool shouldRepaint(_WordmarkPainter old) =>
      old.h != h || old.tracking != tracking || old.charge != charge;
}
