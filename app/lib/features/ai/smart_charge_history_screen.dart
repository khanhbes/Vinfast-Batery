import 'dart:async';
import '../../core/widgets/adaptive_detail_rows.dart';
import '../../core/theme/app_ui_colors.dart';
import 'widgets/session_soc_summary.dart';
import 'widgets/confirm_session_soc_dialog.dart';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/smart_charge_history.dart';
import '../../data/models/smart_charge_cost.dart';
import '../../data/models/smart_charging_session.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/responsive_card_grid.dart';
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
    _liveTimer = Timer.periodic(Duration(seconds: 5), (_) {
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
      adaptive: true,
      child: Scaffold(
        appBar: widget.embedded
            ? null
            : AppBar(title: Text('Lịch sử Smart Charge')),
        body: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: _HistoryHeader(onExport: _export),
                ),
              ),
              if (_activeSession != null)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
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
                padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
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
                padding: EdgeInsets.fromLTRB(16, 2, 16, 12),
                sliver: SliverToBoxAdapter(child: _filters()),
              ),
              if (_error != null && _items.isEmpty)
                SliverFillRemaining(child: _errorState())
              else if (visible.isEmpty && _activeSession == null)
                SliverFillRemaining(
                  child: _EmptyHistory(
                    isFiltered: _filter != null ||
                        _statusFilter != SmartChargeHistorySessionFilter.all ||
                        _customRange != null ||
                        _allVehicles,
                    onClearFilter: () => setState(() {
                      _filter = null;
                      _statusFilter = SmartChargeHistorySessionFilter.all;
                      _customRange = null;
                      _allVehicles = false;
                      _visibleCount = 20;
                      _load(reset: true);
                    }),
                  ),
                )
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
                      Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) => _HistoryRow(
                    session: shown[index],
                    onTap: () => _openDetail(shown[index]),
                    onHide: () => _hide(shown[index]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: _cursor == null && shown.length >= visible.length
                        ? Center(child: Text('Đã hiển thị toàn bộ phiên sạc'))
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
                                ? SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text('TẢI THÊM'),
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
        segments: [
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
      SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: Icon(Icons.date_range_rounded),
              label: Text(
                _customRange == null
                    ? 'CHỌN KHOẢNG NGÀY'
                    : '${DateFormat('dd/MM').format(_customRange!.start)} – ${DateFormat('dd/MM/yyyy').format(_customRange!.end)}',
              ),
            ),
          ),
          if (_customRange != null) ...[
            SizedBox(width: 8),
            IconButton(
              tooltip: 'Trở về tháng hiện tại',
              onPressed: () => setState(() {
                _customRange = null;
                _visibleCount = 20;
              }),
              icon: Icon(Icons.close_rounded),
            ),
          ],
        ],
      ),
      SizedBox(height: 8),
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
        padding: EdgeInsets.only(right: 8),
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

  Future<void> _openDetail(SmartChargingSession session) async {
    final deletedOrChanged = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (_) => FractionallySizedBox(
        heightFactor: .96,
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          child: SmartChargeSessionDetailScreen(
            controller: widget.controller,
            session: session,
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (deletedOrChanged == true || deletedOrChanged is String) {
      if (mounted) {
        setState(() {
          _items.removeWhere((it) => it.sessionId == session.sessionId);
        });
      }
      await _load(reset: true);
    }
  }

  Future<void> _export() async {
    final format = await showModalBottomSheet<ChargeReportFormat>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Xuất báo cáo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: 6),
              Text(
                '${_customRange == null ? DateFormat('MM/yyyy').format(_selectedMonth) : '${DateFormat('dd/MM/yyyy').format(_customRange!.start)} – ${DateFormat('dd/MM/yyyy').format(_customRange!.end)}'} · ${_allVehicles ? 'Tất cả xe' : 'Xe đang chọn'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, ChargeReportFormat.pdf),
                icon: Icon(Icons.picture_as_pdf_rounded),
                label: Text('XUẤT PDF'),
              ),
              SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, ChargeReportFormat.csv),
                icon: Icon(Icons.table_view_rounded),
                label: Text('XUẤT CSV'),
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
      SizedBox(height: 120),
      Icon(
        Icons.cloud_off_rounded,
        size: 44,
        color: Theme.of(context).colorScheme.outline,
      ),
      SizedBox(height: 12),
      Center(child: Text(_error!)),
      Center(
        child: TextButton(
          onPressed: () => _load(reset: true),
          child: Text('THỬ LẠI'),
        ),
      ),
    ],
  );

  Future<void> _hide(SmartChargingSession session) async {
    if (!session.state.isTerminal) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ẩn phiên sạc?'),
        content: Text(
          'Phiên sẽ được ẩn khỏi lịch sử thường. Dữ liệu gốc vẫn được giữ lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('HỦY'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('ẨN PHIÊN'),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Đã ẩn phiên khỏi lịch sử.')));
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
            SizedBox(height: 3),
            Text(
              'Phiên sạc, điện năng và chi phí đã đo.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppUiColors.of(context).muted,
              ),
            ),
          ],
        ),
      ),
      OutlinedButton.icon(
        onPressed: onExport,
        icon: Icon(Icons.ios_share_rounded, size: 18),
        label: Text('Xuất'),
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
          adaptive: true,
          highlight: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    color: AppUiColors.of(context).primary,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ĐANG SẠC',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    _duration(session.remaining()),
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                '~${(session.estimatedSoc ?? session.startSoc).round()}% → Mục tiêu ~${session.targetSoc.round()}%',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 5),
              Text(
                '${powerW == null ? '— W' : '${powerW!.toStringAsFixed(0)} W'} · ${_energy(session.energyUsedWh)} · $cost',
                style: TextStyle(color: AppUiColors.of(context).muted),
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
      adaptive: true,
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onPrevious,
                icon: Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  range == null
                      ? 'TỔNG KẾT THÁNG ${DateFormat('MM/yyyy').format(month)}'
                      : 'TỔNG KẾT ${DateFormat('dd/MM').format(range!.start)} – ${DateFormat('dd/MM/yyyy').format(range!.end)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppUiColors.of(context).primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: .5,
                  ),
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Divider(),
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
          SizedBox(height: 18),
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
          style: TextStyle(color: AppUiColors.of(context).muted, fontSize: 11),
        ),
        SizedBox(height: 3),
        Text(
          value,
          style: CockpitTypography.numbers(
            color: Theme.of(context).colorScheme.onSurface,
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
                          color: AppUiColors.of(context).primary,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  DateFormat('E', 'vi').format(day.day),
                  style: TextStyle(
                    fontSize: 9,
                    color: AppUiColors.of(context).muted,
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
  const _EmptyHistory({this.isFiltered = false, this.onClearFilter});
  final bool isFiltered;
  final VoidCallback? onClearFilter;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 100),
      Icon(
        isFiltered
            ? Icons.filter_alt_off_rounded
            : Icons.electric_bolt_outlined,
        size: 48,
        color: Theme.of(context).colorScheme.outline,
      ),
      const SizedBox(height: 12),
      Center(
        child: Text(
          isFiltered
              ? 'Không có phiên sạc phù hợp bộ lọc'
              : 'Chưa có phiên Smart Charge hoàn tất',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Center(
        child: Text(
          isFiltered
              ? 'Thử đổi khoảng ngày hoặc chuyển bộ lọc sang Tất cả.'
              : 'Phiên sạc sẽ xuất hiện ở đây sau khi relay OFF được xác minh.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      if (isFiltered && onClearFilter != null) ...[
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: onClearFilter,
            icon: const Icon(Icons.clear_all_rounded, size: 18),
            label: const Text('Xóa bộ lọc'),
          ),
        ),
      ],
    ],
  );
}

class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 18),
        SizedBox(width: 8),
        Expanded(child: Text('$message Đang hiển thị dữ liệu gần nhất.')),
        TextButton(onPressed: onRetry, child: Text('THỬ LẠI')),
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
    final isPartial = session.energyQuality == 'partial';
    final isCompleted = session.state == ChargingSessionState.completed;
    final statusText = isPartial
        ? 'Partial'
        : isCompleted
            ? 'Hoàn thành'
            : 'Đã dừng';
    final statusBg = isPartial
        ? Colors.grey.withValues(alpha: 0.15)
        : isCompleted
            ? CockpitColors.emerald.withValues(alpha: 0.15)
            : CockpitColors.amber.withValues(alpha: 0.15);
    final statusFg = isPartial
        ? AppUiColors.of(context).muted
        : isCompleted
            ? CockpitColors.emeraldStrong
            : CockpitColors.amber;

    return Semantics(
      button: true,
      label:
          'Chi tiết phiên sạc ${DateFormat('dd/MM/yyyy').format(session.createdAt)}, trạng thái $statusText',
      child: Dismissible(
        key: ValueKey('history-session-${session.sessionId}'),
        direction: session.state.isTerminal
            ? DismissDirection.endToStart
            : DismissDirection.none,
        confirmDismiss: (_) async {
          onHide();
          return false;
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: Theme.of(context).colorScheme.errorContainer,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_off_rounded,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 8),
              Text(
                'Ẩn phiên',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusFg,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _energy(session.energyUsedWh),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${DateFormat('dd/MM · HH:mm').format(session.createdAt.toLocal())} · ${_duration(duration)} · $cost',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppUiColors.of(context).muted,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${session.startSoc.toStringAsFixed(0)}% → ${session.targetSoc.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppUiColors.of(context).text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onLongPress: session.state.isTerminal ? onHide : null,
        ),
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
  late SmartChargingSession _session;
  List<SmartChargeTelemetryPoint>? _points;
  SmartChargeEnergySummary? _summary;
  String? _error;
  _ChartMetric _metric = _ChartMetric.power;
  Timer? _liveTimer;
  bool _loadingTelemetry = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _load();
    if (!_session.state.isTerminal) {
      _liveTimer = Timer.periodic(Duration(seconds: 5), (_) => _load());
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loadingTelemetry) return;
    _loadingTelemetry = true;
    try {
      final points = await widget.controller.getTelemetry(_session.sessionId);
      if (!mounted) return;
      setState(() {
        final live = widget.controller.currentUiState.session;
        if (live?.sessionId == _session.sessionId) _session = live!;
        _points = points;
        _error = null;
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
    } finally {
      _loadingTelemetry = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = (_session.stoppedAt ?? _session.updatedAt).difference(
      _session.startedAt ?? _session.createdAt,
    );
    return SmartChargeCockpitTheme(
      adaptive: true,
      child: Scaffold(
        appBar: AppBar(title: Text('Chi tiết phiên sạc')),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              _session.strategy == ChargingStrategy.manualTimed
                  ? 'Sạc thủ công'
                  : 'Sạc theo AI',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            ...[
              SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: Icon(Icons.bolt_rounded, size: 18),
                  label: Text(switch (_session.state) {
                    ChargingSessionState.arming => 'Đang chuẩn bị',
                    ChargingSessionState.starting => 'Đang bật sạc',
                    ChargingSessionState.active =>
                      'Đang sạc · Mục tiêu ~${_session.targetSoc.round()}%',
                    ChargingSessionState.stopping => 'Đang dừng sạc',
                    ChargingSessionState.completed => 'Đã hoàn tất',
                    ChargingSessionState.cancelled => 'Đã hủy',
                    ChargingSessionState.interrupted => 'Bị gián đoạn',
                    ChargingSessionState.failed => 'Phiên gặp lỗi',
                  }),
                ),
              ),
            ],
            SizedBox(height: 6),
            Text(
              '${DateFormat('dd/MM/yyyy · HH:mm').format(_session.createdAt.toLocal())}  ·  ${_duration(duration)}',
              style: CockpitTypography.label(
                fontSize: 12,
                color: CockpitColors.muted,
              ),
            ),
            const SizedBox(height: 16),
            SessionSocSummary(session: _session),
            const SizedBox(height: 16),
            _kpis(),
            const SizedBox(height: 16),
            // Card 3: Telemetry & Curves Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: CockpitColors.surface,
                borderRadius: BorderRadius.circular(CockpitRadius.large),
                border: Border.all(color: CockpitColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: CockpitColors.info.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.show_chart_rounded,
                          size: 20,
                          color: CockpitColors.info,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Diễn biến telemetry',
                              style: CockpitTypography.heading(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: CockpitColors.text,
                              ),
                            ),
                            Text(
                              'Chạm và kéo trên biểu đồ để xem chi tiết',
                              style: CockpitTypography.label(
                                fontSize: 11,
                                color: CockpitColors.dim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _metricSelector(),
                  const SizedBox(height: 16),
                  SizedBox(height: 250, child: _chart()),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Card 4: Technical & AI Diagnostics Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: CockpitColors.surface,
                borderRadius: BorderRadius.circular(CockpitRadius.large),
                border: Border.all(color: CockpitColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: CockpitColors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.memory_rounded,
                          size: 20,
                          color: CockpitColors.amber,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Thông số kỹ thuật & AI',
                        style: CockpitTypography.heading(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: CockpitColors.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _technicalSummary(),
                ],
              ),
            ),
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
    final cost = _session.estimatedCostVnd == null
        ? '—'
        : '${NumberFormat.decimalPattern('vi_VN').format(_session.estimatedCostVnd)} đ';
    final duration = (_session.stoppedAt ?? _session.updatedAt).difference(
      _session.startedAt ?? _session.createdAt,
    );
    final durationStr = _duration(duration);
    final avgPower = summary == null
        ? '—'
        : '${(summary.averagePowerW / 1000).toStringAsFixed(2)} kW';

    final items = [
      (
        icon: Icons.electric_bolt_rounded,
        title: 'Điện từ lưới',
        value: summary == null ? '—' : _energy(summary.gridEnergyWh),
        highlight: true,
      ),
      (
        icon: Icons.payments_rounded,
        title: 'Chi phí phiên',
        value: cost,
        highlight: false,
      ),
      (
        icon: Icons.speed_rounded,
        title: 'Công suất TB',
        value: avgPower,
        highlight: false,
      ),
      (
        icon: Icons.timer_outlined,
        title: 'Thời gian sạc',
        value: durationStr,
        highlight: false,
      ),
      (
        icon: Icons.battery_charging_full_rounded,
        title: 'Vào pin (ước tính)',
        value: summary == null ? '—' : _energy(summary.estimatedStoredWh),
        highlight: false,
      ),
      (
        icon: Icons.health_and_safety_rounded,
        title: 'Dung lượng khả dụng',
        value: summary?.estimatedUsableCapacityWh == null
            ? 'Cần xác nhận'
            : _energy(summary!.estimatedUsableCapacityWh!),
        highlight: false,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CockpitColors.surface,
        borderRadius: BorderRadius.circular(CockpitRadius.large),
        border: Border.all(color: CockpitColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CockpitColors.emerald.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.dashboard_customize_rounded,
                  size: 20,
                  color: CockpitColors.emeraldStrong,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Tổng quan phiên sạc',
                style: CockpitTypography.heading(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: CockpitColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ResponsiveCardGrid(
            spacing: 12,
            minCardWidth: 140,
            children: [
              for (final item in items)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: item.highlight
                        ? CockpitColors.emeraldStrong.withValues(alpha: 0.08)
                        : CockpitColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(CockpitRadius.medium),
                    border: Border.all(
                      color: item.highlight
                          ? CockpitColors.emeraldStrong.withValues(alpha: 0.3)
                          : CockpitColors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            item.icon,
                            size: 16,
                            color: item.highlight
                                ? CockpitColors.emeraldStrong
                                : CockpitColors.muted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CockpitTypography.label(
                                fontSize: 11,
                                color: CockpitColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CockpitTypography.numbers(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: item.highlight
                              ? CockpitColors.emeraldStrong
                              : CockpitColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricSelector() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SegmentedButton<_ChartMetric>(
      showSelectedIcon: false,
      segments: [
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
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _load,
              icon: Icon(Icons.refresh_rounded),
              label: Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    if (_points == null) {
      return Center(child: CircularProgressIndicator());
    }
    if (_points!.isEmpty) {
      return Center(child: Text('Phiên này chưa có telemetry chi tiết.'));
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
              Duration(seconds: 75)) {
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
          : Duration(milliseconds: 180),
      child: LineChart(
        key: ValueKey(_metric),
        LineChartData(
          minY: 0,
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) =>
                    Text('${value.round()}m', style: TextStyle(fontSize: 10)),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 42),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (items) => items
                  .map(
                    (item) => LineTooltipItem(
                      '${item.x.toStringAsFixed(1)} phút\n${item.y.toStringAsFixed(1)} ${_metricUnit(_metric)}',
                      TextStyle(
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
                color: AppUiColors.of(context).primary,
                strokeWidth: 1.5,
              ),
              for (final minute in rearmMarkers)
                VerticalLine(
                  x: minute,
                  color: AppUiColors.of(context).warning,
                  strokeWidth: 1.5,
                  dashArray: [5, 4],
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
                    color: AppUiColors.of(context).warning,
                    strokeWidth: 1.5,
                    dashArray: [4, 4],
                  ),
              if (_session.state.isTerminal)
                VerticalLine(
                  x: source.last.elapsedSeconds / 60,
                  color:
                      _session.stopReason == ChargingStopReason.manual ||
                          _session.userStopReason != UserStopReason.none
                      ? AppUiColors.of(context).danger
                      : AppUiColors.of(context).primary,
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
      ('Mã phiên', _session.sessionId),
      ('Mã xe', _session.vehicleId),
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
        '${_session.deviceId ?? 'Chưa có ID'} · ${_session.transport ?? '—'}',
      ),
      ('Model AI', _session.modelVersion),
      ('Nguồn dự đoán', _session.predictionSource),
      (
        'Độ tin cậy dự đoán',
        _session.predictionConfidence != null &&
                _session.predictionConfidence!.isFinite &&
                _session.predictionConfidence! >= 0 &&
                _session.predictionConfidence! <= 1
            ? '${(_session.predictionConfidence! * 100).round()}%'
            : 'Chưa có dữ liệu',
      ),
      (
        'Cập nhật lúc',
        DateFormat('dd/MM/yyyy HH:mm:ss').format(_session.updatedAt.toLocal()),
      ),
    ];
    return AdaptiveDetailRows(rows: rows);
  }

  Future<void> _confirmSoc() async {
    final value = await showDialog<double>(
      context: context,
      builder: (_) => const ConfirmSessionSocDialog(),
    );
    if (value == null || !mounted) return;
    try {
      final summary = await widget.controller.confirmActualEndSoc(
        _session,
        value,
      );
      if (mounted) {
        setState(() {
          _session = _session.copyWith(actualEndSoc: value);
          _summary = summary;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã xác nhận SOC thực tế: ${value.toStringAsFixed(0)}%',
            ),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $error')));
      }
    }
  }

  Future<void> _privacyErase() async {
    final input = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Xóa vĩnh viễn phiên sạc?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Thao tác này xóa summary, telemetry và không thể hoàn tác.'),
            SizedBox(height: 12),
            SelectableText(
              _session.sessionId,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            TextField(
              controller: input,
              decoration: InputDecoration(
                labelText: 'Nhập mã phiên để xác nhận',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('HỦY'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              input.text.trim() == _session.sessionId,
            ),
            child: Text('XÓA VĨNH VIỄN'),
          ),
        ],
      ),
    );
    final code = input.text.trim();
    input.dispose();
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.privacyEraseSession(_session.sessionId, code);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
          }
        });
      }
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
        title: Text('Ẩn phiên sạc?'),
        content: Text(
          'Phiên sẽ biến mất khỏi danh sách thường nhưng dữ liệu gốc vẫn được giữ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('HỦY'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('ẨN PHIÊN'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.hideSession(_session.sessionId);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
          }
        });
      }
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
