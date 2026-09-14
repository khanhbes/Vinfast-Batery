import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/guide_registry.dart';

void main() {
  group('GuideRegistry Tests', () {
    test('Registry contains required guides across categories', () {
      expect(GuideRegistry.items, isNotEmpty);

      final categories = GuideRegistry.items.map((i) => i.category).toSet();
      expect(categories.contains(GuideCategory.gettingStarted), isTrue);
      expect(categories.contains(GuideCategory.vehicle), isTrue);
      expect(categories.contains(GuideCategory.charging), isTrue);
      expect(categories.contains(GuideCategory.trips), isTrue);
      expect(categories.contains(GuideCategory.ai), isTrue);
      expect(categories.contains(GuideCategory.troubleshooting), isTrue);
    });

    test('Overview tour steps are well-defined with anchor keys', () {
      final steps = GuideRegistry.getOverviewTourSteps();
      expect(steps.length, equals(6));

      for (final step in steps) {
        expect(step.id, isNotEmpty);
        expect(step.titleVi, isNotEmpty);
        expect(step.descriptionVi, isNotEmpty);
        expect(step.titleEn, isNotEmpty);
        expect(step.descriptionEn, isNotEmpty);
      }
    });

    test('Search functionality finds relevant items', () {
      final resVi = GuideRegistry.search('Sạc', 'vi');
      expect(resVi, isNotEmpty);

      final resEn = GuideRegistry.search('Charge', 'en');
      expect(resEn, isNotEmpty);

      final emptyRes = GuideRegistry.search('xyzNonExistentTerm123', 'vi');
      expect(emptyRes, isEmpty);
    });

    test('Category filtering functions correctly', () {
      final vehicleGuides = GuideRegistry.filterByCategory(GuideCategory.vehicle);
      expect(vehicleGuides, isNotEmpty);
      expect(vehicleGuides.every((g) => g.category == GuideCategory.vehicle), isTrue);
    });
  });
}
