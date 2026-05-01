import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../core/widgets/premium_card.dart';
import '../../data/models/maintenance_task_model.dart';
import '../../data/repositories/maintenance_repository.dart';
import 'vinfast_service_catalog.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCurrentOdo());
  }

  Future<void> _loadCurrentOdo() async {
    final vehicleId = ref.read(selectedVehicleIdProvider);
    if (vehicleId.isEmpty) return;
    final vehicle = await ref.read(vehicleProvider(vehicleId).future);
    if (!mounted) return;
    setState(() => _currentOdo = vehicle?.currentOdo ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: vehicleId.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddEditDialog(context),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Thêm mốc',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              elevation: 4,
            ),
      body: SafeArea(
        child: vehicleId.isEmpty
            ? _buildSelectVehiclePlaceholder()
            : _buildBody(vehicleId),
      ),
    );
  }

  Widget _buildSelectVehiclePlaceholder() {
    return const Center(
      child: EmptyState(
        icon: Icons.directions_car_outlined,
        title: 'Chưa chọn xe',
        message: 'Vào Garage để chọn 1 xe trước khi xem lịch bảo dưỡng.',
      ),
    );
  }

  Widget _buildBody(String vehicleId) {
    return StreamBuilder<List<MaintenanceTaskModel>>(
      stream: MaintenanceRepository.watchMaintenanceTasks(vehicleId),
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
        final counts = _Counts.from(tasks, _currentOdo);
        final filtered = _filterTasks(tasks, _filter);

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _loadCurrentOdo,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(counts)),
              SliverToBoxAdapter(child: _buildCategoryRow(counts)),
              SliverToBoxAdapter(child: _buildFilterChips(counts)),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: EmptyState(
                      icon: Icons.build_circle_outlined,
                      title: tasks.isEmpty
                          ? 'Chưa có mốc bảo dưỡng'
                          : 'Không có mục theo bộ lọc này',
                      message: tasks.isEmpty
                          ? 'Nhấn nút + để thêm mốc bảo dưỡng đầu tiên cho xe.'
                          : null,
                      actionLabel: tasks.isEmpty ? 'Thêm mốc đầu tiên' : null,
                      onAction:
                          tasks.isEmpty ? () => _showAddEditDialog(context) : null,
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final task = filtered[i];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _MaintenanceCard(
                          task: task,
                          currentOdo: _currentOdo,
                          onTap: () => _showAddEditDialog(context, task: task),
                          onComplete: () => _completeTask(task),
                          onDelete: () => _confirmDelete(task),
                        ).appFadeSlideIn(index: i),
                      );
                    },
                    childCount: filtered.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          ),
        );
      },
    );
  }

  // ── Header (title + ODO badge) ─────────────────────────────────────

  Widget _buildHeader(_Counts counts) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bảo dưỡng',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Theo dõi mốc bảo dưỡng theo ODO',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          if (_currentOdo > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.speed_rounded,
                      color: AppColors.primary, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '$_currentOdo km',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: AppMotion.base);
  }

  // ── Category summary cards ─────────────────────────────────────────

  Widget _buildCategoryRow(_Counts counts) {
    final cards = [
      _CategoryCard(
        label: 'Quá hạn',
        count: counts.overdue,
        color: AppColors.error,
        icon: Icons.warning_amber_rounded,
        onTap: counts.overdue == 0
            ? null
            : () => setState(() => _filter = _UrgencyFilter.overdue),
        active: _filter == _UrgencyFilter.overdue,
      ),
      _CategoryCard(
        label: 'Sắp tới',
        count: counts.dueSoon,
        color: AppColors.warning,
        icon: Icons.schedule_rounded,
        onTap: counts.dueSoon == 0
            ? null
            : () => setState(() => _filter = _UrgencyFilter.dueSoon),
        active: _filter == _UrgencyFilter.dueSoon,
      ),
      _CategoryCard(
        label: 'Dự kiến',
        count: counts.upcoming,
        color: AppColors.primary,
        icon: Icons.event_note_rounded,
        onTap: counts.upcoming == 0
            ? null
            : () => setState(() => _filter = _UrgencyFilter.upcoming),
        active: _filter == _UrgencyFilter.upcoming,
      ),
      _CategoryCard(
        label: 'Đã xong',
        count: counts.completed,
        color: AppColors.success,
        icon: Icons.check_circle_rounded,
        onTap: counts.completed == 0
            ? null
            : () => setState(() => _filter = _UrgencyFilter.completed),
        active: _filter == _UrgencyFilter.completed,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            Expanded(child: cards[i].appFadeSlideIn(index: i)),
            if (i < cards.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  // ── Filter chips ───────────────────────────────────────────────────

  Widget _buildFilterChips(_Counts counts) {
    final entries = <(String label, _UrgencyFilter v, int count)>[
      ('Tất cả', _UrgencyFilter.all, counts.total),
      ('Quá hạn', _UrgencyFilter.overdue, counts.overdue),
      ('Sắp tới', _UrgencyFilter.dueSoon, counts.dueSoon),
      ('Dự kiến', _UrgencyFilter.upcoming, counts.upcoming),
      ('Đã xong', _UrgencyFilter.completed, counts.completed),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final e in entries) ...[
              _FilterChip(
                label: e.$1,
                count: e.$3,
                selected: _filter == e.$2,
                onTap: () => setState(() => _filter = e.$2),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 28,
            width: 160,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 24),
          const Expanded(child: LoadingSkeleton(layout: SkeletonLayout.list, itemCount: 4)),
        ],
      ),
    );
  }

  // ── Filtering helpers ──────────────────────────────────────────────

  List<MaintenanceTaskModel> _filterTasks(
    List<MaintenanceTaskModel> tasks,
    _UrgencyFilter filter,
  ) {
    final filtered = filter == _UrgencyFilter.all
        ? List<MaintenanceTaskModel>.from(tasks)
        : tasks
            .where((t) => t.urgency(_currentOdo) == filter.toUrgency())
            .toList();
    // Ưu tiên hiển thị: overdue > dueSoon > upcoming > completed; cùng nhóm
    // sort theo targetOdo tăng dần.
    int rank(MaintenanceTaskModel t) {
      switch (t.urgency(_currentOdo)) {
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

  Future<void> _completeTask(MaintenanceTaskModel task) async {
    if (task.taskId == null) return;
    HapticFeedback.lightImpact();
    try {
      await MaintenanceRepository.updateMaintenanceTask(task.taskId!, {
        'isCompleted': true,
        'completedDate': DateTime.now().toUtc(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã đánh dấu hoàn thành'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(MaintenanceTaskModel task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xóa mốc bảo dưỡng',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Xóa "${task.title}"? Thao tác này không thể hoàn tác.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true || task.taskId == null) return;
    try {
      await MaintenanceRepository.deleteMaintenanceTask(task.taskId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xóa'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showAddEditDialog(BuildContext context, {MaintenanceTaskModel? task}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MaintenanceDialog(
        task: task,
        currentOdo: _currentOdo,
        onSave: (newTask) async {
          final vehicleId = ref.read(selectedVehicleIdProvider);
          if (vehicleId.isEmpty) return;
          try {
            if (task?.taskId != null) {
              await MaintenanceRepository.updateMaintenanceTask(
                  task!.taskId!, newTask.toFirestore());
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
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(task != null ? 'Đã cập nhật' : 'Đã thêm mốc bảo dưỡng'),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error),
              );
            }
          }
        },
      ),
    );
  }
}

// =============================================================================
// Filters & counts
// =============================================================================

enum _UrgencyFilter { all, overdue, dueSoon, upcoming, completed }

extension on _UrgencyFilter {
  MaintenanceUrgency? toUrgency() {
    switch (this) {
      case _UrgencyFilter.overdue:
        return MaintenanceUrgency.overdue;
      case _UrgencyFilter.dueSoon:
        return MaintenanceUrgency.dueSoon;
      case _UrgencyFilter.upcoming:
        return MaintenanceUrgency.upcoming;
      case _UrgencyFilter.completed:
        return MaintenanceUrgency.completed;
      case _UrgencyFilter.all:
        return null;
    }
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
      switch (t.urgency(currentOdo)) {
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

class _CategoryCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  const _CategoryCard({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    required this.onTap,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      borderColor: active ? color : AppColors.glassBorder,
      backgroundColor: active ? color.withAlpha(20) : AppColors.card,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withAlpha(40),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Filter chip
// =============================================================================

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.background : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.background.withAlpha(60)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: selected ? AppColors.background : AppColors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Maintenance card (single task)
// =============================================================================

class _MaintenanceCard extends StatelessWidget {
  final MaintenanceTaskModel task;
  final int currentOdo;
  final VoidCallback onTap;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  const _MaintenanceCard({
    required this.task,
    required this.currentOdo,
    required this.onTap,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final urgency = task.urgency(currentOdo);
    final remain = task.remainingKm(currentOdo);
    final progress = task.progress(currentOdo);
    final meta = _ServiceTypeMeta.of(task.serviceType);
    final urgencyMeta = _UrgencyMeta.of(urgency);

    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      borderColor: urgencyMeta.borderColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: meta.color.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(meta.icon, color: meta.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: urgency == MaintenanceUrgency.completed
                                  ? AppColors.textTertiary
                                  : AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              decoration: urgency == MaintenanceUrgency.completed
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _UrgencyBadge(meta: urgencyMeta),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusLine(urgency, task.targetOdo, currentOdo, remain),
                      style: TextStyle(
                        color: urgencyMeta.textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (task.scheduledDate != null)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(26),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${task.scheduledDate!.day}/${task.scheduledDate!.month}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              task.description,
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(urgencyMeta.barColor),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '$currentOdo / ${task.targetOdo} km',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (urgency != MaintenanceUrgency.completed)
                _ActionButton(
                  icon: Icons.check_rounded,
                  label: 'Hoàn thành',
                  color: AppColors.success,
                  onTap: onComplete,
                ),
              const SizedBox(width: 6),
              _ActionButton(
                icon: Icons.edit_outlined,
                color: AppColors.textSecondary,
                onTap: onTap,
              ),
              const SizedBox(width: 6),
              _ActionButton(
                icon: Icons.delete_outline_rounded,
                color: AppColors.error,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLine(MaintenanceUrgency u, int target, int odo, int remain) {
    switch (u) {
      case MaintenanceUrgency.overdue:
        return 'Quá hạn ${(odo - target).abs()} km';
      case MaintenanceUrgency.dueSoon:
        return 'Sắp tới hạn — còn ${remain.clamp(0, 9999)} km';
      case MaintenanceUrgency.upcoming:
        return 'Còn $remain km';
      case MaintenanceUrgency.completed:
        return 'Đã hoàn thành';
    }
  }
}

class _UrgencyBadge extends StatelessWidget {
  final _UrgencyMeta meta;
  const _UrgencyBadge({required this.meta});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: meta.barColor.withAlpha(40),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        meta.label,
        style: TextStyle(
          color: meta.textColor,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: label == null ? 8 : 10,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label!,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Service type & urgency meta tables
// =============================================================================

class _ServiceTypeMeta {
  final IconData icon;
  final Color color;
  final String label;

  const _ServiceTypeMeta(this.icon, this.color, this.label);

  static _ServiceTypeMeta of(ServiceType type) {
    switch (type) {
      // ── Hệ điều khiển ──
      case ServiceType.brakeLever:
        return const _ServiceTypeMeta(Icons.pan_tool_alt_rounded, Color(0xFFE8A87C), 'Tay phanh');
      case ServiceType.throttleGrip:
        return const _ServiceTypeMeta(Icons.swipe_rounded, Color(0xFFB59BFF), 'Vỏ bọc, tay ga');
      case ServiceType.lightsHornDash:
        return const _ServiceTypeMeta(Icons.dashboard_rounded, Color(0xFF45B7D1), 'Đèn / Còi / Đồng hồ');

      // ── Khung & khoá ──
      case ServiceType.sideStand:
        return const _ServiceTypeMeta(Icons.support_rounded, Color(0xFF9BA8B5), 'Chân chống');
      case ServiceType.seatLock:
        return const _ServiceTypeMeta(Icons.lock_rounded, Color(0xFFFBBF24), 'Khoá yên');

      // ── Pin ──
      case ServiceType.battery:
        return const _ServiceTypeMeta(Icons.battery_charging_full_rounded, Color(0xFF4ECDC4), 'Pin Li-ion');
      case ServiceType.batteryCheck:
        return const _ServiceTypeMeta(Icons.battery_charging_full_rounded, Color(0xFF4ECDC4), 'Pin');

      // ── Phanh ──
      case ServiceType.brakeFluid:
        return const _ServiceTypeMeta(Icons.water_drop_rounded, Color(0xFF45B7D1), 'Dầu phanh');
      case ServiceType.brakeFront:
        return const _ServiceTypeMeta(Icons.do_not_disturb_on_rounded, Color(0xFFFF6B6B), 'Phanh trước');
      case ServiceType.brakeRear:
        return const _ServiceTypeMeta(Icons.do_not_disturb_on_rounded, Color(0xFFFF8A65), 'Phanh sau');
      case ServiceType.brakeHose:
        return const _ServiceTypeMeta(Icons.cable_rounded, Color(0xFFFF6B6B), 'Ống dầu phanh');
      case ServiceType.brakeCable:
        return const _ServiceTypeMeta(Icons.cable_rounded, Color(0xFFFFA726), 'Dây phanh');
      case ServiceType.brakeService:
        return const _ServiceTypeMeta(Icons.do_not_disturb_on_rounded, Color(0xFFFF6B6B), 'Phanh');

      // ── Bánh xe ──
      case ServiceType.wheelFront:
        return const _ServiceTypeMeta(Icons.donut_large_rounded, Color(0xFF9BA8B5), 'Vành trước');
      case ServiceType.wheelRear:
        return const _ServiceTypeMeta(Icons.donut_large_rounded, Color(0xFF7C8B99), 'Vành sau');
      case ServiceType.tireFront:
        return const _ServiceTypeMeta(Icons.tire_repair_rounded, Color(0xFFE8A87C), 'Lốp trước');
      case ServiceType.tireRear:
        return const _ServiceTypeMeta(Icons.tire_repair_rounded, Color(0xFFD68B5F), 'Lốp sau');
      case ServiceType.tireRotation:
        return const _ServiceTypeMeta(Icons.tire_repair_rounded, Color(0xFFE8A87C), 'Lốp xe');

      // ── Hệ treo ──
      case ServiceType.steeringBearing:
        return const _ServiceTypeMeta(Icons.gps_fixed_rounded, Color(0xFFB59BFF), 'Cổ phốt');
      case ServiceType.suspensionFront:
        return const _ServiceTypeMeta(Icons.unfold_more_rounded, Color(0xFF7986CB), 'Giảm xóc trước');
      case ServiceType.suspensionRear:
        return const _ServiceTypeMeta(Icons.unfold_more_rounded, Color(0xFF5C6BC0), 'Giảm xóc sau');

      // ── Động cơ ──
      case ServiceType.motor:
        return const _ServiceTypeMeta(Icons.electric_bolt_rounded, Color(0xFF4ADE80), 'Động cơ');
      case ServiceType.motorSeal:
        return const _ServiceTypeMeta(Icons.shield_rounded, Color(0xFF66BB6A), 'Phớt động cơ');

      // ── Legacy / khác ──
      case ServiceType.oilChange:
        return const _ServiceTypeMeta(Icons.oil_barrel_rounded, Color(0xFFE8A87C), 'Thay dầu');
      case ServiceType.airFilter:
        return const _ServiceTypeMeta(Icons.air_rounded, Color(0xFF9BA8B5), 'Lọc gió');
      case ServiceType.coolantFlush:
        return const _ServiceTypeMeta(Icons.water_drop_rounded, Color(0xFF45B7D1), 'Nước làm mát');
      case ServiceType.transmissionService:
        return const _ServiceTypeMeta(Icons.settings_suggest_rounded, Color(0xFFB59BFF), 'Hộp số');
      case ServiceType.inspection:
        return const _ServiceTypeMeta(Icons.fact_check_rounded, Color(0xFF96CEB4), 'Kiểm tra');
      case ServiceType.other:
        return const _ServiceTypeMeta(Icons.build_rounded, Color(0xFF9BA8B5), 'Khác');
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
          barColor: AppColors.error,
          textColor: AppColors.error,
          borderColor: AppColors.error.withAlpha(120),
        );
      case MaintenanceUrgency.dueSoon:
        return _UrgencyMeta(
          label: 'SẮP TỚI',
          barColor: AppColors.warning,
          textColor: AppColors.warning,
          borderColor: AppColors.warning.withAlpha(100),
        );
      case MaintenanceUrgency.upcoming:
        return _UrgencyMeta(
          label: 'DỰ KIẾN',
          barColor: AppColors.primary,
          textColor: AppColors.textSecondary,
          borderColor: AppColors.glassBorder,
        );
      case MaintenanceUrgency.completed:
        return _UrgencyMeta(
          label: 'XONG',
          barColor: AppColors.success,
          textColor: AppColors.success,
          borderColor: AppColors.glassBorder,
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
  final void Function(MaintenanceTaskModel) onSave;

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
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.task != null
                          ? 'Sửa mốc bảo dưỡng'
                          : 'Thêm mốc bảo dưỡng',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.close,
                          color: AppColors.textSecondary, size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (widget.task == null) ...[
                _sectionLabel('Mẫu VinFast — chạm để tự điền'),
                const SizedBox(height: 8),
                _buildPresetSections(),
                const SizedBox(height: 16),
              ],
              _buildSelectedTypeBadge(),
              const SizedBox(height: 14),
              _sectionLabel('Tên dịch vụ'),
              const SizedBox(height: 6),
              _buildField(
                _titleCtrl,
                hint: 'VD: Thay dầu hộp số',
                icon: Icons.label_outline_rounded,
              ),
              const SizedBox(height: 14),
              _sectionLabel('Mốc ODO (km)'),
              const SizedBox(height: 6),
              _buildField(
                _odoCtrl,
                hint: 'VD: 5000',
                icon: Icons.speed_rounded,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              _sectionLabel('Mô tả (tuỳ chọn)'),
              const SizedBox(height: 6),
              _buildField(
                _descCtrl,
                hint: 'Ghi chú cho mốc bảo dưỡng',
                icon: Icons.notes_rounded,
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              _sectionLabel('Ngày hẹn (tuỳ chọn)'),
              const SizedBox(height: 6),
              _buildDatePicker(),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  widget.task != null ? 'CẬP NHẬT' : 'THÊM MỚI',
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
        color: AppColors.textSecondary,
        fontSize: 12,
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
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textHint),
        prefixIcon: Icon(icon, color: AppColors.textTertiary, size: 18),
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      color: AppColors.textTertiary,
                      fontSize: 10,
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
    final picked = await showModalBottomSheet<ServiceType>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _TypePickerSheet(currentType: _selectedType),
    );
    if (picked != null) {
      setState(() => _selectedType = picked);
    }
  }

  /// Các section preset VinFast — nhóm theo hạng mục, scroll ngang.
  Widget _buildPresetSections() {
    final groups = VinFastServiceCatalog.grouped();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6, top: 6),
            child: Text(
              entry.key.toUpperCase(),
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: entry.value.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final preset = entry.value[i];
                final meta = _ServiceTypeMeta.of(preset.type);
                final selected = _selectedType == preset.type &&
                    _titleCtrl.text.trim() == preset.title;
                return _PresetCard(
                  preset: preset,
                  meta: meta,
                  selected: selected,
                  onTap: () => _applyPreset(preset),
                ).appFadeSlideIn(index: i, duration: AppMotion.fast);
              },
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  void _applyPreset(VinFastServicePreset preset) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedType = preset.type;
      _titleCtrl.text = preset.title;
      _descCtrl.text = preset.subtitle ?? _descCtrl.text;
      // Gợi ý mốc ODO tiếp theo = ODO hiện tại + chu kỳ (làm tròn 100m).
      final base = widget.currentOdo;
      final next = ((base + preset.suggestedOdoInterval) / 100).round() * 100;
      _odoCtrl.text = '$next';
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
        );
        if (date != null) setState(() => _scheduledDate = date);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                color: AppColors.textTertiary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _scheduledDate != null
                    ? '${_scheduledDate!.day}/${_scheduledDate!.month}/${_scheduledDate!.year}'
                    : 'Chọn ngày hẹn (tuỳ chọn)',
                style: TextStyle(
                  color: _scheduledDate != null
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                  fontSize: 13,
                ),
              ),
            ),
            if (_scheduledDate != null)
              GestureDetector(
                onTap: () => setState(() => _scheduledDate = null),
                child: const Icon(Icons.close_rounded,
                    color: AppColors.textTertiary, size: 16),
              ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    final odo = int.tryParse(_odoCtrl.text.trim()) ?? 0;
    if (title.isEmpty || odo <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập tên dịch vụ và mốc ODO hợp lệ'),
          backgroundColor: AppColors.error,
        ),
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
    );
    widget.onSave(task);
  }
}

// =============================================================================
// Preset card (VinFast quick-fill)
// =============================================================================

class _PresetCard extends StatelessWidget {
  final VinFastServicePreset preset;
  final _ServiceTypeMeta meta;
  final bool selected;
  final VoidCallback onTap;

  const _PresetCard({
    required this.preset,
    required this.meta,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.emphasized,
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? meta.color.withAlpha(40) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? meta.color : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: meta.color.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(meta.icon, color: meta.color, size: 16),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${(preset.suggestedOdoInterval / 1000).toStringAsFixed(preset.suggestedOdoInterval >= 1000 ? 0 : 1)}k',
                    style: TextStyle(
                      color: meta.color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              preset.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? meta.color : AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            if (preset.subtitle != null)
              Text(
                preset.subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  height: 1.25,
                ),
              ),
          ],
        ),
      ),
    );
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Chọn loại dịch vụ',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
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
                            color: AppColors.textTertiary,
                            fontSize: 10,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? meta.color.withAlpha(40) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? meta.color : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(meta.icon, color: selected ? meta.color : AppColors.textSecondary, size: 14),
            const SizedBox(width: 6),
            Text(
              meta.label,
              style: TextStyle(
                color: selected ? meta.color : AppColors.textSecondary,
                fontSize: 12,
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
      'Hệ điều khiển': [
        ServiceType.brakeLever,
        ServiceType.throttleGrip,
        ServiceType.lightsHornDash,
      ],
      'Khung & khoá': [
        ServiceType.sideStand,
        ServiceType.seatLock,
      ],
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
        ServiceType.motorSeal,
      ],
      'Khác': [
        ServiceType.oilChange,
        ServiceType.airFilter,
        ServiceType.coolantFlush,
        ServiceType.inspection,
        ServiceType.transmissionService,
        ServiceType.other,
      ],
    };
  }
}
