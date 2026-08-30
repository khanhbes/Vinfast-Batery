import 'package:flutter/material.dart';

import '../../../data/models/smart_charging_session.dart';

class StopChargingDecision {
  const StopChargingDecision(this.reason);
  final UserStopReason reason;
}

Future<StopChargingDecision?> showStopChargingConfirmationSheet(
  BuildContext context, {
  required double currentSoc,
  required double targetSoc,
  required Duration remaining,
}) => showModalBottomSheet<StopChargingDecision>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Dừng sạc?', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'Dữ liệu đã ghi vẫn được giữ và chỉ dùng để học phần sạc thực tế.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _BatteryProgress(
              currentSoc: widget.currentSoc,
              targetSoc: widget.targetSoc,
            ),
            const SizedBox(height: 16),
            _MetricRow('Pin hiện tại', '${widget.currentSoc.round()}%'),
            _MetricRow('Mục tiêu', '${widget.targetSoc.round()}%'),
            _MetricRow('Còn lại', _duration(widget.remaining)),
            const SizedBox(height: 16),
            Text('Lý do (không bắt buộc)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
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
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tiếp tục sạc'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () =>
                  Navigator.pop(context, StopChargingDecision(_reason)),
              child: const Text('Dừng sạc'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reasonChip(String label, UserStopReason value) => FilterChip(
    label: Text(label),
    selected: _reason == value,
    onSelected: (_) => setState(() => _reason = value),
  );
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _BatteryProgress extends StatelessWidget {
  const _BatteryProgress({required this.currentSoc, required this.targetSoc});
  final double currentSoc;
  final double targetSoc;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 18,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: colors.surfaceContainerHighest),
            ),
            FractionallySizedBox(
              widthFactor: currentSoc.clamp(0, 100) / 100,
              child: ColoredBox(color: colors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours <= 0) return '$minutes phút';
  return '$hours giờ ${minutes.toString().padLeft(2, '0')} phút';
}
