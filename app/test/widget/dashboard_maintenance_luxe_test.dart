import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/maintenance_task_model.dart';
import 'package:vinfast_battery/features/achievements/services/achievement_engine.dart';
import 'package:vinfast_battery/features/home/widgets/luxe_vehicle_hero.dart';
import 'package:vinfast_battery/features/home/widgets/recent_charging_chart.dart';
import 'package:vinfast_battery/features/maintenance/vinfast_service_catalog.dart';
import 'package:vinfast_battery/features/maintenance/widgets/odo_widgets.dart';
import 'package:vinfast_battery/features/maintenance/widgets/vinfast_schedule_sheet.dart';

LedgerSession charge(String id, DateTime at, double wh) => LedgerSession(
  id: id,
  state: 'completed',
  ai: true,
  startSoc: 30,
  targetSoc: 80,
  energyWh: wh,
  startedAt: at,
  stoppedAt: at.add(const Duration(hours: 1)),
);

MaintenanceTaskModel task(int target, {bool done = false, ServiceType? type}) =>
    MaintenanceTaskModel(
      vehicleId: 'v',
      title: 'Mốc $target',
      description: '',
      targetOdo: target,
      isCompleted: done,
      createdAt: DateTime(2030),
      serviceType: type ?? ServiceType.other,
    );

void main() {
  test('standard schedule proposes the next interval and skips open types', () {
    final first = VinFastServiceCatalog.presets.first;
    final proposals = proposeSchedule(1240, [
      task(2000, type: first.type),
    ]);
    expect(proposals.length, VinFastServiceCatalog.presets.length);
    final p = proposals.first;
    expect(p.targetOdo % first.suggestedOdoInterval, 0);
    expect(p.targetOdo, greaterThan(1240));
    expect(p.targetOdo - 1240, lessThanOrEqualTo(first.suggestedOdoInterval));
    expect(p.alreadyOpen, isTrue);
    expect(proposals.skip(1).every((e) => !e.alreadyOpen || e.preset.type == first.type), isTrue);
  });

  test('charging week buckets only valid sessions into local days', () {
    final now = DateTime(2030, 3, 10, 20);
    final week = chargingWeek([
      charge('a', DateTime(2030, 3, 10, 8), 2000),
      charge('b', DateTime(2030, 3, 10, 21), 1000),
      charge('c', DateTime(2030, 3, 4, 9), 2500),
      charge('old', DateTime(2030, 3, 1, 9), 2500),
      charge('noload', DateTime(2030, 3, 9, 9), 0),
    ], now);
    expect(week.length, 7);
    expect(week.last.kwh, closeTo(3.0, 1e-9));
    expect(week.last.sessions, 2);
    expect(week.first.kwh, closeTo(2.5, 1e-9));
    expect(week[5].sessions, 0, reason: 'no-load session is not a charge');
  });

  Widget host(Widget child, {double scale = 1, double width = 320}) =>
      MaterialApp(
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: c!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      );

  testWidgets('charging trend never shows placeholder figures', (tester) async {
    await tester.pumpWidget(
      host(RecentChargingPanel(sessions: const [], now: DateTime(2030, 3, 10))),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Chưa có phiên sạc nào'), findsOneWidget);
    expect(find.text('68.5 kWh'), findsNothing);
    expect(find.text('3.45 kW'), findsNothing);

    await tester.pumpWidget(
      host(
        RecentChargingPanel(
          sessions: [charge('a', DateTime(2030, 3, 10, 8), 2400)],
          now: DateTime(2030, 3, 10, 20),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('2.4'), findsWidgets);
    expect(find.text('Hôm nay'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('odometer, track and hero fit 320dp at text $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Column(
            children: [
              const OdometerDrum(value: 12408),
              OdoTrack(
                currentOdo: 1240,
                tasks: [task(1000), task(1260), task(3000), task(900, done: true)],
              ),
              const LuxeVehicleHero(vehicle: null),
            ],
          ),
          scale: scale,
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Mốc kế tiếp'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
