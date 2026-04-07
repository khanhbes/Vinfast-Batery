import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../data/models/maintenance_task_model.dart';
import '../../data/repositories/maintenance_repository.dart';
import '../../data/services/maintenance_reminder_service.dart';
import '../home/home_screen.dart';

// =============================================================================
// Maintenance Screen — Quản lý mốc bảo dưỡng
// =============================================================================

// Provider cho danh sách tasks
final _maintenanceTasksProvider =
    FutureProvider.family<List<MaintenanceTaskModel>, String>((ref, vehicleId) {
  if (vehicleId.isEmpty) return [];
  return ref.watch(maintenanceRepositoryProvider).getTasks(vehicleId);
});

class MaintenanceScreen extends ConsumerWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    final vehicleAsync = ref.watch(vehicleProvider(vehicleId));
    final tasksAsync = ref.watch(_maintenanceTasksProvider(vehicleId));

    final currentOdo = vehicleAsync.when(
      data: (v) => v?.currentOdo ?? 0,
      loading: () => 0,
      error: (_, __) => 0,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.warning,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(_maintenanceTasksProvider(vehicleId));
            ref.invalidate(vehicleProvider(vehicleId));
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bảo dưỡng',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              )),
                          Text('Lịch bảo dưỡng theo ODO',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              )),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _showAddDialog(context, ref, vehicleId),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.warning, Color(0xFFFF9800)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.warning.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.add_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ],
                ).animate().fadeIn(),
              ),
            ),

            // ODO hiện tại
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.speed_rounded,
                          color: AppColors.info, size: 18),
                      const SizedBox(width: 8),
                      Text('ODO hiện tại: $currentOdo km',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ),
              ),
            ),

            // Tasks list
            tasksAsync.when(
              data: (tasks) {
                if (tasks.isEmpty) {
                  return SliverToBoxAdapter(
                    child: _emptyState(context, ref, vehicleId),
                  );
                }

                // Chia thành: chưa hoàn thành + đã hoàn thành
                final pending = tasks.where((t) => !t.isCompleted).toList();
                final completed = tasks.where((t) => t.isCompleted).toList();

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, index) {
                        // Pending header
                        if (index == 0 && pending.isNotEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _sectionLabel('Chưa hoàn thành',
                                '${pending.length}', AppColors.warning),
                          );
                        }

                        // Pending items
                        final pendingOffset = pending.isNotEmpty ? 1 : 0;
                        if (index < pending.length + pendingOffset &&
                            index >= pendingOffset) {
                          final task = pending[index - pendingOffset];
                          return _TaskCard(
                            task: task,
                            currentOdo: currentOdo,
                            onComplete: () async {
                              await ref
                                  .read(maintenanceRepositoryProvider)
                                  .completeTask(task.taskId!);
                              await MaintenanceReminderService.resetNotifyFlag(task.taskId!);
                              ref.invalidate(
                                  _maintenanceTasksProvider(vehicleId));
                            },
                            onDelete: () async {
                              await ref
                                  .read(maintenanceRepositoryProvider)
                                  .deleteTask(task.taskId!);
                              await MaintenanceReminderService.resetNotifyFlag(task.taskId!);
                              ref.invalidate(
                                  _maintenanceTasksProvider(vehicleId));
                            },
                          ).animate().fadeIn(delay: (index * 80).ms).slideX(
                              begin: 0.1);
                        }

                        // Completed header
                        final completedHeaderIdx =
                            pending.length + pendingOffset;
                        if (index == completedHeaderIdx &&
                            completed.isNotEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 8),
                            child: _sectionLabel('Đã hoàn thành',
                                '${completed.length}', AppColors.primaryGreen),
                          );
                        }

                        // Completed items
                        final completedOffset = completedHeaderIdx +
                            (completed.isNotEmpty ? 1 : 0);
                        if (index >= completedOffset) {
                          final task = completed[index - completedOffset];
                          return Opacity(
                            opacity: 0.5,
                            child: _TaskCard(
                              task: task,
                              currentOdo: currentOdo,
                              onDelete: () async {
                                await ref
                                    .read(maintenanceRepositoryProvider)
                                    .deleteTask(task.taskId!);
                                await MaintenanceReminderService.resetNotifyFlag(task.taskId!);
                                ref.invalidate(
                                    _maintenanceTasksProvider(vehicleId));
                              },
                            ),
                          );
                        }

                        return const SizedBox.shrink();
                      },
                      childCount: pending.length +
                          completed.length +
                          (pending.isNotEmpty ? 1 : 0) +
                          (completed.isNotEmpty ? 1 : 0),
                    ),
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: LoadingSkeleton(layout: SkeletonLayout.list, itemCount: 3),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: ErrorState(
                  message: 'Không tải được dữ liệu bảo dưỡng: $e',
                  onRetry: () => ref.invalidate(_maintenanceTasksProvider(vehicleId)),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String title, String count, Color color) {
    return Row(
      children: [
        Text(title.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            )),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(count,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              )),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context, WidgetRef ref, String vehicleId) {
    return EmptyState(
      icon: Icons.build_circle_rounded,
      title: 'Chưa có mốc bảo dưỡng',
      message: 'Thêm mốc ODO để nhận nhắc nhở tự động',
      actionLabel: 'Thêm mốc bảo dưỡng',
      onAction: () => _showAddDialog(context, ref, vehicleId),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref, String vehicleId) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final odoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Thêm mốc bảo dưỡng',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'VD: Bôi trơn phanh',
                  hintStyle: const TextStyle(color: AppColors.textHint),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Mô tả (tùy chọn)',
                  hintStyle: const TextStyle(color: AppColors.textHint),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: odoCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Mốc ODO (km)',
                  hintStyle: const TextStyle(color: AppColors.textHint),
                  filled: true,
                  fillColor: AppColors.surface,
                  suffixText: 'km',
                  suffixStyle: const TextStyle(color: AppColors.textSecondary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    final odo = int.tryParse(odoCtrl.text.trim()) ?? 0;
                    if (title.isEmpty || odo <= 0) return;

                    final task = MaintenanceTaskModel(
                      vehicleId: vehicleId,
                      title: title,
                      description: descCtrl.text.trim(),
                      targetOdo: odo,
                    );

                    await ref
                        .read(maintenanceRepositoryProvider)
                        .addTask(task);
                    ref.invalidate(_maintenanceTasksProvider(vehicleId));
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Thêm',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Task Card
// =============================================================================

class _TaskCard extends StatelessWidget {
  final MaintenanceTaskModel task;
  final int currentOdo;
  final VoidCallback? onComplete;
  final VoidCallback? onDelete;

  const _TaskCard({
    required this.task,
    required this.currentOdo,
    this.onComplete,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = task.remainingKm(currentOdo);
    final isOverdue = task.isOverdue(currentOdo);
    final isDueSoon = task.isDueSoon(currentOdo);

    Color statusColor = AppColors.textTertiary;
    String statusText = 'Còn $remaining km';
    if (task.isCompleted) {
      statusColor = AppColors.primaryGreen;
      statusText = '✅ Đã hoàn thành';
    } else if (isOverdue) {
      statusColor = AppColors.error;
      statusText = '⚠️ Quá hạn ${-remaining} km';
    } else if (isDueSoon) {
      statusColor = AppColors.warning;
      statusText = '⏰ Sắp đến hạn ($remaining km)';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOverdue
              ? AppColors.error.withValues(alpha: 0.3)
              : isDueSoon
                  ? AppColors.warning.withValues(alpha: 0.3)
                  : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          // Complete button
          if (!task.isCompleted && onComplete != null)
            GestureDetector(
              onTap: onComplete,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: statusColor, width: 2),
                ),
                child: isOverdue
                    ? Icon(Icons.priority_high_rounded,
                        color: statusColor, size: 16)
                    : null,
              ),
            )
          else if (task.isCompleted)
            const Icon(Icons.check_circle_rounded,
                color: AppColors.primaryGreen, size: 28),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title,
                    style: TextStyle(
                      color: task.isCompleted
                          ? AppColors.textTertiary
                          : AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      decoration: task.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    )),
                const SizedBox(height: 4),
                Text(statusText,
                    style: TextStyle(color: statusColor, fontSize: 12)),
              ],
            ),
          ),
          // Target ODO
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${task.targetOdo}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  )),
              const Text('km',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  )),
            ],
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.textTertiary, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}
