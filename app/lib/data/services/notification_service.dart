import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Service quản lý Local Notifications
/// - Thông báo sạc pin 80%, 100%
/// - Thông báo bảo dưỡng sắp đến hạn
/// - Foreground notification cho background service
///
/// Luôn gọi `initialize()` trước schedule/show để đảm bảo timezone + permissions.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _exactAlarmGranted = false;
  void Function(String payload)? _tapHandler;

  void setTapHandler(void Function(String payload) handler) {
    _tapHandler = handler;
  }

  /// true khi app đang dùng inexact alarm (do Android chưa cấp exact).
  /// UI dùng để hiển thị badge "Nhắc gần đúng".
  bool get isUsingInexactAlarm => !_exactAlarmGranted;

  // Notification Channel IDs
  static const String channelCharge = 'charge_channel';
  static const String channelSmartCharge = 'smart_charge_alerts_v2';
  static const String channelTrip = 'trip_channel';
  static const String channelMaintenance = 'maintenance_channel';
  // Must exist before flutter_background_service posts its foreground
  // notification. Android rejects a notification that references a missing
  // channel and may kill the app on API 36.
  static const String channelBackgroundService = 'vinfast_bg_channel';

  // Notification IDs
  static const int idCharge80 = 1001;
  static const int idCharge100 = 1002;
  static const int idChargeOngoing = 1003;
  static const int idTripOngoing = 1004;
  static const int idChargeTarget = 1005;
  static const int idSmartChargeState = 1010;
  static const int idSmartChargeUnsafe = 1011;
  static const int idMaintenanceBase = 2000;

  Future<void> initialize() async {
    if (_initialized) return;

    // ── 1. Timezone (bắt buộc cho zonedSchedule) ────────────────────────
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));

    // ── 2. Local notification plugin init ──────────────────────────────
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchPayload = launchDetails?.notificationResponse?.payload;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchPayload != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _tapHandler?.call(launchPayload),
      );
    }

    // Permission requests are user initiated from onboarding, Settings, or a
    // feature-specific rationale. Initialization must never open OS dialogs.
    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin != null) {
        // Tạo channels
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
            channelSmartCharge,
            'Cảnh báo Smart Charge',
            description: 'Trạng thái relay, timer và cảnh báo an toàn Shelly',
            importance: Importance.high,
            enableVibration: true,
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

        // Android 12+: chỉ kiểm tra exact alarm, không ép mở màn Settings.
        // Một số máy/OEM làm mờ toggle này; app vẫn schedule bằng inexact alarm.
        try {
          final exact =
              await androidPlugin.canScheduleExactNotifications() ?? false;
          _exactAlarmGranted = exact;
          debugPrint('[NotificationService] Exact alarm permission: $exact');
        } catch (e) {
          debugPrint(
            '[NotificationService] Exact alarm check error: $e — using inexact',
          );
          _exactAlarmGranted = false;
        }
      }
    }
    // Keep the foreground-service channel creation as a final guard as well
    // as the normal channel setup above. This covers callers that initialize
    // the service from a different startup path.
    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelBackgroundService,
          'VinFast Battery',
          description: 'Background service status',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );
    }
    _initialized = true;
    if (kDebugMode) {
      debugPrint(
        '[NotificationService] Initialized (timezone=Asia/Ho_Chi_Minh)',
      );
    }
  }

  /// Opens the platform permission prompt only after an explicit user action.
  Future<bool> requestPermission() async {
    await initialize();
    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidPlugin?.requestNotificationsPermission();
      return granted ?? await _hasNotificationPermission();
    }
    if (Platform.isIOS) {
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? await _hasNotificationPermission();
    }
    return true;
  }

  /// Kiểm tra xem notification permission đã được cấp chưa.
  Future<bool> _hasNotificationPermission() async {
    if (Platform.isIOS) {
      final plugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final settings = await plugin?.checkPermissions();
      return settings?.isEnabled ?? true;
    }
    if (!Platform.isAndroid) return true;
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) _tapHandler?.call(payload);
  }

  AndroidNotificationDetails _smartChargeDetails() =>
      const AndroidNotificationDetails(
        channelSmartCharge,
        'Cảnh báo Smart Charge',
        channelDescription:
            'Trạng thái relay, timer và cảnh báo an toàn Shelly',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

  DarwinNotificationDetails _iosDetails({bool presentSound = true}) =>
      DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: presentSound,
        threadIdentifier: channelSmartCharge,
      );

  Future<void> notifySmartChargeRelayOff({
    required String sessionId,
    String? vehicleId,
    bool interrupted = false,
  }) async {
    await initialize();
    await _plugin.show(
      idSmartChargeState,
      interrupted ? 'Phiên Smart Charge đã bị ngắt' : 'Đã xác nhận Shelly OFF',
      interrupted
          ? 'Relay đã tắt trước giờ dự kiến. Mở Smart Charge để kiểm tra.'
          : 'App đã đọc lại thiết bị và xác nhận nguồn sạc đã ngắt.',
      NotificationDetails(android: _smartChargeDetails(), iOS: _iosDetails()),
      payload: _smartChargeSessionPayload(vehicleId, sessionId),
    );
  }

  Future<void> notifySmartChargeUnsafe({
    required String sessionId,
    String? vehicleId,
    required String message,
  }) async {
    await initialize();
    await _plugin.show(
      idSmartChargeUnsafe,
      'Cảnh báo an toàn Smart Charge',
      message,
      NotificationDetails(android: _smartChargeDetails(), iOS: _iosDetails()),
      payload: _smartChargeSessionPayload(vehicleId, sessionId),
    );
  }

  String _smartChargeSessionPayload(String? vehicleId, String sessionId) {
    final safeSession = Uri.encodeComponent(sessionId);
    final safeVehicle = vehicleId == null || vehicleId.isEmpty
        ? ''
        : '${Uri.encodeComponent(vehicleId)}/';
    return 'smart_charge/session/$safeVehicle$safeSession';
  }

  // ── Charge Notifications ──

  /// Thông báo pin đã đạt mục tiêu sạc
  Future<void> notifyChargeTarget(int currentPercent, int targetPercent) async {
    await initialize();
    await _plugin.show(
      idChargeTarget,
      '🎯 Đã đạt mục tiêu sạc $targetPercent%!',
      'Pin hiện tại: $currentPercent%. Bạn có thể rút sạc.',
      NotificationDetails(
        iOS: _iosDetails(),
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
    await initialize();
    await _plugin.show(
      idCharge80,
      '🔋 Pin đã sạc $currentPercent%',
      'Pin đã đạt 80% — Bạn có thể rút sạc để bảo vệ tuổi thọ pin.',
      NotificationDetails(
        iOS: _iosDetails(),
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
    await initialize();
    await _plugin.show(
      idCharge100,
      '⚡ Pin đã sạc đầy 100%!',
      'Hãy rút sạc ngay để tránh sạc quá mức, bảo vệ tuổi thọ pin.',
      NotificationDetails(
        iOS: _iosDetails(),
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

  /// Thông báo nhắc người dùng xác nhận mức pin thực tế sau khi sạc xong để fine-tune AI
  Future<void> showChargeCompleteSocConfirm({
    required String sessionId,
    double? estimatedSoc,
  }) async {
    await initialize();
    final socText = estimatedSoc != null
        ? ' (ước tính ~${estimatedSoc.toStringAsFixed(0)}%)'
        : '';
    await _plugin.show(
      1012,
      '⚡ Phiên sạc hoàn tất$socText',
      'Nhấn để xác nhận mức pin thực tế trên xe để AI học chuẩn xác hơn.',
      NotificationDetails(
        iOS: _iosDetails(),
        android: AndroidNotificationDetails(
          channelSmartCharge,
          'Smart Charge Alerts',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: 'confirm_soc:$sessionId',
    );
  }

  /// Notification ongoing khi đang sạc
  Future<void> showChargingOngoing(int currentPercent, String elapsed) async {
    await initialize();
    await _plugin.show(
      idChargeOngoing,
      '🔌 Đang sạc... $currentPercent%',
      'Thời gian: $elapsed',
      NotificationDetails(
        iOS: _iosDetails(presentSound: false),
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
    await initialize();
    await _plugin.show(
      idTripOngoing,
      '🛵 Đang di chuyển...',
      'Quãng đường: ${distance.toStringAsFixed(1)} km — Pin: $battery%',
      NotificationDetails(
        iOS: _iosDetails(presentSound: false),
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

  // ── Scheduled Notifications ──

  static const int idChargeReminder = 210;

  /// Schedule charging completion reminder.
  ///
  /// Trả về `true` nếu schedule thành công với exact alarm,
  /// `false` nếu dùng inexact (vẫn thành công nhưng kém chính xác).
  /// Ném nếu notification permission bị từ chối hoàn toàn.
  Future<bool> scheduleChargeReminder(
    DateTime reminderTime,
    int targetPercent, {
    String? vehicleId,
    String? sessionId,
  }) async {
    await initialize(); // idempotent
    if (!await _hasNotificationPermission()) {
      throw Exception(
        'Notification permission denied. Hãy bật quyền thông báo trong Cài đặt.',
      );
    }

    // Chuyển sang TZDateTime với timezone Asia/Ho_Chi_Minh đã init trong initialize()
    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(
      reminderTime,
      tz.local,
    );

    // Validate thời điểm nhắc phải ở tương lai
    final now = tz.TZDateTime.now(tz.local);
    if (scheduledDate.isBefore(now) || scheduledDate == now) {
      throw Exception('Thời điểm nhắc nhở đã qua.');
    }

    // Android 12+: exact alarm cần quyền; nếu chưa có → fallback inexact (không crash)
    final exactGranted = _exactAlarmGranted;
    final androidMode = exactGranted
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    debugPrint(
      '[NotificationService] Scheduling charge reminder at '
      '${scheduledDate.toLocal()} (mode=$androidMode, exact=$exactGranted)',
    );

    await _plugin.zonedSchedule(
      idChargeReminder,
      'Shelly dự kiến đã tự ngắt',
      'Mốc ~$targetPercent% đã tới. Mở app để đọc lại relay và xác nhận nguồn đã OFF.',
      scheduledDate,
      NotificationDetails(
        iOS: _iosDetails(),
        android: AndroidNotificationDetails(
          channelSmartCharge,
          'Cảnh báo Smart Charge',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      androidScheduleMode: androidMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: _smartChargeReminderPayload(vehicleId, sessionId, targetPercent),
    );
    // true = exact, false = inexact
    return exactGranted;
  }

  String _smartChargeReminderPayload(
    String? vehicleId,
    String? sessionId,
    int targetPercent,
  ) {
    if (vehicleId == null ||
        vehicleId.isEmpty ||
        sessionId == null ||
        sessionId.isEmpty) {
      return 'smart_charge/current?target=$targetPercent';
    }
    return 'smart_charge/session/${Uri.encodeComponent(vehicleId)}/${Uri.encodeComponent(sessionId)}';
  }

  /// Cancel scheduled charging reminder
  Future<void> cancelChargeReminder() async {
    await initialize();
    await _plugin.cancel(idChargeReminder);
  }

  // ── Maintenance Notifications ──

  /// Thông báo bảo dưỡng sắp đến hạn
  Future<void> notifyMaintenanceDue(
    String taskId,
    String title,
    int remainingKm,
  ) async {
    await initialize();
    final id = idMaintenanceBase + taskId.hashCode.abs() % 999;
    await _plugin.show(
      id,
      '🔧 Bảo dưỡng sắp đến hạn',
      '$title — Còn $remainingKm km nữa',
      NotificationDetails(
        iOS: _iosDetails(),
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
    await initialize();
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    await initialize();
    await _plugin.cancelAll();
  }
}
