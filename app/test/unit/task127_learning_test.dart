import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/data/models/vehicle_learning_status.dart';
import 'package:vinfast_battery/data/services/dashboard_reader.dart';
import 'package:vinfast_battery/data/services/trip_csv_import.dart';
import 'package:vinfast_battery/data/services/trip_energy_model.dart';
import 'package:vinfast_battery/features/ai/services/learning_flow.dart';

Map<String, dynamic> _status({bool chargeReady = true, int trained = 2}) => {
  'vehicleId': 'car',
  'consentEnabled': true,
  'charge': {
    'pending': 3,
    'required': 3,
    'ready': chargeReady,
    'trained': trained,
    'mae': 0.6,
    'whPerPct': 26.15,
    'powerW': 437,
    'report': {
      'decision': 'promoted',
      'mode': 'finetune',
      'used': 5,
      'beforeMae': 1.2,
      'afterMae': 0.6,
    },
  },
  'trip': {
    'pending': 4,
    'required': 10,
    'ready': false,
    'trained': 77,
    'kmPerPct': 1.212,
    'sources': {'csv': 77, 'trip': 2, 'odo_segment': 2},
    'model': {
      'refPctPerKm': 0.72743,
      'speed': 0.012417,
      'speed2': 0.0018093,
      'loadPer10Kg': 0.03108,
      'rain': 0.05583,
      'source': 'model',
      'samples': 77,
      'spread': 0.186,
      'mae': 0.69,
    },
  },
};

void main() {
  group('dashboard photo parser', () {
    test('reads % and a labelled ODO', () {
      final r = DashboardReadingParser.parse(
        '12:45\n85%\nODO 01234 km\n0 km/h',
      );
      expect(r.soc, 85);
      expect(r.odoKm, 1234);
      expect(r.odoFromLabel, isTrue);
    });

    test('seven-segment confusions next to digits', () {
      // "0D0" label, "O" for zero and "S" for five inside numbers.
      final r = DashboardReadingParser.parse('6S%\n0D0 12O45');
      expect(r.soc, 65);
      expect(r.odoKm, 12045);
    });

    test('ignores speed, trip and clock values', () {
      final r = DashboardReadingParser.parse(
        'TRIP 12.3 km\n35 km/h\n09:30\n4821 km\n72 %',
      );
      expect(r.soc, 72);
      expect(r.odoKm, 4821);
    });

    test('thousands separator and one decimal', () {
      expect(DashboardReadingParser.parse('ODO 1.234').odoKm, 1234);
      expect(DashboardReadingParser.parse('ODO 1234.5').odoKm, 1234.5);
    });

    test('nothing readable stays empty (never invented)', () {
      final r = DashboardReadingParser.parse('VINFAST\nREADY');
      expect(r.isEmpty, isTrue);
      expect(DashboardReadingParser.parse('150%').soc, isNull);
    });
  });

  group('trip CSV import', () {
    test("the owner's logger export parses every ride", () {
      final bytes = File(
        '../web/tests/fixtures/owner_rides_sample.csv',
      ).readAsBytesSync();
      final parsed = TripCsvImport.parse(bytes);
      expect(parsed.error, isNull);
      expect(parsed.rows, hasLength(77));
      final first = parsed.rows.first;
      expect(first['clientId'], startsWith('2026-04-10T033921'));
      expect(first['distance_km'], '10.53553698');
      expect(first['soc_delta'], '13');
      expect(first.containsKey('max_acceleration'), isFalse);
    });

    test('a file without the needed columns is refused', () {
      final parsed = TripCsvImport.parse('name,value\na,1\n'.codeUnits);
      expect(parsed.rows, isEmpty);
      expect(parsed.error, contains('distance_km'));
    });

    test('quoted cells', () {
      final parsed = TripCsvImport.parse(
        'trip_id,distance_km,soc_delta,weather_condition\n"a,1",5.5,4,"Rain"\n'
            .codeUnits,
      );
      expect(parsed.rows.single['clientId'], 'a,1');
      expect(parsed.rows.single['weather_condition'], 'Rain');
    });
  });

  group('learning status', () {
    test('parses both models and the trained trip model', () {
      final status = VehicleLearningStatus.fromJson(_status())!;
      expect(status.charge.ready, isTrue);
      expect(status.charge.report!.summary, contains('±1.2% → ±0.6%'));
      expect(status.trip.progress, closeTo(0.4, 1e-9));
      final params = status.tripParams!;
      expect(params.source, TripKmSource.model);
      expect(params.samples, 77);
      expect(params.kmPerPct, closeTo(1.2125, 1e-3));
    });

    test('an ODO prior keeps its source', () {
      final raw = _status();
      (raw['trip'] as Map)['model'] = {'refPctPerKm': 0.9, 'source': 'odo'};
      expect(
        VehicleLearningStatus.fromJson(raw)!.tripParams!.source,
        TripKmSource.personal,
      );
    });

    test('readiness is announced once per training cycle', () async {
      SharedPreferences.setMockInitialValues({});
      final status = VehicleLearningStatus.fromJson(_status())!;
      expect(await TrainingReadiness.newlyReady(status), ['charge']);
      expect(await TrainingReadiness.newlyReady(status), isEmpty);
      // After a training the trained count moves: a new cycle.
      final next = VehicleLearningStatus.fromJson(_status(trained: 5))!;
      expect(await TrainingReadiness.newlyReady(next), ['charge']);
      final notReady = VehicleLearningStatus.fromJson(
        _status(chargeReady: false, trained: 9),
      )!;
      expect(await TrainingReadiness.newlyReady(notReady), isEmpty);
    });
  });
}
