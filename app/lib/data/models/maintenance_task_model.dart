import 'package:cloud_firestore/cloud_firestore.dart';

/// Các loại dịch vụ bảo dưỡng — bám theo sổ tay VinFast.
///
/// Nhóm:
/// - Hệ điều khiển: brakeLever, throttleGrip, lightsHornDash
/// - Khung & khoá: sideStand, seatLock
/// - Pin: battery, batteryCheck (legacy)
/// - Phanh: brakeFluid, brakeFront, brakeRear, brakeHose, brakeCable, brakeService (legacy)
/// - Bánh xe: wheelFront, wheelRear, tireFront, tireRear, tireRotation (legacy)
/// - Hệ treo: steeringBearing, suspensionFront, suspensionRear
/// - Động cơ: motor, motorSeal
/// - Khác: oilChange, airFilter, coolantFlush, transmissionService, inspection, other
enum ServiceType {
  // ── Hệ điều khiển ──
  brakeLever,
  throttleGrip,
  lightsHornDash,

  // ── Khung & khoá ──
  sideStand,
  seatLock,

  // ── Pin ──
  battery,

  // ── Phanh ──
  brakeFluid,
  brakeFront,
  brakeRear,
  brakeHose,
  brakeCable,

  // ── Bánh xe ──
  wheelFront,
  wheelRear,
  tireFront,
  tireRear,

  // ── Hệ treo ──
  steeringBearing,
  suspensionFront,
  suspensionRear,

  // ── Động cơ ──
  motor,
  motorSeal,

  // ── Legacy / khác ──
  oilChange,
  tireRotation,
  brakeService,
  airFilter,
  batteryCheck,
  coolantFlush,
  transmissionService,
  inspection,
  other,
}

/// Mức độ khẩn cấp của 1 maintenance task (tính từ ODO hiện tại).
enum MaintenanceUrgency {
  completed,
  overdue,
  dueSoon,
  upcoming,
}

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
  final DateTime? scheduledDate; // Ngày lên lịch bảo dưỡng
  final ServiceType serviceType; // Loại dịch vụ

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
    this.scheduledDate,
    this.serviceType = ServiceType.other,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Kiểm tra sắp đến hạn (còn ≤50km)
  bool isDueSoon(int currentOdo) {
    return !isCompleted && currentOdo >= targetOdo - 50;
  }

  /// Kiểm tra đã quá hạn
  bool isOverdue(int currentOdo) {
    return !isCompleted && currentOdo >= targetOdo;
  }

  /// Khoảng cách còn lại (km). Có thể âm (đã quá hạn).
  int remainingKm(int currentOdo) {
    return targetOdo - currentOdo;
  }

  /// Phân loại độ khẩn cấp dựa trên ODO hiện tại.
  MaintenanceUrgency urgency(int currentOdo) {
    if (isCompleted) return MaintenanceUrgency.completed;
    if (currentOdo >= targetOdo) return MaintenanceUrgency.overdue;
    if (currentOdo >= targetOdo - 50) return MaintenanceUrgency.dueSoon;
    return MaintenanceUrgency.upcoming;
  }

  /// Tỉ lệ tiến độ tới đích (0..1, clamp). Phục vụ progress bar.
  double progress(int currentOdo) {
    if (targetOdo <= 0) return 0;
    return (currentOdo / targetOdo).clamp(0.0, 1.0);
  }

  factory MaintenanceTaskModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MaintenanceTaskModel(
      taskId: doc.id,
      vehicleId: data['vehicleId'] as String? ?? '',
      ownerUid: data['ownerUid'] as String?,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      // targetOdo: Firestore có thể lưu int, double, num hoặc string.
      targetOdo: _safeParseInt(data['targetOdo']),
      isCompleted: data['isCompleted'] as bool? ?? false,
      completedDate: _safeTimestamp(data['completedDate']),
      createdAt: _safeTimestamp(data['createdAt']) ?? DateTime.now(),
      scheduledDate: _safeTimestamp(data['scheduledDate']),
      serviceType: _parseServiceType(data['serviceType']),
    );
  }

  /// Parse Timestamp | String | DateTime | null an toàn
  static DateTime? _safeTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  /// Parse int | double | num | String an toàn về int (trả 0 nếu không parse được)
  static int _safeParseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static ServiceType _parseServiceType(dynamic value) {
    if (value == null) return ServiceType.other;
    final str = value.toString().toLowerCase();
    return ServiceType.values.firstWhere(
      (e) => e.name.toLowerCase() == str,
      orElse: () => ServiceType.other,
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
      'scheduledDate':
          scheduledDate != null ? Timestamp.fromDate(scheduledDate!) : null,
      'serviceType': serviceType.name,
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
    DateTime? scheduledDate,
    ServiceType? serviceType,
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
      scheduledDate: scheduledDate ?? this.scheduledDate,
      serviceType: serviceType ?? this.serviceType,
    );
  }
}
