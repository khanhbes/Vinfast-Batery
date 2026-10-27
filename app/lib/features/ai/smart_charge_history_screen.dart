import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/services/app_error_reporter.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/utils/app_error_formatter.dart';
import '../../core/utils/number_text.dart';
import '../../data/services/charge_estimator.dart';
import '../../core/widgets/adaptive_detail_rows.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/responsive_card_grid.dart';
import '../../data/models/smart_charge_cost.dart';
import '../../data/models/smart_charge_history.dart';
import '../../data/models/smart_charging_session.dart';
import '../../core/providers/entitlement_provider.dart';
import '../../data/models/entitlement.dart';
import '../auth/auth_providers.dart';
import '../premium/premium_gate.dart';
import 'controllers/smart_charging_controller.dart';
import 'services/learning_flow.dart';
import 'widgets/confirm_actual_soc_sheet.dart';
import 'widgets/history_luxe_widgets.dart';
import 'widgets/session_soc_summary.dart';
import '../../core/services/guide_registry.dart';

class SmartChargeHistoryScreen extends StatefulWidget {
  const SmartChargeHistoryScreen({
    super.key,
    required this.controller,
    this.ownerUid,
    this.initialItems = const [],
    this.initialSessionId,
    this.onPendingTargetConsumed,
    this.onStartCharging,
    this.embedded = false,
  });

  final SmartChargingController controller;
  final String? ownerUid;
  final List<SmartChargingSession> initialItems;
  final String? initialSessionId;
  final VoidCallback? onPendingTargetConsumed;

  /// Empty-state call to action ("start the first session"). Hidden if null.
  final VoidCallback? onStartCharging;
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
  // Empty is a valid result only after at least one successful Firestore/API
  // response.  This prevents permission/network failures from being shown as
  // a misleading zero-history state.
  bool _hasSuccessfulLoad = false;
  bool _allVehicles = false;
  bool _loadingMore = false;
  bool _loading = false;
  int _requestGeneration = 0;
  int _contextGeneration = 0;
  late String _vehicleId = widget.controller.currentUiState.draft.vehicleId;
  int _visibleCount = 20;
  Timer? _liveTimer;
  bool _openedPending = false;

  /// Direction of the last month change, so the summary slides that way.
  int _monthDirection = 0;

  /// QA 135: Free shows the last 30 days (older sessions are hidden, never
  /// deleted, and come back with Pro).
  int? _historyDays;
  bool _exportAllowed = true;
  ProviderSubscription<Entitlement>? _planSubscription;

  DateTime? get _planCutoff => _historyDays == null
      ? null
      : DateTime.now().subtract(Duration(days: _historyDays!));

  bool _beforePlanWindow(SmartChargingSession session) {
    final cutoff = _planCutoff;
    return cutoff != null &&
        (session.startedAt ?? session.createdAt).isBefore(cutoff);
  }

  int get _hiddenByPlan =>
      _items.where((s) => s.state.isTerminal && _beforePlanWindow(s)).length;

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
    if (_beforePlanWindow(session)) return false;
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

  bool get _isFiltered =>
      _filter != null ||
      _statusFilter != SmartChargeHistorySessionFilter.all ||
      _customRange != null ||
      _allVehicles;

  bool get _canGoNext =>
      _customRange == null && !_monthEnd.isAfter(DateTime.now());

  void Function()? _removeControllerListener;
  String? _runningSessionId;

  /// The History tab stays alive in the tab stack, so it must reload when a
  /// session ends (or starts) instead of only on first open (Task 123: the
  /// newest sessions were missing until a manual pull-to-refresh).
  void _subscribeToController() {
    _removeControllerListener?.call();
    _runningSessionId = null;
    var primed = false;
    _removeControllerListener = widget.controller.addListener((state) {
      final session = state.session;
      final running = session != null && !session.state.isTerminal
          ? session.sessionId
          : null;
      if (!primed) {
        // The immediate first callback is the current state: already loaded.
        primed = true;
        _runningSessionId = running;
        return;
      }
      final changed = running != _runningSessionId;
      final hadSession = _runningSessionId != null || running != null;
      _runningSessionId = running;
      if (!changed || !hadSession) return;
      // Never setState while the notifier is dispatching.
      scheduleMicrotask(() {
        if (mounted) _load(reset: true);
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _hasSuccessfulLoad = widget.initialItems.isNotEmpty;
    _subscribeToController();
    _load(reset: true);
    _liveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_loading && _items.any((item) => !item.state.isTerminal)) {
        _load(reset: true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_planSubscription != null) return;
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final plan = container.read(entitlementProvider);
      _historyDays = plan.historyDays;
      _exportAllowed = plan.allows(PremiumFeature.historyExport);
      _planSubscription = container.listen<Entitlement>(entitlementProvider, (
        _,
        next,
      ) {
        if (!mounted) return;
        setState(() {
          _historyDays = next.historyDays;
          _exportAllowed = next.allows(PremiumFeature.historyExport);
        });
      });
    } on Object {
      // No ProviderScope (isolated widget tests): nothing is gated.
    }
  }

  @override
  void didUpdateWidget(covariant SmartChargeHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final vehicleId = widget.controller.currentUiState.draft.vehicleId;
    if (!identical(oldWidget.controller, widget.controller)) {
      _subscribeToController();
    }
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.ownerUid != widget.ownerUid ||
        _vehicleId != vehicleId) {
      _contextGeneration++;
      _vehicleId = vehicleId;
      // Never seed a new account/vehicle with the previous screen's cache.
      _items = [];
      _cursor = null;
      _error = null;
      _hasSuccessfulLoad = false;
      _openedPending = false;
      _load(reset: true);
    } else if (oldWidget.initialSessionId != widget.initialSessionId) {
      _openedPending = false;
      _openPendingIfAvailable();
    }
  }

  @override
  void dispose() {
    _planSubscription?.close();
    _removeControllerListener?.call();
    _contextGeneration++;
    _requestGeneration++;
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({required bool reset, bool clearItems = false}) async {
    if (!mounted || (!reset && (_loading || _cursor == null))) return;
    final controller = widget.controller;
    final ownerUid = widget.ownerUid;
    final vehicleId = _vehicleId;
    final generation = ++_requestGeneration;
    final contextGeneration = _contextGeneration;
    final cursor = reset ? null : _cursor;
    final strategy = _filter;
    final allVehicles = _allVehicles;
    bool isCurrent() =>
        mounted &&
        generation == _requestGeneration &&
        contextGeneration == _contextGeneration &&
        identical(controller, widget.controller) &&
        ownerUid == widget.ownerUid &&
        vehicleId == widget.controller.currentUiState.draft.vehicleId;
    if (reset) {
      setState(() {
        _error = null;
        _visibleCount = 20;
        _loading = true;
        _loadingMore = false;
        if (clearItems) {
          _items = [];
          _cursor = null;
          _hasSuccessfulLoad = false;
        }
      });
      _openPendingIfAvailable();
    } else {
      setState(() {
        _loading = true;
        _loadingMore = true;
      });
    }
    try {
      final page = await controller.getHistoryPage(
        limit: 100,
        cursor: cursor,
        strategy: strategy,
        allVehicles: allVehicles,
      );
      if (!isCurrent()) return;
      setState(() {
        // Pages can overlap after a refresh; keep one row per session.
        _items = {
          if (!reset)
            for (final item in _items) item.sessionId: item,
          for (final item in page.items) item.sessionId: item,
        }.values.toList();
        _cursor = page.nextCursor;
        _error = null;
        _hasSuccessfulLoad = true;
      });
      _openPendingIfAvailable();
    } catch (e, st) {
      if (!isCurrent()) return;
      AppErrorReporter.report(e, st, source: 'SmartChargeHistoryScreen');
      setState(() => _error = 'Không thể đồng bộ lịch sử sạc.');
    } finally {
      if (isCurrent()) {
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
    final contextGeneration = _contextGeneration;
    final controller = widget.controller;
    _openedPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          contextGeneration != _contextGeneration ||
          widget.initialSessionId != target) {
        return;
      }
      widget.onPendingTargetConsumed?.call();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Consumer(
            builder: (context, ref, _) => SmartChargeSessionDetailScreen(
              controller: controller,
              ownerUid: ref.watch(currentUidProvider),
              session: session,
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredItems
      ..sort(
        (a, b) =>
            (b.startedAt ?? b.createdAt).compareTo(a.startedAt ?? a.createdAt),
      );
    final shown = visible.take(_visibleCount).toList();
    final initialLoadFailed =
        _error != null && !_hasSuccessfulLoad && _items.isEmpty;
    final summary = SmartChargeHistorySummary.calculate(
      visible,
      from: _rangeStart,
      to: _rangeEnd,
    );
    final active = _activeSession;
    return Theme(
      data: LuxeTheme.of(context),
      child: Scaffold(
        backgroundColor: LuxeColors.background,
        appBar: widget.embedded
            ? null
            : AppBar(
                title: const Text('Lịch sử sạc'),
                backgroundColor: LuxeColors.background,
              ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const LuxeBackdrop(),
            SafeArea(
              bottom: false,
              child: RefreshIndicator(
                color: LuxeColors.emerald,
                backgroundColor: LuxeColors.raised,
                onRefresh: () => _load(reset: true),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
                      sliver: SliverToBoxAdapter(
                        child: LuxeReveal(
                          key: GuideRegistry.keyHistoryHeader,
                          child: _HistoryHeader(
                            onExport: _export,
                            exportAllowed: _exportAllowed,
                          ),
                        ),
                      ),
                    ),
                    if (active != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        sliver: SliverToBoxAdapter(
                          child: LuxeReveal(
                            index: 1,
                            child: HistoryActiveCard(
                              session: active,
                              powerW: widget
                                  .controller
                                  .currentUiState
                                  .chargerStatus
                                  ?.powerW,
                              onTap: () => _openDetail(active),
                            ),
                          ),
                        ),
                      ),
                    if (_loading && !_hasSuccessfulLoad && _items.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: SizedBox.square(
                            dimension: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: LuxeColors.emerald,
                            ),
                          ),
                        ),
                      )
                    else if (initialLoadFailed)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _errorState(),
                      )
                    else ...[
                      if (_error != null)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          sliver: SliverToBoxAdapter(
                            child: _StaleNotice(
                              message: _error!,
                              onRetry: () => _load(reset: true),
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        sliver: SliverToBoxAdapter(
                          child: LuxeReveal(
                            index: 2,
                            key: GuideRegistry.keyHistorySummary,
                            child: _summaryCard(summary),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: LuxeReveal(
                          index: 3,
                          key: GuideRegistry.keyHistoryFilters,
                          child: _filters(),
                        ),
                      ),
                      if (_hiddenByPlan > 0)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                          sliver: SliverToBoxAdapter(
                            child: LuxeNotice(
                              key: const ValueKey('history-plan-window'),
                              icon: Icons.workspace_premium_rounded,
                              color: LuxeColors.champagne,
                              message:
                                  'Gói Free hiển thị $_historyDays ngày gần '
                                  'nhất; $_hiddenByPlan phiên cũ hơn đang ẩn '
                                  '(không bị xóa).',
                              action: TextButton(
                                onPressed: () => PremiumGate.showUpgrade(
                                  context,
                                  PremiumFeature.historyExport,
                                ),
                                child: const Text('Xem'),
                              ),
                            ),
                          ),
                        ),
                      if (visible.isEmpty && active == null)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyHistory(
                            isFiltered: _isFiltered,
                            onStartCharging: widget.onStartCharging,
                            onClearFilter: () => setState(() {
                              _filter = null;
                              _statusFilter =
                                  SmartChargeHistorySessionFilter.all;
                              _customRange = null;
                              _allVehicles = false;
                              _visibleCount = 20;
                              _load(reset: true, clearItems: true);
                            }),
                          ),
                        ),
                      if (visible.isNotEmpty || active != null) ...[
                        _timeline(shown),
                        SliverToBoxAdapter(child: _footer(shown, visible)),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────── Summary: energy ring + KPIs + month switcher ───────────────

  Widget _summaryCard(SmartChargeHistorySummary summary) {
    final ring = _ringData(summary);
    final periodTitle = _customRange == null
        ? 'Tháng ${DateFormat('MM · yyyy').format(_selectedMonth)}'
        : '${DateFormat('dd/MM').format(_customRange!.start)} – ${DateFormat('dd/MM/yyyy').format(_customRange!.end)}';
    final reduced = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: _customRange != null
          ? null
          : (details) {
              final v = details.primaryVelocity ?? 0;
              if (v > 280) {
                _changeMonth(-1);
              } else if (v < -280 && _canGoNext) {
                _changeMonth(1);
              }
            },
      child: LuxeGlass(
        radius: 26,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 18),
        child: Column(
          children: [
            Row(
              children: [
                HistoryGlassButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Tháng trước',
                  size: 38,
                  onPressed: _customRange == null
                      ? () => _changeMonth(-1)
                      : null,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _customRange == null ? 'TỔNG KẾT THÁNG' : 'TỔNG KẾT',
                        style: LuxeText.eyebrow.copyWith(fontSize: 11),
                      ),
                      const SizedBox(height: 3),
                      AnimatedSwitcher(
                        duration: reduced
                            ? Duration.zero
                            : const Duration(milliseconds: 260),
                        child: Text(
                          periodTitle,
                          key: ValueKey(periodTitle),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: LuxeColors.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                HistoryGlassButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'Tháng sau',
                  size: 38,
                  onPressed: _canGoNext ? () => _changeMonth(1) : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: AnimatedSwitcher(
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                switchInCurve: LuxeMotion.enter,
                switchOutCurve: Curves.easeOut,
                transitionBuilder: (child, animation) {
                  final incoming = child.key == ValueKey(periodTitle);
                  final dx = incoming
                      ? 0.12 * _monthDirection
                      : -0.12 * _monthDirection;
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: Offset(dx, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: HistoryEnergyBars(
                  key: ValueKey(periodTitle),
                  buckets: ring.buckets,
                  labels: ring.labels,
                  details: ring.details,
                  highlightIndex: ring.today,
                  totalWh: summary.totalGridEnergyWh,
                  caption: ring.caption,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Expanded(
                    child: HistoryKpi(
                      label:
                          summary.pricedSessions == 0 &&
                              summary.completedSessions > 0
                          ? 'Chưa đặt giá điện'
                          : 'Chi phí',
                      value: summary.pricedSessions == 0
                          ? '—'
                          : formatVnd(summary.totalCostVnd),
                    ),
                  ),
                  const _KpiDivider(),
                  Expanded(
                    child: HistoryKpi(
                      label: 'Thời gian',
                      value: historyDuration(summary.totalDuration),
                    ),
                  ),
                  const _KpiDivider(),
                  Expanded(
                    child: HistoryKpi(
                      label: 'Phiên',
                      value: '${summary.completedSessions}',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Per-day energy for the month chart; ranges longer than ~2 months use
  /// weeks. QA 136: plus the axis label and the readable name of each bar.
  ({
    List<double> buckets,
    List<String> labels,
    List<String> details,
    int? today,
    String caption,
  })
  _ringData(SmartChargeHistorySummary summary) {
    final byDay = {for (final d in summary.daily) d.day: d.energyWh};
    final start = DateTime(
      _rangeStart.year,
      _rangeStart.month,
      _rangeStart.day,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = <DateTime>[];
    for (var i = 0; i < 400; i++) {
      final day = DateTime(start.year, start.month, start.day + i);
      if (!day.isBefore(_rangeEnd)) break;
      days.add(day);
    }
    final weekly = days.length > 62;
    final buckets = <double>[];
    final labels = <String>[];
    final details = <String>[];
    int? todayIndex;
    String dm(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    const weekdays = [
      'Thứ Hai',
      'Thứ Ba',
      'Thứ Tư',
      'Thứ Năm',
      'Thứ Sáu',
      'Thứ Bảy',
      'Chủ Nhật',
    ];
    for (var i = 0; i < days.length; i++) {
      final slot = weekly ? i ~/ 7 : i;
      if (slot >= buckets.length) {
        buckets.add(0);
        final first = days[i];
        if (weekly) {
          final last = days[min(i + 6, days.length - 1)];
          details.add('Tuần ${dm(first)}–${dm(last)}');
          labels.add(slot % 2 == 0 ? dm(first) : '');
        } else {
          details.add('${weekdays[first.weekday - 1]} ${dm(first)}');
          // 1, 5, 10 … and the last day (a 5 too close to it is skipped).
          final day = first.day;
          final isLast = i == days.length - 1;
          final show =
              days.length <= 10 ||
              isLast ||
              day == 1 ||
              (day % 5 == 0 && i <= days.length - 4);
          labels.add(show ? '$day' : '');
        }
      }
      buckets[slot] += byDay[days[i]] ?? 0;
      if (days[i] == today) todayIndex = slot;
    }
    // Days that have happened: the current month is not "31 ngày" on the
    // 18th (QA 129).
    final elapsed = days.where((day) => !day.isAfter(today)).length;
    final counted = elapsed > 0 ? elapsed : days.length;
    final caption = weekly
        ? 'điện nạp · ${(counted / 7).ceil()} tuần'
        : 'điện nạp · $counted ngày';
    return (
      buckets: buckets,
      labels: labels,
      details: details,
      today: todayIndex,
      caption: caption,
    );
  }

  // ─────────────── Filters ───────────────

  /// "Sạc AI · Dừng sớm"-style summary of the active filters, or null.
  String? get _activeFilterLabel {
    final parts = <String>[
      if (_filter == ChargingStrategy.aiTarget) 'Sạc AI',
      if (_filter == ChargingStrategy.manualTimed) 'Hẹn giờ',
      if (_filter != null &&
          _filter != ChargingStrategy.aiTarget &&
          _filter != ChargingStrategy.manualTimed)
        'Một chế độ sạc',
      if (_statusFilter == SmartChargeHistorySessionFilter.completed)
        'Hoàn thành',
      if (_statusFilter == SmartChargeHistorySessionFilter.stoppedEarly)
        'Dừng sớm',
      if (_statusFilter == SmartChargeHistorySessionFilter.partial)
        'Thiếu số đo',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _filters() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_activeFilterLabel != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: LuxeNotice(
            key: const ValueKey('history-active-filter'),
            icon: Icons.filter_alt_rounded,
            color: LuxeColors.champagne,
            message:
                'Đang lọc: $_activeFilterLabel. Các phiên khác đang bị ẩn.',
            action: TextButton(
              key: const ValueKey('history-clear-filter'),
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _filter = null;
                  _statusFilter = SmartChargeHistorySessionFilter.all;
                  _visibleCount = 20;
                });
                _load(reset: true, clearItems: true);
              },
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Bỏ lọc'),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: HistoryScopeToggle(
          allVehicles: _allVehicles,
          onChanged: (value) {
            HapticFeedback.selectionClick();
            _allVehicles = value;
            _cursor = null;
            _load(reset: true, clearItems: true);
          },
        ),
      ),
      const SizedBox(height: 10),
      // Wrapped, not a horizontal scroller: chips beyond the right edge hid
      // an active filter (QA 128).
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            HistoryChip(
              icon: Icons.date_range_rounded,
              label: _customRange == null
                  ? 'Chọn khoảng ngày'
                  : '${DateFormat('dd/MM').format(_customRange!.start)} – ${DateFormat('dd/MM/yyyy').format(_customRange!.end)}',
              selected: _customRange != null,
              onTap: _pickDateRange,
            ),
            if (_customRange != null) ...[
              const SizedBox(width: 6),
              HistoryGlassButton(
                icon: Icons.close_rounded,
                tooltip: 'Trở về tháng hiện tại',
                size: 38,
                onPressed: () => setState(() {
                  _customRange = null;
                  _monthDirection = 0;
                  _visibleCount = 20;
                }),
              ),
            ],
            Container(
              width: 1,
              height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: LuxeColors.hairline,
            ),
            _chip('Tất cả', _filter == null, () => _setStrategy(null)),
            _chip(
              'Sạc AI',
              _filter == ChargingStrategy.aiTarget,
              () => _setStrategy(ChargingStrategy.aiTarget),
            ),
            _chip(
              'Hẹn giờ',
              _filter == ChargingStrategy.manualTimed,
              () => _setStrategy(ChargingStrategy.manualTimed),
            ),
            _chip(
              'Hoàn thành',
              _statusFilter == SmartChargeHistorySessionFilter.completed,
              () => _setStatus(SmartChargeHistorySessionFilter.completed),
              dot: LuxeColors.emerald,
            ),
            _chip(
              'Dừng sớm',
              _statusFilter == SmartChargeHistorySessionFilter.stoppedEarly,
              () => _setStatus(SmartChargeHistorySessionFilter.stoppedEarly),
              dot: historyAmber,
            ),
            _chip(
              'Thiếu số đo',
              _statusFilter == SmartChargeHistorySessionFilter.partial,
              () => _setStatus(SmartChargeHistorySessionFilter.partial),
              dot: LuxeColors.platinumMid,
            ),
          ],
        ),
      ),
      const SizedBox(height: 6),
    ],
  );

  Widget _chip(String label, bool selected, VoidCallback onTap, {Color? dot}) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: HistoryChip(
          label: label,
          selected: selected,
          dot: dot,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
        ),
      );

  // ─────────────── Timeline ───────────────

  Widget _timeline(List<SmartChargingSession> shown) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime dayOf(SmartChargingSession s) {
      final t = (s.startedAt ?? s.createdAt).toLocal();
      return DateTime(t.year, t.month, t.day);
    }

    final groups = <DateTime, List<SmartChargingSession>>{};
    for (final s in shown) {
      groups.putIfAbsent(dayOf(s), () => []).add(s);
    }
    final entries = <Widget>[];
    var reveal = 0;
    for (final group in groups.entries) {
      final day = group.key;
      final label = day == today
          ? 'Hôm nay'
          : day == today.subtract(const Duration(days: 1))
          ? 'Hôm qua'
          : DateFormat('EEEE, dd/MM', 'vi').format(day);
      entries.add(
        HistoryDayHeader(
          label: label,
          count: group.value.length,
          totalWh: group.value.fold(0.0, (v, s) => v + max(0, s.energyUsedWh)),
        ),
      );
      for (var i = 0; i < group.value.length; i++) {
        final session = group.value[i];
        entries.add(
          LuxeReveal(
            key: ValueKey('reveal-${session.sessionId}'),
            index: reveal < 6 ? reveal : 0,
            child: _sessionTile(
              session,
              isFirst: i == 0,
              isLast: i == group.value.length - 1,
            ),
          ),
        );
        reveal++;
      }
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      sliver: SliverList.list(children: entries),
    );
  }

  Widget _sessionTile(
    SmartChargingSession session, {
    required bool isFirst,
    required bool isLast,
  }) => Dismissible(
    key: ValueKey('history-session-${session.sessionId}'),
    direction: session.state.isTerminal
        ? DismissDirection.endToStart
        : DismissDirection.none,
    confirmDismiss: (_) async {
      _hide(session);
      return false;
    },
    background: Container(
      margin: const EdgeInsets.only(left: 34, bottom: 10),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: LuxeColors.danger.withValues(alpha: 0.12),
        border: Border.all(color: LuxeColors.danger.withValues(alpha: 0.35)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.visibility_off_rounded,
            color: LuxeColors.danger,
            size: 20,
          ),
          SizedBox(width: 8),
          Text(
            'Ẩn phiên',
            style: TextStyle(
              color: LuxeColors.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
    child: HistoryTimelineTile(
      session: session,
      isFirst: isFirst,
      isLast: isLast,
      onTap: () => _openDetail(session),
      onLongPress: session.state.isTerminal ? () => _hide(session) : null,
    ),
  );

  Widget _footer(
    List<SmartChargingSession> shown,
    List<SmartChargingSession> visible,
  ) {
    final done = _cursor == null && shown.length >= visible.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
      child: done
          ? Row(
              children: [
                const Expanded(child: Divider()),
                Flexible(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Đã hiển thị toàn bộ phiên sạc',
                      textAlign: TextAlign.center,
                      style: LuxeText.label.copyWith(fontSize: 11.5),
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            )
          : Center(
              child: OutlinedButton(
                onPressed: _loading
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
                          color: LuxeColors.emerald,
                        ),
                      )
                    : const Text('TẢI THÊM'),
              ),
            ),
    );
  }

  void _setStrategy(ChargingStrategy? value) {
    if (_filter == value) return;
    _filter = value;
    if (value != null) _statusFilter = SmartChargeHistorySessionFilter.all;
    _load(reset: true, clearItems: true);
  }

  void _setStatus(SmartChargeHistorySessionFilter value) => setState(() {
    _visibleCount = 20;
    _statusFilter = _statusFilter == value
        ? SmartChargeHistorySessionFilter.all
        : value;
  });

  void _changeMonth(int delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _customRange = null;
      _visibleCount = 20;
      _monthDirection = delta;
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
  }

  Future<void> _pickDateRange() async {
    final contextGeneration = _contextGeneration;
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: _customRange,
      helpText: 'Chọn khoảng lịch sử sạc',
      saveText: 'ÁP DỤNG',
    );
    if (selected == null ||
        !mounted ||
        contextGeneration != _contextGeneration) {
      return;
    }
    if (selected.duration.inDays > 366) {
      AppPopup.showWarning(
        'Khoảng thời gian quá dài',
        detail: 'Mỗi lần xem hoặc xuất báo cáo tối đa 12 tháng.',
      );
      return;
    }
    setState(() {
      _customRange = selected;
      _monthDirection = 0;
      _visibleCount = 20;
    });
  }

  Future<void> _openDetail(SmartChargingSession session) async {
    final contextGeneration = _contextGeneration;
    final controller = widget.controller;
    final deletedOrChanged = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: luxeSheetBarrier,
      builder: (_) => FractionallySizedBox(
        heightFactor: .96,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Consumer(
            builder: (context, ref, _) => SmartChargeSessionDetailScreen(
              controller: controller,
              ownerUid: ref.watch(currentUidProvider),
              session: session,
              asSheet: true,
            ),
          ),
        ),
      ),
    );
    if (!mounted || contextGeneration != _contextGeneration) return;
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
    if (!_exportAllowed) {
      PremiumGate.showUpgrade(context, PremiumFeature.historyExport);
      return;
    }
    final contextGeneration = _contextGeneration;
    final controller = widget.controller;
    final from = _rangeStart;
    final to = _rangeEnd;
    final allVehicles = _allVehicles;
    final vehicleId = _vehicleId;
    final format = await showLuxeSheet<ChargeReportFormat>(
      context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: LuxeColors.hairlineStrong,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('BÁO CÁO', style: LuxeText.eyebrow),
              const SizedBox(height: 6),
              const Text('Xuất báo cáo', style: LuxeText.title),
              const SizedBox(height: 6),
              Text(
                '${_customRange == null ? DateFormat('MM/yyyy').format(_selectedMonth) : '${DateFormat('dd/MM/yyyy').format(_customRange!.start)} – ${DateFormat('dd/MM/yyyy').format(_customRange!.end)}'} · ${_allVehicles ? 'Tất cả xe' : 'Xe đang chọn'}',
                style: LuxeText.caption,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, ChargeReportFormat.pdf),
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('Xuất PDF'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, ChargeReportFormat.csv),
                icon: const Icon(Icons.table_view_rounded),
                label: const Text('Xuất CSV'),
              ),
            ],
          ),
        ),
      ),
    );
    if (format == null || !mounted || contextGeneration != _contextGeneration) {
      return;
    }
    try {
      final result = await controller.exportHistory(
        ChargeReportRequest(
          format: format,
          from: from,
          to: to,
          allVehicles: allVehicles,
          vehicleId: allVehicles ? null : vehicleId,
        ),
      );
      if (!mounted || contextGeneration != _contextGeneration) return;
      AppPopup.showSuccess(
        'Đã tạo báo cáo',
        detail: '${result.sessionCount} phiên · đã mở bảng chia sẻ Android.',
      );
    } on Object catch (error) {
      if (!mounted || contextGeneration != _contextGeneration) return;
      AppPopup.showError(
        'Không thể xuất báo cáo',
        detail: AppErrorFormatter.format(error),
      );
    }
  }

  Widget _errorState() => Padding(
    padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: LuxeColors.glass,
            border: Border.all(color: LuxeColors.hairline),
          ),
          child: const Icon(
            Icons.cloud_off_rounded,
            size: 28,
            color: LuxeColors.platinumMid,
          ),
        ),
        const SizedBox(height: 16),
        Text(_error!, textAlign: TextAlign.center, style: LuxeText.item),
        const SizedBox(height: 6),
        const Text(
          'Kiểm tra kết nối mạng rồi thử lại.',
          textAlign: TextAlign.center,
          style: LuxeText.caption,
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: () => _load(reset: true),
          child: const Text('THỬ LẠI'),
        ),
      ],
    ),
  );

  Future<void> _hide(SmartChargingSession session) async {
    if (!session.state.isTerminal) return;
    final contextGeneration = _contextGeneration;
    final controller = widget.controller;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LuxeColors.sheet,
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
    if (confirmed != true ||
        !mounted ||
        contextGeneration != _contextGeneration) {
      return;
    }
    try {
      await controller.hideSession(session.sessionId);
      if (mounted && contextGeneration == _contextGeneration) {
        setState(
          () =>
              _items.removeWhere((item) => item.sessionId == session.sessionId),
        );
        AppPopup.showMessage(
          'Đã ẩn phiên khỏi lịch sử.',
          kind: AppNoticeKind.success,
        );
      }
    } catch (error) {
      if (mounted && contextGeneration == _contextGeneration) {
        AppPopup.showError(
          AppErrorFormatter.format(error),
          userInitiated: true,
        );
      }
    }
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.onExport, required this.exportAllowed});
  final VoidCallback onExport;
  final bool exportAllowed;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NHẬT KÝ NĂNG LƯỢNG', style: LuxeText.eyebrow),
            SizedBox(height: 6),
            Text('Lịch sử sạc', style: LuxeText.title),
            SizedBox(height: 4),
            Text(
              'Phiên sạc, điện năng đã đo và chi phí ước tính.',
              style: LuxeText.caption,
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      PremiumLocked(
        feature: PremiumFeature.historyExport,
        allowed: exportAllowed,
        tagAlignment: Alignment.bottomCenter,
        tagPadding: EdgeInsets.zero,
        child: HistoryGlassButton(
          icon: Icons.ios_share_rounded,
          tooltip: 'Xuất báo cáo',
          onPressed: onExport,
        ),
      ),
    ],
  );
}

class _KpiDivider extends StatelessWidget {
  const _KpiDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, color: LuxeColors.hairline);
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({
    this.isFiltered = false,
    this.onClearFilter,
    this.onStartCharging,
  });
  final bool isFiltered;
  final VoidCallback? onClearFilter;
  final VoidCallback? onStartCharging;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 18, 28, 48),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isFiltered)
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: LuxeColors.glass,
              border: Border.all(color: LuxeColors.hairline),
            ),
            child: const Icon(
              Icons.filter_alt_off_rounded,
              size: 26,
              color: LuxeColors.platinumMid,
            ),
          )
        else
          const HistoryEmptyArt(),
        const SizedBox(height: 18),
        Text(
          isFiltered
              ? 'Không có phiên sạc phù hợp bộ lọc'
              : 'Chưa có phiên Smart Charge hoàn tất',
          textAlign: TextAlign.center,
          style: LuxeText.item,
        ),
        const SizedBox(height: 6),
        Text(
          isFiltered
              ? 'Thử đổi khoảng ngày hoặc chuyển bộ lọc sang Tất cả.'
              : 'Lịch sử sạc sẽ hiển thị tại đây sau khi phiên sạc kết thúc và ngắt kết nối an toàn.',
          textAlign: TextAlign.center,
          style: LuxeText.caption,
        ),
        if (isFiltered && onClearFilter != null) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onClearFilter,
            icon: const Icon(Icons.clear_all_rounded, size: 18),
            label: const Text('Xóa bộ lọc'),
          ),
        ] else if (!isFiltered && onStartCharging != null) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onStartCharging,
            icon: const Icon(Icons.bolt_rounded, size: 20),
            label: const Text('Bắt đầu phiên sạc đầu tiên'),
          ),
        ],
      ],
    ),
  );
}

class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: historyAmber.withValues(alpha: 0.08),
      border: Border.all(color: historyAmber.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, size: 18, color: historyAmber),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$message Đang hiển thị dữ liệu gần nhất.',
            style: LuxeText.caption.copyWith(color: LuxeColors.text),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('THỬ LẠI')),
      ],
    ),
  );
}

// ═════════════════════════════ Session detail ═════════════════════════════

enum _ChartMetric { power, voltage, current, temperature, energy }

class SmartChargeSessionDetailScreen extends StatefulWidget {
  const SmartChargeSessionDetailScreen({
    super.key,
    required this.controller,
    required this.session,
    this.ownerUid,
    this.asSheet = false,
  });
  final SmartChargingController controller;
  final SmartChargingSession session;
  final String? ownerUid;

  /// Shows a drag handle; the same layout also works as a pushed page.
  final bool asSheet;

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
  int _contextGeneration = 0;
  bool _contextUnavailable = false;
  bool _showTechnical = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _load();
    _startPolling();
  }

  void _startPolling() {
    _liveTimer?.cancel();
    if (!_session.state.isTerminal) {
      _liveTimer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
    }
  }

  @override
  void didUpdateWidget(covariant SmartChargeSessionDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.ownerUid != widget.ownerUid ||
        oldWidget.session.sessionId != widget.session.sessionId ||
        oldWidget.session.vehicleId != widget.session.vehicleId) {
      _contextGeneration++;
      _session = widget.session;
      _points = null;
      _summary = null;
      _error = null;
      _loadingTelemetry = false;
      // A sheet can outlive its originating tab during an account change.
      // Do not display or query the previous account's session in that case.
      _contextUnavailable =
          oldWidget.ownerUid != widget.ownerUid &&
          oldWidget.session.sessionId == widget.session.sessionId;
      if (_contextUnavailable) {
        _liveTimer?.cancel();
        return;
      }
      _load();
      _startPolling();
    }
  }

  @override
  void dispose() {
    _contextGeneration++;
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loadingTelemetry || _contextUnavailable) return;
    _loadingTelemetry = true;
    final contextGeneration = _contextGeneration;
    final controller = widget.controller;
    final sessionId = _session.sessionId;
    bool isCurrent() => mounted && contextGeneration == _contextGeneration;
    try {
      final existing = _points;
      final after = existing == null || existing.isEmpty
          ? null
          : existing.last.timestamp.toUtc().toIso8601String();
      final incoming = await controller.getTelemetry(
        sessionId,
        after: after,
        limit: 120,
      );
      if (!isCurrent()) return;
      setState(() {
        final live = controller.currentUiState.session;
        if (live?.sessionId == _session.sessionId) _session = live!;
        final merged = after == null
            ? incoming
            : <SmartChargeTelemetryPoint>[...existing!, ...incoming];
        // A retry or a backend cache can return an overlapping sample. Keep
        // the chart bounded and deterministic by timestamp.
        final byTimestamp = <String, SmartChargeTelemetryPoint>{
          for (final point in merged)
            point.timestamp.toUtc().toIso8601String(): point,
        };
        final points = byTimestamp.values.toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        if (points.length > 600) {
          points.removeRange(0, points.length - 600);
        }
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
      if (isCurrent()) {
        setState(() => _error = 'Không thể tải dữ liệu biểu đồ.');
      }
    } finally {
      if (isCurrent()) _loadingTelemetry = false;
    }
  }

  Widget _frame(List<Widget> children) => Theme(
    data: LuxeTheme.of(context),
    child: Scaffold(
      backgroundColor: LuxeColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LuxeBackdrop(),
          SafeArea(
            top: !widget.asSheet,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 36),
              children: children,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _topBar() => Column(
    children: [
      if (widget.asSheet)
        Center(
          child: Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: LuxeColors.hairlineStrong,
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: HistoryGlassButton(
          icon: widget.asSheet ? Icons.close_rounded : Icons.arrow_back_rounded,
          tooltip: 'Đóng',
          size: 40,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_contextUnavailable) {
      return _frame([
        _topBar(),
        const SizedBox(height: 120),
        const Icon(
          Icons.lock_outline_rounded,
          size: 34,
          color: LuxeColors.platinumMid,
        ),
        const SizedBox(height: 14),
        const Text(
          'Tài khoản đã thay đổi. Hãy mở lại lịch sử sạc.',
          textAlign: TextAlign.center,
          style: LuxeText.item,
        ),
      ]);
    }
    final (_, statusColor) = historyStatus(_session);
    final started = (_session.startedAt ?? _session.createdAt).toLocal();
    final stateLabel = switch (_session.state) {
      ChargingSessionState.arming => 'Đang chuẩn bị',
      ChargingSessionState.starting => 'Đang bật sạc',
      ChargingSessionState.active =>
        'Đang sạc · Mục tiêu ${_session.targetSoc.round()}%',
      ChargingSessionState.stopping => 'Đang dừng sạc',
      ChargingSessionState.completed =>
        _session.energyQuality == 'partial'
            ? 'Đã hoàn tất · thiếu một phần số đo'
            : 'Đã hoàn tất',
      ChargingSessionState.cancelled => 'Đã dừng',
      ChargingSessionState.interrupted => 'Bị gián đoạn',
      ChargingSessionState.failed => 'Phiên gặp lỗi',
    };
    final terminal = _session.state.isTerminal;
    return _frame([
      _topBar(),
      LuxeReveal(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('dd/MM/yyyy · HH:mm').format(started).toUpperCase(),
              style: LuxeText.eyebrow,
            ),
            const SizedBox(height: 6),
            Text(historyStrategy(_session), style: LuxeText.title),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                HistoryStatusPill(label: stateLabel, color: statusColor),
                Text(
                  formatChargeDuration(historySessionDuration(_session)),
                  style: LuxeText.label,
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      LuxeReveal(index: 1, child: SessionSocSummary(session: _session)),
      const SizedBox(height: 14),
      LuxeReveal(index: 2, child: _kpis()),
      const SizedBox(height: 14),
      LuxeReveal(
        index: 3,
        child: LuxeGlass(
          radius: 24,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                title: 'Diễn biến telemetry',
                subtitle: 'Chạm và kéo trên biểu đồ để xem chi tiết',
              ),
              const SizedBox(height: 12),
              _metricSelector(),
              const SizedBox(height: 14),
              if (_error != null && _points != null) ...[
                _StaleNotice(message: _error!, onRetry: _load),
                const SizedBox(height: 10),
              ],
              SizedBox(height: 230, child: _chart()),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      LuxeReveal(index: 4, child: _technicalCard()),
      const SizedBox(height: 22),
      FilledButton.icon(
        onPressed: terminal ? _confirmSoc : null,
        icon: const Icon(Icons.battery_saver_rounded, size: 20),
        label: Text(
          _session.actualEndSoc == null
              ? 'Nhập % trên đồng hồ xe'
              : 'Sửa % đã nhập (${_session.actualEndSoc!.round()}%)',
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: terminal ? _hideSession : null,
        icon: const Icon(Icons.visibility_off_rounded, size: 20),
        label: const Text('Ẩn phiên khỏi lịch sử'),
      ),
      const SizedBox(height: 4),
      TextButton.icon(
        onPressed: terminal ? _privacyErase : null,
        icon: const Icon(Icons.delete_forever_rounded, size: 20),
        label: const Text('Xóa vĩnh viễn dữ liệu phiên'),
        style: TextButton.styleFrom(foregroundColor: LuxeColors.danger),
      ),
      const SizedBox(height: 10),
      const Text(
        'Các chỉ số pin là ước tính, không phải dữ liệu BMS. Dung lượng khả dụng chỉ hiện khi phiên đủ chất lượng.',
        textAlign: TextAlign.center,
        style: TextStyle(color: LuxeColors.dim, fontSize: 12.5, height: 1.45),
      ),
    ]);
  }

  Widget _kpis() {
    final summary = _summary;
    // Without a telemetry summary (some samples missing) the session's own
    // metered energy still stands: the list showed 1.97 kWh while this tile
    // said "—" (QA 135).
    double? positive(double? value) =>
        value != null && value > 0 ? value : null;
    final gridWh =
        positive(summary?.gridEnergyWh) ?? positive(_session.energyUsedWh);
    final duration = historySessionDuration(_session);
    // A summary without samples carries 0 W: fall back to energy over time.
    final powerW =
        positive(summary?.averagePowerW) ??
        positive(_session.averagePowerW) ??
        (gridWh != null && duration.inMinutes >= 1
            ? gridWh * 3600 / duration.inSeconds
            : null);
    final avgPower = powerW == null || powerW <= 0
        ? '—'
        : '${(powerW / 1000).toStringAsFixed(2)} kW';
    final items = [
      (
        icon: Icons.electric_bolt_rounded,
        title: 'Điện từ lưới',
        value: gridWh == null ? '—' : historyEnergy(gridWh),
        highlight: true,
      ),
      (
        icon: Icons.payments_rounded,
        title: 'Chi phí phiên',
        value: historyCost(_session.estimatedCostVnd),
        highlight: false,
      ),
      (
        icon: Icons.speed_rounded,
        title: 'Công suất TB',
        value: avgPower,
        highlight: false,
      ),
      (
        icon: Icons.timer_rounded,
        title: 'Thời gian sạc',
        value: formatChargeDuration(duration),
        highlight: false,
      ),
      (
        icon: Icons.battery_charging_full_rounded,
        title: 'Vào pin (ước tính)',
        value: summary == null ? '—' : historyEnergy(summary.estimatedStoredWh),
        highlight: false,
      ),
      (
        icon: Icons.health_and_safety_rounded,
        title: 'Dung lượng khả dụng',
        value: summary?.estimatedUsableCapacityWh == null
            ? 'Cần xác nhận'
            : historyEnergy(summary!.estimatedUsableCapacityWh!),
        highlight: false,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: _SectionTitle(title: 'Tổng quan phiên sạc'),
        ),
        ResponsiveCardGrid(
          spacing: 10,
          minCardWidth: 140,
          children: [
            for (final item in items)
              LuxeGlass(
                selected: item.highlight,
                radius: 18,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          item.icon,
                          size: 15,
                          color: item.highlight
                              ? LuxeColors.emerald
                              : LuxeColors.platinumMid,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LuxeText.label.copyWith(fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: item.highlight
                            ? LuxeColors.emerald
                            : LuxeColors.platinumHi,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _metricSelector() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (metric, label) in const [
          (_ChartMetric.power, 'W'),
          (_ChartMetric.voltage, 'V'),
          (_ChartMetric.current, 'A'),
          (_ChartMetric.temperature, '°C'),
          (_ChartMetric.energy, 'Wh'),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: HistoryChip(
              label: label,
              selected: _metric == metric,
              onTap: () {
                if (_metric == metric) return;
                HapticFeedback.selectionClick();
                setState(() => _metric = metric);
              },
            ),
          ),
      ],
    ),
  );

  Widget _chart() {
    if (_error != null && _points == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: LuxeText.caption),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    if (_points == null) {
      return const Center(
        child: SizedBox.square(
          dimension: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: LuxeColors.emerald,
          ),
        ),
      );
    }
    if (_points!.isEmpty) {
      return const Center(
        child: Text(
          'Phiên này chưa có telemetry chi tiết.',
          textAlign: TextAlign.center,
          style: LuxeText.caption,
        ),
      );
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
    const axisStyle = TextStyle(fontSize: 11, color: LuxeColors.dim);
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260),
      child: LineChart(
        key: ValueKey(_metric),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 450),
        LineChartData(
          minY: 0,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: Color(0x14FFFFFF),
              strokeWidth: 1,
              dashArray: [3, 5],
            ),
          ),
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
                reservedSize: 26,
                getTitlesWidget: (value, meta) =>
                    Text('${value.round()}m', style: axisStyle),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                getTitlesWidget: (value, meta) {
                  final text = value == value.roundToDouble()
                      ? '${value.toInt()}'
                      : value.toStringAsFixed(1);
                  return Text(
                    text,
                    style: axisStyle,
                    maxLines: 1,
                    softWrap: false,
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            getTouchedSpotIndicator: (bar, indexes) => [
              for (final _ in indexes)
                TouchedSpotIndicatorData(
                  const FlLine(color: Color(0x55FFFFFF), strokeWidth: 1),
                  FlDotData(
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                          radius: 4.5,
                          color: LuxeColors.platinumHi,
                          strokeWidth: 3,
                          strokeColor: LuxeColors.emerald.withValues(
                            alpha: 0.45,
                          ),
                        ),
                  ),
                ),
            ],
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => LuxeColors.raisedHigh,
              tooltipRoundedRadius: 12,
              tooltipBorder: const BorderSide(color: LuxeColors.hairline),
              getTooltipItems: (items) => items
                  .map(
                    (item) => LineTooltipItem(
                      '${item.x.toStringAsFixed(1)} phút\n${item.y.toStringAsFixed(1)} ${_metricUnit(_metric)}',
                      const TextStyle(
                        color: LuxeColors.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
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
                color: LuxeColors.emerald.withValues(alpha: 0.6),
                strokeWidth: 1.2,
              ),
              for (final minute in rearmMarkers)
                VerticalLine(
                  x: minute,
                  color: historyAmber,
                  strokeWidth: 1.2,
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
                    color: historyAmber,
                    strokeWidth: 1.2,
                    dashArray: [4, 4],
                  ),
              if (_session.state.isTerminal)
                VerticalLine(
                  x: source.last.elapsedSeconds / 60,
                  color:
                      _session.stopReason == ChargingStopReason.manual ||
                          _session.userStopReason != UserStopReason.none
                      ? LuxeColors.danger
                      : LuxeColors.emerald,
                  strokeWidth: 1.6,
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
                gradient: const LinearGradient(
                  colors: [LuxeColors.platinum, LuxeColors.emerald],
                ),
                barWidth: 2.4,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  checkToShowDot: (spot, _) =>
                      transportMarkers.contains(spot.x),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      LuxeColors.emerald.withValues(alpha: 0.22),
                      LuxeColors.emerald.withValues(alpha: 0.0),
                    ],
                  ),
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

  Widget _technicalCard() => LuxeGlass(
    radius: 24,
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => setState(() => _showTechnical = !_showTechnical),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  const Expanded(
                    child: _SectionTitle(
                      title: 'Thông số kỹ thuật & AI',
                      subtitle: 'Mã phiên, thiết bị, mô hình dự đoán',
                    ),
                  ),
                  AnimatedRotation(
                    turns: _showTechnical ? 0.5 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: LuxeColors.platinumMid,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        LuxeFold(
          alignment: Alignment.topCenter,
          child: _showTechnical
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _technicalSummary(),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    ),
  );

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
    final contextGeneration = _contextGeneration;
    final controller = widget.controller;
    final session = _session;
    SmartChargeEnergySummary? summary;
    // The sheet saves and shows progress (QA 135).
    final reading = await ConfirmActualSocSheet.show(
      context,
      estimatedSoc: session.estimatedSoc,
      startSoc: session.startSoc,
      onSave: (reading) async {
        try {
          summary = await controller.confirmActualEndSoc(
            session,
            reading.soc,
            odoKm: reading.odoKm,
          );
          return null;
        } catch (error) {
          return AppErrorFormatter.format(error);
        }
      },
    );
    if (reading == null ||
        summary == null ||
        !mounted ||
        contextGeneration != _contextGeneration) {
      return;
    }
    setState(() {
      _session = _session.copyWith(
        actualEndSoc: reading.soc,
        endOdoKm: reading.odoKm,
      );
      _summary = summary;
    });
    AppPopup.showSuccess(
      'Đã lưu ${reading.soc.toStringAsFixed(0)}%',
      detail: 'Đã thêm vào dữ liệu học; app báo khi đủ để huấn luyện.',
    );
    unawaited(TrainingReadiness.refresh(session.vehicleId));
  }

  Future<void> _privacyErase() async {
    final contextGeneration = _contextGeneration;
    final controller = widget.controller;
    final sessionId = _session.sessionId;
    final input = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: LuxeColors.sheet,
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
              sessionId,
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
            onPressed: () =>
                Navigator.pop(dialogContext, input.text.trim() == sessionId),
            child: const Text('XÓA VĨNH VIỄN'),
          ),
        ],
      ),
    );
    final code = input.text.trim();
    input.dispose();
    if (confirmed != true ||
        !mounted ||
        contextGeneration != _contextGeneration) {
      return;
    }
    try {
      await controller.privacyEraseSession(sessionId, code);
      if (mounted && contextGeneration == _contextGeneration) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              contextGeneration == _contextGeneration &&
              Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
          }
        });
      }
    } catch (error) {
      if (mounted && contextGeneration == _contextGeneration) {
        AppPopup.showError(
          AppErrorFormatter.format(error),
          userInitiated: true,
        );
      }
    }
  }

  Future<void> _hideSession() async {
    final contextGeneration = _contextGeneration;
    final controller = widget.controller;
    final sessionId = _session.sessionId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LuxeColors.sheet,
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
    if (confirmed != true ||
        !mounted ||
        contextGeneration != _contextGeneration) {
      return;
    }
    try {
      await controller.hideSession(sessionId);
      if (mounted && contextGeneration == _contextGeneration) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              contextGeneration == _contextGeneration &&
              Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
          }
        });
      }
    } on Object catch (error) {
      if (mounted && contextGeneration == _contextGeneration) {
        AppPopup.showError(
          'Không thể ẩn phiên',
          detail: AppErrorFormatter.format(error),
        );
      }
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: LuxeColors.text,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 2),
        Text(subtitle!, style: LuxeText.caption.copyWith(fontSize: 12.5)),
      ],
    ],
  );
}

String _metricUnit(_ChartMetric metric) => switch (metric) {
  _ChartMetric.power => 'W',
  _ChartMetric.voltage => 'V',
  _ChartMetric.current => 'A',
  _ChartMetric.temperature => '°C',
  _ChartMetric.energy => 'Wh',
};
