import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/entitlement_provider.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/theme/plan_style.dart';
import 'premium_screen.dart';

/// Tab Cài đặt: the account's plan and the way into Pinova Premium.
class PremiumBanner extends ConsumerWidget {
  const PremiumBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(entitlementProvider);
    // QA 139: the plan's accent, not emerald (that means "verified").
    final accent = PlanStyle.of(context).accent;
    if (plan.known && !plan.serverSupportsBilling) {
      return const SizedBox.shrink();
    }
    final left = plan.daysLeft(DateTime.now());
    final title = plan.isTrial
        ? 'Dùng thử ${plan.tier.label} · còn ${left ?? 0} ngày'
        : plan.isPremium
        ? 'Pinova ${plan.tier.label}${left != null ? ' · còn $left ngày' : ''}'
        : 'Nâng cấp Pinova Premium';
    final caption = plan.isPremium
        ? 'Xem quyền lợi, gia hạn hoặc nhập mã khuyến mãi'
        : plan.trialAvailable
        ? 'Dùng thử ${plan.trialDays} ngày miễn phí: sạc đêm an toàn, sạc đến %, AI cá nhân'
        : 'Sạc đêm an toàn, sạc đến %, % pin chai, AI cá nhân';
    return Semantics(
      button: true,
      label: '$title. $caption',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('more-premium-banner'),
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            HapticFeedback.selectionClick();
            PremiumScreen.open(context);
          },
          child: Ink(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.alphaBlend(
                    accent.withValues(alpha: 0.08),
                    LuxeColors.raised,
                  ),
                  LuxeColors.sheet,
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.32)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.12),
                    border: Border.all(color: accent.withValues(alpha: 0.4)),
                  ),
                  child: Icon(Icons.workspace_premium_rounded, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: LuxeColors.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        caption,
                        style: LuxeText.caption.copyWith(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: LuxeColors.dim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
