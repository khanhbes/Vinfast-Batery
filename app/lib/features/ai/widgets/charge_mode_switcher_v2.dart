import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';

/// Two-mode switch (Sạc AI / Sạc hẹn giờ): a glass track with a brushed
/// platinum puck that glides between the options.
class ChargeModeSwitcherV2 extends StatelessWidget {
  const ChargeModeSwitcherV2({
    super.key,
    required this.isAiMode,
    required this.onChanged,
  });

  final bool isAiMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 420);
    return Semantics(
      label: isAiMode ? 'Đang chọn sạc theo AI' : 'Đang chọn sạc hẹn giờ',
      child: Container(
        height: 56,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          gradient: const LinearGradient(
            colors: [Color(0x12FFFFFF), Color(0x06FFFFFF)],
          ),
          border: Border.all(color: LuxeColors.hairline),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: duration,
              curve: const Cubic(0.65, 0.0, 0.35, 1.0),
              alignment: isAiMode
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        LuxeColors.platinumHi,
                        LuxeColors.platinum,
                        Color(0xFFB9BCC1),
                      ],
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
            Row(
              children: [
                Expanded(
                  child: _ModeTab(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Sạc AI',
                    selected: isAiMode,
                    duration: duration,
                    onTap: () => _select(true),
                  ),
                ),
                Expanded(
                  child: _ModeTab(
                    icon: Icons.schedule_rounded,
                    label: 'Sạc hẹn giờ',
                    selected: !isAiMode,
                    duration: duration,
                    onTap: () => _select(false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _select(bool ai) {
    if (ai == isAiMode) return;
    HapticFeedback.selectionClick();
    onChanged(ai);
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
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
    final color = selected ? LuxeColors.shell : LuxeColors.muted;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        splashColor: Colors.transparent,
        highlightColor: const Color(0x0AFFFFFF),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: color),
                    duration: duration,
                    builder: (context, c, _) => Icon(icon, size: 18, color: c),
                  ),
                  const SizedBox(width: 8),
                  AnimatedDefaultTextStyle(
                    duration: duration,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                    child: Text(label, maxLines: 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
