import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_ui_colors.dart';
import '../../../core/utils/battery_bot_faq.dart';
import '../models/chat_message.dart';
import '../models/function_call_action.dart';
import 'action_confirmation_card.dart';
import 'streaming_text_widget.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onFeedback,
    this.onActionPressed,
    this.onConfirmAction,
    this.onCancelAction,
    this.isActionLoading = false,
  });

  final ChatMessage message;
  final void Function(String rating)? onFeedback;
  final void Function(BatteryBotAction action)? onActionPressed;
  final void Function(FunctionCallAction action)? onConfirmAction;
  final void Function(FunctionCallAction action)? onCancelAction;
  final bool isActionLoading;

  @override
  Widget build(BuildContext context) {
    final uiColors = AppUiColors.of(context);
    final theme = Theme.of(context);
    final timeStr = DateFormat('HH:mm').format(message.timestamp);

    if (!message.fromBot) {
      // User message — bên phải
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(4),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  message.content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Bot message — bên trái với mascot avatar
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0072BC), Color(0xFF00C853)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.smart_toy_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: uiColors.cardBackground,
                    border: Border.all(
                      color: uiColors.border.withValues(alpha: 0.6),
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StreamingTextWidget(
                        text: message.content,
                        isStreaming: message.isStreaming,
                      ),
                      if (message.actionCard != null) ...[
                        const SizedBox(height: 8),
                        ActionConfirmationCard(
                          action: message.actionCard!,
                          isLoading: isActionLoading,
                          onConfirm: () => onConfirmAction?.call(message.actionCard!),
                          onCancel: () => onCancelAction?.call(message.actionCard!),
                        ),
                      ],
                      if (message.action != null) ...[
                        const SizedBox(height: 10),
                        _buildActionChip(context, message.action!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                    if (!message.isStreaming && message.content.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      _FeedbackButton(
                        icon: Icons.thumb_up_alt_outlined,
                        activeIcon: Icons.thumb_up_alt_rounded,
                        isSelected: message.userFeedback == 'like',
                        onTap: () => onFeedback?.call('like'),
                      ),
                      const SizedBox(width: 4),
                      _FeedbackButton(
                        icon: Icons.thumb_down_alt_outlined,
                        activeIcon: Icons.thumb_down_alt_rounded,
                        isSelected: message.userFeedback == 'dislike',
                        onTap: () => onFeedback?.call('dislike'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip(BuildContext context, String actionKey) {
    BatteryBotAction? action;
    try {
      action = BatteryBotAction.values.firstWhere(
        (a) => a.name == actionKey,
      );
    } catch (_) {}

    final label = switch (action) {
      BatteryBotAction.shellySetup => 'Mở thiết lập Shelly',
      BatteryBotAction.guideCharging => 'Đến trang Sạc pin',
      BatteryBotAction.guideHistory => 'Xem tab Lịch sử',
      BatteryBotAction.guideVehicle => 'Xem màn hình Tổng quan',
      null => actionKey,
    };

    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        foregroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      onPressed: () {
        if (action != null) {
          onActionPressed?.call(action);
        }
      },
    );
  }
}

class _FeedbackButton extends StatelessWidget {
  const _FeedbackButton({
    required this.icon,
    required this.activeIcon,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(
          isSelected ? activeIcon : icon,
          size: 13,
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
