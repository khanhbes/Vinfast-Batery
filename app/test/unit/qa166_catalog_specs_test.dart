import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/utils/number_text.dart';
import 'package:vinfast_battery/data/models/vinfast_model_spec.dart';
import 'package:vinfast_battery/features/settings/catalog_spec_rows.dart';

/// QA 166 (owner's choice, 18/11/2026): the vehicle details show only what
/// VinFast publishes. For the Feliz 2025 that is 2.4 kWh LFP, a 400 W charger
/// and about 6 h 30 min from 0 to 100 %; no voltage, Ah or cell count (the
/// old 48 V / 50 Ah had no source). The wall power the estimates fall back to
/// (450 W, measured on the owner's charger) is not listed as a published spec.
VinFastModelSpec _bundledFeliz() {
  final list =
      jsonDecode(File('assets/vinfast_specs_fallback.json').readAsStringSync())
          as List;
  final data = list.cast<Map>().firstWhere((m) => m['modelId'] == 'feliz_2025');
  return VinFastModelSpec.fromMap(Map<String, dynamic>.from(data));
}

void main() {
  test('the bundled Feliz 2025 holds only what VinFast publishes', () {
    final spec = _bundledFeliz();
    expect(spec.nominalCapacityWh, 2400);
    expect(spec.nominalVoltageV, 0);
    expect(spec.nominalCapacityAh, 0);
    expect(spec.maxDcChargePowerW, 400);
    expect(spec.chargeTimeMinutes, 390);
    expect(spec.maxChargePowerW, 450);
  });

  test('the catalog rows say what is not published and list the charger', () {
    final rows = {
      for (final (label, value) in catalogSpecRows(_bundledFeliz()))
        label: value,
    };
    expect(rows['Dung lượng (Wh)'], groupThousands(2400));
    expect(rows['Dung lượng (Ah)'], VinFastModelSpec.unpublished);
    expect(rows['Điện áp (V)'], VinFastModelSpec.unpublished);
    expect(rows['Bộ sạc theo xe'], '400 W');
    expect(rows['Sạc đầy (0–100%)'], 'khoảng 6 giờ 30 phút');
    expect(rows.containsKey('Sạc tối đa (W)'), isFalse);
    expect(rows['Nguồn dữ liệu'], 'Số liệu VinFast công bố');
    // A model whose maker publishes its voltage keeps it; nothing is
    // invented for a charger nobody published.
    final published = VinFastModelSpec.fromMap({
      'modelId': 'evo_200',
      'modelName': 'VinFast Evo200',
      'nominalCapacityWh': 3500,
      'nominalCapacityAh': 73,
      'nominalVoltageV': 48,
      'maxChargePowerW': 600,
    });
    final other = {
      for (final (label, value) in catalogSpecRows(published)) label: value,
    };
    expect(other['Điện áp (V)'], '48');
    expect(other['Dung lượng (Ah)'], '73');
    expect(other.containsKey('Bộ sạc theo xe'), isFalse);
    expect(other.containsKey('Sạc đầy (0–100%)'), isFalse);
  });

  test('the charger and the time come from the catalog, the legacy '
      'projection and the phone cache alike', () {
    final catalog = VinFastModelSpec.fromMap({
      'catalogId': 'feliz_2025',
      'localized': {
        'vi': {'displayName': 'VinFast Feliz 2025'},
      },
      'battery': {'calculationCapacityWh': 2400, 'chemistry': 'LFP'},
      'charging': {'maxDcPowerW': 400, 'chargeTimeMinutes': 390},
      'appDefaults': {
        'calculationCapacityWh': 2400,
        'maxSafeChargePowerW': 450,
        'defaultEfficiencyKmPerPercent': 1.34,
      },
    });
    expect(catalog.maxDcChargePowerW, 400);
    expect(catalog.chargeTimeMinutes, 390);
    expect(catalog.nominalVoltageV, 0);
    final legacy = VinFastModelSpec.fromMap({
      'modelId': 'feliz_2025',
      'modelName': 'VinFast Feliz 2025',
      'nominalCapacityWh': 2400,
      'chargerOutputW': 400,
      'chargeTimeMinutes': 390,
    });
    expect(legacy.maxDcChargePowerW, 400);
    expect(legacy.chargeTimeMinutes, 390);
    final cached = VinFastModelSpec.fromMap(catalog.toMap());
    expect(cached.maxDcChargePowerW, 400);
    expect(cached.chargeTimeMinutes, 390);
  });
}
