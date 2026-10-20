import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../core/widgets/vehicle_picker_sheet.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/services/charge_estimator.dart';
import '../../data/services/range_estimator.dart';

/// Battery monitor: only what the app really knows (QA 129).
///
/// The scooter has no BMS link, so there is no temperature, cell data or
/// 24-hour SoC history: the old screen showed a hard-coded 25 °C, a default
/// SoH, six "N/A" tiles, and wrote a Firestore snapshot on every visit. Now
/// it shows the last % you entered (and when/how), the same range as the
/// Overview and the same charge time as the Charge tab (learned Wh per 1 %
/// and charging power).
class BatteryMonitorScreen extends ConsumerWidget {
  const BatteryMonitorScreen({super.key, this.vehicle});
  final VehicleModel? vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final given = vehicle;
    final String vehicleId = given != null
        ? given.vehicleId
        : ref.watch(selectedVehicleIdProvider);
    final async = vehicle != null
        ? AsyncValue<VehicleModel?>.data(vehicle)
        : ref.watch(vehicleProvider(vehicleId));
    final learned = vehicleId.isEmpty
        ? const LearnedModels()
        : ref.watch(learnedModelsProvider(vehicleId)).valueOrNull ??
              const LearnedModels();

    Future<void> refresh() async {
      if (vehicleId.isEmpty) return;
      ref.invalidate(vehicleProvider(vehicleId));
      ref.invalidate(learnedModelsProvider(vehicleId));
      await ref.read(learnedModelsProvider(vehicleId).future);
    }

    final v = async.valueOrNull;
    return LuxeScaffold(
      appBar: LuxeAppBar(
        actions: [
          LuxeCircleButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Làm mới',
            onPressed: async.isLoading ? null : refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: LuxeColors.emerald,
        backgroundColor: LuxeColors.raised,
        onRefresh: refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: LuxeReveal(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('GIÁM SÁT PIN', style: LuxeText.eyebrow),
                      const SizedBox(height: 6),
                      Text(
                        v?.vehicleName.isNotEmpty == true
                            ? v!.vehicleName
                            : 'Xe điện VinFast',
                        style: LuxeText.title,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (vehicleId.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: EmptyState(
                    icon: Icons.electric_moped_rounded,
                    title: 'Chưa chọn xe',
                    message: 'Chọn xe để xem mức pin và quãng đường ước tính.',
                    actionLabel: 'Chọn xe ngay',
                    onAction: () => VehiclePickerSheet.show(context, ref),
                  ),
                ),
              )
            else if (async.hasError && v == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ErrorState(
                    message:
                        'Chưa thể tải dữ liệu pin. Kiểm tra kết nối rồi thử lại.',
                    onRetry: refresh,
                  ),
                ),
              )
            else if (v == null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: LoadingSkeleton(layout: SkeletonLayout.card),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: LuxeReveal(
                    index: 1,
                    child: _CurrentBatteryCard(vehicle: v, learned: learned),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 40),
                  child: LuxeReveal(
                    index: 2,
                    child: _EstimateCard(vehicle: v, learned: learned),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Where the battery % came from, in words (never a raw code).
String batterySourceLabel(String? source) {
  final value = source ?? '';
  if (value == 'user_confirmed') return 'Bạn xác nhận sau khi sạc';
  if (value == 'smart_charge_estimated') return 'Ước tính sau phiên sạc';
  if (value.startsWith('reading_')) {
    return switch (value.substring('reading_'.length)) {
      'chat' => 'Nhập qua Pinova Bot',
      'photo' || 'dashboard' || 'ocr' => 'Quét từ đồng hồ xe',
      _ => 'Bạn nhập',
    };
  }
  return 'Bạn nhập';
}

String _when(DateTime at) {
  final local = at.toLocal();
  final now = DateTime.now();
  final hm =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  final sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  return sameDay ? hm : '$hm ${local.day}/${local.month}';
}

class _CurrentBatteryCard extends StatelessWidget {
  const _CurrentBatteryCard({required this.vehicle, required this.learned});
  final VehicleModel vehicle;
  final LearnedModels learned;

  @override
  Widget build(BuildContext context) {
    final has = vehicle.hasBatteryData;
    final percent = has ? vehicle.currentBattery.clamp(0, 100).toDouble() : 0.0;
    final accent = !has
        ? LuxeColors.platinumMid
        : percent < 20
        ? LuxeColors.danger
        : percent < 50
        ? LuxeColors.champagne
        : LuxeColors.emerald;
    final status = !has
        ? 'Chưa có số pin'
        : percent < 20
        ? 'Pin yếu, nên sạc'
        : percent < 50
        ? 'Pin trung bình'
        : 'Pin còn nhiều';
    final range = estimateRange(vehicle, learned: learned.trip);
    final updated = vehicle.batteryDataUpdatedAt;
    final soh = vehicle.hasSohData && vehicle.stateOfHealth.isFinite
        ? vehicle.stateOfHealth.clamp(0, 100).toDouble()
        : null;
    return LuxeGlass(
      radius: 26,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                'Mức pin đã ghi nhận',
                style: LuxeText.item.copyWith(fontSize: 15),
              ),
              if (has && updated != null) LuxeTag('Lúc ${_when(updated)}'),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: LuxeRing(
              value: percent / 100,
              size: 176,
              stroke: 10,
              color: accent,
              semanticLabel: has
                  ? 'Pin ${percent.round()} phần trăm, $status'
                  : status,
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: FittedBox(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        has
                            ? LuxeCountUp(
                                value: percent,
                                suffix: '%',
                                style: const TextStyle(
                                  color: LuxeColors.text,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w200,
                                  letterSpacing: -1.2,
                                ),
                              )
                            : const Text(
                                '—',
                                style: TextStyle(
                                  color: LuxeColors.text,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w200,
                                ),
                              ),
                        const SizedBox(height: 2),
                        Text(
                          status,
                          style: TextStyle(
                            color: accent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _TileGrid([
            LuxeStatTile(
              label: 'Sức khỏe pin (bạn nhập)',
              icon: Icons.health_and_safety_rounded,
              value: soh == null ? '—' : soh.round().toString(),
              unit: soh == null ? null : '%',
            ),
            LuxeStatTile(
              label: range?.source == RangeSource.learned
                  ? 'Quãng đường · đã học'
                  : 'Quãng đường · thông số xe',
              icon: Icons.route_rounded,
              accent: LuxeColors.steel,
              value: range == null ? '—' : '~${range.km.round()}',
              unit: range == null ? null : 'km',
            ),
            LuxeStatTile(
              label: 'Nguồn số pin',
              icon: Icons.edit_note_rounded,
              value: has ? batterySourceLabel(vehicle.batteryDataSource) : '—',
            ),
          ]),
          const SizedBox(height: 12),
          const Text(
            'Xe không kết nối pin (BMS) với app nên không có nhiệt độ hay dữ '
            'liệu từng cell. Cập nhật % ở Tổng quan → "Cập nhật % pin & ODO".',
            style: LuxeText.caption,
          ),
        ],
      ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({required this.vehicle, required this.learned});
  final VehicleModel vehicle;
  final LearnedModels learned;

  @override
  Widget build(BuildContext context) {
    final soc = vehicle.hasBatteryData
        ? vehicle.currentBattery.toDouble()
        : null;
    final range = estimateRange(vehicle, learned: learned.trip);
    final whPerPct = learned.whPerPct;
    final capacityWh = vehicle.batteryCapacityWh > 0
        ? vehicle.batteryCapacityWh
        : (whPerPct == null
              ? 0.0
              : whPerPct * 100 * ChargeEstimator.efficiency);
    // Same inputs as the Charge tab's plan: learned Wh/% and charging power
    // (QA 129: here ~600 W catalog gave 1 h 6 min, the Charge tab 1 h 21).
    final learnedPower = learned.powerW;
    final power = ChargeEstimator.pickPower(
      recentSessionPowers: [?learnedPower],
    );
    ChargeEstimate? charge(double target) => soc == null || capacityWh <= 0
        ? null
        : ChargeEstimator.estimate(
            currentSoc: soc,
            targetSoc: target,
            capacityWh: capacityWh,
            powerW: power.watts,
            powerSource: power.source,
            whPerPercent: whPerPct,
          );
    String chargeText(double target) {
      if (soc != null && soc >= target) return 'Đã đạt';
      final estimate = charge(target);
      return estimate == null
          ? '—'
          : '~${formatChargeDuration(estimate.duration)}';
    }

    final learnedCharge = whPerPct != null && learnedPower != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LuxeSectionLabel('Ước tính'),
        LuxeGlass(
          radius: 22,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const LuxeMedallion(
                    icon: Icons.auto_graph_rounded,
                    accent: LuxeColors.champagne,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Tầm đi & thời gian sạc',
                      style: LuxeText.item.copyWith(fontSize: 15.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _row(
                const ValueKey('monitor-range-estimate'),
                'Tầm đi còn lại',
                range == null
                    ? '—'
                    : '~${range.km.round()} km (${range.lowKm.round()}–${range.highKm.round()})',
              ),
              _row(
                const ValueKey('monitor-charge-80'),
                'Sạc tới 80%',
                chargeText(80),
              ),
              _row(
                const ValueKey('monitor-charge-100'),
                'Sạc đầy 100%',
                chargeText(100),
              ),
              const SizedBox(height: 10),
              Text(
                learnedCharge
                    ? 'Cùng mô hình với tab Sạc pin: ${whPerPct.toStringAsFixed(1)} Wh cho 1% '
                          'và ~${learnedPower.round()} W học từ các lần sạc của xe bạn.'
                    : 'Chưa học từ lần sạc nào: dùng ${power.source.label} '
                          '(~${power.watts.round()} W), sai số rộng hơn.',
                style: LuxeText.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(Key key, String label, String value) => Padding(
    key: key,
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: LuxeText.body)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: LuxeText.item.copyWith(fontSize: 15),
          ),
        ),
      ],
    ),
  );
}

/// Two columns of tiles; one column when text is enlarged.
class _TileGrid extends StatelessWidget {
  const _TileGrid(this.tiles);
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = constraints.maxWidth / scale < 300 ? 1 : 2;
      const gap = 10.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final tile in tiles) SizedBox(width: width, child: tile),
        ],
      );
    },
  );
}
