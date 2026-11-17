import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/features/tips/tip_library.dart';
import 'package:vinfast_battery/features/tips/tips_screen.dart';

/// QA 164 (17/11/2026, owner: Mẹo nhỏ more professional, consistent and
/// friendly): one tip of the day everywhere, tips under their group with a
/// preview, a dot on unread ones, how many have been read.
final _assetJson = File('assets/tips/tips_vi.json').readAsStringSync();

TipLibrary _library() => TipLibrary(
  asset: () async => _assetJson,
  remote: () async => throw Exception('offline'),
);

Future<void> _pump(WidgetTester tester, Widget home, {double scale = 1}) async {
  await tester.binding.setSurfaceSize(Size(320, scale == 1 ? 1600 : 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: LuxeTheme.data(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the tip of the day stays the same after tips are read', () async {
    final library = _library();
    await library.load();
    final morning = DateTime(2026, 11, 17, 7);
    final first = library.today(now: morning)!;
    // Reading it (and others) used to change "today's" pick mid-day.
    await library.markSeen(first.id);
    for (final tip in library.tips.take(5)) {
      await library.markSeen(tip.id);
    }
    expect(
      library.today(now: morning.add(const Duration(hours: 6)))!.id,
      first.id,
    );
    // Another phone screen asking with the vehicle's battery: still the same.
    expect(library.today(now: morning, batteryPercent: 25)!.id, first.id);
    // Kept across a restart.
    final again = _library();
    await again.load();
    expect(again.today(now: morning)!.id, first.id);
    // A new day, a new choice.
    expect(library.today(now: morning.add(const Duration(days: 1))), isNotNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('groups, preview, unread dot and read count at x$scale', (
      tester,
    ) async {
      final library = _library();
      await tester.runAsync(library.load);
      await _pump(tester, TipsScreen(library: library), scale: scale);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('tips-group-drive')), findsOneWidget);
      expect(find.byKey(const ValueKey('tips-filters')), findsOneWidget);
      final total = library.tips.length;
      expect(find.text('Đã đọc 0/$total mẹo'), findsOneWidget);
      const id = 'drive-eco-city';
      expect(find.byKey(const ValueKey('tip-unread-$id')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tip-$id')).first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('tip-unread-$id')), findsNothing);
      expect(find.text('Đã đọc 1/$total mẹo'), findsOneWidget);
      // One group: a flat list without group headers.
      await tester.ensureVisible(
        find.byKey(const ValueKey('tips-filter-charge')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tips-filter-charge')));
      await tester.pump();
      expect(find.byKey(const ValueKey('tips-group-drive')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
