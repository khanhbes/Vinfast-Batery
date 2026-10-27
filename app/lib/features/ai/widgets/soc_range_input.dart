import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/widgets/seven_segment_text.dart';
import '../../../data/models/app_appearance.dart';

/// Battery % now → target for the Charge tab layouts other than the dial
/// (QA 131): one horizontal bar with two thumbs — silver for the scooter's
/// current %, emerald for the target. The read-outs follow the chosen
/// [style] (plain, seven-segment LCD, or detailed numbers).
class SocRangeInput extends StatelessWidget {
  const SocRangeInput({
    super.key,
    required this.style,
    required this.current,
    required this.target,
    required this.onCurrentChanged,
    required this.onTargetChanged,
    this.onEditCurrent,
    this.etaLabel,
    this.enabled = true,
  });

  final ChargeStyle style;
  final double current;
  final double target;
  final ValueChanged<double> onCurrentChanged;
  final ValueChanged<double> onTargetChanged;
  final VoidCallback? onEditCurrent;
  final String? etaLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final now = current.round().clamp(0, 100);
    final goal = target.round().clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Readout(
          style: style,
          now: now,
          goal: goal,
          etaLabel: etaLabel,
          onEditCurrent: enabled ? onEditCurrent : null,
        ),
        const SizedBox(height: 10),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 14,
            activeTrackColor: LuxeColors.emerald.withValues(alpha: 0.75),
            inactiveTrackColor: LuxeColors.glassStrong,
            thumbColor: LuxeColors.platinumHi,
            overlayColor: LuxeColors.platinumHi.withValues(alpha: 0.12),
            rangeThumbShape: const RoundRangeSliderThumbShape(
              enabledThumbRadius: 13,
            ),
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: RangeSlider(
            key: const ValueKey('soc-range-input'),
            min: 0,
            max: 100,
            divisions: 100,
            values: RangeValues(
              now.toDouble(),
              goal.toDouble().clamp(now.toDouble(), 100),
            ),
            semanticFormatterCallback: (v) => '${v.round()}%',
            onChanged: enabled
                ? (v) {
                    if (v.start.round() != now) {
                      HapticFeedback.selectionClick();
                      onCurrentChanged(v.start.roundToDouble());
                    }
                    if (v.end.round() != goal) {
                      HapticFeedback.selectionClick();
                      onTargetChanged(v.end.roundToDouble());
                    }
                  }
                : null,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Pin xe',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: LuxeColors.dim, fontSize: 11.5),
                ),
              ),
              Flexible(
                child: Text(
                  'Mục tiêu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: LuxeColors.dim, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.style,
    required this.now,
    required this.goal,
    required this.etaLabel,
    required this.onEditCurrent,
  });

  final ChargeStyle style;
  final int now;
  final int goal;
  final String? etaLabel;
  final VoidCallback? onEditCurrent;

  @override
  Widget build(BuildContext context) {
    final eta = etaLabel;
    final Widget numbers = switch (style) {
      ChargeStyle.lcd => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SevenSegmentText('$now', height: 52, semanticsLabel: 'Pin $now%'),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 14, 4),
            child: Text(
              '%',
              style: TextStyle(color: LuxeColors.platinum, fontSize: 15.5),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: LuxeColors.platinumMid,
            ),
          ),
          const SizedBox(width: 14),
          SevenSegmentText(
            '$goal',
            height: 52,
            color: LuxeColors.emerald,
            semanticsLabel: 'Mục tiêu $goal%',
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 0, 4),
            child: Text(
              '%',
              style: TextStyle(color: LuxeColors.emerald, fontSize: 15.5),
            ),
          ),
        ],
      ),
      _ => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$now%',
            style: const TextStyle(
              color: LuxeColors.text,
              fontSize: 40,
              fontWeight: FontWeight.w300,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: LuxeColors.platinumMid,
              size: 22,
            ),
          ),
          Text(
            '$goal%',
            style: const TextStyle(
              color: LuxeColors.emerald,
              fontSize: 40,
              fontWeight: FontWeight.w300,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: FittedBox(fit: BoxFit.scaleDown, child: numbers),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 4,
          children: [
            if (eta != null)
              Text(
                'Dự kiến $eta',
                style: const TextStyle(
                  color: LuxeColors.champagne,
                  fontSize: 13,
                ),
              ),
            if (style == ChargeStyle.detail)
              Text(
                'Cần nạp ${(goal - now).clamp(0, 100)}%',
                style: const TextStyle(color: LuxeColors.muted, fontSize: 13),
              ),
            if (onEditCurrent != null)
              TextButton.icon(
                key: const ValueKey('soc-range-edit-current'),
                onPressed: onEditCurrent,
                style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Nhập % pin'),
              ),
          ],
        ),
      ],
    );
  }
}
