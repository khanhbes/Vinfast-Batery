import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/widgets/luxe_kit.dart';

/// Capacity left after each charge (QA 141): one dot per charge, straight
/// lines, a % scale and the first/last date. The smooth sparkline it
/// replaces had no scale and its curve dipped where no charge was measured.
/// QA 149: the scale stops at 100 %. One charge's figure carries the gauge's
/// error of a few %, and the owner's phone showed "120 %" for a battery
/// that cannot hold more than new: such a charge sits on the 100 % line as
/// a hollow dot, and a line under the chart says why the dots move.
/// QA 152: the dots are no longer joined. One charge is a noisy reading, and
/// a line from dot to dot drew every gauge error as if the battery had lost
/// and regained 10% in a week (on the owner's phone the newest, lowest dot
/// was the highlighted one, next to a headline of 99%). The line is now the
/// running median of five charges, and a dashed line marks the estimate the
/// screen reports.
class HealthTrendChart extends StatelessWidget {
  const HealthTrendChart({
    super.key,
    required this.points,
    this.estimate,
    this.weak = const [],
  });

  /// (when, % of rated capacity), oldest first.
  final List<(DateTime?, double)> points;

  /// The reported estimate (% of rated capacity), drawn as a dashed line.
  final double? estimate;

  /// QA 162: per point, read when the gauge was little to be trusted (long
  /// after a full charge): drawn fainter.
  final List<bool> weak;

  /// Median of each charge with its two neighbours on either side.
  static List<double> runningMedian(List<double> values) => [
    for (var i = 0; i < values.length; i++)
      _median(
        values.sublist(math.max(0, i - 2), math.min(values.length, i + 3)),
      ),
  ];

  static double _median(List<double> window) {
    final sorted = [...window]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  @override
  Widget build(BuildContext context) {
    final clean = [
      for (final p in points)
        if (p.$2.isFinite) p,
    ];
    final faint = [
      for (var i = 0; i < points.length; i++)
        if (points[i].$2.isFinite) i < weak.length && weak[i],
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
            // QA 151: the line draws itself once, left to right, each dot
            // landing as the line reaches it.
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: luxeDuration(context, 1100),
              curve: Curves.easeInOutCubic,
              builder: (context, t, _) => CustomPaint(
                painter: _TrendPainter(
                  values: values,
                  low: low,
                  high: high,
                  textScale: scaler.scale(10) / 10,
                  estimate: estimate,
                  reveal: t,
                  weak: faint,
                ),
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
            'Mỗi điểm là một lần sạc. Đồng hồ xe chỉ hiện số tròn nên từng '
            'điểm lệch vài %; hãy nhìn đường liền (trung vị 5 lần sạc)'
            '${faint.contains(true) ? ', điểm mờ là lúc lâu chưa sạc đầy' : ''}'
            '${estimate == null ? '' : ', nét đứt là ước tính hiện tại'}'
            '${over ? '. Điểm rỗng là lần đo vượt 100%' : ''}.',
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
    this.estimate,
    this.reveal = 1,
    this.weak = const [],
  });

  final double? estimate;
  final List<bool> weak;

  /// 0–1: how much of the line is drawn.
  final double reveal;
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
          style: TextStyle(color: LuxeColors.dim, fontSize: 11.5 * textScale),
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
    // The reported estimate: a dashed line across the chart.
    final reported = estimate;
    if (reported != null && reported.isFinite) {
      final at = y(reported.clamp(low, high));
      final dash = Paint()
        ..color = LuxeColors.platinumHi.withValues(alpha: 0.45)
        ..strokeWidth = 1;
      for (var x = chart.left; x < chart.right; x += 8) {
        canvas.drawLine(
          Offset(x, at),
          Offset(math.min(x + 4, chart.right), at),
          dash,
        );
      }
    }
    // Each charge: a quiet dot (hollow when above what a battery can hold).
    final reached = chart.left + chart.width * reveal;
    for (var i = 0; i < dots.length; i++) {
      if (dots[i].dx > reached + 0.5) break;
      final clipped = values[i] > high;
      canvas.drawCircle(
        dots[i],
        3,
        Paint()
          ..color = LuxeColors.platinumMid.withValues(
            alpha: i < weak.length && weak[i] ? 0.25 : 0.6,
          )
          ..style = clipped ? PaintingStyle.stroke : PaintingStyle.fill
          ..strokeWidth = 1.4,
      );
    }
    // The trend: the running median, which one odd reading cannot move.
    final smooth = HealthTrendChart.runningMedian([
      for (final v in values) math.min(v, high),
    ]);
    final trend = [
      for (var i = 0; i < smooth.length; i++)
        Offset(chart.left + step * i, y(smooth[i])),
    ];
    final line = Paint()
      ..color = LuxeColors.platinum
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final whole = Path()..addPolygon(trend, false);
    if (reveal >= 1) {
      canvas.drawPath(whole, line);
    } else {
      for (final metric in whole.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * reveal), line);
      }
    }
    if (reveal >= 1) {
      // Where the trend stands now.
      canvas.drawCircle(
        trend.last,
        8,
        Paint()..color = LuxeColors.platinumHi.withValues(alpha: 0.16),
      );
      canvas.drawCircle(trend.last, 4, Paint()..color = LuxeColors.platinumHi);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values != values ||
      old.low != low ||
      old.high != high ||
      old.estimate != estimate ||
      old.weak != weak ||
      old.reveal != reveal;
}
