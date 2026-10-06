import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/cockpit_design_system.dart';

/// Modal bottom sheet to let the user adjust the current battery percentage
/// when the vehicle or BMS is not automatically synchronizing telemetry.
class EditCurrentBatterySheet extends StatefulWidget {
  const EditCurrentBatterySheet({
    super.key,
    required this.initialPercent,
    required this.onSave,
  });

  final double initialPercent;
  final ValueChanged<double> onSave;

  static Future<void> show(
    BuildContext context, {
    required double initialPercent,
    required ValueChanged<double> onSave,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .72),
    builder: (_) =>
        EditCurrentBatterySheet(initialPercent: initialPercent, onSave: onSave),
  );

  @override
  State<EditCurrentBatterySheet> createState() =>
      _EditCurrentBatterySheetState();
}

class _EditCurrentBatterySheetState extends State<EditCurrentBatterySheet> {
  late double _soc;

  @override
  void initState() {
    super.initState();
    _soc = widget.initialPercent.clamp(0.0, 100.0);
  }

  void _updateSoc(double val) {
    final next = val.clamp(0.0, 100.0);
    if ((next.round() - _soc.round()).abs() >= 1) {
      HapticFeedback.selectionClick();
    }
    setState(() => _soc = next);
  }

  @override
  Widget build(BuildContext context) {
    final rounded = _soc.round();

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: CockpitColors.shell,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CockpitRadius.sheet),
        ),
        border: Border.all(color: CockpitColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: CockpitColors.dim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.battery_charging_full_rounded,
                    size: 22,
                    color: CockpitColors.emerald,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Chỉnh mức pin hiện tại',
                    style: TextStyle(
                      color: CockpitColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                color: CockpitColors.muted,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Điều chỉnh mức pin thực tế nếu xe chưa đồng bộ với ứng dụng',
            style: TextStyle(color: CockpitColors.muted, fontSize: 12),
          ),

          const SizedBox(height: 24),

          // Hero battery readout
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: CockpitColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: CockpitColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$rounded',
                  style: CockpitTypography.numbers(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: CockpitColors.text,
                  ),
                ),
                Text(
                  '%',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: CockpitColors.muted,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Slider with - / + steppers
          Row(
            children: [
              _SheetStepper(
                icon: Icons.remove_rounded,
                onPressed: rounded > 0 ? () => _updateSoc(_soc - 1) : null,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: CockpitColors.emerald,
                    inactiveTrackColor: Colors.white.withValues(alpha: .10),
                    thumbColor: CockpitColors.emerald,
                    overlayColor: CockpitColors.emerald.withValues(alpha: .16),
                    trackHeight: 6,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 9,
                    ),
                  ),
                  child: Slider(
                    value: _soc,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    onChanged: _updateSoc,
                  ),
                ),
              ),
              _SheetStepper(
                icon: Icons.add_rounded,
                onPressed: rounded < 100 ? () => _updateSoc(_soc + 1) : null,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Quick preset shortcuts
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [20, 35, 50, 75, 80].map((preset) {
              final isSelected = rounded == preset;
              return InkWell(
                onTap: () => _updateSoc(preset.toDouble()),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? CockpitColors.emerald.withValues(alpha: .15)
                        : Colors.white.withValues(alpha: .04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? CockpitColors.emerald
                          : CockpitColors.border,
                    ),
                  ),
                  child: Text(
                    '$preset%',
                    style: CockpitTypography.numbers(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? CockpitColors.emerald
                          : CockpitColors.muted,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Apply button
          FilledButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              widget.onSave(_soc.roundToDouble());
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: CockpitColors.emerald,
              foregroundColor: CockpitColors.background,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(CockpitRadius.medium),
              ),
            ),
            child: const Text(
              'XÁC NHẬN MỨC PIN',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetStepper extends StatelessWidget {
  const _SheetStepper({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 36,
    height: 36,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: .06),
        foregroundColor: onPressed != null
            ? CockpitColors.text
            : CockpitColors.dim.withValues(alpha: .3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}
