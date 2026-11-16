import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/constants/app_constants.dart';
import 'package:vinfast_battery/core/providers/app_state_providers.dart';
import 'package:vinfast_battery/core/services/assistant_context_coordinator.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/features/ai/assistant_settings_screen.dart';
import 'package:vinfast_battery/features/ai/bot_release.dart';
import 'package:vinfast_battery/features/ai/services/assistant_api.dart';
import 'package:vinfast_battery/features/settings/about_screen.dart';
import 'package:vinfast_battery/features/tips/tip.dart';
import 'package:vinfast_battery/features/tips/tip_library.dart';
import 'package:vinfast_battery/features/tips/tips_screen.dart';

/// QA 163 (owner's choice, 16/11/2026): "Mẹo nhỏ" in Tiện ích, one tip a
/// day from Pinova Bot, Pinova Bot's own settings and version.
final _assetJson = File('assets/tips/tips_vi.json').readAsStringSync();

TipLibrary _library({Map<String, dynamic>? remote}) => TipLibrary(
  asset: () async => _assetJson,
  remote: () async => remote ?? (throw Exception('offline')),
);

Tip _tip(String id, {String when = 'any', String applies = 'all'}) => Tip(
  id: id,
  category: 'drive',
  title: id,
  body: 'b',
  when: when,
  appliesTo: applies,
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

  group('TipPicker', () {
    final morning = DateTime(2026, 11, 16, 7);
    test('picks a tip for the moment, unseen first, stable for the day', () {
      final tips = [
        _tip('a'),
        _tip('m1', when: 'morning'),
        _tip('m2', when: 'morning'),
      ];
      final first = TipPicker.pick(tips, now: morning)!;
      expect(first.when, 'morning');
      expect(
        TipPicker.pick(tips, now: morning.add(const Duration(hours: 2)))!.id,
        first.id,
      );
      final other = TipPicker.pick(tips, now: morning, seen: {first.id})!;
      expect(other.id, isNot(first.id));
      expect(other.when, 'morning');
    });

    test('a tip for the other kind of battery is never told', () {
      final tips = [
        _tip('li', applies: 'lithium'),
        _tip('pb', applies: 'leadAcid'),
      ];
      expect(TipPicker.pick(tips, now: morning, leadAcid: true)!.id, 'pb');
      expect(TipPicker.pick(tips, now: morning, leadAcid: false)!.id, 'li');
      expect(TipPicker.pick(const [], now: morning), isNull);
    });

    test('low battery and charging pick their own tips', () {
      final tips = [
        _tip('any'),
        _tip('low', when: 'lowBattery'),
        _tip('after', when: 'afterCharge'),
      ];
      final noon = DateTime(2026, 12, 1, 12);
      expect(TipPicker.pick(tips, now: noon, batteryPercent: 20)!.id, 'low');
      expect(TipPicker.pick(tips, now: noon, charging: true)!.id, 'after');
    });
  });

  test('the library reads the bundled list and keeps seen and saved', () async {
    final library = _library();
    await library.load();
    expect(library.tips.length, greaterThanOrEqualTo(30));
    await library.markSeen('drive-eco-city');
    await library.toggleSaved('charge-daily-80');
    await library.setDailyEnabled(false);
    final again = _library();
    await again.load();
    expect(again.seen, contains('drive-eco-city'));
    expect(again.saved, contains('charge-daily-80'));
    expect(again.dailyEnabled, isFalse);
  });

  test('the server list replaces the bundled one (admin edits)', () async {
    final library = _library(
      remote: {
        'tips': [
          {
            'id': 'x',
            'category': 'app',
            'title': 'Từ máy chủ',
            'body': 'b',
            'source': {'name': 'Admin'},
          },
        ],
      },
    );
    await library.load();
    await pumpEventQueue();
    expect(library.tips.single.title, 'Từ máy chủ');
  });

  group('the daily tip', () {
    VehicleModel vehicle() => VehicleModel(
      vehicleId: 'v1',
      vehicleName: 'Feliz',
      currentBattery: 60,
      currentOdo: 1200,
      hasBatteryData: true,
    );

    test(
      'once a day, never on the Charge tab, and it can be turned off',
      () async {
        final library = _library();
        await library.load();
        final noon = DateTime(2026, 12, 1, 12);
        final coordinator = AssistantContextCoordinator(tips: library);
        addTearDown(coordinator.dispose);
        expect(
          coordinator.evaluateContext(
            vehicle: vehicle(),
            currentTab: AppTab.charge,
            now: noon,
          ),
          isFalse,
        );
        expect(
          coordinator.evaluateContext(
            vehicle: vehicle(),
            currentTab: 0,
            now: noon,
          ),
          isTrue,
        );
        expect(coordinator.bubbleText, startsWith('Mẹo: '));
        expect(coordinator.bubbleTipId, isNotNull);
        coordinator.dismissBubble();
        final later = AssistantContextCoordinator(tips: library);
        addTearDown(later.dispose);
        expect(
          later.evaluateContext(vehicle: vehicle(), currentTab: 0, now: noon),
          isFalse,
        );
        final off = _library();
        await off.load();
        await off.setDailyEnabled(false);
        SharedPreferences.setMockInitialValues({});
        final quiet = AssistantContextCoordinator(tips: off);
        addTearDown(quiet.dispose);
        expect(
          quiet.evaluateContext(vehicle: vehicle(), currentTab: 0, now: noon),
          isFalse,
        );
      },
    );
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('Mẹo nhỏ at 320 dp x$scale: today, filter, search, save', (
      tester,
    ) async {
      final library = _library();
      await tester.runAsync(library.load);
      await _pump(tester, TipsScreen(library: library), scale: scale);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('tips-today')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tips-filter-weather')));
      await tester.pump();
      expect(find.text('Tránh đi qua chỗ ngập sâu'), findsWidgets);
      expect(find.text('Hằng ngày sạc đến 80–90%'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tips-filter-all')));
      await tester.enterText(
        find.byKey(const ValueKey('tips-search')),
        'bo sac chinh hang',
      );
      await tester.pump();
      expect(find.text('Dùng bộ sạc chính hãng'), findsWidgets);
      await tester.tap(
        find.byKey(const ValueKey('tip-save-charge-original-charger')),
      );
      await tester.pump();
      expect(library.saved, contains('charge-original-charger'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a tip opened from the bubble is on top and open', (
    tester,
  ) async {
    final library = _library();
    await tester.runAsync(library.load);
    await _pump(
      tester,
      TipsScreen(library: library, highlightId: 'storage-14-days'),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tips-today')),
        matching: find.text('Cất xe trên 2 tuần: sạc khoảng 50%'),
      ),
      findsOneWidget,
    );
    expect(library.seen, contains('storage-14-days'));
  });

  group('Pinova Bot settings', () {
    late List<http.Request> sent;
    Map<String, dynamic> state = {};

    AssistantApi api() => AssistantApi(
      tokenResolver: () async => 't',
      client: MockClient((request) async {
        sent.add(request);
        if (request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['persona'] == 'concierge') {
            return http.Response(
              jsonEncode({
                'success': false,
                'error': {'code': 'premiumRequired'},
              }),
              403,
            );
          }
          state = {...state, ...body};
        }
        return http.Response(
          jsonEncode({'success': true, 'data': state}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    setUp(() {
      sent = [];
      state = {
        'learningEnabled': true,
        'persona': 'companion',
        'length': 'medium',
        'callMe': '',
        'aboutMe': '',
        'followUps': true,
        'conciergeAllowed': false,
        'quota': {'used': 7, 'limit': 10},
        'botVersion': '3.2.0',
      };
      AppConstants.setCustomApiBaseUrl('https://api.example.test');
    });
    tearDown(() => AppConstants.setCustomApiBaseUrl(''));

    for (final scale in [1.0, 2.0]) {
      testWidgets('every group at 320 dp x$scale, saved on the server', (
        tester,
      ) async {
        final library = _library();
        await tester.runAsync(library.load);
        await _pump(
          tester,
          AssistantSettingsScreen(api: api(), tips: library),
          scale: scale,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('bot-persona-concise')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        expect(jsonDecode(sent.last.body), {'persona': 'concise'});
        final list = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        final daily = find.byKey(const ValueKey('bot-daily-tip'));
        await tester.scrollUntilVisible(daily, 300, scrollable: list);
        await tester.ensureVisible(daily);
        await tester.pump();
        await tester.tap(daily);
        await tester.pump();
        expect(library.dailyEnabled, isFalse);
        final quota = find.text('Hôm nay còn 3/10 tin');
        await tester.scrollUntilVisible(quota, 300, scrollable: list);
        expect(quota, findsOneWidget);
        final version = find.text('Pinova Bot ${PinovaBotRelease.current}');
        await tester.scrollUntilVisible(version, 300, scrollable: list);
        expect(version, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('without the server the phone settings still work', (
      tester,
    ) async {
      AppConstants.setCustomApiBaseUrl('');
      final library = _library();
      await tester.runAsync(library.load);
      await _pump(
        tester,
        AssistantSettingsScreen(api: AssistantApi(), tips: library),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('bot-settings-offline')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('bot-daily-tip')), findsOneWidget);
    });
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('Giới thiệu at 320 dp x$scale: both versions and what is new', (
      tester,
    ) async {
      await _pump(
        tester,
        AboutScreen(serverVersion: Future.value('3.2.0')),
        scale: scale,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.text('Pinova Bot ${PinovaBotRelease.current}'),
        findsOneWidget,
      );
      expect(find.text('Máy chủ Bot 3.2.0'), findsOneWidget);
      expect(
        find.text(PinovaBotRelease.releases.first.changes.first),
        findsOneWidget,
      );
    });
  }

  test('the bot version and its notes agree', () {
    expect(PinovaBotRelease.releases.first.version, PinovaBotRelease.current);
    for (final release in PinovaBotRelease.releases) {
      expect(release.changes, isNotEmpty);
      for (final line in release.changes) {
        expect(line.contains('~'), isFalse);
      }
    }
  });
}
