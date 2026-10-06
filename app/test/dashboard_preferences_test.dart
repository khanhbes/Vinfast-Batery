import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/dashboard_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DashboardPreferencesService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('late cache load for A cannot overwrite B tour progress', () async {
      SharedPreferences.setMockInitialValues({
        'dashboard_pending_auto_tours.a': jsonEncode(['tour_overview_v2']),
        'dashboard_completed_tours.b': jsonEncode(['tour_overview_v2']),
      });
      final prefs = await SharedPreferences.getInstance();
      final first = Completer<SharedPreferences>();
      var loads = 0;
      final service = DashboardPreferencesService(
        loadPreferences: () {
          return ++loads == 1 ? first.future : Future.value(prefs);
        },
      );
      final accountA = service.initializeForUser('a');
      await service.initializeForUser('b');
      expect(service.uid, 'b');
      expect(service.completedTours, contains('tour_overview_v2'));
      first.complete(prefs);
      await accountA;
      expect(service.uid, 'b');
      expect(service.pendingAutoTours, isEmpty);
      expect(service.completedTours, contains('tour_overview_v2'));
      expect(service.shouldAutoShow('tour_overview_v2'), isFalse);
      service.dispose();
    });

    test('Initializes with default order and no hidden widgets', () async {
      final service = DashboardPreferencesService();
      await service.initialize();

      expect(service.order, equals(DashboardWidgetId.all));
      expect(service.hidden, isEmpty);
      expect(service.visibleWidgets, equals(DashboardWidgetId.all));
    });

    test('Reorders widgets correctly', () async {
      final service = DashboardPreferencesService();
      await service.initialize();

      final firstItem = service.order[0];
      final secondItem = service.order[1];

      await service.reorder(0, 2);

      expect(service.order[0], equals(secondItem));
      expect(service.order[1], equals(firstItem));
    });

    test(
      'Toggles widget visibility and prevents hiding the last visible widget',
      () async {
        final service = DashboardPreferencesService();
        await service.initialize();

        // Hide first widget
        final toggled = service.toggleVisibility(
          DashboardWidgetId.quickActions,
          false,
        );
        expect(toggled, isTrue);
        expect(service.isVisible(DashboardWidgetId.quickActions), isFalse);
        expect(
          service.visibleWidgets.contains(DashboardWidgetId.quickActions),
          isFalse,
        );

        // Hide remaining until only 1 left
        for (final id in DashboardWidgetId.all) {
          if (id != DashboardWidgetId.efficiencyReference) {
            service.toggleVisibility(id, false);
          }
        }
        expect(service.visibleWidgets.length, equals(1));
        expect(
          service.visibleWidgets.first,
          equals(DashboardWidgetId.efficiencyReference),
        );

        // Attempt to hide the last visible widget -> must return false and fail
        final hideLast = service.toggleVisibility(
          DashboardWidgetId.efficiencyReference,
          false,
        );
        expect(hideLast, isFalse);
        expect(service.visibleWidgets.length, equals(1));
      },
    );

    test('Resets to default layout', () async {
      final service = DashboardPreferencesService();
      await service.initialize();

      service.toggleVisibility(DashboardWidgetId.quickActions, false);
      await service.reorder(0, 3);
      expect(service.hidden, isNotEmpty);

      await service.resetToDefault();
      expect(service.order, equals(DashboardWidgetId.all));
      expect(service.hidden, isEmpty);
      expect(service.visibleWidgets, equals(DashboardWidgetId.all));
    });

    test('Tracks tour completion correctly', () async {
      final service = DashboardPreferencesService();
      await service.initialize();

      expect(service.isTourCompleted('test_tour'), isFalse);
      await service.markTourCompleted('test_tour');
      expect(service.isTourCompleted('test_tour'), isTrue);

      await service.resetTours();
      expect(service.isTourCompleted('test_tour'), isFalse);
    });
  });
}
