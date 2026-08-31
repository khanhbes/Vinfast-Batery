/// Product policy is configurable so server and UI can evolve together.
class VehiclePolicy {
  const VehiclePolicy({this.maxVehiclesPerAccount = 2});

  final int maxVehiclesPerAccount;

  bool canAdd(int activeVehicleCount) =>
      activeVehicleCount < maxVehiclesPerAccount;
}
