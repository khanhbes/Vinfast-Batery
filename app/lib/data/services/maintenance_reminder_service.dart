import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/maintenance_task_model.dart';
import '../models/user_notification.dart';
import '../repositories/maintenance_repository.dart';
import '../repositories/notification_repository.dart';
import '../services/notification_service.dart';

/// What one reminder round has to say (QA 150): the tasks that became due
/// soon or overdue since the last round, as one line each for the phone
/// notification and for Trung tâm thông báo.
class MaintenanceReminderSummary {
  const MaintenanceReminderSummary({required this.title, required this.body});

  final String title;
  final String body;

  /// Null when [titles] is empty. One task is named; several are counted, so
  /// a new account with a high ODO does not get one notification per task.
  static MaintenanceReminderSummary? of({
    required List<String> titles,
    required bool overdue,
    int? remainingKm,
  }) {
    if (titles.isEmpty) return null;
    final state = overdue ? 'đã quá hạn' : 'sắp đến hạn';
    if (titles.length == 1) {
      final km = remainingKm;
      final distance = km == null
          ? ''
          : overdue
          ? ' (quá ${km.abs()} km)'
          : ' (còn $km km)';
      return MaintenanceReminderSummary(
        title: 'Bảo dưỡng $state',
        body: '${titles.single}$distance.',
      );
    }
    final shown = titles.take(2).join(', ');
    final rest = titles.length - 2;
    return MaintenanceReminderSummary(
      title: '${titles.length} mốc bảo dưỡng $state',
      body: rest > 0 ? '$shown và $rest mốc khác.' : '$shown.',
    );
  }
}

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
  ///
  /// QA 150: one notification per round and state (not one per task), and
  /// the same line is written to Trung tâm thông báo, which used to stay
  /// empty with 19 overdue tasks.
  Future<void> checkAndNotify({
    required String vehicleId,
    required int currentOdo,
  }) async {
    if (vehicleId.isEmpty) return;

    try {
      final tasks = await _repo.getPendingTasks(vehicleId);
      final prefs = await SharedPreferences.getInstance();
      final overdue = <MaintenanceTaskModel>[];
      final dueSoon = <MaintenanceTaskModel>[];

      // QA 154: an appointment date reminds too (7 days ahead, and once
      // it has passed), not only the kilometre mark.
      final now = DateTime.now();
      for (final task in tasks) {
        if (task.taskId == null) continue;
        if (task.isOverdue(currentOdo, now: now)) {
          if (!_already(prefs, task, 'overdue')) overdue.add(task);
        } else if (task.isDueSoon(currentOdo, now: now)) {
          if (!_already(prefs, task, 'due_soon')) dueSoon.add(task);
        }
      }

      await _announce(prefs, vehicleId, overdue, 'overdue', currentOdo);
      await _announce(prefs, vehicleId, dueSoon, 'due_soon', currentOdo);
    } catch (e) {
      debugPrint('⚠️ MaintenanceReminder error (${e.runtimeType}).');
    }
  }

  bool _already(
    SharedPreferences prefs,
    MaintenanceTaskModel task,
    String threshold,
  ) => prefs.getBool('maint_notified_${task.taskId}_$threshold') ?? false;

  Future<void> _announce(
    SharedPreferences prefs,
    String vehicleId,
    List<MaintenanceTaskModel> tasks,
    String threshold,
    int currentOdo,
  ) async {
    final summary = MaintenanceReminderSummary.of(
      titles: [for (final task in tasks) task.title],
      overdue: threshold == 'overdue',
      // The distance only when the kilometre mark is what makes it due.
      remainingKm: tasks.length == 1 && tasks.single.isDueSoon(currentOdo)
          ? tasks.single.remainingKm(currentOdo)
          : null,
    );
    if (summary == null) return;
    final first = tasks.first.taskId!;

    await NotificationService().notifyMaintenanceSummary(
      first,
      summary.title,
      summary.body,
    );
    await NotificationRepository().createNotification(
      type: NotificationType.maintenanceDue,
      title: summary.title,
      message: summary.body,
      actionTarget: '/maintenance',
      dedupeKey: 'maint_${vehicleId}_${threshold}_${first}_${tasks.length}',
    );

    for (final task in tasks) {
      await prefs.setBool('maint_notified_${task.taskId}_$threshold', true);
    }
  }

  /// Reset cờ notify khi task hoàn thành hoặc xóa.
  /// Gọi sau completeTask / deleteTask.
  static Future<void> resetNotifyFlag(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('maint_notified_${taskId}_due_soon');
    await prefs.remove('maint_notified_${taskId}_overdue');
  }
}
