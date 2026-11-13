import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/maintenance_task_model.dart';
import 'package:vinfast_battery/features/maintenance/maintenance_screen.dart';
import 'package:vinfast_battery/features/maintenance/vinfast_service_catalog.dart';
import 'package:vinfast_battery/features/maintenance/widgets/maintenance_complete_sheet.dart';

MaintenanceTaskModel _task({
  int target = 6000,
  DateTime? scheduled,
  bool done = false,
  DateTime? completed,
  int? completedOdo,
  int? cost,
  ServiceType type = ServiceType.brakeFluid,
}) => MaintenanceTaskModel(
  taskId: 't1',
  vehicleId: 'v1',
  ownerUid: 'u1',
  title: 'Dầu phanh',
  targetOdo: target,
  scheduledDate: scheduled,
  isCompleted: done,
  completedDate: completed,
  completedOdo: completedOdo,
  costVnd: cost,
  serviceType: type,
);

void main() {
  final now = DateTime(2026, 11, 13, 9, 30);

  group('the appointment date counts', () {
    test('a passed date is overdue even far from the kilometre mark', () {
      final task = _task(scheduled: DateTime(2026, 11, 10));
      expect(task.urgency(5398, now: now), MaintenanceUrgency.overdue);
      expect(task.daysUntilScheduled(now), -3);
      // Without a clock the old kilometre-only answer stays.
      expect(task.urgency(5398), MaintenanceUrgency.upcoming);
    });

    test('within 7 days is due soon; today is not overdue', () {
      expect(
        _task(scheduled: DateTime(2026, 11, 20)).urgency(5398, now: now),
        MaintenanceUrgency.dueSoon,
      );
      expect(
        _task(scheduled: DateTime(2026, 11, 13, 23)).urgency(5398, now: now),
        MaintenanceUrgency.dueSoon,
      );
      expect(
        _task(scheduled: DateTime(2026, 11, 21)).urgency(5398, now: now),
        MaintenanceUrgency.upcoming,
      );
    });

    test('the kilometre mark still decides on its own', () {
      expect(_task().urgency(6000, now: now), MaintenanceUrgency.overdue);
      expect(_task().urgency(5950, now: now), MaintenanceUrgency.dueSoon);
      expect(_task().urgency(5949, now: now), MaintenanceUrgency.upcoming);
      expect(
        _task(
          done: true,
          scheduled: DateTime(2026, 1, 1),
        ).urgency(9999, now: now),
        MaintenanceUrgency.completed,
      );
    });
  });

  group('the service record', () {
    test('a copy keeps the owner and the record', () {
      final copy = _task(completedOdo: 5012, cost: 150000).copyWith(title: 'x');
      expect(copy.ownerUid, 'u1');
      expect(copy.completedOdo, 5012);
      expect(copy.costVnd, 150000);
      final map = copy.toFirestore();
      expect(map['completedOdo'], 5012);
      expect(map['costVnd'], 150000);
    });

    test('the next milestone is counted from where the work was done', () {
      // Due at 5 000, done at 5 398: next at 10 398, not 10 000 or 10 398+.
      final done = _task(target: 5000, done: true, completedOdo: 5398);
      final next = VinFastServiceCatalog.nextAfter(
        done,
        currentOdo: 5600,
        all: [done],
      );
      expect(next!.targetOdo, 5398 + 5000);
      // An older task without a record keeps the old rule.
      final old = _task(target: 5000, done: true);
      expect(
        VinFastServiceCatalog.nextAfter(
          old,
          currentOdo: 5600,
          all: [old],
        )!.targetOdo,
        5600 + 5000,
      );
    });

    test('amounts are read with or without separators', () {
      expect(MaintenanceCompleteSheet.parseAmount('150.000'), 150000);
      expect(MaintenanceCompleteSheet.parseAmount('150 000'), 150000);
      expect(MaintenanceCompleteSheet.parseAmount('5398'), 5398);
      expect(MaintenanceCompleteSheet.parseAmount(''), isNull);
      expect(MaintenanceCompleteSheet.parseAmount('abc'), isNull);
    });

    test('the year summary counts this year only and says what is missing', () {
      final tasks = [
        _task(done: true, completed: DateTime(2026, 8, 1), cost: 150000),
        _task(done: true, completed: DateTime(2026, 10, 2)),
        _task(done: true, completed: DateTime(2025, 12, 30), cost: 900000),
        _task(),
      ];
      final summary = MaintenanceYearSummary.of(tasks, now)!;
      expect(summary.count, 2);
      expect(summary.costVnd, 150000);
      expect(summary.sentence, contains('2 hạng mục'));
      expect(summary.sentence, contains('150.000đ'));
      expect(summary.sentence, contains('1 hạng mục có ghi chi phí'));
      expect(MaintenanceYearSummary.of([_task()], now), isNull);
      expect(
        MaintenanceYearSummary.of([
          _task(done: true, completed: DateTime(2026, 2, 2)),
        ], now)!.sentence,
        contains('Chưa ghi chi phí'),
      );
    });
  });

  group('MaintenanceCompleteSheet', () {
    Future<List<MaintenanceCompletion>> pump(
      WidgetTester tester,
      double scale, {
      int currentOdo = 5398,
    }) async {
      final saved = <MaintenanceCompletion>[];
      tester.view.physicalSize = Size(320, scale == 1 ? 900 : 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: LuxeTheme.data(),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(320, scale == 1 ? 900 : 1800),
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: MaintenanceCompleteSheet(
                task: _task(target: 5000),
                currentOdo: currentOdo,
                now: () => DateTime(2026, 11, 13, 9, 30),
                onSave: (record) async {
                  saved.add(record);
                  return null;
                },
              ),
            ),
          ),
        ),
      );
      return saved;
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets('fits 320 dp at ×$scale and saves the record', (
        tester,
      ) async {
        final saved = await pump(tester, scale);
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byKey(const ValueKey('maintenance-done-cost')),
          '150.000',
        );
        final save = find.byKey(const ValueKey('maintenance-done-save'));
        await tester.ensureVisible(save);
        await tester.pump();
        await tester.tap(save);
        await tester.pump(const Duration(milliseconds: 100));
        expect(saved.single.odo, 5398);
        expect(saved.single.costVnd, 150000);
        expect(saved.single.date, DateTime(2026, 11, 13));
        expect(saved.single.note, isNull);
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an ODO past the vehicle is refused, nothing is saved', (
      tester,
    ) async {
      final saved = await pump(tester, 1);
      await tester.enterText(
        find.byKey(const ValueKey('maintenance-done-odo')),
        '9000',
      );
      final save = find.byKey(const ValueKey('maintenance-done-save'));
      await tester.ensureVisible(save);
      await tester.pump();
      await tester.tap(save);
      await tester.pump(const Duration(milliseconds: 100));
      expect(saved, isEmpty);
      expect(find.textContaining('Lớn hơn ODO hiện tại'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
