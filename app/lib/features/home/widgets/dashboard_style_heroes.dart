import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/utils/number_text.dart';
import '../../../core/widgets/luxe_kit.dart';
import '../../../core/widgets/seven_segment_text.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../data/services/range_estimator.dart';
import '../../../data/services/trip_energy_model.dart';

/// What every Overview layout shows, from the vehicle's real data only
/// (QA 131): a value the owner never entered stays null and shows "—".
class HeroFigures {
  HeroFigures(VehicleModel? v, TripModelParams? learned)
    : name = v?.nickname?.trim().isNotEmpty == true
          ? v!.nickname!.trim()
          : (v?.modelName ?? 'Chưa có dữ liệu xe'),
      plate = v?.licensePlate?.trim().isNotEmpty == true
          ? v!.licensePlate!.trim()
          : null,
      percent = v?.hasBatteryData == true ? v!.currentBattery : null,
      rangeKm = v != null && v.hasBatteryData
          ? estimateRangeKm(v, learned: learned)?.round()
          : null,
      odoKm = v?.hasOdoData == true ? v!.currentOdo : null,
      soh = v?.hasSohData == true ? v!.stateOfHealth.round() : null,
      capacityWh = v != null && v.batteryCapacityWh > 0
          ? v.batteryCapacityWh
          : null,
      updatedAt = v?.batteryDataUpdatedAt;

  final String name;
  final String? plate;
  final int? percent;
  final int? rangeKm;
  final int? odoKm;
  final int? soh;
  final double? capacityWh;
  final DateTime? updatedAt;

  static String ago(DateTime? at, DateTime now) {
    if (at == null) return '—';
    final d = now.difference(at);
    if (d.inMinutes < 1) return 'vừa xong';
    if (d.inMinutes < 60) return '${d.inMinutes} phút trước';
    if (d.inHours < 24) return '${d.inHours} giờ trước';
    return '${d.inDays} ngày trước';
  }
}

/// "Đồng hồ xe": the Overview drawn like the Feliz LCD cluster — battery %
/// and its bars, estimated range, ODO, in seven-segment digits.
class LcdClusterHero extends StatelessWidget {
  const LcdClusterHero({super.key, required this.vehicle, this.learned});

  final VehicleModel? vehicle;
  final TripModelParams? learned;

  @override
  Widget build(BuildContext context) {
    final f = HeroFigures(vehicle, learned);
    final percent = f.percent;
    return Semantics(
      container: true,
      label:
          '${f.name}, pin ${percent ?? 'chưa có'} phần trăm, '
          'quãng đường ước tính ${f.rangeKm ?? 'chưa có'} km, '
          'ODO ${f.odoKm ?? 'chưa có'} km',
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('dashboard-hero-lcd'),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF101214), Color(0xFF07080A)],
          ),
          border: Border.all(color: LuxeColors.platinumLow, width: 1.4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    f.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LuxeText.eyebrow,
                  ),
                ),
                if (f.plate != null)
                  Text(
                    f.plate!,
                    style: const TextStyle(
                      color: LuxeColors.platinumMid,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SevenSegmentText(
                            percent == null ? '--' : '$percent'.padLeft(2),
                            height: 64,
                          ),
                          const SizedBox(width: 6),
                          const _LcdLabel('%', size: 18),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _BatteryBars(percent: percent),
                    ],
                  ),
                  const SizedBox(width: 28),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const _LcdLabel('CÒN ĐI ĐƯỢC'),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SevenSegmentText(
                            f.rangeKm == null ? '--' : '${f.rangeKm}',
                            height: 44,
                            color: LuxeColors.champagne,
                          ),
                          const SizedBox(width: 6),
                          const _LcdLabel('KM'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const _LcdLabel('ước tính'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(height: 1, color: LuxeColors.hairline),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const _LcdLabel('ODO'),
                  const SizedBox(width: 10),
                  SevenSegmentText(
                    f.odoKm == null ? '----' : '${f.odoKm}',
                    height: 28,
                  ),
                  const SizedBox(width: 6),
                  const _LcdLabel('KM'),
                  const SizedBox(width: 24),
                  const _LcdLabel('SOH'),
                  const SizedBox(width: 8),
                  SevenSegmentText(
                    f.soh == null ? '--' : '${f.soh}',
                    height: 28,
                  ),
                  const SizedBox(width: 4),
                  const _LcdLabel('%'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LcdLabel extends StatelessWidget {
  const _LcdLabel(this.text, {this.size = 11});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: LuxeColors.platinum,
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    ),
  );
}

/// Four bars like the Feliz battery icon: green, green, amber, red.
class _BatteryBars extends StatelessWidget {
  const _BatteryBars({required this.percent});

  final int? percent;

  @override
  Widget build(BuildContext context) {
    final p = percent;
    final lit = p == null ? 0 : (p / 25).ceil().clamp(0, 4);
    const colors = [
      Color(0xFFF87171), // lowest bar: red
      Color(0xFFF59E0B),
      LuxeColors.emerald,
      LuxeColors.emerald,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: 18,
            height: 9,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: i < lit ? colors[i] : LuxeColors.glassStrong,
            ),
          ),
      ],
    );
  }
}

/// "Gọn": no large photo, a grid of the vehicle's figures.
class CompactMetricsHero extends StatelessWidget {
  const CompactMetricsHero({super.key, required this.vehicle, this.learned});

  final VehicleModel? vehicle;
  final TripModelParams? learned;

  @override
  Widget build(BuildContext context) {
    final f = HeroFigures(vehicle, learned);
    final cells = [
      ('Pin hiện tại', f.percent == null ? '—' : '${f.percent}%', true),
      ('Quãng đường', f.rangeKm == null ? '—' : '~${f.rangeKm} km', false),
      ('Sức khỏe pin', f.soh == null ? '—' : '${f.soh}%', false),
      ('ODO', f.odoKm == null ? '—' : '${groupThousands(f.odoKm!)} km', false),
      (
        'Dung lượng pin',
        f.capacityWh == null
            ? '—'
            : '${(f.capacityWh! / 1000).toStringAsFixed(2)} kWh',
        false,
      ),
      ('Cập nhật pin', HeroFigures.ago(f.updatedAt, DateTime.now()), false),
    ];
    return LuxeGlass(
      key: const ValueKey('dashboard-hero-compact'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LuxeText.item.copyWith(fontSize: 18),
                ),
              ),
              if (f.plate != null) Text(f.plate!, style: LuxeText.label),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final perRow = box.maxWidth / scale >= 260 ? 2 : 1;
              final width = (box.maxWidth - 10 * (perRow - 1)) / perRow;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (label, value, main) in cells)
                    SizedBox(
                      width: width,
                      child: _MetricCell(
                        label: label,
                        value: value,
                        estimate: label == 'Quãng đường',
                        emphasis: main,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    this.estimate = false,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool estimate;
  final bool emphasis;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: LuxeColors.glass,
      border: Border.all(color: LuxeColors.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LuxeText.label,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              color: estimate ? LuxeColors.champagne : LuxeColors.text,
              fontSize: emphasis ? 26 : 19,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );
}

/// "Tối giản": one large battery ring, the range and a single action.
class MinimalHero extends StatelessWidget {
  const MinimalHero({
    super.key,
    required this.vehicle,
    this.learned,
    required this.onCharge,
  });

  final VehicleModel? vehicle;
  final TripModelParams? learned;
  final VoidCallback onCharge;

  @override
  Widget build(BuildContext context) {
    final f = HeroFigures(vehicle, learned);
    final percent = f.percent;
    final color = percent == null
        ? LuxeColors.platinumMid
        : percent <= 20
        ? LuxeColors.danger
        : LuxeColors.emerald;
    return Column(
      key: const ValueKey('dashboard-hero-minimal'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Center(
          child: LuxeRing(
            value: (percent ?? 0) / 100,
            size: 230,
            stroke: 12,
            color: color,
            semanticLabel: percent == null
                ? 'Chưa có số pin'
                : 'Pin $percent phần trăm',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    percent == null ? '—' : '$percent%',
                    style: const TextStyle(
                      color: LuxeColors.text,
                      fontSize: 60,
                      fontWeight: FontWeight.w200,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LuxeText.caption,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          f.rangeKm == null
              ? 'Cập nhật % pin để ước tính quãng đường'
              : 'Còn đi được ~${f.rangeKm} km (ước tính)',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: f.rangeKm == null ? LuxeColors.muted : LuxeColors.champagne,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          key: const ValueKey('dashboard-minimal-charge'),
          onPressed: onCharge,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            backgroundColor: LuxeColors.platinumHi,
            foregroundColor: LuxeColors.background,
          ),
          icon: const Icon(Icons.bolt_rounded),
          label: const Text('Sạc pin'),
        ),
      ],
    );
  }
}
