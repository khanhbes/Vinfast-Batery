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
      '@drawable/ic_stat_pinova',
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
            'Cảnh báo sạc thông minh',
            description: 'Trạng thái relay, timer và cảnh báo an toàn Shelly',
            importance: Importance.high,
            enableVibration: true,
          ),
        );
        // QA 135: safety cutoffs and night-charging problems ring like an
        // alarm (the server sends them on this channel), so they wake the
        // owner even with the ringer silenced.
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            channelUrgent,
            'Cảnh báo khẩn',
            description:
                'Ngắt sạc vì an toàn và sự cố sạc đêm: kêu như báo thức',
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
            audioAttributesUsage: AudioAttributesUsage.alarm,
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
          'Pinova',
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
        'Cảnh báo sạc thông minh',
        channelDescription:
            'Trạng thái relay, timer và cảnh báo an toàn Shelly',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_stat_pinova',
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
    bool userStopped = false,
  }) async {
    await initialize();
    final String title;
    final String body;
    if (userStopped) {
      title = 'Đã dừng sạc';
      body = 'Shelly đã xác nhận tắt theo yêu cầu của bạn.';
    } else if (interrupted) {
      title = 'Phiên Smart Charge đã bị ngắt';
      body = 'Relay đã tắt trước giờ dự kiến. Mở Smart Charge để kiểm tra.';
    } else {
      title = 'Đã sạc xong theo hẹn giờ';
      body = 'Shelly đã tự ngắt đúng giờ và được đọc lại xác nhận.';
    }
    await _plugin.show(
      idSmartChargeState,
      title,
      body,
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
      'Cảnh báo an toàn khi sạc',
      message,
      NotificationDetails(android: _smartChargeDetails(), iOS: _iosDetails()),
      payload: _smartChargeSessionPayload(vehicleId, sessionId),
    );
  }

  static const int idTrainingReady = 1013;
  static const String channelLearning = 'ai_learning_v1';

  /// Task 127: enough new data for the owner to train a personal model.
  Future<void> showTrainingReady({
    required String vehicleId,
    required String message,
  }) async {
    await initialize();
    if (!await _hasNotificationPermission()) return;
    await _plugin.show(
      idTrainingReady,
      'Đủ dữ liệu để huấn luyện AI',
      message,
      NotificationDetails(
        android: const AndroidNotificationDetails(
          channelLearning,
          'AI cá nhân',
          channelDescription: 'Báo khi đủ dữ liệu để huấn luyện mô hình riêng',
          icon: '@drawable/ic_stat_pinova',
        ),
        iOS: _iosDetails(presentSound: false),
      ),
      payload: 'learning/${Uri.encodeComponent(vehicleId)}',
    );
  }

  static const int idUrgent = 1014;
  static const String channelUrgent = 'pinova_urgent';

  /// QA 135: a safety cutoff or a night-charging problem that arrived while
  /// the app was open (the system shows it by itself otherwise).
  Future<void> showUrgent({
    required String title,
    required String message,
    String? payload,
  }) async {
    await initialize();
    if (!await _hasNotificationPermission()) return;
    await _plugin.show(
      idUrgent,
      title,
      message,
      NotificationDetails(
        android: const AndroidNotificationDetails(
          channelUrgent,
          'Cảnh báo khẩn',
          channelDescription:
              'Ngắt sạc vì an toàn và sự cố sạc đêm: kêu như báo thức',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          icon: '@drawable/ic_stat_pinova',
        ),
        iOS: _iosDetails(),
      ),
      payload: payload,
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

  // ── Scheduled Notifications ──

  static const int idChargeReminder = 210;

  /// One reminder id per vehicle, stable across restarts (String.hashCode is
  /// not): one vehicle ending no longer cancels another's reminder (Task 125).
  static int chargeReminderIdFor(String? vehicleId) {
    if (vehicleId == null || vehicleId.isEmpty) return idChargeReminder;
    var hash = 0;
    for (final unit in vehicleId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return 2100 + hash % 800;
  }

  /// Date reminders are intentionally inexact; no permission prompt here.
  Future<bool> scheduleAccountReminder(
    int id,
    DateTime date,
    int daysBefore,
    String taskId,
  ) async {
    await initialize();
    if (!await _hasNotificationPermission()) return false;
    final when = tz.TZDateTime(
      tz.getLocation('Asia/Ho_Chi_Minh'),
      date.year,
      date.month,
      date.day,
      9,
    ).subtract(Duration(days: daysBefore));
    if (!when.isAfter(tz.TZDateTime.now(when.location))) return true;
    await _plugin.zonedSchedule(
      id,
      'Lịch nhắc cho xe',
      'Bạn có lịch bảo hành hoặc bảo dưỡng sắp đến hạn. Mở app để xem chi tiết.',
      when,
      NotificationDetails(
        iOS: _iosDetails(),
        android: AndroidNotificationDetails(
          channelMaintenance,
          'Bảo dưỡng',
          icon: '@drawable/ic_stat_pinova',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'maintenance_$taskId',
    );
    return true;
  }

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
      chargeReminderIdFor(vehicleId),
      'Shelly dự kiến đã tự ngắt',
      'Mốc ~$targetPercent% đã tới. Mở app để đọc lại relay và xác nhận nguồn đã OFF.',
      scheduledDate,
      NotificationDetails(
        iOS: _iosDetails(),
        android: AndroidNotificationDetails(
          channelSmartCharge,
          'Cảnh báo sạc thông minh',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_stat_pinova',
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
  Future<void> cancelChargeReminder({String? vehicleId}) async {
    await initialize();
    await _plugin.cancel(chargeReminderIdFor(vehicleId));
    // Reminders scheduled by builds before Task 125 used one shared id.
    if (vehicleId != null) await _plugin.cancel(idChargeReminder);
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
          icon: '@drawable/ic_stat_pinova',
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
