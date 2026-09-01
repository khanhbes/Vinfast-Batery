import 'package:flutter/material.dart';

import '../../../core/theme/cockpit_design_system.dart';

/// Premium bottom sheet showing detailed charging prediction with
/// CC/CV phase breakdown, cost estimation, and range added.
class PredictionDetailSheet extends StatelessWidget {
  const PredictionDetailSheet({
    super.key,
    required this.currentSoc,
    required this.targetSoc,
    required this.estimatedMinutes,
    required this.stopTime,
    required this.personalizationLabel,
    this.energyWh,
    this.costVnd,
    this.rangeAddedKm,
    this.phases = const [],
    this.etaCandidates = const [],
  });

  final int currentSoc;
  final int targetSoc;
  final int estimatedMinutes;
  final String stopTime;
  final String personalizationLabel;
  final double? energyWh;
  final double? costVnd;
  final int? rangeAddedKm;
  final List<ChargingPhaseInfo> phases;
  final List<EtaCandidateInfo> etaCandidates;

  static Future<void> show(
    BuildContext context, {
    required int currentSoc,
    required int targetSoc,
    required int estimatedMinutes,
    required String stopTime,
    required String personalizationLabel,
    double? energyWh,
    double? costVnd,
    int? rangeAddedKm,
    List<ChargingPhaseInfo> phases = const [],
    List<EtaCandidateInfo> etaCandidates = const [],
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: .72),
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.92,
          minChildSize: 0.5,
          builder: (context, scrollController) => PredictionDetailSheet(
            currentSoc: currentSoc,
            targetSoc: targetSoc,
            estimatedMinutes: estimatedMinutes,
            stopTime: stopTime,
            personalizationLabel: personalizationLabel,
            energyWh: energyWh,
            costVnd: costVnd,
            rangeAddedKm: rangeAddedKm,
            phases: phases,
            etaCandidates: etaCandidates,
          ),
        ),
      );

  String _formatDuration(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h > 0) return '$h giờ $m phút';
    return '$m phút';
  }

  String _formatEnergy(double wh) => wh >= 1000
      ? '${(wh / 1000).toStringAsFixed(2)} kWh'
      : '${wh.toStringAsFixed(0)} Wh';

  String _formatCost(double vnd) =>
      '~${vnd.round().toString().replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+$)'),
            (m) => '${m[1]}.',
          )} đ';

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: CockpitColors.shell,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(CockpitRadius.sheet),
          ),
          border: Border.all(color: CockpitColors.border),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CockpitColors.dim,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Row(
              children: [
                Icon(
                  Icons.analytics_rounded,
                  size: 22,
                  color: CockpitColors.emerald,
                ),
                const SizedBox(width: 10),
                Text(
                  'Chi tiết dự đoán sạc',
                  style: TextStyle(
                    color: CockpitColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              personalizationLabel,
              style: TextStyle(
                color: CockpitColors.emerald,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 20),

            // Hero stats grid
            Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    label: 'Thời gian',
                    value: _formatDuration(estimatedMinutes),
                    icon: Icons.schedule_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeroStat(
                    label: 'Mục tiêu',
                    value: '$currentSoc% → $targetSoc%',
                    icon: Icons.battery_charging_full_rounded,
                    valueColor: CockpitColors.emerald,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (energyWh != null)
                  Expanded(
                    child: _HeroStat(
                      label: 'Năng lượng',
                      value: _formatEnergy(energyWh!),
                      icon: Icons.bolt_rounded,
                    ),
                  ),
                if (energyWh != null && costVnd != null)
                  const SizedBox(width: 10),
                if (costVnd != null)
                  Expanded(
                    child: _HeroStat(
                      label: 'Chi phí',
                      value: _formatCost(costVnd!),
                      icon: Icons.payments_rounded,
                      valueColor: CockpitColors.amber,
                    ),
                  ),
              ],
            ),
            if (rangeAddedKm != null) ...[
              const SizedBox(height: 10),
              _HeroStat(
                label: 'Quãng đường thêm',
                value: '+$rangeAddedKm km',
                icon: Icons.route_rounded,
                valueColor: CockpitColors.info,
              ),
            ],

            const SizedBox(height: 10),
            _InfoTile(
              icon: Icons.alarm_rounded,
              label: 'Dự kiến hoàn thành',
              value: stopTime,
              valueColor: CockpitColors.amber,
            ),

            // CC/CV Phase breakdown
            if (phases.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'CÁC PHA SẠC',
                style: TextStyle(
                  color: CockpitColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              for (final phase in phases) ...[
                _PhaseTile(phase: phase),
                if (phase != phases.last)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 18),
                        Container(
                          width: 2,
                          height: 16,
                          decoration: BoxDecoration(
                            color: CockpitColors.border,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],

            // ETA Candidates
            if (etaCandidates.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'NGUỒN DỰ ĐOÁN',
                style: TextStyle(
                  color: CockpitColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              for (final candidate in etaCandidates)
                _EtaCandidateTile(candidate: candidate),
            ],
          ],
        ),
      );
}

/// Data classes for phase info
class ChargingPhaseInfo {
  const ChargingPhaseInfo({
    required this.name,
    required this.description,
    required this.fromPercent,
    required this.toPercent,
    required this.minutes,
    required this.powerW,
  });
  final String name;
  final String description;
  final int fromPercent;
  final int toPercent;
  final int minutes;
  final int powerW;
}

class EtaCandidateInfo {
  const EtaCandidateInfo({
    required this.source,
    required this.label,
    required this.durationSeconds,
    required this.weight,
  });
  final String source;
  final String label;
  final int durationSeconds;
  final double weight;
}

// ─────────────────────────────────────────────────────────────────────────────

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CockpitColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: CockpitColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: CockpitColors.muted),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: CockpitColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: CockpitTypography.numbers(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: valueColor ?? CockpitColors.text,
              ),
            ),
          ],
        ),
      );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CockpitColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: CockpitColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: CockpitColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: CockpitColors.muted,
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              value,
              style: CockpitTypography.numbers(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: valueColor ?? CockpitColors.text,
              ),
            ),
          ],
        ),
      );
}

class _PhaseTile extends StatelessWidget {
  const _PhaseTile({required this.phase});
  final ChargingPhaseInfo phase;

  @override
  Widget build(BuildContext context) {
    final isCC = phase.name.contains('CC');
    final phaseColor = isCC ? CockpitColors.emerald : CockpitColors.info;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CockpitColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: phaseColor.withValues(alpha: .20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: phaseColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  phase.name,
                  style: TextStyle(
                    color: CockpitColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${phase.fromPercent}% → ${phase.toPercent}%',
                style: CockpitTypography.numbers(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: phaseColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            phase.description,
            style: TextStyle(
              color: CockpitColors.dim,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _PhaseChip(
                icon: Icons.schedule_rounded,
                value: '${phase.minutes} phút',
              ),
              const SizedBox(width: 8),
              _PhaseChip(
                icon: Icons.bolt_rounded,
                value: '${phase.powerW} W',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.icon, required this.value});
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: CockpitColors.muted),
            const SizedBox(width: 4),
            Text(
              value,
              style: CockpitTypography.numbers(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _EtaCandidateTile extends StatelessWidget {
  const _EtaCandidateTile({required this.candidate});
  final EtaCandidateInfo candidate;

  @override
  Widget build(BuildContext context) {
    final minutes = (candidate.durationSeconds / 60).round();
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final durationText = h > 0 ? '$h giờ $m phút' : '$m phút';
    final weightPct = (candidate.weight * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CockpitColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CockpitColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: CockpitColors.emerald.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _iconForSource(candidate.source),
                size: 16,
                color: CockpitColors.emerald,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.label,
                    style: TextStyle(
                      color: CockpitColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    durationText,
                    style: CockpitTypography.numbers(
                      fontSize: 11,
                      color: CockpitColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: CockpitColors.emerald.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$weightPct%',
                style: CockpitTypography.numbers(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: CockpitColors.emerald,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForSource(String source) => switch (source) {
        'personal' => Icons.person_rounded,
        'global_ai' => Icons.psychology_rounded,
        'physics' => Icons.science_rounded,
        _ => Icons.auto_awesome_rounded,
      };
}
