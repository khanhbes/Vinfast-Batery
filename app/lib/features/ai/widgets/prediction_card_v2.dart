import 'package:flutter/material.dart';

import '../../../core/theme/cockpit_design_system.dart';

/// Premium prediction card showing AI estimation with stage badge.
/// Matches the EV cockpit reference's prediction display.
class PredictionCardV2 extends StatelessWidget {
  const PredictionCardV2({
    super.key,
    required this.durationMinutes,
    required this.stopTime,
    required this.fromSoc,
    required this.toSoc,
    required this.personalizationLabel,
    this.energyWh,
    this.costVnd,
    this.onViewDetails,
    this.warnings = const [],
  });

  final int durationMinutes;
  final String stopTime;
  final int fromSoc;
  final int toSoc;
  final String personalizationLabel;
  final double? energyWh;
  final double? costVnd;
  final VoidCallback? onViewDetails;
  final List<String> warnings;

  /// AI stage badge color based on personalization label.
  Color get _stageColor {
    if (personalizationLabel.contains('cá nhân') ||
        personalizationLabel.contains('personal')) {
      return CockpitColors.emerald;
    }
    if (personalizationLabel.contains('học') ||
        personalizationLabel.contains('learn')) {
      return CockpitColors.info;
    }
    return CockpitColors.amber;
  }

  String _formatDuration(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h > 0) return '$h giờ $m phút';
    return '$m phút';
  }

  String _formatEnergy(double wh) => wh >= 1000
      ? '${(wh / 1000).toStringAsFixed(2)} kWh'
      : '${wh.toStringAsFixed(0)} Wh';

  @override
  Widget build(BuildContext context) => CockpitSurface(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: _stageColor,
                ),
                const SizedBox(width: 6),
                Text(
                  'Kế hoạch sạc',
                  style: TextStyle(
                    color: CockpitColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            // SOC range badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: _stageColor.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _stageColor.withValues(alpha: .30),
                ),
              ),
              child: Text(
                '$fromSoc% → $toSoc%',
                style: CockpitTypography.numbers(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _stageColor,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Duration display (hero)
        Text(
          _formatDuration(durationMinutes),
          style: CockpitTypography.numbers(
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Dự kiến dừng lúc $stopTime',
          style: TextStyle(
            color: CockpitColors.muted,
            fontSize: 12,
          ),
        ),

        const SizedBox(height: 14),

        // Detail rows
        if (energyWh != null) ...[
          _DetailRow(
            label: 'Điện cần nạp',
            value: _formatEnergy(energyWh!),
          ),
          const SizedBox(height: 6),
        ],
        if (costVnd != null) ...[
          _DetailRow(
            label: 'Chi phí dự kiến',
            value: '~${costVnd!.round().toString().replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+$)'),
              (m) => '${m[1]}.',
            )} đ',
          ),
          const SizedBox(height: 6),
        ],

        // Personalization badge
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: _stageColor.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                personalizationLabel,
                style: TextStyle(
                  color: _stageColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onViewDetails != null)
              InkWell(
                onTap: onViewDetails,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Tinh chỉnh',
                        style: TextStyle(
                          color: CockpitColors.emerald,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: CockpitColors.emerald,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),

        // Warnings
        for (final warning in warnings) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: CockpitColors.amber,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  warning,
                  style: TextStyle(
                    color: CockpitColors.amber,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          color: CockpitColors.muted,
          fontSize: 12,
        ),
      ),
      Text(
        value,
        style: CockpitTypography.numbers(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}
