import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../controllers/achievements_controller.dart';
import 'achievement_detail_sheet.dart';
import 'achievement_medal.dart';

/// Compact entry on the charging screen: rank medal, points, progress to
/// the next rank and the nearest achievement to chase.
class AchievementsTeaserCard extends StatelessWidget {
  const AchievementsTeaserCard({
    super.key,
    required this.state,
    required this.onTap,
  });

  final AchievementsState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rank = state.rank;
    final next = state.upNext.isEmpty ? null : state.upNext.first;
    return Semantics(
      button: true,
      label:
          'Thành tựu, ${rank.name}, ${state.points} điểm, ${state.unlockedCount} trên ${state.total} huy hiệu',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: const Color(0x1434D399),
          child: LuxeGlass(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(
              children: [
                AchievementMedal(
                  rarity: rank.rarity,
                  icon: Icons.workspace_premium_rounded,
                  size: 56,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'Thành tựu',
                            style: TextStyle(
                              color: LuxeColors.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            rank.name,
                            style: TextStyle(
                              color: rank.rarity.metal[0],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${state.points} điểm · ${state.unlockedCount}/${state.total} huy hiệu',
                        style: const TextStyle(
                          color: LuxeColors.muted,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LuxeProgressBar(value: state.rankProgress, height: 4),
                      if (next != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Sắp mở: ${next.def.title} · ${next.label}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: LuxeColors.dim,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: LuxeColors.platinumMid,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
