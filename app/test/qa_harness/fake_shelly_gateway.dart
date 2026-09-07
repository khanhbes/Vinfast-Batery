import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

enum ShellyRelayState {
  unknown,
  offline,
  off,
  commandOnPending,
  on,
  commandOffPending,
  readbackMismatch,
  safetyCutoff,
}

/// Fake Shelly / Smart Charger Gateway for isolated QA testing and fault injection.
/// Implements state machine, fault injection (offline, timeout, HTTP 500/503,
/// stale telemetry, readback mismatch, restart, safety cutoff, manual OFF priority).
class FakeShellyGateway {
  FakeShellyGateway({
    this.deviceId = 'shellyplus1pm-test-01',
    this.deviceIp = '192.168.1.199',
  });

  final String deviceId;
  final String deviceIp;

  ShellyRelayState state = ShellyRelayState.off;
  bool isOffline = false;
  bool shouldTimeout = false;
  int? forcedHttpError;
  bool simulateMismatchOnReadback = false;
  bool simulateStaleTelemetry = false;
  Duration staleTelemetryAge = const Duration(minutes: 15);
  bool autoOnAfterRestartTriggered = false;

  int commandOnCount = 0;
  int commandOffCount = 0;
  final List<Map<String, dynamic>> callHistory = [];

  void reset() {
    state = ShellyRelayState.off;
    isOffline = false;
    shouldTimeout = false;
    forcedHttpError = null;
    simulateMismatchOnReadback = false;
    simulateStaleTelemetry = false;
    autoOnAfterRestartTriggered = false;
    commandOnCount = 0;
    commandOffCount = 0;
    callHistory.clear();
  }

  void triggerSafetyCutoff({String reason = 'overpower_detected'}) {
    state = ShellyRelayState.safetyCutoff;
    callHistory.add({
      'event': 'safety_cutoff',
      'reason': reason,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void triggerDeviceRestart() {
    // A safe device restart MUST return to OFF state, never auto-ON
    state = ShellyRelayState.off;
    callHistory.add({
      'event': 'device_restart',
      'timestamp': DateTime.now().toIso8601String(),
      'relayStateAfterRestart': 'off',
    });
  }

  Future<http.Response> handleRpcRequest(String method, Map<String, dynamic> params) async {
    callHistory.add({
      'method': method,
      'params': params,
      'timestamp': DateTime.now().toIso8601String(),
    });

    if (shouldTimeout) {
      await Future.delayed(const Duration(milliseconds: 500));
      throw TimeoutException('Fake Shelly gateway timed out after 500ms');
    }

    if (isOffline) {
      return http.Response(
        jsonEncode({'error': {'code': -1, 'message': 'Device offline / unreachable'}}),
        503,
      );
    }

    if (forcedHttpError != null) {
      return http.Response(
        jsonEncode({'error': {'code': forcedHttpError, 'message': 'Simulated Server Error'}}),
        forcedHttpError!,
      );
    }

    if (method == 'Switch.Set') {
      final bool targetOn = params['on'] == true;
      if (targetOn) {
        commandOnCount++;
        state = ShellyRelayState.commandOnPending;
        // Check if readback mismatch is injected
        if (simulateMismatchOnReadback) {
          state = ShellyRelayState.readbackMismatch;
          return http.Response(
            jsonEncode({'was_on': false, 'is_on': false, 'mismatch': true}),
            200,
          );
        }
        state = ShellyRelayState.on;
        return http.Response(
          jsonEncode({'was_on': false, 'is_on': true}),
          200,
        );
      } else {
        commandOffCount++;
        state = ShellyRelayState.commandOffPending;
        state = ShellyRelayState.off;
        return http.Response(
          jsonEncode({'was_on': true, 'is_on': false}),
          200,
        );
      }
    }

    if (method == 'Switch.GetStatus' || method == 'Shelly.GetStatus') {
      final now = DateTime.now();
      final reportedTime = simulateStaleTelemetry
          ? now.subtract(staleTelemetryAge)
          : now;

      final bool isOn = state == ShellyRelayState.on;
      return http.Response(
        jsonEncode({
          'id': 0,
          'output': isOn,
          'apower': isOn ? 2150.0 : 0.0,
          'voltage': isOn ? 228.4 : 230.1,
          'current': isOn ? 9.41 : 0.0,
          'temperature': {'tC': 36.5},
          'timer_duration': isOn ? 14400 : 0,
          'timer_remaining': isOn ? 14380 : 0,
          'updated_at': reportedTime.toIso8601String(),
          'is_stale': simulateStaleTelemetry,
        }),
        200,
      );
    }

    return http.Response(
      jsonEncode({'error': {'code': 404, 'message': 'Unknown RPC method: $method'}}),
      404,
    );
  }
}
