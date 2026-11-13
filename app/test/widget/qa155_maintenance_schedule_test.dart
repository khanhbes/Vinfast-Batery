import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/maintenance_task_model.dart';
import 'package:vinfast_battery/features/maintenance/vinfast_service_catalog.dart';
import 'package:vinfast_battery/features/maintenance/widgets/vinfast_schedule_sheet.dart';

MaintenanceTaskModel _visit(
  int target, {
  String id = 'v',
  bool done = false,
  int? doneOdo,
  DateTime? doneAt,
}) => MaintenanceTaskModel(
  taskId: id,
  vehicleId: 'v1',
  title: VinFastSchedule.visitTitle(target),
  targetOdo: target,
  isCompleted: done,
  completedOdo: doneOdo,
  completedDate: doneAt,
  serviceType: ServiceType.inspection,
);

void main() {
  group('the published schedule', () {
    test('1 000 km, then every 5 000 km; months 1, 6, 12', () {
      expect(VinFastSchedule.nearest(0), 1000);
      expect(VinFastSchedule.nearest(2600), 1000);
      expect(VinFastSchedule.nearest(3100), 5000);
      expect(VinFastSchedule.nearest(5398), 5000);
      expect(VinFastSchedule.nearest(7600), 10000);
      expect(VinFastSchedule.after(1000), 5000);
      expect(VinFastSchedule.after(5000), 10000);
      expect(VinFastSchedule.monthOf(1000), 1);
      expect(VinFastSchedule.monthOf(5000), 6);
      expect(VinFastSchedule.monthOf(50000), 60);
      expect(VinFastSchedule.monthsToNext(1000), 5);
      expect(VinFastSchedule.monthsToNext(10000), 6);
    });

    test('the work of a visit is the table of the book', () {
      final first = VinFastSchedule.workAt(1000);
      // No motor and no seat lock at the first visit; nothing is greased.
      expect(first.length, 17);
      expect(first.any((w) => w.grease), isFalse);
      final second = VinFastSchedule.workAt(5000);
      expect(second.length, 19);
      expect(
        [
          for (final w in second)
            if (w.grease) w.preset.type,
        ],
        [ServiceType.brakeLever, ServiceType.sideStand, ServiceType.seatLock],
      );
      // The seat lock is greased, not inspected.
      expect(second.where((w) => w.check).length, 18);
      bool neck(int km) => VinFastSchedule.workAt(km)
          .firstWhere((w) => w.preset.type == ServiceType.steeringBearing)
          .grease;
      expect(neck(15000), isFalse);
      expect(neck(20000), isTrue);
      expect(neck(40000), isTrue);
      // Past 50 000 km the cycle repeats.
      expect(neck(70000), isTrue);
      expect(VinFastSchedule.workAt(55000).length, 19);
      expect(
        VinFastSchedule.visitDescription(5000),
        contains('Kiểm tra 18 hạng mục'),
      );
    });

    test('every item of the book is planned at the visit interval', () {
      expect(VinFastServiceCatalog.presets.length, 19);
      expect(
        VinFastServiceCatalog.presets.every(
          (p) => p.suggestedOdoInterval == 5000,
        ),
        isTrue,
      );
    });
  });

  group('which visit to plan', () {
    test('no record: the milestone the scooter is at, with the next one', () {
      final p = proposeVisit(5398, const []);
      expect(p.milestones, [5000, 10000]);
      expect(p.open, isNull);
      expect(p.suggestedDate, isNull);
      expect(proposeVisit(0, const []).milestones, [1000]);
      expect(proposeVisit(7600, const []).milestones, [10000]);
    });

    test('after a recorded visit: the next one, six months later', () {
      final done = _visit(
        5000,
        done: true,
        doneOdo: 5398,
        doneAt: DateTime(2026, 8, 31, 12),
      );
      final p = proposeVisit(5600, [done]);
      expect(p.milestones, [10000]);
      // 31 August plus six months lands on the last day of February.
      expect(p.suggestedDate, DateTime(2027, 2, 28));
    });

    test('an open visit means nothing to create', () {
      final p = proposeVisit(5398, [_visit(10000)]);
      expect(p.open!.targetOdo, 10000);
    });

    test('completing a visit offers the next milestone and its date', () {
      final done = _visit(
        1000,
        done: true,
        doneOdo: 1240,
        doneAt: DateTime(2026, 11, 13, 12),
      );
      final next = VinFastServiceCatalog.nextAfter(
        done,
        currentOdo: 1240,
        all: [done],
      )!;
      expect(next.targetOdo, 5000);
      expect(next.title, VinFastSchedule.visitTitle(5000));
      expect(next.serviceType, ServiceType.inspection);
      expect(next.scheduledDate, DateTime(2027, 4, 13));
    });
  });

  group('VisitSheet', () {
    Future<List<VisitDraft>> pump(
      WidgetTester tester,
      double scale,
      VisitProposal proposal, {
      bool readOnly = false,
    }) async {
      final saved = <VisitDraft>[];
      final size = Size(320, scale == 1 ? 2400 : 5200);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: LuxeTheme.data(),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: VisitSheet(
                proposal: proposal,
                readOnly: readOnly,
                now: () => DateTime(2026, 11, 13, 9, 30),
                onCreate: (draft) async {
                  saved.add(draft);
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
      testWidgets('fits 320 dp at ×$scale; the owner picks the milestone', (
        tester,
      ) async {
        final saved = await pump(tester, scale, proposeVisit(5398, const []));
        expect(tester.takeException(), isNull);
        expect(find.text(VinFastSchedule.visitTitle(5000)), findsOneWidget);
        final later = find.byKey(const ValueKey('visit-choice-10000'));
        await tester.ensureVisible(later);
        await tester.pump();
        await tester.tap(later);
        await tester.pump();
        expect(find.text(VinFastSchedule.visitTitle(10000)), findsOneWidget);
        final create = find.byKey(const ValueKey('visit-create'));
        await tester.ensureVisible(create);
        await tester.pump();
        await tester.tap(create);
        await tester.pump(const Duration(milliseconds: 100));
        expect(saved.single.milestone, 10000);
        expect(saved.single.date, isNull);
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an open visit shows the list and no create button', (
      tester,
    ) async {
      await pump(tester, 1, proposeVisit(5398, [_visit(10000)]));
      expect(find.byKey(const ValueKey('visit-open')), findsOneWidget);
      expect(find.byKey(const ValueKey('visit-create')), findsNothing);
      expect(find.text('Dầu phanh'), findsOneWidget);
    });

    testWidgets('the read-only list has no date and no button', (tester) async {
      await pump(
        tester,
        1,
        const VisitProposal(milestones: [20000], currentOdo: 0),
        readOnly: true,
      );
      expect(find.byKey(const ValueKey('visit-date')), findsNothing);
      expect(find.byKey(const ValueKey('visit-create')), findsNothing);
      expect(find.text('Kiểm tra, bôi trơn'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  });
}
