import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/maintenance_task_model.dart';
import '../repositories/maintenance_repository.dart';
import '../services/notification_service.dart';

/// ========================================================================
/// Maintenance Reminder Service
/// Tự động kiểm tra và gửi nhắc nhở bảo dưỡng, chống spam bằng cờ.
/// ========================================================================
class MaintenanceReminderService {
  static final MaintenanceReminderService _instance =
      MaintenanceReminderService._();
  factory MaintenanceReminderService() => _instance;
  MaintenanceReminderService._();

  final _repo = MaintenanceRepository();

  /// Kiểm tra và gửi nhắc nhở cho tất cả tasks sắp đến hạn / quá hạn.
  /// Gọi tại: app launch, sau stop trip, sau lưu charge.
  ///
  /// Dedupe: mỗi task+threshold chỉ notify 1 lần.
  /// Key format: `maint_notified_{taskId}_{threshold}`
  /// threshold = "due_soon" hoặc "overdue"
  Future<void> checkAndNotify({
    required String vehicleId,
    required int currentOdo,
  }) async {
    if (vehicleId.isEmpty) return;

    try {
      final tasks = await _repo.getPendingTasks(vehicleId);
      final prefs = await SharedPreferences.getInstance();

      for (final task in tasks) {
        if (task.taskId == null) continue;

        final isOverdue = task.isOverdue(currentOdo);
        final isDueSoon = task.isDueSoon(currentOdo);

        if (isOverdue) {
          await _notifyIfNew(
            prefs: prefs,
            task: task,
            threshold: 'overdue',
            currentOdo: currentOdo,
          );
        } else if (isDueSoon) {
          await _notifyIfNew(
            prefs: prefs,
            task: task,
            threshold: 'due_soon',
            currentOdo: currentOdo,
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ MaintenanceReminder error: $e');
    }
  }

  Future<void> _notifyIfNew({
    required SharedPreferences prefs,
    required MaintenanceTaskModel task,
    required String threshold,
    required int currentOdo,
  }) async {
    final key = 'maint_notified_${task.taskId}_$threshold';
    final already = prefs.getBool(key) ?? false;
    if (already) return;

    final remaining = task.remainingKm(currentOdo);
    if (threshold == 'overdue') {
      await NotificationService().notifyMaintenanceDue(
        task.taskId!,
        '⚠️ Quá hạn: ${task.title}',
        remaining,
      );
    } else {
      await NotificationService().notifyMaintenanceDue(
        task.taskId!,
        task.title,
        remaining,
      );
    }

    await prefs.setBool(key, true);
    debugPrint('🔔 Maintenance notify: ${task.title} ($threshold)');
  }

  /// Reset cờ notify khi task hoàn thành hoặc xóa.
  /// Gọi sau completeTask / deleteTask.
  static Future<void> resetNotifyFlag(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('maint_notified_${taskId}_due_soon');
    await prefs.remove('maint_notified_${taskId}_overdue');
  }
}
