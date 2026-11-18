import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/dev_view.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/utils/number_text.dart';
import 'package:vinfast_battery/features/ai/widgets/battery_reading_sheet.dart';
import 'package:vinfast_battery/features/battery_monitor/battery_health_screen.dart';

/// QA 166 (18/11/2026, owner's choice): the capacity measured, not assumed.
/// What more charges cannot reduce is shown apart in "Chế độ develop"; the
/// owner keeps the figure and one line; a reading at a low % can say the
/// scooter just shut off. QA 166 (2): a charge to full after the gauge
/// drifted is listed, not counted; the charger's rating caps the factor.
Map<String, dynamic> _map({bool rated = false}) => {
  'nominalCapacityWh': 2400,
  'estimate': {
    'sohPct': 98.4,
    'capacityWh': 2362,
    'samples': 8,
    'confidence': 'medium',
  },
  'spread': {
    'uncertaintyPct': 0.6,
    'lowPct': 97.8,
    'highPct': 99.0,
    'totalLowPct': 87.9,
    'totalHighPct': 99.6,
    'totalPct': 5.9,
  },
  'systematic': {
    'factor': rated ? 0.842 : 0.9,
    'factorLow': 0.81,
    'factorHigh': rated ? 0.873 : 0.9,
    'factorMeasured': false,
    if (rated) 'factorSource': 'rated',
    if (rated) 'chargerRatedW': 400,
    if (rated) 'wallPowerW': 444.1,
    'nominalPct': 2.0,
    'nominalSource': 'catalog',
    'meterPct': 1.0,
    'cutoffPct': 0,
  },
  'gaugeDrift': {
    'lastPct': 14.2,
    'sessions': 5,
    'fulls': 2.77,
    'at': '2026-11-17T14:56:13Z',
    'perFullPct': 5.12,
  },
  'sigmas': {
    'points': {'high': 0.47, 'medium': 3.82, 'low': 6.84},
    'charges': {'high': 2, 'medium': 4, 'low': 4},
  },
  'trend': [
    {'at': '2026-09-12T00:00:00Z', 'sohPct': 98.9},
    {'at': '2026-11-06T00:00:00Z', 'sohPct': 98.3},
  ],
  'charges': [
    {
      'at': '2026-11-06T00:00:00Z',
      'startPct': 9,
      'endPct': 81,
      'sohPct': 98.3,
      'used': true,
      'trust': 'high',
      'sigmaPct': 0.9,
    },
    {
      'at': '2026-11-10T00:00:00Z',
      'startPct': 0,
      'endPct': 100,
      'sohPct': 98.0,
      'used': true,
      'trust': 'high',
      'kind': 'full_range',
      'test': true,
      'sigmaPct': 4.9,
    },
    {
      'at': '2026-11-17T00:00:00Z',
      'startPct': 27,
      'endPct': 100,
      'sohPct': 80.1,
      'used': false,
      'reason': 'drift',
      'trust': 'low',
    },
    {
      'at': '2026-08-10T00:00:00Z',
      'startPct': 20,
      'endPct': 80,
      'sohPct': 104.0,
      'used': false,
      'reason': 'epoch',
      'trust': 'low',
    },
  ],
  'full': true,
  'tracking': {
    'status': 'ready',
    'since': '2026-09-12T00:00:00Z',
    'until': '2026-10-23T00:00:00Z',
    'relativePct': 99.5,
    'uncertaintyPct': 1.1,
    'referenceErrorPct': 0.9,
    'monthly': [],
  },
};

Future<void> _pump(
  WidgetTester tester,
  double scale, {
  bool rated = false,
}) async {
  await tester.binding.setSurfaceSize(Size(320, scale == 1 ? 3000 : 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        batteryHealthProvider('v1').overrideWith(
          (ref) async => BatteryHealth.fromMap(_map(rated: rated)),
        ),
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

class _Opener extends StatefulWidget {
  const _Opener(this.open);
  final Future<Object?> Function(BuildContext context) open;

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  Object? result;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: const ValueKey('open'),
        onPressed: () async {
          final value = await widget.open(context);
          setState(() => result = value);
        },
        child: Text('result: $result'),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DevView.instance.debugSet(unlocked: false, on: false);
  });

  test('the model reads the measured and the assumed parts', () {
    final health = BatteryHealth.fromMap(_map());
    expect(health.totalLowPct, 87.9);
    expect(health.totalHighPct, 99.6);
    expect(health.systematic!.factorMeasured, isFalse);
    expect(health.systematic!.factorLow, 0.81);
    expect(health.sigmaPoints['low'], 6.84);
    expect(health.tracking!.referenceErrorPct, 0.9);
    final notes = {for (final c in health.charges) c.startPct: c.note};
    // QA 166 (2): the shut-off follows the gauge, no "đo trọn".
    expect(notes[0], 'Từ lúc xe tự ngắt tới đầy');
    expect(notes[27], 'Sạc tới đầy khi đồng hồ đã trôi, không tính');
    expect(notes[20], 'Trước khi đổi bộ sạc hoặc pin, không tính');
    expect(health.gaugeDrift!.lastPct, 14.2);
    expect(health.gaugeDrift!.sessions, 5);
    expect(health.systematic!.fromRating, isFalse);
    final rated = BatteryHealth.fromMap(_map(rated: true)).systematic!;
    expect(rated.fromRating, isTrue);
    expect(rated.chargerRatedW, 400);
    expect(rated.factorHigh, 0.873);
    // The capacity range is the server's own (lower side wider).
    final verdict = HealthVerdict.of(health)!;
    expect(verdict.capacityText, contains(groupThousands(2110)));
    expect(verdict.capacityText, contains(groupThousands(2390)));
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('owners see no assumption text (x$scale)', (tester) async {
      await _pump(tester, scale);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('health-soh')), findsOneWidget);
      expect(find.text('Hệ số ổ cắm → pin'), findsNothing);
      expect(find.text('Sai số đồng hồ (điểm)'), findsNothing);
    });

    testWidgets('develop mode shows what was measured and what was not '
        '(x$scale)', (tester) async {
      DevView.instance.debugSet(unlocked: true, on: true);
      addTearDown(() => DevView.instance.debugSet(unlocked: false, on: false));
      await _pump(tester, scale);
      expect(tester.takeException(), isNull);
      expect(find.text('Hệ số ổ cắm → pin'), findsOneWidget);
      // QA 129: a dot for decimals, the same as every other figure.
      expect(find.text('0.90 · chưa đo (0.81–0.90)'), findsOneWidget);
      expect(find.text('98.4% · ${groupThousands(2362)} Wh'), findsOneWidget);
      expect(
        find.text('${groupThousands(2400)} Wh · danh mục ±2%'),
        findsOneWidget,
      );
      expect(find.text('Khoảng gồm hệ số'), findsOneWidget);
      expect(find.text('sau đầy 0.5 · vừa 3.8 · lâu 6.8'), findsOneWidget);
      expect(find.textContaining('danh mục ±2%'), findsOneWidget);
      expect(find.textContaining('Sạc đầy một lần'), findsOneWidget);
      expect(find.textContaining('Quét đồng hồ ngay trước'), findsOneWidget);
      expect(find.byKey(const ValueKey('health-test-charge')), findsOneWidget);
      // QA 166 (2): the gauge's drift at the charger's full signal, and a
      // charge to full after it drifted listed but not counted.
      expect(find.text('Đồng hồ trôi khi sạc đầy'), findsOneWidget);
      expect(find.text('14.2% sau 5 lần sạc (17/11)'), findsOneWidget);
      expect(
        find.textContaining('Sạc tới đầy khi đồng hồ đã trôi'),
        findsOneWidget,
      );
      expect(find.textContaining('đo trọn'), findsNothing);
      expect(find.textContaining('mốc thật'), findsNothing);
    });

    testWidgets('develop mode shows the factor capped by the charger '
        '(x$scale)', (tester) async {
      DevView.instance.debugSet(unlocked: true, on: true);
      addTearDown(() => DevView.instance.debugSet(unlocked: false, on: false));
      await _pump(tester, scale, rated: true);
      expect(tester.takeException(), isNull);
      expect(find.text('0.84 · từ bộ sạc 400 W (0.81–0.87)'), findsOneWidget);
      expect(find.textContaining('chưa đo'), findsNothing);
    });

    testWidgets('a low reading can say the scooter just shut off (x$scale)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: LuxeTheme.data(),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 640),
                textScaler: TextScaler.linear(scale),
              ),
              child: _Opener(
                (context) =>
                    BatteryReadingSheet.show(context, requireSoc: true),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await _settle(tester);
      final soc = find.byKey(const ValueKey('reading-soc'));
      await tester.enterText(soc, '30');
      await tester.pump();
      expect(find.byKey(const ValueKey('reading-cutoff')), findsNothing);
      await tester.enterText(soc, '0');
      await tester.pump();
      final cutoff = find.byKey(const ValueKey('reading-cutoff'));
      expect(cutoff, findsOneWidget);
      await tester.ensureVisible(cutoff);
      await tester.pump();
      await tester.tap(cutoff);
      await tester.pump();
      final save = find.byKey(const ValueKey('reading-save'));
      await tester.ensureVisible(save);
      await tester.pump();
      await tester.tap(save);
      await _settle(tester);
      expect(find.textContaining('cutoff: true'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
