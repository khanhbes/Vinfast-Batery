import 'shelly_connection.dart';

double _asDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

class SmartChargerStatus {
  const SmartChargerStatus({
    required this.online,
    required this.relay,
    required this.powerW,
    required this.voltageV,
    required this.currentA,
    required this.frequencyHz,
    required this.temperatureC,
    required this.energyWh,
    this.timerRemaining,
    this.transport,
    this.deviceName,
    this.deviceId,
    this.codeRefreshRequired,
    double? shellyTemperatureC,
    this.batteryTemperatureC,
    this.readAt,
  }) : shellyTemperatureC = shellyTemperatureC ?? temperatureC;

  final bool online;
  final bool relay;
  final double powerW;
  final double voltageV;
  final double currentA;
  final double frequencyHz;
  final double? temperatureC;
  final double? shellyTemperatureC;
  final double? batteryTemperatureC;
  final double energyWh;
  final Duration? timerRemaining;
  final ShellyTransport? transport;
  final String? deviceName;
  final String? deviceId;
  final bool? codeRefreshRequired;

  /// When this readback was received. [timerRemaining] is only true at
  /// that instant; screens count it down with [timerRemainingAt] (Task 125).
  final DateTime? readAt;

  /// Hardware timer left at [now]: the readback minus its age, never < 0.
  Duration? timerRemainingAt(DateTime now) {
    final timer = timerRemaining;
    if (timer == null) return null;
    final at = readAt;
    if (at == null) return timer;
    final left = timer - now.difference(at);
    return left.isNegative ? Duration.zero : left;
  }

  /// Presentation copy after the server has verified a relay command
  /// (Task 122): every screen can show the new relay state at once while a
  /// fresh `/live` read follows. Never used as authorization to energize.
  SmartChargerStatus withVerifiedRelay(bool on, {Duration? timerRemaining}) =>
      SmartChargerStatus(
        online: online,
        relay: on,
        powerW: on ? powerW : 0,
        voltageV: voltageV,
        currentA: on ? currentA : 0,
        frequencyHz: frequencyHz,
        temperatureC: temperatureC,
        energyWh: energyWh,
        timerRemaining: on
            ? (timerRemaining ?? this.timerRemaining)
            : Duration.zero,
        transport: transport,
        deviceName: deviceName,
        deviceId: deviceId,
        codeRefreshRequired: codeRefreshRequired,
        shellyTemperatureC: shellyTemperatureC,
        batteryTemperatureC: batteryTemperatureC,
        // A verified command's timer is as of now.
        readAt: on && timerRemaining != null ? DateTime.now() : readAt,
      );

  /// Same wire shape as the server `/live` status (round-trips via fromJson).
  Map<String, dynamic> toJson() => {
    'online': online,
    'relay': relay,
    'power_w': powerW,
    'voltage_v': voltageV,
    'current_a': currentA,
    'frequency_hz': frequencyHz,
    if (temperatureC != null) 'temperature_c': temperatureC,
    if (shellyTemperatureC != null) 'shelly_temperature_c': shellyTemperatureC,
    if (batteryTemperatureC != null)
      'battery_temperature_c': batteryTemperatureC,
    'energy_wh': energyWh,
    if (timerRemaining != null) 'timer_remaining': timerRemaining!.inSeconds,
    if (transport != null) 'transport': transport!.name,
    if (deviceName != null) 'device_name': deviceName,
    if (deviceId != null) 'device_id': deviceId,
    if (codeRefreshRequired != null) 'codeRefreshRequired': codeRefreshRequired,
    if (readAt != null) 'read_at': readAt!.toUtc().toIso8601String(),
  };

  factory SmartChargerStatus.fromJson(Map<String, dynamic> json) {
    final online = json['online'];
    final relay = json['relay'];
    if (online is! bool || relay is! bool) {
      throw const FormatException('Invalid Smart Charger status response.');
    }
    return SmartChargerStatus(
      deviceId: json['device_id']?.toString(),
      codeRefreshRequired: json['codeRefreshRequired'] is bool
          ? json['codeRefreshRequired'] as bool
          : null,
      online: online,
      relay: relay,
      powerW: _asDouble(json['power_w']),
      voltageV: _asDouble(json['voltage_v']),
      currentA: _asDouble(json['current_a']),
      frequencyHz: _asDouble(json['frequency_hz']),
      temperatureC: json['temperature_c'] == null
          ? (json['shelly_temperature_c'] == null
                ? null
                : _asDouble(json['shelly_temperature_c']))
          : _asDouble(json['temperature_c']),
      shellyTemperatureC:
          json['shelly_temperature_c'] == null &&
              json['shellyTemperatureC'] == null
          ? null
          : _asDouble(
              json['shelly_temperature_c'] ?? json['shellyTemperatureC'],
            ),
      batteryTemperatureC:
          json['battery_temperature_c'] == null &&
              json['batteryTemperatureC'] == null
          ? null
          : _asDouble(
              json['battery_temperature_c'] ?? json['batteryTemperatureC'],
            ),
      energyWh: _asDouble(json['energy_wh']),
      timerRemaining: json['timer_remaining'] == null
          ? null
          : Duration(seconds: _asDouble(json['timer_remaining']).round()),
      transport: switch (json['transport']?.toString()) {
        'cloud' => ShellyTransport.cloud,
        'lan' => ShellyTransport.lan,
        _ => null,
      },
      deviceName: json['device_name']?.toString(),
      readAt:
          DateTime.tryParse(json['read_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}

class SmartChargerCommandResult {
  const SmartChargerCommandResult({
    required this.success,
    required this.relay,
    this.previousState,
  });

  final bool success;
  final bool relay;
  final bool? previousState;

  factory SmartChargerCommandResult.fromJson(Map<String, dynamic> json) {
    final success = json['success'];
    final relay = json['relay'];
    final previousState = json['previous_state'];
    if (success is! bool || relay is! bool) {
      throw const FormatException('Invalid Smart Charger command response.');
    }
    if (previousState != null && previousState is! bool) {
      throw const FormatException('Invalid previous relay state.');
    }
    return SmartChargerCommandResult(
      success: success,
      relay: relay,
      previousState: previousState as bool?,
    );
  }
}
