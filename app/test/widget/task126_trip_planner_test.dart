import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/providers/app_providers.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/vehicle_learning_status.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/services/server_smart_charger_service.dart';
import 'package:vinfast_battery/features/trip_planner/trip_planner_screen.dart';

VehicleModel _vehicle({bool battery = true}) => VehicleModel(
  vehicleId: 'car',
  currentOdo: 1200,
  currentBattery: 50,
  hasBatteryData: battery,
  stateOfHealth: 100,
  defaultEfficiency: 0.9,
  batteryCapacityWh: 2600,
);

class _RideService implements ServerSmartChargerService {
  final rides = <Map<String, dynamic>>[];
  final readings = <String>[];

  @override
  Future<VehicleLearningStatus?> learningStatus(String vehicleId) async => null;

  @override
  Future<BatteryReadingResult> addBatteryReading(
    String vehicleId, {
    double? soc,
    double? odoKm,
    required String source,
    String? sessionId,
  }) async {
    readings.add(source);
    return const BatteryReadingResult(readingId: 'r');
  }

  @override
  Future<
    ({int added, int duplicates, int rejected, VehicleLearningStatus? status})
  >
  addTripSamples(
    String vehicleId,
    List<Map<String, dynamic>> trips, {
    required String source,
  }) async {
    rides.addAll(trips);
    return (added: trips.length, duplicates: 0, rejected: 0, status: null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child, double scale, ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: LuxeTheme.data(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 640),
            textScaler: TextScaler.linear(scale),
          ),
          child: child,
        ),
      ),
    );

Future<void> _scrollTo(WidgetTester tester, Finder target) =>
    tester.scrollUntilVisible(
      target,
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'manual distance gives a verdict and a charge-first plan x$scale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(
          _app(TripPlannerScreen(vehicle: _vehicle()), scale, container),
        );
        await tester.pump();
        final km = find.byKey(const ValueKey('trip-manual-km'));
        await _scrollTo(tester, km);
        await tester.enterText(km, '45');
        await tester.pump();
        final verdict = find.byKey(const ValueKey('trip-verdict'));
        await _scrollTo(tester, verdict);
        // 45 km / 0.9 km per % = 50 % from 50 %: not enough.
        expect(tester.widget<Text>(verdict).data, 'Không đủ pin');
        final charge = find.byKey(
          const ValueKey('trip-suggestion-charge_first'),
        );
        await _scrollTo(tester, charge);
        await tester.pump();
        await tester.tap(charge);
        await tester.pump();
        final pending = container.read(pendingChargeTargetSocProvider);
        expect(pending?.vehicleId, 'car');
        expect(pending?.targetSoc, 80);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('recording a ride sends it for training x$scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = _RideService();
      await tester.pumpWidget(
        _app(
          TripPlannerScreen(vehicle: _vehicle(), learningService: service),
          scale,
          container,
        ),
      );
      await tester.pump();
      final km = find.byKey(const ValueKey('trip-manual-km'));
      await _scrollTo(tester, km);
      await tester.enterText(km, '12');
      await tester.pump();
      final start = find.byKey(const ValueKey('trip-record-start'));
      await _scrollTo(tester, start);
      await tester.ensureVisible(start);
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('reading-odo')), '1200');
      final save = find.byKey(const ValueKey('reading-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final finish = find.byKey(const ValueKey('trip-record-finish'));
      await _scrollTo(tester, finish);
      await tester.ensureVisible(finish);
      await tester.pumpAndSettle();
      await tester.tap(finish);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('reading-soc')), '40');
      await tester.enterText(
        find.byKey(const ValueKey('reading-odo')),
        '1211.5',
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(service.readings, ['trip_start', 'trip_end']);
      final ride = service.rides.single;
      expect(ride['distanceKm'], 11.5);
      expect(ride['startSoc'], 50);
      expect(ride['endSoc'], 40);
      expect(ride['predictedUsePct'], isNotNull);
      expect(find.byKey(const ValueKey('trip-recording')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no battery reading asks for one instead of guessing', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _app(TripPlannerScreen(vehicle: _vehicle(battery: false)), 1, container),
    );
    await tester.pump();
    final km = find.byKey(const ValueKey('trip-manual-km'));
    await _scrollTo(tester, km);
    await tester.enterText(km, '10');
    await tester.pump();
    expect(find.byKey(const ValueKey('trip-verdict')), findsNothing);
    expect(find.textContaining('nhập mức pin hiện tại'), findsOneWidget);
  });
}
