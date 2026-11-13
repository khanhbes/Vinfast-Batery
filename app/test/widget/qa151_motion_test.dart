import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/assistant_context_coordinator.dart';
import 'package:vinfast_battery/core/services/luxe_feedback.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/theme/plan_style.dart';
import 'package:vinfast_battery/data/models/entitlement.dart';
import 'package:vinfast_battery/core/widgets/battery_bot_mascot.dart';
import 'package:vinfast_battery/core/widgets/luxe_expand_route.dart';
import 'package:vinfast_battery/core/widgets/luxe_kit.dart';
import 'package:vinfast_battery/core/widgets/luxe_skeleton.dart';
import 'package:vinfast_battery/core/widgets/luxe_submit_button.dart';
import 'package:vinfast_battery/features/ai/widgets/active_charging_card_v2.dart';
import 'package:vinfast_battery/features/ai/widgets/charge_ceremony.dart';
import 'package:vinfast_battery/features/battery_monitor/widgets/health_trend_chart.dart';

/// QA 151: the charge-start and charge-finished scenes, the current that
/// follows the real power, and the loading skeleton.
void main() {
  final events = <String>[];

  setUp(() {
    events.clear();
    LuxeFeedback.probe = events.add;
  });

  tearDown(() {
    LuxeFeedback.probe = null;
    ChargeCeremony.dismiss();
  });

  Future<BuildContext> host(
    WidgetTester tester, {
    bool reduce = false,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: LuxeTheme.data(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 720),
            disableAnimations: reduce,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    return context;
  }

  group('ChargeCeremony.started', () {
    testWidgets('plays once for 1.5 s, takes no touches, then is gone', (
      tester,
    ) async {
      final context = await host(tester);
      ChargeCeremony.started(context);
      expect(events, ['chargeStarted']);
      await tester.pump();
      expect(ChargeCeremony.isPlaying, isTrue);
      // A second call while it plays does not stack another scene.
      ChargeCeremony.started(context);
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      expect(find.byType(IgnorePointer), findsWidgets);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump();
      expect(ChargeCeremony.isPlaying, isFalse);
    });

    testWidgets('Giảm chuyển động: feedback only, nothing drawn', (
      tester,
    ) async {
      final context = await host(tester, reduce: true);
      ChargeCeremony.started(context);
      await tester.pump();
      expect(events, ['chargeStarted']);
      expect(ChargeCeremony.isPlaying, isFalse);
    });
  });

  group('ChargeCeremony.finished', () {
    Future<void> play(BuildContext context) => ChargeCeremony.finished(
      context,
      startPercent: 22,
      endPercent: 80,
      energyKwh: 1.53,
      durationText: '3 giờ 12 phút',
    );

    testWidgets('fills to the level reached, counts the energy, completes', (
      tester,
    ) async {
      final context = await host(tester);
      var done = false;
      play(context).then((_) => done = true);
      expect(events, ['chargeDone']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1900));
      expect(tester.takeException(), isNull);
      expect(find.text('80%'), findsOneWidget);
      expect(find.text('Đã sạc xong'), findsOneWidget);
      expect(find.textContaining('1.53 kWh · 3 giờ 12 phút'), findsOneWidget);
      expect(find.text('Mức pin là ước tính'), findsOneWidget);
      expect(done, isFalse);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(done, isTrue);
      expect(ChargeCeremony.isPlaying, isFalse);
    });

    testWidgets('a tap skips it', (tester) async {
      final context = await host(tester);
      var done = false;
      play(context).then((_) => done = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(160, 360));
      await tester.pump();
      expect(done, isTrue);
      expect(ChargeCeremony.isPlaying, isFalse);
    });

    testWidgets('320 dp at text x2 does not overflow', (tester) async {
      final context = await host(tester, scale: 2);
      play(context);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1900));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
    });

    testWidgets('Giảm chuyển động: completes at once, nothing drawn', (
      tester,
    ) async {
      final context = await host(tester, reduce: true);
      var done = false;
      play(context).then((_) => done = true);
      await tester.pump();
      expect(done, isTrue);
      expect(events, ['chargeDone']);
      expect(find.text('Đã sạc xong'), findsNothing);
    });
  });

  group('ActiveChargingCardV2.flowPeriod', () {
    test('no current, no motion', () {
      expect(ActiveChargingCardV2.flowPeriod(0), isNull);
      expect(ActiveChargingCardV2.flowPeriod(14.9), isNull);
      expect(ActiveChargingCardV2.flowPeriod(double.nan), isNull);
    });

    test('more power runs faster, within 1.2 s and 4.8 s', () {
      final slow = ActiveChargingCardV2.flowPeriod(120)!;
      final usual = ActiveChargingCardV2.flowPeriod(400)!;
      final fast = ActiveChargingCardV2.flowPeriod(900)!;
      expect(usual, const Duration(milliseconds: 2400));
      expect(slow, const Duration(milliseconds: 4800));
      expect(fast, const Duration(milliseconds: 1200));
      expect(ActiveChargingCardV2.flowPeriod(2500), fast);
    });

    test('a flickering reading keeps the same step', () {
      expect(
        ActiveChargingCardV2.flowPeriod(441),
        ActiveChargingCardV2.flowPeriod(446),
      );
    });
  });

  group('Pinova Bot expressions', () {
    Widget bot(BatteryBotMood mood, {bool reduce = false, double? avatar}) =>
        MaterialApp(
          theme: LuxeTheme.data(),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Center(
              child: avatar == null
                  ? BatteryBotMascot(mood: mood)
                  : BatteryBotMascot(
                      mood: mood,
                      displayMode: BatteryBotDisplayMode.avatar,
                      customWidth: avatar,
                    ),
            ),
          ),
        );

    testWidgets('every mood draws at every size', (tester) async {
      for (final mood in BatteryBotMood.values) {
        for (final avatar in <double?>[null, 24, 40, 96]) {
          await tester.pumpWidget(bot(mood, reduce: true, avatar: avatar));
          expect(tester.takeException(), isNull, reason: '$mood $avatar');
        }
      }
    });

    testWidgets('a new mood reacts once, then is still', (tester) async {
      await tester.pumpWidget(bot(BatteryBotMood.idle));
      await tester.pumpWidget(bot(BatteryBotMood.worried));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('Giảm chuyển động: the face changes without moving', (
      tester,
    ) async {
      await tester.pumpWidget(bot(BatteryBotMood.idle, reduce: true));
      await tester.pumpWidget(bot(BatteryBotMood.celebrating, reduce: true));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('resting face: reaction, then charging, then the hour', (
      tester,
    ) async {
      final c = AssistantContextCoordinator();
      addTearDown(c.dispose);
      final noon = DateTime(2026, 11, 12, 12);
      final night = DateTime(2026, 11, 12, 23, 30);
      expect(c.restingMood(charging: false, now: noon), BatteryBotMood.idle);
      expect(c.restingMood(charging: false, now: night), BatteryBotMood.sleepy);
      expect(
        c.restingMood(charging: true, now: night),
        BatteryBotMood.charging,
      );
      c.react(BatteryBotMood.celebrating);
      expect(
        c.restingMood(charging: true, now: noon),
        BatteryBotMood.celebrating,
      );
      await tester.pump(AssistantContextCoordinator.reactionHold);
      expect(c.restingMood(charging: false, now: noon), BatteryBotMood.idle);
    });
  });

  group('QA 151 round 2', () {
    testWidgets('a page grows out of the tapped tile and folds back', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: LuxeTheme.data(),
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    LuxeExpandOrigin.mark(context);
                    Navigator.push(
                      context,
                      LuxeExpandRoute<void>(
                        builder: (_) => const Scaffold(body: Text('Trang mới')),
                        origin: LuxeExpandOrigin.take(),
                      ),
                    );
                  },
                  child: const Text('Mở'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ClipPath), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text('Trang mới'), findsOneWidget);
      // The origin is used once.
      expect(LuxeExpandOrigin.take(), isNull);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.text('Mở'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the health trend draws itself once, then is still', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: LuxeTheme.data(),
          home: Scaffold(
            body: HealthTrendChart(
              points: [
                (DateTime(2026, 11, 1), 98.0),
                (DateTime(2026, 11, 5), 104.0),
                (DateTime(2026, 11, 9), 97.5),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a save that worked is one firm tap, a refused one two knocks',
      (tester) async {
        var ok = true;
        await tester.pumpWidget(
          MaterialApp(
            theme: LuxeTheme.data(),
            home: Scaffold(
              body: Center(
                child: LuxeSubmitButton(
                  label: 'Lưu',
                  onPressed: () async => ok,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Lưu'));
        await tester.pump();
        await tester.pump();
        expect(events, ['confirm']);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        ok = false;
        events.clear();
        await tester.tap(find.byType(LuxeSubmitButton));
        await tester.pump();
        await tester.pump();
        expect(events, ['error']);
      },
    );
  });

  group('QA 151 round 3', () {
    testWidgets('scrollTitle appears once the heading has scrolled away', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: LuxeTheme.data(),
          home: LuxeScaffold(
            scrollTitle: 'AI cá nhân',
            body: ListView(
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 60, child: Text('Dòng $i')),
              ],
            ),
          ),
        ),
      );
      double opacity() => tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.text('AI cá nhân'),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;
      expect(opacity(), 0);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(opacity(), 0);
    });

    testWidgets('a quiet card has a fainter edge than a plain one', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: LuxeTheme.data(),
          home: const Scaffold(
            body: Column(
              children: [
                LuxeGlass(key: ValueKey('plain'), child: Text('a')),
                LuxeGlass(
                  key: ValueKey('quiet'),
                  quiet: true,
                  child: Text('b'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      double edge(String key) {
        final box = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return ((box.decoration! as BoxDecoration).border! as Border)
            .top
            .color
            .a;
      }

      expect(edge('quiet'), lessThan(edge('plain')));
    });
  });

  test('QA 152: one colour scale for a battery level', () {
    const plan = Color(0xFF123456);
    expect(LuxeColors.level(5, plan), LuxeColors.danger);
    expect(LuxeColors.level(10, plan), LuxeColors.champagne);
    expect(LuxeColors.level(20, plan), LuxeColors.champagne);
    expect(LuxeColors.level(21, plan), plan);
  });

  test('QA 152: Pinova Bot is drawn from the LUXE palette only', () {
    for (final file in [
      'lib/core/widgets/battery_bot_mascot.dart',
      'lib/core/widgets/bot_face.dart',
    ]) {
      expect(
        RegExp(r'Color\(0x').hasMatch(File(file).readAsStringSync()),
        isFalse,
        reason: file,
      );
    }
  });

  testWidgets('LuxeSkeleton: named for TalkBack, still with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LuxeTheme.data(),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: LuxeSkeleton.list(label: 'Đang tải lịch sử sạc'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Đang tải lịch sử sạc'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  group('QA 152 round 3', () {
    Widget host(Widget child, {PlanTier tier = PlanTier.free}) => MaterialApp(
      theme: LuxeTheme.data(tier: tier),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: SizedBox(width: 320, height: 200, child: child)),
      ),
    );

    test('Free has a warm silver light, not an emerald one', () {
      expect(PlanStyle.free.glow, isNot(LuxeColors.emerald));
      expect(PlanStyle.free.accent, LuxeColors.platinumHi);
    });

    test('the type scale has no near-duplicate steps', () {
      expect(LuxeText.scale, isNot(contains(11)));
      expect(LuxeText.scale, isNot(contains(15)));
    });

    testWidgets('the backdrop paints every mood and settles', (tester) async {
      for (final mood in LuxeBackdropMood.values) {
        await tester.pumpWidget(host(LuxeBackdrop(mood: mood)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('only Ultra draws the signature edge', (tester) async {
      Finder edge() => find.descendant(
        of: find.byType(LuxeGlass),
        matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.foregroundPainter != null,
        ),
      );
      const card = LuxeGlass(signature: true, child: Text('xe'));
      await tester.pumpWidget(host(card));
      expect(edge(), findsNothing);
      await tester.pumpWidget(host(card, tier: PlanTier.ultra));
      await tester.pumpAndSettle();
      expect(edge(), findsOneWidget);
    });
  });
}
