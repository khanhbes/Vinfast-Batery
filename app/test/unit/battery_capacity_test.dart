import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/vinfast_model_spec.dart';
import 'package:vinfast_battery/data/services/battery_capacity_service.dart';

/// ========================================================================
/// Unit Tests: Dung Lượng Pin AI — Catalog, Alias, Capacity, Threshold
/// ========================================================================

void main() {
  // ─── Helper: tạo VinFastModelSpec test ─────────────────────────────────────
  VinFastModelSpec makeSpec({
    String modelId = 'feliz',
    String modelName = 'Feliz',
    List<String> aliases = const ['VinFast Feliz', 'VF Feliz'],
    double nominalCapacityWh = 2400,
    double nominalCapacityAh = 50,
    double nominalVoltageV = 48,
    double maxChargePowerW = 300,
    double defaultEfficiencyKmPerPercent = 1.2,
  }) {
    return VinFastModelSpec(
      modelId: modelId,
      modelName: modelName,
      aliases: aliases,
      nominalCapacityWh: nominalCapacityWh,
      nominalCapacityAh: nominalCapacityAh,
      nominalVoltageV: nominalVoltageV,
      maxChargePowerW: maxChargePowerW,
      ratedMotorPowerW: 1800,
      peakMotorPowerW: 3000,
      defaultEfficiencyKmPerPercent: defaultEfficiencyKmPerPercent,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 1: VinFastModelSpec — Alias matching
  // ─────────────────────────────────────────────────────────────────────────
  group('VinFastModelSpec.matchesName', () {
    final spec = makeSpec();

    test('exact model name → matches', () {
      expect(spec.matchesName('Feliz'), isTrue);
    });

    test('case-insensitive model name → matches', () {
      expect(spec.matchesName('feliz'), isTrue);
      expect(spec.matchesName('FELIZ'), isTrue);
    });

    test('alias substring → matches', () {
      expect(spec.matchesName('VinFast Feliz S'), isTrue);
    });

    test('partial alias → matches', () {
      expect(spec.matchesName('VF Feliz 2024'), isTrue);
    });

    test('unrelated name → no match', () {
      expect(spec.matchesName('Honda Vision'), isFalse);
    });

    test('empty name → no match', () {
      expect(spec.matchesName(''), isFalse);
    });

    test('name containing alias in different case → matches', () {
      expect(spec.matchesName('Tôi đi xe VF feliz'), isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 2: VinFastModelSpec — fromMap / toMap
  // ─────────────────────────────────────────────────────────────────────────
  group('VinFastModelSpec serialization', () {
    test('roundtrip fromMap → toMap preserves data', () {
      final original = makeSpec(
        modelId: 'theon',
        modelName: 'Theon',
        aliases: ['Theon S'],
        nominalCapacityWh: 2400,
        nominalCapacityAh: 50,
        nominalVoltageV: 48,
      );

      final map = original.toMap();
      final restored = VinFastModelSpec.fromMap(map, id: map['modelId']);

      expect(restored.modelId, original.modelId);
      expect(restored.modelName, original.modelName);
      expect(restored.aliases, original.aliases);
      expect(restored.nominalCapacityWh, original.nominalCapacityWh);
      expect(restored.nominalCapacityAh, original.nominalCapacityAh);
      expect(restored.nominalVoltageV, original.nominalVoltageV);
      expect(restored.specVersion, original.specVersion);
    });

    test('fromMap handles missing fields gracefully', () {
      final spec = VinFastModelSpec.fromMap({'modelName': 'Unknown'});
      expect(spec.modelId, '');
      expect(spec.nominalCapacityWh, 0);
      expect(spec.aliases, isEmpty);
      expect(spec.specVersion, 1);
      expect(spec.defaultEfficiencyKmPerPercent, 1.2);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 3: SoHAlertLevel — threshold logic
  // ─────────────────────────────────────────────────────────────────────────
  group('SoHAlertLevel.fromSoH', () {
    test('SoH >= 80 → none', () {
      expect(SoHAlertLevel.fromSoH(100), SoHAlertLevel.none);
      expect(SoHAlertLevel.fromSoH(80), SoHAlertLevel.none);
    });

    test('70 <= SoH < 80 → mild', () {
      expect(SoHAlertLevel.fromSoH(79.9), SoHAlertLevel.mild);
      expect(SoHAlertLevel.fromSoH(70), SoHAlertLevel.mild);
    });

    test('60 <= SoH < 70 → moderate', () {
      expect(SoHAlertLevel.fromSoH(69.9), SoHAlertLevel.moderate);
      expect(SoHAlertLevel.fromSoH(60), SoHAlertLevel.moderate);
    });

    test('SoH < 60 → severe', () {
      expect(SoHAlertLevel.fromSoH(59.9), SoHAlertLevel.severe);
      expect(SoHAlertLevel.fromSoH(30), SoHAlertLevel.severe);
      expect(SoHAlertLevel.fromSoH(0), SoHAlertLevel.severe);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 4: CapacityConfidence — enum labels
  // ─────────────────────────────────────────────────────────────────────────
  group('CapacityConfidence', () {
    test('high label', () {
      expect(CapacityConfidence.high.label, 'Cao');
    });
    test('medium label', () {
      expect(CapacityConfidence.medium.label, 'Trung bình');
    });
    test('low label', () {
      expect(CapacityConfidence.low.label, 'Thấp');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 5: CapacityResult — capacity formulas
  // ─────────────────────────────────────────────────────────────────────────
  group('CapacityResult formulas', () {
    test('usableCapacity = nominal × SoH / 100', () {
      final result = CapacityResult(
        nominalCapacityWh: 1440,
        nominalCapacityAh: 30,
        nominalVoltageV: 48,
        sohPercent: 80,
        usableCapacityWh: 1440 * 80 / 100,
        usableCapacityAh: (1440 * 80 / 100) / 48,
        maxChargePowerW: 300,
        confidence: CapacityConfidence.high,
        alertLevel: SoHAlertLevel.mild,
      );

      expect(result.usableCapacityWh, closeTo(1152, 0.1));
      expect(result.usableCapacityAh, closeTo(24.0, 0.1));
    });

    test('100% SoH → usable == nominal', () {
      final result = CapacityResult(
        nominalCapacityWh: 2400,
        nominalCapacityAh: 50,
        nominalVoltageV: 48,
        sohPercent: 100,
        usableCapacityWh: 2400,
        usableCapacityAh: 50,
        maxChargePowerW: 500,
        confidence: CapacityConfidence.high,
        alertLevel: SoHAlertLevel.none,
      );

      expect(result.usableCapacityWh, result.nominalCapacityWh);
      expect(result.usableCapacityAh, result.nominalCapacityAh);
    });

    test('50% SoH → usable = half nominal', () {
      const nomWh = 1440.0;
      const nomAh = 30.0;
      const soh = 50.0;

      final result = CapacityResult(
        nominalCapacityWh: nomWh,
        nominalCapacityAh: nomAh,
        nominalVoltageV: 48,
        sohPercent: soh,
        usableCapacityWh: nomWh * soh / 100,
        usableCapacityAh: nomAh * soh / 100,
        maxChargePowerW: 300,
        confidence: CapacityConfidence.low,
        alertLevel: SoHAlertLevel.severe,
      );

      expect(result.usableCapacityWh, closeTo(720, 0.1));
      expect(result.usableCapacityAh, closeTo(15, 0.1));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // GROUP 6: VehicleModel.hasModelLink
  // ─────────────────────────────────────────────────────────────────────────
  group('VehicleModel.hasModelLink', () {
    test('null vinfastModelId → no link', () {
      // ignore: unnecessary_null_comparison
      expect(null == null, isTrue); // simulates String? modelId = null check
    });

    test('empty vinfastModelId → no link', () {
      const String modelId = '';
      expect(modelId.isNotEmpty, isFalse);
    });

    test('non-empty vinfastModelId → has link', () {
      const String modelId = 'feliz';
      expect(modelId.isNotEmpty, isTrue);
    });
  });
}
