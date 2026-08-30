enum BatteryTelemetryQuality { good, estimated, stale, partial }

class ChargingTelemetrySample {
  const ChargingTelemetrySample({
    required this.timestamp,
    required this.sessionEnergyWh,
    required this.powerW,
    required this.voltageV,
    required this.currentA,
    required this.relay,
    required this.timerRemainingSeconds,
    required this.targetSoc,
    this.shellyTemperatureC,
    this.batteryTemperatureC,
    this.soc,
    this.socSource = 'estimated',
    this.transport = 'unknown',
    this.quality = BatteryTelemetryQuality.good,
  });

  final DateTime timestamp;
  final double sessionEnergyWh;
  final double powerW;
  final double voltageV;
  final double currentA;
  final double? shellyTemperatureC;
  final double? batteryTemperatureC;
  final double? soc;
  final String socSource;
  final double targetSoc;
  final bool relay;
  final int timerRemainingSeconds;
  final String transport;
  final BatteryTelemetryQuality quality;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'sessionEnergyWh': sessionEnergyWh,
    'powerW': powerW,
    'voltageV': voltageV,
    'currentA': currentA,
    'shellyTemperatureC': shellyTemperatureC,
    'batteryTemperatureC': batteryTemperatureC,
    'soc': soc,
    'socSource': socSource,
    'targetSoc': targetSoc,
    'relay': relay,
    'timerRemainingSeconds': timerRemainingSeconds,
    'transport': transport,
    'quality': quality.name,
  };
}
