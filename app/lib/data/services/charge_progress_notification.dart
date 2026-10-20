import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'charge_estimator.dart';

/// "Charging now" notification kept alive by server pushes (Task 126).
///
/// When Android has killed the app, the live monitor ([ServerChargeMonitor])
/// is gone; the worker then sends a data-only `smart_charge_progress` push
/// about every 2 minutes and this shows/refreshes one ongoing notification.
/// Between pushes the system chronometer keeps counting down by itself. The
/// notification expires on its own ([expiry]) if pushes stop, so a lost
/// terminal push can never leave a stale "charging" behind. Display only:
/// the server and the Shelly timer own the cutoff.
abstract final class ChargeProgressNotification {
  /// Same id as the legacy ongoing-charge slot in NotificationService.
  static const int id = 1003;
  static const String channelId = 'smart_charge_progress_v1';
  static const String channelName = 'Đang sạc (cập nhật từ máy chủ)';
  static const Duration expiry = Duration(minutes: 6);
  static const String payload = 'smart_charge/current';

  static FlutterLocalNotificationsPlugin? _plugin;

  static Future<FlutterLocalNotificationsPlugin> _ready() async {
    final existing = _plugin;
    if (existing != null) return existing;
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_pinova'),
      ),
    );
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: 'Tiến độ phiên sạc khi ứng dụng đang đóng',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
            showBadge: false,
          ),
        );
    return _plugin = plugin;
  }

  /// Entry point for every FCM data message (background isolate included).
  static Future<void> handlePush(Map<String, dynamic> data) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final event = data['event']?.toString();
    try {
      if (event == 'smart_charge_progress') {
        // The app's own live monitor is more current: never show both.
        if (await _monitorRunning()) return;
        final content = ChargeProgressContent.from(data, DateTime.now());
        if (content == null) return;
        await show(content);
      } else if (event == 'smart_charge_link') {
        if (data['state'] == 'lost') {
          await showLinkAlert(data);
        } else {
          await cancelLinkAlert();
        }
      } else if (event == 'smart_charge' &&
          data['silent'] != '1' &&
          const {
            'completed',
            'cancelled',
            'interrupted',
            'failed',
          }.contains(data['state'])) {
        await cancel();
      }
    } on Object catch (error) {
      debugPrint('[ChargeProgress] skipped (${error.runtimeType})');
    }
  }

  static Future<bool> _monitorRunning() async {
    try {
      return await FlutterForegroundTask.isRunningService;
    } on Object {
      return false;
    }
  }

  static Future<void> show(ChargeProgressContent content) async {
    final plugin = await _ready();
    final finish = content.finishAt;
    await plugin.show(
      id,
      content.title,
      content.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          silent: true,
          category: AndroidNotificationCategory.progress,
          showProgress: content.progress != null,
          maxProgress: 100,
          progress: content.progress ?? 0,
          showWhen: finish != null,
          when: finish?.millisecondsSinceEpoch,
          usesChronometer: finish != null,
          chronometerCountDown: finish != null,
          timeoutAfter: expiry.inMilliseconds,
          color: const Color(0xFF9DB8E8),
        ),
      ),
      payload: payload,
    );
  }

  static const int linkAlertId = 1012;
  static const String alertChannelId = 'smart_charge_link_v1';

  /// The worker could not reach the Shelly for ~5 minutes during a charge.
  static Future<void> showLinkAlert(Map<String, dynamic> data) async {
    final plugin = await _ready();
    final ceiling = DateTime.tryParse(data['ceilingAt']?.toString() ?? '');
    final minutes =
        ((int.tryParse(data['seconds']?.toString() ?? '') ?? 0) / 60).round();
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            alertChannelId,
            'Mất kết nối khi đang sạc',
            description: 'Báo khi máy chủ không liên lạc được với ổ Shelly',
            importance: Importance.high,
          ),
        );
    await plugin.show(
      linkAlertId,
      'Mất kết nối với ổ sạc',
      'Đã ${minutes < 1 ? 'vài' : minutes} phút không liên lạc được với ổ Shelly. '
          'Xe vẫn sạc theo hẹn giờ trên ổ'
          '${ceiling == null ? '' : ', tự tắt muộn nhất ${formatClock(ceiling)}'}. '
          'Kiểm tra Wi-Fi nhà và đèn trên ổ.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          alertChannelId,
          'Mất kết nối khi đang sạc',
          importance: Importance.high,
          priority: Priority.high,
          onlyAlertOnce: true,
          category: AndroidNotificationCategory.status,
        ),
      ),
      payload: payload,
    );
  }

  static Future<void> cancelLinkAlert() async {
    try {
      await (await _ready()).cancel(linkAlertId);
    } on Object {
      // Nothing to cancel.
    }
  }

  static Future<void> cancel() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await (await _ready()).cancel(id);
    } on Object {
      // Nothing to cancel on an unsupported platform.
    }
  }
}

/// Text of the pushed progress notification; pure for unit tests.
@immutable
class ChargeProgressContent {
  const ChargeProgressContent({
    required this.title,
    required this.body,
    this.progress,
    this.finishAt,
  });

  final String title;
  final String body;

  /// Battery % for the progress bar (null when unknown).
  final int? progress;

  /// When the estimate reaches the target (chronometer counts down to it).
  final DateTime? finishAt;

  static ChargeProgressContent? from(Map<String, dynamic> data, DateTime now) {
    if (data['event'] != 'smart_charge_progress') return null;
    double? number(String key) => double.tryParse(data[key]?.toString() ?? '');
    final soc = number('soc');
    final target = number('targetSoc');
    final power = number('powerW');
    final remaining = number('remainingSeconds');
    final sentAt = DateTime.tryParse(data['sentAt']?.toString() ?? '');
    final ceiling = DateTime.tryParse(data['ceilingAt']?.toString() ?? '');
    // A push that waited in a queue: count from when the server sent it.
    final base = sentAt != null && sentAt.isBefore(now) ? sentAt : now;
    final finish = remaining == null
        ? null
        : base.add(Duration(seconds: remaining.round()));
    // The % is an estimate (no BMS): "~" like every other screen (QA 129).
    final socText = soc == null ? '—' : '~${soc.round()}%';
    final targetMode = data['stopMode'] == 'target' && target != null;
    final title = targetMode
        ? 'Đang sạc $socText → ${target.round()}%'
        : 'Đang sạc $socText';
    if (data['link'] == 'lost') {
      // The server cannot reach the Shelly; it keeps charging on its timer.
      return ChargeProgressContent(
        title: title,
        body: ceiling == null
            ? 'Tạm mất kết nối với ổ · vẫn sạc theo hẹn giờ trên ổ'
            : 'Tạm mất kết nối với ổ · vẫn sạc, ổ tự tắt muộn nhất '
                  '${formatClock(ceiling)}',
        progress: soc?.round().clamp(0, 100),
      );
    }
    final parts = <String>[
      if (power != null && power < 15)
        'Xe chưa nhận điện'
      else if (power != null)
        '${power.round()} W',
      if (finish != null && finish.isAfter(now)) 'xong ~${formatClock(finish)}',
      if (ceiling != null && !targetMode) 'tự tắt ${formatClock(ceiling)}',
      'cập nhật ${formatClock(base)}',
    ];
    return ChargeProgressContent(
      title: title,
      body: parts.join(' · '),
      progress: soc?.round().clamp(0, 100),
      finishAt: finish != null && finish.isAfter(now) ? finish : null,
    );
  }
}
