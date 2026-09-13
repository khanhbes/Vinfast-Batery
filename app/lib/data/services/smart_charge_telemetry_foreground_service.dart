import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../core/services/platform_capability_adapter.dart';
import '../../core/services/firebase_bootstrap_coordinator.dart';

import '../models/smart_charger_status.dart';
import '../models/smart_charging_session.dart';
import 'shelly_charge_log_service.dart';
import 'smart_charger_service.dart';
import 'smart_charge_energy_accumulator.dart';

/// Dedicated Android foreground worker for Smart Charge telemetry.
///
/// Shelly's device timer remains the safety authority. This worker only reads
/// status and persists measurements; it never extends an armed timer.
class SmartChargeTelemetryForegroundService {
  SmartChargeTelemetryForegroundService._();

  static const _serviceId = 24071;
  static const _route = '/';
  static const _sessionIdKey = 'smartChargeSessionId';
  static const _sessionPayloadKey = 'smartChargeSessionPayload';
  static final _statusController =
      StreamController<SmartChargerStatus>.broadcast();
  static bool _initialized = false;

  static Stream<SmartChargerStatus> get statuses => _statusController.stream;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_receiveTaskData);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'smart_charge_monitoring_v1',
        channelName: 'Theo dõi Smart Charge',
        channelDescription:
            'Hiển thị khi ứng dụng đang ghi dữ liệu sạc từ Shelly.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowAutoRestart: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  static Future<void> start(SmartChargingSession session) async {
    if (!PlatformCapabilityAdapter.supportsContinuousForegroundService) {
      debugPrint('[SmartChargeTelemetry] iOS uses backend timer and resume reconciliation');
      return;
    }
    initialize();
    await FlutterForegroundTask.saveData(
      key: _sessionIdKey,
      value: session.sessionId,
    );
    // The task isolate cannot depend on the UI controller or a Firestore
    // session query during startup. Persist a self-contained, non-secret
    // snapshot alongside the id so it can continue telemetry after the app
    // is backgrounded or killed.
    await FlutterForegroundTask.saveData(
      key: _sessionPayloadKey,
      value: jsonEncode(session.toJson()),
    );
    await FlutterForegroundTask.saveData(
      key: 'smartChargeSafetyStopAt',
      value: session.absoluteSafetyStopAt.toIso8601String(),
    );
    final running = await FlutterForegroundTask.isRunningService;
    if (running) {
      await FlutterForegroundTask.restartService();
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: const [ForegroundServiceTypes.connectedDevice],
      notificationTitle: 'Đang theo dõi Smart Charge',
      notificationText: 'Shelly đang sạc với timer an toàn trên thiết bị',
      notificationInitialRoute: _route,
      callback: smartChargeTelemetryStartCallback,
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static void _receiveTaskData(Object data) {
    if (data is! Map) return;
    final raw = data['status'];
    if (raw is! Map) return;
    try {
      _statusController.add(
        SmartChargerStatus.fromJson(Map<String, dynamic>.from(raw)),
      );
    } catch (_) {
      // A malformed UI update must not stop the background safety monitor.
    }
  }
}

@pragma('vm:entry-point')
void smartChargeTelemetryStartCallback() {
  FlutterForegroundTask.setTaskHandler(_SmartChargeTelemetryTaskHandler());
}

class _SmartChargeTelemetryTaskHandler extends TaskHandler {
  static const _sessionPayloadKey = 'smartChargeSessionPayload';
  SmartChargerService? _charger;
  ShellyChargeLogService? _logs;
  bool _polling = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    DartPluginRegistrant.ensureInitialized();
    await FirebaseBootstrapCoordinator.ensureInitialized();
    _charger = SmartChargerService();
    _logs = ShellyChargeLogService();
    await _poll(timestamp);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_polling) return;
    unawaited(_poll(timestamp));
  }

  Future<void> _poll(DateTime timestamp) async {
    _polling = true;
    try {
      final charger = _charger;
      final logs = _logs;
      if (charger == null || logs == null) return;
      final encoded = await FlutterForegroundTask.getData<String>(
        key: _sessionPayloadKey,
      );
      final session = encoded == null
          ? null
          : SmartChargingSession.fromJson(
              Map<String, dynamic>.from(jsonDecode(encoded) as Map),
            );
      if (session == null || session.state.isTerminal) {
        await FlutterForegroundTask.stopService();
        return;
      }

      // Never monitor beyond the immutable 10-hour safety boundary. The OFF
      // command is idempotent and verified by the direct service.
      if (!timestamp.isBefore(session.absoluteSafetyStopAt)) {
        final terminal = await charger.turnOffAndVerify(
          reason: ChargingStopReason.safetyCutoff,
        );
        if (terminal != null) await logs.saveTerminalSession(terminal);
        await logs.flushPendingTelemetry(session.sessionId);
        await FlutterForegroundTask.stopService();
        return;
      }

      final status = await charger.getStatus();
      final meter = SmartChargeEnergyAccumulator.ingest(session, status.energyWh);
      final measured = session.copyWith(
        baselineEnergyWh: meter.baselineEnergyWh,
        lastMeterEnergyWh: meter.lastMeterEnergyWh,
        energyUsedWh: meter.energyUsedWh,
        energyQuality: meter.energyQuality,
      );
      final estimate = SmartChargeEnergyAccumulator.estimate(measured);
      final updated = measured.copyWith(
        estimatedSoc: estimate.soc,
        estimatedStoredEnergyWh:
            estimate.available ? estimate.storedEnergyWh : null,
        socEstimateSource: estimate.available ? 'shelly_energy' : 'unavailable',
        socEstimateQuality: estimate.available
            ? (meter.energyQuality == 'good' ? 'live' : 'partial')
            : 'unavailable',
        socEstimationVersion: 2,
      );
      await charger.persistActiveTelemetry(updated);
      await FlutterForegroundTask.saveData(
        key: _sessionPayloadKey,
        value: jsonEncode(updated.toJson()),
      );
      await logs.recordStatusSample(updated, status);
      FlutterForegroundTask.sendDataToMain({
        'status': {
          'online': status.online,
          'relay': status.relay,
          'power_w': status.powerW,
          'voltage_v': status.voltageV,
          'current_a': status.currentA,
          'frequency_hz': status.frequencyHz,
          'temperature_c': status.temperatureC,
          'energy_wh': status.energyWh,
          'timer_remaining': status.timerRemaining?.inSeconds,
          'transport': status.transport?.name,
          'device_name': status.deviceName,
        },
      });
      final power = status.powerW.round();
      final totalSeconds = status.timerRemaining?.inSeconds ?? 0;
      final hours = totalSeconds ~/ 3600;
      final minutes = (totalSeconds % 3600) ~/ 60;
      final timeStr = totalSeconds > 0
          ? (hours > 0
              ? 'còn khoảng ${hours}g ${minutes.toString().padLeft(2, '0')}p'
              : 'còn khoảng $minutes phút')
          : 'đang sạc';

      final socText = estimate.available ? '${estimate.soc!.round()}%' : '—';

      await FlutterForegroundTask.updateService(
        notificationTitle: 'Đang sạc $socText · $power W',
        notificationText: '$socText · $power W · $timeStr',
      );

      if (!status.relay) {
        final terminal = await charger.reconcileActiveSession();
        if (terminal?.state.isTerminal == true) {
          await logs.saveTerminalSession(terminal!);
        }
        await logs.flushPendingTelemetry(session.sessionId);
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {
      // The Shelly timer stays armed if polling or persistence is unavailable.
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Smart Charge đang chạy',
        notificationText:
            'Mất dữ liệu tạm thời; timer an toàn vẫn ở trên Shelly',
      );
    } finally {
      _polling = false;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    final sessionId = await FlutterForegroundTask.getData<String>(
      key: 'smartChargeSessionId',
    );
    if (sessionId != null) {
      try {
        await _logs?.flushPendingTelemetry(sessionId);
      } catch (_) {}
    }
  }
}
