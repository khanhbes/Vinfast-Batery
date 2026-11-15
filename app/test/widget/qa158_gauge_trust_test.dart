import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/models/vehicle_learning_status.dart';
import 'package:vinfast_battery/features/ai/widgets/edit_current_battery_sheet.dart';
import 'package:vinfast_battery/features/ai/widgets/full_charge_nudge.dart';
import 'package:vinfast_battery/features/ai/widgets/prediction_card_v2.dart';

Future<void> _pump(WidgetTester tester, Widget child, double scale) async {
  final size = Size(320, scale == 1 ? 1200 : 2600);
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
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

void main() {
  group('GaugeTrust', () {
    test('reads the server and says what to expect', () {
      final medium = GaugeTrust.fromJson({
        'level': 'medium',
        'anchored': true,
        'sessionsSinceFull': 3,
        'expectedErrorPct': 3.0,
      })!;
      expect(medium.isHigh, isFalse);
      expect(
        medium.line(2),
        'Đã 3 lần chưa sạc đầy · sai số dự kiến khoảng 3% · app sạc dư 2%',
      );
      final high = GaugeTrust.fromJson({
        'level': 'high',
        'anchored': true,
        'expectedErrorPct': 0.5,
      })!;
      expect(high.line(0), 'Sai số dự kiến khoảng 0.5%');
      final never = GaugeTrust.fromJson({'level': 'medium'})!;
      expect(never.line(0), startsWith('Chưa có lần sạc đầy nào làm mốc'));
      expect(GaugeTrust.fromJson({'level': 'odd'}), isNull);
      expect(GaugeTrust.fromJson(null), isNull);
    });

    test('the personal AI card sums the two groups', () {
      final status = ModelTrainingStatus.fromJson({
        'model': {
          'drift': {
            'afterFull': {'n': 4, 'mae': 0.51},
            'later': {'n': 6, 'mae': 5.04},
          },
          'lastDrift': {'driftPct': 13.39},
        },
      });
      expect(
        status.driftSummary,
        'ngay sau sạc đầy sai số khoảng 0.5% (4 lần) · xa lần sạc đầy '
        'khoảng 5.0% (6 lần) · lần sạc đầy gần nhất đồng hồ lệch 13.4%',
      );
      expect(ModelTrainingStatus.fromJson({}).driftSummary, isNull);
    });
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the trust line and the nudge fit 320 dp at ×$scale', (
      tester,
    ) async {
      await _pump(
        tester,
        Column(
          children: [
            const PredictionCardV2(
              durationMinutes: 150,
              stopTime: '21:30',
              fromSoc: 9,
              toSoc: 80,
              personalizationLabel: 'Học từ 12 lần sạc',
              trustLine:
                  'Đã 3 lần chưa sạc đầy · sai số dự kiến khoảng 3% · app sạc dư 2%',
              trustCaution: true,
            ),
            FullChargeNudge(chargesSinceFull: 3, onChooseFull: () {}),
            FullChargeNudge(
              chargesSinceFull: 0,
              anchored: false,
              onChooseFull: () {},
            ),
          ],
        ),
        scale,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('prediction-trust')), findsOneWidget);
      expect(find.textContaining('Chưa có lần sạc đầy nào'), findsOneWidget);
    });

    testWidgets('the ODO before charging fits 320 dp at ×$scale', (
      tester,
    ) async {
      double? odo = -1;
      await _pump(
        tester,
        EditCurrentBatterySheet(
          initialPercent: 9,
          savedNote: 'Lưu từ 3 giờ trước',
          onSave: (_) {},
          onOdo: (value) => odo = value,
          lastOdoKm: 5398,
          scanReading: () async => (soc: 9, odoKm: 5420.0),
        ),
        scale,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('start-odo')), findsOneWidget);
      // Below the saved ODO: refused, nothing saved.
      await tester.enterText(find.byKey(const ValueKey('start-odo')), '5000');
      final confirm = find.byKey(const ValueKey('start-soc-confirm'));
      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      expect(odo, -1);
      expect(find.textContaining('Nhỏ hơn ODO đã lưu'), findsOneWidget);
      // The scan fills it.
      final scan = find.byKey(const ValueKey('start-soc-scan'));
      await tester.ensureVisible(scan);
      await tester.pump();
      await tester.tap(scan);
      await tester.pump();
      expect(find.text('5420'), findsOneWidget);
    });
  }

  testWidgets('an empty ODO is fine and a typed one is saved', (tester) async {
    final saved = <double?>[];
    Widget sheet() => Navigator(
      key: UniqueKey(),
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => EditCurrentBatterySheet(
          initialPercent: 9,
          onSave: (_) {},
          onOdo: saved.add,
          lastOdoKm: 5398,
        ),
      ),
    );
    await _pump(tester, SizedBox(height: 1100, child: sheet()), 1);
    final confirm = find.byKey(const ValueKey('start-soc-confirm'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    expect(saved, [null]);
    await _pump(tester, SizedBox(height: 1100, child: sheet()), 1);
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('start-odo')), '5 430');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    expect(saved.last, 5430);
  });
}
