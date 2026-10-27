import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/entitlement_provider.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/theme/plan_style.dart';
import '../../data/models/entitlement.dart';
import 'premium_screen.dart';

/// The plan's tag (QA 136): Free a quiet outline, Pro brushed silver with
/// one sheen when it appears, Ultra an aurora that keeps flowing (still
/// under "reduce motion" or with Ultra effects off).
class PlanTag extends StatelessWidget {
  const PlanTag({
    super.key,
    required this.tier,
    this.onTap,
    this.large = false,
    this.semanticLabel,
  });

  final PlanTier tier;

  /// Tappable tags get a 48 dp hit area around the pill.
  final VoidCallback? onTap;
  final bool large;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final pill = switch (tier) {
      PlanTier.free => _FreePill(large: large),
      PlanTier.pro => _ProPill(large: large),
      PlanTier.ultra => _UltraPill(large: large),
    };
    final label = semanticLabel ?? 'Gói ${tier.label}';
    if (onTap == null) {
      return Semantics(label: label, excludeSemantics: true, child: pill);
    }
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(widthFactor: 1, heightFactor: 1, child: pill),
        ),
      ),
    );
  }
}

/// The signed-in account's plan; opens Pinova Premium when tapped.
class CurrentPlanTag extends ConsumerWidget {
  const CurrentPlanTag({super.key, this.large = false, this.tappable = true});

  final bool large;
  final bool tappable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(entitlementProvider);
    if (!plan.known) return const SizedBox.shrink();
    return PlanTag(
      key: ValueKey('plan-tag-${plan.tier.id}'),
      tier: plan.tier,
      large: large,
      semanticLabel: plan.isTrial
          ? 'Đang dùng thử gói ${plan.tier.label}'
          : 'Gói ${plan.tier.label}',
      onTap: tappable ? () => PremiumScreen.open(context) : null,
    );
  }
}

EdgeInsets _padding(bool large) => large
    ? const EdgeInsets.symmetric(horizontal: 11, vertical: 4.5)
    : const EdgeInsets.symmetric(horizontal: 8, vertical: 3);

TextStyle _text(bool large, Color color) => TextStyle(
  color: color,
  fontSize: large ? 11.5 : 11, // QA 139: 10 px was the smallest text
  height: 1.2,
  fontWeight: FontWeight.w800,
  letterSpacing: 1.4,
);

class _FreePill extends StatelessWidget {
  const _FreePill({required this.large});
  final bool large;

  @override
  Widget build(BuildContext context) => Container(
    padding: _padding(large),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: LuxeColors.glass,
      border: Border.all(color: LuxeColors.hairlineStrong),
    ),
    child: Text('FREE', style: _text(large, LuxeColors.muted)),
  );
}

class _ProPill extends StatelessWidget {
  const _ProPill({required this.large});
  final bool large;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: _padding(large),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PlanColors.silverHi, PlanColors.silver, PlanColors.steel],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: const Color(0x99FFFFFF), width: 0.8),
        boxShadow: const [
          BoxShadow(color: Color(0x338FA9D6), blurRadius: 10, spreadRadius: -2),
        ],
      ),
      child: Text('PRO', style: _text(large, PlanColors.ink)),
    );
    if (MediaQuery.disableAnimationsOf(context)) return pill;
    // One sheen across the metal when the tag appears; nothing loops.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -1, end: 2),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeInOutCubic,
      child: pill,
      builder: (context, t, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(t - 0.6, -1),
          end: Alignment(t + 0.6, 1),
          colors: const [
            Color(0x00FFFFFF),
            Color(0x88FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: const [0.3, 0.5, 0.7],
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

class _UltraPill extends StatelessWidget {
  const _UltraPill({required this.large});
  final bool large;

  @override
  Widget build(BuildContext context) => PlanFlow(
    builder: (context, phase) => Container(
      padding: _padding(large),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: planFlowGradient(phase),
        border: Border.all(color: const Color(0x80FFFFFF), width: 0.8),
        boxShadow: const [
          BoxShadow(color: Color(0x668B5CF6), blurRadius: 14, spreadRadius: -3),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: large ? 12 : 11,
            color: PlanColors.ink,
          ),
          const SizedBox(width: 3),
          Text('ULTRA', style: _text(large, PlanColors.ink)),
        ],
      ),
    ),
  );
}
