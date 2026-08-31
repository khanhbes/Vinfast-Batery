import '../../data/models/vehicle_model.dart';

/// App-wide identity for the vehicle whose normal content is currently shown.
/// Charging sessions remain bound to their original vehicle even when this
/// context changes.
class VehicleContext {
  const VehicleContext({required this.vehicleId, this.vehicle});

  final String vehicleId;
  final VehicleModel? vehicle;

  bool get hasVehicle => vehicleId.trim().isNotEmpty;
  String get displayName => vehicle?.vehicleName.isNotEmpty == true
      ? vehicle!.vehicleName
      : 'Chưa chọn xe';
  double get batteryPercent => (vehicle?.currentBattery ?? 0).toDouble();
  double get stateOfHealth => vehicle?.stateOfHealth ?? 0;
}
