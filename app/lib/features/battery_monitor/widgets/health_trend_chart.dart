import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';

/// Capacity left after each charge (QA 141): one dot per charge, straight
/// lines, a % scale and the first/last date. The smooth sparkline it
/// replaces had no scale and its curve dipped where no charge was measured.
/// QA 149: the scale stops at 100 %. One charge's figure carries the gauge's
/// error of a few %, and the owner's phone showed "120 %" for a battery
/// that cannot hold more than new: such a charge sits on the 100 % line as
/// a hollow dot, and a line under the chart says why the dots move.
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
    final low = math.min(90.0, (values.reduce(math.min) / 5).floor() * 5.0);
    const high = 100.0;
    final over = values.any((v) => v > high);
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
          const SizedBox(height: 6),
          Text(
            over
                ? 'Mỗi điểm là một lần sạc. Đồng hồ xe lệch vài % nên các '
                      'điểm dao động; điểm rỗng là lần đo vượt 100%.'
                : 'Mỗi điểm là một lần sạc. Đồng hồ xe lệch vài % nên các '
                      'điểm dao động.',
            key: const ValueKey('health-trend-note'),
            style: LuxeText.caption,
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
        Offset(chart.left + step * i, y(math.min(values[i], high))),
    ];
    final line = Paint()
      ..color = LuxeColors.champagne.withValues(alpha: 0.7)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawPath(Path()..addPolygon(dots, false), line);
    for (var i = 0; i < dots.length; i++) {
      final last = i == dots.length - 1;
      final clipped = values[i] > high;
      if (clipped) {
        // Above what a battery can hold: the gauge's error, drawn hollow.
        canvas.drawCircle(dots[i], 3.4, Paint()..color = LuxeColors.background);
      }
      canvas.drawCircle(
        dots[i],
        last ? 4.5 : 3.4,
        Paint()
          ..color = LuxeColors.champagne
          ..style = clipped ? PaintingStyle.stroke : PaintingStyle.fill
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values != values || old.low != low || old.high != high;
}
