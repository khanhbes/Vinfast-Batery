import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charge_cost.dart';

/// QA 130: the charge target lived only on each phone (85 % on the OnePlus,
/// 100 % on the Xiaomi); it is now part of the account's preferences.
void main() {
  test('targets survive the cache round trip, per vehicle', () {
    final value = SmartChargePreferences(
      ownerUid: 'u1',
      updatedAt: DateTime.utc(2026, 10, 18),
      targetSocByVehicle: const {'car': 85, 'evo': 90},
    );
    final back = SmartChargePreferences.fromJson(value.toJson());
    expect(back.targetSocByVehicle, {'car': 85.0, 'evo': 90.0});
  });

  test('invalid stored targets are ignored', () {
    expect(
      SmartChargePreferences.targetsFrom({
        'car': 85,
        'bad': 0,
        'high': 140,
        'text': 'x',
      }),
      {'car': 85.0},
    );
    expect(SmartChargePreferences.targetsFrom(null), isEmpty);
  });

  test('copyWith keeps or replaces the targets', () {
    final base = SmartChargePreferences(
      updatedAt: DateTime.utc(2026),
      targetSocByVehicle: const {'car': 85},
    );
    expect(base.copyWith(tariffVndPerKwh: 2800).targetSocByVehicle, {
      'car': 85.0,
    });
    expect(
      base.copyWith(targetSocByVehicle: const {'car': 90}).targetSocByVehicle,
      {'car': 90.0},
    );
  });
}
