import 'package:flutter/material.dart';
import '../services/guide_registry.dart';
import '../theme/luxe_theme.dart';
import '../theme/plan_style.dart';

/// LUXE tab bar: a dark rail with a hairline top edge and one platinum glass
/// "jewel" that glides to the selected destination, topped by a short emerald
/// light line. Equal-width destinations; motion is instant in reduced motion.
class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const destinations = [
    (Icons.dashboard_rounded, 'Tổng quan'),
    (Icons.bolt_rounded, 'Sạc pin'),
    (Icons.history_rounded, 'Lịch sử'),
    (Icons.tune_rounded, 'Cài đặt'),
  ];

  /// Rail colour, shared with the system navigation bar.
  static const railColor = Color(0xFF08090A);

  static Key? _guideKey(int i) => switch (i) {
    1 => GuideRegistry.keyChargeTab,
    2 => GuideRegistry.keyHistoryTab,
    3 => GuideRegistry.keyMoreSettingsTab,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    // Keep the label readable at large system text sizes. A fixed 58dp
    // viewport clips labels at 200% and causes a RenderFlex overflow.
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final barHeight = (58 * textScale).clamp(58.0, 104.0);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final glide = reduce ? Duration.zero : const Duration(milliseconds: 420);
    final fade = reduce ? Duration.zero : const Duration(milliseconds: 240);
    final n = destinations.length;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: railColor,
        border: Border(top: BorderSide(color: LuxeColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: SizedBox(
            height: barHeight,
            child: Stack(
              children: [
                // The gliding jewel sits beneath the destinations.
                AnimatedAlign(
                  duration: glide,
                  curve: LuxeMotion.enter,
                  alignment: Alignment(-1 + 2 * selectedIndex / (n - 1), 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / n,
                    heightFactor: 1,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 3),
                      child: _Jewel(),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: Semantics(
                          selected: selectedIndex == i,
                          button: true,
                          label: destinations[i].$2,
                          hint: 'Chuyển sang màn hình ${destinations[i].$2}',
                          onTap: () => onSelected(i),
                          child: KeyedSubtree(
                            key: ValueKey('navigation-destination-$i'),
                            child: _Destination(
                              key: _guideKey(i),
                              icon: destinations[i].$1,
                              label: destinations[i].$2,
                              selected: selectedIndex == i,
                              duration: fade,
                              onTap: () => onSelected(i),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Jewel extends StatelessWidget {
  const _Jewel();

  @override
  Widget build(BuildContext context) {
    // QA 136: the light line takes the plan (Pro steel, Ultra aurora).
    final plan = PlanStyle.of(context);
    Widget line(Gradient? gradient) => Container(
      width: plan.isUltra ? 30 : 22,
      height: 2,
      decoration: BoxDecoration(
        color: gradient == null ? plan.accent : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: plan.accent.withValues(alpha: 0.55),
            blurRadius: plan.isUltra ? 14 : 10,
          ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: plan.isUltra
              ? const [Color(0x268B5CF6), Color(0x0A22D3EE)]
              : const [LuxeColors.hairline, Color(0x08FFFFFF)],
        ),
        border: Border.all(
          color: plan.tier == PlanStyle.free.tier
              ? LuxeColors.hairlineStrong
              : plan.glassBorder,
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: plan.isUltra
            ? PlanFlow(
                builder: (context, phase) => line(planFlowGradient(phase)),
              )
            : line(null),
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    splashColor: PlanStyle.of(context).accent.withValues(alpha: 0.10),
    highlightColor: Colors.white.withValues(alpha: 0.03),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TweenAnimationBuilder<Color?>(
          duration: duration,
          curve: LuxeMotion.enter,
          tween: ColorTween(
            end: selected
                ? PlanStyle.of(context).accent
                : LuxeColors.platinumMid,
          ),
          builder: (context, color, _) => AnimatedScale(
            duration: duration,
            curve: LuxeMotion.enter,
            scale: selected ? 1.08 : 1.0,
            child: Icon(icon, size: 22, color: color),
          ),
        ),
        const SizedBox(height: 4),
        ExcludeSemantics(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: AnimatedDefaultTextStyle(
              duration: duration,
              curve: LuxeMotion.enter,
              style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.3,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? LuxeColors.text : LuxeColors.muted,
              ),
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
