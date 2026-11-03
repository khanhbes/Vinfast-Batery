import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/constants/app_constants.dart';
import 'package:vinfast_battery/core/providers/entitlement_provider.dart';
import 'package:vinfast_battery/core/services/pinova_api.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/utils/number_text.dart';
import 'package:vinfast_battery/data/models/entitlement.dart';
import 'package:vinfast_battery/features/auth/auth_providers.dart';
import 'package:vinfast_battery/features/premium/payment_history_screen.dart';
import 'package:vinfast_battery/features/premium/payment_sheet.dart';

/// QA 145: paying with MoMo — the server's quote, opening MoMo, waiting for
/// the answer, the payment history; 320 dp at text ×1 and ×2.
Map<String, dynamic> _plan(String tier, {String status = 'active'}) => {
  'tier': tier,
  'status': tier == 'free' ? 'none' : status,
  'expiresAt': tier == 'free' ? null : '2026-12-03T03:00:00Z',
  'trialAvailable': false,
  'features': <String, bool>{},
  'limits': <String, int?>{},
  'enforced': true,
  'payments': {'momo': true},
};

Map<String, dynamic> _order(String status, {int amount = 49000}) => {
  'orderId': 'PNV261103100000ABCDEF',
  'tier': 'ultra',
  'period': 'month',
  'amount': amount,
  'status': status,
  'method': amount == 0 ? 'free' : 'momo',
  'createdAt': '2026-11-03T03:00:00Z',
  'paidAt': status == 'paid' ? '2026-11-03T03:01:00Z' : null,
  'deeplink': 'momo://app?order=1',
  'payUrl': 'https://pay.test/1',
};

class _FakeBilling extends BillingRepository {
  _FakeBilling({this.quoteMap, this.free = false}) : super(api: PinovaApi());

  Map<String, dynamic>? quoteMap;
  bool free;
  String orderStatus = 'pending';
  int checkouts = 0;
  int checks = 0;
  List<Map<String, dynamic>> history = [];

  @override
  Future<Entitlement> me() async => Entitlement.fromMap(_plan('free'));

  @override
  Future<PaymentQuote> quote(PlanTier tier, PlanPeriod period) async {
    final map = quoteMap;
    if (map == null) {
      throw const PinovaApiException(
        'downgradeLater',
        message: 'Gói Ultra còn hạn tới 03/12/2026.',
        status: 409,
      );
    }
    return PaymentQuote.fromMap(map);
  }

  @override
  Future<PaymentResult> checkout(PlanTier tier, PlanPeriod period) async {
    checkouts++;
    if (free) {
      return PaymentResult.fromMap({
        'order': _order('paid', amount: 0),
        'plan': _plan('ultra'),
      });
    }
    return PaymentResult.fromMap({'order': _order('pending'), 'plan': null});
  }

  @override
  Future<PaymentResult> order(String orderId) async {
    checks++;
    return PaymentResult.fromMap({
      'order': _order(orderStatus),
      'plan': orderStatus == 'paid' ? _plan('ultra') : null,
    });
  }

  @override
  Future<List<PaymentOrder>> orders() async => [
    for (final o in history) PaymentOrder.fromMap(o),
  ];
}

const _upgrade = {
  'tier': 'ultra',
  'period': 'month',
  'kind': 'upgrade',
  'base': 49000,
  'afterPromo': 39000,
  'promoCode': 'SALE20',
  'percentOff': 20,
  'credit': 20000,
  'extraDays': 0,
  'days': 30,
  'amount': 19000,
  'newExpiresAt': '2026-12-03T03:00:00Z',
};

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _FakeBilling billing, {
  double scale = 1,
  bool allowPaid = true,
  List<Uri>? opened,
  bool opens = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
    overrides: [
      billingRepositoryProvider.overrideWithValue(billing),
      currentUidProvider.overrideWith((ref) => 'u1'),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: LuxeTheme.data(),
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: page!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PaymentSheet(
              tier: PlanTier.ultra,
              period: PlanPeriod.month,
              allowPaid: allowPaid,
              checkDelays: const [Duration(seconds: 1)],
              slowAfter: const Duration(seconds: 5),
              launcher: (uri) async {
                opened?.add(uri);
                return opens;
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the APK build pays directly unless built for a store', () {
    expect(AppConstants.paymentChannel, 'direct');
    expect(AppConstants.directPayments, isTrue);
  });

  test('the plan says when MoMo is open', () {
    expect(Entitlement.fromMap(_plan('free')).momoAvailable, isTrue);
    expect(
      Entitlement.fromMap({..._plan('free'), 'payments': null}).momoAvailable,
      isFalse,
    );
    final map = Entitlement.fromMap(_plan('pro')).toMap();
    expect(
      Entitlement.fromMap(Map<String, dynamic>.from(map)).momoAvailable,
      isTrue,
    );
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('quote shows code, Pro credit and total at ×$scale', (
      tester,
    ) async {
      await _pump(tester, _FakeBilling(quoteMap: _upgrade), scale: scale);
      expect(find.text('Xác nhận thanh toán'), findsOneWidget);
      expect(find.text('Mã SALE20 (giảm 20%)'), findsOneWidget);
      expect(find.text('−${formatVnd(10000)}'), findsOneWidget);
      expect(find.text('Quy đổi phần Pro còn lại'), findsOneWidget);
      expect(find.text('−${formatVnd(20000)}'), findsOneWidget);
      expect(find.text(formatVnd(19000)), findsOneWidget);
      expect(find.text('03/12/2026'), findsOneWidget);
      expect(
        find.text('Thanh toán ${formatVnd(19000)} bằng MoMo'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('paying opens MoMo, waits, and turns the plan on', (
    tester,
  ) async {
    final billing = _FakeBilling(quoteMap: _upgrade);
    final opened = <Uri>[];
    final container = await _pump(tester, billing, opened: opened);
    await tester.tap(find.byKey(const ValueKey('pay-momo')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(billing.checkouts, 1);
    expect(opened.single.scheme, 'momo');
    expect(find.text('Đang chờ MoMo xác nhận'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(billing.checks, 1);
    expect(find.text('Đang chờ MoMo xác nhận'), findsOneWidget);
    billing.orderStatus = 'paid';
    await tester.tap(find.byKey(const ValueKey('pay-check')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(entitlementProvider).tier, PlanTier.ultra);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('no MoMo app: the web page opens instead', (tester) async {
    final opened = <Uri>[];
    final billing = _FakeBilling(quoteMap: _upgrade);
    await _pump(tester, billing, opened: opened, opens: false);
    await tester.tap(find.byKey(const ValueKey('pay-momo')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(opened.map((u) => u.scheme), ['momo', 'https']);
    expect(find.textContaining('Chưa mở được MoMo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a slow answer is explained; a failed one offers a retry', (
    tester,
  ) async {
    final billing = _FakeBilling(quoteMap: _upgrade);
    await _pump(tester, billing);
    await tester.tap(find.byKey(const ValueKey('pay-momo')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(const ValueKey('pay-slow')), findsOneWidget);
    billing.orderStatus = 'failed';
    await tester.tap(find.byKey(const ValueKey('pay-check')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Thanh toán chưa hoàn tất'), findsOneWidget);
    expect(find.textContaining('chưa bị trừ tiền'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pay-retry')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Xác nhận thanh toán'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a free order turns on without MoMo, even in a store build', (
    tester,
  ) async {
    final billing = _FakeBilling(
      quoteMap: {..._upgrade, 'amount': 0, 'credit': 249000, 'extraDays': 122},
      free: true,
    );
    final opened = <Uri>[];
    final container = await _pump(
      tester,
      billing,
      allowPaid: false,
      opened: opened,
    );
    expect(find.text('Miễn phí'), findsOneWidget);
    expect(find.text('+122 ngày Ultra'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pay-momo')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(opened, isEmpty);
    expect(container.read(entitlementProvider).tier, PlanTier.ultra);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a store build never shows MoMo for a paid order', (
    tester,
  ) async {
    await _pump(tester, _FakeBilling(quoteMap: _upgrade), allowPaid: false);
    expect(find.byKey(const ValueKey('pay-momo')), findsNothing);
    expect(find.text(PaymentSheet.closedText), findsOneWidget);
  });

  testWidgets('the server explains a refused change (moving down)', (
    tester,
  ) async {
    await _pump(tester, _FakeBilling());
    expect(find.text('Gói Ultra còn hạn tới 03/12/2026.'), findsOneWidget);
    expect(find.byKey(const ValueKey('pay-momo')), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('payment history lists orders at ×$scale', (tester) async {
      final billing = _FakeBilling()
        ..history = [_order('paid'), _order('failed', amount: 29000)];
      await tester.binding.setSurfaceSize(const Size(320, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [billingRepositoryProvider.overrideWithValue(billing)],
          child: MaterialApp(
            theme: LuxeTheme.data(),
            builder: (context, page) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: page!,
            ),
            home: const PaymentHistoryScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Đã thanh toán'), findsOneWidget);
      expect(find.text('Chưa thanh toán'), findsOneWidget);
      expect(find.text(formatVnd(49000)), findsOneWidget);
      expect(find.textContaining('PNV261103100000ABCDEF'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }
}
