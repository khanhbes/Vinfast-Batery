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
    double? shellyTemperatureC,
    this.batteryTemperatureC,
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

  factory SmartChargerStatus.fromJson(Map<String, dynamic> json) {
    final online = json['online'];
    final relay = json['relay'];
    if (online is! bool || relay is! bool) {
      throw const FormatException('Invalid Smart Charger status response.');
    }
    return SmartChargerStatus(
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
