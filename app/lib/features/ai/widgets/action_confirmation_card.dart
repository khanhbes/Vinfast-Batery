import 'package:flutter/material.dart';

import '../../../core/theme/app_ui_colors.dart';
import '../models/function_call_action.dart';
import '../theme/chatbot_glass_theme.dart';

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

    final accentColor = action.isConfirmed
        ? Colors.green
        : (action.isCancelled ? uiColors.muted : uiColors.primary);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: ChatbotGlassTheme.cardDecoration(
        context,
        accentColor: accentColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  action.isConfirmed
                      ? Icons.check_circle_rounded
                      : action.isCancelled
                      ? Icons.cancel_outlined
                      : Icons.bolt_rounded,
                  color: accentColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: uiColors.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: action.isConfirmed
                        ? Colors.green
                        : action.isCancelled
                        ? uiColors.muted
                        : Colors.amber.shade800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                fontSize: 12.5,
                color: uiColors.text,
                height: 1.35,
              ),
            ),

          if (estTime != null && estTime.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 13, color: uiColors.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Thời gian: $estTime',
                    style: TextStyle(fontSize: 11.5, color: uiColors.muted),
                    overflow: TextOverflow.ellipsis,
                  ),
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
                color: uiColors.background.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: uiColors.border.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 13,
                    color: uiColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      safety,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: uiColors.muted,
                        height: 1.3,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Action buttons - Wrap to prevent overflow on small screens
          if (action.isPending) ...[
            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      side: BorderSide(color: uiColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: onCancel,
                    child: Text(
                      'HỦY',
                      style: TextStyle(fontSize: 11.5, color: uiColors.muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    key: const Key('action_card_confirm_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: uiColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 15),
                    label: const Text(
                      'XÁC NHẬN SẠC',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
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
                  const Icon(Icons.check_circle, size: 15, color: Colors.green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      action.resultMessage ?? 'Đã xác nhận thành công.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (action.isCancelled) ...[
            Text(
              'Thao tác đã được hủy bỏ.',
              style: TextStyle(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: uiColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
