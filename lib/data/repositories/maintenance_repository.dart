import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/maintenance_task_model.dart';

/// Repository cho MaintenanceTasks collection trên Firestore
class MaintenanceRepository {
  final FirebaseFirestore _firestore;

  MaintenanceRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference get _tasksRef => _firestore.collection('MaintenanceTasks');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Lấy tất cả tasks của xe (chưa hoàn thành trước)
  Future<List<MaintenanceTaskModel>> getTasks(String vehicleId) async {
    final snapshot = await _tasksRef
        .where('vehicleId', isEqualTo: vehicleId)
        .get();

    final tasks = snapshot.docs
        .map((doc) => MaintenanceTaskModel.fromFirestore(doc))
        .toList();
    tasks.sort((a, b) => a.targetOdo.compareTo(b.targetOdo));
    return tasks;
  }

  /// Lấy tasks chưa hoàn thành
  Future<List<MaintenanceTaskModel>> getPendingTasks(String vehicleId) async {
    final snapshot = await _tasksRef
        .where('vehicleId', isEqualTo: vehicleId)
        .where('isCompleted', isEqualTo: false)
        .get();

    final tasks = snapshot.docs
        .map((doc) => MaintenanceTaskModel.fromFirestore(doc))
        .toList();
    tasks.sort((a, b) => a.targetOdo.compareTo(b.targetOdo));
    return tasks;
  }

  /// Tạo task mới
  Future<void> addTask(MaintenanceTaskModel task) async {
    final data = task.toFirestore();
    if (_uid != null) data['ownerUid'] = _uid;
    data['isDeleted'] = false;
    await _tasksRef.add(data);
  }

  /// Đánh dấu hoàn thành
  Future<void> completeTask(String taskId) async {
    await _tasksRef.doc(taskId).update({
      'isCompleted': true,
      'completedDate': Timestamp.fromDate(DateTime.now()),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Xóa task
  Future<void> deleteTask(String taskId) async {
    await _tasksRef.doc(taskId).delete();
  }

  /// Update task
  Future<void> updateTask(MaintenanceTaskModel task) async {
    if (task.taskId == null) return;
    await _tasksRef.doc(task.taskId).update(task.toFirestore());
  }

  /// Lấy tasks sắp đến hạn (cần thông báo)
  Future<List<MaintenanceTaskModel>> getDueSoonTasks(
    String vehicleId,
    int currentOdo,
  ) async {
    final pending = await getPendingTasks(vehicleId);
    return pending.where((t) => t.isDueSoon(currentOdo)).toList();
  }
}

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>((ref) {
  return MaintenanceRepository();
});
