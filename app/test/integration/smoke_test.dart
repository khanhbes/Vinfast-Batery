import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/charge_log_model.dart';
import 'package:vinfast_battery/data/models/trip_log_model.dart';
import 'package:vinfast_battery/data/models/maintenance_task_model.dart';
import 'package:vinfast_battery/data/services/battery_logic_service.dart';
import 'package:vinfast_battery/data/services/smart_charging_service.dart';
import 'package:vinfast_battery/data/services/route_prediction_service.dart';

/// ========================================================================
/// Integration Smoke Tests
/// Kiểm tra luồng: trip → Firestore fields, charge target → log fields
/// (chạy offline, không cần Firebase thật)
/// ========================================================================

/// Helper builders
ChargeLogModel _makeCharge({
  required int start,
  required int end,
  required int minutes,
  int? target,
}) {
  final now = DateTime(2026, 4, 1, 10, 0);
  return ChargeLogModel(
    vehicleId: 'v1',
    startTime: now,
    endTime: now.add(Duration(minutes: minutes)),
    startBatteryPercent: start,
    endBatteryPercent: end,
    odoAtCharge: 5000,
    targetBatteryPercent: target,
    estimatedCompleteAt: target != null
        ? now.add(Duration(minutes: minutes + 10))
        : null,
  );
}

TripLogModel _makeTrip({
  required double distance,
  required int startBat,
  required int endBat,
  PayloadType payload = PayloadType.onePerson,
  TripEntryMode mode = TripEntryMode.live,
  DistanceSource source = DistanceSource.gps,
}) {
  final consumed = startBat - endBat;
  final eff = consumed > 0 ? distance / consumed : 0.0;
  final now = DateTime(2026, 4, 1, 10, 0);
  return TripLogModel(
    vehicleId: 'v1',
    startTime: now,
    endTime: now.add(const Duration(hours: 1)),
    distance: distance,
    payloadType: payload,
    startBattery: startBat,
    endBattery: endBat,
    batteryConsumed: consumed,
    efficiency: eff,
    startOdo: 5000,
    endOdo: 5000 + distance.toInt(),
    entryMode: mode,
    distanceSource: source,
  );
}

void main() {
  group('Smoke: Live trip → fields đầy đủ', () {
    test('live trip has correct entry mode + distance source', () {
      final trip = _makeTrip(
        distance: 12,
        startBat: 80,
        endBat: 70,
        mode: TripEntryMode.live,
        source: DistanceSource.gps,
      );
      expect(trip.entryMode, TripEntryMode.live);
      expect(trip.distanceSource, DistanceSource.gps);
      expect(trip.batteryConsumed, 10);
      expect(trip.efficiency, closeTo(1.2, 0.01));
      expect(trip.distance, 12.0);
    });

    test('manual trip has correct fields', () {
      final trip = _makeTrip(
        distance: 15,
        startBat: 90,
        endBat: 75,
        mode: TripEntryMode.manual,
        source: DistanceSource.odometer,
      );
      expect(trip.entryMode, TripEntryMode.manual);
      expect(trip.distanceSource, DistanceSource.odometer);
      expect(trip.batteryConsumed, 15);
      expect(trip.efficiency, closeTo(1.0, 0.01));
    });

    test('trip toFirestore includes entryMode + distanceSource', () {
      final trip = _makeTrip(
        distance: 12,
        startBat: 80,
        endBat: 70,
        mode: TripEntryMode.manual,
        source: DistanceSource.odometer,
      );
      final map = trip.toFirestore();
      expect(map['entryMode'], 'manual');
      expect(map['distanceSource'], 'odometer');
      expect(map['distance'], 12.0);
      expect(map['batteryConsumed'], 10);
    });
  });

  group('Smoke: Charge target 80% → log lưu đúng', () {
    test('charge log with target has targetBatteryPercent', () {
      final log = _makeCharge(start: 30, end: 80, minutes: 125, target: 80);
      expect(log.targetBatteryPercent, 80);
      expect(log.estimatedCompleteAt, isNotNull);
      expect(log.chargeGain, 50);
    });

    test('charge log without target has null target fields', () {
      final log = _makeCharge(start: 30, end: 80, minutes: 125);
      expect(log.targetBatteryPercent, isNull);
      expect(log.estimatedCompleteAt, isNull);
    });

    test('charge toFirestore includes target fields', () {
      final log = _makeCharge(start: 30, end: 80, minutes: 125, target: 90);
      final map = log.toFirestore();
      expect(map['targetBatteryPercent'], 90);
      expect(map['estimatedCompleteAt'], isNotNull);
    });

    test('charge toMap includes target fields', () {
      final log = _makeCharge(start: 30, end: 80, minutes: 125, target: 100);
      final map = log.toMap();
      expect(map['targetBatteryPercent'], 100);
      expect(map['estimatedCompleteAt'], isNotNull);
    });
  });

  group('Smoke: End-to-end trip → ETA → route prediction', () {
    test('trip data → feeds smart charging → feeds route prediction', () {
      // 1. Tạo trips & charge logs
      final trips = [
        _makeTrip(distance: 12, startBat: 80, endBat: 70),
        _makeTrip(distance: 10, startBat: 70, endBat: 62),
        _makeTrip(distance: 8, startBat: 62, endBat: 55),
      ];
      final chargeLogs = [
        _makeCharge(start: 20, end: 80, minutes: 150, target: 80),
        _makeCharge(start: 30, end: 90, minutes: 120, target: 90),
        _makeCharge(start: 40, end: 100, minutes: 180, target: 100),
      ];

      // 2. BatteryLogicService: hiệu suất trung bình
      final avgEff = BatteryLogicService.avgEfficiency(trips);
      expect(avgEff, greaterThan(0));

      // 3. SmartChargingService: ETA sạc
      final eta = SmartChargingService.estimateChargeMinutes(
        fromPercent: 30,
        toPercent: 80,
        chargeLogs: chargeLogs,
      );
      expect(eta, isNotNull);
      expect(eta!, greaterThan(0));

      // 4. Route prediction: dùng kết quả trip data
      final prediction = RoutePredictionService.predict(
        distanceKm: 15,
        currentBattery: 80,
        payload: PayloadType.onePerson,
        trips: trips,
      );
      expect(prediction.isEnough, isTrue);
      expect(prediction.estimatedBatteryDrain, greaterThan(0));
      expect(prediction.remainingBattery, lessThan(80));
    });
  });

  group('Smoke: Maintenance integration', () {
    test('overdue task detected at correct ODO', () {
      final task = MaintenanceTaskModel(
        taskId: 'maint_1',
        vehicleId: 'v1',
        title: 'Thay nhớt',
        targetOdo: 10000,
      );

      // Before due
      expect(task.isDueSoon(9000), isFalse);
      expect(task.isOverdue(9000), isFalse);

      // Due soon (within 50km)
      expect(task.isDueSoon(9960), isTrue);
      expect(task.isOverdue(9960), isFalse);

      // Overdue
      expect(task.isDueSoon(10100), isTrue);
      expect(task.isOverdue(10100), isTrue);

      // After completion
      final completed = task.copyWith(isCompleted: true);
      expect(completed.isDueSoon(10100), isFalse);
      expect(completed.isOverdue(10100), isFalse);
    });
  });

  group('Smoke: Enum serialization round-trip', () {
    test('PayloadType round-trip', () {
      expect(PayloadType.fromString('1_person'), PayloadType.onePerson);
      expect(PayloadType.fromString('2_person'), PayloadType.twoPerson);
      expect(PayloadType.fromString('unknown'), PayloadType.onePerson); // fallback
    });

    test('TripEntryMode round-trip', () {
      expect(TripEntryMode.fromString('live'), TripEntryMode.live);
      expect(TripEntryMode.fromString('manual'), TripEntryMode.manual);
      expect(TripEntryMode.fromString('unknown'), TripEntryMode.live);
    });

    test('DistanceSource round-trip', () {
      expect(DistanceSource.fromString('gps'), DistanceSource.gps);
      expect(DistanceSource.fromString('odometer'), DistanceSource.odometer);
      expect(DistanceSource.fromString('unknown'), DistanceSource.gps);
    });
  });

  group('Smoke: BatteryLogicService calculations', () {
    test('batteryDrainForDistance 1 person', () {
      final drain = BatteryLogicService.batteryDrainForDistance(
        12.0, 1.2, PayloadType.onePerson,
      );
      // base = 12/1.2 = 10, factor 1.0, ceil = 10
      expect(drain, 10);
    });

    test('batteryDrainForDistance 2 person', () {
      final drain = BatteryLogicService.batteryDrainForDistance(
        12.0, 1.2, PayloadType.twoPerson,
      );
      // base = 12/1.2 = 10, factor 1.3 → 13.0, ceil = 13
      expect(drain, 13);
    });

    test('SoH calculation from trips', () {
      final trips = [
        _makeTrip(distance: 10, startBat: 80, endBat: 70), // eff = 1.0
      ];
      final soh = BatteryLogicService.calculateSoH(trips);
      // soh = (1.0 / 1.2) * 100 = 83.33
      expect(soh, closeTo(83.33, 0.1));
    });

    test('SoH good status', () {
      expect(BatteryLogicService.getSoHStatus(85), SoHStatus.good);
    });

    test('SoH fair status', () {
      expect(BatteryLogicService.getSoHStatus(70), SoHStatus.fair);
    });

    test('SoH degraded status', () {
      expect(BatteryLogicService.getSoHStatus(50), SoHStatus.degraded);
    });

    test('SoH critical status', () {
      expect(BatteryLogicService.getSoHStatus(30), SoHStatus.critical);
    });
  });
}
