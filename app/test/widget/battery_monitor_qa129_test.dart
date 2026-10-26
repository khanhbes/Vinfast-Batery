import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/providers/learned_models_provider.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/services/trip_energy_model.dart';
import 'package:vinfast_battery/features/battery_monitor/battery_monitor_screen.dart';

/// QA 129: the Battery monitor showed a hard-coded 25 °C, six "N/A" tiles,
/// "Good" and a catalog charge time that disagreed with the Charge tab.
void main() {
  final vehicle = VehicleModel(
    vehicleId: 'car',
    vehicleName: 'VinFast Feliz',
    currentOdo: 4804,
    currentBattery: 79,
    batteryCapacityWh: 2340,
    batteryDataSource: 'reading_chat',
    batteryDataUpdatedAt: DateTime(2026, 10, 18, 4, 8),
  );
  const models = LearnedModels(
    trip: TripModelParams(
      refPctPerKm: TripEnergyModel.refToMean / 1.21,
      source: TripKmSource.model,
      samples: 77,
      spread: 0.18,
    ),
    whPerPct: 26.2,
    powerW: 440,
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('only real data at 320dp, text x$scale', (tester) async {
      tester.view.physicalSize = const Size(320, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            learnedModelsProvider.overrideWith((ref, id) async => models),
          ],
          child: MaterialApp(
            theme: LuxeTheme.data(),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 1400),
                textScaler: TextScaler.linear(scale),
              ),
              child: BatteryMonitorScreen(vehicle: vehicle),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('°C'), findsNothing);
      expect(find.textContaining('N/A'), findsNothing);
      expect(find.text('Good'), findsNothing);
      expect(find.text('Nhập qua Pinova Bot'), findsOneWidget);
      // Same km/% as the Overview: (79 − 5) × 1.21 ≈ 90 km.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('monitor-range-estimate')),
        200,
      );
      expect(find.textContaining('khoảng 90 km'), findsWidgets);
      expect(find.textContaining('26.2 Wh cho 1%'), findsOneWidget);
    });
  }
}
