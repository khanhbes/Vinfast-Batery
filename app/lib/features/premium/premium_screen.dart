import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/entitlement_provider.dart';
import '../../core/services/pinova_api.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/utils/number_text.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../core/widgets/luxe_submit_button.dart';
import '../../data/models/entitlement.dart';

/// Pinova Premium (QA 135): the plans, what each adds, the 7-day trial and
/// a promo code field. Phase 1 takes no payment: buying shows "sắp mở" and
/// support can grant a plan.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key, this.highlight});

  /// The feature the owner tried to open (shown at the top).
  final PremiumFeature? highlight;

  static Future<void> open(BuildContext context, {PremiumFeature? highlight}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PremiumScreen(highlight: highlight),
        ),
      );

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PlanCopy {
  const _PlanCopy(this.tagline, this.highlights);
  final String tagline;
  final List<(IconData, String, String)> highlights;
}

const _ultraCopy = _PlanCopy('Trọn bộ an toàn và trí tuệ cho pin', [
  (
    Icons.nights_stay_rounded,
    'Sạc đêm an toàn',
    'Đầy đúng giờ thức dậy, giới hạn 85 %, ngắt ngay khi ổ nóng',
  ),
  (
    Icons.model_training_rounded,
    'AI cá nhân',
    'Học đúng xe của bạn: thời gian sạc và quãng đường chính xác hơn',
  ),
  (
    Icons.alt_route_rounded,
    'Dự đoán pin theo lộ trình',
    'Biết đủ pin đến nơi không, trước khi đi',
  ),
  (
    Icons.savings_rounded,
    'Sạc giờ điện rẻ · chi phí nâng cao',
    'Tự sạc vào khung giá thấp, xem chi phí theo tháng',
  ),
  (
    Icons.family_restroom_rounded,
    'Chia sẻ xe với người nhà',
    'Cả nhà cùng xem và điều khiển ổ sạc',
  ),
  (
    Icons.auto_awesome_rounded,
    'Pinova Bot 100 tin/ngày',
    'Hỏi thoải mái, cùng mọi tính năng Pro',
  ),
]);

const _proCopy = _PlanCopy('Sạc thông minh mỗi ngày', [
  (
    Icons.battery_charging_full_rounded,
    'Sạc đến % rồi tự ngắt',
    'Chọn 80 % hay 90 %, đổi mục tiêu ngay khi đang sạc',
  ),
  (
    Icons.health_and_safety_rounded,
    '% pin chai',
    'Ước tính dung lượng còn lại và bài kiểm tra pin',
  ),
  (
    Icons.history_rounded,
    'Lịch sử không giới hạn + CSV',
    'Free chỉ giữ 30 ngày gần nhất',
  ),
  (
    Icons.palette_rounded,
    'Giao diện tùy chọn · widget',
    'Đổi kiểu Tổng quan, tab Sạc và widget màn hình chính',
  ),
  (Icons.two_wheeler_rounded, '2 xe · Pinova Bot 30 tin/ngày', ''),
]);

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  PlanPeriod _period = PlanPeriod.year;
  final _promo = TextEditingController();
  bool _promoBusy = false;
  String? _promoError;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(entitlementProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _promo.dispose();
    super.dispose();
  }

  Future<bool> _startTrial() async {
    try {
      final value = await ref.read(entitlementProvider.notifier).startTrial();
      AppPopup.showSuccess(
        'Đã mở dùng thử ${value.tier.label} ${value.trialDays} ngày.',
      );
      return true;
    } on PinovaApiException catch (error) {
      AppPopup.showWarning(error.message ?? 'Chưa mở được dùng thử.');
      return false;
    }
  }

  Future<bool> _applyPromo() async {
    final code = _promo.text.trim();
    if (code.isEmpty) {
      setState(() => _promoError = 'Nhập mã khuyến mãi.');
      return false;
    }
    setState(() => _promoError = null);
    try {
      final quote = await ref
          .read(entitlementProvider.notifier)
          .redeemPromo(code);
      _promo.clear();
      AppPopup.showSuccess('Đã áp mã ${quote.code}: giảm ${quote.percentOff} %.');
      return true;
    } on PinovaApiException catch (error) {
      setState(
        () => _promoError = error.offline
            ? 'Cần kết nối mạng để kiểm tra mã.'
            : (error.message ?? 'Mã khuyến mãi không hợp lệ.'),
      );
      return false;
    }
  }

  void _buy(PlanTier tier) {
    showLuxeSheet<void>(
      context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LuxeSheetHeader(
              title: 'Thanh toán sắp mở',
              caption: 'Gói ${tier.label} · ${_period.label}',
            ),
            const Text(
              'Pinova chưa nhận thanh toán trong app. Trong lúc chờ, bạn có '
              'thể dùng thử miễn phí, hoặc gửi yêu cầu cho bộ phận hỗ trợ để '
              'được cấp gói. Mã khuyến mãi đã nhập được giữ cho lần mua đầu.',
              style: LuxeText.body,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Đã hiểu'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(entitlementProvider);
    final promo = plan.pendingPromo;
    return LuxeScaffold(
      title: 'Pinova Premium',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          _Hero(plan: plan, highlight: widget.highlight),
          const SizedBox(height: 18),
          LuxeSegmented<PlanPeriod>(
            key: const ValueKey('premium-period'),
            segments: [
              (PlanPeriod.month, 'Hằng tháng'),
              (PlanPeriod.year, 'Hằng năm'),
            ],
            selected: _period,
            onChanged: (value) => setState(() => _period = value),
          ),
          const SizedBox(height: 16),
          _PlanCard(
            key: const ValueKey('premium-plan-ultra'),
            tier: PlanTier.ultra,
            copy: _ultraCopy,
            period: _period,
            promo: promo,
            current: plan.tier == PlanTier.ultra,
            recommended: true,
            trialAvailable: plan.trialAvailable && !plan.isPremium,
            trialDays: plan.trialDays,
            onTrial: _startTrial,
            onBuy: () => _buy(PlanTier.ultra),
          ),
          const SizedBox(height: 14),
          _PlanCard(
            key: const ValueKey('premium-plan-pro'),
            tier: PlanTier.pro,
            copy: _proCopy,
            period: _period,
            promo: promo,
            current: plan.tier == PlanTier.pro,
            onBuy: () => _buy(PlanTier.pro),
          ),
          const SizedBox(height: 14),
          _FreeCard(current: plan.tier == PlanTier.free),
          const LuxeSectionLabel('Mã khuyến mãi'),
          _PromoField(
            controller: _promo,
            busy: _promoBusy,
            error: _promoError,
            applied: promo,
            onBusyChanged: (busy) => setState(() => _promoBusy = busy),
            onApply: _applyPromo,
            onRemove: promo == null
                ? null
                : () async {
                    try {
                      await ref.read(entitlementProvider.notifier).clearPromo();
                    } on PinovaApiException catch (error) {
                      AppPopup.showWarning(
                        error.message ?? 'Chưa bỏ được mã.',
                      );
                    }
                  },
          ),
          const LuxeSectionLabel('So sánh các gói'),
          const _CompareTable(),
          const SizedBox(height: 16),
          const LuxeNotice(
            icon: Icons.shield_outlined,
            color: LuxeColors.emerald,
            message:
                'An toàn luôn miễn phí: bật/dừng sạc có xác minh, hẹn giờ, '
                'ngắt khi quá tải hoặc quá nhiệt, quét đồng hồ và trợ giúp có '
                'ở mọi gói. Hết hạn gói không ngắt phiên sạc đang chạy.',
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.plan, this.highlight});
  final Entitlement plan;
  final PremiumFeature? highlight;

  @override
  Widget build(BuildContext context) {
    final left = plan.daysLeft(DateTime.now());
    final status = !plan.known
        ? 'Đang tải gói của bạn…'
        : !plan.serverSupportsBilling
        ? 'Máy chủ chưa bật Premium — mọi tính năng đang mở.'
        : plan.isTrial
        ? 'Đang dùng thử ${plan.tier.label} · còn ${left ?? 0} ngày'
        : plan.isPremium
        ? 'Bạn đang dùng ${plan.tier.label}${left != null ? ' · còn $left ngày' : ''}'
        : 'Bạn đang dùng gói Free';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B2A24), Color(0xFF111316), Color(0xFF0B0C0E)],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: LuxeColors.emerald.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/icons/pinova_logo_full.png',
                width: 44,
                height: 44,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.workspace_premium_rounded,
                  color: LuxeColors.emerald,
                  size: 40,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('PINOVA PREMIUM', style: LuxeText.eyebrow),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Pin bền hơn, sạc an tâm hơn',
            style: LuxeText.title,
          ),
          const SizedBox(height: 6),
          Text(
            highlight != null
                ? '“${highlight!.label}” có trong gói ${highlight!.tier.label}. '
                      'Dùng thử miễn phí hoặc chọn gói bên dưới.'
                : 'Sạc đến đúng %, sạc đêm an toàn, AI hiểu chiếc xe của bạn.',
            style: LuxeText.body,
          ),
          const SizedBox(height: 14),
          LuxeTag(
            status,
            color: plan.isPremium ? LuxeColors.emerald : LuxeColors.platinumMid,
          ),
        ],
      ),
    );
  }
}

class _Price extends StatelessWidget {
  const _Price({
    required this.tier,
    required this.period,
    required this.promo,
  });
  final PlanTier tier;
  final PlanPeriod period;
  final PromoQuote? promo;

  @override
  Widget build(BuildContext context) {
    final base = PlanTable.price(tier, period);
    final discounted = promo?.finalPrice(tier, period);
    final shown = discounted ?? base;
    final perMonth = period == PlanPeriod.year ? (shown / 12).round() : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          children: [
            Text(
              formatVnd(shown),
              key: ValueKey('premium-price-${tier.id}'),
              style: const TextStyle(
                color: LuxeColors.text,
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                period == PlanPeriod.year ? '/năm' : '/tháng',
                style: LuxeText.caption,
              ),
            ),
            if (discounted != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  formatVnd(base),
                  style: LuxeText.caption.copyWith(
                    decoration: TextDecoration.lineThrough,
                    decorationColor: LuxeColors.muted,
                  ),
                ),
              ),
          ],
        ),
        if (perMonth != null)
          Text(
            '~${formatVnd(perMonth)} mỗi tháng · tiết kiệm '
            '${PlanTable.yearlySavingPct(tier)} % so với trả tháng',
            style: LuxeText.caption.copyWith(color: LuxeColors.champagne),
          ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    super.key,
    required this.tier,
    required this.copy,
    required this.period,
    required this.promo,
    required this.current,
    required this.onBuy,
    this.recommended = false,
    this.trialAvailable = false,
    this.trialDays = 7,
    this.onTrial,
  });

  final PlanTier tier;
  final _PlanCopy copy;
  final PlanPeriod period;
  final PromoQuote? promo;
  final bool current;
  final bool recommended;
  final bool trialAvailable;
  final int trialDays;
  final Future<bool> Function()? onTrial;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final accent = recommended ? LuxeColors.emerald : LuxeColors.platinum;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: LuxeColors.raised,
        border: Border.all(
          color: recommended
              ? LuxeColors.emerald.withValues(alpha: 0.55)
              : LuxeColors.hairlineStrong,
          width: recommended ? 1.4 : 1,
        ),
        boxShadow: recommended
            ? [
                BoxShadow(
                  color: LuxeColors.emerald.withValues(alpha: 0.14),
                  blurRadius: 28,
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Pinova ${tier.label}',
                style: TextStyle(
                  color: accent,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (recommended)
                const LuxeTag('ĐỀ XUẤT', color: LuxeColors.emerald),
              if (current) const LuxeTag('GÓI HIỆN TẠI'),
            ],
          ),
          const SizedBox(height: 4),
          Text(copy.tagline, style: LuxeText.caption),
          const SizedBox(height: 12),
          _Price(tier: tier, period: period, promo: promo),
          const SizedBox(height: 14),
          for (final (icon, title, caption) in copy.highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.1),
                      border: Border.all(color: accent.withValues(alpha: 0.3)),
                    ),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: LuxeColors.text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (caption.isNotEmpty)
                          Text(
                            caption,
                            style: LuxeText.caption.copyWith(fontSize: 12.5),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          if (current)
            const LuxeNotice(
              icon: Icons.check_circle_outline_rounded,
              color: LuxeColors.emerald,
              message: 'Bạn đang dùng gói này.',
            )
          else ...[
            if (trialAvailable && onTrial != null) ...[
              LuxeSubmitButton(
                key: ValueKey('premium-trial-${tier.id}'),
                label: 'Dùng thử miễn phí $trialDays ngày',
                busyLabel: 'Đang mở dùng thử…',
                doneLabel: 'Đã mở dùng thử',
                icon: Icons.auto_awesome_rounded,
                onPressed: onTrial,
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: (trialAvailable && onTrial != null)
                  ? OutlinedButton(
                      key: ValueKey('premium-buy-${tier.id}'),
                      onPressed: onBuy,
                      child: Text('Chọn ${tier.label}'),
                    )
                  : FilledButton(
                      key: ValueKey('premium-buy-${tier.id}'),
                      onPressed: onBuy,
                      child: Text('Chọn ${tier.label}'),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FreeCard extends StatelessWidget {
  const _FreeCard({required this.current});
  final bool current;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: LuxeColors.glass,
      border: Border.all(color: LuxeColors.hairline),
    ),
    child: Row(
      children: [
        const Icon(Icons.bolt_rounded, color: LuxeColors.platinumMid),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Free · 0đ',
                style: TextStyle(
                  color: LuxeColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Sạc an toàn, hẹn giờ, pin/ODO, quét đồng hồ, 1 xe, '
                'lịch sử 30 ngày, Pinova Bot 10 tin/ngày',
                style: LuxeText.caption,
              ),
            ],
          ),
        ),
        if (current) const LuxeTag('GÓI HIỆN TẠI'),
      ],
    ),
  );
}

class _PromoField extends StatelessWidget {
  const _PromoField({
    required this.controller,
    required this.busy,
    required this.error,
    required this.applied,
    required this.onBusyChanged,
    required this.onApply,
    required this.onRemove,
  });

  final TextEditingController controller;
  final bool busy;
  final String? error;
  final PromoQuote? applied;
  final ValueChanged<bool> onBusyChanged;
  final Future<bool> Function() onApply;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (applied != null) ...[
        LuxeNotice(
          key: const ValueKey('premium-promo-applied'),
          icon: Icons.local_offer_rounded,
          color: LuxeColors.emerald,
          message:
              'Mã ${applied!.code}: giảm ${applied!.percentOff} %'
              '${applied!.validTo != null ? ' · đến ${_date(applied!.validTo!)}' : ''}. '
              'Giá đã giảm hiện ở các gói áp dụng.',
          action: onRemove == null
              ? null
              : TextButton(onPressed: onRemove, child: const Text('Bỏ')),
        ),
        const SizedBox(height: 10),
      ],
      TextField(
        key: const ValueKey('premium-promo-input'),
        controller: controller,
        enabled: !busy,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')),
          LengthLimitingTextInputFormatter(20),
        ],
        decoration: InputDecoration(
          labelText: 'Nhập mã khuyến mãi',
          prefixIcon: const Icon(Icons.confirmation_number_outlined),
          errorText: error,
        ),
        onSubmitted: (_) => onApply(),
      ),
      const SizedBox(height: 10),
      LuxeSubmitButton(
        key: const ValueKey('premium-promo-apply'),
        label: 'Áp dụng mã',
        busyLabel: 'Đang kiểm tra mã…',
        doneLabel: 'Đã áp mã',
        outlined: true,
        onPressed: onApply,
        onBusyChanged: onBusyChanged,
      ),
    ],
  );

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}

class _CompareTable extends StatelessWidget {
  const _CompareTable();

  static const _rows = <(String, String, String, String)>[
    ('Sạc an toàn, hẹn giờ, quét đồng hồ', '✓', '✓', '✓'),
    ('Pinova Bot mỗi ngày', '10', '30', '100'),
    ('Lịch sử sạc', '30 ngày', '∞ + CSV', '∞ + CSV'),
    ('Sạc đến % tự ngắt, sửa mục tiêu', '—', '✓', '✓'),
    ('% pin chai + bài kiểm tra', '—', '✓', '✓'),
    ('Giao diện tùy chọn, widget', '—', '✓', '✓'),
    ('Số xe', '1', '2', 'Không giới hạn'),
    ('AI cá nhân', '—', '—', '✓'),
    ('Dự đoán pin theo lộ trình', '—', '—', '✓'),
    ('Sạc đêm an toàn', '—', '—', '✓'),
    ('Sạc giờ điện rẻ, chi phí nâng cao', '—', '—', '✓'),
    ('Chia sẻ xe, báo cáo pin tháng', '—', '—', '✓'),
    ('Trợ giúp & khắc phục sự cố', '✓', '✓', '✓'),
  ];

  @override
  Widget build(BuildContext context) {
    Widget cell(String text, {bool head = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color ?? (text == '—' ? LuxeColors.dim : LuxeColors.text),
          fontSize: head ? 12.5 : 13,
          fontWeight: head ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: LuxeColors.glass,
        border: Border.all(color: LuxeColors.hairline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.4),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
          3: FlexColumnWidth(1.2),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: const TableBorder(
          horizontalInside: BorderSide(color: LuxeColors.hairline),
        ),
        children: [
          TableRow(
            children: [
              const SizedBox.shrink(),
              cell('Free', head: true, color: LuxeColors.muted),
              cell('Pro', head: true, color: LuxeColors.platinum),
              cell('Ultra', head: true, color: LuxeColors.emerald),
            ],
          ),
          for (final (label, free, pro, ultra) in _rows)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(label, style: LuxeText.caption),
                ),
                cell(free),
                cell(pro),
                cell(ultra, color: ultra == '—' ? null : LuxeColors.emerald),
              ],
            ),
        ],
      ),
    );
  }
}
