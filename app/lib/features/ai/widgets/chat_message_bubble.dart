import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/battery_bot_faq.dart';
import '../models/chat_message.dart';
import '../models/function_call_action.dart';
import '../theme/chatbot_glass_theme.dart';
import 'action_confirmation_card.dart';
import 'battery_status_card.dart';
import 'breathing_bot_avatar.dart';
import 'charging_progress_card.dart';
import 'streaming_text_widget.dart';
import 'trip_summary_card.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onFeedback,
    this.onActionPressed,
    this.onConfirmAction,
    this.onCancelAction,
    this.onRetry,
    this.isActionLoading = false,
  });

  final ChatMessage message;
  final void Function(String rating)? onFeedback;
  final void Function(BatteryBotAction action)? onActionPressed;
  final void Function(FunctionCallAction action)? onConfirmAction;
  final void Function(FunctionCallAction action)? onCancelAction;
  final VoidCallback? onRetry;
  final bool isActionLoading;

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã sao chép nội dung tin nhắn'),
        duration: Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _shareMessage() {
    Share.share(
      '${message.content}\n\n— VinFast Battery Copilot',
      subject: 'Chia sẻ từ VinFast Battery',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr = DateFormat('HH:mm').format(message.timestamp);
    final screenWidth = MediaQuery.of(context).size.width;

    // Smooth Entrance Animation (Slide-in & Fade-in)
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (context, animValue, child) {
        return Opacity(
          opacity: animValue,
          child: Transform.translate(
            offset: Offset(0, (1.0 - animValue) * 8.0),
            child: child,
          ),
        );
      },
      child: !message.fromBot
          ? _buildUserBubble(context, theme, timeStr, screenWidth)
          : _buildBotBubble(context, theme, timeStr, screenWidth),
    );
  }

  Widget _buildUserBubble(
    BuildContext context,
    ThemeData theme,
    String timeStr,
    double screenWidth,
  ) {
    return Semantics(
      label: 'Tin nhắn của bạn: ${message.content}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.isQueued) ...[
              Icon(
                Icons.schedule_rounded,
                size: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              message.isQueued ? 'Chờ mạng' : timeStr,
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Container(
                constraints: BoxConstraints(maxWidth: screenWidth * 0.82),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: ChatbotGlassTheme.userBubbleDecoration(
                  context,
                  isQueued: message.isQueued,
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
      ),
    );
  }

  Widget _buildBotBubble(
    BuildContext context,
    ThemeData theme,
    String timeStr,
    double screenWidth,
  ) {
    final hasRichCards =
        (message.richCards != null && message.richCards!.isNotEmpty) ||
        message.actionCard != null;

    // Responsive width: normal text bubble takes up to 82% of screen;
    // rich cards can use up to 88% on small screens so they never squeeze.
    final maxBubbleWidth = screenWidth * (hasRichCards ? 0.88 : 0.82);

    return Semantics(
      label: 'BatteryBot trả lời: ${message.content}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Breathing Bot Avatar with halo
            BreathingBotAvatar(size: 32, isStreaming: message.isStreaming),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 11,
                    ),
                    decoration: ChatbotGlassTheme.botBubbleDecoration(
                      context,
                      hasError: message.hasError,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StreamingTextWidget(
                          text: message.content,
                          isStreaming: message.isStreaming,
                        ),
                        if (message.hasError && onRetry != null) ...[
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: onRetry,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.refresh_rounded,
                                    size: 14,
                                    color: theme.colorScheme.error,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Thử lại câu trả lời',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (message.actionCard != null) ...[
                          const SizedBox(height: 8),
                          ActionConfirmationCard(
                            action: message.actionCard!,
                            isLoading: isActionLoading,
                            onConfirm: () =>
                                onConfirmAction?.call(message.actionCard!),
                            onCancel: () =>
                                onCancelAction?.call(message.actionCard!),
                          ),
                        ],
                        if (message.richCards != null &&
                            message.richCards!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          for (final card in message.richCards!)
                            _buildRichCard(context, card),
                        ],
                        if (message.action != null) ...[
                          const SizedBox(height: 10),
                          _buildActionChip(context, message.action!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Bottom action row: Timestamp, Copy, Share, Thumb Up / Down
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ),
                      if (!message.isStreaming &&
                          message.content.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        // Nút Copy
                        _BubbleActionButton(
                          icon: Icons.copy_rounded,
                          tooltip: 'Sao chép',
                          onTap: () => _copyToClipboard(context),
                        ),
                        const SizedBox(width: 4),
                        // Nút Share
                        _BubbleActionButton(
                          icon: Icons.share_rounded,
                          tooltip: 'Chia sẻ',
                          onTap: _shareMessage,
                        ),
                        const SizedBox(width: 6),
                        // Thumbs up / down feedback
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
      ),
    );
  }

  Widget _buildActionChip(BuildContext context, String actionKey) {
    BatteryBotAction? action;
    try {
      action = BatteryBotAction.values.firstWhere((a) => a.name == actionKey);
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
        backgroundColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.12),
        foregroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
      onPressed: () {
        if (action != null) {
          onActionPressed?.call(action);
        }
      },
    );
  }

  Widget _buildRichCard(BuildContext context, Map<String, dynamic> card) {
    final cardType = card['cardType'] as String? ?? '';
    final title = card['title'] as String? ?? '';
    final data = (card['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final requiredFields = switch (cardType) {
      'battery_status' => [
        'soc',
        'soh',
        'voltage',
        'temperature',
        'estimatedRangeKm',
      ],
      'charging_progress' => [
        'currentSoc',
        'targetSoc',
        'chargingPowerW',
        'currentAmps',
        'remainingMinutes',
      ],
      'trip_summary' => [
        'distanceKm',
        'energyUsedWh',
        'efficiencyWhKm',
        'co2SavedKg',
        'durationMinutes',
      ],
      _ => <String>[],
    };
    if (requiredFields.any(
      (key) => data[key] is! num || !(data[key] as num).isFinite,
    )) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Chưa đủ dữ liệu để hiển thị. Hãy mở màn hình tương ứng để kiểm tra.',
        ),
      );
    }

    switch (cardType) {
      case 'battery_status':
        return BatteryStatusCard(
          title: title.isNotEmpty ? title : 'Trạng thái Pin & Xe',
          data: data,
        );
      case 'charging_progress':
        return ChargingProgressCard(
          title: title.isNotEmpty ? title : 'Tiến độ Sạc Thông Minh',
          data: data,
        );
      case 'trip_summary':
        return TripSummaryCard(
          title: title.isNotEmpty ? title : 'Tóm tắt Chuyến đi & Hiệu suất',
          data: data,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _BubbleActionButton extends StatelessWidget {
  const _BubbleActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Icon(
              icon,
              size: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
            ),
          ),
        ),
      ),
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
      child: Semantics(
        button: true,
        selected: isSelected,
        label: icon == Icons.thumb_up_outlined ? 'Hữu ích' : 'Chưa hữu ích',
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Icon(
              isSelected ? activeIcon : icon,
              size: 13,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
