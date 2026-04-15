import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/features/dashboard/add_manual_trip_modal.dart';

/// ========================================================================
/// Widget Tests: AddManualTripModal form validation + RoutePredictionCard
/// ========================================================================

/// Helper: show modal in a dialog-like container
Widget _wrapModal(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => ProviderScope(
                  child: child,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final testVehicle = VehicleModel(
    vehicleId: 'test_v',
    vehicleName: 'Xe test',
    currentOdo: 5000,
    currentBattery: 80,
  );

  group('AddManualTripModal', () {
    testWidgets('renders form with all fields', (tester) async {
      await tester.pumpWidget(_wrapModal(
        AddManualTripModal(vehicle: testVehicle),
      ));
      // Open the modal
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Check title
      expect(find.text('Nhập chuyến đi thủ công'), findsOneWidget);
      // Check vehicle name
      expect(find.text('Xe: Xe test'), findsOneWidget);
      // Check fields
      expect(find.text('Pin đầu (%)'), findsOneWidget);
      expect(find.text('Pin cuối (%)'), findsOneWidget);
      expect(find.text('ODO đầu (km)'), findsOneWidget);
      expect(find.text('ODO cuối (km)'), findsOneWidget);
      // Check save button
      expect(find.text('Lưu chuyến đi'), findsOneWidget);
      // Check payload selector
      expect(find.text('Tải trọng:'), findsOneWidget);
    });

    testWidgets('ODO đầu pre-filled with vehicle currentOdo', (tester) async {
      await tester.pumpWidget(_wrapModal(
        AddManualTripModal(vehicle: testVehicle),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // ODO đầu should be pre-filled with 5000
      final odoField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, '5000'),
      );
      expect(odoField, isNotNull);
    });

    testWidgets('empty form shows validation errors on save', (tester) async {
      await tester.pumpWidget(_wrapModal(
        AddManualTripModal(vehicle: testVehicle),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap save without filling
      await tester.tap(find.text('Lưu chuyến đi'));
      await tester.pumpAndSettle();

      // Should see "Nhập số" validation messages
      expect(find.text('Nhập số'), findsWidgets);
    });

    testWidgets('battery field rejects value > 100', (tester) async {
      await tester.pumpWidget(_wrapModal(
        AddManualTripModal(vehicle: testVehicle),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Find "Pin đầu (%)" field and enter 101
      final pinFields = find.byType(TextFormField);
      // Pin đầu is the first TextFormField with that label
      await tester.enterText(pinFields.at(0), '101');
      await tester.tap(find.text('Lưu chuyến đi'));
      await tester.pumpAndSettle();

      expect(find.text('0-100%'), findsWidgets);
    });

    testWidgets('time picker labels exist', (tester) async {
      await tester.pumpWidget(_wrapModal(
        AddManualTripModal(vehicle: testVehicle),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Giờ xuất phát'), findsOneWidget);
      expect(find.text('Giờ kết thúc'), findsOneWidget);
    });

    testWidgets('payload selector toggles between 1 and 2 person', (tester) async {
      await tester.pumpWidget(_wrapModal(
        AddManualTripModal(vehicle: testVehicle),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Both payload options should be visible
      expect(find.text('1 người'), findsOneWidget);
      expect(find.text('2 người / Chở nặng'), findsOneWidget);

      // Tap 2 person
      await tester.tap(find.text('2 người / Chở nặng'));
      await tester.pumpAndSettle();
      // Should still be present (toggle visual state)
      expect(find.text('2 người / Chở nặng'), findsOneWidget);
    });
  });
}
