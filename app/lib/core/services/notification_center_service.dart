import 'package:flutter/material.dart';
import '../../data/models/user_notification.dart';
import '../../data/repositories/notification_repository.dart';
import 'model_sync_service.dart';

/// Service tích hợp Notification Center với Model Sync
/// Tự động tạo thông báo khi có model mới/cập nhật
class NotificationCenterService {
  static final NotificationCenterService _instance =
      NotificationCenterService._internal();
  factory NotificationCenterService() => _instance;
  NotificationCenterService._internal();

  final NotificationRepository _repository = NotificationRepository();
  final ModelSyncService _modelSync = ModelSyncService();

  bool _initialized = false;

  /// Khởi tạo service
  Future<void> initialize() async {
    if (_initialized) return;

    // Khởi tạo các service con
    await _modelSync.initialize();

    // Đăng ký callback khi có model update
    _modelSync.onModelUpdate = _onModelsUpdated;

    _initialized = true;
    debugPrint('[NotificationCenter] Initialized');
  }

  /// Đồng bộ model và tạo thông báo nếu có cập nhật
  Future<ModelSyncResult> syncModels({bool force = false}) async {
    if (!_initialized) {
      await initialize();
    }

    final result = await _modelSync.sync(force: force);

    // Dọn dẹp thông báo cũ sau mỗi lần sync
    if (result.success) {
      await _repository.cleanupOldNotifications();
    }

    return result;
  }

  /// Callback khi có model mới/cập nhật
  void _onModelsUpdated(
    List<DeployedModelInfo> newModels,
    List<DeployedModelInfo> updatedModels,
  ) {
    // Tạo thông báo cho model mới
    for (final model in newModels) {
      _createModelNotification(model, isNew: true);
    }

    // Tạo thông báo cho model cập nhật
    for (final model in updatedModels) {
      _createModelNotification(model, isNew: false);
    }
  }

  /// Tạo thông báo và local notification cho model
  Future<void> _createModelNotification(
    DeployedModelInfo model, {
    required bool isNew,
  }) async {
    final title = isNew ? 'Model AI đã triển khai' : 'Model AI đã cập nhật';

    final message = isNew
        ? 'Model "${model.label}" phiên bản ${model.deploymentVersion} đã được triển khai và sẵn sàng để sử dụng.'
        : 'Model "${model.label}" đã được cập nhật lên phiên bản ${model.deploymentVersion}.';

    // Tạo notification trong Firestore (cho Notification Center)
    await _repository.createNotification(
      type: NotificationType.modelUpdated,
      title: title,
      message: message,
      payload: {
        'modelKey': model.key,
        'version': model.deploymentVersion,
        'isNew': isNew,
        'mobileCompatible': model.mobileCompatible,
      },
      actionTarget: '/ai/${model.key}',
    );

    // TODO: Hiển thị local notification khi có notification_service
    // if (notification != null) {
    //   await _localNotifications.showNotification(...);
    // }

    debugPrint('[NotificationCenter] Created notification for ${model.key}');
  }

  /// Tạo thông báo tải model thất bại
  Future<void> notifyModelDownloadFailed(
    DeployedModelInfo model,
    String error,
  ) async {
    await _repository.createModelDownloadFailedNotification(
      modelKey: model.key,
      modelName: model.label,
      error: error,
    );

    // TODO: Local notification - cần notification_service
    // await _localNotifications.showNotification(...);
  }

  /// Tạo thông báo bảo dưỡng đến hạn
  Future<void> notifyMaintenanceDue({
    required String vehicleName,
    required String taskName,
    required int daysRemaining,
  }) async {
    final title = daysRemaining <= 0
        ? 'Bảo dưỡng đến hạn ngay hôm nay'
        : 'Bảo dưỡng đến hạn trong $daysRemaining ngày';

    await _repository.createNotification(
      type: NotificationType.maintenanceDue,
      title: title,
      message: '$vehicleName: $taskName cần được thực hiện.',
      payload: {
        'vehicleName': vehicleName,
        'taskName': taskName,
        'daysRemaining': daysRemaining,
      },
      actionTarget: '/maintenance',
    );

    // TODO: Local notification - cần notification_service
    // await _localNotifications.showNotification(...);
  }

  Future<void> notifyChargeReminderScheduled({
    required int targetPercent,
    required DateTime scheduledAt,
    required bool exact,
  }) async {
    await _repository.createNotification(
      type: NotificationType.chargeReminder,
      title: 'Đã đặt nhắc rút sạc',
      message: exact
          ? 'App sẽ nhắc bạn rút sạc lúc ${_formatDateTime(scheduledAt)} khi pin dự kiến đạt $targetPercent%.'
          : 'App sẽ nhắc gần đúng lúc ${_formatDateTime(scheduledAt)} khi pin dự kiến đạt $targetPercent%.',
      payload: {
        'targetPercent': targetPercent,
        'scheduledAt': scheduledAt.toIso8601String(),
        'exact': exact,
      },
      actionTarget: '/ai/charging_time',
    );
  }

  Future<void> notifyChargeReminderCancelled({DateTime? scheduledAt}) async {
    await _repository.createNotification(
      type: NotificationType.chargeReminder,
      title: 'Đã hủy nhắc rút sạc',
      message: scheduledAt == null
          ? 'Nhắc hẹn rút sạc hiện tại đã được hủy.'
          : 'Nhắc hẹn rút sạc lúc ${_formatDateTime(scheduledAt)} đã được hủy.',
      payload: {
        if (scheduledAt != null) 'scheduledAt': scheduledAt.toIso8601String(),
      },
      actionTarget: '/ai/charging_time',
    );
  }

  Future<void> notifyAppUpdateAvailable({
    required String latestVersion,
    required int latestBuild,
    required bool forceUpdate,
  }) async {
    await _repository.createNotification(
      type: NotificationType.system,
      title: forceUpdate ? 'Cập nhật bắt buộc' : 'Có phiên bản mới',
      message: latestBuild > 0
          ? 'VinFast Battery $latestVersion+$latestBuild đã sẵn sàng để tải về.'
          : 'VinFast Battery $latestVersion đã sẵn sàng để tải về.',
      payload: {
        'latestVersion': latestVersion,
        'latestBuild': latestBuild,
        'forceUpdate': forceUpdate,
      },
      actionTarget: '/settings/update',
    );
  }

  Future<void> notifyModelDeployed({
    required String modelKey,
    required String modelName,
    required String version,
  }) async {
    await _repository.createNotification(
      type: NotificationType.modelUpdated,
      title: 'Model AI đã triển khai',
      message: 'Model "$modelName" phiên bản $version đã sẵn sàng để sử dụng.',
      payload: {'modelKey': modelKey, 'version': version},
      actionTarget: '/ai/$modelKey',
    );
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$hh:$mm $dd/$mo/${local.year}';
  }

  /// Stream thông báo
  Stream<List<UserNotification>> watchNotifications({int limit = 100}) {
    return _repository.watchNotifications(limit: limit);
  }

  /// Stream unread count
  Stream<int> watchUnreadCount() {
    return _repository.watchUnreadCount();
  }

  /// Lấy danh sách thông báo
  Future<List<UserNotification>> getNotifications({int limit = 50}) {
    return _repository.getNotifications(limit: limit);
  }

  /// Đánh dấu đã đọc
  Future<bool> markAsRead(String notificationId) {
    return _repository.markAsRead(notificationId);
  }

  /// Đánh dấu tất cả đã đọc
  Future<bool> markAllAsRead() {
    return _repository.markAllAsRead();
  }

  /// Archive
  Future<bool> archive(String notificationId) {
    return _repository.archive(notificationId);
  }

  /// Xóa
  Future<bool> delete(String notificationId) {
    return _repository.delete(notificationId);
  }

  /// Model sync service (truy cập trực tiếp nếu cần)
  ModelSyncService get modelSync => _modelSync;
}
