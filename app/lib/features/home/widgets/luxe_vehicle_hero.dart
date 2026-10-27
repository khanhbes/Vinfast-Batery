import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../data/services/range_estimator.dart';
import '../../../data/services/trip_energy_model.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/theme/plan_style.dart';
import '../../../core/widgets/vehicle_photo.dart';
import '../../../data/models/vehicle_model.dart';

/// Dashboard hero: the scooter on a lit stage (the vehicle photo shared by
/// every screen, otherwise a platinum line-art scooter whose battery glows
/// with the charge), the name, plate and the battery reading.
class LuxeVehicleHero extends StatefulWidget {
  const LuxeVehicleHero({super.key, required this.vehicle, this.learned});
  final VehicleModel? vehicle;

  /// The owner's trained trip model: same km/% as every other screen.
  final TripModelParams? learned;

  @override
  State<LuxeVehicleHero> createState() => _LuxeVehicleHeroState();
}

class _LuxeVehicleHeroState extends State<LuxeVehicleHero>
    with TickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      _float.stop();
      _enter.value = 1;
    } else if (!_started) {
      // Entrance only: no endless decorative float (LUXE motion rule,
      // Task 125); the scooter rests on its final frame.
      _enter.forward();
    }
    _started = true;
  }

  @override
  void dispose() {
    _float.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    final model = v?.vinfastModelName?.trim().isNotEmpty == true
        ? v!.vinfastModelName!.trim()
        : (v?.vehicleName.trim().isNotEmpty == true ? v!.vehicleName : null);
    final name = v?.nickname?.trim().isNotEmpty == true
        ? v!.nickname!.trim()
        : (model ?? 'Chưa có dữ liệu xe');
    final plate = v?.licensePlate?.trim().isNotEmpty == true
        ? v!.licensePlate!.trim()
        : 'Chưa có BSX';
    // Only data the owner actually entered or a charge measured: a vehicle
    // without battery data used to show the model defaults "100% · ~120 km"
    // (Task 125). One field, the same the Charge tab and BatteryBot write.
    final percent = v?.hasBatteryData == true ? v?.currentBattery : null;
    final estimate = v == null || percent == null
        ? null
        : estimateRangeKm(v, learned: widget.learned);
    final range = estimate?.round();
    final photo = VehicleImages.forVehicle(v);

    return Semantics(
      container: true,
      label:
          '$name, $plate${percent == null ? '' : ', pin $percent phần trăm'}',
      child: LuxeGlass(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The model name only above a nickname: without one,
                      // "VINFAST FELIZ / VinFast Feliz" repeated (QA 130).
                      Text(
                        (name != model && model != null ? model : 'Xe của bạn')
                            .toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LuxeText.eyebrow,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: LuxeColors.text,
                          fontSize: 24,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: LuxeColors.hairlineStrong),
                        color: LuxeColors.glass,
                      ),
                      child: Text(
                        plate,
                        style: const TextStyle(
                          color: LuxeColors.platinum,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // A lit studio box (QA 133): a graphite cyclorama with a top
            // spotlight, a floor and a contact shadow, so black wheels and
            // dark paint keep their silhouette instead of sinking into the
            // page's near-black.
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                height: 232,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_float, _enter]),
                  builder: (context, _) {
                    final t = _float.value;
                    final e = Curves.easeOutCubic.transform(_enter.value);
                    final bob = 3 * math.sin(t * 2 * math.pi);
                    return Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _StagePainter(
                              glow: 0.85 + 0.15 * math.sin(t * 2 * math.pi),
                              // QA 136: the stage light takes the plan.
                              light: PlanStyle.of(context).accent,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 6,
                          right: 6,
                          bottom: 16,
                          top: 10,
                          child: Opacity(
                            opacity: e,
                            child: Transform.translate(
                              offset: Offset(24 * (1 - e), bob),
                              child: VehiclePhoto(
                                url: photo,
                                reflection: true,
                                fallback: LuxeScooterArt(
                                  level: (percent ?? 0) / 100,
                                  spin: t,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            TweenAnimationBuilder<double>(
                              tween: Tween(end: (percent ?? 0).toDouble()),
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 1200),
                              curve: LuxeMotion.enter,
                              builder: (context, val, _) => LuxeMetalText(
                                percent == null ? '—' : '${val.round()}',
                                style: const TextStyle(
                                  fontSize: 52,
                                  height: 1.0,
                                  fontWeight: FontWeight.w200,
                                  letterSpacing: -1.5,
                                  fontFeatures: [
                                    ui.FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            const Text(
                              '%',
                              style: TextStyle(
                                color: LuxeColors.emerald,
                                fontSize: 18,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text('Pin hiện tại', style: LuxeText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          range == null ? '— km' : '$range km',
                          style: const TextStyle(
                            color: LuxeColors.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w300,
                            fontFeatures: [ui.FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Quãng đường ước tính',
                          style: LuxeText.caption,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ChargeBar(level: (percent ?? 0) / 100),
          ],
        ),
      ),
    );
  }
}

/// Spotlight pool and a platinum pedestal ellipse.
class _StagePainter extends CustomPainter {
  _StagePainter({required this.glow, this.light = LuxeColors.emerald});
  final double glow;
  final Color light;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    // Cyclorama: graphite wall falling to a darker floor.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, h),
          const [Color(0xFF3B3F46), Color(0xFF2B2E33), Color(0xFF1C1E22)],
          const [0.0, 0.62, 1.0],
        ),
    );
    // Top spotlight behind the vehicle: the silhouette reads against it.
    final spot = Offset(w / 2, h * 0.36);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          spot,
          w * 0.62,
          [
            Color.fromRGBO(255, 255, 255, 0.26 * glow),
            const Color.fromRGBO(255, 255, 255, 0.09),
            const Color(0x00FFFFFF),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );
    // Horizon where the wall meets the floor: a soft light band.
    final horizon = h * 0.70;
    canvas.drawRect(
      Rect.fromLTWH(0, horizon - 10, w, 20),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, horizon - 10),
          Offset(0, horizon + 10),
          const [Color(0x00FFFFFF), LuxeColors.hairline, Color(0x00FFFFFF)],
          const [0.0, 0.5, 1.0],
        ),
    );
    // Contact shadow under the wheels.
    final base = Offset(w / 2, h - 20);
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.scale(1, 0.16);
    canvas.drawCircle(
      Offset.zero,
      w * 0.36,
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, w * 0.36, const [
          Color(0x8C000000),
          Color(0x00000000),
        ]),
    );
    canvas.restore();
    // The emerald floor line of the LUXE stage, kept faint.
    canvas.drawOval(
      Rect.fromCenter(center: base, width: w * 0.62, height: 12),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          base.translate(-w * 0.31, 0),
          base.translate(w * 0.31, 0),
          [
            light.withValues(alpha: 0),
            light.withValues(alpha: 0.45 * glow),
            light.withValues(alpha: 0),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );
    // Edge vignette so the box sits inside the dark card.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w / 2, h * 0.45),
          w * 0.75,
          const [Color(0x00000000), Color(0x40000000)],
          const [0.6, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_StagePainter old) =>
      old.glow != glow || old.light != light;
}

/// Catalog photo with a soft floor reflection; falls back to the line art.
/// Platinum line-art scooter (side view); the battery under the seat fills
/// with emerald to the current level, wheels carry a spinning highlight.
class LuxeScooterArt extends StatelessWidget {
  const LuxeScooterArt({super.key, required this.level, this.spin = 0});
  final double level;
  final double spin;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      painter: _ScooterPainter(level: level.clamp(0.0, 1.0), spin: spin),
    ),
  );
}

class _ScooterPainter extends CustomPainter {
  _ScooterPainter({required this.level, required this.spin});
  final double level;
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw in a 300×160 design box, centred and scaled to fit.
    const w = 300.0, h = 160.0;
    final s = math.min(size.width / w, size.height / h);
    canvas.save();
    canvas.translate((size.width - w * s) / 2, (size.height - h * s) / 2);
    canvas.scale(s);

    final metal = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = ui.Gradient.linear(
        const Offset(0, 20),
        const Offset(300, 150),
        const [
          LuxeColors.platinumHi,
          LuxeColors.platinum,
          LuxeColors.platinumMid,
        ],
        const [0.0, 0.5, 1.0],
      );
    final glass = Paint()..color = const Color(0x12FFFFFF);

    const rear = Offset(70, 124), front = Offset(236, 124);
    const r = 30.0;

    // Body: rear fender → seat → floor → front apron.
    final body = Path()
      ..moveTo(36, 112)
      ..cubicTo(36, 86, 60, 70, 96, 68)
      ..lineTo(150, 66)
      ..cubicTo(166, 66, 170, 76, 170, 88)
      ..lineTo(170, 104)
      ..lineTo(196, 104)
      ..cubicTo(204, 84, 206, 56, 210, 36)
      ..lineTo(222, 34)
      ..cubicTo(226, 60, 236, 84, 258, 104)
      ..cubicTo(266, 112, 266, 120, 262, 124);
    canvas.drawPath(
      Path.from(body)
        ..lineTo(100, 124)
        ..close(),
      glass,
    );
    canvas.drawPath(body, metal);
    // Seat.
    final seat = Path()
      ..moveTo(84, 66)
      ..cubicTo(90, 54, 140, 52, 152, 60);
    canvas.drawPath(seat, metal..strokeWidth = 3);
    metal.strokeWidth = 2.2;
    // Handlebar + mirror + headlight.
    canvas.drawLine(const Offset(214, 36), const Offset(204, 18), metal);
    canvas.drawLine(const Offset(194, 18), const Offset(226, 16), metal);
    canvas.drawCircle(
      const Offset(232, 46),
      5,
      Paint()
        ..color = const Color(0xFFEFF6FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(const Offset(232, 46), 3, Paint()..color = Colors.white);

    // Battery under the seat, filling to the level.
    final battery = RRect.fromLTRBR(92, 78, 156, 98, const Radius.circular(5));
    canvas.drawRRect(battery, Paint()..color = const Color(0x22000000));
    if (level > 0) {
      final fill = RRect.fromLTRBR(
        battery.left + 2,
        battery.top + 2,
        battery.left + 2 + (battery.width - 4) * level,
        battery.bottom - 2,
        const Radius.circular(3),
      );
      canvas.drawRRect(
        fill.inflate(3),
        Paint()
          ..color = LuxeColors.emerald.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawRRect(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(
            fill.outerRect.topLeft,
            fill.outerRect.topRight,
            const [LuxeColors.emeraldDeep, LuxeColors.emerald],
          ),
      );
    }
    canvas.drawRRect(
      battery,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = LuxeColors.platinum.withValues(alpha: 0.7),
    );

    // Wheels with a spinning highlight.
    for (final c in [rear, front]) {
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFF101113));
      canvas.drawCircle(c, r, metal);
      canvas.drawCircle(
        c,
        r * 0.55,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = LuxeColors.platinumMid,
      );
      canvas.drawCircle(c, 3, Paint()..color = LuxeColors.platinum);
      final a = spin * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 1),
        a,
        0.9,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.55),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScooterPainter old) =>
      old.level != level || old.spin != spin;
}

/// Thin capsule battery bar with an emerald fill and a glowing head.
class _ChargeBar extends StatelessWidget {
  const _ChargeBar({required this.level});
  final double level;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: level.clamp(0.0, 1.0)),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 1200),
    curve: LuxeMotion.enter,
    builder: (context, v, _) => SizedBox(
      height: 8,
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: const Color(0x14FFFFFF),
              ),
            ),
            Container(
              width: math.max(8, c.maxWidth * v),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  colors: v < 0.2
                      ? const [Color(0xFFB45309), LuxeColors.champagne]
                      : const [LuxeColors.emeraldDeep, LuxeColors.emerald],
                ),
                boxShadow: const [
                  BoxShadow(color: LuxeColors.emeraldGlow, blurRadius: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
