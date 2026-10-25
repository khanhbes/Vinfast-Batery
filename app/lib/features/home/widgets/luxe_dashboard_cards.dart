import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/utils/number_text.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/range_estimator.dart';
import '../../../data/services/trip_energy_model.dart';
import '../../../data/models/entitlement.dart';
import '../../premium/premium_gate.dart';

/// Tinted glass orb for accented dashboard actions. Neutral icon wells use
/// the metal [LuxeMedallion] from `core/widgets/luxe_settings.dart`.
class LuxeOrb extends StatelessWidget {
  const LuxeOrb({
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
    required this.onMaintenance,
    required this.onBatteryMonitor,
    this.onTrip,
    this.tripKey,
    this.onReadDashboard,
  });

  /// Null hides the tile (trip planner off in the beta, Task 125).
  final VoidCallback? onTrip;

  /// QA 136: Lộ trình is a Pro feature; outside the plan the tile is faded
  /// and only its tag opens Pinova Premium (it used to open anyway).
  static Widget _lockFor(bool isTrip, Widget tile) => isTrip
      ? PremiumLocked(feature: PremiumFeature.tripEstimate, child: tile)
      : tile;

  /// Task 127: "% pin & ODO" from a dashboard photo or typed (full width).
  final VoidCallback? onReadDashboard;
  final VoidCallback onMaintenance;
  final VoidCallback onBatteryMonitor;
  final Key? tripKey;

  @override
  Widget build(BuildContext context) {
    final trip = onTrip;
    // Data saves to the account automatically, so a manual "Đồng bộ ngay"
    // tile contradicted Settings; Battery monitor is a real destination.
    // Emerald stays for verified states only (Task 125).
    final items = <(IconData, String, Color, VoidCallback, Key?)>[
      if (trip != null)
        (Icons.route_rounded, 'Lộ trình', LuxeColors.steel, trip, tripKey),
      (
        Icons.build_rounded,
        'Bảo dưỡng xe',
        LuxeColors.champagne,
        onMaintenance,
        null,
      ),
      (
        Icons.monitor_heart_outlined,
        'Theo dõi pin',
        LuxeColors.platinum,
        onBatteryMonitor,
        null,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final stacked = c.maxWidth / items.length < 100 || scale > 1.4;
        final tiles = [
          for (final it in items)
            _lockFor(
              it.$4 == trip,
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
                              LuxeOrb(icon: it.$1, color: it.$3, size: 40),
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
                              LuxeOrb(icon: it.$1, color: it.$3),
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
            ),
        ];
        final read = onReadDashboard;
        final reading = read == null
            ? null
            : LuxePressable(
                key: const ValueKey('quick-read-dashboard'),
                onTap: read,
                semanticsLabel: 'Cập nhật phần trăm pin và ODO',
                child: LuxeGlass(
                  radius: 20,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: const ExcludeSemantics(
                    child: Row(
                      children: [
                        LuxeOrb(
                          icon: Icons.photo_camera_outlined,
                          color: LuxeColors.steel,
                          size: 40,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cập nhật % pin & ODO',
                                style: TextStyle(
                                  color: LuxeColors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Quét đồng hồ xe hoặc nhập tay',
                                style: TextStyle(
                                  color: LuxeColors.muted,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: LuxeColors.dim,
                        ),
                      ],
                    ),
                  ),
                ),
              );
        if (stacked) {
          return Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                tiles[i],
              ],
              if (reading != null) ...[const SizedBox(height: 8), reading],
            ],
          );
        }
        final row = IntrinsicHeight(
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
        if (reading == null) return row;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [row, const SizedBox(height: 8), reading],
        );
      },
    );
  }
}

/// ODO · efficiency · SoH (the battery itself lives in the hero).
class LuxeStatsStrip extends StatelessWidget {
  const LuxeStatsStrip({super.key, required this.vehicle, this.learned});
  final VehicleModel? vehicle;

  /// Trained trip model: the km/% every other screen uses (QA 129).
  final TripModelParams? learned;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    final perPct = v == null ? null : kmPerPctFor(v, learned);
    final cells = [
      (
        Icons.speed_rounded,
        v == null ? '—' : groupThousands(v.currentOdo),
        'km ODO',
      ),
      (
        Icons.route_rounded,
        perPct == null ? '—' : perPct.toStringAsFixed(2),
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
        ? 'Chưa có số SoH'
        : value >= 90
        ? 'Pin rất khỏe'
        : value >= 80
        ? 'Pin còn tốt'
        : value >= 70
        ? 'Pin đã hao mòn, nên theo dõi'
        : 'Pin xuống cấp, nên kiểm tra';
    // The app cannot measure SoH (no BMS link): the number is what the owner
    // entered, and the card says so (QA 129: "Pin rất khỏe" read as a test).
    return LuxePressable(
      onTap: onTap,
      semanticsLabel:
          'Sức khỏe pin ${has ? '${value.round()} phần trăm theo số bạn nhập' : 'chưa có dữ liệu'}. Mở chi tiết pin',
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
                    const SizedBox(height: 2),
                    Text(
                      has
                          ? 'Theo số bạn nhập · app không đo được SoH'
                          : 'Nhập SoH trong Xe của tôi nếu bạn biết',
                      style: LuxeText.caption,
                    ),
                    const SizedBox(height: 6),
                    const Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Chi tiết pin',
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
        ? LuxeColors.champagne
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
          color: LuxeColors.champagne,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: LuxeText.caption)),
      ],
    ),
  );
}

/// Configured km per 1% (not a measured efficiency or a driving score).
class LuxeEfficiencyNote extends StatelessWidget {
  const LuxeEfficiencyNote({super.key, required this.vehicle, this.learned});
  final VehicleModel? vehicle;
  final TripModelParams? learned;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    final perPct = v == null ? null : kmPerPctFor(v, learned);
    final fromRides = learned != null && learned!.source == TripKmSource.model;
    return LuxeGlass(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LuxeOrb(icon: Icons.tune_rounded, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fromRides
                      ? 'Hiệu suất học từ chuyến đi'
                      : 'Thông số quãng đường cơ sở',
                  style: TextStyle(
                    color: LuxeColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  perPct != null
                      ? '${perPct.toStringAsFixed(2)} km / 1% pin'
                      : 'Chưa có dữ liệu cấu hình',
                  style: const TextStyle(
                    color: LuxeColors.platinum,
                    fontSize: 18,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  fromRides
                      ? 'Trung bình trên ${learned!.samples} chuyến thật của bạn; mọi màn ước tính quãng đường dùng cùng số này.'
                      : 'Thông số dòng xe dùng để ước tính quãng đường. Không phải hiệu suất đo thực tế hay điểm đánh giá lái xe.',
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
        const LuxeOrb(
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
