import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/theme/plan_style.dart';

/// The Sạc pin tab's three sections (QA 140): Sạc AI | Theo giờ | Lịch sử.
/// A glass track with a puck in the plan's accent that glides between them;
/// it stays visible while a charge runs, so History is always one tap away.
class ChargeSectionSwitcher extends StatelessWidget {
  const ChargeSectionSwitcher({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ChargeSection value;
  final ValueChanged<ChargeSection> onChanged;

  static const _items = [
    (ChargeSection.ai, Icons.auto_awesome_rounded, 'Sạc AI'),
    (ChargeSection.timed, Icons.schedule_rounded, 'Theo giờ'),
    (ChargeSection.history, Icons.history_rounded, 'Lịch sử'),
  ];

  @override
  Widget build(BuildContext context) {
    final plan = PlanStyle.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 380);
    final index = _items.indexWhere((item) => item.$1 == value);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          gradient: LinearGradient(colors: plan.glassColors),
          border: Border.all(color: plan.glassBorder),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedAlign(
                duration: duration,
                curve: const Cubic(0.65, 0.0, 0.35, 1.0),
                alignment: Alignment(-1 + index.toDouble(), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / _items.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: plan.accentColors,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x40000000),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final (section, icon, label) in _items)
                  Expanded(
                    child: _SectionTab(
                      icon: icon,
                      label: label,
                      selected: section == value,
                      duration: duration,
                      onTap: () {
                        if (section == value) return;
                        HapticFeedback.selectionClick();
                        onChanged(section);
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTab extends StatelessWidget {
  const _SectionTab({
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
  Widget build(BuildContext context) {
    // Ink reads on every plan's accent fill (≥ 4.5:1, QA 139).
    final color = selected ? PlanColors.ink : LuxeColors.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        splashColor: Colors.transparent,
        highlightColor: const Color(0x0AFFFFFF),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: color),
                      duration: duration,
                      builder: (context, c, _) =>
                          Icon(icon, size: 17, color: c),
                    ),
                    const SizedBox(width: 6),
                    AnimatedDefaultTextStyle(
                      duration: duration,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                      child: Text(label, maxLines: 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
