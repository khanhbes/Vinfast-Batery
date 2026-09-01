import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/cockpit_design_system.dart';

/// Premium bottom sheet for confirming end SOC after a charging session.
/// Used to train the personal AI model with actual charge results.
class ConfirmEndSocSheet extends StatefulWidget {
  const ConfirmEndSocSheet({
    super.key,
    required this.suggestedSoc,
    required this.startSoc,
    required this.targetSoc,
  });

  final double suggestedSoc;
  final double startSoc;
  final double targetSoc;

  /// Show as a modal bottom sheet and return the confirmed SOC value.
  static Future<double?> show(
    BuildContext context, {
    required double suggestedSoc,
    required double startSoc,
    required double targetSoc,
  }) =>
      showModalBottomSheet<double>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: .72),
        builder: (_) => ConfirmEndSocSheet(
          suggestedSoc: suggestedSoc,
          startSoc: startSoc,
          targetSoc: targetSoc,
        ),
      );

  @override
  State<ConfirmEndSocSheet> createState() => _ConfirmEndSocSheetState();
}

class _ConfirmEndSocSheetState extends State<ConfirmEndSocSheet> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.suggestedSoc;
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: CockpitColors.shell,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(CockpitRadius.sheet),
          ),
          border: Border.all(color: CockpitColors.border),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
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
                          color:
                              CockpitColors.emerald.withValues(alpha: .25),
                        ),
                      ),
                      child: const Icon(
                        Icons.battery_charging_full_rounded,
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
                            'Xác nhận mức pin cuối',
                            style: TextStyle(
                              color: CockpitColors.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Giúp AI dự đoán chính xác hơn',
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

                // Session summary
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: CockpitColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: CockpitColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _MiniStat(
                        label: 'Bắt đầu',
                        value: '${widget.startSoc.round()}%',
                      ),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: CockpitColors.muted,
                      ),
                      _MiniStat(
                        label: 'Mục tiêu',
                        value: '${widget.targetSoc.round()}%',
                        valueColor: CockpitColors.emerald,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // SOC input
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: CockpitColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: CockpitColors.emerald.withValues(alpha: .20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Pin thực tế sau khi sạc',
                        style: TextStyle(
                          color: CockpitColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_value.round()}%',
                        style: CockpitTypography.numbers(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          color: CockpitColors.emerald,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: CockpitColors.emerald,
                          inactiveTrackColor:
                              Colors.white.withValues(alpha: .10),
                          thumbColor: CockpitColors.emerald,
                          overlayColor:
                              CockpitColors.emerald.withValues(alpha: .12),
                          trackHeight: 8,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 10,
                          ),
                        ),
                        child: Slider(
                          value: _value.clamp(0, 100),
                          min: 0,
                          max: 100,
                          divisions: 100,
                          onChanged: (v) {
                            setState(() => _value = v);
                            HapticFeedback.selectionClick();
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Gợi ý: ~${widget.suggestedSoc.round()}%',
                        style: TextStyle(
                          color: CockpitColors.dim,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // AI training info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CockpitColors.emerald.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: CockpitColors.emerald.withValues(alpha: .15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.psychology_rounded,
                        size: 18,
                        color: CockpitColors.emerald,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Dữ liệu này sẽ giúp mô hình AI cá nhân dự đoán thời gian sạc chính xác hơn cho xe của bạn.',
                          style: TextStyle(
                            color: CockpitColors.muted,
                            fontSize: 11,
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
                    onPressed: () => Navigator.pop(context, _value),
                    style: FilledButton.styleFrom(
                      backgroundColor: CockpitColors.emeraldStrong,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text(
                      'Xác nhận & Huấn luyện AI',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Bỏ qua',
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
      );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    this.valueColor,
  });
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: CockpitColors.dim,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: CockpitTypography.numbers(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: valueColor ?? CockpitColors.text,
            ),
          ),
        ],
      );
}
