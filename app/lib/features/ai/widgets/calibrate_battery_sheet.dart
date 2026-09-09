import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/cockpit_design_system.dart';

/// Premium bottom sheet for calibrating the current battery SOC.
/// Matches the EV cockpit reference CalibrateModal.
class CalibrateBatterySheet extends StatefulWidget {
  const CalibrateBatterySheet({
    super.key,
    required this.currentSoc,
  });

  final double currentSoc;

  /// Show as a modal bottom sheet and return the new SOC value if saved.
  static Future<double?> show(
    BuildContext context, {
    required double currentSoc,
  }) =>
      showModalBottomSheet<double>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: .72),
        builder: (_) => CalibrateBatterySheet(currentSoc: currentSoc),
      );

  @override
  State<CalibrateBatterySheet> createState() => _CalibrateBatterySheetState();
}

class _CalibrateBatterySheetState extends State<CalibrateBatterySheet> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.currentSoc;
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? context.cockpit.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(CockpitRadius.sheet),
          ),
          border: Border.all(color: context.cockpit.border),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
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
                        Icons.tune_rounded,
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
                            'Chỉnh mức pin hiện tại',
                            style: TextStyle(
                              color: CockpitColors.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Cập nhật SOC ước tính của xe',
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

                const SizedBox(height: 24),

                // Current value display
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: CockpitColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: CockpitColors.border),
                  ),
                  child: Column(
                    children: [
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
                          value: _value.clamp(0, 99),
                          min: 0,
                          max: 99,
                          divisions: 99,
                          onChanged: (v) {
                            setState(() => _value = v);
                            HapticFeedback.selectionClick();
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '0%',
                            style: TextStyle(
                              color: CockpitColors.dim,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Giá trị trước: ~${widget.currentSoc.round()}%',
                            style: TextStyle(
                              color: CockpitColors.muted,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '99%',
                            style: TextStyle(
                              color: CockpitColors.dim,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Info note
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CockpitColors.info.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: CockpitColors.info.withValues(alpha: .20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: CockpitColors.info,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Pin hiện tại là giá trị ước tính từ hồ sơ xe, không phải dữ liệu BMS thực.',
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
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: CockpitColors.muted,
                            side: BorderSide(color: CockpitColors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Hủy',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context, _value),
                          style: FilledButton.styleFrom(
                            backgroundColor: CockpitColors.emeraldStrong,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.save_rounded, size: 18),
                          label: const Text(
                            'Lưu',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
}
