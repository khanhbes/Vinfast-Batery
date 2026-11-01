import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';

/// Capacity left after each charge (QA 141): one dot per charge, straight
/// lines, a % scale and the first/last date. The smooth sparkline it
/// replaces had no scale and its curve dipped where no charge was measured.
class HealthTrendChart extends StatelessWidget {
  const HealthTrendChart({super.key, required this.points});

  /// (when, % of rated capacity), oldest first.
  final List<(DateTime?, double)> points;

  @override
  Widget build(BuildContext context) {
    final clean = [
      for (final p in points)
        if (p.$2.isFinite) p,
    ];
    if (clean.length < 2) return const SizedBox.shrink();
    final values = [for (final p in clean) p.$2];
    final low = (values.reduce(math.min) / 5).floor() * 5.0;
    final high = math.max(100.0, (values.reduce(math.max) / 5).ceil() * 5.0);
    String date(DateTime? d) => d == null ? '' : '${d.day}/${d.month}';
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      label:
          'Dung lượng còn lại theo ${clean.length} lần sạc, từ '
          '${values.first.round()}% đến ${values.last.round()}%',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 120,
            child: CustomPaint(
              painter: _TrendPainter(
                values: values,
                low: low,
                high: high,
                textScale: scaler.scale(10) / 10,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 34),
              Expanded(
                child: Text(
                  date(clean.first.$1),
                  maxLines: 1,
                  style: LuxeText.caption,
                ),
              ),
              Expanded(
                child: Text(
                  date(clean.last.$1),
                  maxLines: 1,
                  textAlign: TextAlign.end,
                  style: LuxeText.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.low,
    required this.high,
    required this.textScale,
  });

  final List<double> values;
  final double low;
  final double high;
  final double textScale;

  static const _axis = 34.0;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTRB(_axis, 8, size.width - 8, size.height - 6);
    double y(double v) =>
        chart.bottom - (v - low) / (high - low) * chart.height;
    final grid = Paint()
      ..color = const Color(0x1FFFFFFF)
      ..strokeWidth = 1;
    for (final mark in [low, (low + high) / 2, high]) {
      final at = y(mark);
      canvas.drawLine(Offset(chart.left, at), Offset(chart.right, at), grid);
      final label = TextPainter(
        text: TextSpan(
          text: '${mark.round()}%',
          style: TextStyle(color: LuxeColors.dim, fontSize: 11 * textScale),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(chart.left - label.width - 6, at - label.height / 2),
      );
    }
    final step = values.length == 1 ? 0.0 : chart.width / (values.length - 1);
    final dots = [
      for (var i = 0; i < values.length; i++)
        Offset(chart.left + step * i, y(values[i])),
    ];
    final line = Paint()
      ..color = LuxeColors.champagne.withValues(alpha: 0.7)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawPath(Path()..addPolygon(dots, false), line);
    for (var i = 0; i < dots.length; i++) {
      final last = i == dots.length - 1;
      canvas.drawCircle(
        dots[i],
        last ? 4.5 : 3,
        Paint()..color = LuxeColors.champagne,
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values != values || old.low != low || old.high != high;
}
