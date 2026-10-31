import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/features/battery_monitor/battery_health_screen.dart';
import 'package:vinfast_battery/features/battery_monitor/charge_habits_screen.dart';

/// QA 140 (items 1, 9): the overall assessment at 320 dp, text ×1/×2;
/// Free sees the score and one comment, Pro the charts and the schedule.
Map<String, dynamic> _data({required bool full}) => {
  'sessions': 11,
  'enough': true,
  'minSessions': 3,
  'full': full,
  'score': 50,
  'grade': 'poor',
  'stats': {
    'perWeek': 1.4,
    'avgStartPct': 8,
    'avgEndPct': 100,
    'avgDepthPct': 92,
    'equivalentCycles': 10.1,
    'fullShare': 1.0,
    'lowStartShare': 1.0,
    'nightShare': 0.0,
    'kWh': 9.9,
    'confirmedShare': 1.0,
  },
  'comments': [
    {'level': 'warn', 'text': '100% số lần sạc lên gần 100%.'},
    if (full) {'level': 'warn', 'text': '100% số lần bắt đầu dưới 15%.'},
  ],
  'suggestions': ['Hằng ngày dừng ở 80–90%.'],
  'charts': full
      ? {
          'weekdayHour': [
            for (var d = 0; d < 7; d++)
              [for (var h = 0; h < 24; h++) h == 7 ? 2 : 0],
          ],
          'startPct': [11, 0, 0, 0, 0, 0, 0, 0, 0, 0],
          'endPct': [0, 0, 0, 0, 0, 0, 0, 0, 0, 11],
          'weeklyKWh': [
            {'week': '2026-10-19', 'kWh': 4.5},
            {'week': '2026-10-26', 'kWh': 5.4},
          ],
        }
      : null,
  'schedule': full
      ? {
          'startHour': 7,
          'weekdays': [0, 2, 4],
          'typicalStartPct': 8,
          'targetPct': 85,
          'estimatedMinutes': 233,
        }
      : null,
};

Future<void> _pump(WidgetTester tester, bool full, double scale) async {
  await tester.binding.setSurfaceSize(Size(320, scale == 1 ? 2400 : 5200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chargeAssessmentProvider('v1').overrideWith(
          (ref) async => ChargeAssessment.fromMap(_data(full: full)),
        ),
      ],
      child: MaterialApp(
        theme: LuxeTheme.data(),
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: page!,
        ),
        home: const ChargeHabitsScreen(vehicleId: 'v1'),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1500));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scale in [1.0, 2.0]) {
    testWidgets('Pro sees charts and the schedule at 320 dp ×$scale', (
      tester,
    ) async {
      await _pump(tester, true, scale);
      expect(tester.takeException(), isNull);
      expect(find.text('Cần thay đổi'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('GIỜ CẮM SẠC THEO THỨ'), findsOneWidget);
      expect(find.byKey(const ValueKey('habits-remind')), findsOneWidget);
      expect(find.byKey(const ValueKey('habits-apply-night')), findsOneWidget);
      expect(find.textContaining('lúc 07:00'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Free sees the score and one comment at 320 dp ×$scale', (
      tester,
    ) async {
      await _pump(tester, false, scale);
      expect(tester.takeException(), isNull);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('GIỜ CẮM SẠC THEO THỨ'), findsNothing);
      expect(find.byKey(const ValueKey('habits-remind')), findsNothing);
      // The teaser of what Pro adds (its lock follows the plan).
      expect(find.textContaining('Biểu đồ giờ sạc'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('Free health hides the trend and the guided test', () {
    final health = BatteryHealth.fromMap({
      'nominalCapacityWh': 2400,
      'estimate': {'sohPct': 93.0, 'capacityWh': 2232, 'samples': 3},
      'trend': const [],
      'test': null,
      'full': false,
    });
    expect(health.full, isFalse);
    expect(BatteryHealth.fromMap({'estimate': null}).full, isTrue);
  });
}
