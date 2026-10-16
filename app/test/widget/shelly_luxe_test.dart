import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/theme/cockpit_design_system.dart';
import 'package:vinfast_battery/core/widgets/luxe_kit.dart';
import 'package:vinfast_battery/data/services/shelly_connection_coordinator.dart';
import 'package:vinfast_battery/features/smart_charging/shelly_connect_screen.dart';

/// Task 120 — LUXE Shelly connection flow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'developerModeUnlocked': false});
    await ShellyConnectionCoordinator.shared.restore();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('Admin code uses engraved slots at 320dp x$scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const ShellyConnectScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      final adminStep = find.text('Qua Bước 3: Mã Admin');
      await tester.scrollUntilVisible(
        adminStep,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(adminStep);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(adminStep);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byType(LuxeSegmented<int>, skipOffstage: false),
        findsOneWidget,
      );
      final field = find.byType(TextField, skipOffstage: false);
      expect(field, findsOneWidget);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'ab9');
      await tester.pump(const Duration(milliseconds: 300));
      // Slots mirror the code in upper case.
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Cockpit surfaces render as LUXE glass', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CockpitSurface(child: Text('a')),
              CockpitSurface(highlight: true, child: Text('b')),
              CockpitSectionLabel('Nhóm'),
            ],
          ),
        ),
      ),
    );
    final boxes = tester.widgetList<DecoratedBox>(
      find.ancestor(of: find.text('a'), matching: find.byType(DecoratedBox)),
    );
    final decoration = boxes.first.decoration as BoxDecoration;
    expect(decoration.gradient, isNotNull);
    expect(find.text('NHÓM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
