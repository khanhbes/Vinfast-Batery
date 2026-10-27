import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/providers/entitlement_provider.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/theme/plan_style.dart';
import 'package:vinfast_battery/data/models/app_appearance.dart';
import 'package:vinfast_battery/data/models/entitlement.dart';
import 'package:vinfast_battery/features/ai/widgets/history_luxe_widgets.dart';
import 'package:vinfast_battery/features/home/widgets/luxe_dashboard_cards.dart';
import 'package:vinfast_battery/features/maintenance/widgets/odo_widgets.dart';
import 'package:vinfast_battery/features/premium/plan_tag.dart';
import 'package:vinfast_battery/features/premium/premium_gate.dart';
import 'package:vinfast_battery/features/premium/premium_screen.dart';

/// QA 136: Lộ trình is Pro, locked features are faded with only their plan
/// tag tappable (and their screens refuse too), each plan has its look, the
/// month chart is bars, and the ODO drum is exact at rest.
Entitlement _plan(PlanTier tier) => Entitlement.fromMap({
  'tier': tier.id,
  'status': tier == PlanTier.free ? 'none' : 'active',
  'trialAvailable': tier == PlanTier.free,
  'features': {
    for (final f in PremiumFeature.values) f.id: tier.covers(f.tier),
  },
  'limits': {
    'assistant_daily': [10, 30, 100][tier.index],
  },
  'enforced': true,
});

class _FixedPlan extends EntitlementNotifier {
  _FixedPlan(this.plan);
  final Entitlement plan;

  @override
  Entitlement build() => plan;

  @override
  Future<void> refresh() async {}
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  PlanTier tier = PlanTier.free,
  double scale = 1,
  Size size = const Size(320, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        entitlementProvider.overrideWith(() => _FixedPlan(_plan(tier))),
      ],
      child: MaterialApp(
        theme: LuxeTheme.data(tier: tier),
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            // The Ultra clock stays still in tests (pumpAndSettle).
            disableAnimations: true,
          ),
          child: page!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1600));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Lộ trình is a Pro feature; the aurora look is Ultra', () {
    expect(PremiumFeature.tripEstimate.tier, PlanTier.pro);
    expect(_plan(PlanTier.pro).allows(PremiumFeature.tripEstimate), isTrue);
    expect(_plan(PlanTier.free).allows(PremiumFeature.tripEstimate), isFalse);
    expect(_plan(PlanTier.pro).allows(PremiumFeature.ultraLook), isFalse);
    expect(_plan(PlanTier.ultra).allows(PremiumFeature.ultraLook), isTrue);
  });

  test('each plan has its own theme; status colours stay', () {
    final free = LuxeTheme.data();
    final pro = LuxeTheme.data(tier: PlanTier.pro);
    final ultra = LuxeTheme.data(tier: PlanTier.ultra);
    expect(free.extension<PlanStyle>()!.tier, PlanTier.free);
    // QA 139: Free accents in platinum; emerald means "verified" only.
    expect(free.colorScheme.primary, LuxeColors.platinumHi);
    expect(pro.colorScheme.primary, PlanStyle.pro.accent);
    expect(ultra.extension<PlanStyle>()!.isUltra, isTrue);
    expect(ultra.colorScheme.error, LuxeColors.danger);
    expect(identical(LuxeTheme.data(tier: PlanTier.ultra), ultra), isTrue);
  });

  test('Ultra effects are saved with the appearance (on by default)', () {
    expect(const AppAppearance().ultraEffects, isTrue);
    final off = const AppAppearance().copyWith(ultraEffects: false);
    expect(AppAppearance.fromMap(off.toMap()).ultraEffects, isFalse);
    expect(AppAppearance.fromMap({}).ultraEffects, isTrue);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('plan tags fit 320 dp at text ×$scale', (tester) async {
      await _pump(
        tester,
        const Wrap(
          spacing: 8,
          children: [
            PlanTag(tier: PlanTier.free),
            PlanTag(tier: PlanTier.pro, large: true),
            PlanTag(tier: PlanTier.ultra, large: true),
          ],
        ),
        scale: scale,
      );
      expect(find.text('FREE'), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
      expect(find.text('ULTRA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the current plan tag follows the account', (tester) async {
    await _pump(tester, const CurrentPlanTag(), tier: PlanTier.ultra);
    expect(find.byKey(const ValueKey('plan-tag-ultra')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-tag-ultra')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byType(PremiumScreen), findsOneWidget);
  });

  testWidgets('a locked entry is faded, ignores taps, its tag opens Premium', (
    tester,
  ) async {
    var opened = 0;
    await _pump(
      tester,
      PremiumLocked(
        feature: PremiumFeature.tripEstimate,
        child: SizedBox(
          width: 240,
          height: 80,
          child: ElevatedButton(
            onPressed: () => opened++,
            child: const Text('Lộ trình'),
          ),
        ),
      ),
    );
    final filter = tester.widget<ColorFiltered>(
      find.ancestor(
        of: find.text('Lộ trình'),
        matching: find.byType(ColorFiltered),
      ),
    );
    expect(filter.colorFilter, PremiumLocked.lockedFilter);
    await tester.tap(find.text('Lộ trình'), warnIfMissed: false);
    await tester.pump();
    expect(opened, 0);
    await tester.tap(
      find.byKey(const ValueKey('premium-locked-tag-trip_estimate')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byType(PremiumScreen), findsOneWidget);
    expect(find.text('Pinova Pro'), findsOneWidget, reason: 'its plan first');
  });

  testWidgets('Pro opens Lộ trình normally', (tester) async {
    var opened = 0;
    await _pump(
      tester,
      PremiumLocked(
        feature: PremiumFeature.tripEstimate,
        child: TextButton(
          onPressed: () => opened++,
          child: const Text('Lộ trình'),
        ),
      ),
      tier: PlanTier.pro,
    );
    expect(find.byType(Opacity), findsNothing);
    await tester.tap(find.text('Lộ trình'));
    expect(opened, 1);
  });

  testWidgets('a feature screen reached any other way shows Premium', (
    tester,
  ) async {
    await _pump(
      tester,
      const PremiumRequired(
        feature: PremiumFeature.nightCharging,
        child: Text('màn sạc đêm'),
      ),
      tier: PlanTier.pro,
      size: const Size(320, 2400),
    );
    expect(find.text('màn sạc đêm'), findsNothing);
    expect(find.byType(PremiumScreen), findsOneWidget);
  });

  testWidgets('the Overview Lộ trình tile is locked on Free', (tester) async {
    var trips = 0;
    await _pump(
      tester,
      LuxeQuickActions(
        onTrip: () => trips++,
        onMaintenance: () {},
        onBatteryMonitor: () {},
      ),
    );
    await tester.tap(find.text('Lộ trình'), warnIfMissed: false);
    await tester.pump();
    expect(trips, 0);
    expect(
      find.byKey(const ValueKey('premium-locked-tag-trip_estimate')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('month bars fit 320 dp and read a day at text ×$scale', (
      tester,
    ) async {
      final buckets = List<double>.filled(31, 0)
        ..[4] = 900
        ..[22] = 1970;
      await _pump(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: HistoryEnergyBars(
            buckets: buckets,
            labels: [for (var i = 1; i <= 31; i++) i % 5 == 0 ? '$i' : ''],
            details: [for (var i = 1; i <= 31; i++) 'Ngày $i/10'],
            totalWh: 2870,
            caption: 'điện nạp · 25 ngày',
            highlightIndex: 24,
          ),
        ),
        tier: PlanTier.ultra,
        scale: scale,
      );
      expect(find.text('2.9'), findsOneWidget);
      expect(find.textContaining('Nhiều nhất: Ngày 23/10'), findsOneWidget);
      final chart = find.byKey(const ValueKey('history-energy-bars'));
      final box = tester.getRect(chart);
      // Tap the 5th bar.
      await tester.tapAt(
        Offset(box.left + box.width * 4.5 / 31, box.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Ngày 5/10 · 0.90 kWh'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('the ODO drum is exact at rest and carries like a real one', () {
    // 4 958 km: the thousands drum shows 4, not a "5" rolling in.
    expect(OdometerDrum.drumDigit(4958, 3), (digit: 4, turn: 0.0));
    expect(OdometerDrum.drumDigit(4958, 2), (digit: 9, turn: 0.0));
    expect(OdometerDrum.drumDigit(4958, 0), (digit: 8, turn: 0.0));
    // Only while 4 999 rolls to 5 000 do the upper drums turn together.
    final rolling = OdometerDrum.drumDigit(4999.5, 3);
    expect(rolling.digit, 4);
    expect(rolling.turn, closeTo(0.5, 1e-9));
    expect(OdometerDrum.drumDigit(4999.5, 2).turn, closeTo(0.5, 1e-9));
    expect(OdometerDrum.drumDigit(4998.5, 3).turn, 0.0);
  });

  testWidgets('the Ultra clock runs only when asked and stops cleanly', (
    tester,
  ) async {
    final seen = <double>[];
    Widget host(bool running) => MaterialApp(
      home: PlanMotionHost(
        running: running,
        child: PlanFlow(
          builder: (context, phase) {
            seen.add(phase);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(host(true));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(seen.toSet().length, greaterThan(3), reason: 'colours move');
    await tester.pumpWidget(host(false));
    final before = seen.length;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(seen.length - before, lessThanOrEqualTo(1), reason: 'still');
  });
}
