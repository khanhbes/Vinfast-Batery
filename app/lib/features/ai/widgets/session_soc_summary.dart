import 'package:flutter/material.dart';
import '../../../core/theme/cockpit_design_system.dart';
import '../../../data/models/smart_charging_session.dart';

/// Redesigned SOC Progress Card for session detail:
/// Shows Start SOC → End/Current SOC, Gain delta badge, Target marker, and visual progress bar.
class SessionSocSummary extends StatelessWidget {
  const SessionSocSummary({super.key, required this.session});
  final SmartChargingSession session;

  String _soc(double? value) =>
      value != null && value.isFinite && value >= 0 && value <= 100
          ? '${value.round()}%'
          : '—';

  @override
  Widget build(BuildContext context) {
    final confirmed = session.actualEndSoc;
    final estimated = session.estimatedSoc;
    final actualValid =
        confirmed != null &&
        confirmed.isFinite &&
        confirmed >= 0 &&
        confirmed <= 100;

    final startSoc = (session.startSoc >= 0 && session.startSoc <= 100)
        ? session.startSoc
        : 0.0;
    final endSoc = actualValid
        ? confirmed
        : (estimated != null && estimated >= 0 && estimated <= 100
            ? estimated
            : startSoc);
    final gain = (endSoc - startSoc).clamp(-100.0, 100.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CockpitColors.surface,
        borderRadius: BorderRadius.circular(CockpitRadius.large),
        border: Border.all(color: CockpitColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CockpitColors.emerald.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.battery_charging_full_rounded,
                  size: 20,
                  color: CockpitColors.emeraldStrong,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tiến trình sạc pin (SOC)',
                      style: CockpitTypography.heading(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: CockpitColors.text,
                      ),
                    ),
                    Text(
                      actualValid
                          ? 'Đã xác nhận kết thúc'
                          : (session.state.isTerminal
                              ? 'Ước tính kết thúc'
                              : 'Đang tiếp tục nạp'),
                      style: CockpitTypography.label(
                        fontSize: 11,
                        color: actualValid
                            ? CockpitColors.emeraldStrong
                            : CockpitColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (gain > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: CockpitColors.emerald.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: CockpitColors.emerald.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.trending_up_rounded,
                        size: 14,
                        color: CockpitColors.emeraldStrong,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '+${gain.round()}% pin',
                        style: CockpitTypography.numbers(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: CockpitColors.emeraldStrong,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 20),

          // Values comparison row
          Row(
            children: [
              // Start SOC
              Expanded(
                child: _SocBox(
                  label: 'Bắt đầu',
                  value: _soc(startSoc),
                  color: CockpitColors.muted,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: CockpitColors.dim,
                ),
              ),
              // Current/End SOC
              Expanded(
                child: _SocBox(
                  label: actualValid
                      ? 'Thực tế cuối'
                      : (session.state.isTerminal ? 'Ước tính cuối' : 'Hiện tại'),
                  value: _soc(endSoc),
                  color: CockpitColors.emeraldStrong,
                  isHighlighted: true,
                ),
              ),
              const SizedBox(width: 12),
              // Target SOC
              Expanded(
                child: _SocBox(
                  label: 'Mục tiêu',
                  value: _soc(session.targetSoc),
                  color: CockpitColors.info,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Visual Progress Bar
          Stack(
            children: [
              // Background track
              Container(
                height: 10,
                decoration: BoxDecoration(
                  color: CockpitColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              // Filled progress
              FractionallySizedBox(
                widthFactor: (endSoc / 100.0).clamp(0.0, 1.0),
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF059669),
                        CockpitColors.emeraldStrong,
                        Color(0xFF34D399),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: CockpitColors.emeraldStrong.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Clarification footer
          Text(
            actualValid
                ? '✓ SOC cuối được ghi nhận theo thông số người dùng xác nhận.'
                : '• Số đo SOC ước tính dựa trên công suất nạp lưới và dung lượng xe.',
            style: CockpitTypography.label(
              fontSize: 11,
              color: CockpitColors.dim,
            ),
          ),
        ],
      ),
    );
  }
}

class _SocBox extends StatelessWidget {
  const _SocBox({
    required this.label,
    required this.value,
    required this.color,
    this.isHighlighted = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isHighlighted
            ? color.withValues(alpha: 0.08)
            : CockpitColors.surfaceSoft.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(CockpitRadius.medium),
        border: Border.all(
          color: isHighlighted
              ? color.withValues(alpha: 0.35)
              : CockpitColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CockpitTypography.label(
              fontSize: 10,
              color: CockpitColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: CockpitTypography.numbers(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isHighlighted ? color : CockpitColors.text,
            ),
          ),
        ],
      ),
    );
  }
}
