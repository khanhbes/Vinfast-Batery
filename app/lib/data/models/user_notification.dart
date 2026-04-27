import 'package:cloud_firestore/cloud_firestore.dart';

/// Loại thông báo
enum NotificationType {
  modelUpdated,
  modelDownloadFailed,
  syncCompleted,
  syncFailed,
  maintenanceDue,
  batteryAlert,
  chargeReminder,
  system,
}

/// Trạng thái thông báo
enum NotificationStatus {
  unread,
  read,
  archived,
}

/// Model đại diện cho một thông báo trong Notification Center
class UserNotification {
  final String id;
  final String userId;
  final NotificationType type;
  final String title;
  final String message;
  final NotificationStatus status;
  final DateTime createdAt;
  final DateTime? readAt;
  final Map<String, dynamic>? payload;
  final String? actionTarget; // deep link target (e.g., '/ai/charging_time')
  final String? imageUrl;

  UserNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    this.status = NotificationStatus.unread,
    required this.createdAt,
    this.readAt,
    this.payload,
    this.actionTarget,
    this.imageUrl,
  });

  /// Factory từ Firestore document
  factory UserNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    return UserNotification(
      id: doc.id,
      userId: data['userId'] ?? '',
      type: _parseType(data['type']),
      title: data['title'] ?? '',
      message: data['message'] ?? '',
      status: _parseStatus(data['status']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      readAt: (data['readAt'] as Timestamp?)?.toDate(),
      payload: data['payload'] as Map<String, dynamic>?,
      actionTarget: data['actionTarget'],
      imageUrl: data['imageUrl'],
    );
  }

  /// Convert sang Firestore data
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'type': type.name,
      'title': title,
      'message': message,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
      'payload': payload,
      'actionTarget': actionTarget,
      'imageUrl': imageUrl,
    };
  }

  /// Tạo bản sao với trạng thái mới
  UserNotification copyWith({
    NotificationStatus? status,
    DateTime? readAt,
  }) {
    return UserNotification(
      id: id,
      userId: userId,
      type: type,
      title: title,
      message: message,
      status: status ?? this.status,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
      payload: payload,
      actionTarget: actionTarget,
      imageUrl: imageUrl,
    );
  }

  /// Parse type từ string
  static NotificationType _parseType(String? value) {
    switch (value) {
      case 'modelUpdated': return NotificationType.modelUpdated;
      case 'modelDownloadFailed': return NotificationType.modelDownloadFailed;
      case 'syncCompleted': return NotificationType.syncCompleted;
      case 'syncFailed': return NotificationType.syncFailed;
      case 'maintenanceDue': return NotificationType.maintenanceDue;
      case 'batteryAlert': return NotificationType.batteryAlert;
      case 'chargeReminder': return NotificationType.chargeReminder;
      default: return NotificationType.system;
    }
  }

  /// Parse status từ string
  static NotificationStatus _parseStatus(String? value) {
    switch (value) {
      case 'read': return NotificationStatus.read;
      case 'archived': return NotificationStatus.archived;
      default: return NotificationStatus.unread;
    }
  }

  /// Icon cho loại thông báo
  String get iconName {
    switch (type) {
      case NotificationType.modelUpdated:
        return 'Brain';
      case NotificationType.modelDownloadFailed:
        return 'AlertTriangle';
      case NotificationType.syncCompleted:
        return 'CheckCircle';
      case NotificationType.syncFailed:
        return 'XCircle';
      case NotificationType.maintenanceDue:
        return 'Wrench';
      case NotificationType.batteryAlert:
        return 'BatteryWarning';
      case NotificationType.chargeReminder:
        return 'PlugZap';
      case NotificationType.system:
        return 'Info';
    }
  }

  /// Màu accent cho loại thông báo
  String get accentColor {
    switch (type) {
      case NotificationType.modelUpdated:
        return 'emerald';
      case NotificationType.modelDownloadFailed:
      case NotificationType.syncFailed:
      case NotificationType.batteryAlert:
        return 'rose';
      case NotificationType.syncCompleted:
        return 'blue';
      case NotificationType.maintenanceDue:
      case NotificationType.chargeReminder:
        return 'amber';
      case NotificationType.system:
        return 'slate';
    }
  }

  bool get isUnread => status == NotificationStatus.unread;
}
