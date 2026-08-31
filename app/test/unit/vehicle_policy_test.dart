import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/vehicle_policy.dart';

void main() {
  test('vehicle policy defaults to two active vehicles', () {
    const policy = VehiclePolicy();
    expect(policy.maxVehiclesPerAccount, 2);
    expect(policy.canAdd(0), isTrue);
    expect(policy.canAdd(1), isTrue);
    expect(policy.canAdd(2), isFalse);
  });

  test('custom policy remains configurable', () {
    const policy = VehiclePolicy(maxVehiclesPerAccount: 3);
    expect(policy.canAdd(2), isTrue);
    expect(policy.canAdd(3), isFalse);
  });
}
