import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/trip_log_model.dart';
import 'package:vinfast_battery/data/services/route_prediction_service.dart';

/// ========================================================================
/// Unit Tests: RoutePredictionService — Dự báo tiêu hao pin lộ trình
/// ========================================================================

/// Helper: tạo TripLogModel nhanh cho test
TripLogModel _makeTrip({
  required double distance,
  required int batteryConsumed,
  PayloadType payload = PayloadType.onePerson,
}) {
  final efficiency = batteryConsumed > 0 ? distance / batteryConsumed : 0.0;
  final now = DateTime(2026, 4, 1, 10, 0);
  return TripLogModel(
    vehicleId: 'test_v',
    startTime: now,
    endTime: now.add(const Duration(hours: 1)),
    distance: distance,
    payloadType: payload,
    startBattery: 80,
    endBattery: 80 - batteryConsumed,
    batteryConsumed: batteryConsumed,
    efficiency: efficiency,
    startOdo: 5000,
    endOdo: 5000 + distance.toInt(),
  );
}

void main() {
  group('RoutePredictionService.predict', () {
    test('1 person, enough battery', () {
      final trips = [
        _makeTrip(distance: 12, batteryConsumed: 10, payload: PayloadType.onePerson),
        _makeTrip(distance: 10, batteryConsumed: 8, payload: PayloadType.onePerson),
      ];
      // Avg efficiency for onePerson: (1.2 + 1.25) / 2 = 1.225
      // With 80% battery, 10km trip:
      //   baseDrain = 10 / 1.225 = 8.16
      //   drain (x1.0) = 9 (ceil)
      //   remaining = 80 - 9 = 71 → enough (>= 5)
      final result = RoutePredictionService.predict(
        distanceKm: 10,
        currentBattery: 80,
        payload: PayloadType.onePerson,
        trips: trips,
      );
      expect(result.isEnough, isTrue);
      expect(result.remainingBattery, greaterThanOrEqualTo(5));
      expect(result.estimatedBatteryDrain, greaterThan(0));
      expect(result.payload, PayloadType.onePerson);
      expect(result.distanceKm, 10);
    });

    test('2 person, enough battery', () {
      final trips = [
        _makeTrip(distance: 10, batteryConsumed: 13, payload: PayloadType.twoPerson),
      ];
      // Efficiency for twoPerson matching trip: 10/13 ≈ 0.769
      // drain = 10 / 0.769 * 1.3 (factor) = ceil(16.9) = 17
      // remaining = 80 - 17 = 63 → enough
      final result = RoutePredictionService.predict(
        distanceKm: 10,
        currentBattery: 80,
        payload: PayloadType.twoPerson,
        trips: trips,
      );
      expect(result.isEnough, isTrue);
      expect(result.payload, PayloadType.twoPerson);
    });

    test('not enough battery → isEnough=false', () {
      final trips = [
        _makeTrip(distance: 12, batteryConsumed: 10, payload: PayloadType.onePerson),
      ];
      // efficiency = 1.2 km/1%
      // 50km → drain = ceil(50/1.2 * 1.0) = ceil(41.67) = 42
      // remaining = 20 - 42 = -22 → NOT enough
      final result = RoutePredictionService.predict(
        distanceKm: 50,
        currentBattery: 20,
        payload: PayloadType.onePerson,
        trips: trips,
      );
      expect(result.isEnough, isFalse);
      expect(result.remainingBattery, lessThan(5));
    });

    test('exactly at 5% buffer → still enough', () {
      // Need remaining == 5 exactly
      // With default efficiency 1.2: drain for 90km = ceil(90/1.2) = 75
      // 80 - 75 = 5 → enough
      final result = RoutePredictionService.predict(
        distanceKm: 90,
        currentBattery: 80,
        payload: PayloadType.onePerson,
        trips: [],
        defaultEfficiency: 1.2,
      );
      expect(result.remainingBattery, equals(5));
      expect(result.isEnough, isTrue);
    });

    test('no matching payload trips → falls back to all trips + payload adjust', () {
      final trips = [
        _makeTrip(distance: 12, batteryConsumed: 10, payload: PayloadType.onePerson),
      ];
      // No twoPerson trips → falls back to all trips
      // avg eff from onePerson trips = 1.2
      // adjusted for twoPerson: 1.2 / 1.3 = 0.923
      // drain = ceil(10 / 0.923 * 1.3) = ceil(14.08) = 15
      final result = RoutePredictionService.predict(
        distanceKm: 10,
        currentBattery: 80,
        payload: PayloadType.twoPerson,
        trips: trips,
      );
      expect(result.isEnough, isTrue);
      expect(result.estimatedBatteryDrain, greaterThan(0));
      // twoPerson should consume more than onePerson for same distance
      final result1p = RoutePredictionService.predict(
        distanceKm: 10,
        currentBattery: 80,
        payload: PayloadType.onePerson,
        trips: trips,
      );
      expect(result.estimatedBatteryDrain,
          greaterThanOrEqualTo(result1p.estimatedBatteryDrain));
    });

    test('no trips at all → uses defaultEfficiency', () {
      final result = RoutePredictionService.predict(
        distanceKm: 12,
        currentBattery: 80,
        payload: PayloadType.onePerson,
        trips: [],
        defaultEfficiency: 1.2,
      );
      // drain = ceil(12 / 1.2 * 1.0) = 10
      // remaining = 80 - 10 = 70
      expect(result.estimatedBatteryDrain, 10);
      expect(result.remainingBattery, 70);
      expect(result.isEnough, isTrue);
      expect(result.efficiencyUsed, 1.2);
    });

    test('zero distance → 0 drain', () {
      final result = RoutePredictionService.predict(
        distanceKm: 0,
        currentBattery: 80,
        payload: PayloadType.onePerson,
        trips: [],
      );
      expect(result.estimatedBatteryDrain, 0);
      expect(result.remainingBattery, 80);
      expect(result.isEnough, isTrue);
    });
  });

  group('MockRouteDistanceProvider', () {
    test('returns manual distance', () async {
      final provider = MockRouteDistanceProvider(manualDistanceKm: 15.5);
      final distance = await provider.getDistance('Anywhere');
      expect(distance, 15.5);
    });
  });

  group('RoutePredictionResult', () {
    test('fields are correctly assigned', () {
      final result = RoutePredictionResult(
        distanceKm: 20,
        payload: PayloadType.onePerson,
        efficiencyUsed: 1.1,
        estimatedBatteryDrain: 18,
        remainingBattery: 62,
        isEnough: true,
      );
      expect(result.distanceKm, 20);
      expect(result.payload, PayloadType.onePerson);
      expect(result.efficiencyUsed, 1.1);
      expect(result.estimatedBatteryDrain, 18);
      expect(result.remainingBattery, 62);
      expect(result.isEnough, isTrue);
    });
  });
}
