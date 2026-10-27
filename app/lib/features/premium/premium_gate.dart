import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/entitlement_provider.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../data/models/entitlement.dart';
import 'plan_tag.dart';
import 'premium_screen.dart';

/// Premium gates in the app (QA 135). The server is the authority; these
/// only explain a lock before the owner runs into a server refusal.
abstract final class PremiumGate {
  /// True when [feature] is in the plan; otherwise shows the upgrade sheet.
  static bool check(
    BuildContext context,
    WidgetRef ref,
    PremiumFeature feature,
  ) {
    if (ref.read(entitlementProvider).allows(feature)) return true;
    showUpgrade(context, feature);
    return false;
  }

  /// The server refused because of the plan (HTTP 403 `premiumRequired`).
  static bool isPremiumError(Object? error) {
    final text = error?.toString() ?? '';
    return text.contains('premiumRequired') ||
        text.contains('cần gói Pro') ||
        text.contains('cần gói Ultra');
  }

  /// The account reached its plan's vehicle limit (server 409
  /// `vehicleLimitReached`).
  static Future<void> showVehicleLimit(BuildContext context) {
    final plan = ProviderScope.containerOf(context).read(entitlementProvider);
    final next = plan.tier == PlanTier.free ? PlanTier.pro : PlanTier.ultra;
    return _sheet(
      context,
      tier: next,
      title: 'Thêm xe',
      message:
          'Gói ${plan.tier.label} có tối đa ${plan.maxVehicles} xe. '
          'Pro có ${PlanTable.maxVehicles[PlanTier.pro]} xe, Ultra tối đa '
          '${PlanTable.maxVehicles[PlanTier.ultra]} xe.',
      highlight: null,
    );
  }

  static Future<void> showUpgrade(
    BuildContext context,
    PremiumFeature feature,
  ) => _sheet(
    context,
    tier: feature.tier,
    title: feature.label,
    message:
        'Tính năng này có trong gói ${feature.tier.label}'
        '${feature.tier == PlanTier.pro ? ' và Ultra' : ''}. '
        'Bạn có thể dùng thử miễn phí 7 ngày, không cần thanh toán.',
    highlight: feature,
  );

  static Future<void> _sheet(
    BuildContext context, {
    required PlanTier tier,
    required String title,
    required String message,
    required PremiumFeature? highlight,
  }) => showLuxeSheet<void>(
    context,
    builder: (sheet) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LuxeSheetHeader(
            key: const ValueKey('premium-gate-sheet'),
            eyebrow: 'Pinova ${tier.label}',
            title: title,
            trailing: PremiumBadge(tier: tier),
          ),
          const SizedBox(height: 10),
          Text(message, style: LuxeText.body),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('premium-gate-open'),
              onPressed: () {
                Navigator.of(sheet).pop();
                PremiumScreen.open(context, highlight: highlight);
              },
              child: const Text('Xem gói Premium'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(sheet).pop(),
              child: const Text('Để sau'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// "PRO" / "ULTRA" tag next to a locked entry.
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key, required this.tier});
  final PlanTier tier;

  @override
  Widget build(BuildContext context) => PlanTag(tier: tier);
}

/// An entry to a feature outside the plan (QA 136): drawn in grey, does not
/// react to taps, and only its plan tag is tappable (opens Pinova Premium
/// at that feature). Inside the plan it is just [child].
///
/// QA 139: grey and a little darker instead of 38 % opacity, so the text
/// that sells the feature stays readable (secondary text about 4.8:1)
/// while icons and accents lose their colour; it fills its parent like the
/// child would (a locked grid tile used to shrink to half width).
class PremiumLocked extends ConsumerWidget {
  const PremiumLocked({
    super.key,
    required this.feature,
    required this.child,
    this.tagAlignment = AlignmentDirectional.topEnd,
    this.tagPadding = const EdgeInsets.all(4),
    this.allowed,
    this.reserveTagSpace = false,
  });

  final PremiumFeature feature;
  final Widget child;

  /// The answer when the screen already holds it (no provider read).
  final bool? allowed;

  /// Rows: keep the tag's width free at the end so it never covers the
  /// row's text (QA 137: "ULTRA" sat on "…ngắt sớm khi ổ nóng").
  final bool reserveTagSpace;
  final AlignmentGeometry tagAlignment;
  final EdgeInsetsGeometry tagPadding;

  /// Brightness kept after the grey filter.
  static const lockedBrightness = 0.8;

  static const _lum = [0.2126, 0.7152, 0.0722];

  /// Luminance grey scaled by [lockedBrightness]; alpha unchanged.
  static final ColorFilter lockedFilter = ColorFilter.matrix([
    for (var row = 0; row < 3; row++) ...[
      for (final w in _lum) w * lockedBrightness,
      0,
      0,
    ],
    0,
    0,
    0,
    1,
    0,
  ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool open =
        allowed ??
        ref.watch(
          entitlementProvider.select<bool>((plan) => plan.allows(feature)),
        );
    if (open) return child;
    final tier = feature.tier;
    final scaler = MediaQuery.textScalerOf(context);
    // QA 138 (QA-08): at large text the tag sits above the row; reserving
    // its scaled width at the end left no room for the row itself.
    final stacked = reserveTagSpace && scaler.scale(1) > 1.3;
    return Stack(
      key: ValueKey('premium-locked-${feature.id}'),
      fit: StackFit.passthrough,
      children: [
        Semantics(
          label: '${feature.label}, cần gói ${tier.label}',
          enabled: false,
          excludeSemantics: true,
          child: IgnorePointer(
            child: ColorFiltered(
              colorFilter: lockedFilter,
              child: !reserveTagSpace
                  ? child
                  : Padding(
                      padding: stacked
                          ? EdgeInsets.only(top: scaler.scale(30))
                          : EdgeInsetsDirectional.only(
                              end: scaler.scale(
                                tier == PlanTier.ultra ? 74 : 50,
                              ),
                            ),
                      child: child,
                    ),
            ),
          ),
        ),
        Positioned.fill(
          child: Align(
            alignment: stacked ? AlignmentDirectional.topEnd : tagAlignment,
            child: Padding(
              padding: stacked
                  ? const EdgeInsetsDirectional.only(top: 4, end: 10)
                  : tagPadding,
              child: PlanTag(
                key: ValueKey('premium-locked-tag-${feature.id}'),
                tier: tier,
                semanticLabel: 'Xem gói ${tier.label} để mở ${feature.label}',
                onTap: () => PremiumScreen.open(context, highlight: feature),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A feature screen behind the plan (QA 136): however it is reached (a tile,
/// Pinova Bot, a notification), without the plan it shows Pinova Premium
/// for that feature instead.
class PremiumRequired extends ConsumerWidget {
  const PremiumRequired({
    super.key,
    required this.feature,
    required this.child,
  });

  final PremiumFeature feature;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(
      entitlementProvider.select((plan) => plan.allows(feature)),
    );
    return allowed ? child : PremiumScreen(highlight: feature);
  }
}
