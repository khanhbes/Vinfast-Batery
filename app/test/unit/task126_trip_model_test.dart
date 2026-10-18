import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/trip_energy_model.dart';

/// Task 126: the app and BatteryBot must agree. Both suites read
/// web/tests/fixtures/trip_model_vectors.json.
Map<String, dynamic> _vectors() =>
    jsonDecode(
          File(
            '../web/tests/fixtures/trip_model_vectors.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

double _r1(double value) => (value * 10).roundToDouble() / 10;

TripConditions _conditions(Map<String, dynamic> raw) => TripConditions(
  speed: TripSpeed.values.byName(raw['speed'] as String? ?? 'normal'),
  riders: (raw['riders'] as num?)?.toInt() ?? 1,
  cargoKg: (raw['cargo_kg'] as num?)?.toDouble() ?? 0,
  weather: TripWeather.values.byName(raw['weather'] as String? ?? 'dry'),
  hilly: raw['hilly'] == true,
  roundTrip: raw['round_trip'] == true,
);

void main() {
  final vectors = _vectors();

  for (final raw in vectors['plans'] as List) {
    final vector = Map<String, dynamic>.from(raw as Map);
    test('plan: ${vector['name']}', () {
      final input = Map<String, dynamic>.from(vector['input'] as Map);
      final expected = Map<String, dynamic>.from(vector['expect'] as Map);
      final plan = TripEnergyModel.plan(
        distanceKm: (input['distance_km'] as num).toDouble(),
        currentSoc: (input['current_soc'] as num).toDouble(),
        kmPerPct: (input['km_per_pct'] as num?)?.toDouble(),
        source: input['km_per_pct_source'] == 'personal'
            ? TripKmSource.personal
            : TripKmSource.catalog,
        model: TripModelParams.fromJson(input['model']),
        conditions: _conditions(
          Map<String, dynamic>.from(input['conditions'] as Map),
        ),
        durationMin: (input['duration_min'] as num?)?.toDouble(),
        alternativeKm: [
          for (final km in (input['alternative_km'] as List?) ?? const [])
            (km as num).toDouble(),
        ],
      );
      expect(_r1(plan.usePct), expected['usePct']);
      expect(_r1(plan.useLowPct), expected['useLowPct']);
      expect(_r1(plan.useHighPct), expected['useHighPct']);
      expect(_r1(plan.arrivalSoc), expected['arrivalSoc']);
      expect(plan.verdict.name, expected['verdict']);
      expect(_r1(plan.startNeededSoc), expected['startNeededSoc']);
      expect(plan.source.wire, expected['kmPerPctSource']);
      expect(
        (plan.factor * 1000).roundToDouble() / 1000,
        expected['factor'],
      );
      expect(_r1(plan.avgSpeedKmh), expected['avgSpeedKmh']);
      final suggestions = [
        for (final item in expected['suggestions'] as List)
          Map<String, dynamic>.from(item as Map),
      ];
      expect(plan.suggestions.map((s) => s.wire).toList(), [
        for (final s in suggestions) s['kind'],
      ]);
      for (var i = 0; i < suggestions.length; i++) {
        final want = suggestions[i];
        final got = plan.suggestions[i];
        if (want['targetSoc'] != null) {
          expect(got.targetSoc, (want['targetSoc'] as num).toDouble());
        }
        if (want['stops'] != null) expect(got.stops, want['stops']);
        if (want['savedPct'] != null) {
          expect(got.savedPct, (want['savedPct'] as num).toDouble());
        }
        if (want['distanceKm'] != null) {
          expect(got.distanceKm, (want['distanceKm'] as num).toDouble());
        }
      }
    });
  }

  test('km per 1 % learned from ODO + confirmed % pairs', () {
    final learning = Map<String, dynamic>.from(vectors['learning'] as Map);
    final readings = [
      for (final raw in learning['sessions'] as List)
        TripChargeReading(
          endedAt: DateTime.parse((raw as Map)['endedAt'] as String),
          startSoc: (raw['startSoc'] as num).toDouble(),
          actualEndSoc: (raw['actualEndSoc'] as num).toDouble(),
          odoKm: (raw['odoKm'] as num).toDouble(),
        ),
    ];
    final result = TripEnergyModel.learnKmPerPct(
      readings,
      catalog: (learning['catalog'] as num).toDouble(),
    );
    expect(result.pairs, learning['pairs']);
    expect(
      result.kmPerPct,
      closeTo((learning['kmPerPct'] as num).toDouble(), 1e-4),
    );
  });
}
