import 'package:flutter/material.dart';

import '../../../core/theme/app_ui_colors.dart';
import '../models/function_call_action.dart';

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

  @override
  Widget build(BuildContext context) {
    final uiColors = AppUiColors.of(context);
    final card = action.cardData;
    final title = card?.title ?? 'Xác nhận lệnh điều khiển';
    final desc = card?.description ?? '';
    final safety = card?.safetyNote;
    final estTime = card?.estimatedTime;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: uiColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: action.isConfirmed
              ? Colors.green.withValues(alpha: 0.5)
              : action.isCancelled
                  ? uiColors.border
                  : uiColors.primary.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (action.isConfirmed ? Colors.green : uiColors.primary)
                .withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (action.isConfirmed ? Colors.green : uiColors.primary)
                      .withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  action.isConfirmed
                      ? Icons.check_circle_rounded
                      : action.isCancelled
                          ? Icons.cancel_outlined
                          : Icons.bolt_rounded,
                  color: action.isConfirmed
                      ? Colors.green
                      : action.isCancelled
                          ? uiColors.muted
                          : uiColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: uiColors.text,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: action.isConfirmed
                      ? Colors.green.withValues(alpha: 0.15)
                      : action.isCancelled
                          ? uiColors.border.withValues(alpha: 0.5)
                          : Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  action.isConfirmed
                      ? 'ĐÃ KÍCH HOẠT'
                      : action.isCancelled
                          ? 'ĐÃ HỦY'
                          : 'CẦN XÁC NHẬN',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: action.isConfirmed
                        ? Colors.green
                        : action.isCancelled
                            ? uiColors.muted
                            : Colors.amber.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Description
          if (desc.isNotEmpty)
            Text(
              desc,
              style: TextStyle(
                fontSize: 13,
                color: uiColors.text,
                height: 1.4,
              ),
            ),

          if (estTime != null && estTime.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: uiColors.muted),
                const SizedBox(width: 4),
                Text(
                  'Thời gian: $estTime',
                  style: TextStyle(fontSize: 12, color: uiColors.muted),
                ),
              ],
            ),
          ],

          // Safety note
          if (safety != null && safety.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: uiColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: uiColors.border.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, size: 14, color: uiColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      safety,
                      style: TextStyle(
                        fontSize: 11,
                        color: uiColors.muted,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Action buttons
          if (action.isPending) ...[
            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    key: const Key('action_card_cancel_button'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      side: BorderSide(color: uiColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: onCancel,
                    child: Text(
                      'HỦY',
                      style: TextStyle(fontSize: 12, color: uiColors.muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    key: const Key('action_card_confirm_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: uiColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text(
                      'XÁC NHẬN SẠC',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: onConfirm,
                  ),
                ],
              ),
          ] else if (action.isConfirmed) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      action.resultMessage ?? 'Đã xác nhận thành công.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (action.isCancelled) ...[
            Text(
              'Thao tác đã được hủy bỏ.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: uiColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}
