import 'dart:async';
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

  /// Stream thông báo của user hiện tại, sắp xếp mới nhất trước.
  ///
  /// Dùng query đơn `where('userId', ==, uid)` rồi sort/filter/limit ở client.
  /// Cách này KHÔNG yêu cầu composite index → không bao giờ stuck loading
  /// vì index chưa deploy. Với ≤100 doc client-side sort là rất nhẹ.
  ///
  /// Lỗi (permission, network, …) propagate thẳng lên UI để hiển thị error
  /// state thay vì spinner vô hạn.
  Stream<List<UserNotification>> watchNotifications({int limit = 100}) {
    final uid = _uid;
    if (uid == null) return Stream.value(const <UserNotification>[]);

    return _notificationsRef
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => UserNotification.fromFirestore(doc))
          .where((n) => n.status != NotificationStatus.archived)
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list.take(limit).toList();
    });
  }

  /// Lấy danh sách thông báo một lần.
  /// Fallback: nếu thiếu index thì query không orderBy, sort ở client.
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
      final msg = e.toString();
      final isIndexError = msg.contains('failed-precondition') ||
          msg.toLowerCase().contains('index');
      if (!isIndexError) {
        debugPrint('[NotificationRepo] Get error (non-index): $e');
        return [];
      }
      // Fallback: query không orderBy
      debugPrint('[NotificationRepo] Index fallback for getNotifications');
      try {
        final snapshot = await _notificationsRef
            .where('userId', isEqualTo: uid)
            .get();
        final list = snapshot.docs
            .map((doc) => UserNotification.fromFirestore(doc))
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list.take(limit).toList();
      } catch (e2) {
        debugPrint('[NotificationRepo] Fallback also failed: $e2');
        return [];
      }
    }
  }

  /// Đếm số thông báo chưa đọc — realtime snapshots.
  ///
  /// Dùng 1 where filter rồi đếm `status == 'unread'` ở client (tránh composite
  /// index khi backend chưa deploy). Lỗi không spam UI (badge fallback 0).
  Stream<int> watchUnreadCount() {
    final uid = _uid;
    if (uid == null) return Stream.value(0);

    return _notificationsRef
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          var count = 0;
          for (final doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>?;
            if (data?['status'] == 'unread') count++;
          }
          return count;
        })
        .handleError((Object error, StackTrace st) {
          debugPrint('[NotificationRepo] Unread count error: $error');
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

  /// Đánh dấu tất cả đã đọc.
  /// Query 1 where rồi filter `status == 'unread'` ở client (tránh composite index).
  Future<bool> markAllAsRead() async {
    final uid = _uid;
    if (uid == null) return false;

    try {
      final snapshot = await _notificationsRef
          .where('userId', isEqualTo: uid)
          .get();

      final unread = snapshot.docs.where((d) {
        final data = d.data() as Map<String, dynamic>?;
        return data?['status'] == 'unread';
      }).toList();

      if (unread.isEmpty) return true;

      final batch = _firestore.batch();
      for (final doc in unread) {
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

  /// Dọn dẹp thông báo cũ (giữ lại 100 thông báo mới nhất).
  /// Fallback nếu thiếu index: query không orderBy, sort ở client.
  Future<void> cleanupOldNotifications() async {
    final uid = _uid;
    if (uid == null) return;

    try {
      QuerySnapshot snapshot;
      try {
        snapshot = await _notificationsRef
            .where('userId', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .get();
      } catch (indexErr) {
        // Fallback: không orderBy, sort ở client
        debugPrint('[NotificationRepo] Cleanup index fallback');
        snapshot = await _notificationsRef
            .where('userId', isEqualTo: uid)
            .get();
      }

      // Sort client-side (mới nhất trước)
      final sortedDocs = snapshot.docs.toList();
      sortedDocs.sort((a, b) {
        final aTime = (a.data() as Map<String, dynamic>?)?['createdAt'];
        final bTime = (b.data() as Map<String, dynamic>?)?['createdAt'];
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return (bTime as Comparable).compareTo(aTime);
      });

      if (sortedDocs.length <= 100) return;

      final toDelete = sortedDocs.skip(100).toList();
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
