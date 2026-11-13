import 'package:cloud_firestore/cloud_firestore.dart';

/// Các loại dịch vụ bảo dưỡng — bám theo sổ tay VinFast.
///
/// Nhóm:
/// - Hệ điều khiển: brakeLever, throttleGrip, lightsHornDash
/// - Khung & khóa: sideStand, seatLock
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

  // ── Khung & khóa ──
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
enum MaintenanceUrgency { completed, overdue, dueSoon, upcoming }

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

  /// QA 154, the service record: what the odometer showed when the work
  /// was done, what it cost (đồng) and a note (garage, parts). All
  /// optional; older tasks have none.
  final int? completedOdo;
  final int? costVnd;
  final String? completionNote;

  /// An appointment this close counts as due soon.
  static const dueSoonDays = 7;

  /// A milestone this close counts as due soon. QA 155: 200 km, about
  /// a week of riding, like [dueSoonDays]; 50 km was a day's notice
  /// for a visit that comes every 5 000 km.
  static const dueSoonKm = 200;

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
    this.completedOdo,
    this.costVnd,
    this.completionNote,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Whole days from [now] to the appointment (negative once it has
  /// passed), or null without one.
  int? daysUntilScheduled(DateTime now) {
    final date = scheduledDate?.toLocal();
    if (date == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(date.year, date.month, date.day).difference(today).inDays;
  }

  /// Sắp đến hạn: còn ≤ [dueSoonKm], hoặc (khi truyền [now]) ngày hẹn trong
  /// vòng 7 ngày. Đã quá hạn cũng tính là sắp đến hạn, như trước.
  bool isDueSoon(int currentOdo, {DateTime? now}) {
    if (isCompleted) return false;
    if (currentOdo >= targetOdo - dueSoonKm) return true;
    final days = now == null ? null : daysUntilScheduled(now);
    return days != null && days <= dueSoonDays;
  }

  /// Đã quá hạn: qua mốc ODO, hoặc (khi truyền [now]) qua ngày hẹn.
  /// QA 154: the appointment date was shown but never counted.
  bool isOverdue(int currentOdo, {DateTime? now}) {
    if (isCompleted) return false;
    if (currentOdo >= targetOdo) return true;
    final days = now == null ? null : daysUntilScheduled(now);
    return days != null && days < 0;
  }

  /// Khoảng cách còn lại (km). Có thể âm (đã quá hạn).
  int remainingKm(int currentOdo) {
    return targetOdo - currentOdo;
  }

  /// Phân loại độ khẩn cấp dựa trên ODO hiện tại.
  MaintenanceUrgency urgency(int currentOdo, {DateTime? now}) {
    if (isCompleted) return MaintenanceUrgency.completed;
    if (isOverdue(currentOdo, now: now)) return MaintenanceUrgency.overdue;
    if (isDueSoon(currentOdo, now: now)) return MaintenanceUrgency.dueSoon;
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
      completedOdo: _optionalInt(data['completedOdo']),
      costVnd: _optionalInt(data['costVnd']),
      completionNote: switch (data['completionNote']) {
        final String note when note.trim().isNotEmpty => note.trim(),
        _ => null,
      },
    );
  }

  static int? _optionalInt(dynamic value) {
    if (value is num && value.isFinite && value >= 0) return value.round();
    return null;
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
      'completedDate': completedDate != null
          ? Timestamp.fromDate(completedDate!)
          : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
      'scheduledDate': scheduledDate != null
          ? Timestamp.fromDate(scheduledDate!)
          : null,
      'serviceType': serviceType.name,
      'completedOdo': completedOdo,
      'costVnd': costVnd,
      'completionNote': completionNote,
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
    int? completedOdo,
    int? costVnd,
    String? completionNote,
  }) {
    return MaintenanceTaskModel(
      taskId: taskId ?? this.taskId,
      vehicleId: vehicleId ?? this.vehicleId,
      // QA 154: the copy used to lose the owner.
      ownerUid: ownerUid,
      title: title ?? this.title,
      description: description ?? this.description,
      targetOdo: targetOdo ?? this.targetOdo,
      isCompleted: isCompleted ?? this.isCompleted,
      completedDate: completedDate ?? this.completedDate,
      createdAt: createdAt ?? this.createdAt,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      serviceType: serviceType ?? this.serviceType,
      completedOdo: completedOdo ?? this.completedOdo,
      costVnd: costVnd ?? this.costVnd,
      completionNote: completionNote ?? this.completionNote,
    );
  }
}
