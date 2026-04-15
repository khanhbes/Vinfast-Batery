import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

/// Service quản lý Local Notifications
/// - Thông báo sạc pin 80%, 100%
/// - Thông báo bảo dưỡng sắp đến hạn
/// - Foreground notification cho background service
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Notification Channel IDs
  static const String channelCharge = 'charge_channel';
  static const String channelTrip = 'trip_channel';
  static const String channelMaintenance = 'maintenance_channel';

  // Notification IDs
  static const int idCharge80 = 1001;
  static const int idCharge100 = 1002;
  static const int idChargeOngoing = 1003;
  static const int idTripOngoing = 1004;
  static const int idChargeTarget = 1005;
  static const int idMaintenanceBase = 2000;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Tạo notification channels
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          channelCharge,
          'Sạc pin',
          description: 'Thông báo trạng thái sạc pin',
          importance: Importance.high,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          channelTrip,
          'Hành trình',
          description: 'Thông báo tracking hành trình',
          importance: Importance.low,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          channelMaintenance,
          'Bảo dưỡng',
          description: 'Nhắc nhở bảo dưỡng xe',
          importance: Importance.high,
        ),
      );
    }

    _initialized = true;
    debugPrint('✅ NotificationService initialized');
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
  }

  // ── Charge Notifications ──

  /// Thông báo pin đã đạt mục tiêu sạc
  Future<void> notifyChargeTarget(int currentPercent, int targetPercent) async {
    await _plugin.show(
      idChargeTarget,
      '🎯 Đã đạt mục tiêu sạc $targetPercent%!',
      'Pin hiện tại: $currentPercent%. Bạn có thể rút sạc.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelCharge,
          'Sạc pin',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  /// Thông báo pin đã sạc đến 80%
  Future<void> notifyCharge80(int currentPercent) async {
    await _plugin.show(
      idCharge80,
      '🔋 Pin đã sạc $currentPercent%',
      'Pin đã đạt 80% — Bạn có thể rút sạc để bảo vệ tuổi thọ pin.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelCharge,
          'Sạc pin',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  /// Thông báo pin đã sạc đầy 100%
  Future<void> notifyCharge100() async {
    await _plugin.show(
      idCharge100,
      '⚡ Pin đã sạc đầy 100%!',
      'Hãy rút sạc ngay để tránh sạc quá mức, bảo vệ tuổi thọ pin.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelCharge,
          'Sạc pin',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  /// Notification ongoing khi đang sạc
  Future<void> showChargingOngoing(int currentPercent, String elapsed) async {
    await _plugin.show(
      idChargeOngoing,
      '🔌 Đang sạc... $currentPercent%',
      'Thời gian: $elapsed',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelCharge,
          'Sạc pin',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  /// Notification ongoing khi đang chạy
  Future<void> showTripOngoing(double distance, int battery) async {
    await _plugin.show(
      idTripOngoing,
      '🛵 Đang di chuyển...',
      'Quãng đường: ${distance.toStringAsFixed(1)} km — Pin: $battery%',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelTrip,
          'Hành trình',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  // ── Maintenance Notifications ──

  /// Thông báo bảo dưỡng sắp đến hạn
  Future<void> notifyMaintenanceDue(String taskId, String title, int remainingKm) async {
    final id = idMaintenanceBase + taskId.hashCode.abs() % 999;
    await _plugin.show(
      id,
      '🔧 Bảo dưỡng sắp đến hạn',
      '$title — Còn $remainingKm km nữa',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelMaintenance,
          'Bảo dưỡng',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: 'maintenance_$taskId',
    );
  }

  /// Xóa notification đang hiển thị
  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
