import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/utils/number_text.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/range_estimator.dart';
import '../../../data/services/trip_energy_model.dart';
import '../../../data/models/entitlement.dart';
import '../../../core/providers/entitlement_provider.dart';
import '../../battery_monitor/battery_health_screen.dart';
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
        Icons.monitor_heart_rounded,
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
                          icon: Icons.photo_camera_rounded,
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

/// ODO · efficiency · capacity (the battery itself lives in the hero).
class LuxeStatsStrip extends ConsumerWidget {
  const LuxeStatsStrip({super.key, required this.vehicle, this.learned});
  final VehicleModel? vehicle;

  /// Trained trip model: the km/% every other screen uses (QA 129).
  final TripModelParams? learned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = vehicle;
    final perPct = v == null ? null : kmPerPctFor(v, learned);
    // QA 139: the estimated capacity left (Pro) once there is one; the SoH
    // the owner typed otherwise, and said so.
    final allowed = ref.watch(
      entitlementProvider.select(
        (plan) => plan.allows(PremiumFeature.batteryHealth),
      ),
    );
    final health = allowed && v != null
        ? ref.watch(batteryHealthProvider(v.vehicleId)).valueOrNull
        : null;
    final capacity = (health?.test ?? health?.estimate)?.sohPct;
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
      capacity != null
          ? (
              Icons.battery_std_rounded,
              '${capacity.clamp(0, 100).round()}%',
              'dung lượng pin',
            )
          : (
              Icons.battery_std_rounded,
              v?.hasSohData == true ? '${v!.stateOfHealth.round()}%' : '—',
              v?.hasSohData == true ? 'SoH bạn nhập' : 'dung lượng pin',
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
                        fontSize: 19,
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

/// Battery capacity (QA 139): how much of its rated capacity the battery
/// still holds, estimated by the server from the charges whose % the owner
/// confirmed (`/api/learning/<vehicle>/health`, the "% pin chai" of Pro).
/// An estimate, so champagne; Free sees the card locked with its PRO tag.
class LuxeBatteryCapacityCard extends ConsumerWidget {
  const LuxeBatteryCapacityCard({super.key, required this.vehicleId});
  final String? vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(
      entitlementProvider.select(
        (plan) => plan.allows(PremiumFeature.batteryHealth),
      ),
    );
    final id = vehicleId;
    if (!allowed) {
      return const PremiumLocked(
        feature: PremiumFeature.batteryHealth,
        allowed: false,
        child: _CapacityShell(
          value: null,
          title: 'Dung lượng pin còn lại',
          caption: 'Ước tính từ các lần sạc của bạn, có ở gói Pro.',
        ),
      );
    }
    if (id == null) {
      return const _CapacityShell(
        value: null,
        title: 'Chưa chọn xe',
        caption: 'Chọn xe để xem dung lượng pin còn lại.',
      );
    }
    final async = ref.watch(batteryHealthProvider(id));
    final shell = async.when(
      loading: () => const _CapacityShell(
        value: null,
        title: 'Dung lượng pin còn lại',
        caption: 'Đang tải ước tính…',
      ),
      error: (_, _) => const _CapacityShell(
        value: null,
        title: 'Dung lượng pin còn lại',
        caption: 'Chưa tải được ước tính. Chạm để xem chi tiết.',
      ),
      data: (health) {
        final best = health.test ?? health.estimate;
        if (health.nominalCapacityWh == null) {
          return const _CapacityShell(
            value: null,
            title: 'Chưa tính được dung lượng',
            caption: 'Xe chưa có dung lượng danh định trong danh mục.',
          );
        }
        if (best == null) {
          return const _CapacityShell(
            value: null,
            title: 'Chưa đủ dữ liệu',
            caption: 'Sau mỗi lần sạc, nhập % trên đồng hồ xe để app ước tính.',
          );
        }
        final pct = best.sohPct.clamp(0.0, 100.0);
        return _CapacityShell(
          value: pct,
          title: pct >= 95
              ? 'Pin gần như mới'
              : pct >= 80
              ? 'Pin còn tốt'
              : pct >= 70
              ? 'Pin đã chai, nên theo dõi'
              : 'Pin chai nhiều, nên kiểm tra',
          caption:
              'Còn khoảng ${pct.round()}% dung lượng · '
              '${health.test != null ? 'theo bài kiểm tra' : '${best.confidenceLabel.toLowerCase()}, ${best.samples ?? 0} lần sạc'}',
        );
      },
    );
    return LuxePressable(
      onTap: () => BatteryHealthScreen.open(context, ref, id),
      semanticsLabel: '${shell.title}. ${shell.caption} Mở % pin chai',
      child: shell,
    );
  }
}

class _CapacityShell extends StatelessWidget {
  const _CapacityShell({
    required this.value,
    required this.title,
    required this.caption,
  });

  /// Capacity in %, or null while there is no estimate.
  final double? value;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return LuxeGlass(
      padding: const EdgeInsets.all(16),
      child: ExcludeSemantics(
        child: Row(
          children: [
            SizedBox.square(
              dimension: 84,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: (v ?? 0) / 100),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 1300),
                curve: LuxeMotion.enter,
                builder: (context, t, _) => CustomPaint(
                  painter: _RingPainter(t),
                  child: Center(
                    child: Text(
                      v == null ? '—' : '${(t * 100).round()}%',
                      style: const TextStyle(
                        color: LuxeColors.text,
                        fontSize: 22,
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
                  const Text(
                    'DUNG LƯỢNG PIN · ƯỚC TÍNH',
                    style: LuxeText.eyebrow,
                  ),
                  const SizedBox(height: 6),
                  Text(title, style: LuxeText.item),
                  const SizedBox(height: 2),
                  Text(caption, style: LuxeText.caption),
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      Flexible(
                        child: Text(
                          '% pin chai',
                          style: TextStyle(
                            color: LuxeColors.platinum,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: LuxeColors.platinum,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
    // An estimate is never emerald (QA 139); rose only when it is low.
    final color = t >= 0.7 ? LuxeColors.champagne : LuxeColors.danger;
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
      border: Border.all(color: LuxeColors.champagne.withValues(alpha: 0.33)),
      color: LuxeColors.champagne.withValues(alpha: 0.06),
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
                    fontSize: 19,
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
                  fontSize: 14,
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
