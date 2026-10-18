import '../models/vehicle_model.dart';
import 'trip_energy_model.dart';

/// Battery kept in reserve when estimating range: the BMS cuts power before
/// 0 %, so the last few percent are not usable distance.
const double rangeReservePercent = 5;

/// Where the km per 1 % behind a range comes from.
enum RangeSource {
  /// Trained on the owner's own rides (Task 127).
  learned,

  /// Vehicle catalog km/1 % × SoH.
  catalog,
}

/// One range everyone shows (Overview hero, stats, range card, Battery
/// monitor, BatteryBot): QA 129 found 1.20, 1.21 and ~1.36 km/% for the same
/// scooter on different screens.
class RangeEstimate {
  const RangeEstimate({
    required this.km,
    required this.lowKm,
    required this.highKm,
    required this.kmPerPct,
    required this.source,
    this.samples = 0,
  });

  final double km;
  final double lowKm;
  final double highKm;

  /// Average km per 1 % over mixed riding.
  final double kmPerPct;
  final RangeSource source;

  /// Rides the learned model was trained on.
  final int samples;
}

/// `(SOC − reserve) × km/1 %`. The km/1 % is the owner's learned average
/// when a trained trip model exists (it already reflects today's battery, so
/// SoH is not applied again), otherwise catalog km/1 % × SoH.
///
/// Returns null when the vehicle lacks real battery data (or, without a
/// learned model, SoH/efficiency data), so callers show "chưa đủ dữ liệu"
/// instead of an invented number.
RangeEstimate? estimateRange(
  VehicleModel vehicle, {
  double? socOverride,
  TripModelParams? learned,
}) {
  final soc = socOverride ?? vehicle.currentBattery.toDouble();
  if (!vehicle.hasBatteryData || !soc.isFinite) return null;
  final usable = (soc.clamp(0, 100) - rangeReservePercent).clamp(0, 100);
  if (learned != null && learned.source == TripKmSource.model) {
    final perPct = learned.kmPerPct;
    if (perPct.isFinite && perPct > 0) {
      final km = usable * perPct;
      return RangeEstimate(
        km: km,
        lowKm: km * (1 - learned.spread),
        highKm: km * (1 + learned.spread),
        kmPerPct: perPct,
        source: RangeSource.learned,
        samples: learned.samples,
      );
    }
  }
  final efficiency = vehicle.defaultEfficiency;
  final soh = vehicle.stateOfHealth;
  if (!vehicle.hasSohData ||
      !vehicle.hasEfficiencyData ||
      !efficiency.isFinite ||
      efficiency <= 0 ||
      !soh.isFinite ||
      soh < 0 ||
      soh > 100) {
    return null;
  }
  final perPct = efficiency * soh / 100;
  final km = usable * perPct;
  return RangeEstimate(
    km: km,
    lowKm: km * (1 - TripEnergyModel.catalogSpread),
    highKm: km * (1 + TripEnergyModel.catalogSpread),
    kmPerPct: perPct,
    source: RangeSource.catalog,
  );
}

/// The km per 1 % behind [estimateRange] (learned average, else catalog ×
/// SoH, else catalog), or null when nothing is known.
double? kmPerPctFor(VehicleModel vehicle, TripModelParams? learned) {
  if (learned != null && learned.source == TripKmSource.model) {
    final perPct = learned.kmPerPct;
    if (perPct.isFinite && perPct > 0) return perPct;
  }
  final efficiency = vehicle.defaultEfficiency;
  if (!vehicle.hasEfficiencyData || !efficiency.isFinite || efficiency <= 0) {
    return null;
  }
  final soh = vehicle.stateOfHealth;
  return vehicle.hasSohData && soh.isFinite && soh > 0 && soh <= 100
      ? efficiency * soh / 100
      : efficiency;
}

/// [estimateRange] in km only.
double? estimateRangeKm(
  VehicleModel vehicle, {
  double? socOverride,
  TripModelParams? learned,
}) =>
    estimateRange(vehicle, socOverride: socOverride, learned: learned)?.km;
