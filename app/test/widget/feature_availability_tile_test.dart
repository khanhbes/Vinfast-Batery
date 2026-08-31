import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/models/feature_availability.dart';
import 'package:vinfast_battery/core/widgets/feature_availability_tile.dart';

void main() {
  testWidgets('disabled feature shows reason and does not fire action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeatureAvailabilityTile(
            icon: Icons.bolt,
            title: 'Smart Charge',
            availability: const FeatureAvailability(
              state: FeatureAvailabilityState.needsSetup,
              reason: 'Cần kết nối Shelly',
            ),
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Cần kết nối Shelly'), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    expect(tapped, isFalse);
  });

  testWidgets('ready feature exposes an enabled action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeatureAvailabilityTile(
            icon: Icons.bolt,
            title: 'Smart Charge',
            availability: const FeatureAvailability(
              state: FeatureAvailabilityState.ready,
              reason: 'Sẵn sàng',
            ),
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ListTile));
    expect(tapped, isTrue);
  });
}
