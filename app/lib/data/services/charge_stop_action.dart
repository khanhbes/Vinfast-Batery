import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/firebase_bootstrap_coordinator.dart';
import 'charge_progress_notification.dart';
import 'server_smart_charger_service.dart';

/// "Dừng sạc" on the pushed charging notification (QA 140): it works on the
/// lock screen and after the app was swiped away. Android runs
/// [chargeStopFromNotification] in a background isolate; it signs in from
/// the saved Firebase session and sends the same verified OFF as the app's
/// button (the server reads the relay back). Stopping never needs a second
/// step, and a failure says so instead of pretending.
abstract final class ChargeStopAction {
  static const actionId = 'stop_charge';
  static const _sessionKey = 'charge_notification_session_v1';
  static const _vehicleKey = 'charge_notification_vehicle_v1';

  /// The session the notification is about, for the background isolate.
  static Future<void> remember(String? sessionId, String? vehicleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (sessionId == null || sessionId.isEmpty) {
        await prefs.remove(_sessionKey);
      } else {
        await prefs.setString(_sessionKey, sessionId);
      }
      if (vehicleId == null || vehicleId.isEmpty) {
        await prefs.remove(_vehicleKey);
      } else {
        await prefs.setString(_vehicleKey, vehicleId);
      }
    } on Object {
      // Without it the button still stops by vehicle on the server.
    }
  }

  static Future<void> run() async {
    String? sessionId;
    String? vehicleId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // written by another isolate
      sessionId = prefs.getString(_sessionKey);
      vehicleId = prefs.getString(_vehicleKey);
    } on Object {
      // Fall through: the server refuses a stop it cannot place.
    }
    await ChargeProgressNotification.showStopping();
    ServerSmartChargerService? service;
    try {
      await FirebaseBootstrapCoordinator.ensureInitialized();
      service = ServerSmartChargerService();
      await service.off(sessionId: sessionId, vehicleId: vehicleId);
      await ChargeProgressNotification.showStopped();
      await remember(null, null);
    } on Object catch (error) {
      debugPrint('[ChargeStop] failed (${error.runtimeType})');
      await ChargeProgressNotification.showStopFailed();
    } finally {
      service?.close();
    }
  }
}

/// Background entry point for notification actions (top level, kept by the
/// compiler for the platform to call).
@pragma('vm:entry-point')
void chargeStopFromNotification(NotificationResponse response) {
  if (response.actionId != ChargeStopAction.actionId) return;
  DartPluginRegistrant.ensureInitialized();
  unawaited(ChargeStopAction.run());
}
