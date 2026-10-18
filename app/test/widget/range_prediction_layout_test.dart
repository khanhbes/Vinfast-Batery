import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/services/trip_energy_model.dart';
import 'package:vinfast_battery/features/home/widgets/range_prediction_card.dart';

VehicleModel vehicle(String id) => VehicleModel(
  vehicleId: id,
  currentOdo: 10,
  currentBattery: 50,
  stateOfHealth: 90,
);

/// 1.21 km/% average (the owner's trained model, QA 129).
const learned = TripModelParams(
  refPctPerKm: TripEnergyModel.refToMean / 1.21,
  source: TripKmSource.model,
  samples: 77,
  spread: 0.18,
);

Widget _page(Widget child, {double scale = 1}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: child,
      ),
    ),
  ),
);

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('Range wraps at 320dp, text x$scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _page(
          RangePredictionCard(vehicle: vehicle('a'), learned: learned),
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();
      // (50 − 5) × 1.21 = 54.45 km, ±18 %.
      expect(find.text('~54 km'), findsOneWidget);
      expect(find.text('45–64 km'), findsOneWidget);
      expect(find.textContaining('77 chuyến'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Without a learned model: catalog x SoH, labelled so', (
    tester,
  ) async {
    await tester.pumpWidget(_page(RangePredictionCard(vehicle: vehicle('a'))));
    await tester.pumpAndSettle();
    // (50 − 5) × 1.2 × 0.9 = 48.6 km.
    expect(find.text('~49 km'), findsOneWidget);
    expect(find.text('Ước tính theo thông số dòng xe'), findsOneWidget);
    expect(find.textContaining('Độ tin cậy'), findsNothing);
  });
}
