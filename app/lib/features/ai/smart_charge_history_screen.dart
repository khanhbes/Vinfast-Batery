import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/smart_charge_history.dart';
import '../../data/models/smart_charging_session.dart';
import 'controllers/smart_charging_controller.dart';

class SmartChargeHistoryScreen extends StatefulWidget {
  const SmartChargeHistoryScreen({
    super.key,
    required this.controller,
    this.initialItems = const [],
    this.initialSessionId,
    this.onPendingTargetConsumed,
  });

  final SmartChargingController controller;
  final List<SmartChargingSession> initialItems;
  final String? initialSessionId;
  final VoidCallback? onPendingTargetConsumed;

  @override
  State<SmartChargeHistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<SmartChargeHistoryScreen> {
  late List<SmartChargingSession> _items = [...widget.initialItems];
  ChargingStrategy? _filter;
  String? _cursor;
  String? _error;
  bool _allVehicles = false;
  bool _loading = true;
  bool _loadingMore = false;
  Timer? _liveTimer;
  bool _openedPending = false;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _liveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_items.any((item) => !item.state.isTerminal)) _load(reset: true);
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
      _openPendingIfAvailable();
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final page = await widget.controller.getHistoryPage(
        cursor: reset ? null : _cursor,
        strategy: _filter,
        allVehicles: _allVehicles,
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _cursor = page.nextCursor;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Không thể đồng bộ lịch sử sạc.');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _openPendingIfAvailable() {
    final target = widget.initialSessionId;
    if (_openedPending || target == null || !mounted) return;
    final session = _items.where((item) => item.sessionId == target).firstOrNull;
    if (session == null) return;
    _openedPending = true;
    widget.onPendingTargetConsumed?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SmartChargeSessionDetailScreen(
          controller: widget.controller,
          session: session,
        ),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử Smart Charge')),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              sliver: SliverToBoxAdapter(child: _filters()),
            ),
            if (_loading && _items.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _items.isEmpty)
              SliverFillRemaining(child: _errorState())
            else if (_items.isEmpty)
              const SliverFillRemaining(child: _EmptyHistory())
            else ...[
              if (_error != null)
                SliverToBoxAdapter(
                  child: _StaleNotice(
                    message: _error!,
                    onRetry: () => _load(reset: true),
                  ),
                ),
              SliverList.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, index) => _HistoryRow(
                  session: _items[index],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SmartChargeSessionDetailScreen(
                        controller: widget.controller,
                        session: _items[index],
                      ),
                    ),
                  ),
                  onHide: () => _hide(_items[index]),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _cursor == null
                      ? const Center(
                          child: Text('Đã hiển thị toàn bộ phiên sạc'),
                        )
                      : OutlinedButton(
                          onPressed: _loadingMore
                              ? null
                              : () => _load(reset: false),
                          child: _loadingMore
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('TẢI THÊM'),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filters() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, label: Text('Xe này')),
          ButtonSegment(value: true, label: Text('Tất cả xe')),
        ],
        selected: {_allVehicles},
        onSelectionChanged: (value) {
          _allVehicles = value.first;
          _cursor = null;
          _load(reset: true);
        },
      ),
      const SizedBox(height: 8),
      SegmentedButton<ChargingStrategy?>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: null, label: Text('Tất cả')),
          ButtonSegment(value: ChargingStrategy.aiTarget, label: Text('Sạc AI')),
          ButtonSegment(value: ChargingStrategy.manualTimed, label: Text('Thủ công')),
        ],
        selected: {_filter},
        onSelectionChanged: (value) {
          _filter = value.first;
          _cursor = null;
          _load(reset: true);
        },
      ),
    ],
  );

  Widget _errorState() => ListView(
    children: [
      const SizedBox(height: 120),
      Icon(
        Icons.cloud_off_rounded,
        size: 44,
        color: Theme.of(context).colorScheme.outline,
      ),
      const SizedBox(height: 12),
      Center(child: Text(_error!)),
      Center(
        child: TextButton(
          onPressed: () => _load(reset: true),
          child: const Text('THỬ LẠI'),
        ),
      ),
    ],
  );

  Future<void> _hide(SmartChargingSession session) async {
    if (!session.state.isTerminal) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ẩn phiên sạc?'),
        content: const Text(
          'Phiên sẽ được ẩn khỏi lịch sử thường. Dữ liệu gốc vẫn được giữ lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('HỦY'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ẨN PHIÊN'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.hideSession(session.sessionId);
      if (mounted) {
        setState(
          () => _items.removeWhere((item) => item.sessionId == session.sessionId),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã ẩn phiên khỏi lịch sử.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể ẩn phiên: $error')),
        );
      }
    }
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const SizedBox(height: 120),
      Icon(
        Icons.electric_bolt_outlined,
        size: 48,
        color: Theme.of(context).colorScheme.outline,
      ),
      const SizedBox(height: 12),
      const Center(child: Text('Chưa có phiên Smart Charge hoàn tất')),
      const SizedBox(height: 6),
      Center(
        child: Text(
          'Phiên sạc sẽ xuất hiện ở đây sau khi relay OFF được xác minh.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}

class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text('$message Đang hiển thị dữ liệu gần nhất.')),
        TextButton(onPressed: onRetry, child: const Text('THỬ LẠI')),
      ],
    ),
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.session,
    required this.onTap,
    required this.onHide,
  });
  final SmartChargingSession session;
  final VoidCallback onTap;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final duration = (session.stoppedAt ?? session.updatedAt).difference(
      session.startedAt ?? session.createdAt,
    );
    return Semantics(
      button: true,
      label:
          'Chi tiết phiên sạc ${DateFormat('dd/MM/yyyy').format(session.createdAt)}',
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onTap,
        title: Row(
          children: [
            Expanded(
              child: Text(
                session.strategy == ChargingStrategy.manualTimed
                    ? 'Sạc thủ công'
                    : 'Sạc theo AI',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              _energy(session.energyUsedWh),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (!session.state.isTerminal) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'ĐANG SẠC',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${DateFormat('dd/MM · HH:mm').format(session.createdAt.toLocal())}  ·  '
            '${session.startSoc.toStringAsFixed(0)} → Mục tiêu ${session.targetSoc.toStringAsFixed(0)}%  ·  '
            '${!session.state.isTerminal ? '${_duration(session.remaining())} còn lại' : _duration(duration)}',
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onLongPress: session.state.isTerminal ? onHide : null,
      ),
    );
  }
}

enum _ChartMetric { power, voltage, current, temperature, energy }

class SmartChargeSessionDetailScreen extends StatefulWidget {
  const SmartChargeSessionDetailScreen({
    super.key,
    required this.controller,
    required this.session,
  });
  final SmartChargingController controller;
  final SmartChargingSession session;

  @override
  State<SmartChargeSessionDetailScreen> createState() => _DetailState();
}

class _DetailState extends State<SmartChargeSessionDetailScreen> {
  List<SmartChargeTelemetryPoint>? _points;
  SmartChargeEnergySummary? _summary;
  String? _error;
  _ChartMetric _metric = _ChartMetric.power;
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _load();
    if (!widget.session.state.isTerminal) {
      _liveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final points = await widget.controller.getTelemetry(
        widget.session.sessionId,
      );
      if (!mounted) return;
      setState(() {
        _points = points;
        _summary = SmartChargeEnergySummary.calculate(
          session: widget.session,
          points: points,
        );
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Không thể tải dữ liệu biểu đồ.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = (widget.session.stoppedAt ?? widget.session.updatedAt)
        .difference(widget.session.startedAt ?? widget.session.createdAt);
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết phiên sạc')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            widget.session.strategy == ChargingStrategy.manualTimed
                ? 'Sạc thủ công'
                : 'Sạc theo AI',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (!widget.session.state.isTerminal) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: const Icon(Icons.bolt_rounded, size: 18),
                label: Text(
                  'ĐANG SẠC · Mục tiêu ${widget.session.targetSoc.round()}%',
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '${DateFormat('dd/MM/yyyy · HH:mm').format(widget.session.createdAt.toLocal())}  ·  ${_duration(duration)}',
          ),
          const SizedBox(height: 20),
          _kpis(),
          const SizedBox(height: 24),
          Text(
            'Diễn biến phiên sạc',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Chạm và kéo trên biểu đồ để xem từng thời điểm.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _metricSelector(),
          const SizedBox(height: 14),
          SizedBox(height: 250, child: _chart()),
          const SizedBox(height: 24),
          _technicalSummary(),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _confirmSoc,
            icon: const Icon(Icons.battery_saver_rounded),
            label: const Text('XÁC NHẬN SOC THỰC TẾ KHI KẾT THÚC'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: widget.session.state.isTerminal ? _privacyErase : null,
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('XÓA VĨNH VIỄN DỮ LIỆU PHIÊN'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Các chỉ số pin là ước tính, không phải dữ liệu BMS. Dung lượng khả dụng chỉ hiện khi phiên đủ chất lượng.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpis() {
    final summary = _summary;
    final values = [
      ('Điện từ lưới', summary == null ? '—' : _energy(summary.gridEnergyWh)),
      (
        'Ước tính vào pin',
        summary == null
            ? '—'
            : '${_energy(summary.estimatedStoredWh)} ước tính',
      ),
      (
        'Còn trong pin',
        summary?.estimatedRemainingWh == null
            ? '—'
            : '${_energy(summary!.estimatedRemainingWh!)} ước tính',
      ),
      (
        'Dung lượng khả dụng',
        summary?.estimatedUsableCapacityWh == null
            ? 'Cần xác nhận SOC'
            : '${_energy(summary!.estimatedUsableCapacityWh!)} ước tính',
      ),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 16,
      children: [
        for (final value in values)
          SizedBox(
            width: (MediaQuery.sizeOf(context).width - 44) / 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value.$1, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 3),
                Text(
                  value.$2,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _metricSelector() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SegmentedButton<_ChartMetric>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: _ChartMetric.power, label: Text('W')),
        ButtonSegment(value: _ChartMetric.voltage, label: Text('V')),
        ButtonSegment(value: _ChartMetric.current, label: Text('A')),
        ButtonSegment(value: _ChartMetric.temperature, label: Text('°C')),
        ButtonSegment(value: _ChartMetric.energy, label: Text('Wh')),
      ],
      selected: {_metric},
      onSelectionChanged: (value) => setState(() => _metric = value.first),
    ),
  );

  Widget _chart() {
    if (_points == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return Center(child: Text(_error!));
    if (_points!.isEmpty) {
      return const Center(child: Text('Phiên này chưa có telemetry chi tiết.'));
    }
    double read(SmartChargeTelemetryPoint point) => switch (_metric) {
      _ChartMetric.power => point.powerAverageW,
      _ChartMetric.voltage => point.voltageV,
      _ChartMetric.current => point.currentA,
      _ChartMetric.temperature => point.temperatureC ?? 0,
      _ChartMetric.energy => point.energyWh - _points!.first.energyWh,
    };
    final spots = _points!
        .map((point) => FlSpot(point.elapsedSeconds / 60, max(0, read(point))))
        .toList();
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      child: LineChart(
        key: ValueKey(_metric),
        LineChartData(
          minY: 0,
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) => Text(
                  '${value.round()}m',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 42),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (items) => items
                  .map(
                    (item) => LineTooltipItem(
                      item.y.toStringAsFixed(1),
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: color,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _technicalSummary() {
    final s = _summary;
    final rows = <(String, String)>[
      (
        'Công suất TB / đỉnh',
        s == null
            ? '—'
            : '${s.averagePowerW.toStringAsFixed(0)} / ${s.peakPowerW.toStringAsFixed(0)} W',
      ),
      (
        'Điện áp / dòng TB',
        s == null
            ? '—'
            : '${s.averageVoltageV.toStringAsFixed(1)} V · ${s.averageCurrentA.toStringAsFixed(2)} A',
      ),
      (
        'Nhiệt độ cao nhất',
        s?.maximumTemperatureC == null
            ? '—'
            : '${s!.maximumTemperatureC!.toStringAsFixed(1)} °C',
      ),
      (
        'Độ phủ telemetry',
        s == null
            ? '—'
            : '${(s.coverageRatio * 100).round()}% · ${s.sampleCount} điểm',
      ),
      (
        'Dừng sạc',
        widget.session.stopReason?.wireValue ?? widget.session.state.wireValue,
      ),
      (
        'Thiết bị / kết nối',
        '${widget.session.deviceId ?? 'Shelly'} · ${widget.session.transport ?? '—'}',
      ),
      (
        'Model AI',
        '${widget.session.modelVersion} · ${widget.session.predictionSource}',
      ),
    ];
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.$1,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Flexible(
                  child: Text(
                    row.$2,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _confirmSoc() async {
    final controller = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SOC thực tế cuối phiên'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            suffixText: '%',
            hintText: 'Ví dụ: 80',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('HỦY'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('XÁC NHẬN'),
          ),
        ],
      ),
    );
    if (value == null) return;
    try {
      final summary = await widget.controller.confirmActualEndSoc(
        widget.session,
        value,
      );
      if (mounted) setState(() => _summary = summary);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _privacyErase() async {
    final input = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa vĩnh viễn phiên sạc?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Thao tác này xóa summary, telemetry và không thể hoàn tác.'),
            const SizedBox(height: 12),
            SelectableText(widget.session.sessionId,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: input,
              decoration: const InputDecoration(labelText: 'Nhập mã phiên để xác nhận'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('HỦY')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.text.trim() == widget.session.sessionId),
            child: const Text('XÓA VĨNH VIỄN'),
          ),
        ],
      ),
    );
    final code = input.text.trim();
    input.dispose();
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.privacyEraseSession(widget.session.sessionId, code);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể xóa dữ liệu: $error')),
        );
      }
    }
  }
}

String _energy(double wh) => wh >= 1000
    ? '${(wh / 1000).toStringAsFixed(2)} kWh'
    : '${wh.toStringAsFixed(0)} Wh';

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  return hours == 0
      ? '$minutes phút'
      : '${hours}g ${minutes.toString().padLeft(2, '0')}p';
}
