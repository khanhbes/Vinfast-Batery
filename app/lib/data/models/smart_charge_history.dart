import 'smart_charger_status.dart';
import 'smart_charging_session.dart';

enum SmartChargeHistoryStatus { loading, ready, empty, stale, error }

enum SmartChargeTelemetryStatus {
  idle,
  recording,
  syncing,
  partial,
  complete,
  error,
}

class SmartChargeStopResult {
  const SmartChargeStopResult({
    required this.relayOffVerified,
    this.session,
    this.alreadyStopped = false,
    this.historySyncPending = false,
  });

  final bool relayOffVerified;
  final SmartChargingSession? session;
  final bool alreadyStopped;
  final bool historySyncPending;
}

class SmartChargeHistoryPage {
  const SmartChargeHistoryPage({
    required this.items,
    this.nextCursor,
    this.skippedLegacyDocuments = 0,
  });

  final List<SmartChargingSession> items;
  final String? nextCursor;
  final int skippedLegacyDocuments;
}

class SmartChargeTelemetryPoint {
  const SmartChargeTelemetryPoint({
    required this.timestamp,
    required this.elapsedSeconds,
    required this.powerAverageW,
    required this.powerMinimumW,
    required this.powerMaximumW,
    required this.voltageV,
    required this.currentA,
    required this.energyWh,
    required this.relay,
    this.temperatureC,
    this.estimatedSoc,
    this.timerRemainingSeconds,
    this.transport,
    this.quality = 'good',
  });

  final DateTime timestamp;
  final int elapsedSeconds;
  final double powerAverageW;
  final double powerMinimumW;
  final double powerMaximumW;
  final double voltageV;
  final double currentA;
  final double? temperatureC;
  final double energyWh;
  final double? estimatedSoc;
  final bool relay;
  final int? timerRemainingSeconds;
  final String? transport;
  final String quality;

  factory SmartChargeTelemetryPoint.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return SmartChargeTelemetryPoint(
      timestamp: DateTime.parse(json['timestamp'].toString()),
      elapsedSeconds: (json['elapsedSeconds'] as num?)?.round() ?? 0,
      powerAverageW: number('powerAverageW'),
      powerMinimumW: number('powerMinimumW'),
      powerMaximumW: number('powerMaximumW'),
      voltageV: number('voltageV'),
      currentA: number('currentA'),
      temperatureC: (json['temperatureC'] as num?)?.toDouble(),
      energyWh: number('energyWh'),
      estimatedSoc: (json['estimatedSoc'] as num?)?.toDouble(),
      relay: json['relay'] == true,
      timerRemainingSeconds: (json['timerRemainingSeconds'] as num?)?.round(),
      transport: json['transport']?.toString(),
      quality: json['quality']?.toString() ?? 'good',
    );
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'elapsedSeconds': elapsedSeconds,
    'powerAverageW': powerAverageW,
    'powerMinimumW': powerMinimumW,
    'powerMaximumW': powerMaximumW,
    'voltageV': voltageV,
    'currentA': currentA,
    if (temperatureC != null) 'temperatureC': temperatureC,
    'energyWh': energyWh,
    if (estimatedSoc != null) 'estimatedSoc': estimatedSoc,
    'relay': relay,
    if (timerRemainingSeconds != null)
      'timerRemainingSeconds': timerRemainingSeconds,
    if (transport != null) 'transport': transport,
    'quality': quality,
  };
}

class SmartChargeEnergySummary {
  const SmartChargeEnergySummary({
    required this.gridEnergyWh,
    required this.estimatedStoredWh,
    required this.averagePowerW,
    required this.peakPowerW,
    required this.averageVoltageV,
    required this.averageCurrentA,
    required this.sampleCount,
    required this.coverageRatio,
    required this.energyQuality,
    this.maximumTemperatureC,
    this.estimatedEndSoc,
    this.estimatedRemainingWh,
    this.confirmedEndSoc,
    this.estimatedUsableCapacityWh,
  });

  final double gridEnergyWh;
  final double estimatedStoredWh;
  final double averagePowerW;
  final double peakPowerW;
  final double averageVoltageV;
  final double averageCurrentA;
  final double? maximumTemperatureC;
  final double? estimatedEndSoc;
  final double? estimatedRemainingWh;
  final double? confirmedEndSoc;
  final double? estimatedUsableCapacityWh;
  final int sampleCount;
  final double coverageRatio;
  final String energyQuality;

  static SmartChargeEnergySummary calculate({
    required SmartChargingSession session,
    required List<SmartChargeTelemetryPoint> points,
    double? confirmedEndSoc,
  }) {
    final sorted = [...points]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    var gridWh = session.energyUsedWh;
    var quality = session.energyQuality;
    if (sorted.length >= 2) {
      var positiveDelta = 0.0;
      var resetDetected = false;
      for (var index = 1; index < sorted.length; index++) {
        final delta = sorted[index].energyWh - sorted[index - 1].energyWh;
        if (delta >= 0) {
          positiveDelta += delta;
        } else {
          resetDetected = true;
        }
      }
      if (gridWh <= 0 || resetDetected) gridWh = positiveDelta;
      if (resetDetected) quality = 'partial';
    }
    if (gridWh < 0) gridWh = 0;

    final storedWh = gridWh * 0.90;
    final capacity = session.estimatedCapacityWh ?? 0;
    final estimatedEndSoc = capacity > 0
        ? (session.startSoc + storedWh / capacity * 100)
              .clamp(0, 100)
              .toDouble()
        : null;
    final remainingWh = estimatedEndSoc == null
        ? null
        : capacity * estimatedEndSoc / 100;
    final duration = (session.stoppedAt ?? session.updatedAt).difference(
      session.startedAt ?? session.createdAt,
    );
    final expectedPoints = duration.inSeconds <= 0
        ? 0
        : (duration.inSeconds / 30).ceil();
    final coverage = expectedPoints == 0
        ? 0.0
        : (sorted.length / expectedPoints).clamp(0, 1).toDouble();
    final independentGain = confirmedEndSoc == null
        ? 0.0
        : confirmedEndSoc - session.startSoc;
    final usable =
        confirmedEndSoc != null &&
            independentGain >= 10 &&
            coverage >= 0.70 &&
            gridWh > 0 &&
            duration >= const Duration(minutes: 20)
        ? storedWh / (independentGain / 100)
        : null;

    double average(double Function(SmartChargeTelemetryPoint point) read) =>
        sorted.isEmpty
        ? 0
        : sorted.map(read).reduce((a, b) => a + b) / sorted.length;
    final temperatures = sorted
        .map((point) => point.temperatureC)
        .whereType<double>()
        .toList();

    return SmartChargeEnergySummary(
      gridEnergyWh: gridWh,
      estimatedStoredWh: storedWh,
      averagePowerW: average((point) => point.powerAverageW),
      peakPowerW: sorted.isEmpty
          ? 0
          : sorted
                .map((point) => point.powerMaximumW)
                .reduce((a, b) => a > b ? a : b),
      averageVoltageV: average((point) => point.voltageV),
      averageCurrentA: average((point) => point.currentA),
      maximumTemperatureC: temperatures.isEmpty
          ? null
          : temperatures.reduce((a, b) => a > b ? a : b),
      estimatedEndSoc: estimatedEndSoc,
      estimatedRemainingWh: remainingWh,
      confirmedEndSoc: confirmedEndSoc,
      estimatedUsableCapacityWh: usable,
      sampleCount: sorted.length,
      coverageRatio: coverage,
      energyQuality: quality,
    );
  }
}

class SmartChargeRawStatusSample {
  const SmartChargeRawStatusSample(this.timestamp, this.status);
  final DateTime timestamp;
  final SmartChargerStatus status;
}
