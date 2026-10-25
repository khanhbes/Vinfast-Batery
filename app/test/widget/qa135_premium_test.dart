import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/providers/appearance_provider.dart';
import 'package:vinfast_battery/core/providers/entitlement_provider.dart';
import 'package:vinfast_battery/core/services/pinova_api.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/utils/number_text.dart';
import 'package:vinfast_battery/core/widgets/luxe_submit_button.dart';
import 'package:vinfast_battery/data/models/app_appearance.dart';
import 'package:vinfast_battery/data/models/entitlement.dart';
import 'package:vinfast_battery/features/auth/auth_providers.dart';
import 'package:vinfast_battery/features/premium/premium_banner.dart';
import 'package:vinfast_battery/features/premium/premium_screen.dart';
import 'package:vinfast_battery/features/settings/appearance_screen.dart';

/// QA 135: Pinova Premium — plan model, paywall, promo, trial and gates;
/// every new screen at 320 dp with text ×1 and ×2.
Map<String, dynamic> _plan(
  String tier, {
  String status = 'none',
  bool trial = true,
  Map<String, dynamic>? promo,
}) {
  final rank = {'free': 0, 'pro': 1, 'ultra': 2}[tier]!;
  return {
    'tier': tier,
    'status': status,
    'expiresAt': tier == 'free'
        ? null
        : DateTime.now().add(const Duration(days: 5)).toIso8601String(),
    'trialAvailable': trial,
    'trialDays': 7,
    'features': {
      for (final f in PremiumFeature.values) f.id: rank >= f.tier.index,
    },
    'limits': {
      'assistant_daily': [10, 30, 100][rank],
      'history_days': rank == 0 ? 30 : null,
      'max_vehicles': [1, 2, 10][rank],
    },
    'pendingPromo': promo,
    'enforced': true,
  };
}

class _FakeBilling extends BillingRepository {
  _FakeBilling(this.current) : super(api: PinovaApi());

  Map<String, dynamic> current;
  int trials = 0;
  final codes = <String>[];

  @override
  Future<Entitlement> me() async => Entitlement.fromMap(current);

  @override
  Future<Entitlement> startTrial() async {
    trials++;
    if (current['trialAvailable'] != true) {
      throw const PinovaApiException(
        'trialUsed',
        message: 'Tài khoản đã dùng thử Premium.',
        status: 409,
      );
    }
    current = _plan('ultra', status: 'trial', trial: false);
    return Entitlement.fromMap(current);
  }

  @override
  Future<PromoQuote> redeemPromo(String code) async {
    codes.add(code);
    if (code != 'TET2027') {
      throw const PinovaApiException(
        'promoInvalid',
        message: 'Mã khuyến mãi không đúng.',
        status: 404,
      );
    }
    return PromoQuote.fromMap({
      'code': 'TET2027',
      'percentOff': 20,
      'validTo': '2027-02-01T00:00:00Z',
      'prices': {
        'pro': {
          'year': {'base': 249000, 'final': 199000},
        },
        'ultra': {
          'year': {'base': 449000, 'final': 359000},
        },
      },
    })!;
  }

  @override
  Future<void> clearPromo() async {}
}

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  double scale,
  _FakeBilling billing, {
  double height = 2600,
}) async {
  await tester.binding.setSurfaceSize(Size(320, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        billingRepositoryProvider.overrideWithValue(billing),
        currentUidProvider.overrideWith((ref) => 'u1'),
      ],
      child: MaterialApp(
        theme: LuxeTheme.data(),
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: page!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1500));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('plan model', () {
    test('mirrors the server table and parses the server answer', () {
      final free = Entitlement.fromMap(_plan('free'));
      expect(free.tier, PlanTier.free);
      expect(free.allows(PremiumFeature.targetCharging), isFalse);
      expect(free.allows(PremiumFeature.nightCharging), isFalse);
      expect(free.assistantDaily, 10);
      expect(free.historyDays, 30);
      expect(free.maxVehicles, 1);
      final pro = Entitlement.fromMap(_plan('pro', status: 'active'));
      expect(pro.allows(PremiumFeature.targetCharging), isTrue);
      expect(pro.allows(PremiumFeature.batteryHealth), isTrue);
      expect(pro.allows(PremiumFeature.nightCharging), isFalse);
      expect(pro.historyDays, isNull);
      final ultra = Entitlement.fromMap(_plan('ultra', status: 'trial'));
      expect(ultra.isTrial, isTrue);
      expect(ultra.allows(PremiumFeature.nightCharging), isTrue);
      expect(ultra.daysLeft(DateTime.now()), inInclusiveRange(4, 5));
      expect(Entitlement.fromMap(ultra.toMap()).tier, PlanTier.ultra);
    });

    test('nothing is locked before the server answers or on an old server', () {
      expect(const Entitlement().allows(PremiumFeature.nightCharging), isTrue);
      expect(const Entitlement().historyDays, isNull);
      expect(
        Entitlement.legacyServer.allows(PremiumFeature.learningTrain),
        isTrue,
      );
    });

    test('prices have no lifetime plan and the yearly saving is honest', () {
      expect(PlanTable.price(PlanTier.pro, PlanPeriod.month), 29000);
      expect(PlanTable.price(PlanTier.pro, PlanPeriod.year), 249000);
      expect(PlanTable.price(PlanTier.ultra, PlanPeriod.month), 49000);
      expect(PlanTable.price(PlanTier.ultra, PlanPeriod.year), 449000);
      expect(PlanPeriod.values.map((p) => p.id), ['month', 'year']);
      expect(PlanTable.yearlySavingPct(PlanTier.pro), 28);
      expect(PlanTable.yearlySavingPct(PlanTier.ultra), 24);
    });

    test('promo quote parses only the plans it applies to', () {
      final quote = PromoQuote.fromMap({
        'code': 'X1',
        'percentOff': 20,
        'prices': {
          'pro': {
            'year': {'base': 249000, 'final': 199000},
          },
        },
      })!;
      expect(quote.finalPrice(PlanTier.pro, PlanPeriod.year), 199000);
      expect(quote.finalPrice(PlanTier.pro, PlanPeriod.month), isNull);
      expect(quote.finalPrice(PlanTier.ultra, PlanPeriod.year), isNull);
      expect(PromoQuote.fromMap({'percentOff': 1}), isNull);
    });
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('paywall fits 320 dp at text ×$scale', (tester) async {
      final billing = _FakeBilling(_plan('free'));
      await _pump(
        tester,
        const PremiumScreen(),
        scale,
        billing,
        height: scale == 1 ? 3200 : 7000,
      );
      expect(tester.takeException(), isNull);
      // QA 136: one plan at a time, Ultra first; the trial at the bottom.
      expect(find.text('Pinova Ultra'), findsOneWidget);
      expect(find.text('ĐỀ XUẤT'), findsOneWidget);
      expect(find.text('Bạn đang dùng gói Free'), findsOneWidget);
      expect(find.byKey(const ValueKey('premium-trial-ultra')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('premium-tier-pro')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Pinova Pro'), findsOneWidget);
      expect(find.text('Lộ trình'), findsWidgets);
      // The comparison opens on demand and fits too.
      await tester.ensureVisible(
        find.byKey(const ValueKey('premium-compare-toggle')),
      );
      await tester.tap(find.byKey(const ValueKey('premium-compare-toggle')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Giao diện Aurora'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('trial opens Ultra and the card shows the current plan', (
    tester,
  ) async {
    final billing = _FakeBilling(_plan('free'));
    await _pump(tester, const PremiumScreen(), 1, billing, height: 3200);
    await tester.tap(find.byKey(const ValueKey('premium-trial-ultra')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(billing.trials, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Đang dùng thử Ultra'), findsOneWidget);
    expect(find.text('Bạn đang dùng gói này.'), findsOneWidget);
    expect(find.byKey(const ValueKey('premium-trial-ultra')), findsNothing);
  });

  testWidgets('a promo code strikes the base price; a wrong one explains', (
    tester,
  ) async {
    final billing = _FakeBilling(_plan('free'));
    await _pump(tester, const PremiumScreen(), 1, billing, height: 3200);
    await tester.tap(find.byKey(const ValueKey('premium-promo-toggle')));
    await tester.pump(const Duration(milliseconds: 400));
    final input = find.byKey(const ValueKey('premium-promo-input'));
    await tester.enterText(input, 'SAI123');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('premium-promo-apply')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Mã khuyến mãi không đúng.'), findsOneWidget);
    await tester.enterText(input, 'TET2027');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('premium-promo-apply')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 2));
    expect(billing.codes, ['SAI123', 'TET2027']);
    expect(find.byKey(const ValueKey('premium-promo-applied')), findsOneWidget);
    // Yearly Ultra is selected by default: the struck base and the new price.
    expect(find.text(formatVnd(359000)), findsOneWidget);
    expect(find.text(formatVnd(449000)), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('premium-tier-pro')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(formatVnd(199000)), findsOneWidget);
    expect(find.text(formatVnd(249000)), findsOneWidget);
  });

  testWidgets('submit button ignores taps while busy and returns on failure', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: LuxeTheme.data(),
        home: Scaffold(
          body: LuxeSubmitButton(
            label: 'Lưu',
            onPressed: () async {
              calls++;
              await Future<void>.delayed(const Duration(milliseconds: 200));
              return false;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Lưu'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('submit-busy')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Lưu'), findsOneWidget);
  });

  testWidgets('Free keeps the default layouts and explains the lock', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app_appearance_v1_u1':
          '{"dashboardStyle":"lcd","chargeStyle":"bar","confirmStyle":"hold"}',
    });
    final billing = _FakeBilling(_plan('free'));
    await _pump(tester, const AppearanceScreen(), 1, billing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppearanceScreen)),
    );
    final drawn = container.read(effectiveAppearanceProvider);
    expect(drawn.dashboard, DashboardStyle.luxe);
    expect(drawn.charge, ChargeStyle.dial);
    // The ON confirmation stays the owner's choice on every plan.
    expect(drawn.confirm, ChargeConfirmStyle.hold);
    expect(
      find.byKey(const ValueKey('appearance-premium-notice')),
      findsOneWidget,
    );
    // QA 136: a locked layout is faded and ignores taps; its tag opens
    // Pinova Premium.
    await tester.tap(
      find.byKey(const ValueKey('appearance-dashboard-lcd')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PremiumScreen), findsNothing);
    expect(find.byKey(const ValueKey('premium-gate-sheet')), findsNothing);
    expect(container.read(appearanceProvider).dashboard, DashboardStyle.lcd);
    await tester.tap(
      find.byKey(const ValueKey('premium-locked-tag-appearance')).first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byType(PremiumScreen), findsOneWidget);
  });

  testWidgets('Pro draws the chosen layouts', (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_appearance_v1_u1':
          '{"dashboardStyle":"lcd","chargeStyle":"bar","confirmStyle":"slide"}',
    });
    final billing = _FakeBilling(_plan('pro', status: 'active'));
    await _pump(tester, const AppearanceScreen(), 1, billing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppearanceScreen)),
    );
    expect(
      container.read(effectiveAppearanceProvider).dashboard,
      DashboardStyle.lcd,
    );
    expect(
      find.byKey(const ValueKey('appearance-premium-notice')),
      findsNothing,
    );
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('settings banner fits 320 dp at text ×$scale', (tester) async {
      final billing = _FakeBilling(_plan('free'));
      await _pump(
        tester,
        const Scaffold(
          body: Padding(padding: EdgeInsets.all(16), child: PremiumBanner()),
        ),
        scale,
        billing,
        height: 800,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Nâng cấp Pinova Premium'), findsOneWidget);
    });
  }
}
