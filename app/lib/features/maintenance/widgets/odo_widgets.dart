import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../data/models/maintenance_task_model.dart';

/// Colour per urgency, shared by the track, chips and cards.
Color urgencyColor(MaintenanceUrgency u) => switch (u) {
  MaintenanceUrgency.overdue => const Color(0xFFF59E9E),
  MaintenanceUrgency.dueSoon => LuxeColors.champagne,
  MaintenanceUrgency.upcoming => LuxeColors.emerald,
  MaintenanceUrgency.completed => LuxeColors.platinumMid,
};

/// Mechanical odometer: each digit rolls into place; the last digit is lit.
class OdometerDrum extends StatelessWidget {
  const OdometerDrum({super.key, required this.value, this.minDigits = 5});
  final int value;
  final int minDigits;

  @override
  Widget build(BuildContext context) {
    final digits = math.max(minDigits, value.abs().toString().length);
    return Semantics(
      label: 'Số km ODO $value',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 1600),
        curve: const Cubic(0.2, 0.0, 0.0, 1.0),
        builder: (context, v, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = digits - 1; i >= 0; i--)
              _DigitWheel(
                // Continuous position of this digit: v / 10^i.
                position: v / math.pow(10, i),
                lit: i == 0,
              ),
          ],
        ),
      ),
    );
  }
}

class _DigitWheel extends StatelessWidget {
  const _DigitWheel({required this.position, required this.lit});
  final double position;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    const h = 44.0, w = 30.0;
    final p = position % 10;
    final base = p.floor();
    // Higher digits only roll during the last tenth (like a real drum).
    final frac = lit
        ? p - base
        : ((p - base) > 0.9 ? (p - base - 0.9) * 10 : 0.0);
    return Container(
      width: w,
      height: h,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF050506), Color(0xFF1B1C1F), Color(0xFF050506)],
        ),
        border: Border.all(
          color: lit
              ? LuxeColors.emerald.withValues(alpha: 0.5)
              : LuxeColors.hairlineStrong,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          children: [
            for (final (d, dy) in [
              (base, -frac * h),
              ((base + 1) % 10, (1 - frac) * h),
            ])
              Positioned(
                left: 0,
                right: 0,
                top: dy,
                height: h,
                child: Center(
                  child: Text(
                    '$d',
                    style: TextStyle(
                      color: lit ? LuxeColors.emerald : LuxeColors.platinumHi,
                      fontSize: 24,
                      fontWeight: FontWeight.w300,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            // Glass highlight across the drum window.
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x99000000),
                        Color(0x00000000),
                        Color(0x14FFFFFF),
                        Color(0x00000000),
                        Color(0x99000000),
                      ],
                      stops: [0.0, 0.3, 0.5, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kilometre track: where the scooter is now and every open milestone.
class OdoTrack extends StatelessWidget {
  const OdoTrack({super.key, required this.currentOdo, required this.tasks});
  final int currentOdo;
  final List<MaintenanceTaskModel> tasks;

  @override
  Widget build(BuildContext context) {
    final open = tasks.where((t) => !t.isCompleted).toList()
      ..sort((a, b) => a.targetOdo.compareTo(b.targetOdo));
    final next = open.where((t) => t.targetOdo > currentOdo).toList();
    final label = open.isEmpty
        ? 'Chưa có mốc nào đang mở'
        : next.isEmpty
        ? '${open.length} mốc đã đến hạn'
        : 'Mốc kế tiếp: ${next.first.title} · còn ${_km(next.first.targetOdo - currentOdo)} km';
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 74,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 1300),
              curve: LuxeMotion.enter,
              builder: (context, t, _) => CustomPaint(
                painter: _TrackPainter(
                  current: currentOdo,
                  tasks: open,
                  reveal: t,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: LuxeText.caption),
        ],
      ),
    );
  }

  static String _km(int km) {
    final s = km.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.current,
    required this.tasks,
    required this.reveal,
  });
  final int current;
  final List<MaintenanceTaskModel> tasks;
  final double reveal;

  @override
  void paint(Canvas canvas, Size size) {
    final targets = tasks.map((t) => t.targetOdo).toList();
    final lo = math.min(
      current,
      targets.isEmpty ? current : targets.reduce(math.min),
    );
    final hi = math.max(
      current + 500,
      targets.isEmpty ? current + 1000 : targets.reduce(math.max),
    );
    final span = math.max(1, hi - lo);
    const pad = 18.0;
    final y = size.height * 0.52;
    double x(int km) => pad + (size.width - 2 * pad) * (km - lo) / span;
    final right = pad + (size.width - 2 * pad) * reveal;

    // Track: travelled part platinum, road ahead faint.
    canvas.drawLine(
      Offset(pad, y),
      Offset(right, y),
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x22FFFFFF),
    );
    final now = x(current).clamp(pad, right);
    canvas.drawLine(
      Offset(pad, y),
      Offset(now, y),
      Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          Offset(pad, y),
          Offset(math.max(now, pad + 1), y),
          const [LuxeColors.platinumLow, LuxeColors.platinumHi],
        ),
    );
    // Kilometre ticks.
    for (var i = 0; i <= 10; i++) {
      final tx = pad + (size.width - 2 * pad) * i / 10;
      if (tx > right) break;
      canvas.drawLine(
        Offset(tx, y + 6),
        Offset(tx, y + (i % 5 == 0 ? 12 : 9)),
        Paint()
          ..strokeWidth = 1
          ..color = const Color(0x33FFFFFF),
      );
    }
    void label(String text, Offset at, Color color, {bool above = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (at.dx - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(dx, above ? at.dy - tp.height : at.dy));
    }

    // Milestones.
    for (final t in tasks) {
      final mx = x(t.targetOdo);
      if (mx > right + 0.5) continue;
      final color = urgencyColor(t.urgency(current));
      final diamond = Path()
        ..moveTo(mx, y - 7)
        ..lineTo(mx + 6, y)
        ..lineTo(mx, y + 7)
        ..lineTo(mx - 6, y)
        ..close();
      canvas.drawPath(
        diamond,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawPath(diamond, Paint()..color = color);
    }
    // Scooter marker with a halo.
    if (reveal > 0.2) {
      canvas.drawCircle(
        Offset(now, y),
        12,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(
        Offset(now, y),
        7,
        Paint()..color = LuxeColors.platinumHi,
      );
      canvas.drawCircle(
        Offset(now, y),
        3,
        Paint()..color = const Color(0xFF0B0C0E),
      );
      label(
        'Xe · ${_short(current)}',
        Offset(now, y - 12),
        LuxeColors.text,
        above: true,
      );
    }
    label(_short(lo), Offset(pad, y + 14), LuxeColors.dim);
    label(_short(hi), Offset(size.width - pad, y + 14), LuxeColors.dim);
  }

  static String _short(int km) => km >= 10000
      ? '${(km / 1000).toStringAsFixed(km % 1000 == 0 ? 0 : 1)}k km'
      : '$km km';

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.reveal != reveal || old.current != current || old.tasks != tasks;
}
