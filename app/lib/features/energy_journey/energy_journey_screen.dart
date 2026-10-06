import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cockpit_design_system.dart';
import 'controllers/energy_journey_controller.dart';
import 'models/energy_level.dart';
import 'widgets/energy_milestone_card.dart';
import 'widgets/energy_stats_overview.dart';
import 'widgets/level_up_celebration_dialog.dart';

/// Full screen gamification experience representing the user's 36-level
/// charging milestone journey.
class EnergyJourneyScreen extends ConsumerStatefulWidget {
  const EnergyJourneyScreen({super.key});

  @override
  ConsumerState<EnergyJourneyScreen> createState() =>
      _EnergyJourneyScreenState();
}

class _EnergyJourneyScreenState extends ConsumerState<EnergyJourneyScreen> {
  int _selectedTierFilter = 0; // 0: All, 1..6: specific tier

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(energyJourneyControllerProvider);
    final controller = ref.read(energyJourneyControllerProvider.notifier);

    // Listen for level up celebration
    ref.listen<EnergyJourneyState>(
      energyJourneyControllerProvider,
      (previous, next) {
        if (next.newLevelCelebration != null &&
            previous?.newLevelCelebration != next.newLevelCelebration) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            LevelUpCelebrationDialog.show(
              context,
              level: next.newLevelCelebration!,
              onDismiss: controller.dismissCelebration,
            );
          });
        }
      },
    );

    final currentLevel = state.currentLevel;
    final nextLevel = state.nextLevel;

    final filteredLevels = _selectedTierFilter == 0
        ? EnergyLevel.allLevels
        : EnergyLevel.allLevels
            .where((l) => l.tier == _selectedTierFilter)
            .toList();

    return Scaffold(
      backgroundColor: CockpitColors.background,
      appBar: AppBar(
        backgroundColor: CockpitColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: CockpitColors.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Hành trình năng lượng',
          style: TextStyle(
            color: CockpitColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            // ── Hero Level Header Card ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: CockpitColors.shell,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: currentLevel.badgeColor.withValues(alpha: .35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: currentLevel.badgeColor.withValues(alpha: .08),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Glowing icon avatar
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: currentLevel.badgeColor.withValues(alpha: .15),
                          border: Border.all(
                            color: currentLevel.badgeColor,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: currentLevel.badgeColor.withValues(alpha: .3),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Icon(
                          currentLevel.icon,
                          size: 32,
                          color: currentLevel.badgeColor,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: currentLevel.badgeColor.withValues(alpha: .15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'CẤP ${currentLevel.level}',
                                    style: TextStyle(
                                      color: currentLevel.badgeColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  currentLevel.tierName,
                                  style: TextStyle(
                                    color: CockpitColors.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currentLevel.name,
                              style: TextStyle(
                                color: CockpitColors.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Đã tích lũy ${state.totalKWh.toStringAsFixed(1)} kWh',
                              style: TextStyle(
                                color: CockpitColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Progress to next level bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            nextLevel != null
                                ? 'Tiến độ lên Cấp ${nextLevel.level}: ${nextLevel.name}'
                                : 'Đã đạt cấp tối đa!',
                            style: TextStyle(
                              color: CockpitColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (nextLevel != null)
                            Text(
                              'Còn ${state.remainingKWhToNext.toStringAsFixed(1)} kWh',
                              style: TextStyle(
                                color: currentLevel.badgeColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 6,
                          child: LinearProgressIndicator(
                            value: state.progressToNext,
                            backgroundColor: Colors.white.withValues(alpha: .08),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              currentLevel.badgeColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Environmental & EV Stats Card ──
            EnergyStatsOverview(
              totalKWh: state.totalKWh,
              co2KgSaved: state.co2KgSaved,
              equivalentKmDriven: state.equivalentKmDriven,
              treesEquivalent: state.treesEquivalent,
            ),

            const SizedBox(height: 24),

            // ── Tier Tabs Selector ──
            Row(
              children: [
                const Icon(
                  Icons.map_rounded,
                  size: 18,
                  color: CockpitColors.emerald,
                ),
                const SizedBox(width: 8),
                Text(
                  '36 Mốc hành trình',
                  style: TextStyle(
                    color: CockpitColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _TierChip(
                    label: 'Tất cả (36)',
                    isSelected: _selectedTierFilter == 0,
                    onTap: () => setState(() => _selectedTierFilter = 0),
                  ),
                  for (var t = 1; t <= 6; t++) ...[
                    const SizedBox(width: 8),
                    _TierChip(
                      label: switch (t) {
                        1 => 'Tier 1: Hạt mầm',
                        2 => 'Tier 2: Khởi nguyên',
                        3 => 'Tier 3: Đô thị',
                        4 => 'Tier 4: Trạm phát',
                        5 => 'Tier 5: Lưới điện',
                        _ => 'Tier 6: Vũ trụ',
                      },
                      isSelected: _selectedTierFilter == t,
                      onTap: () => setState(() => _selectedTierFilter = t),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Milestone Cards List ──
            for (final level in filteredLevels) ...[
              EnergyMilestoneCard(
                level: level,
                state: level.level < currentLevel.level
                    ? MilestoneState.unlocked
                    : level.level == currentLevel.level
                        ? MilestoneState.current
                        : MilestoneState.locked,
                totalKWh: state.totalKWh,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: CockpitMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? CockpitColors.emerald.withValues(alpha: .15)
                : Colors.white.withValues(alpha: .04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? CockpitColors.emerald
                  : CockpitColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? CockpitColors.emerald
                  : CockpitColors.muted,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
}
