class VehicleChargerBinding {
  const VehicleChargerBinding({
    required this.vehicleId,
    required this.deviceId,
    this.shared = false,
    this.active = true,
  });

  final String vehicleId;
  final String deviceId;
  final bool shared;
  final bool active;

  factory VehicleChargerBinding.fromMap(Map<String, dynamic> map) =>
      VehicleChargerBinding(
        vehicleId: '${map['vehicleId'] ?? ''}',
        deviceId: '${map['deviceId'] ?? ''}',
        shared: map['shared'] == true,
        active: map['active'] != false,
      );

  Map<String, dynamic> toMap() => {
    'vehicleId': vehicleId,
    'deviceId': deviceId,
    'shared': shared,
    'active': active,
  };
}
