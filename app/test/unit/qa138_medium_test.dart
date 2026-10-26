import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/data/models/vehicle_learning_status.dart';
import 'package:vinfast_battery/data/services/trip_route_service.dart';
import 'package:vinfast_battery/features/ai/services/learning_flow.dart';

/// QA 138 (review 26/10/2026), Medium findings on the app side.
/// QA-07: no "train now" nudge for a plan that cannot train.
/// QA-11: the trip planner asks the Pinova API, never OSM directly.
Map<String, dynamic> _status({Object? trainAllowed}) => {
  'vehicleId': 'car',
  'consentEnabled': true,
  'trainAllowed': ?trainAllowed,
  'charge': {'pending': 3, 'required': 3, 'ready': true, 'trained': 2},
  'trip': {'pending': 0, 'required': 10, 'ready': false, 'trained': 0},
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('QA-07', () {
    test('an older server without the flag keeps the nudge', () {
      expect(VehicleLearningStatus.fromJson(_status())!.trainAllowed, isTrue);
      expect(
        VehicleLearningStatus.fromJson(_status(trainAllowed: false))!.trainAllowed,
        isFalse,
      );
    });

    test('a plan that cannot train gets no nudge', () async {
      final free = VehicleLearningStatus.fromJson(_status(trainAllowed: false));
      expect(await TrainingReadiness.check(free), isEmpty);
      // Nothing was marked as announced either: it still nudges after an
      // upgrade.
      expect(await TrainingReadiness.newlyReady(free!), ['charge']);
    });
  });

  group('QA-11', () {
    final calls = <String>[];
    setUp(() {
      calls.clear();
      TripRouteService.getJson = (endpoint) async {
        calls.add('GET $endpoint');
        return {
          'success': true,
          'data': {
            'items': [
              {'name': 'Hồ Gươm, Hà Nội', 'lat': 21.03, 'lon': 105.85},
              {'name': 'bad row'},
            ],
          },
        };
      };
      TripRouteService.postJson = (endpoint, body) async {
        calls.add('POST $endpoint ${body['from']} ${body['to']}');
        return {
          'success': true,
          'data': {
            'items': [
              {
                'km': 12.5,
                'minutes': 31.0,
                'geometry': [
                  [21.03, 105.85],
                  [21.0, 105.8],
                ],
              },
              {'km': 11.0, 'minutes': 40.0},
            ],
          },
        };
      };
    });

    test('places come from /api/trip/places', () async {
      final places = await TripRouteService.searchPlaces('Hồ Gươm');
      expect(calls.single, 'GET /api/trip/places?q=H%E1%BB%93+G%C6%B0%C6%A1m');
      expect(places.single.name, 'Hồ Gươm, Hà Nội');
      expect(places.single.point, const LatLng(21.03, 105.85));
      expect(await TripRouteService.searchPlaces('Hồ'), isEmpty);
      expect(calls, hasLength(1), reason: 'too short: no request');
    });

    test('routes come from /api/trip/routes with the road shape', () async {
      final routes = await TripRouteService.routes(
        const LatLng(21.03, 105.85),
        const LatLng(21.0, 105.8),
      );
      expect(calls.single, startsWith('POST /api/trip/routes'));
      expect(routes.first.distanceKm, 12.5);
      expect(routes.first.geometry, hasLength(2));
      expect(routes[1].geometry, isEmpty);
    });

    test('a refusal (Pro) or an outage is an error for the screen', () async {
      TripRouteService.postJson = (endpoint, body) async => {
        'success': false,
        'code': 'premiumRequired',
      };
      await expectLater(
        TripRouteService.routes(const LatLng(1, 1), const LatLng(2, 2)),
        throwsA(
          isA<TripRouteException>().having((e) => e.code, 'code', 'premiumRequired'),
        ),
      );
    });
  });
}
