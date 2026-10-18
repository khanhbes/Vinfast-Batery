import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/assistant_context_coordinator.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/features/ai/widgets/timed_charging_section_v2.dart';

/// QA 130 polish: the resting BatteryBot covered the "sức khỏe pin" tile,
/// and the timed choice reset to 2 giờ after a charge ended.
void main() {
  testWidgets('the bot tucks in after a pause and comes back for a bubble', (
    tester,
  ) async {
    final bot = AssistantContextCoordinator(
      idleDockAfter: const Duration(seconds: 6),
    );
    addTearDown(bot.dispose);
    expect(bot.isDocked, isFalse);
    await tester.pump(const Duration(seconds: 6));
    expect(bot.isDocked, isTrue, reason: 'idle at rest');
    bot.showBubble('Pin xe chỉ còn 15%.');
    expect(bot.isDocked, isFalse, reason: 'a bubble needs the full button');
    await tester.pump(const Duration(seconds: 7));
    expect(bot.isBubbleVisible, isFalse);
    await tester.pump(const Duration(seconds: 6));
    expect(bot.isDocked, isTrue);
    bot.setDocked(false); // scrolled up
    expect(bot.isDocked, isFalse);
    await tester.pump(const Duration(seconds: 6));
    expect(bot.isDocked, isTrue);
  });

  testWidgets('the timed choice survives a rebuild', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Widget section(Key key) => MaterialApp(
      theme: LuxeTheme.data(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TimedChargingSectionV2(
            key: key,
            onStart: (_) async {},
            onOff: () {},
            readyForControl: true,
          ),
        ),
      ),
    );
    await tester.pumpWidget(section(const ValueKey('a')));
    await tester.pump();
    await tester.tap(find.text('30 phút'));
    await tester.pump();
    expect(find.text('Sạc 30 phút'), findsOneWidget);
    // A finished charge rebuilds the section from scratch.
    await tester.pumpWidget(section(const ValueKey('b')));
    await tester.pump();
    expect(find.text('Sạc 30 phút'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getInt('timed_charge_minutes'),
      30,
    );
  });
}
