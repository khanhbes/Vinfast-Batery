import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/widgets/energy_journey_teaser_card.dart';
import 'package:vinfast_battery/features/energy_journey/energy_journey_screen.dart';
import 'package:vinfast_battery/features/energy_journey/models/energy_level.dart';
import 'package:vinfast_battery/features/energy_journey/widgets/energy_stats_overview.dart';

void main() {
  test('EnergyLevel contains exactly 36 levels across 6 tiers', () {
    expect(EnergyLevel.allLevels.length, 36);

    for (var i = 0; i < 36; i++) {
      expect(EnergyLevel.allLevels[i].level, i + 1);
    }

    expect(EnergyLevel.fromKWh(0).level, 1);
    expect(EnergyLevel.fromKWh(5).level, 2);
    expect(EnergyLevel.fromKWh(50).level, 6);
    expect(EnergyLevel.fromKWh(70).level, 7);
    expect(EnergyLevel.fromKWh(310).level, 13);
    expect(EnergyLevel.fromKWh(880).level, 19);
    expect(EnergyLevel.fromKWh(1810).level, 25);
    expect(EnergyLevel.fromKWh(3100).level, 31);
    expect(EnergyLevel.fromKWh(4450).level, 36);
  });

  testWidgets('EnergyJourneyTeaserCard renders level progress and triggers onTap', (
    tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnergyJourneyTeaserCard(
            totalKWh: 15.0,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Hành trình năng lượng'), findsOneWidget);
    expect(find.text('Cấp 3'), findsOneWidget);
    expect(find.textContaining('Đã tích luỹ 15.0 kWh'), findsOneWidget);

    await tester.tap(find.byType(EnergyJourneyTeaserCard));
    expect(tapped, isTrue);
  });

  testWidgets('EnergyStatsOverview displays green impacts', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EnergyStatsOverview(
            totalKWh: 100.0,
            co2KgSaved: 40.0,
            equivalentKmDriven: 3500.0,
            treesEquivalent: 2.0,
          ),
        ),
      ),
    );

    expect(find.text('100.0 kWh'), findsOneWidget);
    expect(find.text('40.0 kg'), findsOneWidget);
    expect(find.text('~3500 km'), findsOneWidget);
    expect(find.text('~2.0 cây xanh'), findsOneWidget);
  });

  testWidgets('EnergyJourneyScreen renders hero card, stats and milestone roadmap', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: EnergyJourneyScreen(),
        ),
      ),
    );

    expect(find.text('Hành trình năng lượng'), findsWidgets);
    expect(find.text('36 Mốc hành trình'), findsOneWidget);
    expect(find.text('Tất cả (36)'), findsOneWidget);
    expect(find.text('Tier 1: Hạt mầm'), findsOneWidget);

    // Initial level 1 milestone
    expect(find.text('Tia lửa đầu tiên'), findsWidgets);
    expect(find.text('HIỆN TẠI'), findsOneWidget);
  });
}
