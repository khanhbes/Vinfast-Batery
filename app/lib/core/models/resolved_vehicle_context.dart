import '../../data/models/vehicle_model.dart';
import '../../data/models/vinfast_model_spec.dart';

/// Manufacturer data is resolved from the latest reviewed catalog while live
/// and personal values remain on the user's vehicle document.
class ResolvedVehicleContext {
  const ResolvedVehicleContext({required this.vehicle, this.catalog});

  final VehicleModel vehicle;
  final VinFastModelSpec? catalog;

  String get displayName {
    final nickname = vehicle.nickname?.trim() ?? '';
    if (nickname.isNotEmpty) return nickname;
    return catalog?.modelName ?? vehicle.vehicleName;
  }

  String get manufacturer => catalog?.brandName ?? '';
  String get modelName => catalog?.modelName ?? vehicle.vehicleName;
  int? get catalogRevision => catalog?.specVersion;
  bool get hasCatalogUpdate =>
      catalog != null &&
      vehicle.catalogRevisionAtSelection != null &&
      catalog!.specVersion > vehicle.catalogRevisionAtSelection!;
  double get batteryCapacityWh =>
      catalog?.nominalCapacityWh ?? vehicle.batteryCapacityWh;
  double get defaultEfficiency =>
      catalog?.defaultEfficiencyKmPerPercent ?? vehicle.defaultEfficiency;
  String get batteryChemistry =>
      catalog?.batteryChemistry ?? vehicle.batteryType ?? 'Unknown';
}
