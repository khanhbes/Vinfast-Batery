import 'dart:math';

import 'smart_charging_session.dart';

enum SmartChargeCostQuality {
  unavailable,
  provisional,
  finalValue;

  String get wireValue => switch (this) {
    unavailable => 'unavailable',
    provisional => 'provisional',
    finalValue => 'final',
  };

  static SmartChargeCostQuality fromJson(Object? value) => switch (value) {
    'provisional' => provisional,
    'final' => finalValue,
    _ => unavailable,
  };
}

class SmartChargePreferences {
  const SmartChargePreferences({
    this.ownerUid,
    this.tariffVndPerKwh,
    this.chargePowerW = 400.0,
    required this.updatedAt,
  });

  factory SmartChargePreferences.empty([DateTime? now]) =>
      SmartChargePreferences(
        updatedAt: now ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String? ownerUid;
  final double? tariffVndPerKwh;
  final double? chargePowerW;
  final DateTime updatedAt;

  bool get hasTariff => tariffVndPerKwh != null && tariffVndPerKwh! > 0;
  bool get hasChargePower => chargePowerW != null && chargePowerW! > 0;

  SmartChargePreferences copyWith({
    String? ownerUid,
    double? tariffVndPerKwh,
    double? chargePowerW,
    bool clearTariff = false,
    bool clearChargePower = false,
    DateTime? updatedAt,
  }) => SmartChargePreferences(
    ownerUid: ownerUid ?? this.ownerUid,
    tariffVndPerKwh: clearTariff
        ? null
        : tariffVndPerKwh ?? this.tariffVndPerKwh,
    chargePowerW: clearChargePower
        ? null
        : chargePowerW ?? this.chargePowerW,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory SmartChargePreferences.fromJson(Map<String, dynamic> json) =>
      SmartChargePreferences(
        ownerUid: json['ownerUid']?.toString(),
        tariffVndPerKwh: (json['tariffVndPerKwh'] as num?)?.toDouble(),
        chargePowerW: (json['chargePowerW'] as num?)?.toDouble() ?? 400.0,
        updatedAt:
            DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => {
    if (ownerUid != null) 'ownerUid': ownerUid,
    if (tariffVndPerKwh != null) 'tariffVndPerKwh': tariffVndPerKwh,
    if (chargePowerW != null) 'chargePowerW': chargePowerW,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

class SmartChargeCostSnapshot {
  const SmartChargeCostSnapshot({
    required this.gridEnergyWh,
    required this.quality,
    this.tariffVndPerKwh,
    this.costVnd,
  });

  final double gridEnergyWh;
  final double? tariffVndPerKwh;
  final double? costVnd;
  final SmartChargeCostQuality quality;

  factory SmartChargeCostSnapshot.calculate({
    required double gridEnergyWh,
    double? tariffVndPerKwh,
    required bool terminal,
  }) {
    final energy = max(0.0, gridEnergyWh);
    if (tariffVndPerKwh == null || tariffVndPerKwh <= 0) {
      return SmartChargeCostSnapshot(
        gridEnergyWh: energy,
        quality: SmartChargeCostQuality.unavailable,
      );
    }
    return SmartChargeCostSnapshot(
      gridEnergyWh: energy,
      tariffVndPerKwh: tariffVndPerKwh,
      costVnd: energy / 1000 * tariffVndPerKwh,
      quality: terminal
          ? SmartChargeCostQuality.finalValue
          : SmartChargeCostQuality.provisional,
    );
  }
}

enum SmartChargeHistorySessionFilter { all, completed, stoppedEarly, partial }

class SmartChargeHistoryQuery {
  const SmartChargeHistoryQuery({
    this.vehicleId,
    this.allVehicles = false,
    this.strategy,
    this.status = SmartChargeHistorySessionFilter.all,
    this.from,
    this.to,
    this.limit = 20,
    this.cursor,
  });

  final String? vehicleId;
  final bool allVehicles;
  final ChargingStrategy? strategy;
  final SmartChargeHistorySessionFilter status;
  final DateTime? from;
  final DateTime? to;
  final int limit;
  final String? cursor;

  bool matches(SmartChargingSession session) {
    if (!allVehicles && vehicleId != null && session.vehicleId != vehicleId) {
      return false;
    }
    if (strategy != null) {
      final ai = strategy == ChargingStrategy.aiTarget;
      if (ai && session.strategy == ChargingStrategy.manualTimed) return false;
      if (!ai && session.strategy != strategy) return false;
    }
    final started = session.startedAt ?? session.createdAt;
    if (from != null && started.isBefore(from!)) return false;
    if (to != null && !started.isBefore(to!)) return false;
    return switch (status) {
      SmartChargeHistorySessionFilter.all => true,
      SmartChargeHistorySessionFilter.completed =>
        session.state == ChargingSessionState.completed &&
            session.energyQuality != 'partial',
      SmartChargeHistorySessionFilter.stoppedEarly =>
        session.state == ChargingSessionState.interrupted ||
            session.state == ChargingSessionState.cancelled,
      SmartChargeHistorySessionFilter.partial =>
        session.energyQuality == 'partial' || session.telemetryCoverage < .70,
    };
  }
}

class SmartChargeDailyEnergy {
  const SmartChargeDailyEnergy(this.day, this.energyWh, this.costVnd);
  final DateTime day;
  final double energyWh;
  final double costVnd;
}

class SmartChargeHistorySummary {
  const SmartChargeHistorySummary({
    required this.totalGridEnergyWh,
    required this.totalCostVnd,
    required this.totalDuration,
    required this.completedSessions,
    required this.daily,
  });

  final double totalGridEnergyWh;
  final double totalCostVnd;
  final Duration totalDuration;
  final int completedSessions;
  final List<SmartChargeDailyEnergy> daily;

  factory SmartChargeHistorySummary.calculate(
    Iterable<SmartChargingSession> sessions, {
    DateTime? from,
    DateTime? to,
  }) {
    final terminal = sessions.where((session) {
      if (!session.state.isTerminal) return false;
      final started = session.startedAt ?? session.createdAt;
      return (from == null || !started.isBefore(from)) &&
          (to == null || started.isBefore(to));
    }).toList();
    var energy = 0.0;
    var cost = 0.0;
    var seconds = 0;
    final buckets = <DateTime, (double, double)>{};
    for (final session in terminal) {
      energy += max(0, session.energyUsedWh);
      cost += max(0, session.estimatedCostVnd ?? 0);
      seconds += max(
        0,
        (session.stoppedAt ?? session.updatedAt)
            .difference(session.startedAt ?? session.createdAt)
            .inSeconds,
      );
      final local = (session.startedAt ?? session.createdAt).toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final previous = buckets[day] ?? (0.0, 0.0);
      buckets[day] = (
        previous.$1 + max(0, session.energyUsedWh),
        previous.$2 + max(0, session.estimatedCostVnd ?? 0),
      );
    }
    final daily =
        buckets.entries
            .map(
              (entry) => SmartChargeDailyEnergy(
                entry.key,
                entry.value.$1,
                entry.value.$2,
              ),
            )
            .toList()
          ..sort((a, b) => a.day.compareTo(b.day));
    return SmartChargeHistorySummary(
      totalGridEnergyWh: energy,
      totalCostVnd: cost,
      totalDuration: Duration(seconds: seconds),
      completedSessions: terminal.length,
      daily: daily,
    );
  }
}

enum ChargeReportFormat { csv, pdf }

class ChargeReportRequest {
  const ChargeReportRequest({
    required this.format,
    required this.from,
    required this.to,
    required this.allVehicles,
    this.vehicleId,
  });

  final ChargeReportFormat format;
  final DateTime from;
  final DateTime to;
  final bool allVehicles;
  final String? vehicleId;
}

class ChargeReportResult {
  const ChargeReportResult({
    required this.path,
    required this.sessionCount,
    required this.format,
  });
  final String path;
  final int sessionCount;
  final ChargeReportFormat format;
}
