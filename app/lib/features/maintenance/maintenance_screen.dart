import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/utils/number_text.dart';
import '../../core/widgets/vehicle_picker_sheet.dart';
import '../../core/widgets/empty_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../core/theme/luxe_theme.dart';
import '../../data/services/account_reminder_service.dart';
import 'widgets/odo_widgets.dart';
import 'widgets/vinfast_schedule_sheet.dart';
import '../../core/providers/app_providers.dart';
import '../../core/utils/app_error_formatter.dart';
import '../../core/widgets/error_state.dart';
import '../../data/models/maintenance_task_model.dart';
import '../../data/services/maintenance_reminder_service.dart';
import 'widgets/maintenance_complete_sheet.dart';
import '../../data/repositories/maintenance_repository.dart';
import 'vinfast_service_catalog.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/theme/plan_style.dart';

// =============================================================================
// Service / Maintenance Screen V6 — Category-first, Urgency-clear
// =============================================================================

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  int _currentOdo = 0;
  _UrgencyFilter _filter = _UrgencyFilter.all;
  Future<List<AccountReminder>>? _reminders;
  String? _remindersFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCurrentOdo());
  }

  Future<void> _loadCurrentOdo() async {
    final vehicleId = ref.read(selectedVehicleIdProvider);
    if (vehicleId.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _reminders = AccountReminderService.instance.list(vehicleId);
      _remindersFor = vehicleId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    // QA 137: the ODO follows the vehicle live: a reading saved from the
    // Overview, a confirmed charge or Pinova Bot shows here at once (it was
    // read once when the screen opened).
    _currentOdo = vehicleId.isEmpty
        ? 0
        : ref.watch(vehicleProvider(vehicleId)).valueOrNull?.currentOdo ?? 0;
    if (vehicleId.isNotEmpty && _remindersFor != vehicleId) {
      _remindersFor = vehicleId;
      _reminders = AccountReminderService.instance.list(vehicleId);
    }

    return Theme(
      data: LuxeTheme.of(context),
      child: Scaffold(
        backgroundColor: LuxeColors.background,
        // QA 141: the same header as every other page (glass back button).
        appBar: Navigator.canPop(context)
            ? const LuxeAppBar(title: 'Lịch bảo dưỡng')
            : null,
        extendBodyBehindAppBar: false,
        floatingActionButton: vehicleId.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _showAddEditDialog(context),
                backgroundColor: LuxeColors.platinum,
                foregroundColor: LuxeColors.shell,
                shape: const StadiumBorder(),
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Thêm mốc',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                elevation: 6,
              ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const LuxeBackdrop(),
            SafeArea(
              top: !Navigator.canPop(context),
              child: vehicleId.isEmpty
                  ? _buildSelectVehiclePlaceholder()
                  : _buildBody(vehicleId),
            ),
          ],
        ),
      ),
    );
  }

  // Same pattern as the Charge tab: a way forward, not a dead end (Task 125).
  Widget _buildSelectVehiclePlaceholder() {
    return EmptyState(
      icon: Icons.two_wheeler_rounded,
      title: 'Chưa chọn xe',
      message: 'Chọn xe để xem lịch bảo dưỡng theo ODO.',
      actionLabel: 'Chọn xe ngay',
      onAction: () => VehiclePickerSheet.show(context, ref),
    );
  }

  // Cached per vehicle: a filter-chip setState used to re-subscribe (and
  // flash the loading state) on every tap (Task 125).
  String? _tasksVehicleId;
  Stream<List<MaintenanceTaskModel>>? _tasks;
  List<MaintenanceTaskModel> _latestTasks = const [];

  Widget _buildBody(String vehicleId) {
    if (_tasksVehicleId != vehicleId || _tasks == null) {
      _tasksVehicleId = vehicleId;
      _tasks = MaintenanceRepository.watchMaintenanceTasks(vehicleId);
    }
    return StreamBuilder<List<MaintenanceTaskModel>>(
      stream: _tasks,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _buildLoading();
        }
        if (snapshot.hasError) {
          return ErrorState.fromError(
            error: snapshot.error!,
            prefix: 'Không tải được lịch bảo dưỡng',
            onRetry: () => setState(() {}),
          );
        }

        final tasks = snapshot.data ?? const <MaintenanceTaskModel>[];
        _latestTasks = tasks;
        final counts = _Counts.from(tasks, _currentOdo);
        final filtered = _filterTasks(tasks, _filter);

        return RefreshIndicator(
          color: context.planAccent,
          backgroundColor: LuxeColors.raised,
          onRefresh: _loadCurrentOdo,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: LuxeReveal(child: _buildOdoHero(tasks)),
                ),
              ),
              if (tasks.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: LuxeReveal(
                      index: 1,
                      child: OutlinedButton.icon(
                        onPressed: () => _openStandardSchedule(tasks),
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: const Text('Tạo lịch chuẩn VinFast'),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: LuxeReveal(index: 2, child: _buildFilterChips(counts)),
              ),
              if (filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: _buildEmpty(tasks.isEmpty, tasks),
                  ),
                )
              else
                ..._buildTaskSlivers(filtered),
              SliverToBoxAdapter(child: _buildYearSummary(tasks)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: _buildReminders(),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          ),
        );
      },
    );
  }

  // ── ODO hero: rolling odometer + kilometre track ───────────────────

  Widget _buildOdoHero(List<MaintenanceTaskModel> tasks) {
    return LuxeGlass(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('ODO HIỆN TẠI', style: LuxeText.eyebrow),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: OdometerDrum(value: _currentOdo),
                ),
              ),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'km',
                  style: TextStyle(color: LuxeColors.muted, fontSize: 15.5),
                ),
              ),
            ],
          ),
          if (_currentOdo == 0) ...[
            const SizedBox(height: 8),
            const Text(
              'Chưa có số ODO của xe. Cập nhật ODO trong hồ sơ xe để các mốc được tính chính xác.',
              style: TextStyle(
                color: LuxeColors.champagne,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 16),
          OdoTrack(currentOdo: _currentOdo, tasks: tasks),
        ],
      ),
    );
  }

  // ── Filter chips (with urgency dots and counts) ────────────────────

  Widget _buildFilterChips(_Counts counts) {
    final entries = <(String, _UrgencyFilter, int, Color?)>[
      ('Tất cả', _UrgencyFilter.all, counts.total, null),
      (
        'Quá hạn',
        _UrgencyFilter.overdue,
        counts.overdue,
        urgencyColor(MaintenanceUrgency.overdue),
      ),
      (
        'Sắp tới',
        _UrgencyFilter.dueSoon,
        counts.dueSoon,
        urgencyColor(MaintenanceUrgency.dueSoon),
      ),
      (
        'Dự kiến',
        _UrgencyFilter.upcoming,
        counts.upcoming,
        urgencyColor(MaintenanceUrgency.upcoming),
      ),
      (
        'Đã xong',
        _UrgencyFilter.completed,
        counts.completed,
        urgencyColor(MaintenanceUrgency.completed),
      ),
    ];
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _LuxeFilterChip(
                label: e.$1,
                count: e.$3,
                dot: e.$4,
                selected: _filter == e.$2,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _filter = e.$2);
                },
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildTaskSlivers(List<MaintenanceTaskModel> filtered) {
    final items = <Widget>[];
    MaintenanceUrgency? section;
    var index = 0;
    for (final task in filtered) {
      final u = task.urgency(_currentOdo, now: DateTime.now());
      if (_filter == _UrgencyFilter.all && u != section) {
        section = u;
        final n = filtered
            .where((t) => t.urgency(_currentOdo, now: DateTime.now()) == u)
            .length;
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: urgencyColor(u),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_UrgencyMeta.of(u).label} · $n',
                  style: LuxeText.label.copyWith(letterSpacing: 1.4),
                ),
              ],
            ),
          ),
        );
      }
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: LuxeReveal(
            index: 3 + (index++ % 6),
            child: _TaskCard(
              task: task,
              currentOdo: _currentOdo,
              onTap: () => _showAddEditDialog(context, task: task),
              onComplete: () => _completeTask(task),
              onDelete: () => _confirmDelete(task),
              onChecklist: VinFastSchedule.isVisit(task)
                  ? () => VinFastScheduleSheet.showChecklist(
                      context,
                      milestone: task.targetOdo,
                    )
                  : null,
            ),
          ),
        ),
      );
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        sliver: SliverList(delegate: SliverChildListDelegate(items)),
      ),
    ];
  }

  Widget _buildEmpty(bool noTasks, List<MaintenanceTaskModel> tasks) {
    return LuxeGlass(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
      child: Column(
        children: [
          const Icon(
            Icons.build_circle_rounded,
            size: 44,
            color: _Lx.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            noTasks ? 'Chưa có mốc bảo dưỡng' : 'Không có mục theo bộ lọc này',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: LuxeColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (noTasks) ...[
            const SizedBox(height: 6),
            const Text(
              'Tạo mốc bảo dưỡng định kỳ kế tiếp theo sổ tay VinFast, hoặc tự thêm mốc riêng.',
              textAlign: TextAlign.center,
              style: LuxeText.body,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openStandardSchedule(tasks),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Tạo lịch chuẩn VinFast'),
              ),
            ),
            TextButton(
              onPressed: () => _showAddEditDialog(context),
              child: const Text('Thêm mốc đầu tiên'),
            ),
          ],
        ],
      ),
    );
  }

  /// QA 154: what this year's service book adds up to; nothing when the
  /// year has no completed work.
  Widget _buildYearSummary(List<MaintenanceTaskModel> tasks) {
    final summary = MaintenanceYearSummary.of(tasks, DateTime.now());
    if (summary == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: LuxeNotice(
        key: const ValueKey('maintenance-year-summary'),
        icon: Icons.menu_book_rounded,
        message: summary.sentence,
      ),
    );
  }

  // ── BatteryBot reminders (read only) ───────────────────────────────

  Widget _buildReminders() {
    return FutureBuilder<List<AccountReminder>>(
      future: _reminders,
      builder: (context, snap) {
        final items = snap.data ?? const <AccountReminder>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return LuxeReveal(
          index: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('NHẮC LỊCH TỪ PINOVA BOT', style: LuxeText.eyebrow),
              const SizedBox(height: 4),
              const Text(
                'Chỉ xem tại đây. Sửa hoặc hủy qua Pinova Bot.',
                style: LuxeText.caption,
              ),
              const SizedBox(height: 10),
              LuxeGlass(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: 12, endIndent: 12),
                      _ReminderRow(item: items[i]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          for (final h in const [190.0, 52.0, 110.0, 110.0]) ...[
            Container(
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: LuxeColors.glass,
                border: Border.all(color: LuxeColors.hairline),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Future<void> _openStandardSchedule(List<MaintenanceTaskModel> tasks) async {
    final vehicleId = ref.read(selectedVehicleIdProvider);
    if (vehicleId.isEmpty) return;
    final created = await VinFastScheduleSheet.show(
      context,
      currentOdo: _currentOdo,
      existing: tasks,
      onCreate: (draft) async {
        try {
          await MaintenanceRepository.createMaintenanceTask(
            vehicleId: vehicleId,
            title: VinFastSchedule.visitTitle(draft.milestone),
            description: VinFastSchedule.visitDescription(draft.milestone),
            targetOdo: draft.milestone,
            serviceType: ServiceType.inspection,
            scheduledDate: draft.date,
          );
          return null;
        } catch (e) {
          return AppErrorFormatter.format(e);
        }
      },
    );
    if (created != null && mounted) {
      AppPopup.showMessage(
        'Đã tạo mốc bảo dưỡng định kỳ ${groupThousands(created)} km',
        kind: AppNoticeKind.success,
      );
    }
  }

  // ── Filtering helpers ──────────────────────────────────────────────

  List<MaintenanceTaskModel> _filterTasks(
    List<MaintenanceTaskModel> tasks,
    _UrgencyFilter filter,
  ) {
    final filtered = filter == _UrgencyFilter.all
        ? List<MaintenanceTaskModel>.from(tasks)
        : tasks
              .where(
                (t) =>
                    t.urgency(_currentOdo, now: DateTime.now()) ==
                    filter.toUrgency(),
              )
              .toList();
    // Ưu tiên hiển thị: overdue > dueSoon > upcoming > completed; cùng nhóm
    // sort theo targetOdo tăng dần.
    int rank(MaintenanceTaskModel t) {
      switch (t.urgency(_currentOdo, now: DateTime.now())) {
        case MaintenanceUrgency.overdue:
          return 0;
        case MaintenanceUrgency.dueSoon:
          return 1;
        case MaintenanceUrgency.upcoming:
          return 2;
        case MaintenanceUrgency.completed:
          return 3;
      }
    }

    filtered.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return a.targetOdo.compareTo(b.targetOdo);
    });
    return filtered;
  }

  // ── Actions ────────────────────────────────────────────────────────

  /// QA 154: "done" asks where the odometer stood and, if the owner
  /// wants, what it cost. One tap kept only today's date.
  Future<void> _completeTask(MaintenanceTaskModel task) async {
    final id = task.taskId;
    if (id == null) return;
    HapticFeedback.lightImpact();
    final record = await MaintenanceCompleteSheet.show(
      context,
      task: task,
      currentOdo: _currentOdo,
      onSave: (record) async {
        try {
          // Noon, so the day is the same in every time zone.
          final at = DateTime(
            record.date.year,
            record.date.month,
            record.date.day,
            12,
          );
          await MaintenanceRepository.updateMaintenanceTask(id, {
            'isCompleted': true,
            'completedDate': at.toUtc(),
            'completedOdo': record.odo,
            'costVnd': record.costVnd,
            'completionNote': record.note,
          });
          return null;
        } catch (e) {
          return AppErrorFormatter.format(e);
        }
      },
    );
    if (record == null || !mounted) return;
    unawaited(MaintenanceReminderService.resetNotifyFlag(id));
    AppPopup.showMessage(
      'Đã ghi vào sổ bảo dưỡng',
      kind: AppNoticeKind.success,
      // QA 150: a mistaken tap could not be taken back.
      actionLabel: 'Hoàn tác',
      action: () => _undoComplete(task),
    );
    await _offerNext(
      task.copyWith(completedOdo: record.odo, completedDate: record.date),
    );
  }

  /// QA 150: a periodic service used to end with its one milestone. The
  /// app offers the next one; the sheet opens filled in and editable.
  Future<void> _offerNext(MaintenanceTaskModel done) async {
    final next = VinFastServiceCatalog.nextAfter(
      done,
      currentOdo: _currentOdo,
      all: _latestTasks,
    );
    if (next == null || !mounted) return;
    final ok = await showLuxeConfirm(
      context,
      title: 'Tạo mốc kế tiếp?',
      message:
          '${done.title}: theo sổ tay, lần tới ở mốc '
          '${groupThousands(next.targetOdo)} km'
          '${next.scheduledDate == null ? '' : ' hoặc ngày ${DateFormat('dd/MM/yyyy').format(next.scheduledDate!)}, điều kiện nào đến trước'}. '
          'Bạn sửa được trước khi lưu.',
      confirmLabel: 'Tạo mốc',
      danger: false,
    );
    if (ok == true && mounted) _showAddEditDialog(context, task: next);
  }

  Future<void> _undoComplete(MaintenanceTaskModel task) async {
    try {
      await MaintenanceRepository.updateMaintenanceTask(task.taskId!, {
        'isCompleted': false,
        'completedDate': null,
        'completedOdo': null,
        'costVnd': null,
        'completionNote': null,
      });
    } catch (e) {
      if (mounted) {
        AppPopup.showError(AppErrorFormatter.format(e), userInitiated: true);
      }
    }
  }

  Future<void> _confirmDelete(MaintenanceTaskModel task) async {
    final ok = await showLuxeConfirm(
      context,
      title: 'Xóa mốc bảo dưỡng',
      message: task.isCompleted
          ? 'Xóa "${task.title}" khỏi sổ bảo dưỡng? Không hoàn tác được.'
          : 'Xóa "${task.title}"? Không hoàn tác được.',
      confirmLabel: 'Xóa',
    );
    if (ok != true || task.taskId == null) return;
    try {
      await MaintenanceRepository.deleteMaintenanceTask(task.taskId!);
      unawaited(MaintenanceReminderService.resetNotifyFlag(task.taskId!));
      if (mounted) {
        AppPopup.showMessage('Đã xóa', kind: AppNoticeKind.success);
      }
    } catch (e) {
      if (mounted) {
        AppPopup.showError(AppErrorFormatter.format(e), userInitiated: true);
      }
    }
  }

  void _showAddEditDialog(BuildContext context, {MaintenanceTaskModel? task}) {
    // QA 155: the same sheet frame as the rest of the app.
    showLuxeSheet<void>(
      context,
      builder: (_) => Builder(
        builder: (_) => _MaintenanceDialog(
          task: task,
          currentOdo: _currentOdo,
          onSave: (newTask) async {
            final vehicleId = ref.read(selectedVehicleIdProvider);
            if (vehicleId.isEmpty) return;
            try {
              if (task?.taskId != null) {
                await MaintenanceRepository.updateMaintenanceTask(
                  task!.taskId!,
                  newTask.toFirestore(),
                );
                // A moved milestone or date may be due again later.
                unawaited(
                  MaintenanceReminderService.resetNotifyFlag(task.taskId!),
                );
              } else {
                await MaintenanceRepository.createMaintenanceTask(
                  vehicleId: vehicleId,
                  title: newTask.title,
                  description: newTask.description,
                  targetOdo: newTask.targetOdo,
                  serviceType: newTask.serviceType,
                  scheduledDate: newTask.scheduledDate,
                );
              }
              if (context.mounted) {
                Navigator.pop(context);
                AppPopup.showMessage(
                  task?.taskId != null
                      ? 'Đã cập nhật'
                      : 'Đã thêm mốc bảo dưỡng',
                  kind: AppNoticeKind.success,
                );
              }
            } catch (e) {
              if (context.mounted) {
                AppPopup.showError(
                  AppErrorFormatter.format(e),
                  userInitiated: true,
                );
              }
            }
          },
        ),
      ),
    );
  }
}

enum _UrgencyFilter { all, overdue, dueSoon, upcoming, completed }

extension on _UrgencyFilter {
  MaintenanceUrgency? toUrgency() => switch (this) {
    _UrgencyFilter.overdue => MaintenanceUrgency.overdue,
    _UrgencyFilter.dueSoon => MaintenanceUrgency.dueSoon,
    _UrgencyFilter.upcoming => MaintenanceUrgency.upcoming,
    _UrgencyFilter.completed => MaintenanceUrgency.completed,
    _UrgencyFilter.all => null,
  };
}

/// Luxe palette for the add/edit sheet and helpers (was AppColors).
abstract final class _Lx {
  static const background = Color(0xFF0C0D0F);
  static const surfaceVariant = LuxeColors.raised;
  static const glassBorder = LuxeColors.hairline;
  static const success = LuxeColors.emerald;
  static const warning = LuxeColors.champagne;
  static const error = LuxeColors.danger;
  static const textPrimary = LuxeColors.text;
  static const textSecondary = LuxeColors.muted;
  static const textTertiary = LuxeColors.dim;
  static const textHint = LuxeColors.muted; // QA 139 (hint contrast)
}

class _LuxeFilterChip extends StatelessWidget {
  const _LuxeFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.dot,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: selected
                ? const LinearGradient(
                    colors: [LuxeColors.platinumHi, LuxeColors.platinum],
                  )
                : null,
            color: selected ? null : LuxeColors.glass,
            border: Border.all(
              color: selected ? Colors.transparent : LuxeColors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                '$label  $count',
                style: TextStyle(
                  color: selected ? LuxeColors.shell : LuxeColors.text,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// One milestone: type medallion, status, distance and progress over the
/// service interval, plus complete / edit / delete.
class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.currentOdo,
    required this.onTap,
    required this.onComplete,
    required this.onDelete,
    this.onChecklist,
  });

  final MaintenanceTaskModel task;
  final int currentOdo;
  final VoidCallback onTap;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  /// The work of a periodic visit, for the garage (QA 155).
  final VoidCallback? onChecklist;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final urgency = task.urgency(currentOdo, now: now);
    final days = task.daysUntilScheduled(now);
    final color = urgencyColor(urgency);
    final meta = _ServiceTypeMeta.of(task.serviceType);
    final remain = task.remainingKm(currentOdo);
    // The first visit is 1 000 km from new; the rest are 5 000 apart.
    final interval = task.targetOdo < VinFastSchedule.intervalKm
        ? VinFastSchedule.firstVisitKm
        : VinFastSchedule.intervalKm;
    final progress = task.isCompleted
        ? 1.0
        : (1 - remain / interval).clamp(0.0, 1.0);
    final status = switch (urgency) {
      // QA 154: say which of the two limits made it due.
      MaintenanceUrgency.overdue =>
        remain <= 0
            ? 'Quá ${groupThousands(-remain)} km'
            : 'Quá ngày hẹn ${-(days ?? 0)} ngày · còn ${groupThousands(remain)} km',
      MaintenanceUrgency.dueSoon =>
        remain <= MaintenanceTaskModel.dueSoonKm
            ? 'Còn ${groupThousands(remain)} km'
            : days == 0
            ? 'Hẹn hôm nay · còn ${groupThousands(remain)} km'
            : 'Hẹn sau $days ngày · còn ${groupThousands(remain)} km',
      MaintenanceUrgency.upcoming =>
        'Còn ${groupThousands(remain)} km · mốc ${groupThousands(task.targetOdo)} km',
      MaintenanceUrgency.completed =>
        task.completedDate == null
            ? 'Đã hoàn thành'
            : [
                'Hoàn thành ${DateFormat('dd/MM/yyyy').format(task.completedDate!.toLocal())}',
                if (task.completedOdo != null)
                  '${groupThousands(task.completedOdo!)} km',
                if (task.costVnd != null && task.costVnd! > 0)
                  formatVnd(task.costVnd!),
              ].join(' · '),
    };

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: LuxeGlass(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.3, -0.4),
                        colors: [
                          meta.color.withValues(alpha: 0.3),
                          meta.color.withValues(alpha: 0.06),
                        ],
                      ),
                      border: Border.all(
                        color: meta.color.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Icon(meta.icon, size: 20, color: meta.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: task.isCompleted
                                ? LuxeColors.muted
                                : LuxeColors.text,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            decoration: task.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: LuxeColors.dim,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          status,
                          style: TextStyle(
                            color: color,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!task.isCompleted)
                    IconButton(
                      tooltip: 'Đánh dấu hoàn thành',
                      onPressed: onComplete,
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      color: context.planAccent,
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Tùy chọn',
                    color: LuxeColors.raised,
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      color: LuxeColors.platinumMid,
                    ),
                    onSelected: (v) => switch (v) {
                      'list' => onChecklist?.call(),
                      'edit' => onTap(),
                      _ => onDelete(),
                    },
                    itemBuilder: (_) => [
                      if (onChecklist != null)
                        const PopupMenuItem(
                          value: 'list',
                          child: Text('Xem hạng mục'),
                        ),
                      const PopupMenuItem(value: 'edit', child: Text('Sửa')),
                      const PopupMenuItem(value: 'delete', child: Text('Xóa')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _UrgencyBar(value: progress, color: color),
              ),
              if (task.scheduledDate != null ||
                  task.completionNote != null ||
                  task.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    [
                      if (task.scheduledDate != null)
                        'Hẹn ${DateFormat('dd/MM/yyyy').format(task.scheduledDate!.toLocal())}',
                      if (task.completionNote != null) task.completionNote!,
                      if (task.description.isNotEmpty) task.description,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LuxeText.caption,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UrgencyBar extends StatelessWidget {
  const _UrgencyBar({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 900),
    curve: LuxeMotion.enter,
    builder: (context, v, _) => SizedBox(
      height: 4,
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: const Color(0x14FFFFFF),
              ),
            ),
            Container(
              width: c.maxWidth * v,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 6,
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

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.item});
  final AccountReminder item;

  @override
  Widget build(BuildContext context) {
    final (icon, kind) = switch (item.kind) {
      'warranty' => (Icons.verified_rounded, 'Bảo hành'),
      'appointment' => (Icons.event_rounded, 'Lịch hẹn'),
      _ => (Icons.build_rounded, 'Bảo dưỡng'),
    };
    final today = DateTime.now();
    final due = item.dueDate.toLocal();
    final days = DateTime(
      due.year,
      due.month,
      due.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    final when = days < 0
        ? 'đã qua ${-days} ngày'
        : days == 0
        ? 'hôm nay'
        : 'còn $days ngày';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: LuxeColors.platinum),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: LuxeColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$kind · ${DateFormat('dd/MM/yyyy').format(due)} · $when',
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

class _Counts {
  final int overdue;
  final int dueSoon;
  final int upcoming;
  final int completed;

  const _Counts({
    required this.overdue,
    required this.dueSoon,
    required this.upcoming,
    required this.completed,
  });

  int get total => overdue + dueSoon + upcoming + completed;

  factory _Counts.from(List<MaintenanceTaskModel> tasks, int currentOdo) {
    var overdue = 0, dueSoon = 0, upcoming = 0, completed = 0;
    for (final t in tasks) {
      switch (t.urgency(currentOdo, now: DateTime.now())) {
        case MaintenanceUrgency.overdue:
          overdue++;
          break;
        case MaintenanceUrgency.dueSoon:
          dueSoon++;
          break;
        case MaintenanceUrgency.upcoming:
          upcoming++;
          break;
        case MaintenanceUrgency.completed:
          completed++;
          break;
      }
    }
    return _Counts(
      overdue: overdue,
      dueSoon: dueSoon,
      upcoming: upcoming,
      completed: completed,
    );
  }
}

// =============================================================================
// Category card (overdue / dueSoon / upcoming / completed)
// =============================================================================

class _ServiceTypeMeta {
  final IconData icon;
  final String label;

  const _ServiceTypeMeta(this.icon, this.label);

  /// QA 150: every service type had its own off-palette colour. The icon
  /// and the label tell them apart; the tint is the neutral platinum.
  Color get color => LuxeColors.platinumMid;

  static _ServiceTypeMeta of(ServiceType type) {
    switch (type) {
      // ── Hệ điều khiển ──
      case ServiceType.brakeLever:
        return const _ServiceTypeMeta(Icons.pan_tool_alt_rounded, 'Tay phanh');
      case ServiceType.throttleGrip:
        return const _ServiceTypeMeta(Icons.swipe_rounded, 'Vỏ bọc, tay ga');
      case ServiceType.lightsHornDash:
        return const _ServiceTypeMeta(
          Icons.dashboard_rounded,
          'Đèn, còi, đồng hồ',
        );

      // ── Khung & khoá ──
      case ServiceType.sideStand:
        return const _ServiceTypeMeta(Icons.support_rounded, 'Chân chống');
      case ServiceType.seatLock:
        return const _ServiceTypeMeta(Icons.lock_rounded, 'Khóa yên');

      // ── Pin ──
      case ServiceType.battery:
        return const _ServiceTypeMeta(
          Icons.battery_charging_full_rounded,
          'Pin Li-ion',
        );
      case ServiceType.batteryCheck:
        return const _ServiceTypeMeta(
          Icons.battery_charging_full_rounded,
          'Pin',
        );

      // ── Phanh ──
      case ServiceType.brakeFluid:
        return const _ServiceTypeMeta(Icons.water_drop_rounded, 'Dầu phanh');
      case ServiceType.brakeFront:
        return const _ServiceTypeMeta(
          Icons.do_not_disturb_on_rounded,
          'Phanh trước',
        );
      case ServiceType.brakeRear:
        return const _ServiceTypeMeta(
          Icons.do_not_disturb_on_rounded,
          'Phanh sau',
        );
      case ServiceType.brakeHose:
        return const _ServiceTypeMeta(Icons.cable_rounded, 'Ống dầu phanh');
      case ServiceType.brakeCable:
        return const _ServiceTypeMeta(Icons.cable_rounded, 'Dây phanh');
      case ServiceType.brakeService:
        return const _ServiceTypeMeta(Icons.do_not_disturb_on_rounded, 'Phanh');

      // ── Bánh xe ──
      case ServiceType.wheelFront:
        return const _ServiceTypeMeta(Icons.donut_large_rounded, 'Vành trước');
      case ServiceType.wheelRear:
        return const _ServiceTypeMeta(Icons.donut_large_rounded, 'Vành sau');
      case ServiceType.tireFront:
        return const _ServiceTypeMeta(Icons.tire_repair_rounded, 'Lốp trước');
      case ServiceType.tireRear:
        return const _ServiceTypeMeta(Icons.tire_repair_rounded, 'Lốp sau');
      case ServiceType.tireRotation:
        return const _ServiceTypeMeta(Icons.tire_repair_rounded, 'Lốp xe');

      // ── Hệ treo ──
      case ServiceType.steeringBearing:
        return const _ServiceTypeMeta(Icons.gps_fixed_rounded, 'Cổ phốt');
      case ServiceType.suspensionFront:
        return const _ServiceTypeMeta(
          Icons.unfold_more_rounded,
          'Giảm xóc trước',
        );
      case ServiceType.suspensionRear:
        return const _ServiceTypeMeta(
          Icons.unfold_more_rounded,
          'Giảm xóc sau',
        );

      // ── Động cơ ──
      case ServiceType.motor:
        return const _ServiceTypeMeta(Icons.electric_bolt_rounded, 'Động cơ');
      case ServiceType.motorSeal:
        return const _ServiceTypeMeta(Icons.shield_rounded, 'Phớt động cơ');

      // ── Legacy / khác ──
      case ServiceType.oilChange:
        return const _ServiceTypeMeta(Icons.oil_barrel_rounded, 'Thay dầu');
      case ServiceType.airFilter:
        return const _ServiceTypeMeta(Icons.air_rounded, 'Lọc gió');
      case ServiceType.coolantFlush:
        return const _ServiceTypeMeta(Icons.water_drop_rounded, 'Nước làm mát');
      case ServiceType.transmissionService:
        return const _ServiceTypeMeta(Icons.settings_suggest_rounded, 'Hộp số');
      case ServiceType.inspection:
        return const _ServiceTypeMeta(
          Icons.fact_check_rounded,
          'Bảo dưỡng định kỳ',
        );
      case ServiceType.other:
        return const _ServiceTypeMeta(Icons.build_rounded, 'Khác');
    }
  }
}

class _UrgencyMeta {
  final String label;
  final Color barColor;
  final Color textColor;
  final Color borderColor;

  const _UrgencyMeta({
    required this.label,
    required this.barColor,
    required this.textColor,
    required this.borderColor,
  });

  static _UrgencyMeta of(MaintenanceUrgency u) {
    switch (u) {
      case MaintenanceUrgency.overdue:
        return _UrgencyMeta(
          label: 'QUÁ HẠN',
          barColor: _Lx.error,
          textColor: _Lx.error,
          borderColor: _Lx.error.withAlpha(120),
        );
      case MaintenanceUrgency.dueSoon:
        return _UrgencyMeta(
          label: 'SẮP TỚI',
          barColor: _Lx.warning,
          textColor: _Lx.warning,
          borderColor: _Lx.warning.withAlpha(100),
        );
      case MaintenanceUrgency.upcoming:
        return _UrgencyMeta(
          label: 'DỰ KIẾN',
          barColor: LuxeColors.platinum,
          textColor: _Lx.textSecondary,
          borderColor: _Lx.glassBorder,
        );
      case MaintenanceUrgency.completed:
        return _UrgencyMeta(
          label: 'XONG',
          barColor: _Lx.success,
          textColor: _Lx.success,
          borderColor: _Lx.glassBorder,
        );
    }
  }
}

// =============================================================================
// Add / Edit dialog (bottom sheet)
// =============================================================================

class _MaintenanceDialog extends StatefulWidget {
  final MaintenanceTaskModel? task;
  final int currentOdo;
  final Future<void> Function(MaintenanceTaskModel) onSave;

  const _MaintenanceDialog({
    this.task,
    required this.currentOdo,
    required this.onSave,
  });

  @override
  State<_MaintenanceDialog> createState() => _MaintenanceDialogState();
}

class _MaintenanceDialogState extends State<_MaintenanceDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _odoCtrl;
  ServiceType _selectedType = ServiceType.other;
  DateTime? _scheduledDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _descCtrl = TextEditingController(text: t?.description ?? '');
    _odoCtrl = TextEditingController(text: t?.targetOdo.toString() ?? '');
    _selectedType = t?.serviceType ?? ServiceType.other;
    _scheduledDate = t?.scheduledDate;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _odoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final preset = VinFastServiceCatalog.presetOf(_selectedType);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.task?.taskId != null
                          ? 'Sửa mốc bảo dưỡng'
                          : 'Thêm mốc bảo dưỡng',
                      style: const TextStyle(
                        color: _Lx.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // QA 150: a 30 dp target with no label.
                  IconButton(
                    key: const ValueKey('maintenance-sheet-close'),
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: _Lx.surfaceVariant,
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: _Lx.textSecondary,
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSelectedTypeBadge(),
              const SizedBox(height: 14),
              _sectionLabel('Tên dịch vụ'),
              const SizedBox(height: 6),
              _buildField(
                _titleCtrl,
                hint: 'VD: Thay má phanh sau',
                icon: Icons.label_outline_rounded,
              ),
              const SizedBox(height: 14),
              _sectionLabel('Mốc ODO (km)'),
              const SizedBox(height: 6),
              _buildField(
                _odoCtrl,
                hint: 'VD: 10000',
                icon: Icons.speed_rounded,
                keyboardType: TextInputType.number,
                fieldKey: const ValueKey('maintenance-form-odo'),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (widget.currentOdo > 0)
                    'Xe đang ở ${groupThousands(widget.currentOdo)} km.',
                  if (preset != null || _selectedType == ServiceType.inspection)
                    'Sổ tay VinFast: lần đầu 1 000 km, sau đó mỗi 5 000 km hoặc 6 tháng.',
                ].join(' '),
                style: LuxeText.caption,
              ),
              const SizedBox(height: 14),
              _sectionLabel('Ngày hẹn (không bắt buộc)'),
              const SizedBox(height: 6),
              _buildDatePicker(),
              const SizedBox(height: 6),
              const Text(
                'Có ngày hẹn thì mốc đến hạn theo km hoặc theo ngày, điều kiện nào đến trước.',
                style: LuxeText.caption,
              ),
              const SizedBox(height: 14),
              _sectionLabel('Ghi chú (không bắt buộc)'),
              const SizedBox(height: 6),
              _buildField(
                _descCtrl,
                hint: 'Việc cần làm, nơi làm',
                icon: Icons.notes_rounded,
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: context.planAccent,
                  foregroundColor: _Lx.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  widget.task?.taskId != null ? 'Cập nhật' : 'Thêm mốc',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: _Lx.textSecondary,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller, {
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    Key? fieldKey,
  }) {
    return TextField(
      key: fieldKey,
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: _Lx.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _Lx.textHint),
        prefixIcon: Icon(icon, color: _Lx.textTertiary, size: 18),
        filled: true,
        fillColor: _Lx.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }

  /// Hiển thị badge cho loại đang chọn (tap-able để mở bottom sheet đổi loại).
  Widget _buildSelectedTypeBadge() {
    final meta = _ServiceTypeMeta.of(_selectedType);
    return GestureDetector(
      onTap: _showTypePicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: meta.color.withAlpha(30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: meta.color.withAlpha(120), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: meta.color.withAlpha(50),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(meta.icon, color: meta.color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Loại dịch vụ',
                    style: TextStyle(
                      color: _Lx.textTertiary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Text(
                    meta.label,
                    style: TextStyle(
                      color: meta.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.expand_more_rounded, color: meta.color, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _showTypePicker() async {
    final picked = await showLuxeSheet<ServiceType>(
      context,
      builder: (ctx) => _TypePickerSheet(currentType: _selectedType),
    );
    if (picked != null) _applyType(picked);
  }

  String? _autoTitle;
  String? _autoOdo;

  /// QA 155: choosing an item of the service book fills the name and the
  /// book's next milestone, unless the owner already typed their own.
  /// (This replaces a strip of twenty preset cards above the fields.)
  void _applyType(ServiceType type) {
    HapticFeedback.selectionClick();
    final preset = VinFastServiceCatalog.presetOf(type);
    setState(() {
      _selectedType = type;
      if (widget.task?.taskId != null) return;
      final here = VinFastSchedule.proposed(currentOdo: widget.currentOdo);
      final next = here <= widget.currentOdo
          ? VinFastSchedule.after(here)
          : here;
      final title = type == ServiceType.inspection
          ? VinFastSchedule.visitTitle(next)
          : preset?.title;
      if (title == null) return;
      final typedTitle = _titleCtrl.text.trim();
      if (typedTitle.isEmpty || typedTitle == _autoTitle) {
        _titleCtrl.text = title;
        _autoTitle = title;
      }
      final typedOdo = _odoCtrl.text.trim();
      if (typedOdo.isEmpty || typedOdo == _autoOdo) {
        _odoCtrl.text = '$next';
        _autoOdo = '$next';
      }
    });
  }

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _scheduledDate ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 30)),
          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
          helpText: 'Ngày hẹn',
        );
        if (date != null) setState(() => _scheduledDate = date);
      },
      child: Container(
        // QA 155: 48 dp tall like the fields above; the clear button
        // was a 16 dp target.
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(
          color: _Lx.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _Lx.glassBorder),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              color: _Lx.textTertiary,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _scheduledDate != null
                    ? DateFormat('dd/MM/yyyy').format(_scheduledDate!)
                    : 'Chọn ngày',
                style: TextStyle(
                  color: _scheduledDate != null
                      ? _Lx.textPrimary
                      : _Lx.textHint,
                  fontSize: 14,
                ),
              ),
            ),
            if (_scheduledDate != null)
              IconButton(
                tooltip: 'Bỏ ngày hẹn',
                onPressed: () => setState(() => _scheduledDate = null),
                icon: const Icon(
                  Icons.close_rounded,
                  color: _Lx.textSecondary,
                  size: 18,
                ),
              )
            else
              const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleCtrl.text.trim();
    // "5 000" and "5.000" are the same milestone.
    final odo = MaintenanceCompleteSheet.parseAmount(_odoCtrl.text) ?? 0;
    if (title.isEmpty || odo <= 0 || odo > 999999) {
      AppPopup.showMessage(
        'Nhập tên dịch vụ và mốc ODO từ 1 đến 999 999 km',
        kind: AppNoticeKind.warning,
      );
      return;
    }
    final task = MaintenanceTaskModel(
      taskId: widget.task?.taskId,
      vehicleId: widget.task?.vehicleId ?? '',
      title: title,
      description: _descCtrl.text.trim(),
      targetOdo: odo,
      isCompleted: widget.task?.isCompleted ?? false,
      completedDate: widget.task?.completedDate,
      createdAt: widget.task?.createdAt ?? DateTime.now(),
      scheduledDate: _scheduledDate,
      serviceType: _selectedType,
      completedOdo: widget.task?.completedOdo,
      costVnd: widget.task?.costVnd,
      completionNote: widget.task?.completionNote,
    );
    // QA 154: a second tap while the first save ran made a duplicate.
    setState(() => _saving = true);
    try {
      await widget.onSave(task);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// =============================================================================
// Type picker bottom sheet (đổi loại dịch vụ thủ công)
// =============================================================================

class _TypePickerSheet extends StatelessWidget {
  final ServiceType currentType;

  const _TypePickerSheet({required this.currentType});

  @override
  Widget build(BuildContext context) {
    final groups = _groupedTypes();
    return SafeArea(
      child: Padding(
        // The handle comes from showLuxeSheet (QA 139).
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chọn loại dịch vụ',
              style: TextStyle(
                color: _Lx.textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(
                          entry.key.toUpperCase(),
                          style: TextStyle(
                            color: _Lx.textTertiary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final type in entry.value)
                            _typeChip(context, type),
                        ],
                      ),
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

  Widget _typeChip(BuildContext context, ServiceType type) {
    final meta = _ServiceTypeMeta.of(type);
    final selected = type == currentType;
    return GestureDetector(
      onTap: () => Navigator.pop(context, type),
      child: Container(
        // QA 155: the chips were 36 dp tall.
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? meta.color.withAlpha(40) : _Lx.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? meta.color : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              meta.icon,
              color: selected ? meta.color : _Lx.textSecondary,
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              meta.label,
              style: TextStyle(
                color: selected ? meta.color : _Lx.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Map ServiceType → group label cho picker.
  Map<String, List<ServiceType>> _groupedTypes() {
    return {
      // QA 155: the visit the service book plans comes first.
      'Theo sổ tay': [ServiceType.inspection],
      'Hệ điều khiển': [
        ServiceType.brakeLever,
        ServiceType.throttleGrip,
        ServiceType.lightsHornDash,
      ],
      'Khung & khoá': [ServiceType.sideStand, ServiceType.seatLock],
      'Pin': [ServiceType.battery],
      'Phanh': [
        ServiceType.brakeFluid,
        ServiceType.brakeFront,
        ServiceType.brakeRear,
        ServiceType.brakeHose,
        ServiceType.brakeCable,
      ],
      'Bánh xe': [
        ServiceType.wheelFront,
        ServiceType.wheelRear,
        ServiceType.tireFront,
        ServiceType.tireRear,
      ],
      'Hệ treo': [
        ServiceType.steeringBearing,
        ServiceType.suspensionFront,
        ServiceType.suspensionRear,
      ],
      'Động cơ': [
        ServiceType.motor,
        // Not an item of the published schedule.
        if (currentType == ServiceType.motorSeal) ServiceType.motorSeal,
      ],
      // QA 154: engine oil, air filter, coolant and gearbox are not parts
      // of an electric scooter; a task that already has one keeps it.
      'Khác': [
        ServiceType.other,
        if (const {
          ServiceType.oilChange,
          ServiceType.airFilter,
          ServiceType.coolantFlush,
          ServiceType.transmissionService,
        }.contains(currentType))
          currentType,
      ],
    };
  }
}

/// QA 154: this year's completed work, for the line under the list.
class MaintenanceYearSummary {
  const MaintenanceYearSummary({
    required this.year,
    required this.count,
    required this.costVnd,
    required this.costed,
  });

  final int year;
  final int count;
  final int costVnd;

  /// How many of them have a cost recorded.
  final int costed;

  static MaintenanceYearSummary? of(
    List<MaintenanceTaskModel> tasks,
    DateTime now,
  ) {
    var count = 0, cost = 0, costed = 0;
    for (final task in tasks) {
      final done = task.completedDate?.toLocal();
      if (!task.isCompleted || done == null || done.year != now.year) continue;
      count++;
      final value = task.costVnd;
      if (value != null && value > 0) {
        cost += value;
        costed++;
      }
    }
    if (count == 0) return null;
    return MaintenanceYearSummary(
      year: now.year,
      count: count,
      costVnd: cost,
      costed: costed,
    );
  }

  String get sentence {
    final head = 'Sổ bảo dưỡng $year: $count hạng mục đã làm';
    if (costed == 0) return '$head. Chưa ghi chi phí.';
    final partial = costed < count ? ' ($costed hạng mục có ghi chi phí)' : '';
    return '$head, tổng chi ${formatVnd(costVnd)}$partial.';
  }
}
