import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/models/onboarding_draft.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/utils/number_text.dart';
import 'package:vinfast_battery/core/widgets/bootstrap_splash.dart';
import 'package:vinfast_battery/features/auth/authenticated_prefetch.dart';
import 'package:vinfast_battery/features/battery_monitor/battery_health_screen.dart';

/// QA 162 (owner's choice, 16/11/2026): one reading of the capacity left
/// everywhere, the figure as measured (it may pass 100), wear only beyond
/// the error, the latest charges with why each counts; the splash hands
/// over when its motion ends and the profile is read meanwhile.
BatteryHealth _health({
  double soh = 98.8,
  double uncertainty = 2.2,
  int samples = 6,
  Map<String, Object?>? test,
  List<Map<String, Object?>> charges = const [],
}) => BatteryHealth.fromMap({
  'nominalCapacityWh': 2400,
  'estimate': {
    'sohPct': soh,
    'capacityWh': 2400 * soh / 100,
    'samples': samples,
    'confidence': 'high',
  },
  'spread': {
    'uncertaintyPct': uncertainty,
    'lowPct': soh - uncertainty,
    'highPct': soh + uncertainty,
  },
  'test': test,
  'trend': const [],
  'charges': charges,
  'full': true,
});

Future<void> _pump(
  WidgetTester tester,
  BatteryHealth health,
  double scale,
) async {
  await tester.binding.setSurfaceSize(Size(320, scale == 1 ? 2400 : 4800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        batteryHealthProvider('v1').overrideWith((ref) async => health),
      ],
      child: MaterialApp(
        theme: LuxeTheme.data(),
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: page!,
        ),
        home: const BatteryHealthScreen(vehicleId: 'v1'),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1500));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('HealthVerdict', () {
    test('within the error there is no wear to report', () {
      final v = HealthVerdict.of(_health())!;
      expect(v.label, 'Pin còn như mới');
      expect(v.detail, 'Chưa thấy chai rõ (trong sai số ±2%)');
      expect(v.basis, 'Dựa trên 6 lần sạc · sai số ±2%');
      expect(v.short, '6 lần sạc · ±2%');
      expect(
        v.capacityText,
        'khoảng 2${thousandsSeparator}320–2${thousandsSeparator}420 Wh / '
        '2${thousandsSeparator}400 Wh danh định',
      );
    });

    test('wear beyond the error is said, with one scale everywhere', () {
      expect(HealthVerdict.of(_health(soh: 90))!.detail, 'Đã chai khoảng 10%');
      expect(HealthVerdict.of(_health(soh: 90))!.label, 'Pin còn tốt');
      expect(
        HealthVerdict.of(_health(soh: 74))!.label,
        'Pin đã chai, nên theo dõi',
      );
      expect(
        HealthVerdict.of(_health(soh: 60))!.label,
        'Pin chai nhiều, nên đưa xe đi kiểm tra',
      );
    });

    test('above the rating is shown as measured', () {
      final v = HealthVerdict.of(_health(soh: 102.4))!;
      expect(v.pct, 102.4);
      expect(v.label, 'Pin còn như mới');
      expect(v.detail, startsWith('Bằng hoặc hơn danh định'));
    });

    test('a recent guided test is named in the basis', () {
      final at = DateTime.now().subtract(const Duration(days: 5));
      final v = HealthVerdict.of(
        _health(
          test: {
            'sohPct': 97.0,
            'capacityWh': 2328,
            'at': at.toIso8601String(),
          },
        ),
      )!;
      expect(v.basis, endsWith('· có bài kiểm tra'));
      // The headline is the merged estimate, not the test alone.
      expect(v.pct, 98.8);
    });

    test('no estimate or no rating: nothing is guessed', () {
      expect(
        HealthVerdict.of(BatteryHealth.fromMap({'nominalCapacityWh': 2400})),
        isNull,
      );
      expect(
        HealthVerdict.of(
          BatteryHealth.fromMap({
            'estimate': {'sohPct': 98.0, 'capacityWh': 2352},
          }),
        ),
        isNull,
      );
    });
  });

  final charges = [
    {
      'at': '2026-11-06T16:50:00Z',
      'startPct': 9,
      'endPct': 81,
      'sohPct': 98.3,
      'trust': 'high',
      'used': true,
      'reason': null,
    },
    {
      'at': '2026-11-09T16:45:00Z',
      'startPct': 9,
      'endPct': 88,
      'sohPct': 89.3,
      'trust': 'medium',
      'used': false,
      'reason': 'outlier',
    },
    {
      'at': '2026-11-12T10:00:00Z',
      'startPct': 60,
      'endPct': 72,
      'sohPct': null,
      'trust': 'low',
      'used': false,
      'reason': 'short',
    },
  ];

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Sức khỏe pin at 320 dp x$scale: one reading and every charge',
      (tester) async {
        await _pump(tester, _health(soh: 102.4, charges: charges), scale);
        expect(tester.takeException(), isNull);
        expect(find.text('102%'), findsOneWidget);
        expect(find.byKey(const ValueKey('health-label')), findsOneWidget);
        expect(find.text('Pin còn như mới'), findsOneWidget);
        expect(find.text('Từng lần sạc'.toUpperCase()), findsOneWidget);
        expect(find.text('Ngay sau lần sạc đầy, tin cậy nhất'), findsOneWidget);
        expect(
          find.text('Lệch nhiều so với các lần khác, không tính'),
          findsOneWidget,
        );
        expect(find.text('Quá ngắn để tính'), findsOneWidget);
      },
    );
  }

  testWidgets('the splash hands over when its motion ends (4.2 s)', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: BootstrapSplash(message: '', onFinished: () => finished = true),
      ),
    );
    await tester.pump(const Duration(milliseconds: 4000));
    await tester.pump();
    expect(finished, isFalse);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(finished, isTrue);
    await tester.pump(const Duration(seconds: 2));
  });

  test(
    'the profile read during the splash is taken once, for its account',
    () async {
      final reads = <String>[];
      final profile = Completer<DocumentSnapshot<Map<String, dynamic>>>();
      AuthenticatedPrefetch.readProfile = (uid) {
        reads.add(uid);
        return profile.future;
      };
      AuthenticatedPrefetch.readDraft = (uid) async => null as OnboardingDraft?;
      addTearDown(AuthenticatedPrefetch.clear);
      AuthenticatedPrefetch.start('a');
      AuthenticatedPrefetch.start('a');
      expect(reads, ['a']);
      expect(AuthenticatedPrefetch.take('b'), isNull);
      AuthenticatedPrefetch.start('a');
      expect(AuthenticatedPrefetch.take('a'), isNotNull);
      expect(AuthenticatedPrefetch.take('a'), isNull);
    },
  );
}
