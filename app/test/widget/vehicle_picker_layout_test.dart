import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/providers/app_providers.dart';
import 'package:vinfast_battery/core/widgets/vehicle_picker_sheet.dart';
import 'package:vinfast_battery/core/widgets/vehicle_switcher.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/repositories/vehicle_spec_repository.dart';

void main() {
  final current = VehicleModel(
    vehicleId: 'current',
    currentOdo: 1,
    vehicleName: 'VinFast Feliz Neo tên xe rất dài để kiểm tra',
    batteryCapacityWh: 2400,
    hasEfficiencyData: false,
  );
  final archived = VehicleModel(
    vehicleId: 'archived',
    currentOdo: 2,
    vehicleName: 'Xe đã lưu trữ',
    isArchived: true,
  );
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Vehicle picker $brightness / $scale', (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              allVehiclesProvider.overrideWith(
                (ref) async => [current, archived],
              ),
              allVinFastSpecsProvider.overrideWith((ref) async => []),
              selectedVehicleIdProvider.overrideWith(
                (ref) => current.vehicleId,
              ),
            ],
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: const Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: VehiclePickerSheet(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Xe đã lưu trữ'), findsNothing);
        expect(find.text('2400 Wh'), findsOneWidget);
        expect(find.text('Chưa có dữ liệu'), findsOneWidget);
        expect(find.textContaining('LFP'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('Vehicle switcher has 48dp target and opens picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allVehiclesProvider.overrideWith((ref) async => [current]),
          allVinFastSpecsProvider.overrideWith((ref) async => []),
          selectedVehicleIdProvider.overrideWith((ref) => current.vehicleId),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: VehicleSwitcher())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(TextButton)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.byType(VehiclePickerSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
