import 'package:flutter/material.dart';
import '../../core/widgets/vehicle_picker_sheet.dart';
import '../../core/widgets/empty_state.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../data/models/battery_state_model.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/models/vinfast_model_spec.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import '../../data/services/battery_state_service.dart';
import '../../data/services/charge_estimator.dart';
import '../../data/services/range_estimator.dart';

import '../../core/providers/app_providers.dart';

class BatteryMonitorScreen extends ConsumerStatefulWidget {
  final VehicleModel? vehicle;

  const BatteryMonitorScreen({super.key, this.vehicle});

  @override
  ConsumerState<BatteryMonitorScreen> createState() =>
      _BatteryMonitorScreenState();
}

class _BatteryMonitorScreenState extends ConsumerState<BatteryMonitorScreen> {
  bool _isLoading = true;
  BatteryStateModel? _currentBatteryState;
  List<BatteryStateModel> _batteryHistory = [];
  Map<String, dynamic>? _batteryStats;
  VinFastModelSpec? _spec;
  String? _error;
  bool _noVehicle = false;

  String _getVehicleId() {
    if (widget.vehicle != null) return widget.vehicle!.vehicleId;
    return ref.read(selectedVehicleIdProvider);
  }

  String _getVehicleName() {
    if (widget.vehicle != null) return widget.vehicle!.vehicleName;
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    final vehicle = ref.watch(vehicleProvider(vehicleId)).valueOrNull;
    return vehicle?.vehicleName ?? 'Xe điện VinFast';
  }

  @override
  void initState() {
    super.initState();
    _loadBatteryData();
  }

  Future<void> _loadBatteryData() async {
    final vehicleId = _getVehicleId();
    if (vehicleId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _noVehicle = true;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _noVehicle = false;
    });

    try {
      final currentState = await BatteryStateService.getCurrentBatteryState(
        vehicleId,
      );

      final history = await BatteryStateService.getBatteryHistory(
        vehicleId: vehicleId,
        limit: 24,
        timeRange: const Duration(hours: 24),
      );

      final stats = await BatteryStateService.getBatteryStats(vehicleId);
      final spec = await _loadSpec(vehicleId);

      if (!mounted) return;
      setState(() {
        _currentBatteryState = currentState;
        _batteryHistory = history;
        _batteryStats = stats;
        _spec = spec;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Chưa thể tải dữ liệu pin. Kiểm tra kết nối rồi thử lại.';
        _isLoading = false;
      });
    }
  }

  /// Catalog spec for capacity/charger power; optional, never blocks the page.
  Future<VinFastModelSpec?> _loadSpec(String vehicleId) async {
    try {
      final vehicle =
          widget.vehicle ?? ref.read(vehicleProvider(vehicleId)).valueOrNull;
      if (vehicle == null) return null;
      final repository = VehicleSpecRepository();
      final modelId = vehicle.catalogId ?? vehicle.vinfastModelId;
      if (modelId != null && modelId.isNotEmpty) {
        final spec = await repository.getSpec(modelId);
        if (spec != null) return spec;
      }
      final name = (vehicle.vinfastModelName?.isNotEmpty == true)
          ? vehicle.vinfastModelName!
          : vehicle.vehicleName;
      return await repository.matchByVehicleName(name);
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshData() async {
    await _loadBatteryData();
  }

  @override
  Widget build(BuildContext context) {
    return LuxeScaffold(
      appBar: LuxeAppBar(
        actions: [
          LuxeCircleButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Làm mới',
            onPressed: _isLoading ? null : _refreshData,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: LuxeColors.emerald,
        backgroundColor: LuxeColors.raised,
        onRefresh: _refreshData,
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
                      Text(_getVehicleName(), style: LuxeText.title),
                    ],
                  ),
                ),
              ),
            ),
            // No vehicle is a choice to make, not an error with a useless
            // "Thử lại" (Task 125).
            if (_noVehicle)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: EmptyState(
                    icon: Icons.electric_moped_rounded,
                    title: 'Chưa chọn xe',
                    message: 'Chọn xe để xem mức pin và quãng đường ước tính.',
                    actionLabel: 'Chọn xe ngay',
                    onAction: () async {
                      await VehiclePickerSheet.show(context, ref);
                      if (mounted) unawaited(_loadBatteryData());
                    },
                  ),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ErrorState(message: _error!, onRetry: _refreshData),
                ),
              )
            else if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: LoadingSkeleton(layout: SkeletonLayout.card),
                ),
              )
            else ...[
              if (_currentBatteryState != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: LuxeReveal(
                      index: 1,
                      child: _buildCurrentBatteryCard(),
                    ),
                  ),
                ),
              if (_batteryStats != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                    child: LuxeReveal(index: 2, child: _buildBatteryStats()),
                  ),
                ),
              if (_batteryHistory.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                    child: LuxeReveal(index: 3, child: _buildBatteryChart()),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 40),
                  child: LuxeReveal(index: 4, child: _buildSOCPredictionCard()),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Two columns of tiles; one column when text is enlarged.
  Widget _tileGrid(List<Widget> tiles) => LayoutBuilder(
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

  Widget _buildCurrentBatteryCard() {
    final batteryState = _currentBatteryState!;
    final safePercent = batteryState.percentage.isFinite
        ? batteryState.percentage.clamp(0.0, 100.0)
        : 0.0;
    final safeSoh = batteryState.soh.isFinite
        ? batteryState.soh.clamp(0.0, 100.0)
        : 0.0;
    final accent = _getBatteryColor(safePercent);

    return LuxeGlass(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
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
                'Trạng thái pin hiện tại',
                style: LuxeText.item.copyWith(fontSize: 15),
              ),
              LuxeTag('Cập nhật ${_formatTime(batteryState.timestamp)}'),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: LuxeRing(
              value: safePercent / 100,
              size: 176,
              stroke: 10,
              color: accent,
              semanticLabel:
                  'Pin ${safePercent.toStringAsFixed(1)} phần trăm, '
                  '${batteryState.statusText}',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: FittedBox(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LuxeCountUp(
                          value: safePercent.toDouble(),
                          decimals: 1,
                          suffix: '%',
                          style: const TextStyle(
                            color: LuxeColors.text,
                            fontSize: 34,
                            fontWeight: FontWeight.w200,
                            letterSpacing: -1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          batteryState.statusText,
                          style: TextStyle(
                            color: accent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
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
          _tileGrid([
            LuxeStatTile(
              label: 'Sức khỏe pin',
              icon: Icons.health_and_safety_rounded,
              accent: _getHealthColor(safeSoh.toDouble()),
              value: safeSoh.toStringAsFixed(1),
              numeric: safeSoh.toDouble(),
              decimals: 1,
              unit: '%',
            ),
            LuxeStatTile(
              label: 'Tầm hoạt động',
              icon: Icons.route_rounded,
              accent: LuxeColors.steel,
              value: batteryState.estimatedRange.toStringAsFixed(1),
              numeric: batteryState.estimatedRange.isFinite
                  ? batteryState.estimatedRange
                  : null,
              decimals: 1,
              unit: 'km',
            ),
            LuxeStatTile(
              label: 'Nhiệt độ',
              icon: Icons.thermostat_rounded,
              accent: _getTemperatureColor(batteryState.temp),
              value: batteryState.temp.toStringAsFixed(1),
              unit: '°C',
            ),
            LuxeStatTile(
              label: 'Nguồn',
              icon: Icons.sensors_rounded,
              value: batteryState.source ?? 'Tiêu chuẩn',
            ),
          ]),
        ],
      ),
    );
  }

  String _fmt(dynamic v) =>
      v is num && v.isFinite ? v.toStringAsFixed(1) : 'N/A';

  Widget _buildBatteryStats() {
    final stats = _batteryStats!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LuxeSectionLabel('Thống kê pin (24h)'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: _tileGrid([
            LuxeStatTile(
              label: 'SOC trung bình',
              value: _fmt(stats['avgSOC']),
              unit: '%',
              accent: LuxeColors.steel,
              icon: Icons.donut_large_rounded,
            ),
            LuxeStatTile(
              label: 'SOC thấp nhất',
              value: _fmt(stats['minSOC']),
              unit: '%',
              accent: LuxeColors.danger,
              icon: Icons.south_rounded,
            ),
            LuxeStatTile(
              label: 'SOC cao nhất',
              value: _fmt(stats['maxSOC']),
              unit: '%',
              accent: LuxeColors.emerald,
              icon: Icons.north_rounded,
            ),
            LuxeStatTile(
              label: 'Nhiệt độ TB',
              value: _fmt(stats['avgTemp']),
              unit: '°C',
              accent: LuxeColors.champagne,
              icon: Icons.thermostat_rounded,
            ),
            LuxeStatTile(
              label: 'SoH TB',
              value: _fmt(stats['avgSOH']),
              unit: '%',
              accent: _getHealthColor(
                (stats['avgSOH'] as num?)?.toDouble() ?? 0,
              ),
              icon: Icons.health_and_safety_rounded,
            ),
            LuxeStatTile(
              label: 'Xu hướng',
              value: _getTrendText(stats['consumptionTrend']),
              accent: _getTrendColor(stats['consumptionTrend']),
              icon: Icons.trending_flat_rounded,
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildBatteryChart() {
    final validHistory = _batteryHistory
        .where((s) => s.percentage.isFinite)
        .toList();
    final points = [
      for (final s in validHistory) s.percentage.clamp(0.0, 100.0).toDouble(),
    ];
    const axis = TextStyle(color: LuxeColors.dim, fontSize: 10.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LuxeSectionLabel('Biểu đồ pin (24h)'),
        LuxeGlass(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(
                    height: 180,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('100%', style: axis),
                        Text('50%', style: axis),
                        Text('0%', style: axis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LuxeSparkline(
                      points: points,
                      height: 180,
                      minY: 0,
                      maxY: 100,
                      semanticLabel:
                          'Biểu đồ pin 24 giờ, ${points.length} điểm đo, '
                          'gần nhất ${points.isEmpty ? '—' : points.last.toStringAsFixed(0)}%',
                    ),
                  ),
                ],
              ),
              if (validHistory.length >= 2) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatTime(validHistory.first.timestamp),
                        style: axis,
                      ),
                      Text(
                        _formatTime(validHistory.last.timestamp),
                        style: axis,
                      ),
                    ],
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 40),
                  child: Text(
                    'Cần ít nhất 2 điểm đo để vẽ biểu đồ.',
                    style: LuxeText.caption,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Local, display-only estimate from real data (Task 122): the shared
  /// range formula and [ChargeEstimator] with the catalog's charger power.
  /// Replaces the old "Dự đoán SOC AI" call that sent fixed sensor values.
  Widget _buildSOCPredictionCard() {
    final vehicleId = _getVehicleId();
    final vehicle =
        widget.vehicle ?? ref.watch(vehicleProvider(vehicleId)).valueOrNull;
    final soc =
        _currentBatteryState?.percentage ?? vehicle?.currentBattery.toDouble();
    final range = vehicle == null
        ? null
        : estimateRangeKm(vehicle, socOverride: soc);
    final capacityWh = (vehicle?.batteryCapacityWh ?? 0) > 0
        ? vehicle!.batteryCapacityWh
        : (_spec?.nominalCapacityWh ?? 0);
    final power = ChargeEstimator.pickPower(
      specMaxPowerW: _spec?.maxChargePowerW,
    );
    ChargeEstimate? charge(double target) => soc == null || capacityWh <= 0
        ? null
        : ChargeEstimator.estimate(
            currentSoc: soc,
            targetSoc: target,
            capacityWh: capacityWh,
            powerW: power.watts,
            powerSource: power.source,
          );
    final to80 = charge(80);
    final to100 = charge(100);
    String chargeText(double target, ChargeEstimate? estimate) {
      if (soc != null && soc >= target) return 'Đã đạt';
      if (estimate == null) return '—';
      return '~${formatChargeDuration(estimate.duration)}';
    }

    final hasAny = range != null || to80 != null || to100 != null;
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
              _estimateRow(
                key: const ValueKey('monitor-range-estimate'),
                label: 'Tầm đi còn lại',
                value: range == null ? '—' : '~${range.round()} km',
              ),
              _estimateRow(
                key: const ValueKey('monitor-charge-80'),
                label: 'Sạc tới 80%',
                value: chargeText(80, to80),
              ),
              _estimateRow(
                key: const ValueKey('monitor-charge-100'),
                label: 'Sạc đầy 100%',
                value: chargeText(100, to100),
              ),
              const SizedBox(height: 10),
              Text(
                hasAny
                    ? 'Ước tính tham khảo theo SoC, SoH, hiệu suất xe và '
                          '${power.source.label} (~${power.watts.round()} W). '
                          'Khi đang sạc, tab Sạc pin dùng công suất Shelly đo thực tế.'
                    : 'Chưa đủ dữ liệu xe (dung lượng pin, SoH, hiệu suất) '
                          'để ước tính.',
                style: LuxeText.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _estimateRow({
    required Key key,
    required String label,
    required String value,
  }) {
    return Padding(
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

  Color _getBatteryColor(double percentage) {
    if (percentage < 20) return LuxeColors.danger;
    if (percentage < 50) return LuxeColors.champagne;
    return LuxeColors.emerald;
  }

  Color _getHealthColor(double soh) {
    if (soh < 80) return LuxeColors.danger;
    if (soh < 90) return LuxeColors.champagne;
    return LuxeColors.emerald;
  }

  Color _getTemperatureColor(double temp) {
    if (temp > 40) return LuxeColors.danger;
    if (temp < 10) return LuxeColors.steel;
    return LuxeColors.emerald;
  }

  Color _getTrendColor(dynamic trend) {
    if (trend is! Map) return LuxeColors.platinumMid;
    final trendType = trend['trend'];
    if (trendType == 'decreasing') return LuxeColors.danger;
    if (trendType == 'increasing') return LuxeColors.emerald;
    return LuxeColors.steel;
  }

  String _getTrendText(dynamic trend) {
    if (trend is! Map) return 'N/A';
    final trendType = trend['trend'];
    if (trendType == 'decreasing') return 'Giảm';
    if (trendType == 'increasing') return 'Tăng';
    return 'Ổn định';
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
