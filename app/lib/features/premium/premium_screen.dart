import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/entitlement_provider.dart';
import '../../core/services/guide_registry.dart';
import '../../core/services/pinova_api.dart';
import '../../core/services/screen_tour.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/theme/plan_style.dart';
import '../../core/utils/number_text.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_submit_button.dart';
import '../../data/models/entitlement.dart';
import 'plan_tag.dart';

/// Pinova Premium (QA 135; layout QA 136): pick Pro or Ultra, read four
/// plain benefits, pick month or year, then one button at the bottom (the
/// 7-day trial, or the plan). Promo code and the full comparison are folded
/// away. Phase 1 takes no payment: buying shows "sắp mở".
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key, this.highlight});

  /// The feature the owner tried to open (its plan is selected first).
  final PremiumFeature? highlight;

  /// QA 137: on this page Ultra always shows its slow aurora (to everyone,
  /// on every plan), one loop every 18 s; still under "reduce motion".
  static const ultraFlow = Duration(seconds: 18);

  static Future<void> open(BuildContext context, {PremiumFeature? highlight}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PremiumScreen(highlight: highlight),
        ),
      );

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _Benefit {
  const _Benefit(this.icon, this.title, this.caption);
  final IconData icon;
  final String title;
  final String caption;
}

const _proLead = 'Sạc thông minh mỗi ngày';
const _proBenefits = [
  _Benefit(
    Icons.battery_charging_full_rounded,
    'Sạc đến đúng % rồi tự tắt',
    'Chọn 80% hay 90%, đổi được cả khi đang sạc.',
  ),
  _Benefit(
    Icons.alt_route_rounded,
    'Lộ trình',
    'Nhập nơi muốn đến, biết pin có đủ đi không.',
  ),
  _Benefit(
    Icons.health_and_safety_rounded,
    'Pin còn khỏe bao nhiêu',
    'Ước tính % pin chai và bài kiểm tra pin.',
  ),
  _Benefit(
    Icons.history_rounded,
    'Lịch sử đầy đủ, 2 xe',
    'Xem lại mọi lần sạc, xuất file, Pinova Bot 30 tin mỗi ngày.',
  ),
];

const _ultraLead = 'Mọi thứ của Pro, thêm:';
const _ultraBenefits = [
  _Benefit(
    Icons.nights_stay_rounded,
    'Sạc đêm an toàn',
    'Đầy đúng giờ bạn thức dậy, tự ngắt sớm nếu ổ nóng.',
  ),
  _Benefit(
    Icons.model_training_rounded,
    'AI hiểu riêng xe bạn',
    'Đoán thời gian sạc và quãng đường sát hơn.',
  ),
  _Benefit(
    Icons.auto_awesome_rounded,
    'Giao diện Aurora',
    'Màu sắc và hiệu ứng riêng của Ultra.',
  ),
  _Benefit(
    Icons.all_inclusive_rounded,
    'Nhiều xe, nhiều tin hơn',
    'Tối đa 10 xe, Pinova Bot 100 tin mỗi ngày.',
  ),
];

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  PlanPeriod _period = PlanPeriod.year;
  late PlanTier _tier = widget.highlight?.tier ?? PlanTier.ultra;
  final _promo = TextEditingController();
  bool _promoOpen = false;
  bool _promoBusy = false;
  String? _promoError;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(entitlementProvider.notifier).refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScreenTour.maybeShow(
          context,
          ScreenTour.premium,
          GuideRegistry.premiumTourSteps(),
        );
      }
    });
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
      AppPopup.showSuccess(
        'Đã áp mã ${quote.code}: giảm ${quote.percentOff}%.',
      );
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
    final ultra = _tier == PlanTier.ultra;
    return PlanMotionHost(
      running: !MediaQuery.disableAnimationsOf(context),
      period: PremiumScreen.ultraFlow,
      child: _page(context, plan, promo, ultra),
    );
  }

  Widget _page(
    BuildContext context,
    Entitlement plan,
    PromoQuote? promo,
    bool ultra,
  ) {
    return LuxeScaffold(
      title: 'Pinova Premium',
      bottomNavigationBar: _ActionBar(
        plan: plan,
        tier: _tier,
        period: _period,
        promo: promo,
        onTrial: _startTrial,
        onBuy: () => _buy(_tier),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _Hero(plan: plan, highlight: widget.highlight),
          const SizedBox(height: 18),
          _TierSwitch(
            selected: _tier,
            onChanged: (tier) {
              HapticFeedback.selectionClick();
              setState(() => _tier = tier);
            },
          ),
          const SizedBox(height: 14),
          KeyedSubtree(
            key: GuideRegistry.keyPremiumUltra,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 320),
              switchInCurve: LuxeMotion.enter,
              switchOutCurve: Curves.easeOut,
              child: _BenefitsCard(
                key: ValueKey('premium-benefits-${_tier.id}'),
                tier: _tier,
                lead: ultra ? _ultraLead : _proLead,
                benefits: ultra ? _ultraBenefits : _proBenefits,
                highlight: widget.highlight?.tier == _tier
                    ? widget.highlight
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 18),
          LuxeSegmented<PlanPeriod>(
            key: GuideRegistry.keyPremiumPeriod,
            segments: [
              (PlanPeriod.month, 'Theo tháng'),
              (
                PlanPeriod.year,
                'Theo năm · −${PlanTable.yearlySavingPct(_tier)}%',
              ),
            ],
            selected: _period,
            onChanged: (value) => setState(() => _period = value),
          ),
          const SizedBox(height: 12),
          _Price(tier: _tier, period: _period, promo: promo),
          const SizedBox(height: 10),
          _Fold(
            key: GuideRegistry.keyPremiumPromo,
            foldKey: const ValueKey('premium-promo-toggle'),
            icon: Icons.local_offer_rounded,
            title: promo == null
                ? 'Có mã khuyến mãi?'
                : 'Mã ${promo.code} · giảm ${promo.percentOff}%',
            open: _promoOpen || promo != null,
            onToggle: () => setState(() => _promoOpen = !_promoOpen),
            child: _PromoField(
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
                        await ref
                            .read(entitlementProvider.notifier)
                            .clearPromo();
                      } on PinovaApiException catch (error) {
                        AppPopup.showWarning(
                          error.message ?? 'Chưa bỏ được mã.',
                        );
                      }
                    },
            ),
          ),
          const SizedBox(height: 10),
          const _Fold(
            foldKey: ValueKey('premium-compare-toggle'),
            icon: Icons.table_rows_rounded,
            title: 'So sánh đầy đủ Free · Pro · Ultra',
            child: _CompareTable(),
          ),
          const SizedBox(height: 16),
          const LuxeNotice(
            icon: Icons.shield_rounded,
            color: LuxeColors.emerald,
            message:
                'An toàn luôn miễn phí ở mọi gói: bật/dừng sạc có xác minh, '
                'hẹn giờ, tự ngắt khi quá tải hoặc quá nóng. Hết gói không '
                'ngắt phiên sạc đang chạy.',
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Hero ─────────────────────────────

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Image.asset(
              'assets/icons/pinova_logo_full.png',
              width: 34,
              height: 34,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const Icon(
                Icons.workspace_premium_rounded,
                color: LuxeColors.platinum,
                size: 30,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('PINOVA PREMIUM', style: LuxeText.eyebrow),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text('Pin bền hơn, sạc an tâm hơn', style: LuxeText.title),
        const SizedBox(height: 6),
        Text(
          highlight != null
              ? '“${highlight!.label}” có trong gói ${highlight!.tier.label}. '
                    'Dùng thử 7 ngày miễn phí để mở ngay.'
              : 'Chọn gói phù hợp. Dùng thử 7 ngày miễn phí, không cần '
                    'thanh toán.',
          style: LuxeText.body,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (plan.known) PlanTag(tier: plan.tier),
            Text(status, style: LuxeText.caption),
          ],
        ),
      ],
    );
  }
}

// ───────────────────────────── Pro | Ultra ─────────────────────────────

class _TierSwitch extends StatelessWidget {
  const _TierSwitch({required this.selected, required this.onChanged});
  final PlanTier selected;
  final ValueChanged<PlanTier> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final tier in const [PlanTier.pro, PlanTier.ultra]) ...[
        if (tier == PlanTier.ultra) const SizedBox(width: 10),
        Expanded(
          child: _TierPill(
            tier: tier,
            selected: selected == tier,
            onTap: () => onChanged(tier),
          ),
        ),
      ],
    ],
  );
}

class _TierPill extends StatelessWidget {
  const _TierPill({
    required this.tier,
    required this.selected,
    required this.onTap,
  });
  final PlanTier tier;
  final bool selected;
  final VoidCallback onTap;

  static const _silver = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [PlanColors.silverHi, PlanColors.silver, PlanColors.steel],
  );

  @override
  Widget build(BuildContext context) {
    final ultra = tier == PlanTier.ultra;
    final from = PlanTable.price(tier, PlanPeriod.year) / 12;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                tier.label,
                style: TextStyle(
                  color: selected ? PlanColors.ink : LuxeColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (ultra)
                Text(
                  'ĐỀ XUẤT',
                  style: TextStyle(
                    color: selected ? PlanColors.ink : PlanColors.lavender,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'khoảng ${formatVnd(from.round())}/tháng',
            style: TextStyle(
              // QA 139: solid ink (80 % ink was 3.8:1 on the violet stop).
              color: selected ? PlanColors.ink : LuxeColors.muted,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
    // QA 137: the fill is its own layer that fades in once. Inside an
    // AnimatedContainer the flowing aurora restarted the implicit animation
    // 25 times a second and stayed stuck dark on a real phone.
    Widget pill(Gradient fill) {
      final surface = Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          // Unselected Ultra sits on an aurora ring: keep the inside opaque.
          color: ultra && !selected ? LuxeColors.surface : LuxeColors.glass,
          border: ultra && !selected
              ? null
              : Border.all(
                  color: selected
                      ? const Color(0x99FFFFFF)
                      : LuxeColors.hairline,
                ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: (ultra ? PlanColors.violet : PlanColors.steel)
                        .withValues(alpha: 0.35),
                    blurRadius: 22,
                    spreadRadius: -6,
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            if (selected)
              Positioned.fill(
                child: _FadeIn(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(19),
                      gradient: fill,
                    ),
                  ),
                ),
              ),
            content,
          ],
        ),
      );
      if (!ultra || selected) return surface;
      // Not chosen yet, Ultra still shows a slow aurora edge (owner's ask:
      // the top plan moves gently, never static).
      return Container(
        padding: const EdgeInsets.all(1.2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(21),
          gradient: fill,
        ),
        child: surface,
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      label: 'Gói ${tier.label}',
      child: GestureDetector(
        key: ValueKey('premium-tier-${tier.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ultra
            ? PlanFlow(
                builder: (context, phase) => pill(planFlowGradient(phase)),
              )
            : pill(_silver),
      ),
    );
  }
}

/// Fades its child in once when it first appears.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260),
    curve: LuxeMotion.enter,
    builder: (context, t, child) => Opacity(opacity: t, child: child),
    child: child,
  );
}

// ───────────────────────────── Benefits ─────────────────────────────

class _BenefitsCard extends StatelessWidget {
  const _BenefitsCard({
    super.key,
    required this.tier,
    required this.lead,
    required this.benefits,
    this.highlight,
  });

  final PlanTier tier;
  final String lead;
  final List<_Benefit> benefits;
  final PremiumFeature? highlight;

  @override
  Widget build(BuildContext context) {
    final ultra = tier == PlanTier.ultra;
    final colors = ultra ? PlanColors.aurora : PlanStyle.pro.accentColors;
    Widget card(Gradient border) => Container(
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: border,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(23),
          color: LuxeColors.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pinova ${tier.label}',
                    style: const TextStyle(
                      color: LuxeColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PlanTag(tier: tier),
              ],
            ),
            const SizedBox(height: 2),
            Text(lead, style: LuxeText.caption),
            if (highlight != null) ...[
              const SizedBox(height: 10),
              LuxeNotice(
                icon: Icons.touch_app_rounded,
                color: ultra ? PlanColors.lavender : PlanColors.steelText,
                message: 'Bạn vừa mở: ${highlight!.label}.',
              ),
            ],
            const SizedBox(height: 12),
            for (var i = 0; i < benefits.length; i++)
              LuxeReveal(
                index: i,
                child: _BenefitRow(benefit: benefits[i], colors: colors),
              ),
          ],
        ),
      ),
    );
    return ultra
        ? PlanFlow(
            builder: (context, phase) => card(
              planFlowGradient(
                phase,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          )
        : card(
            const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x99F4F6FA), Color(0x338FA9D6), Color(0x66C9D2E0)],
            ),
          );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.benefit, required this.colors});
  final _Benefit benefit;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BenefitIcon(icon: benefit.icon, colors: colors),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                benefit.title,
                style: const TextStyle(
                  color: LuxeColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(benefit.caption, style: LuxeText.caption),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A ring in the plan's colours that draws itself once around the icon.
class _BenefitIcon extends StatelessWidget {
  const _BenefitIcon({required this.icon, required this.colors});
  final IconData icon;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 900),
      curve: LuxeMotion.enter,
      builder: (context, t, child) => CustomPaint(
        painter: _RingPainter(sweep: t, colors: colors),
        child: child,
      ),
      child: Center(child: Icon(icon, size: 20, color: LuxeColors.platinumHi)),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.sweep, required this.colors});
  final double sweep;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final c = rect.center;
    final r = size.shortestSide / 2 - 1.5;
    canvas.drawCircle(c, r, Paint()..color = const Color(0x14FFFFFF));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [...colors, colors.first],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.sweep != sweep;
}

// ───────────────────────────── Price ─────────────────────────────

class _Price extends StatelessWidget {
  const _Price({required this.tier, required this.period, required this.promo});
  final PlanTier tier;
  final PlanPeriod period;
  final PromoQuote? promo;

  @override
  Widget build(BuildContext context) {
    final base = PlanTable.price(tier, period);
    final discounted = promo?.finalPrice(tier, period);
    final shown = discounted ?? base;
    final note = period == PlanPeriod.year
        ? 'khoảng ${formatVnd((shown / 12).round())} mỗi tháng · tiết kiệm '
              '${PlanTable.yearlySavingPct(tier)}% so với trả từng tháng'
        : 'Trả theo năm chỉ ${formatVnd(PlanTable.price(tier, PlanPeriod.year))}';
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
                fontSize: 30,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                period == PlanPeriod.year ? '/năm' : '/tháng',
                style: LuxeText.caption,
              ),
            ),
            if (discounted != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
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
        Text(
          note,
          style: LuxeText.caption.copyWith(color: LuxeColors.champagne),
        ),
      ],
    );
  }
}

// ───────────────────────────── Bottom action ─────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.plan,
    required this.tier,
    required this.period,
    required this.promo,
    required this.onTrial,
    required this.onBuy,
  });

  final Entitlement plan;
  final PlanTier tier;
  final PlanPeriod period;
  final PromoQuote? promo;
  final Future<bool> Function() onTrial;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final covered = plan.isPremium && plan.tier.covers(tier);
    final price = formatVnd(
      promo?.finalPrice(tier, period) ?? PlanTable.price(tier, period),
    );
    final buyLabel =
        'Chọn ${tier.label} · $price/${period == PlanPeriod.year ? 'năm' : 'tháng'}';
    final trial = plan.trialAvailable && !plan.isPremium;
    final Widget content;
    if (covered) {
      content = LuxeNotice(
        key: const ValueKey('premium-current'),
        icon: Icons.check_circle_outline_rounded,
        color: LuxeColors.emerald,
        message: plan.tier == tier
            ? 'Bạn đang dùng gói này.'
            : 'Gói ${plan.tier.label} của bạn đã gồm mọi thứ của ${tier.label}.',
      );
    } else if (trial) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LuxeSubmitButton(
            key: const ValueKey('premium-trial-ultra'),
            label: 'Dùng thử Ultra miễn phí ${plan.trialDays} ngày',
            busyLabel: 'Đang mở dùng thử…',
            doneLabel: 'Đã mở dùng thử',
            icon: Icons.auto_awesome_rounded,
            onPressed: onTrial,
          ),
          TextButton(
            key: ValueKey('premium-buy-${tier.id}'),
            onPressed: onBuy,
            child: Text(buyLabel, textAlign: TextAlign.center),
          ),
        ],
      );
    } else {
      content = FilledButton(
        key: ValueKey('premium-buy-${tier.id}'),
        onPressed: onBuy,
        child: Text(buyLabel, textAlign: TextAlign.center),
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xF2080809),
        border: Border(top: BorderSide(color: LuxeColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: content,
        ),
      ),
    );
  }
}

// ───────────────────────────── Folded sections ─────────────────────────────

class _Fold extends StatefulWidget {
  const _Fold({
    super.key,
    required this.foldKey,
    required this.icon,
    required this.title,
    required this.child,
    this.open,
    this.onToggle,
  });

  final Key foldKey;
  final IconData icon;
  final String title;
  final Widget child;

  /// Controlled when given (the promo opens itself once a code applies).
  final bool? open;
  final VoidCallback? onToggle;

  @override
  State<_Fold> createState() => _FoldState();
}

class _FoldState extends State<_Fold> {
  bool _open = false;

  bool get _isOpen => widget.open ?? _open;

  Widget get _body => _isOpen
      ? Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: widget.child,
        )
      : const SizedBox(width: double.infinity);

  @override
  Widget build(BuildContext context) => LuxeGlass(
    radius: 18,
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        Semantics(
          button: true,
          expanded: _isOpen,
          child: InkWell(
            key: widget.foldKey,
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              if (widget.onToggle != null) {
                widget.onToggle!();
              } else {
                setState(() => _open = !_open);
              }
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 18, color: LuxeColors.platinumMid),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: LuxeColors.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _isOpen ? 0.5 : 0,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      child: const Icon(
                        Icons.expand_more_rounded,
                        color: LuxeColors.dim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // QA 138: under reduce motion open/close in one step. An
        // AnimatedSize with a zero duration re-dirties itself during layout
        // (framework assertion).
        if (MediaQuery.disableAnimationsOf(context))
          _body
        else
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: LuxeMotion.enter,
            alignment: Alignment.topCenter,
            child: _body,
          ),
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
              'Mã ${applied!.code}: giảm ${applied!.percentOff}%'
              '${applied!.validTo != null ? ' · đến ${_date(applied!.validTo!)}' : ''}. '
              'Giá đã giảm hiện ở trên.',
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
          prefixIcon: const Icon(Icons.confirmation_number_rounded),
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
    ('Lịch sử sạc', '30 ngày', 'Đầy đủ', 'Đầy đủ'),
    ('Sạc đến % tự tắt, đổi mục tiêu', '—', '✓', '✓'),
    ('Lộ trình', '—', '✓', '✓'),
    ('% pin chai, bài kiểm tra', '—', '✓', '✓'),
    ('Giao diện tùy chọn, xuất file', '—', '✓', '✓'),
    ('Số xe', '1', '2', '10'),
    ('Sạc đêm an toàn', '—', '—', '✓'),
    ('AI cá nhân (huấn luyện)', '—', '—', '✓'),
    ('Giao diện Aurora', '—', '—', '✓'),
    ('Trợ giúp & khắc phục sự cố', '✓', '✓', '✓'),
  ];

  @override
  Widget build(BuildContext context) {
    Widget cell(String text, {bool head = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color ?? (text == '—' ? LuxeColors.dim : LuxeColors.text),
          fontSize: head ? 12.5 : 12.5,
          fontWeight: head ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.3),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1.1),
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
            cell('Pro', head: true, color: PlanColors.steelText),
            cell('Ultra', head: true, color: PlanColors.lavender),
          ],
        ),
        for (final (label, free, pro, ultra) in _rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Text(label, style: LuxeText.caption),
              ),
              cell(free),
              cell(pro),
              cell(ultra),
            ],
          ),
      ],
    );
  }
}
