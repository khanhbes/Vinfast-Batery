import 'package:cloud_firestore/cloud_firestore.dart';

/// Model mốc bảo dưỡng xe
class MaintenanceTaskModel {
  final String? taskId;
  final String vehicleId;
  final String? ownerUid;
  final String title;
  final String description;
  final int targetOdo; // Mốc ODO cần bảo dưỡng
  final bool isCompleted;
  final DateTime? completedDate;
  final DateTime createdAt;

  MaintenanceTaskModel({
    this.taskId,
    required this.vehicleId,
    this.ownerUid,
    required this.title,
    this.description = '',
    required this.targetOdo,
    this.isCompleted = false,
    this.completedDate,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Kiểm tra sắp đến hạn (còn ≤50km)
  bool isDueSoon(int currentOdo) {
    return !isCompleted && currentOdo >= targetOdo - 50;
  }

  /// Kiểm tra đã quá hạn
  bool isOverdue(int currentOdo) {
    return !isCompleted && currentOdo >= targetOdo;
  }

  /// Khoảng cách còn lại (km)
  int remainingKm(int currentOdo) {
    return targetOdo - currentOdo;
  }

  factory MaintenanceTaskModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MaintenanceTaskModel(
      taskId: doc.id,
      vehicleId: data['vehicleId'] ?? '',
      ownerUid: data['ownerUid'],
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      targetOdo: data['targetOdo'] ?? 0,
      isCompleted: data['isCompleted'] ?? false,
      completedDate: data['completedDate'] != null
          ? (data['completedDate'] as Timestamp).toDate()
          : null,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'vehicleId': vehicleId,
      if (ownerUid != null) 'ownerUid': ownerUid,
      'title': title,
      'description': description,
      'targetOdo': targetOdo,
      'isCompleted': isCompleted,
      'completedDate':
          completedDate != null ? Timestamp.fromDate(completedDate!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  MaintenanceTaskModel copyWith({
    String? taskId,
    String? vehicleId,
    String? title,
    String? description,
    int? targetOdo,
    bool? isCompleted,
    DateTime? completedDate,
    DateTime? createdAt,
  }) {
    return MaintenanceTaskModel(
      taskId: taskId ?? this.taskId,
      vehicleId: vehicleId ?? this.vehicleId,
      title: title ?? this.title,
      description: description ?? this.description,
      targetOdo: targetOdo ?? this.targetOdo,
      isCompleted: isCompleted ?? this.isCompleted,
      completedDate: completedDate ?? this.completedDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
