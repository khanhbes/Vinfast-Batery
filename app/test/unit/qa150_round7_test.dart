import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/widgets/luxe_time_picker.dart';
import 'package:vinfast_battery/data/models/maintenance_task_model.dart';
import 'package:vinfast_battery/features/maintenance/vinfast_service_catalog.dart';

/// QA 150, round 7: next maintenance milestone and the LUXE time picker.
void main() {
  MaintenanceTaskModel task(
    String id,
    ServiceType type,
    int odo, {
    bool done = false,
  }) => MaintenanceTaskModel(
    taskId: id,
    vehicleId: 'v1',
    title: 'Tay phanh',
    targetOdo: odo,
    serviceType: type,
    isCompleted: done,
  );

  group('VinFastServiceCatalog.nextAfter', () {
    test('offers the visit after the one the scooter is at', () {
      final done = task('a', ServiceType.brakeLever, 1000, done: true);
      final next = VinFastServiceCatalog.nextAfter(
        done,
        currentOdo: 1240,
        all: [done],
      )!;
      expect(next.targetOdo, 5000);
      expect(next.taskId, isNull);
      expect(next.serviceType, ServiceType.brakeLever);
      expect(next.title, 'Tay phanh');
    });

    test('done early: still the visit after that milestone', () {
      final done = task('a', ServiceType.brakeLever, 1000, done: true);
      expect(
        VinFastServiceCatalog.nextAfter(
          done,
          currentOdo: 900,
          all: [done],
        )!.targetOdo,
        5000,
      );
    });

    test('nothing to offer when that service already has an open one', () {
      final done = task('a', ServiceType.brakeLever, 1000, done: true);
      final later = task('b', ServiceType.brakeLever, 2000);
      expect(
        VinFastServiceCatalog.nextAfter(
          done,
          currentOdo: 1000,
          all: [done, later],
        ),
        isNull,
      );
    });

    test('a service without a published interval is left to the owner', () {
      final done = task('a', ServiceType.other, 1000, done: true);
      expect(
        VinFastServiceCatalog.nextAfter(done, currentOdo: 1000, all: [done]),
        isNull,
      );
    });
  });

  group('showLuxeTimePicker', () {
    Future<TimeOfDay?> open(WidgetTester tester, {double scale = 1}) async {
      TimeOfDay? result;
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: LuxeTheme.data(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 720),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showLuxeTimePicker(
                      context,
                      initialTime: const TimeOfDay(hour: 21, minute: 5),
                      title: 'Ngắt lúc',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('21:05'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('luxe-time-hour')),
        const Offset(0, -48),
      );
      await tester.pumpAndSettle();
      expect(find.text('22:05'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('luxe-time-confirm')));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('320 dp: shows the time, a wheel changes it, Chọn returns', (
      tester,
    ) async {
      expect(await open(tester), const TimeOfDay(hour: 22, minute: 5));
    });

    testWidgets('320 dp at text x2 does not overflow', (tester) async {
      expect(
        await open(tester, scale: 2),
        const TimeOfDay(hour: 22, minute: 5),
      );
    });
  });
}
