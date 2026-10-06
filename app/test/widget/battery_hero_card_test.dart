import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/widgets/battery_hero_card.dart';

void main() {
  testWidgets('BatteryHeroCard renders metrics, delta, badges and presets', (
    tester,
  ) async {
    double target = 80;
    double current = 35;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => BatteryHeroCard(
              currentPercent: current,
              targetPercent: target,
              isCharging: false,
              onTargetChanged: (val) => setState(() => target = val),
              onCurrentChanged: (val) => setState(() => current = val),
            ),
          ),
        ),
      ),
    );

    // Assert dual metrics
    expect(find.text('35'), findsOneWidget);
    expect(find.text('Mức pin hiện tại'), findsOneWidget);
    expect(find.text('(chạm để sửa)'), findsOneWidget);
    expect(find.text('+45%'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(find.text('Khuyên dùng'), findsWidgets);

    // Floating badges above track
    expect(find.text('Hiện tại 35%'), findsOneWidget);
    expect(find.text('Sạc đến 80%'), findsOneWidget);

    // Presets
    expect(find.text('80%'), findsWidgets);
    expect(find.text('· Bảo vệ pin'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('· Cân bằng'), findsOneWidget);
    expect(find.text('100%'), findsWidgets);
    expect(find.text('· Đầy pin'), findsOneWidget);

    // Tap 90% preset
    await tester.tap(find.text('90%'));
    await tester.pump();

    expect(target, 90);
    expect(find.text('90'), findsOneWidget);
    expect(find.text('+55%'), findsOneWidget);
    expect(find.text('Sạc đến 90%'), findsOneWidget);
  });

  testWidgets('BatteryHeroCard shows LFP warning when target is 100%', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BatteryHeroCard(
            currentPercent: 40,
            targetPercent: 100,
            isCharging: false,
            onTargetChanged: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.text('Pin LFP chỉ nên sạc đến 100% mỗi 1-2 tuần để cân bằng cell.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping current SOC opens EditCurrentBatterySheet and updates value', (
    tester,
  ) async {
    double current = 35;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => BatteryHeroCard(
              currentPercent: current,
              targetPercent: 80,
              isCharging: false,
              onTargetChanged: (_) {},
              onCurrentChanged: (val) => setState(() => current = val),
            ),
          ),
        ),
      ),
    );

    // Tap current SOC to open sheet
    await tester.tap(find.text('Mức pin hiện tại'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Chỉnh mức pin hiện tại'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);

    // Tap 50% quick shortcut
    await tester.tap(find.text('50%'));
    await tester.pump();

    // Confirm button
    await tester.tap(find.text('XÁC NHẬN MỨC PIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(current, 50);
  });
}
