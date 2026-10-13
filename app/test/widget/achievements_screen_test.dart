import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/features/achievements/achievements_screen.dart';
import 'package:vinfast_battery/features/achievements/controllers/achievements_controller.dart';
import 'package:vinfast_battery/features/achievements/models/achievement.dart';
import 'package:vinfast_battery/features/achievements/services/achievement_signals.dart';
import 'package:vinfast_battery/features/achievements/widgets/achievement_unlock_ceremony.dart';
import 'package:vinfast_battery/features/achievements/widgets/achievements_teaser_card.dart';

import '../unit/achievements_engine_test.dart' show FakeRemote, session;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AchievementSignals.instance.drain();
  });

  Future<AchievementsController> seeded(WidgetTester tester) async {
    late AchievementsController c;
    await tester.runAsync(() async {
      c = AchievementsController(uid: 'w1', remote: FakeRemote());
      await c.load();
      await c.ingest([
        for (var i = 0; i < 6; i++)
          session('s$i', startedAt: '2030-03-0${i + 1}T15:30:00Z'),
      ]);
      c.takeCelebrations();
    });
    return c;
  }

  Widget host(AchievementsController c, Widget home, {double scale = 1}) =>
      ProviderScope(
        overrides: [achievementsControllerProvider.overrideWith((ref) => c)],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: home,
        ),
      );

  testWidgets('collection fits a small phone and celebrates the first visit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = await seeded(tester);
    await tester.pumpWidget(host(c, const AchievementsScreen(), scale: 1.3));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    // Opening the collection unlocks "Nhà sưu tầm" with its ceremony.
    expect(find.text('THÀNH TỰU MỚI'), findsOneWidget);
    expect(find.text('Nhà sưu tầm'), findsWidgets);
    await tester.tap(find.text('Tuyệt vời'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('THÀNH TỰU MỚI'), findsNothing);
    expect(find.text('Thành tựu'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('SẮP MỞ KHÓA'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('SẮP MỞ KHÓA'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The ProviderScope owns (and disposes) the controller.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a secret medal opens its detail without revealing it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = await seeded(tester);
    await tester.pumpWidget(host(c, const AchievementsScreen()));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 3));
    if (find.text('Tuyệt vời').evaluate().isNotEmpty) {
      await tester.tap(find.text('Tuyệt vời'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
    // Secret medals close the collection; their titles stay hidden.
    final outer = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    outer.jumpTo(outer.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('???'), findsNWidgets(7));
    // Dismiss any unlock ceremony (e.g. "Nhà sưu tầm") still on screen.
    while (find.text('Tuyệt vời').evaluate().isNotEmpty) {
      await tester.tap(find.text('Tuyệt vời'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.tap(find.text('???').first);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Thành tựu bí mật'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The ProviderScope owns (and disposes) the controller.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a large batch plays one summary ceremony', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => AchievementUnlockCeremony.show(
              context,
              achievementCatalog.take(9).toList(),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Mở khóa 9 thành tựu'), findsOneWidget);
    expect(find.text('Tuyệt vời'), findsOneWidget);
    await tester.tap(find.text('Tuyệt vời'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Mở khóa 9 thành tựu'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('teaser shows rank, points and the next target', (tester) async {
    final c = await seeded(tester);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AchievementsTeaserCard(state: c.state, onTap: () => taps++),
        ),
      ),
    );
    expect(find.text('Thành tựu'), findsOneWidget);
    expect(find.text(c.state.rank.name), findsOneWidget);
    expect(find.textContaining('Sắp mở:'), findsOneWidget);
    await tester.tap(find.byType(AchievementsTeaserCard));
    expect(taps, 1);
    c.dispose();
  });
}
