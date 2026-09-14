import 'dart:math' as math;

import '../models/smart_charging_session.dart';

/// One deterministic interpretation of Shelly's cumulative energy meter.
/// The same rules are used while charging and when a terminal session is
/// persisted, so a final read cannot regress the SOC shown in the app.
class SmartChargeEnergyAccumulator {
  SmartChargeEnergyAccumulator._();

  static const double defaultChargingEfficiency = .90;

  static SmartChargeMeterUpdate ingest(
    SmartChargingSession session,
    double meterEnergyWh,
  ) {
    final reading = math.max(0, meterEnergyWh).toDouble();
    final baseline = session.baselineEnergyWh;
    if (baseline == null) {
      return SmartChargeMeterUpdate(
        baselineEnergyWh: reading,
        lastMeterEnergyWh: reading,
        energyUsedWh: session.energyUsedWh,
        energyQuality: session.energyQuality,
      );
    }

    final last = session.lastMeterEnergyWh ?? baseline;
    var used = math.max(0, session.energyUsedWh).toDouble();
    var quality = session.energyQuality;
    var nextBaseline = baseline;
    var nextLast = last;
    if (reading >= last) {
      used += reading - last;
      nextLast = reading;
    } else {
      final resetThreshold = math.max(25, last.abs() * .20).toDouble();
      if (reading < last - resetThreshold) {
        // The lifetime counter reset. Preserve previously accumulated energy
        // and use the new reading as the base for subsequent deltas.
        nextBaseline = reading;
        nextLast = reading;
        quality = 'meter_reset';
      }
      // A small backwards movement is meter jitter. Keep [last] so the next
      // valid reading contributes only the missing positive delta.
    }
    return SmartChargeMeterUpdate(
      baselineEnergyWh: nextBaseline,
      lastMeterEnergyWh: nextLast,
      energyUsedWh: used,
      energyQuality: quality,
    );
  }

  static SmartChargeSocEstimate estimate(
    SmartChargingSession session, {
    double? energyUsedWh,
  }) {
    // A present zero is not a usable capacity. Continue through the ordered
    // fallbacks instead of treating it as a valid override.
    final capacity = _firstPositive([
      session.effectiveCapacityWh,
      session.estimatedCapacityWh,
      session.nominalCapacityWh,
    ]);
    if (capacity == null) return const SmartChargeSocEstimate.unavailable();
    final efficiency = _validEfficiency(session.chargingEfficiency);
    final gridEnergy = math.max(0, energyUsedWh ?? session.energyUsedWh).toDouble();
    final stored = gridEnergy * efficiency;
    final soc = (session.startSoc + stored / capacity * 100)
        .clamp(session.startSoc, 100.0)
        .toDouble();
    return SmartChargeSocEstimate(
      available: true,
      gridEnergyWh: gridEnergy,
      storedEnergyWh: stored,
      capacityWh: capacity,
      efficiency: efficiency,
      soc: soc,
    );
  }

  static double? _positive(double? value) =>
      value != null && value.isFinite && value > 0 ? value : null;

  static double? _firstPositive(Iterable<double?> values) {
    for (final value in values) {
      final positive = _positive(value);
      if (positive != null) return positive;
    }
    return null;
  }

  static double _validEfficiency(double? value) =>
      value != null && value.isFinite && value >= .65 && value <= .98
          ? value
          : defaultChargingEfficiency;
}

class SmartChargeMeterUpdate {
  const SmartChargeMeterUpdate({
    required this.baselineEnergyWh,
    required this.lastMeterEnergyWh,
    required this.energyUsedWh,
    required this.energyQuality,
  });

  final double baselineEnergyWh;
  final double lastMeterEnergyWh;
  final double energyUsedWh;
  final String energyQuality;
}

class SmartChargeSocEstimate {
  const SmartChargeSocEstimate({
    required this.available,
    required this.gridEnergyWh,
    required this.storedEnergyWh,
    required this.capacityWh,
    required this.efficiency,
    required this.soc,
  });

  const SmartChargeSocEstimate.unavailable()
    : available = false,
      gridEnergyWh = 0,
      storedEnergyWh = 0,
      capacityWh = 0,
      efficiency = SmartChargeEnergyAccumulator.defaultChargingEfficiency,
      soc = null;

  final bool available;
  final double gridEnergyWh;
  final double storedEnergyWh;
  final double capacityWh;
  final double efficiency;
  final double? soc;
}
