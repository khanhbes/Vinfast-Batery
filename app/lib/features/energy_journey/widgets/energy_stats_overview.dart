import 'package:flutter/material.dart';

import '../../../../core/theme/cockpit_design_system.dart';

/// Card summarizing environmental and distance impacts of total charged energy.
class EnergyStatsOverview extends StatelessWidget {
  const EnergyStatsOverview({
    super.key,
    required this.totalKWh,
    required this.co2KgSaved,
    required this.equivalentKmDriven,
    required this.treesEquivalent,
  });

  final double totalKWh;
  final double co2KgSaved;
  final double equivalentKmDriven;
  final double treesEquivalent;

  @override
  Widget build(BuildContext context) => CockpitSurface(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.eco_rounded,
                  size: 18,
                  color: CockpitColors.emerald,
                ),
                const SizedBox(width: 8),
                Text(
                  'Tác động tích cực tới môi trường',
                  style: TextStyle(
                    color: CockpitColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatBox(
                    label: 'Năng lượng nạp',
                    value: '${totalKWh.toStringAsFixed(1)} kWh',
                    icon: Icons.bolt_rounded,
                    accentColor: CockpitColors.emerald,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatBox(
                    label: 'Giảm phát thải CO₂',
                    value: '${co2KgSaved.toStringAsFixed(1)} kg',
                    icon: Icons.cloud_off_rounded,
                    accentColor: const Color(0xFF06B6D4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _StatBox(
                    label: 'Quãng đường xanh',
                    value: '~${equivalentKmDriven.round()} km',
                    icon: Icons.two_wheeler_rounded,
                    accentColor: const Color(0xFF3B82F6),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatBox(
                    label: 'Tương đương',
                    value: '~${treesEquivalent.toStringAsFixed(1)} cây xanh',
                    icon: Icons.forest_rounded,
                    accentColor: const Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CockpitColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CockpitColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: CockpitTypography.numbers(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: CockpitColors.text,
              ),
            ),
          ],
        ),
      );
}
