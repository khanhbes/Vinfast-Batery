import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/smart_charge_history.dart';
import '../../data/models/smart_charge_cost.dart';
import '../../data/models/smart_charging_session.dart';
import '../../core/widgets/app_popup.dart';
import 'widgets/smart_charge_cockpit_theme.dart';
import '../../core/theme/cockpit_design_system.dart';
import 'controllers/smart_charging_controller.dart';

class SmartChargeHistoryScreen extends StatefulWidget {
  const SmartChargeHistoryScreen({
    super.key,
    required this.controller,
    this.initialItems = const [],
    this.initialSessionId,
    this.onPendingTargetConsumed,
    this.embedded = false,
  });

  final SmartChargingController controller;
  final List<SmartChargingSession> initialItems;
  final String? initialSessionId;
  final VoidCallback? onPendingTargetConsumed;
  final bool embedded;

  @override
  State<SmartChargeHistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<SmartChargeHistoryScreen> {
  late List<SmartChargingSession> _items = [...widget.initialItems];
  ChargingStrategy? _filter;
  SmartChargeHistorySessionFilter _statusFilter =
      SmartChargeHistorySessionFilter.all;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTimeRange? _customRange;
  String? _cursor;
  String? _error;
  bool _allVehicles = false;
  bool _loading = true;
  bool _loadingMore = false;
  int _visibleCount = 20;
  Timer? _liveTimer;
  bool _openedPending = false;

  DateTime get _monthEnd => DateTime(
    _selectedMonth.month == 12 ? _selectedMonth.year + 1 : _selectedMonth.year,
    _selectedMonth.month == 12 ? 1 : _selectedMonth.month + 1,
  );

  DateTime get _rangeStart => _customRange?.start ?? _selectedMonth;
  DateTime get _rangeEnd => _customRange == null
      ? _monthEnd
      : DateTime(
          _customRange!.end.year,
          _customRange!.end.month,
          _customRange!.end.day + 1,
        );

  List<SmartChargingSession> get _filteredItems => _items.where((session) {
    if (!session.state.isTerminal) return false;
    return SmartChargeHistoryQuery(
      vehicleId: session.vehicleId,
      allVehicles: true,
      strategy: _filter,
      status: _statusFilter,
      from: _rangeStart,
      to: _rangeEnd,
    ).matches(session);
  }).toList();

  SmartChargingSession? get _activeSession =>
      _items.where((item) => !item.state.isTerminal).firstOrNull;

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
        _visibleCount = 20;
      });
      _openPendingIfAvailable();
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final page = await widget.controller.getHistoryPage(
        limit: 100,
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
    final session = _items
        .where((item) => item.sessionId == target)
        .firstOrNull;
    if (session == null) return;
    _openedPending = true;
    widget.onPendingTargetConsumed?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SmartChargeSessionDetailScreen(
            controller: widget.controller,
            session: session,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredItems;
    final shown = visible.take(_visibleCount).toList();
    final summary = SmartChargeHistorySummary.calculate(
      visible,
      from: _rangeStart,
      to: _rangeEnd,
    );
    return SmartChargeCockpitTheme(
      child: Scaffold(
        appBar: widget.embedded
            ? null
            : AppBar(title: const Text('Lịch sử Smart Charge')),
        body: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: _HistoryHeader(onExport: _export),
                ),
              ),
              if (_activeSession != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: _ActiveHistoryCard(
                      session: _activeSession!,
                      powerW: widget
                          .controller
                          .currentUiState
                          .chargerStatus
                          ?.powerW,
                      onTap: () => _openDetail(_activeSession!),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: _MonthlySummary(
                    month: _selectedMonth,
                    range: _customRange,
                    summary: summary,
                    onPrevious: _customRange == null
                        ? () => _changeMonth(-1)
                        : null,
                    onNext:
                        _customRange != null ||
                            _monthEnd.isAfter(DateTime.now())
                        ? null
                        : () => _changeMonth(1),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                sliver: SliverToBoxAdapter(child: _filters()),
              ),
              if (_loading && _items.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _items.isEmpty)
                SliverFillRemaining(child: _errorState())
              else if (visible.isEmpty && _activeSession == null)
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
                  itemCount: shown.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) => _HistoryRow(
                    session: shown[index],
                    onTap: () => _openDetail(shown[index]),
                    onHide: () => _hide(shown[index]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _cursor == null && shown.length >= visible.length
                        ? const Center(
                            child: Text('Đã hiển thị toàn bộ phiên sạc'),
                          )
                        : OutlinedButton(
                            onPressed: _loadingMore
                                ? null
                                : () {
                                    if (shown.length < visible.length) {
                                      setState(() => _visibleCount += 20);
                                    } else {
                                      _load(reset: false);
                                    }
                                  },
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
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range_rounded),
              label: Text(
                _customRange == null
                    ? 'CHỌN KHOẢNG NGÀY'
                    : '${DateFormat('dd/MM').format(_customRange!.start)} – ${DateFormat('dd/MM/yyyy').format(_customRange!.end)}',
              ),
            ),
          ),
          if (_customRange != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Trở về tháng hiện tại',
              onPressed: () => setState(() {
                _customRange = null;
                _visibleCount = 20;
              }),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ],
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip('Tất cả', _filter == null, () => _setStrategy(null)),
            _filterChip(
              'Sạc AI',
              _filter == ChargingStrategy.aiTarget,
              () => _setStrategy(ChargingStrategy.aiTarget),
            ),
            _filterChip(
              'Thủ công',
              _filter == ChargingStrategy.manualTimed,
              () => _setStrategy(ChargingStrategy.manualTimed),
            ),
            _filterChip(
              'Hoàn thành',
              _statusFilter == SmartChargeHistorySessionFilter.completed,
              () => _setStatus(SmartChargeHistorySessionFilter.completed),
            ),
            _filterChip(
              'Dừng sớm',
              _statusFilter == SmartChargeHistorySessionFilter.stoppedEarly,
              () => _setStatus(SmartChargeHistorySessionFilter.stoppedEarly),
            ),
            _filterChip(
              'Partial',
              _statusFilter == SmartChargeHistorySessionFilter.partial,
              () => _setStatus(SmartChargeHistorySessionFilter.partial),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _filterChip(String label, bool selected, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );

  void _setStrategy(ChargingStrategy? value) => setState(() {
    _filter = value;
    _visibleCount = 20;
    if (value != null) _statusFilter = SmartChargeHistorySessionFilter.all;
  });

  void _setStatus(SmartChargeHistorySessionFilter value) => setState(() {
    _visibleCount = 20;
    _statusFilter = _statusFilter == value
        ? SmartChargeHistorySessionFilter.all
        : value;
  });

  void _changeMonth(int delta) => setState(() {
    _customRange = null;
    _visibleCount = 20;
    _selectedMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + delta,
    );
  });

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: _customRange,
      helpText: 'Chọn khoảng lịch sử sạc',
      saveText: 'ÁP DỤNG',
    );
    if (selected == null || !mounted) return;
    if (selected.duration.inDays > 366) {
      AppPopup.showWarning(
        'Khoảng thời gian quá dài',
        detail: 'Mỗi lần xem hoặc xuất báo cáo tối đa 12 tháng.',
      );
      return;
    }
    setState(() {
      _customRange = selected;
      _visibleCount = 20;
    });
  }

  void _openDetail(SmartChargingSession session) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .72),
    builder: (_) => FractionallySizedBox(
      heightFactor: .96,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SmartChargeSessionDetailScreen(
          controller: widget.controller,
          session: session,
        ),
      ),
    ),
  );

  Future<void> _export() async {
    final format = await showModalBottomSheet<ChargeReportFormat>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Xuất báo cáo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                '${_customRange == null ? DateFormat('MM/yyyy').format(_selectedMonth) : '${DateFormat('dd/MM/yyyy').format(_customRange!.start)} – ${DateFormat('dd/MM/yyyy').format(_customRange!.end)}'} · ${_allVehicles ? 'Tất cả xe' : 'Xe đang chọn'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, ChargeReportFormat.pdf),
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('XUẤT PDF'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, ChargeReportFormat.csv),
                icon: const Icon(Icons.table_view_rounded),
                label: const Text('XUẤT CSV'),
              ),
            ],
          ),
        ),
      ),
    );
    if (format == null) return;
    try {
      final result = await widget.controller.exportHistory(
        ChargeReportRequest(
          format: format,
          from: _rangeStart,
          to: _rangeEnd,
          allVehicles: _allVehicles,
          vehicleId: _allVehicles
              ? null
              : widget.controller.currentUiState.draft.vehicleId,
        ),
      );
      AppPopup.showSuccess(
        'Đã tạo báo cáo',
        detail: '${result.sessionCount} phiên · đã mở bảng chia sẻ Android.',
      );
    } on Object catch (error) {
      AppPopup.showError('Không thể xuất báo cáo', detail: '$error');
    }
  }

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
          () =>
              _items.removeWhere((item) => item.sessionId == session.sessionId),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã ẩn phiên khỏi lịch sử.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không thể ẩn phiên: $error')));
      }
    }
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.onExport});
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lịch sử sạc điện',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              'Phiên sạc, điện năng và chi phí đã đo.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SmartChargeCockpitColors.muted,
              ),
            ),
          ],
        ),
      ),
      OutlinedButton.icon(
        onPressed: onExport,
        icon: const Icon(Icons.ios_share_rounded, size: 18),
        label: const Text('Xuất'),
      ),
    ],
  );
}

class _ActiveHistoryCard extends StatelessWidget {
  const _ActiveHistoryCard({
    required this.session,
    required this.onTap,
    this.powerW,
  });
  final SmartChargingSession session;
  final VoidCallback onTap;
  final double? powerW;

  @override
  Widget build(BuildContext context) {
    final cost = session.estimatedCostVnd == null
        ? 'Chưa đặt giá điện'
        : '${NumberFormat.decimalPattern('vi_VN').format(session.estimatedCostVnd)} đ tạm tính';
    return Semantics(
      button: true,
      label: 'Phiên đang sạc, mở chi tiết realtime',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: CockpitPanel(
          highlight: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    color: SmartChargeCockpitColors.verified,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'ĐANG SẠC',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    _duration(session.remaining()),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '~${(session.estimatedSoc ?? session.startSoc).round()}% → Mục tiêu ~${session.targetSoc.round()}%',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                '${powerW == null ? '— W' : '${powerW!.toStringAsFixed(0)} W'} · ${_energy(session.energyUsedWh)} · $cost',
                style: const TextStyle(color: SmartChargeCockpitColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthlySummary extends StatelessWidget {
  const _MonthlySummary({
    required this.month,
    required this.range,
    required this.summary,
    this.onPrevious,
    this.onNext,
  });
  final DateTime month;
  final DateTimeRange? range;
  final SmartChargeHistorySummary summary;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final recent = <SmartChargeDailyEnergy>[];
    final now = DateTime.now();
    for (var offset = 6; offset >= 0; offset--) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: offset));
      recent.add(
        summary.daily.firstWhere(
          (item) => item.day == day,
          orElse: () => SmartChargeDailyEnergy(day, 0, 0),
        ),
      );
    }
    return CockpitPanel(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  range == null
                      ? 'TỔNG KẾT THÁNG ${DateFormat('MM/yyyy').format(month)}'
                      : 'TỔNG KẾT ${DateFormat('dd/MM').format(range!.start)} – ${DateFormat('dd/MM/yyyy').format(range!.end)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: SmartChargeCockpitColors.verified,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: .5,
                  ),
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const Divider(),
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              _SummaryKpi('Điện nạp', _energy(summary.totalGridEnergyWh)),
              _SummaryKpi(
                'Tổng tiền',
                summary.totalCostVnd <= 0
                    ? '—'
                    : '${NumberFormat.compact(locale: 'vi').format(summary.totalCostVnd)} đ',
              ),
              _SummaryKpi('Thời gian', _duration(summary.totalDuration)),
              _SummaryKpi('Phiên', '${summary.completedSessions}'),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(height: 72, child: _SevenDayBars(days: recent)),
        ],
      ),
    );
  }
}

class _SummaryKpi extends StatelessWidget {
  const _SummaryKpi(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 116,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: SmartChargeCockpitColors.muted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: CockpitTypography.numbers(
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _SevenDayBars extends StatelessWidget {
  const _SevenDayBars({required this.days});
  final List<SmartChargeDailyEnergy> days;
  @override
  Widget build(BuildContext context) {
    final maximum = days.fold<double>(
      1,
      (value, item) => max(value, item.energyWh),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final day in days)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: max(.06, day.energyWh / maximum),
                      child: Container(
                        width: 16,
                        decoration: BoxDecoration(
                          color: SmartChargeCockpitColors.verified,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('E', 'vi').format(day.day),
                  style: const TextStyle(
                    fontSize: 9,
                    color: SmartChargeCockpitColors.muted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
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
    final cost = session.estimatedCostVnd == null
        ? '—'
        : '${NumberFormat.decimalPattern('vi_VN').format(session.estimatedCostVnd)} đ';
    final status = session.energyQuality == 'partial'
        ? 'Partial'
        : session.state == ChargingSessionState.completed
        ? 'Hoàn thành'
        : 'Đã dừng';
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
            '${!session.state.isTerminal ? '${_duration(session.remaining())} còn lại' : _duration(duration)} · $cost · $status',
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onLongPress: session.state.isTerminal ? onHide : null,
      ),
    );
  }
}

enum _ChartMetric { power, voltage, current, temperature, energy }

class _SocProgressHeader extends StatelessWidget {
  const _SocProgressHeader({required this.session});
  final SmartChargingSession session;

  @override
  Widget build(BuildContext context) {
    final end =
        session.actualEndSoc ?? session.estimatedSoc ?? session.targetSoc;
    final confirmed = session.actualEndSoc != null;
    return CockpitPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MỨC PIN TRONG PHIÊN',
            style: TextStyle(
              color: SmartChargeCockpitColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '~${session.startSoc.round()}%',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Divider(
                          color: SmartChargeCockpitColors.verified,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: SmartChargeCockpitColors.verified,
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                '${confirmed ? '' : '~'}${end.round()}%',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: SmartChargeCockpitColors.verified,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            confirmed
                ? 'SOC cuối do người dùng xác nhận'
                : 'Ước tính, không phải dữ liệu BMS',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: confirmed
                  ? SmartChargeCockpitColors.verified
                  : SmartChargeCockpitColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}

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
  late SmartChargingSession _session;
  List<SmartChargeTelemetryPoint>? _points;
  SmartChargeEnergySummary? _summary;
  String? _error;
  _ChartMetric _metric = _ChartMetric.power;
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _load();
    if (!_session.state.isTerminal) {
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
      final points = await widget.controller.getTelemetry(_session.sessionId);
      if (!mounted) return;
      setState(() {
        final live = widget.controller.currentUiState.session;
        if (live?.sessionId == _session.sessionId) _session = live!;
        _points = points;
        _summary = SmartChargeEnergySummary.calculate(
          session: _session,
          points: points,
        );
      });
      if (_session.state.isTerminal) {
        _liveTimer?.cancel();
        _liveTimer = null;
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Không thể tải dữ liệu biểu đồ.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = (_session.stoppedAt ?? _session.updatedAt).difference(
      _session.startedAt ?? _session.createdAt,
    );
    return SmartChargeCockpitTheme(
      child: Scaffold(
        appBar: AppBar(title: const Text('Chi tiết phiên sạc')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              _session.strategy == ChargingStrategy.manualTimed
                  ? 'Sạc thủ công'
                  : 'Sạc theo AI',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (!_session.state.isTerminal) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: const Icon(Icons.bolt_rounded, size: 18),
                  label: Text(
                    'ĐANG SẠC · Mục tiêu ~${_session.targetSoc.round()}%',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              '${DateFormat('dd/MM/yyyy · HH:mm').format(_session.createdAt.toLocal())}  ·  ${_duration(duration)}',
            ),
            const SizedBox(height: 16),
            _SocProgressHeader(session: _session),
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
              onPressed: _session.state.isTerminal ? _confirmSoc : null,
              icon: const Icon(Icons.battery_saver_rounded),
              label: const Text('XÁC NHẬN SOC THỰC TẾ KHI KẾT THÚC'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _session.state.isTerminal ? _hideSession : null,
              icon: const Icon(Icons.visibility_off_outlined),
              label: const Text('ẨN PHIÊN KHỎI LỊCH SỬ'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _session.state.isTerminal ? _privacyErase : null,
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
      (
        'Chi phí phiên',
        _session.estimatedCostVnd == null
            ? 'Chưa đặt giá điện'
            : '${NumberFormat.decimalPattern('vi_VN').format(_session.estimatedCostVnd)} đ',
      ),
      (
        'Độ phủ dữ liệu',
        summary == null
            ? '—'
            : '${(summary.coverageRatio * 100).round()}% · ${summary.energyQuality}',
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
    final source = _downsample(_points!, 500);
    double read(SmartChargeTelemetryPoint point) => switch (_metric) {
      _ChartMetric.power => point.powerAverageW,
      _ChartMetric.voltage => point.voltageV,
      _ChartMetric.current => point.currentA,
      _ChartMetric.temperature => point.temperatureC ?? 0,
      _ChartMetric.energy => point.energyWh - source.first.energyWh,
    };
    final segments = <List<SmartChargeTelemetryPoint>>[];
    for (final point in source) {
      if (segments.isEmpty ||
          point.timestamp.difference(segments.last.last.timestamp) >
              const Duration(seconds: 75)) {
        segments.add([point]);
      } else {
        segments.last.add(point);
      }
    }
    final transportMarkers = <double>{};
    final rearmMarkers = <double>{};
    for (var index = 1; index < source.length; index++) {
      if (source[index].transport != source[index - 1].transport) {
        transportMarkers.add(source[index].elapsedSeconds / 60);
      }
      final previousTimer = source[index - 1].timerRemainingSeconds;
      final currentTimer = source[index].timerRemainingSeconds;
      if (previousTimer != null &&
          currentTimer != null &&
          currentTimer > previousTimer + 90) {
        rearmMarkers.add(source[index].elapsedSeconds / 60);
      }
    }
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
                      '${item.x.toStringAsFixed(1)} phút\n${item.y.toStringAsFixed(1)} ${_metricUnit(_metric)}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          extraLinesData: ExtraLinesData(
            verticalLines: [
              VerticalLine(
                x: 0,
                color: SmartChargeCockpitColors.verified,
                strokeWidth: 1.5,
              ),
              for (final minute in rearmMarkers)
                VerticalLine(
                  x: minute,
                  color: SmartChargeCockpitColors.warning,
                  strokeWidth: 1.5,
                  dashArray: const [5, 4],
                ),
              for (final event in _session.safetyEvents)
                if (event.createdAt != null)
                  VerticalLine(
                    x:
                        event.createdAt!
                            .difference(
                              _session.startedAt ?? _session.createdAt,
                            )
                            .inSeconds /
                        60,
                    color: SmartChargeCockpitColors.warning,
                    strokeWidth: 1.5,
                    dashArray: const [4, 4],
                  ),
              if (_session.state.isTerminal)
                VerticalLine(
                  x: source.last.elapsedSeconds / 60,
                  color:
                      _session.stopReason == ChargingStopReason.manual ||
                          _session.userStopReason != UserStopReason.none
                      ? SmartChargeCockpitColors.danger
                      : SmartChargeCockpitColors.verified,
                  strokeWidth: 2,
                ),
            ],
          ),
          lineBarsData: [
            for (final segment in segments)
              LineChartBarData(
                spots: segment
                    .map(
                      (point) => FlSpot(
                        point.elapsedSeconds / 60,
                        max(0, read(point)),
                      ),
                    )
                    .toList(),
                isCurved: true,
                curveSmoothness: 0.25,
                color: color,
                barWidth: 3,
                dotData: FlDotData(
                  show: true,
                  checkToShowDot: (spot, _) =>
                      transportMarkers.contains(spot.x),
                ),
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

  List<SmartChargeTelemetryPoint> _downsample(
    List<SmartChargeTelemetryPoint> points,
    int maximum,
  ) {
    if (points.length <= maximum) return points;
    final step = points.length / maximum;
    return [
      for (var index = 0.0; index < points.length; index += step)
        points[min(points.length - 1, index.floor())],
    ];
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
      ('Dừng sạc', _session.stopReason?.wireValue ?? _session.state.wireValue),
      (
        'Thiết bị / kết nối',
        '${_session.deviceId ?? 'Shelly'} · ${_session.transport ?? '—'}',
      ),
      ('Model AI', '${_session.modelVersion} · ${_session.predictionSource}'),
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
        _session,
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
            const Text(
              'Thao tác này xóa summary, telemetry và không thể hoàn tác.',
            ),
            const SizedBox(height: 12),
            SelectableText(
              _session.sessionId,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: input,
              decoration: const InputDecoration(
                labelText: 'Nhập mã phiên để xác nhận',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('HỦY'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              input.text.trim() == _session.sessionId,
            ),
            child: const Text('XÓA VĨNH VIỄN'),
          ),
        ],
      ),
    );
    final code = input.text.trim();
    input.dispose();
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.privacyEraseSession(_session.sessionId, code);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể xóa dữ liệu: $error')),
        );
      }
    }
  }

  Future<void> _hideSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ẩn phiên sạc?'),
        content: const Text(
          'Phiên sẽ biến mất khỏi danh sách thường nhưng dữ liệu gốc vẫn được giữ.',
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
      await widget.controller.hideSession(_session.sessionId);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        AppPopup.showError('Không thể ẩn phiên', detail: '$error');
      }
    }
  }
}

String _energy(double wh) => wh >= 1000
    ? '${(wh / 1000).toStringAsFixed(2)} kWh'
    : '${wh.toStringAsFixed(0)} Wh';

String _metricUnit(_ChartMetric metric) => switch (metric) {
  _ChartMetric.power => 'W',
  _ChartMetric.voltage => 'V',
  _ChartMetric.current => 'A',
  _ChartMetric.temperature => '°C',
  _ChartMetric.energy => 'Wh',
};

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  return hours == 0
      ? '$minutes phút'
      : '${hours}g ${minutes.toString().padLeft(2, '0')}p';
}
