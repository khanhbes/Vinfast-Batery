import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/maintenance_task_model.dart';

/// Repository cho MaintenanceTasks collection trên Firestore
class MaintenanceRepository {
  final FirebaseFirestore _instanceFirestore;

  MaintenanceRepository({FirebaseFirestore? firestore})
    : _instanceFirestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference get _tasksRef =>
      _instanceFirestore.collection('MaintenanceTasks');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Lấy tất cả tasks của xe (chưa hoàn thành trước)
  Future<List<MaintenanceTaskModel>> getTasks(String vehicleId) async {
    if (_uid == null) return [];
    final snapshot = await _tasksRef
        .where('ownerUid', isEqualTo: _uid)
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
    if (_uid == null) return [];
    final snapshot = await _tasksRef
        .where('ownerUid', isEqualTo: _uid)
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

  // ═══════════════════════════════════════════════════════════════════════
  // STATIC METHODS for convenience (used by UI)
  // ═══════════════════════════════════════════════════════════════════════

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream of maintenance tasks for real-time updates.
  ///
  /// Query tối giản theo ownerUid rồi filter/sort phía client.
  /// Service tab không phụ thuộc composite index nên sẽ không kẹt skeleton
  /// khi server chưa deploy index mới.
  static Stream<List<MaintenanceTaskModel>> watchMaintenanceTasks(
    String vehicleId,
  ) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(const <MaintenanceTaskModel>[]);

    // NOTE: Both where-clauses must match the Firestore security rule:
    //   allow read: if canReadOwned() && notDeleted();
    // The rule checks ownerUid == request.auth.uid AND isDeleted != true.
    // Firestore validates collection queries by checking that every document
    // the query COULD return satisfies the rule.  If we only filter by
    // ownerUid the evaluator cannot confirm notDeleted(), so it rejects the
    // query with PERMISSION_DENIED.  Adding isDeleted == false makes the
    // constraint explicit and satisfies the rule evaluator.
    return _firestore
        .collection('MaintenanceTasks')
        .where('ownerUid', isEqualTo: uid)
        .where('isDeleted', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
          final tasks = snapshot.docs
              // Client-side filter: narrow to the selected vehicle only
              .where((doc) => doc.data()['vehicleId'] == vehicleId)
              .map((doc) => MaintenanceTaskModel.fromFirestore(doc))
              .toList();
          tasks.sort((a, b) => a.targetOdo.compareTo(b.targetOdo));
          return tasks;
        })
        .handleError((Object error, StackTrace st) {
          debugPrint('[MaintenanceRepo] Watch error: $error');
          throw error;
        });
  }

  /// Create a new maintenance task
  static Future<void> createMaintenanceTask({
    required String vehicleId,
    required String title,
    required String description,
    required int targetOdo,
    ServiceType serviceType = ServiceType.other,
    DateTime? scheduledDate,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final data = {
      'vehicleId': vehicleId,
      'title': title,
      'description': description,
      'targetOdo': targetOdo,
      'isCompleted': false,
      'serviceType': serviceType.name,
      'scheduledDate': scheduledDate != null
          ? Timestamp.fromDate(scheduledDate)
          : null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
    };
    if (uid != null) data['ownerUid'] = uid;
    await _firestore.collection('MaintenanceTasks').add(data);
  }

  /// Update a maintenance task
  static Future<void> updateMaintenanceTask(
    String taskId,
    Map<String, dynamic> data,
  ) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _firestore.collection('MaintenanceTasks').doc(taskId).update(data);
  }

  /// Delete a maintenance task
  static Future<void> deleteMaintenanceTask(String taskId) async {
    await _firestore.collection('MaintenanceTasks').doc(taskId).delete();
  }
}

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>((ref) {
  return MaintenanceRepository();
});
