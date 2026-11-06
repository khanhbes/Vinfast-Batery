import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/utils/start_soc_freshness.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/models/vehicle_learning_status.dart';
import 'package:vinfast_battery/features/ai/widgets/confirm_actual_soc_sheet.dart';
import 'package:vinfast_battery/features/ai/widgets/edit_current_battery_sheet.dart';
import 'package:vinfast_battery/features/ai/widgets/full_charge_nudge.dart';

Widget _host(void Function(BuildContext) onTap, double scale) => MaterialApp(
  theme: LuxeTheme.data(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => onTap(context),
          child: const Text('Mở'),
        ),
      ),
    ),
  ),
);

Future<void> _open(
  WidgetTester tester,
  void Function(BuildContext) onTap,
  double scale,
) async {
  await tester.binding.setSurfaceSize(const Size(320, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_host(onTap, scale));
  await tester.tap(find.text('Mở'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

SmartChargingSession _session(
  String id, {
  double energy = 1000,
  ChargingStopReason? stop = ChargingStopReason.targetReached,
  double? actual,
  ChargingSessionState state = ChargingSessionState.completed,
}) {
  final at = DateTime(2026, 11, 6);
  return SmartChargingSession.fromJson({
    'session_id': id,
    'vehicle_id': 'car',
    'device_id': 'd',
    'state': state.wireValue,
    'strategy': 'target_soc',
    'start_soc': 20,
    'target_soc': 80,
    'version': 1,
    'created_at': at.toIso8601String(),
    'updated_at': at.toIso8601String(),
    'ai_stop_at': at.toIso8601String(),
    'effective_stop_at': at.toIso8601String(),
    'absolute_safety_stop_at': at.toIso8601String(),
    'hard_deadline_at': at.toIso8601String(),
    'energy_used_wh': energy,
    'stop_reason': stop?.wireValue,
    'actual_end_soc': actual,
  });
}

void main() {
  group('the saved start % (QA 148)', () {
    final now = DateTime(2026, 11, 6, 12);

    test('only a recent reading counts as fresh', () {
      final recent = now.subtract(const Duration(minutes: 30));
      expect(StartSocFreshness.isFresh(recent, 'reading_manual', now), isTrue);
      expect(StartSocFreshness.isFresh(recent, 'user_confirmed', now), isTrue);
      expect(StartSocFreshness.isFresh(recent, 'reading_photo', now), isTrue);
      final old = now.subtract(const Duration(hours: 3));
      expect(StartSocFreshness.isFresh(old, 'reading_manual', now), isFalse);
      // The estimate of the last charge is never the gauge, however recent.
      expect(
        StartSocFreshness.isFresh(recent, 'smart_charge_estimated', now),
        isFalse,
      );
      expect(StartSocFreshness.isFresh(null, 'reading_manual', now), isFalse);
    });

    test('the note says how old it is and what is wrong with it', () {
      final old = now.subtract(const Duration(days: 2));
      expect(
        StartSocFreshness.staleNote(old, 'reading_manual', now),
        startsWith('Số này lưu từ 2 ngày trước.'),
      );
      expect(
        StartSocFreshness.staleNote(old, 'smart_charge_estimated', now),
        startsWith('Số ước tính sau lần sạc trước, 2 ngày trước.'),
      );
      expect(
        StartSocFreshness.staleNote(null, null, now),
        startsWith('Chưa rõ số này lưu từ khi nào.'),
      );
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('one tap says the saved number is right x$scale', (
        tester,
      ) async {
        double? saved;
        await _open(
          tester,
          (context) => EditCurrentBatterySheet.show(
            context,
            initialPercent: 80,
            savedNote: 'Số này lưu từ 2 ngày trước.',
            scan: () async => 42,
            onSave: (value) => saved = value,
          ),
          scale,
        );
        expect(find.text('Đồng hồ xe đang báo bao nhiêu %?'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('start-soc-saved-note')),
          findsOneWidget,
        );
        final confirm = find.byKey(const ValueKey('start-soc-confirm'));
        await tester.ensureVisible(confirm);
        await tester.pumpAndSettle();
        expect(find.text('Đúng số trên xe'), findsOneWidget);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(saved, 80);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a scan fills the number and changes the button x$scale', (
        tester,
      ) async {
        double? saved;
        await _open(
          tester,
          (context) => EditCurrentBatterySheet.show(
            context,
            initialPercent: 80,
            savedNote: 'Số này lưu từ 2 ngày trước.',
            scan: () async => 42,
            onSave: (value) => saved = value,
          ),
          scale,
        );
        final scan = find.byKey(const ValueKey('start-soc-scan'));
        await tester.ensureVisible(scan);
        await tester.tap(scan);
        await tester.pumpAndSettle();
        final confirm = find.byKey(const ValueKey('start-soc-confirm'));
        await tester.ensureVisible(confirm);
        await tester.pumpAndSettle();
        expect(find.text('Xác nhận mức pin'), findsOneWidget);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(saved, 42);
      });
    }

    testWidgets('editing without a stale number keeps the plain sheet', (
      tester,
    ) async {
      await _open(
        tester,
        (context) => EditCurrentBatterySheet.show(
          context,
          initialPercent: 80,
          onSave: (_) {},
        ),
        1,
      );
      expect(find.text('Chỉnh mức pin hiện tại'), findsOneWidget);
      expect(find.byKey(const ValueKey('start-soc-scan')), findsNothing);
    });
  });

  group('the reading after a charge (QA 148)', () {
    ActualSocReading? result;
    Future<void> open(
      WidgetTester tester, {
      DateTime? endedAt,
      double scale = 1,
    }) => _open(tester, (context) async {
      result = await ConfirmActualSocSheet.show(
        context,
        estimatedSoc: 79,
        startSoc: 22,
        endedAt: endedAt,
      );
    }, scale);

    final save = find.byKey(const ValueKey('actual-soc-save'));

    setUp(() => result = null);

    for (final scale in [1.0, 2.0]) {
      testWidgets('nothing is filled in, so one tap saves nothing x$scale', (
        tester,
      ) async {
        await open(tester, scale: scale);
        expect(find.text('Chọn số trên xe'), findsOneWidget);
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(find.text('Đồng hồ xe đang báo bao nhiêu %?'), findsOneWidget);

        // The estimate itself is a valid answer, once it is chosen.
        final chip = find.widgetWithText(ChoiceChip, '79%');
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(result?.soc, 79);
        expect(result?.ridden, isFalse);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a late reading asks about riding x$scale', (tester) async {
        await open(
          tester,
          endedAt: DateTime.now().subtract(const Duration(hours: 7)),
          scale: scale,
        );
        expect(find.text('Từ lúc rút sạc, xe đã chạy chưa?'), findsOneWidget);
        final chip = find.widgetWithText(ChoiceChip, '79%');
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        // A number alone is not enough here.
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(result, isNull);

        final ridden = find.byKey(const ValueKey('actual-soc-ridden'));
        await tester.ensureVisible(ridden);
        await tester.tap(ridden);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('actual-soc-ridden-note')),
          findsOneWidget,
        );
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(result?.ridden, isTrue);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('right after the charge it does not ask', (tester) async {
      await open(
        tester,
        endedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(find.text('Từ lúc rút sạc, xe đã chạy chưa?'), findsNothing);
    });

    testWidgets('leaving without a number is fine', (tester) async {
      await open(tester);
      final later = find.text('Để sau');
      await tester.ensureVisible(later);
      await tester.tap(later);
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('Đồng hồ xe đang báo bao nhiêu %?'), findsNothing);
    });
  });

  group('suggesting a full charge (QA 148)', () {
    test('counts every real charge, with or without a typed %', () {
      expect(chargesSinceFull([for (var i = 0; i < 6; i++) _session('s$i')]), 6);
    });

    test('stops at the last full one, newest first', () {
      expect(
        chargesSinceFull([
          _session('a'),
          _session('b'),
          _session('full', stop: ChargingStopReason.batteryFull),
          _session('c'),
        ]),
        2,
      );
      expect(
        chargesSinceFull([_session('a'), _session('typed', actual: 100)]),
        1,
      );
    });

    test('a short test and a running charge do not count', () {
      expect(
        chargesSinceFull([
          _session('run', state: ChargingSessionState.active),
          _session('test', energy: 5),
          _session('real'),
        ]),
        1,
      );
    });
  });

  group('training by itself (QA 148)', () {
    VehicleLearningStatus? status(Map<String, dynamic> extra) =>
        VehicleLearningStatus.fromJson({
          'vehicleId': 'car',
          'charge': {
            'pending': 0,
            'required': 3,
            'learning': {
              'state': 'enough',
              'charges': 5,
              'needCharges': 5,
              'gainPct': 120,
              'needGainPct': 100,
            },
          },
          'trip': {'pending': 0, 'required': 10},
          ...extra,
        });

    test('switched on there is nothing to press, and an older server', () {
      expect(status({'autoTrain': true})!.chargeLearningTag, isNull);
      expect(status({})!.autoTrain, isFalse);
      expect(status({})!.chargeLearningTag, 'Đủ dữ liệu · bấm Huấn luyện');
      expect(
        status({'autoTrain': false, 'trainAllowed': false})!.chargeLearningTag,
        'Đủ dữ liệu · bật Tự huấn luyện',
      );
    });

    test('the report says it ran by itself', () {
      expect(
        TrainingReport.fromJson({'decision': 'promoted', 'auto': true})!.auto,
        isTrue,
      );
      expect(TrainingReport.fromJson({'decision': 'promoted'})!.auto, isFalse);
    });
  });
}
