import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../data/models/vehicle_model.dart';

/// Medallion icon on glass (shared look for dashboard tiles).
class LuxeMedallion extends StatelessWidget {
  const LuxeMedallion({
    super.key,
    required this.icon,
    this.color = LuxeColors.platinum,
    this.size = 44,
  });
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        center: const Alignment(-0.3, -0.4),
        colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.06)],
      ),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Icon(icon, size: size * 0.46, color: color),
  );
}

/// Pressable glass tile with a gentle press-scale.
class LuxePressable extends StatefulWidget {
  const LuxePressable({
    super.key,
    required this.child,
    required this.onTap,
    this.radius = 20,
    this.semanticsLabel,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final String? semanticsLabel;

  @override
  State<LuxePressable> createState() => _LuxePressableState();
}

class _LuxePressableState extends State<LuxePressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.semanticsLabel,
    child: GestureDetector(
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: widget.onTap == null
          ? null
          : (_) => setState(() => _down = false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down && !MediaQuery.disableAnimationsOf(context) ? 0.97 : 1,
        duration: const Duration(milliseconds: 140),
        child: widget.child,
      ),
    ),
  );
}

class LuxeQuickActions extends StatelessWidget {
  const LuxeQuickActions({
    super.key,
    required this.onTrip,
    required this.onMaintenance,
    required this.onSync,
    this.tripKey,
  });

  final VoidCallback onTrip;
  final VoidCallback onMaintenance;
  final VoidCallback onSync;
  final Key? tripKey;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        Icons.route_rounded,
        'Lộ trình sạc',
        LuxeColors.emerald,
        onTrip,
        tripKey,
      ),
      (
        Icons.build_rounded,
        'Bảo dưỡng xe',
        const Color(0xFFE2B654),
        onMaintenance,
        null,
      ),
      (Icons.sync_rounded, 'Đồng bộ ngay', LuxeColors.platinum, onSync, null),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final stacked = c.maxWidth / 3 < 100 || scale > 1.4;
        final tiles = [
          for (final it in items)
            LuxePressable(
              key: it.$5,
              onTap: it.$4,
              semanticsLabel: it.$2,
              child: LuxeGlass(
                radius: 20,
                padding: stacked
                    ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
                    : const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                child: ExcludeSemantics(
                  child: stacked
                      ? Row(
                          children: [
                            LuxeMedallion(icon: it.$1, color: it.$3, size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                it.$2,
                                style: const TextStyle(
                                  color: LuxeColors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: LuxeColors.dim,
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            LuxeMedallion(icon: it.$1, color: it.$3),
                            const SizedBox(height: 10),
                            Text(
                              it.$2,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: LuxeColors.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
        ];
        if (stacked) {
          return Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                tiles[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// ODO · efficiency · SoH (the battery itself lives in the hero).
class LuxeStatsStrip extends StatelessWidget {
  const LuxeStatsStrip({super.key, required this.vehicle});
  final VehicleModel? vehicle;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    final effOk =
        v != null &&
        v.hasEfficiencyData &&
        v.defaultEfficiency.isFinite &&
        v.defaultEfficiency > 0;
    final cells = [
      (Icons.speed_rounded, v == null ? '—' : _group(v.currentOdo), 'km ODO'),
      (
        Icons.route_rounded,
        effOk ? v.defaultEfficiency.toStringAsFixed(2) : '—',
        'km / 1% pin',
      ),
      (
        Icons.favorite_rounded,
        v?.hasSohData == true ? '${v!.stateOfHealth.round()}%' : '—',
        'sức khỏe pin',
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: LuxeGlass(
              radius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(cells[i].$1, size: 16, color: LuxeColors.platinumMid),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      cells[i].$2,
                      style: const TextStyle(
                        color: LuxeColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w300,
                        fontFeatures: [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Text(
                    cells[i].$3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: LuxeColors.dim,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _group(int km) {
    final s = km.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// Battery health: SoH on a platinum ring, tap for cell details.
class LuxeBatteryHealthCard extends StatelessWidget {
  const LuxeBatteryHealthCard({
    super.key,
    required this.soh,
    required this.onTap,
  });
  final double? soh;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final has = soh != null && soh!.isFinite;
    final value = has ? soh!.clamp(0.0, 100.0) : 0.0;
    final verdict = !has
        ? 'Cần thêm dữ liệu xe để đánh giá'
        : value >= 90
        ? 'Pin rất khỏe'
        : value >= 80
        ? 'Pin còn tốt'
        : value >= 70
        ? 'Pin đã hao mòn, nên theo dõi'
        : 'Pin xuống cấp, nên kiểm tra';
    return LuxePressable(
      onTap: onTap,
      semanticsLabel:
          'Sức khỏe pin ${has ? '${value.round()} phần trăm' : 'chưa có dữ liệu'}. Mở chi tiết cell pin',
      child: LuxeGlass(
        padding: const EdgeInsets.all(16),
        child: ExcludeSemantics(
          child: Row(
            children: [
              SizedBox.square(
                dimension: 84,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: value / 100),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 1300),
                  curve: LuxeMotion.enter,
                  builder: (context, t, _) => CustomPaint(
                    painter: _RingPainter(t),
                    child: Center(
                      child: Text(
                        has ? '${(t * 100).round()}' : '—',
                        style: const TextStyle(
                          color: LuxeColors.text,
                          fontSize: 24,
                          fontWeight: FontWeight.w300,
                          fontFeatures: [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SỨC KHỎE PIN · SoH', style: LuxeText.eyebrow),
                    const SizedBox(height: 6),
                    Text(
                      verdict,
                      style: const TextStyle(
                        color: LuxeColors.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Chi tiết cell pin',
                            style: TextStyle(
                              color: LuxeColors.emerald,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: LuxeColors.emerald,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 5;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = const Color(0x14FFFFFF),
    );
    // Fine ticks.
    for (var i = 0; i < 40; i++) {
      final a = i / 40 * 2 * math.pi;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        c + d * (r + 3.5),
        c + d * (r + 5.5),
        Paint()
          ..strokeWidth = 1
          ..color = const Color(0x22FFFFFF),
      );
    }
    if (t <= 0) return;
    final sweep = 2 * math.pi * t;
    final color = t >= 0.8
        ? LuxeColors.emerald
        : t >= 0.7
        ? const Color(0xFFFBBF24)
        : LuxeColors.danger;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.sweep(
          c,
          [color.withValues(alpha: 0.5), color],
          null,
          TileMode.clamp,
          -math.pi / 2,
          -math.pi / 2 + sweep,
        ),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}

/// Compact "needs data" note instead of a full warning card.
class LuxeDataHint extends StatelessWidget {
  const LuxeDataHint({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0x55FBBF24)),
      color: const Color(0x0FFBBF24),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: Color(0xFFFBBF24),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: LuxeText.caption)),
      ],
    ),
  );
}

/// Configured km per 1% (not a measured efficiency or a driving score).
class LuxeEfficiencyNote extends StatelessWidget {
  const LuxeEfficiencyNote({super.key, required this.vehicle});
  final VehicleModel? vehicle;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    final valid =
        v != null &&
        v.hasEfficiencyData &&
        v.defaultEfficiency.isFinite &&
        v.defaultEfficiency > 0;
    return LuxeGlass(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LuxeMedallion(icon: Icons.tune_rounded, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Thông số quãng đường cơ sở',
                  style: TextStyle(
                    color: LuxeColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  valid
                      ? '${v.defaultEfficiency.toStringAsFixed(2)} km / 1% pin'
                      : 'Chưa có dữ liệu cấu hình',
                  style: const TextStyle(
                    color: LuxeColors.platinum,
                    fontSize: 18,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Thông số cấu hình dùng để ước tính quãng đường. Không phải hiệu suất đo thực tế hay điểm đánh giá lái xe.',
                  style: LuxeText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Prompt shown while the Shelly charger setup was skipped in onboarding.
class LuxeShellyPrompt extends StatelessWidget {
  const LuxeShellyPrompt({super.key, required this.onSetup});
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) => LuxeGlass(
    selected: true,
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        const LuxeMedallion(
          icon: Icons.power_rounded,
          color: LuxeColors.emerald,
          size: 40,
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thiết lập bộ sạc Shelly',
                style: TextStyle(
                  color: LuxeColors.text,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Hẹn giờ sạc và tự ngắt an toàn bằng rơ-le.',
                style: LuxeText.caption,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onSetup,
          style: TextButton.styleFrom(foregroundColor: LuxeColors.emerald),
          child: const Text('Thiết lập'),
        ),
      ],
    ),
  );
}
