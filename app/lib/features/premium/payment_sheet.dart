import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/entitlement_provider.dart';
import '../../core/services/pinova_api.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/theme/plan_style.dart';
import '../../core/utils/number_text.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_submit_button.dart';
import '../../data/models/entitlement.dart';
import 'payment_history_screen.dart';

String _day(DateTime value) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year}';
}

/// Paying for a plan with MoMo (QA 145): the server's quote, one button,
/// then the wait for MoMo's answer. The plan turns on only when the server
/// says the order is paid; the app never decides a payment itself.
class PaymentSheet extends ConsumerStatefulWidget {
  const PaymentSheet({
    super.key,
    required this.tier,
    required this.period,
    this.allowPaid = true,
    this.launcher,
    this.checkDelays = defaultCheckDelays,
    this.slowAfter = const Duration(minutes: 2),
  });

  final PlanTier tier;
  final PlanPeriod period;

  /// False in a store build or while the server has MoMo closed: only a
  /// free order (a 100 % code, or credit covering the price) goes through.
  final bool allowPaid;

  static const closedText =
      'Pinova chưa nhận thanh toán trong bản này. Trong lúc chờ, bạn có thể '
      'dùng thử miễn phí, hoặc gửi yêu cầu cho bộ phận hỗ trợ để được cấp '
      'gói. Mã khuyến mãi đã nhập được giữ cho lần mua đầu.';

  /// Opens MoMo (tests pass a fake). True when something opened.
  final Future<bool> Function(Uri uri)? launcher;

  /// When to ask the server again after MoMo opened or the app came back.
  final List<Duration> checkDelays;
  final Duration slowAfter;

  static const defaultCheckDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 7),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  static Future<void> open(
    BuildContext context, {
    required PlanTier tier,
    required PlanPeriod period,
  }) => showLuxeSheet<void>(
    context,
    builder: (_) => PaymentSheet(tier: tier, period: period),
  );

  @override
  ConsumerState<PaymentSheet> createState() => _PaymentSheetState();
}

enum _Step { quote, waiting, failed }

class _PaymentSheetState extends ConsumerState<PaymentSheet> {
  PaymentQuote? _quote;
  String? _error;
  bool _loading = true;
  _Step _step = _Step.quote;
  PaymentOrder? _order;
  DateTime? _openedAt;
  bool _slow = false;
  final List<Timer> _timers = [];
  AppLifecycleListener? _lifecycle;

  BillingRepository get _billing => ref.read(billingRepositoryProvider);

  @override
  void initState() {
    super.initState();
    try {
      _lifecycle = AppLifecycleListener(onResume: _scheduleChecks);
    } on Object {
      _lifecycle = null;
    }
    _loadQuote();
  }

  @override
  void dispose() {
    _cancelChecks();
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final quote = await _billing.quote(widget.tier, widget.period);
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _loading = false;
      });
    } on PinovaApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.offline
            ? 'Cần kết nối mạng để thanh toán.'
            : (error.message ?? 'Chưa tính được giá. Bạn thử lại sau.');
      });
    }
  }

  Future<bool> _pay() async {
    setState(() => _error = null);
    try {
      final result = await _billing.checkout(widget.tier, widget.period);
      if (!mounted) return false;
      if (result.order.paid) {
        await _finish(result);
        return true;
      }
      _order = result.order;
      final opened = await _openMomo(result.order);
      if (!mounted) return false;
      setState(() {
        _step = _Step.waiting;
        _openedAt = DateTime.now();
        _slow = false;
        if (!opened) {
          _error =
              'Chưa mở được MoMo. Kiểm tra app MoMo đã cài, rồi bấm Mở lại MoMo.';
        }
      });
      _scheduleChecks();
      return true;
    } on PinovaApiException catch (error) {
      if (!mounted) return false;
      setState(
        () => _error = error.offline
            ? 'Cần kết nối mạng để thanh toán.'
            : (error.message ?? 'Chưa tạo được đơn thanh toán.'),
      );
      return false;
    }
  }

  Future<bool> _openMomo(PaymentOrder order) async {
    final launch =
        widget.launcher ??
        (Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
    for (final link in [order.deeplink, order.payUrl]) {
      final uri = link == null ? null : Uri.tryParse(link);
      if (uri == null) continue;
      try {
        if (await launch(uri)) return true;
      } on Object {
        // Try the web page next.
      }
    }
    return false;
  }

  void _cancelChecks() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _scheduleChecks() {
    if (!mounted || _step != _Step.waiting || _order == null) return;
    _cancelChecks();
    for (final delay in widget.checkDelays) {
      _timers.add(Timer(delay, () => _check()));
    }
    final opened = _openedAt;
    if (opened != null) {
      final left = widget.slowAfter - DateTime.now().difference(opened);
      _timers.add(
        Timer(left.isNegative ? Duration.zero : left, () {
          if (mounted && _step == _Step.waiting) setState(() => _slow = true);
        }),
      );
    }
  }

  Future<bool> _check() async {
    final order = _order;
    if (order == null || !mounted || _step != _Step.waiting) return false;
    try {
      final result = await _billing.order(order.orderId);
      if (!mounted) return false;
      if (result.order.paid) {
        await _finish(result);
        return true;
      }
      if (!result.order.pending) {
        _cancelChecks();
        setState(() {
          _step = _Step.failed;
          _order = result.order;
        });
      }
      return false;
    } on PinovaApiException {
      return false; // keep waiting; the server settles it with MoMo
    }
  }

  Future<void> _finish(PaymentResult result) async {
    _cancelChecks();
    final notifier = ref.read(entitlementProvider.notifier);
    final plan = result.plan;
    if (plan != null) {
      await notifier.applyPlan(plan);
    } else {
      await notifier.refresh();
    }
    if (!mounted) return;
    final Entitlement current = plan ?? ref.read(entitlementProvider);
    final end = current.expiresAt?.toLocal();
    Navigator.of(context).pop();
    AppPopup.showSuccess(
      'Đã bật gói ${result.order.tier.label}',
      detail: end == null ? null : 'Dùng đến ${_day(end)}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final periodText = widget.period == PlanPeriod.year ? '1 năm' : '1 tháng';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LuxeSheetHeader(
            title: switch (_step) {
              _Step.quote => 'Xác nhận thanh toán',
              _Step.waiting => 'Đang chờ MoMo xác nhận',
              _Step.failed => 'Thanh toán chưa hoàn tất',
            },
            caption: 'Gói ${widget.tier.label} · $periodText',
          ),
          ...switch (_step) {
            _Step.quote => _quoteBody(context),
            _Step.waiting => _waitingBody(context),
            _Step.failed => _failedBody(context),
          },
        ],
      ),
    );
  }

  List<Widget> _quoteBody(BuildContext context) {
    final quote = _quote;
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (quote == null) {
      return [
        _ErrorText(_error ?? 'Chưa tính được giá.'),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: _loadQuote, child: const Text('Thử lại')),
      ];
    }
    final rows = <Widget>[
      _Row('Giá gói', formatVnd(quote.base)),
      if (quote.promoCode != null && quote.afterPromo < quote.base)
        _Row(
          'Mã ${quote.promoCode} (giảm ${quote.percentOff}%)',
          '−${formatVnd(quote.base - quote.afterPromo)}',
        ),
      if (quote.credit > 0)
        _Row(
          'Quy đổi phần Pro còn lại',
          '−${formatVnd(quote.credit < quote.afterPromo ? quote.credit : quote.afterPromo)}',
        ),
      if (quote.extraDays > 0)
        _Row('Phần dư đổi thành', '+${quote.extraDays} ngày Ultra'),
    ];
    final end = quote.newExpiresAt;
    return [
      LuxeGlass(
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...rows,
            const Divider(height: 20, color: LuxeColors.hairline),
            _Row(
              'Tổng thanh toán',
              quote.free ? 'Miễn phí' : formatVnd(quote.amount),
              strong: true,
            ),
            if (end != null)
              _Row('Dùng đến', _day(end), key: const ValueKey('pay-ends')),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Text(
        quote.kind == 'extend'
            ? 'Thời gian mới được cộng vào sau ngày hết hạn hiện tại. '
                  'Trả trước, không tự gia hạn.'
            : quote.kind == 'upgrade'
            ? 'Ultra bắt đầu ngay. Trả trước, không tự gia hạn.'
            : 'Trả trước, không tự gia hạn. App nhắc bạn trước khi hết hạn.',
        style: LuxeText.caption,
      ),
      if (_error != null) ...[const SizedBox(height: 10), _ErrorText(_error!)],
      const SizedBox(height: 16),
      if (!quote.free && !widget.allowPaid) ...[
        const Text(PaymentSheet.closedText, style: LuxeText.body),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đã hiểu'),
        ),
      ] else
        LuxeSubmitButton(
          key: const ValueKey('pay-momo'),
          label: quote.free
              ? 'Kích hoạt miễn phí'
              : 'Thanh toán ${formatVnd(quote.amount)} bằng MoMo',
          busyLabel: quote.free ? 'Đang kích hoạt…' : 'Đang mở MoMo…',
          doneLabel: quote.free ? 'Đã kích hoạt' : 'Đã mở MoMo',
          icon: quote.free
              ? Icons.check_circle_outline_rounded
              : Icons.account_balance_wallet_rounded,
          onPressed: _pay,
        ),
      TextButton(
        key: const ValueKey('pay-terms'),
        onPressed: () => launchUrl(
          Uri.parse('${AppConstants.apiBaseUrl}/dieu-khoan-premium'),
          mode: LaunchMode.externalApplication,
        ),
        child: const Text('Điều khoản gói Premium'),
      ),
    ];
  }

  List<Widget> _waitingBody(BuildContext context) => [
    const Text(
      'Hoàn tất thanh toán trong app MoMo rồi quay lại đây. Gói bật ngay khi '
      'MoMo báo thành công.',
      style: LuxeText.body,
    ),
    if (_slow) ...[
      const SizedBox(height: 10),
      Text(
        'Chưa nhận kết quả từ MoMo. Nếu bạn đã bị trừ tiền, gói sẽ tự bật '
        'khi MoMo báo; xem lại trong Lịch sử thanh toán.',
        key: const ValueKey('pay-slow'),
        style: LuxeText.caption.copyWith(color: LuxeColors.champagne),
      ),
    ],
    if (_error != null) ...[const SizedBox(height: 10), _ErrorText(_error!)],
    const SizedBox(height: 16),
    LuxeSubmitButton(
      key: const ValueKey('pay-check'),
      label: 'Kiểm tra lại',
      busyLabel: 'Đang kiểm tra…',
      doneLabel: 'Đã thanh toán',
      icon: Icons.refresh_rounded,
      onPressed: _check,
    ),
    const SizedBox(height: 8),
    OutlinedButton(
      key: const ValueKey('pay-reopen'),
      onPressed: () async {
        final order = _order;
        if (order == null) return;
        final opened = await _openMomo(order);
        if (!mounted) return;
        setState(
          () => _error = opened
              ? null
              : 'Chưa mở được MoMo. Kiểm tra app MoMo đã cài.',
        );
        _scheduleChecks();
      },
      child: const Text('Mở lại MoMo'),
    ),
  ];

  List<Widget> _failedBody(BuildContext context) => [
    Text(
      _order?.status == 'failed'
          ? 'MoMo báo đơn chưa được thanh toán (đã hủy hoặc hết hạn). Bạn chưa bị trừ tiền cho đơn này.'
          : 'Đơn đang được kiểm tra. Nếu bạn đã bị trừ tiền, hãy gửi yêu cầu ở Cài đặt → Trợ giúp kèm mã đơn trong Lịch sử thanh toán.',
      style: LuxeText.body,
    ),
    const SizedBox(height: 16),
    FilledButton(
      key: const ValueKey('pay-retry'),
      onPressed: () {
        setState(() {
          _step = _Step.quote;
          _order = null;
        });
        _loadQuote();
      },
      child: const Text('Thử lại'),
    ),
    TextButton(
      onPressed: () {
        Navigator.of(context).pop();
        PaymentHistoryScreen.open(context);
      },
      child: const Text('Lịch sử thanh toán'),
    ),
  ];
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {super.key, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: strong ? LuxeText.item : LuxeText.body),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: strong
                ? LuxeText.item.copyWith(color: context.planAccent)
                : LuxeText.body.copyWith(color: LuxeColors.text),
          ),
        ),
      ],
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: LuxeText.caption.copyWith(color: LuxeColors.danger));
}
