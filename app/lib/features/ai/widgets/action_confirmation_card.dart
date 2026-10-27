import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/widgets/charge_confirm_control.dart';
import '../models/function_call_action.dart';

/// BatteryBot proposal card (LUXE, Task 125): emerald only once the result
/// is verified, champagne while waiting or unverified, rose when the action
/// did not run. Every control is at least 48 dp.
class ActionConfirmationCard extends StatelessWidget {
  const ActionConfirmationCard({
    super.key,
    required this.action,
    required this.onConfirm,
    required this.onCancel,
    this.isLoading = false,
  });

  final FunctionCallAction action;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool isLoading;

  /// The only chat tool that can switch the charger relay ON.
  static const energizingTool = 'start_timed_charging';

  /// Pending icon by kind: only charger commands show the bolt.
  static IconData pendingIcon(String toolName) {
    if (toolName.contains('reminder')) return Icons.event_rounded;
    if (toolName == 'app_set_app_setting') return Icons.tune_rounded;
    if (toolName.startsWith('app_')) return Icons.edit_rounded;
    // QA 139: stopping is not the bolt that starts a charge.
    if (toolName.contains('stop')) return Icons.power_settings_new_rounded;
    return Icons.bolt_rounded;
  }

  bool get _failed =>
      !action.isPending &&
      !action.isConfirmed &&
      !action.isCancelled &&
      action.status != 'unknown';

  Color get _accent {
    if (action.isConfirmed) return LuxeColors.emerald;
    if (action.isCancelled) return LuxeColors.muted;
    if (_failed) return LuxeColors.danger;
    return LuxeColors.champagne;
  }

  String get _statusLabel {
    if (action.isConfirmed) return 'ĐÃ XÁC MINH';
    if (action.isCancelled) return 'ĐÃ HỦY';
    if (action.status == 'unknown') return 'CHƯA XÁC MINH';
    if (action.isPending) return 'CHỜ XÁC NHẬN';
    return 'CHƯA THỰC HIỆN';
  }

  @override
  Widget build(BuildContext context) {
    final card = action.cardData;
    final title = card?.title ?? 'Xác nhận lệnh điều khiển';
    final desc = card?.description ?? '';
    final safety = card?.safetyNote;
    final estTime = card?.estimatedTime;
    final energizes = action.toolName == energizingTool;
    final accent = _accent;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LuxeColors.raised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  action.isConfirmed
                      ? Icons.check_circle_rounded
                      : action.isCancelled
                      ? Icons.cancel_rounded
                      : _failed
                      ? Icons.error_outline_rounded
                      : pendingIcon(action.toolName),
                  color: accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              // Status above the title: side by side they overflowed 320 dp
              // at text x2 (Task 125).
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        _statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: LuxeColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              desc,
              style: const TextStyle(
                fontSize: 14,
                color: LuxeColors.text,
                height: 1.4,
              ),
            ),
          ],
          if (estTime != null && estTime.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 15,
                  color: LuxeColors.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Thời gian: $estTime',
                    style: const TextStyle(
                      fontSize: 13,
                      color: LuxeColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (safety != null && safety.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: LuxeColors.glass,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: LuxeColors.hairline),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Information, not a verified state: steel, not emerald.
                  const Icon(
                    Icons.shield_rounded,
                    size: 15,
                    color: LuxeColors.steel,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      safety,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: LuxeColors.muted,
                        height: 1.35,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (action.isPending) ...[
            if (isLoading)
              Semantics(
                liveRegion: true,
                child: const Row(
                  key: Key('action_card_progress'),
                  children: [
                    SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: LuxeColors.champagne,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Đang gửi lệnh và chờ máy chủ xác minh…',
                        style: TextStyle(fontSize: 13, color: LuxeColors.muted),
                      ),
                    ),
                  ],
                ),
              )
            else if (energizes)
              // Switching a relay ON needs a full slide, never a single tap.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChargeConfirmControl(
                    sliderKey: const Key('action_card_confirm_slider'),
                    label: 'Vuốt để bật sạc',
                    height: 54,
                    onConfirmed: onConfirm,
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _CancelButton(onPressed: onCancel),
                  ),
                ],
              )
            else
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CancelButton(onPressed: onCancel),
                  FilledButton.icon(
                    key: const Key('action_card_confirm_button'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      // Dark text on platinum (white on emerald was ~1.9:1).
                      backgroundColor: LuxeColors.platinumHi,
                      foregroundColor: LuxeColors.shell,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 17),
                    label: const Text(
                      'XÁC NHẬN',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: onConfirm,
                  ),
                ],
              ),
          ] else if (action.isConfirmed) ...[
            _ResultStrip(
              icon: Icons.check_circle_rounded,
              color: LuxeColors.emerald,
              message: action.resultMessage ?? 'Đã xác nhận thành công.',
            ),
          ] else if (action.isCancelled) ...[
            const Text(
              'Thao tác đã được hủy bỏ.',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: LuxeColors.muted,
              ),
            ),
          ] else if (action.resultMessage != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                action.resultMessage!,
                style: TextStyle(
                  fontSize: 14,
                  color: _failed ? LuxeColors.danger : LuxeColors.text,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: const Key('action_card_cancel_button'),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      side: const BorderSide(color: LuxeColors.hairlineStrong),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    onPressed: onPressed,
    child: const Text(
      'HỦY',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: LuxeColors.platinum,
      ),
    ),
  );
}

class _ResultStrip extends StatelessWidget {
  const _ResultStrip({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}
