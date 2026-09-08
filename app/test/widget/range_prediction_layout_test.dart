import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/features/home/widgets/range_prediction_card.dart';

VehicleModel vehicle(String id) => VehicleModel(
  vehicleId: id,
  currentOdo: 10,
  currentBattery: 50,
  stateOfHealth: 90,
);

void main() {
  for (final dark in [false, true]) {
    testWidgets('Range wraps at 320dp with large text / dark=$dark', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: RangePredictionCard(
                  vehicle: vehicle('a'),
                  predictRange: (_) async => {
                    'success': true,
                    'data': {
                      'estimatedRangeKm': 125.5,
                      'rangeLowKm': 100,
                      'rangeHighKm': 150,
                      'confidence': 0,
                    },
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('125.5 km'), findsOneWidget);
      expect(find.text('Độ tin cậy 0%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Offline calculation does not invent confidence', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RangePredictionCard(
            vehicle: vehicle('a'),
            predictRange: (_) async => throw StateError('offline'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('48.6 km'), findsOneWidget);
    expect(find.text('Chưa có độ tin cậy được kiểm chứng'), findsOneWidget);
    expect(find.textContaining('72%'), findsNothing);
  });
  testWidgets('Old response cannot overwrite the selected vehicle', (
    tester,
  ) async {
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    Future<Map<String, dynamic>> predict(VehicleModel v) =>
        v.vehicleId == 'a' ? first.future : second.future;
    Widget page(String id) => MaterialApp(
      home: Scaffold(
        body: RangePredictionCard(vehicle: vehicle(id), predictRange: predict),
      ),
    );
    await tester.pumpWidget(page('a'));
    await tester.pumpWidget(page('b'));
    second.complete({'success': true, 'estimatedRangeKm': 20});
    await tester.pumpAndSettle();
    first.complete({'success': true, 'estimatedRangeKm': 99});
    await tester.pumpAndSettle();
    expect(find.text('20.0 km'), findsOneWidget);
    expect(find.text('99.0 km'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
