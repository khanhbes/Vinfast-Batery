import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../data/models/smart_charging_session.dart';
import 'history_luxe_widgets.dart';
import 'start_charge_confirmation_sheet.dart';

class StopChargingDecision {
  const StopChargingDecision(this.reason);
  final UserStopReason reason;
}

/// Stopping is never gated behind a gesture: switching OFF must stay fast.
Future<StopChargingDecision?> showStopChargingConfirmationSheet(
  BuildContext context, {
  required double currentSoc,
  required double targetSoc,
  required Duration remaining,
}) => showModalBottomSheet<StopChargingDecision>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .72),
  builder: (context) => _StopChargingConfirmationSheet(
    currentSoc: currentSoc,
    targetSoc: targetSoc,
    remaining: remaining,
  ),
);

class _StopChargingConfirmationSheet extends StatefulWidget {
  const _StopChargingConfirmationSheet({
    required this.currentSoc,
    required this.targetSoc,
    required this.remaining,
  });

  final double currentSoc;
  final double targetSoc;
  final Duration remaining;

  @override
  State<_StopChargingConfirmationSheet> createState() =>
      _StopChargingConfirmationSheetState();
}

class _StopChargingConfirmationSheetState
    extends State<_StopChargingConfirmationSheet> {
  UserStopReason _reason = UserStopReason.none;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) => Theme(
    data: LuxeTheme.of(context),
    child: LuxeSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('ĐANG SẠC', style: LuxeText.eyebrow),
          const SizedBox(height: 6),
          const Text('Dừng sạc?', style: LuxeText.title),
          const SizedBox(height: 6),
          const Text(
            'Dữ liệu đã ghi vẫn được giữ và chỉ dùng để học phần sạc thực tế.',
            style: LuxeText.caption,
          ),
          const SizedBox(height: 18),
          LuxeGlass(
            radius: 20,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HistorySocTrack(
                  start: 0,
                  end: widget.currentSoc,
                  showLabel: false,
                ),
                const SizedBox(height: 4),
                LuxeInfoRow(
                  icon: Icons.battery_5_bar_rounded,
                  label: 'Pin hiện tại',
                  value: '${widget.currentSoc.round()}%',
                ),
                const Divider(height: 1),
                LuxeInfoRow(
                  icon: Icons.flag_outlined,
                  label: 'Mục tiêu',
                  value: '${widget.targetSoc.round()}%',
                  valueColor: LuxeColors.emerald,
                ),
                const Divider(height: 1),
                LuxeInfoRow(
                  icon: Icons.timer_outlined,
                  label: 'Còn lại',
                  value: _duration(widget.remaining),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'LÝ DO (KHÔNG BẮT BUỘC)',
            style: LuxeText.label.copyWith(letterSpacing: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _reasonChip('Cần dùng xe', UserStopReason.needVehicle),
              _reasonChip('Pin đã đủ', UserStopReason.enoughCharge),
              _reasonChip('Lo ngại an toàn', UserStopReason.safetyConcern),
              _reasonChip('Khác', UserStopReason.other),
            ],
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            key: const ValueKey('stop-charge-confirm'),
            style: ButtonStyle(
              foregroundColor: const WidgetStatePropertyAll(Color(0xFF1A0505)),
              backgroundBuilder: (context, states, child) => DecoratedBox(
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  gradient: states.contains(WidgetState.disabled)
                      ? null
                      : const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFFBC4C4), LuxeColors.danger],
                        ),
                  color: states.contains(WidgetState.disabled)
                      ? LuxeColors.glass
                      : null,
                ),
                child: child,
              ),
            ),
            onPressed: _submitting
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    setState(() => _submitting = true);
                    Navigator.pop(context, StopChargingDecision(_reason));
                  },
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF1A0505),
                    ),
                  )
                : const Icon(Icons.power_settings_new_rounded, size: 20),
            label: const Text('Dừng sạc'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _submitting ? null : () => Navigator.pop(context),
            child: const Text('Tiếp tục sạc'),
          ),
        ],
      ),
    ),
  );

  Widget _reasonChip(String label, UserStopReason value) => HistoryChip(
    label: label,
    selected: _reason == value,
    onTap: () {
      HapticFeedback.selectionClick();
      setState(() => _reason = _reason == value ? UserStopReason.none : value);
    },
  );
}

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours <= 0) return '$minutes phút';
  return '$hours giờ ${minutes.toString().padLeft(2, '0')} phút';
}
