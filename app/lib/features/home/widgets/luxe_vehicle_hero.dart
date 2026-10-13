import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../data/models/vehicle_model.dart';

/// Dashboard hero: the scooter on a lit stage (the catalog photo when the
/// admin has provided one, otherwise a platinum line-art scooter whose
/// battery glows with the charge), the name, plate and the battery reading.
class LuxeVehicleHero extends StatefulWidget {
  const LuxeVehicleHero({super.key, required this.vehicle});
  final VehicleModel? vehicle;

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
      _float.repeat();
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
    final percent = v?.hasBatteryData == true
        ? (v?.lastBatteryPercent ?? v?.currentBattery)
        : v?.currentBattery;
    final efficiency = v?.defaultEfficiency;
    final range = percent != null && efficiency != null && efficiency > 0
        ? (percent * efficiency).round()
        : null;
    final image = v?.imageUrl?.trim();

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
                      Text(
                        (model ?? 'VINFAST').toUpperCase(),
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
            SizedBox(
              height: 176,
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
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 18,
                        top: 6,
                        child: Opacity(
                          opacity: e,
                          child: Transform.translate(
                            offset: Offset(24 * (1 - e), bob),
                            child: image == null || image.isEmpty
                                ? _ScooterArt(
                                    level: (percent ?? 0) / 100,
                                    spin: t,
                                  )
                                : _CatalogPhoto(
                                    url: image,
                                    fallback: _ScooterArt(
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
            const SizedBox(height: 6),
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
                          range == null ? '— km' : '~$range km',
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
  _StagePainter({required this.glow});
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.55);
    canvas.drawOval(
      Rect.fromCenter(
        center: c,
        width: size.width * 0.95,
        height: size.height * 1.1,
      ),
      Paint()
        ..shader = ui.Gradient.radial(c, size.width * 0.5, [
          Color.fromRGBO(255, 255, 255, 0.07 * glow),
          const Color(0x00FFFFFF),
        ]),
    );
    final base = Offset(size.width / 2, size.height - 14);
    canvas.drawOval(
      Rect.fromCenter(center: base, width: size.width * 0.72, height: 22),
      Paint()
        ..shader = ui.Gradient.radial(base, size.width * 0.36, [
          LuxeColors.emerald.withValues(alpha: 0.22 * glow),
          const Color(0x0034D399),
        ]),
    );
    canvas.drawOval(
      Rect.fromCenter(center: base, width: size.width * 0.6, height: 14),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          base.translate(-size.width * 0.3, 0),
          base.translate(size.width * 0.3, 0),
          const [Color(0x00FFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
          const [0.0, 0.5, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_StagePainter old) => old.glow != glow;
}

/// Catalog photo with a soft floor reflection; falls back to the line art.
class _CatalogPhoto extends StatelessWidget {
  const _CatalogPhoto({required this.url, required this.fallback});
  final String url;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    Widget photo() => Image.network(
      url,
      fit: BoxFit.contain,
      cacheWidth: 900,
      frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
        opacity: sync || frame != null ? 1 : 0,
        duration: const Duration(milliseconds: 450),
        child: child,
      ),
      errorBuilder: (_, _, _) => fallback,
    );
    return Column(
      children: [
        Expanded(flex: 5, child: photo()),
        // Mirrored reflection fading into the pedestal.
        Expanded(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (b) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
            ).createShader(b),
            child: Transform(
              alignment: Alignment.topCenter,
              transform: Matrix4.diagonal3Values(1, -1, 1),
              child: ClipRect(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: 0.25,
                  child: AspectRatio(aspectRatio: 1.8, child: photo()),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Platinum line-art scooter (side view); the battery under the seat fills
/// with emerald to the current level, wheels carry a spinning highlight.
class _ScooterArt extends StatelessWidget {
  const _ScooterArt({required this.level, required this.spin});
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
                      ? const [Color(0xFFB45309), Color(0xFFFBBF24)]
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
