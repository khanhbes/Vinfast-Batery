import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ========================================================================
/// Background Service Configuration
/// Entry point cho Isolate chạy ngầm trên Android
/// Xử lý 2 luồng: Trip Tracking (GPS) & Charge Tracking (Timer)
/// ========================================================================
class BackgroundServiceConfig {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  /// Khởi tạo background service — gọi 1 lần trong main()
  static Future<void> initialize() async {
    await _service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        // Notification config cho Foreground Service
        notificationChannelId: 'vinfast_bg_channel',
        initialNotificationTitle: 'VinFast Battery',
        initialNotificationContent: 'Đang chạy ngầm...',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
    );
    debugPrint('✅ BackgroundService configured');
  }

  /// Bắt đầu service
  static Future<void> startService() async {
    final isRunning = await _service.isRunning();
    if (!isRunning) {
      await _service.startService();
      debugPrint('🚀 BackgroundService started');
    }
  }

  /// Dừng service
  static void stopService() {
    _service.invoke('stop');
    debugPrint('🛑 BackgroundService stopped');
  }

  /// Gửi lệnh từ UI → Background Isolate
  static void sendCommand(String command, [Map<String, dynamic>? data]) {
    _service.invoke(command, data);
  }

  /// Lắng nghe data từ Background Isolate → UI
  static Stream<Map<String, dynamic>?> get onDataReceived {
    return _service.on('update');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BACKGROUND ISOLATE ENTRY POINTS
// Chạy trong isolate riêng, KHÔNG có access tới UI
// ═══════════════════════════════════════════════════════════════════════════

/// iOS background handler
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Main entry point cho background isolate
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  Timer? tripTimer;
  Timer? chargeTimer;

  // ── Lắng nghe lệnh từ UI ──

  // Lệnh dừng service
  service.on('stop').listen((event) {
    tripTimer?.cancel();
    chargeTimer?.cancel();
    service.stopSelf();
    debugPrint('🛑 Background isolate stopped');
  });

  // Lệnh bắt đầu trip tracking
  service.on('startTrip').listen((event) {
    debugPrint('🛵 BG: Trip tracking started');
    tripTimer?.cancel();
    tripTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      // Gửi heartbeat về UI
      service.invoke('update', {
        'type': 'trip',
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
  });

  // Lệnh dừng trip
  service.on('stopTrip').listen((event) {
    tripTimer?.cancel();
    tripTimer = null;
    debugPrint('🛵 BG: Trip tracking stopped');
  });

  // Lệnh bắt đầu sạc
  service.on('startCharge').listen((event) {
    debugPrint('🔌 BG: Charge tracking started');
    chargeTimer?.cancel();
    chargeTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      service.invoke('update', {
        'type': 'charge',
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
  });

  // Lệnh dừng sạc
  service.on('stopCharge').listen((event) {
    chargeTimer?.cancel();
    chargeTimer = null;
    debugPrint('🔌 BG: Charge tracking stopped');
  });

  // ── Heartbeat tổng ──
  // Gửi signal mỗi 10s để UI biết service còn sống
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    final prefs = await SharedPreferences.getInstance();
    final tripActive = prefs.getBool('trip_active') ?? false;
    final chargeActive = prefs.getBool('charge_active') ?? false;

    service.invoke('update', {
      'type': 'heartbeat',
      'tripActive': tripActive,
      'chargeActive': chargeActive,
      'timestamp': DateTime.now().toIso8601String(),
    });
  });
}
