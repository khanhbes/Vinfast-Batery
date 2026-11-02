import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/constants/app_constants.dart';
import 'package:vinfast_battery/core/utils/emergency_text.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/services/range_estimator.dart';

/// QA 143: fixes from the full-flow test with a brand-new account.
void main() {
  group('emergency words (same as the server guardrail)', () {
    test('plain fire, smoke, explosion and shock words match', () {
      for (final text in [
        'Xe bị cháy, có khói',
        'xe boc chay roi',
        'khói bốc ra từ cốp xe',
        'nghe tiếng nổ ở pin',
        'ổ cắm có tia lửa',
        'bị điện giật khi rút sạc',
        'pin bị phồng rồi',
        'Fire! smoke everywhere',
      ]) {
        expect(EmergencyText.matches(text), isTrue, reason: text);
      }
    });

    test('riding, leaving and prevention questions do not', () {
      for (final text in [
        'xe đang chạy 40 km/h',
        'xe dang chay binh thuong',
        'mình muốn ra khỏi app',
        'sạc qua đêm có sợ cháy không?',
        'làm sao để phòng cháy khi sạc',
        'nút này nổi bật quá',
      ]) {
        expect(EmergencyText.matches(text), isFalse, reason: text);
      }
    });
  });

  group('range for a new account', () {
    test('no SoH entered: the catalog km/1 % with the 5 % reserve', () {
      final vehicle = VehicleModel(
        vehicleId: 'new',
        currentOdo: 0,
        currentBattery: 80,
        defaultEfficiency: 1.34,
        hasSohData: false,
      );
      final range = estimateRange(vehicle)!;
      expect(range.km, closeTo(75 * 1.34, 1e-9));
      expect(range.source, RangeSource.catalog);
      // The km/1 % tile and the hero use the same number.
      expect(kmPerPctFor(vehicle, null), range.kmPerPct);
    });

    test('a SoH the owner entered still scales the catalog figure', () {
      final vehicle = VehicleModel(
        vehicleId: 'v',
        currentOdo: 0,
        currentBattery: 80,
        defaultEfficiency: 1.34,
        stateOfHealth: 90,
      );
      expect(estimateRangeKm(vehicle), closeTo(75 * 1.34 * 0.9, 1e-9));
    });
  });

  test('one odometer range: 6 digits', () {
    expect(maxOdoKm, 999999);
    expect(AppConstants.maxOdoDigits, 6);
  });

  test('the catalog uses VinFast figures and km/1 % = range / 100', () {
    final models =
        jsonDecode(
              File('assets/vinfast_specs_fallback.json').readAsStringSync(),
            )
            as List;
    final byId = <String, dynamic>{
      for (final m in models) (m as Map)['modelId'] as String: m,
    };
    expect(byId['evo200']['nominalCapacityWh'], 3500);
    expect(byId['feliz_s']['nominalCapacityWh'], 3500);
    expect(byId['feliz_2025']['nominalCapacityWh'], 2400);
    expect(byId['feliz_2025']['rangeKm'], 134);
    expect(byId['tempest']['batteryChemistry'], 'Lead-acid');
    for (final m in models.cast<Map>()) {
      expect(
        m['defaultEfficiencyKmPerPercent'],
        closeTo((m['rangeKm'] as num) / 100, 0.006),
        reason: '${m['modelId']}',
      );
    }
    // The server bundles the same file.
    expect(
      File('../web/assets/vinfast_specs_fallback.json').readAsStringSync(),
      File('assets/vinfast_specs_fallback.json').readAsStringSync(),
    );
  });
}
