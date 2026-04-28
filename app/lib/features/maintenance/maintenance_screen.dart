import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../data/models/maintenance_task_model.dart';
import '../../data/repositories/maintenance_repository.dart';

// =============================================================================
// Service / Maintenance Screen V5
// Full CRUD with Firestore + Sticky Header + Service Type Icons
// =============================================================================

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  int? _currentOdo;

  @override
  void initState() {
    super.initState();
    _loadCurrentOdo();
  }

  Future<void> _loadCurrentOdo() async {
    final vehicleId = ref.read(selectedVehicleIdProvider);
    if (vehicleId.isNotEmpty) {
      final vehicle = await ref.read(vehicleProvider(vehicleId).future);
      setState(() {
        _currentOdo = vehicle?.currentOdo ?? 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Title Section with Add Button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Service',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Vehicle maintenance log',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _showAddEditDialog(context),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),
            ),

            // Maintenance List from Firestore
            if (vehicleId.isNotEmpty)
              StreamBuilder<List<MaintenanceTaskModel>>(
                stream: MaintenanceRepository.watchMaintenanceTasks(vehicleId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    return SliverToBoxAdapter(
                      child: Center(
                        child: Text(
                          'Error: ${snapshot.error}',
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                    );
                  }

                  final tasks = snapshot.data ?? [];
                  final activeTasks = tasks.where((t) => !t.isCompleted).toList();
                  final completedTasks = tasks.where((t) => t.isCompleted).toList();

                  return SliverList(
                    delegate: SliverChildListDelegate([
                      // Active Tasks Section
                      if (activeTasks.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _buildTasksSection(
                            'ACTIVE LOGS',
                            activeTasks,
                            '${_currentOdo ?? 0} km Total',
                          ),
                        ),

                      // Completed Tasks Section
                      if (completedTasks.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _buildTasksSection(
                            'COMPLETED',
                            completedTasks,
                            null,
                          ),
                        ),
                      ],

                      if (tasks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.build_outlined,
                                  size: 48,
                                  color: AppColors.textTertiary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Chưa có lịch bảo dưỡng',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Nhấn + để thêm mốc bảo dưỡng',
                                  style: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 100),
                    ]),
                  );
                },
              )
            else
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Text(
                      'Vui lòng chọn xe để xem lịch bảo dưỡng',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksSection(
    String title,
    List<MaintenanceTaskModel> tasks,
    String? subtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          ...tasks.asMap().entries.map((entry) {
            final index = entry.key;
            final task = entry.value;
            return _buildTaskItem(task, index);
          }),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildTaskItem(MaintenanceTaskModel task, int index) {
    final currentOdo = _currentOdo ?? 0;
    final remainingKm = (task.targetOdo - currentOdo).clamp(0, 999999);
    final progress = (currentOdo / task.targetOdo).clamp(0.0, 1.0);
    final iconData = _getServiceTypeIcon(task.serviceType);
    final color = _getServiceTypeColor(task.serviceType);
    final isDueSoon = task.isDueSoon(currentOdo);
    final isOverdue = task.isOverdue(currentOdo);

    return Dismissible(
      key: Key(task.taskId ?? 'task_$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.card,
            title: const Text(
              'Xác nhận xóa',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            content: Text(
              'Bạn có chắc muốn xóa "${task.title}"?',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Hủy'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Xóa',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        if (task.taskId != null) {
          await MaintenanceRepository.deleteMaintenanceTask(task.taskId!);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Đã xóa mốc bảo dưỡng'),
                backgroundColor: AppColors.success,
              ),
            );
          }
        }
      },
      child: GestureDetector(
        onTap: () => _showAddEditDialog(context, task: task),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isOverdue
                ? AppColors.error.withAlpha(26)
                : isDueSoon
                    ? AppColors.warning.withAlpha(26)
                    : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isOverdue
                  ? AppColors.error
                  : isDueSoon
                      ? AppColors.warning
                      : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withAlpha(40),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      iconData,
                      color: isOverdue
                          ? AppColors.error
                          : isDueSoon
                              ? AppColors.warning
                              : color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: TextStyle(
                            color: isOverdue ? AppColors.error : AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isOverdue
                              ? '⚠️ Quá hạn ${(currentOdo - task.targetOdo)} km'
                              : isDueSoon
                                  ? '⏰ Sắp đến hạn (còn ≤50km)'
                                  : '$remainingKm km còn lại',
                          style: TextStyle(
                            color: isOverdue
                                ? AppColors.error
                                : isDueSoon
                                    ? AppColors.warning
                                    : AppColors.textTertiary,
                            fontSize: 12,
                            fontWeight: isOverdue || isDueSoon ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (task.scheduledDate != null)
                    Container(
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
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColors.card,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isOverdue
                        ? AppColors.error
                        : isDueSoon
                            ? AppColors.warning
                            : AppColors.success,
                  ),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: (200 + index * 100).ms).slideX(begin: 0.1);
  }

  IconData _getServiceTypeIcon(ServiceType type) {
    return switch (type) {
      ServiceType.oilChange => Icons.oil_barrel_outlined,
      ServiceType.tireRotation => Icons.circle_outlined,
      ServiceType.brakeService => Icons.stop_circle_outlined,
      ServiceType.airFilter => Icons.air,
      ServiceType.batteryCheck => Icons.battery_full_outlined,
      ServiceType.coolantFlush => Icons.water_drop_outlined,
      ServiceType.transmissionService => Icons.settings_outlined,
      ServiceType.inspection => Icons.fact_check_outlined,
      ServiceType.other => Icons.build_outlined,
    };
  }

  Color _getServiceTypeColor(ServiceType type) {
    return switch (type) {
      ServiceType.oilChange => const Color(0xFFE8A87C),
      ServiceType.tireRotation => const Color(0xFFE8A87C),
      ServiceType.brakeService => const Color(0xFFFF6B6B),
      ServiceType.airFilter => const Color(0xFF9B9B9B),
      ServiceType.batteryCheck => const Color(0xFF4ECDC4),
      ServiceType.coolantFlush => const Color(0xFF45B7D1),
      ServiceType.transmissionService => const Color(0xFF9B9B9B),
      ServiceType.inspection => const Color(0xFF96CEB4),
      ServiceType.other => const Color(0xFF9B9B9B),
    };
  }

  void _showAddEditDialog(BuildContext context, {MaintenanceTaskModel? task}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MaintenanceTaskDialog(
        task: task,
        onSave: (newTask) async {
          final vehicleId = ref.read(selectedVehicleIdProvider);
          if (vehicleId.isEmpty) return;

          try {
            if (task?.taskId != null) {
              // Update existing
              await MaintenanceRepository.updateMaintenanceTask(
                task!.taskId!,
                newTask.toFirestore(),
              );
            } else {
              // Create new
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
        },
      ),
    );
  }

}

// Maintenance Task Dialog
class MaintenanceTaskDialog extends StatefulWidget {
  final MaintenanceTaskModel? task;
  final Function(MaintenanceTaskModel) onSave;

  const MaintenanceTaskDialog({
    super.key,
    this.task,
    required this.onSave,
  });

  @override
  State<MaintenanceTaskDialog> createState() => _MaintenanceTaskDialogState();
}

class _MaintenanceTaskDialogState extends State<MaintenanceTaskDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _odoController;
  ServiceType _selectedType = ServiceType.other;
  DateTime? _scheduledDate;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _descController = TextEditingController(text: task?.description ?? '');
    _odoController = TextEditingController(
      text: task?.targetOdo.toString() ?? '',
    );
    _selectedType = task?.serviceType ?? ServiceType.other;
    _scheduledDate = task?.scheduledDate;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.task != null ? 'Sửa mốc bảo dưỡng' : 'Thêm mốc bảo dưỡng',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildTextField('Tên dịch vụ', _titleController, Icons.build_outlined),
            const SizedBox(height: 16),
            _buildTextField('Mô tả', _descController, Icons.description_outlined, maxLines: 2),
            const SizedBox(height: 16),
            _buildTextField('Mốc ODO (km)', _odoController, Icons.speed_outlined, keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            _buildServiceTypeSelector(),
            const SizedBox(height: 16),
            _buildDatePicker(),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _save,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.task != null ? 'CẬP NHẬT' : 'THÊM MỚI',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: AppColors.textTertiary),
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildServiceTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Loại dịch vụ',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ServiceType.values.map((type) {
            final isSelected = _selectedType == type;
            return GestureDetector(
              onTap: () => setState(() => _selectedType = type),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _getServiceTypeLabel(type),
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _getServiceTypeLabel(ServiceType type) {
    return switch (type) {
      ServiceType.oilChange => 'Thay dầu',
      ServiceType.tireRotation => 'Lốp xe',
      ServiceType.brakeService => 'Phanh',
      ServiceType.airFilter => 'Lọc gió',
      ServiceType.batteryCheck => 'Pin',
      ServiceType.coolantFlush => 'Nước làm mát',
      ServiceType.transmissionService => 'Hộp số',
      ServiceType.inspection => 'Kiểm tra',
      ServiceType.other => 'Khác',
    };
  }

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _scheduledDate ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.dark(
                primary: AppColors.primary,
                surface: AppColors.card,
              ),
            ),
            child: child!,
          ),
        );
        if (date != null) {
          setState(() => _scheduledDate = date);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: AppColors.textTertiary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _scheduledDate != null
                    ? 'Ngày hẹn: ${_scheduledDate!.day}/${_scheduledDate!.month}/${_scheduledDate!.year}'
                    : 'Chọn ngày hẹn bảo dưỡng (tùy chọn)',
                style: TextStyle(
                  color: _scheduledDate != null ? AppColors.textPrimary : AppColors.textTertiary,
                  fontSize: 14,
                ),
              ),
            ),
            if (_scheduledDate != null)
              GestureDetector(
                onTap: () => setState(() => _scheduledDate = null),
                child: Icon(Icons.close, color: AppColors.textTertiary, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final title = _titleController.text.trim();
    final odo = int.tryParse(_odoController.text.trim()) ?? 0;

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
      description: _descController.text.trim(),
      targetOdo: odo,
      isCompleted: widget.task?.isCompleted ?? false,
      completedDate: widget.task?.completedDate,
      createdAt: widget.task?.createdAt ?? DateTime.now(),
      scheduledDate: _scheduledDate,
      serviceType: _selectedType,
    );

    widget.onSave(task);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _odoController.dispose();
    super.dispose();
  }
}
