import 'package:flutter/material.dart';

import '../../../core/theme/cockpit_design_system.dart';

/// Premium bottom sheet confirming charge start.
/// Shows vehicle context, SOC range, estimated time, and mode-specific UI.
class StartChargeConfirmationSheet extends StatefulWidget {
  const StartChargeConfirmationSheet({
    super.key,
    required this.currentSoc,
    required this.targetSoc,
    required this.estimatedMinutes,
    required this.stopTime,
    required this.isAiMode,
    this.personalizationLabel,
  });

  final int currentSoc;
  final int targetSoc;
  final int estimatedMinutes;
  final String stopTime;
  final bool isAiMode;
  final String? personalizationLabel;

  /// Show as a modal bottom sheet and return true if confirmed.
  static Future<bool?> show(
    BuildContext context, {
    required int currentSoc,
    required int targetSoc,
    required int estimatedMinutes,
    required String stopTime,
    required bool isAiMode,
    String? personalizationLabel,
  }) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .72),
    builder: (_) => StartChargeConfirmationSheet(
      currentSoc: currentSoc,
      targetSoc: targetSoc,
      estimatedMinutes: estimatedMinutes,
      stopTime: stopTime,
      isAiMode: isAiMode,
      personalizationLabel: personalizationLabel,
    ),
  );

  @override
  State<StartChargeConfirmationSheet> createState() =>
      _StartChargeConfirmationSheetState();
}

class _StartChargeConfirmationSheetState
    extends State<StartChargeConfirmationSheet> {
  bool _acknowledged = false;

  String _formatDuration(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h > 0) return '$h giờ $m phút';
    return '$m phút';
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .92,
    ),
    decoration: BoxDecoration(
      color: CockpitColors.shell,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(CockpitRadius.sheet),
      ),
      border: Border.all(color: CockpitColors.border),
    ),
    child: SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CockpitColors.dim,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: CockpitColors.emerald.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: CockpitColors.emerald.withValues(alpha: .25),
                      ),
                    ),
                    child: Icon(
                      widget.isAiMode
                          ? Icons.auto_awesome_rounded
                          : Icons.timer_rounded,
                      color: CockpitColors.emerald,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Xác nhận bắt đầu sạc',
                          style: TextStyle(
                            color: CockpitColors.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.isAiMode
                              ? 'Sạc theo AI Prediction'
                              : 'Sạc hẹn giờ',
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

              const SizedBox(height: 20),

              // Info cards
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CockpitColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: CockpitColors.border),
                ),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.battery_charging_full_rounded,
                      label: 'Mục tiêu',
                      value: '${widget.currentSoc}% → ${widget.targetSoc}%',
                      valueColor: CockpitColors.emerald,
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(
                      icon: Icons.schedule_rounded,
                      label: 'Thời gian dự kiến',
                      value: _formatDuration(widget.estimatedMinutes),
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(
                      icon: Icons.alarm_rounded,
                      label: 'Tự ngắt lúc',
                      value: widget.stopTime,
                      valueColor: CockpitColors.amber,
                    ),
                    if (widget.personalizationLabel != null) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Color(0xFF2A2A2A)),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.psychology_rounded,
                            size: 18,
                            color: CockpitColors.muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.personalizationLabel!,
                              style: TextStyle(
                                color: CockpitColors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Acknowledgement
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CockpitColors.amber.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: CockpitColors.amber.withValues(alpha: .20),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _acknowledged,
                        onChanged: (v) =>
                            setState(() => _acknowledged = v == true),
                        activeColor: CockpitColors.emerald,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _acknowledged = !_acknowledged),
                        child: Text(
                          'Pin hiện tại là giá trị ước tính. Tôi đã hiểu.',
                          style: TextStyle(
                            color: CockpitColors.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Buttons
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _acknowledged
                      ? () => Navigator.pop(context, true)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: CockpitColors.emeraldStrong,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: CockpitColors.elevated,
                    disabledForegroundColor: CockpitColors.dim,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(
                    widget.isAiMode
                        ? Icons.auto_awesome_rounded
                        : Icons.bolt_rounded,
                    size: 18,
                  ),
                  label: Text(
                    'BẮT ĐẦU SẠC',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Hủy',
                  style: TextStyle(
                    color: CockpitColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: CockpitColors.muted),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          style: TextStyle(color: CockpitColors.muted, fontSize: 13),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          value,
          style: CockpitTypography.numbers(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? CockpitColors.text,
          ),
          textAlign: TextAlign.end,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}
