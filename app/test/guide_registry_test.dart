import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/guide_registry.dart';

void main() {
  group('GuideRegistry', () {
    test('actions name their destination in each supported language', () {
      expect(GuideDestination.overview.actionLabel('vi'), 'Mở Tổng quan');
      expect(GuideDestination.charging.actionLabel('vi'), 'Mở Sạc pin');
      expect(GuideDestination.history.actionLabel('vi'), 'Mở Lịch sử');
      expect(GuideDestination.settings.actionLabel('vi'), 'Mở Cài đặt');
      expect(
        GuideDestination.shellySetup.actionLabel('en'),
        'Start Shelly setup',
      );
      expect(GuideDestination.batteryBot.actionLabel('vi'), 'Hỏi BatteryBot');
      for (final destination in GuideDestination.values) {
        expect(destination.actionLabel('en'), isNotEmpty);
      }
    });
    test('shows the five core guides including Shelly setup', () {
      expect(GuideRegistry.items, hasLength(5));
      expect(
        GuideRegistry.items.map((item) => item.id),
        containsAll([
          'guide_vehicle_battery',
          'guide_charging',
          'guide_history',
          'guide_settings',
          'guide_shelly_setup',
        ]),
      );
      expect(
        GuideRegistry.items
            .singleWhere((item) => item.id == 'guide_shelly_setup')
            .destination,
        GuideDestination.shellySetup,
      );
    });

    test('overview tour has four stable and complete steps', () {
      final steps = GuideRegistry.getOverviewTourSteps();
      expect(steps, hasLength(4));
      expect(
        steps.map((step) => step.anchorKey),
        contains(GuideRegistry.keyBatterySummary),
      );
      expect(
        steps.map((step) => step.anchorKey),
        contains(GuideRegistry.keyHistoryTab),
      );
      for (final step in steps) {
        expect(step.id, isNotEmpty);
        expect(step.titleVi, isNotEmpty);
        expect(step.descriptionVi, isNotEmpty);
        expect(step.titleEn, isNotEmpty);
        expect(step.descriptionEn, isNotEmpty);
      }
    });

    test(
      'Shelly guide explains current setup paths and safety without exposing identifiers',
      () {
        final guide = GuideRegistry.items.singleWhere(
          (item) => item.id == 'guide_shelly_setup',
        );
        final content = [
          guide.summaryVi,
          ...guide.stepsVi,
          guide.noteVi!,
        ].join(' ');
        expect(content, contains('Wi-Fi'));
        expect(content, contains('Shelly Cloud'));
        expect(content, contains('6 ký tự'));
        expect(content, contains('rút xe'));
        expect(content, contains('5 giây'));
        expect(content, contains('relay đã tắt'));
        expect(content, isNot(contains('Device ID')));
        expect(content, isNot(contains('Cloud Key')));
        expect(content, isNot(contains('Access Point')));
        expect(guide.destination, GuideDestination.shellySetup);
      },
    );

    test('search and category filtering return expected guides', () {
      expect(
        GuideRegistry.search('Shelly', 'vi').single.id,
        'guide_shelly_setup',
      );
      expect(GuideRegistry.search('History', 'en').single.id, 'guide_history');
      expect(GuideRegistry.search('not-a-guide', 'en'), isEmpty);
      expect(
        GuideRegistry.filterByCategory(
          GuideCategory.charging,
        ).map((guide) => guide.id),
        containsAll(['guide_charging', 'guide_shelly_setup']),
      );
    });
  });
}
