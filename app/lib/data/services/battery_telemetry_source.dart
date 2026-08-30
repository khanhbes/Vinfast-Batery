class BatteryTelemetryReading {
  const BatteryTelemetryReading({
    required this.timestamp,
    required this.source,
    required this.quality,
    this.soc,
    this.temperatureC,
  });

  final double? soc;
  final double? temperatureC;
  final DateTime timestamp;
  final String source;
  final String quality;
}

abstract interface class BatteryTelemetrySource {
  Future<BatteryTelemetryReading?> latest(String vehicleId);
}

class EstimatedBatteryTelemetrySource implements BatteryTelemetrySource {
  const EstimatedBatteryTelemetrySource(this.reader);

  final Future<double?> Function(String vehicleId) reader;

  @override
  Future<BatteryTelemetryReading?> latest(String vehicleId) async {
    final soc = await reader(vehicleId);
    if (soc == null) return null;
    return BatteryTelemetryReading(
      soc: soc.clamp(0, 100),
      temperatureC: null,
      timestamp: DateTime.now(),
      source: 'estimated',
      quality: 'estimated',
    );
  }
}

abstract interface class BmsBatteryTelemetrySource
    implements BatteryTelemetrySource {}
