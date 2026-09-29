import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../core/services/api_service.dart';
import '../models/user_notification.dart';

/// Repository quản lý thông báo người dùng từ Firestore
class NotificationRepository {
  static final NotificationRepository _instance =
      NotificationRepository._internal();
  factory NotificationRepository() => _instance;
  NotificationRepository._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  int? _cachedUnread;
  DateTime? _cachedUnreadAt;
  String? _cachedUnreadUid;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference get _notificationsRef =>
      _firestore.collection('UserNotifications');

  /// Stream thông báo của user hiện tại, sắp xếp mới nhất trước.
  ///
  /// Dùng query đơn `where('userId', ==, uid)` rồi sort/filter/limit ở client.
  /// Cách này KHÔNG yêu cầu composite index → không bao giờ stuck loading
  /// vì index chưa deploy. Với ≤100 doc client-side sort là rất nhẹ.
  ///
  /// Lỗi (permission, network, …) propagate thẳng lên UI để hiển thị error
  /// state thay vì spinner vô hạn.
  Stream<List<UserNotification>> watchNotifications({
    int limit = 100,
    String? expectedUid,
  }) {
    final uid = expectedUid ?? _uid;
    if (uid == null || uid.isEmpty) {
      return Stream.value(const <UserNotification>[]);
    }
    if (_uid != uid) return Stream.error(StateError('Account changed'));

    return Stream.fromFuture(getNotifications(limit: limit, expectedUid: uid));
  }

  /// Lấy danh sách thông báo một lần.
  /// Fallback: nếu thiếu index thì query không orderBy, sort ở client.
  Future<List<UserNotification>> getNotifications({
    int limit = 50,
    String? expectedUid,
  }) async {
    final uid = expectedUid ?? _uid;
    if (uid == null || uid.isEmpty) return [];
    if (_uid != uid) throw StateError('Account changed');

    try {
      final snapshot = await _notificationsRef
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      if (_uid != uid) throw StateError('Account changed');
      return snapshot.docs
          .map((doc) => UserNotification.fromFirestore(doc))
          .toList();
    } catch (e) {
      final msg = e.toString();
      final isIndexError =
          msg.contains('failed-precondition') ||
          msg.toLowerCase().contains('index');
      if (!isIndexError) {
        debugPrint('[NotificationRepo] Get error (${e.runtimeType})');
        rethrow;
      }
      // Fallback: query không orderBy
      debugPrint('[NotificationRepo] Index fallback for getNotifications');
      try {
        final snapshot = await _notificationsRef
            .where('userId', isEqualTo: uid)
            .limit(limit)
            .get();
        if (_uid != uid) throw StateError('Account changed');
        final list = snapshot.docs
            .map((doc) => UserNotification.fromFirestore(doc))
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list.take(limit).toList();
      } catch (e2) {
        debugPrint('[NotificationRepo] Fallback failed (${e2.runtimeType})');
        rethrow;
      }
    }
  }

  /// Đếm số thông báo chưa đọc — realtime snapshots.
  ///
  /// Dùng 1 where filter rồi đếm `status == 'unread'` ở client (tránh composite
  /// index khi backend chưa deploy). Lỗi không spam UI (badge fallback 0).
  Stream<int> watchUnreadCount({String? expectedUid}) =>
      Stream.fromFuture(getUnreadCount(expectedUid: expectedUid));

  Future<int> getUnreadCount({bool force = false, String? expectedUid}) async {
    final uid = expectedUid ?? _uid;
    if (uid == null || uid.isEmpty) return 0;
    if (_uid != uid) throw StateError('Account changed');
    final now = DateTime.now();
    if (!force &&
        _cachedUnreadUid == uid &&
        _cachedUnread != null &&
        _cachedUnreadAt != null &&
        now.difference(_cachedUnreadAt!) < const Duration(minutes: 1)) {
      return _cachedUnread!;
    }
    try {
      final snapshot = await _notificationsRef
          .where('userId', isEqualTo: uid)
          .where('status', isEqualTo: 'unread')
          .limit(1000)
          .get();
      if (_uid != uid) throw StateError('Account changed');
      _cachedUnread = snapshot.size;
      _cachedUnreadAt = now;
      _cachedUnreadUid = uid;
      return snapshot.size;
    } catch (e) {
      debugPrint('[NotificationRepo] Unread count error (${e.runtimeType})');
      rethrow;
    }
  }

  void invalidateUnread() {
    _cachedUnreadAt = null;
    _cachedUnread = null;
    _cachedUnreadUid = null;
  }

  /// Đánh dấu đã đọc
  Future<bool> markAsRead(String notificationId) async {
    try {
      await _notificationsRef.doc(notificationId).update({
        'status': 'read',
        'readAt': Timestamp.now(),
      });
      invalidateUnread();
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
      if (_uid != uid) return false;

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
      invalidateUnread();
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

  /// Xóa toàn bộ thông báo của tài khoản hiện tại qua API xác thực.
  ///
  /// Backend tự giới hạn truy vấn theo UID từ Firebase token và xóa theo các
  /// batch nhỏ, tránh client phải tải rồi phát hàng trăm lệnh delete riêng lẻ.
  Future<bool> deleteAll() async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final response = await ApiService().delete('/api/mobile/notifications');
      if (_uid != uid) return false;
      if (response['success'] != true) return false;
      _cachedUnread = 0;
      _cachedUnreadAt = DateTime.now();
      _cachedUnreadUid = uid;
      return true;
    } catch (e) {
      debugPrint('[NotificationRepo] Delete all error: $e');
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
      payload: {
        'modelKey': modelKey,
        'modelName': modelName,
        'version': version,
      },
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
      payload: {'modelKey': modelKey, 'modelName': modelName, 'error': error},
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
      debugPrint(
        '[NotificationRepo] Cleaned up ${toDelete.length} old notifications',
      );
    } catch (e) {
      debugPrint('[NotificationRepo] Cleanup error: $e');
    }
  }
}
