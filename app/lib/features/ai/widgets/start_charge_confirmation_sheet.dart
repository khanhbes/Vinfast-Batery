import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/widgets/luxe_slide_to_confirm.dart';
import 'history_luxe_widgets.dart';

/// Luxe sheet confirming a charge start. The relay is only requested after
/// the estimated-SOC acknowledgement AND a full slide of the platinum knob.
class StartChargeConfirmationSheet extends StatefulWidget {
  const StartChargeConfirmationSheet({
    super.key,
    required this.currentSoc,
    required this.targetSoc,
    required this.estimatedMinutes,
    required this.stopTime,
    required this.isAiMode,
    this.personalizationLabel,
    this.safetyCeiling,
  });

  final int currentSoc;
  final int targetSoc;
  final int estimatedMinutes;
  final String stopTime;
  final bool isAiMode;
  final String? personalizationLabel;

  /// Set for a target charge: latest Shelly timer cut, "HH:MM".
  final String? safetyCeiling;

  /// Show as a modal bottom sheet and return true if confirmed.
  static Future<bool?> show(
    BuildContext context, {
    required int currentSoc,
    required int targetSoc,
    required int estimatedMinutes,
    required String stopTime,
    required bool isAiMode,
    String? personalizationLabel,
    String? safetyCeiling,
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
      safetyCeiling: safetyCeiling,
    ),
  );

  @override
  State<StartChargeConfirmationSheet> createState() =>
      _StartChargeConfirmationSheetState();
}

class _StartChargeConfirmationSheetState
    extends State<StartChargeConfirmationSheet> {
  bool _acknowledged = false;

  /// Task 126 target charge: the server cuts at the %, Shelly at the ceiling.
  bool get _targetMode => widget.safetyCeiling != null;

  String _formatDuration(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h > 0) return '$h giờ $m phút';
    return '$m phút';
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: LuxeTheme.of(context),
    child: LuxeSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LuxeReveal(
            child: Row(
              children: [
                _ModeMedallion(isAi: widget.isAiMode),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Xác nhận bắt đầu sạc', style: LuxeText.item),
                      const SizedBox(height: 2),
                      Text(
                        _targetMode
                            ? 'Sạc đến ${widget.targetSoc}% · tự ngắt'
                            : widget.isAiMode
                            ? 'Sạc theo dự đoán'
                            : 'Sạc hẹn giờ',
                        style: LuxeText.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          LuxeReveal(
            index: 1,
            child: _SocJourney(
              from: widget.currentSoc,
              to: widget.targetSoc,
              label: widget.isAiMode ? 'Mục tiêu' : 'Ước tính khi tự ngắt',
              approximate: !widget.isAiMode,
            ),
          ),
          const SizedBox(height: 18),
          LuxeReveal(
            index: 2,
            child: LuxeGlass(
              radius: 20,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Column(
                children: [
                  LuxeInfoRow(
                    icon: Icons.schedule_rounded,
                    label: 'Thời gian dự kiến',
                    value: _formatDuration(widget.estimatedMinutes),
                  ),
                  const Divider(height: 1),
                  LuxeInfoRow(
                    icon: Icons.power_settings_new_rounded,
                    label: _targetMode ? 'Tự ngắt khi đạt' : 'Tự ngắt lúc',
                    value: _targetMode
                        ? '~${widget.targetSoc}% (dự kiến ${widget.stopTime})'
                        : widget.stopTime,
                  ),
                  if (_targetMode) ...[
                    const Divider(height: 1),
                    LuxeInfoRow(
                      icon: Icons.shield_outlined,
                      label: 'Giới hạn an toàn',
                      value: 'Shelly tự tắt muộn nhất ${widget.safetyCeiling}',
                    ),
                  ],
                  if (widget.personalizationLabel != null) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.auto_awesome_rounded,
                            size: 17,
                            color: LuxeColors.platinumMid,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.personalizationLabel!,
                              style: LuxeText.caption.copyWith(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          LuxeReveal(
            index: 3,
            child: _Acknowledgement(
              value: _acknowledged,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setState(() => _acknowledged = v);
              },
            ),
          ),
          const SizedBox(height: 20),
          LuxeReveal(
            index: 4,
            child: LuxeSlideToConfirm(
              key: const ValueKey('start-charge-slider'),
              enabled: _acknowledged,
              label: _targetMode
                  ? 'Vuốt để sạc đến ${widget.targetSoc}%'
                  : widget.isAiMode
                  ? 'Vuốt để sạc theo dự đoán'
                  : 'Vuốt để bắt đầu sạc',
              lockedLabel: 'Đánh dấu ô phía trên để mở khóa',
              onConfirmed: () => Navigator.pop(context, true),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
        ],
      ),
    ),
  );
}

/// Dark glass bottom-sheet body shared by the luxe charge confirmations.
class LuxeSheetFrame extends StatelessWidget {
  const LuxeSheetFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .92,
    ),
    decoration: const BoxDecoration(
      color: Color(0xFF0C0D0F),
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      border: Border(top: BorderSide(color: LuxeColors.hairlineStrong)),
      gradient: RadialGradient(
        center: Alignment(0, -1.2),
        radius: 1.2,
        colors: [Color(0xFF1A1C1F), Color(0xFF0C0D0F)],
      ),
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: LuxeColors.hairlineStrong,
                ),
              ),
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    ),
  );
}

/// Label / value row that stacks under narrow widths or large text.
class LuxeInfoRow extends StatelessWidget {
  const LuxeInfoRow({
    super.key,
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 270 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.25;
        final valueText = Text(
          value,
          textAlign: stacked ? TextAlign.start : TextAlign.end,
          maxLines: stacked ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor ?? LuxeColors.platinumHi,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        );
        final labelText = Text(label, style: LuxeText.caption);
        final iconWidget = Icon(icon, size: 17, color: LuxeColors.platinumMid);
        if (stacked) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              iconWidget,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [labelText, const SizedBox(height: 4), valueText],
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            iconWidget,
            const SizedBox(width: 10),
            Expanded(child: labelText),
            const SizedBox(width: 8),
            Flexible(child: valueText),
          ],
        );
      },
    ),
  );
}

class _ModeMedallion extends StatelessWidget {
  const _ModeMedallion({required this.isAi});
  final bool isAi;

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF26282C), Color(0xFF101113)],
      ),
      border: Border.all(color: LuxeColors.emerald.withValues(alpha: 0.55)),
      boxShadow: const [
        BoxShadow(color: Color(0x3334D399), blurRadius: 16, spreadRadius: -4),
      ],
    ),
    child: Icon(
      isAi ? Icons.auto_awesome_rounded : Icons.schedule_rounded,
      color: LuxeColors.emerald,
      size: 22,
    ),
  );
}

/// Large "22% → 85%" with the span lit on a slim track.
class _SocJourney extends StatelessWidget {
  const _SocJourney({
    required this.from,
    required this.to,
    required this.label,
    this.approximate = false,
  });
  final int from;
  final int to;
  final String label;

  /// An estimate (timed charge): written "~X%".
  final bool approximate;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: pin từ $from% đến $to%',
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label.toUpperCase(), style: LuxeText.eyebrow),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$from%',
                style: const TextStyle(
                  color: LuxeColors.platinumMid,
                  fontSize: 30,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: LuxeColors.dim,
                ),
              ),
              LuxeMetalText(
                '${approximate ? '~' : ''}$to%',
                style: const TextStyle(
                  fontSize: 44,
                  height: 1.05,
                  fontWeight: FontWeight.w200,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        HistorySocTrack(
          start: from.toDouble(),
          end: to.toDouble(),
          showLabel: false,
        ),
      ],
    ),
  );
}

class _Acknowledgement extends StatelessWidget {
  const _Acknowledgement({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: value
              ? LuxeColors.emerald.withValues(alpha: 0.08)
              : historyAmber.withValues(alpha: 0.06),
          border: Border.all(
            color: value
                ? LuxeColors.emerald.withValues(alpha: 0.45)
                : historyAmber.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v == true),
              activeColor: LuxeColors.emerald,
              checkColor: const Color(0xFF04140D),
              side: const BorderSide(color: LuxeColors.platinumMid, width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(width: 4),
            const Expanded(
              child: Text(
                'Pin hiện tại là giá trị ước tính. Tôi đã hiểu.',
                style: TextStyle(
                  color: LuxeColors.text,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
