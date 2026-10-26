import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../core/services/firebase_bootstrap_coordinator.dart';
import '../../core/services/platform_capability_adapter.dart';
import '../models/smart_charger_status.dart';
import '../models/smart_charging_session.dart';
import 'charge_progress_notification.dart';
import 'charge_estimator.dart';
import 'server_smart_charger_service.dart';
import 'smart_charge_telemetry_foreground_service.dart';

/// Ongoing "charging now" notification for server-owned sessions (Task 126).
///
/// The server and the Shelly timer own the cutoff; this only reads `/live`
/// every [pollInterval] and shows battery %, power and time left, with a
/// plain "Dừng sạc" button (stopping never needs an extra step). A failed
/// read keeps the last values and says so; it never changes the session.
class ServerChargeMonitor {
  ServerChargeMonitor._();

  static const pollInterval = Duration(seconds: 15);
  static const _serviceId = 24072;
  static const sessionIdKey = 'serverChargeSessionId';
  static const vehicleIdKey = 'serverChargeVehicleId';
  static const stopButtonId = 'stop';
  static String? _runningFor;

  static Future<void> start(SmartChargingSession session) async {
    if (!PlatformCapabilityAdapter.supportsContinuousForegroundService) return;
    if (_runningFor == session.sessionId &&
        await FlutterForegroundTask.isRunningService) {
      return;
    }
    SmartChargeTelemetryForegroundService.initialize();
    // The live monitor replaces the push-driven notification (Task 126).
    await ChargeProgressNotification.cancel();
    await FlutterForegroundTask.saveData(
      key: sessionIdKey,
      value: session.sessionId,
    );
    await FlutterForegroundTask.saveData(
      key: vehicleIdKey,
      value: session.vehicleId,
    );
    final content = ServerChargeNotificationContent.from(
      session: session,
      now: DateTime.now(),
    );
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: const [ForegroundServiceTypes.connectedDevice],
        notificationTitle: content.title,
        notificationText: content.text,
        notificationButtons: const [
          NotificationButton(id: stopButtonId, text: 'Dừng sạc'),
        ],
        notificationInitialRoute: '/',
        callback: serverChargeMonitorStartCallback,
      );
    }
    _runningFor = session.sessionId;
  }

  static Future<void> stop() async {
    _runningFor = null;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {
      // Unsupported platform or plugin not registered (tests).
    }
  }
}

/// Text of the ongoing notification; pure so it can be unit tested.
@immutable
class ServerChargeNotificationContent {
  const ServerChargeNotificationContent(this.title, this.text);

  final String title;
  final String text;

  static ServerChargeNotificationContent from({
    required SmartChargingSession session,
    SmartChargerStatus? status,
    required DateTime now,
    int failedReads = 0,
    bool linkLost = false,
  }) {
    final soc = session.estimatedSoc;
    final target = session.targetSoc.round();
    final socText = soc == null ? '—' : 'khoảng ${soc.round()}%';
    final title = session.isTargetMode
        ? 'Đang sạc $socText → $target%'
        : 'Đang sạc $socText';
    if (linkLost) {
      return ServerChargeNotificationContent(
        title,
        'Tạm mất kết nối với ổ · vẫn sạc, ổ tự tắt muộn nhất '
        '${formatClock(session.effectiveStopAt)}',
      );
    }
    if (failedReads >= 3) {
      final ceiling = session.effectiveStopAt;
      return ServerChargeNotificationContent(
        title,
        'Chưa đọc được trạng thái · Shelly vẫn tự tắt muộn nhất '
        '${formatClock(ceiling)}',
      );
    }
    final power = status?.powerW;
    if (power != null && power < 15) {
      return ServerChargeNotificationContent(
        title,
        'Xe chưa nhận điện · máy chủ tự tắt nếu kéo dài 3 phút',
      );
    }
    final left = remaining(session: session, status: status, now: now);
    final parts = <String>[
      if (power != null) '${power.round()} W',
      if (left != null && left > Duration.zero)
        'còn khoảng ${formatChargeDuration(left)}',
      if (left != null && left > Duration.zero)
        'xong khoảng ${formatClock(now.add(left))}',
    ];
    return ServerChargeNotificationContent(
      title,
      parts.isEmpty ? 'Đang cập nhật số liệu…' : parts.join(' · '),
    );
  }

  /// Target charge: energy left at the measured power (same model as the
  /// server). Timed charge: the Shelly timer.
  static Duration? remaining({
    required SmartChargingSession session,
    SmartChargerStatus? status,
    required DateTime now,
  }) {
    if (session.isTargetMode) {
      final soc = session.estimatedSoc;
      final wh = session.modelWhPerPct;
      final live = status?.powerW;
      final power = live != null && live >= ChargeEstimator.minChargingPowerW
          ? live
          : session.averagePowerW;
      if (soc != null && wh != null && power != null && power > 0) {
        return Duration(
          seconds: ChargeEstimator.wallSeconds(
            whPerPct: wh,
            powerW: power,
            from: soc,
            to: session.targetSoc,
          ),
        );
      }
      final left = session.aiStopAt.difference(now);
      return left.isNegative ? Duration.zero : left;
    }
    return status?.timerRemainingAt(now) ?? session.remaining(now);
  }
}

@pragma('vm:entry-point')
void serverChargeMonitorStartCallback() {
  FlutterForegroundTask.setTaskHandler(_ServerChargeMonitorHandler());
}

class _ServerChargeMonitorHandler extends TaskHandler {
  ServerSmartChargerService? _service;
  SmartChargingSession? _last;
  SmartChargerStatus? _lastStatus;
  int _failedReads = 0;
  bool _linkLost = false;
  bool _polling = false;
  DateTime? _lastPollAt;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    DartPluginRegistrant.ensureInitialized();
    await FirebaseBootstrapCoordinator.ensureInitialized();
    _service = ServerSmartChargerService();
    await _poll();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final last = _lastPollAt;
    if (_polling ||
        (last != null &&
            timestamp.difference(last) < ServerChargeMonitor.pollInterval)) {
      return;
    }
    unawaited(_poll());
  }

  Future<void> _poll() async {
    final service = _service;
    if (service == null) return;
    _polling = true;
    _lastPollAt = DateTime.now();
    try {
      final vehicleId = await FlutterForegroundTask.getData<String>(
        key: ServerChargeMonitor.vehicleIdKey,
      );
      final data = await service.getLive(vehicleId: vehicleId);
      final rawSession = data['session'];
      final rawStatus = data['status'];
      final session = rawSession is Map
          ? SmartChargingSession.fromJson(Map<String, dynamic>.from(rawSession))
          : null;
      if (session == null || session.state.isTerminal) {
        // The server push carries the final result; nothing left to show.
        await FlutterForegroundTask.stopService();
        return;
      }
      _last = session;
      final link = data['link'];
      _linkLost = link is Map && link['state'] == 'lost';
      if (_linkLost) {
        _failedReads = 0;
        await _render();
        return;
      }
      _lastStatus = rawStatus is Map
          ? SmartChargerStatus.fromJson(Map<String, dynamic>.from(rawStatus))
          : null;
      _failedReads = 0;
      await _render();
    } catch (_) {
      _failedReads++;
      await _render();
    } finally {
      _polling = false;
    }
  }

  Future<void> _render() async {
    final session = _last;
    if (session == null) return;
    final content = ServerChargeNotificationContent.from(
      session: session,
      status: _lastStatus,
      now: DateTime.now(),
      failedReads: _failedReads,
      linkLost: _linkLost,
    );
    await FlutterForegroundTask.updateService(
      notificationTitle: content.title,
      notificationText: content.text,
    );
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id != ServerChargeMonitor.stopButtonId) return;
    unawaited(_stop());
  }

  Future<void> _stop() async {
    final service = _service;
    final session = _last;
    if (service == null) return;
    await FlutterForegroundTask.updateService(
      notificationText: 'Đang gửi lệnh dừng và chờ Shelly xác nhận…',
    );
    try {
      // The server verifies OFF (readback) exactly as the in-app button.
      await service.off(
        sessionId: session?.sessionId,
        vehicleId: session?.vehicleId,
      );
      _lastPollAt = null;
      await _poll();
    } catch (_) {
      await FlutterForegroundTask.updateService(
        notificationText:
            'Chưa dừng được. Mở app để dừng sạc; Shelly vẫn tự tắt theo giới hạn an toàn.',
      );
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _service?.close();
  }
}
