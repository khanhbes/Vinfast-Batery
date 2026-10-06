import 'package:flutter/material.dart';

import '../../../../core/theme/cockpit_design_system.dart';
import '../models/energy_level.dart';

enum MilestoneState { unlocked, current, locked }

/// Card displaying one level milestone on the Energy Journey screen.
class EnergyMilestoneCard extends StatelessWidget {
  const EnergyMilestoneCard({
    super.key,
    required this.level,
    required this.state,
    required this.totalKWh,
  });

  final EnergyLevel level;
  final MilestoneState state;
  final double totalKWh;

  @override
  Widget build(BuildContext context) {
    final isCurrent = state == MilestoneState.current;
    final isUnlocked = state == MilestoneState.unlocked;
    final isLocked = state == MilestoneState.locked;

    final badgeColor = isLocked ? CockpitColors.dim : level.badgeColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCurrent
            ? level.badgeColor.withValues(alpha: .08)
            : CockpitColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrent
              ? level.badgeColor.withValues(alpha: .5)
              : isUnlocked
                  ? level.badgeColor.withValues(alpha: .2)
                  : CockpitColors.border,
          width: isCurrent ? 1.5 : 1.0,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: level.badgeColor.withValues(alpha: .12),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Level Number & Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLocked
                  ? Colors.white.withValues(alpha: .04)
                  : level.badgeColor.withValues(alpha: .15),
              border: Border.all(
                color: isLocked
                    ? CockpitColors.border
                    : level.badgeColor.withValues(alpha: .4),
              ),
            ),
            child: Center(
              child: Icon(
                isLocked ? Icons.lock_outline_rounded : level.icon,
                size: 22,
                color: badgeColor,
              ),
            ),
          ),

          const SizedBox(width: 14),

          // Center: Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'CẤP ${level.level}',
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· ${level.tierName}',
                      style: TextStyle(
                        color: CockpitColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: level.badgeColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'HIỆN TẠI',
                          style: TextStyle(
                            color: Color(0xFF042F2E),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      )
                    else if (isUnlocked)
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: CockpitColors.emerald,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  level.name,
                  style: TextStyle(
                    color: isLocked ? CockpitColors.muted : CockpitColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  level.description,
                  style: TextStyle(
                    color: CockpitColors.dim,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 14,
                      color: isLocked ? CockpitColors.dim : level.badgeColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Mốc: ${level.thresholdKWh.toStringAsFixed(0)} kWh',
                      style: CockpitTypography.numbers(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isLocked ? CockpitColors.dim : CockpitColors.muted,
                      ),
                    ),
                    if (isLocked) ...[
                      const SizedBox(width: 8),
                      Text(
                        '· Còn ${(level.thresholdKWh - totalKWh).clamp(0.0, 99999.0).toStringAsFixed(1)} kWh',
                        style: TextStyle(
                          color: CockpitColors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
