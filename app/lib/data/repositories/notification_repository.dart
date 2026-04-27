import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_notification.dart';

/// Repository quản lý thông báo người dùng từ Firestore
class NotificationRepository {
  static final NotificationRepository _instance = NotificationRepository._internal();
  factory NotificationRepository() => _instance;
  NotificationRepository._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference get _notificationsRef => _firestore.collection('UserNotifications');

  /// Stream thông báo của user hiện tại, sắp xếp mới nhất trước
  Stream<List<UserNotification>> watchNotifications({int limit = 100}) {
    final uid = _uid;
    if (uid == null) return Stream.value([]);

    return _notificationsRef
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => UserNotification.fromFirestore(doc))
              .toList();
        })
        .handleError((error) {
          debugPrint('[NotificationRepo] Watch error: $error');
          return <UserNotification>[];
        });
  }

  /// Lấy danh sách thông báo một lần
  Future<List<UserNotification>> getNotifications({int limit = 50}) async {
    final uid = _uid;
    if (uid == null) return [];

    try {
      final snapshot = await _notificationsRef
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => UserNotification.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('[NotificationRepo] Get error: $e');
      return [];
    }
  }

  /// Đếm số thông báo chưa đọc — realtime snapshots (PLAN1)
  Stream<int> watchUnreadCount() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);

    return _notificationsRef
        .where('userId', isEqualTo: uid)
        .where('status', isEqualTo: 'unread')
        .snapshots()
        .map((snapshot) => snapshot.docs.length)
        .handleError((error) {
          debugPrint('[NotificationRepo] Unread count error: $error');
          return 0;
        });
  }

  /// Đánh dấu đã đọc
  Future<bool> markAsRead(String notificationId) async {
    try {
      await _notificationsRef.doc(notificationId).update({
        'status': 'read',
        'readAt': Timestamp.now(),
      });
      return true;
    } catch (e) {
      debugPrint('[NotificationRepo] Mark read error: $e');
      return false;
    }
  }

  /// Đánh dấu tất cả đã đọc
  Future<bool> markAllAsRead() async {
    final uid = _uid;
    if (uid == null) return false;

    try {
      final batch = _firestore.batch();
      final snapshot = await _notificationsRef
          .where('userId', isEqualTo: uid)
          .where('status', isEqualTo: 'unread')
          .get();

      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'status': 'read',
          'readAt': Timestamp.now(),
        });
      }

      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('[NotificationRepo] Mark all read error: $e');
      return false;
    }
  }

  /// Archive một thông báo
  Future<bool> archive(String notificationId) async {
    try {
      await _notificationsRef.doc(notificationId).update({
        'status': 'archived',
      });
      return true;
    } catch (e) {
      debugPrint('[NotificationRepo] Archive error: $e');
      return false;
    }
  }

  /// Xóa một thông báo
  Future<bool> delete(String notificationId) async {
    try {
      await _notificationsRef.doc(notificationId).delete();
      return true;
    } catch (e) {
      debugPrint('[NotificationRepo] Delete error: $e');
      return false;
    }
  }

  /// Tạo thông báo mới (cho local service sử dụng)
  Future<UserNotification?> createNotification({
    required NotificationType type,
    required String title,
    required String message,
    Map<String, dynamic>? payload,
    String? actionTarget,
    String? imageUrl,
  }) async {
    final uid = _uid;
    if (uid == null) return null;

    try {
      final docRef = _notificationsRef.doc();
      final notification = UserNotification(
        id: docRef.id,
        userId: uid,
        type: type,
        title: title,
        message: message,
        createdAt: DateTime.now(),
        payload: payload,
        actionTarget: actionTarget,
        imageUrl: imageUrl,
      );

      await docRef.set(notification.toFirestore());
      return notification;
    } catch (e) {
      debugPrint('[NotificationRepo] Create error: $e');
      return null;
    }
  }

  /// Tạo thông báo model đã cập nhật
  Future<void> createModelUpdatedNotification({
    required String modelKey,
    required String modelName,
    required String version,
  }) async {
    await createNotification(
      type: NotificationType.modelUpdated,
      title: 'Model AI đã cập nhật',
      message: 'Model "$modelName" phiên bản $version đã sẵn sàng để sử dụng.',
      payload: {'modelKey': modelKey, 'version': version},
      actionTarget: '/ai/$modelKey',
    );
  }

  /// Tạo thông báo tải model thất bại
  Future<void> createModelDownloadFailedNotification({
    required String modelKey,
    required String modelName,
    required String error,
  }) async {
    await createNotification(
      type: NotificationType.modelDownloadFailed,
      title: 'Tải model thất bại',
      message: 'Không thể tải model "$modelName": $error',
      payload: {'modelKey': modelKey, 'error': error},
      actionTarget: '/ai',
    );
  }

  /// Dọn dẹp thông báo cũ (giữ lại 100 thông báo mới nhất)
  Future<void> cleanupOldNotifications() async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final snapshot = await _notificationsRef
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .get();

      if (snapshot.docs.length <= 100) return;

      final toDelete = snapshot.docs.skip(100).toList();
      final batch = _firestore.batch();

      for (final doc in toDelete) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      debugPrint('[NotificationRepo] Cleaned up ${toDelete.length} old notifications');
    } catch (e) {
      debugPrint('[NotificationRepo] Cleanup error: $e');
    }
  }
}
