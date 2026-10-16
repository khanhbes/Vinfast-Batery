import '../models/vehicle_model.dart';

/// Battery kept in reserve when estimating range: the BMS cuts power before
/// 0 %, so the last few percent are not usable distance.
const double rangeReservePercent = 5;

/// One local range formula for the Battery monitor, the Overview offline
/// fallback and battery snapshots (Task 122):
/// `(SOC − reserve) × km/1 % × SoH`.
///
/// Returns null when the vehicle lacks real battery, SoH or efficiency data,
/// so callers show "chưa đủ dữ liệu" instead of an invented number.
double? estimateRangeKm(VehicleModel vehicle, {double? socOverride}) {
  final soc = socOverride ?? vehicle.currentBattery.toDouble();
  final efficiency = vehicle.defaultEfficiency;
  final soh = vehicle.stateOfHealth;
  if (!vehicle.hasBatteryData ||
      !vehicle.hasSohData ||
      !vehicle.hasEfficiencyData ||
      !soc.isFinite ||
      !efficiency.isFinite ||
      efficiency <= 0 ||
      !soh.isFinite ||
      soh < 0 ||
      soh > 100) {
    return null;
  }
  final usable = (soc.clamp(0, 100) - rangeReservePercent).clamp(0, 100);
  return usable * efficiency * soh / 100;
}
