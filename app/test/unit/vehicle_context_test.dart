import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/models/vehicle_context.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';

void main() {
  test('context exposes selected vehicle identity and telemetry summary', () {
    final vehicle = VehicleModel(
      vehicleId: 'vehicle-a',
      vehicleName: 'Feliz A',
      currentOdo: 12000,
      currentBattery: 68,
      stateOfHealth: 94.5,
    );
    final context = VehicleContext(vehicleId: vehicle.vehicleId, vehicle: vehicle);

    expect(context.hasVehicle, isTrue);
    expect(context.displayName, 'Feliz A');
    expect(context.batteryPercent, 68);
    expect(context.stateOfHealth, 94.5);
  });

  test('empty context never invents a vehicle', () {
    const context = VehicleContext(vehicleId: '');
    expect(context.hasVehicle, isFalse);
    expect(context.displayName, 'Chưa chọn xe');
    expect(context.batteryPercent, 0);
  });
}
