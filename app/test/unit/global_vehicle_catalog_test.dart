import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/models/resolved_vehicle_context.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/models/vinfast_model_spec.dart';

Map<String, dynamic> catalogMap({int revision = 2}) => {
  'catalogId': 'vinfast-evo200-2024-vn',
  'brandId': 'vinfast',
  'brandName': 'VinFast',
  'model': 'Evo',
  'variant': 'Evo200',
  'modelYear': 2024,
  'market': 'VN',
  'vehicleType': 'scooter',
  'selectable': true,
  'revision': revision,
  'localized': {
    'vi': {'displayName': 'VinFast Evo200', 'tagline': 'Đi phố mỗi ngày'},
    'en': {'displayName': 'VinFast Evo200', 'tagline': 'Everyday mobility'},
  },
  'battery': {
    'calculationCapacityWh': 1872,
    'usableCapacityWh': 1750,
    'voltageV': 48,
    'capacityAh': 39,
    'chemistry': 'LFP',
  },
  'charging': {'maxAcPowerW': 480, 'maxDcPowerW': 0},
  'performance': {
    'ratedMotorPowerW': 1500,
    'peakMotorPowerW': 3000,
    'rangeKm': 203,
    'rangeTestCycle': 'Manufacturer published',
  },
  'appDefaults': {
    'calculationCapacityWh': 1872,
    'defaultEfficiencyKmPerPercent': 1.2,
    'maxSafeChargePowerW': 480,
  },
  'media': {'thumbnailUrl': 'https://example.test/evo.webp'},
  'sources': [
    {'url': 'https://vinfastauto.com/spec', 'publisher': 'VinFast'},
  ],
};

void main() {
  test('parses reviewed global catalog while preserving legacy interface', () {
    final spec = VinFastModelSpec.fromMap(catalogMap());
    expect(spec.modelId, 'vinfast-evo200-2024-vn');
    expect(spec.modelName, 'VinFast Evo200');
    expect(spec.brandName, 'VinFast');
    expect(spec.nominalCapacityWh, 1872);
    expect(spec.defaultEfficiencyKmPerPercent, 1.2);
    expect(spec.batteryChemistry, 'LFP');
    expect(spec.imageUrl, 'https://example.test/evo.webp');
    expect(spec.specVersion, 2);
    expect(spec.sources, hasLength(1));
  });

  test(
    'resolved context updates catalog values and preserves personal state',
    () {
      final vehicle = VehicleModel(
        vehicleId: 'vehicle-1',
        vehicleName: 'Old catalog name',
        nickname: 'Xe đi làm',
        catalogId: 'vinfast-evo200-2024-vn',
        catalogRevisionAtSelection: 1,
        currentOdo: 1200,
        currentBattery: 63,
        stateOfHealth: 94,
        batteryCapacityWh: 1440,
        defaultEfficiency: 1,
      );
      final resolved = ResolvedVehicleContext(
        vehicle: vehicle,
        catalog: VinFastModelSpec.fromMap(catalogMap(revision: 3)),
      );
      expect(vehicle.effectiveCatalogId, 'vinfast-evo200-2024-vn');
      expect(vehicle.hasModelLink, isTrue);
      expect(resolved.displayName, 'Xe đi làm');
      expect(resolved.batteryCapacityWh, 1872);
      expect(resolved.defaultEfficiency, 1.2);
      expect(resolved.hasCatalogUpdate, isTrue);
      expect(resolved.vehicle.currentOdo, 1200);
      expect(resolved.vehicle.currentBattery, 63);
      expect(resolved.vehicle.stateOfHealth, 94);
    },
  );

  test('legacy VinFast catalog remains readable during migration', () {
    final spec = VinFastModelSpec.fromMap({
      'modelId': 'evo200',
      'modelName': 'VinFast Evo200',
      'nominalCapacityWh': 1872,
      'nominalCapacityAh': 39,
      'nominalVoltageV': 48,
      'maxChargePowerW': 480,
      'ratedMotorPowerW': 1500,
      'peakMotorPowerW': 3000,
      'defaultEfficiencyKmPerPercent': 1.2,
      'specVersion': 2,
    });
    expect(spec.brandName, 'VinFast');
    expect(spec.selectable, isTrue);
    expect(spec.nominalCapacityWh, 1872);
  });
}
