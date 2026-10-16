import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/battery_bot_faq.dart';
import '../models/chat_message.dart';
import '../models/function_call_action.dart';
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
    this.showMeta = true,
  });

  final ChatMessage message;
  final void Function(String rating)? onFeedback;
  final void Function(BatteryBotAction action)? onActionPressed;
  final void Function(FunctionCallAction action)? onConfirmAction;
  final void Function(FunctionCallAction action)? onCancelAction;
  final VoidCallback? onRetry;
  final bool isActionLoading;

  /// Copy/share/feedback row; hidden for the greeting.
  final bool showMeta;

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
      '${message.content}\n\n— BatteryBot · VinFast Battery',
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
        padding: const EdgeInsets.fromLTRB(48, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: screenWidth * 0.8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(22),
                  topRight: Radius.circular(22),
                  bottomLeft: Radius.circular(22),
                  bottomRight: Radius.circular(6),
                ),
                gradient: message.isQueued
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF7F7F5), Color(0xFFD3D6DA)],
                      ),
                color: message.isQueued ? const Color(0xFF1D1F22) : null,
                border: message.isQueued
                    ? Border.all(color: const Color(0x38FFFFFF))
                    : null,
                boxShadow: message.isQueued
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x22FFFFFF),
                          blurRadius: 16,
                          spreadRadius: -6,
                        ),
                      ],
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: message.isQueued
                      ? const Color(0xFFF2F2F0)
                      : const Color(0xFF0B0C0E),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.isQueued) ...[
                  const Icon(
                    Icons.schedule_rounded,
                    size: 12,
                    color: Color(0xFF858990),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  message.isQueued ? 'Chờ mạng' : timeStr,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF858990),
                  ),
                ),
              ],
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
    // Luxe: BatteryBot answers as open text (no bubble) under a small
    // signature line; cards and actions sit flush with the text.
    const dim = Color(0xFF858990);
    return Semantics(
      label: 'BatteryBot trả lời: ${message.content}',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BreathingBotAvatar(size: 24, isStreaming: message.isStreaming),
                const SizedBox(width: 10),
                Text(
                  timeStr,
                  style: const TextStyle(fontSize: 10.5, color: dim),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: EdgeInsets.only(left: message.hasError ? 12 : 0),
              decoration: message.hasError
                  ? BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: theme.colorScheme.error.withValues(alpha: 0.6),
                          width: 2,
                        ),
                      ),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StreamingTextWidget(
                    text: message.content,
                    isStreaming: message.isStreaming,
                  ),
                  if (message.hasError && onRetry != null) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text(
                        'Thử lại câu trả lời',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (message.actionCard != null) ...[
              const SizedBox(height: 10),
              ActionConfirmationCard(
                action: message.actionCard!,
                isLoading: isActionLoading,
                onConfirm: () => onConfirmAction?.call(message.actionCard!),
                onCancel: () => onCancelAction?.call(message.actionCard!),
              ),
            ],
            if (message.richCards != null && message.richCards!.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final card in message.richCards!)
                _buildRichCard(context, card),
            ],
            if (message.action != null) ...[
              const SizedBox(height: 10),
              _buildActionChip(context, message.action!),
            ],
            if (showMeta && !message.isStreaming && message.content.isNotEmpty)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _BubbleActionButton(
                    icon: Icons.copy_rounded,
                    tooltip: 'Sao chép',
                    onTap: () => _copyToClipboard(context),
                  ),
                  _BubbleActionButton(
                    icon: Icons.ios_share_rounded,
                    tooltip: 'Chia sẻ',
                    onTap: _shareMessage,
                  ),
                  _FeedbackButton(
                    icon: Icons.thumb_up_alt_outlined,
                    activeIcon: Icons.thumb_up_alt_rounded,
                    isSelected: message.userFeedback == 'like',
                    onTap: () => onFeedback?.call('like'),
                  ),
                  _FeedbackButton(
                    icon: Icons.thumb_down_alt_outlined,
                    activeIcon: Icons.thumb_down_alt_rounded,
                    isSelected: message.userFeedback == 'dislike',
                    onTap: () => onFeedback?.call('dislike'),
                  ),
                ],
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

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF34D399),
        side: const BorderSide(color: Color(0x8034D399)),
        backgroundColor: const Color(0x1434D399),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: const StadiumBorder(),
      ),
      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      onPressed: () {
        if (action != null) {
          onActionPressed?.call(action);
        }
      },
    );
  }

  Widget _buildRichCard(BuildContext context, Map<String, dynamic> card) {
    final cardType = card['cardType'] is String
        ? card['cardType'] as String
        : '';
    final title = card['title'] is String ? card['title'] as String : '';
    final raw = card['data'];
    final data = raw is Map
        ? Map<String, dynamic>.fromEntries(
            raw.entries
                .where((e) => e.key is String)
                .map((e) => MapEntry(e.key as String, e.value)),
          )
        : <String, dynamic>{};
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
      'local_prediction' => ['durationSeconds'],
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
      case 'local_prediction':
        final seconds = data['durationSeconds'] as num;
        if (seconds <= 0 ||
            seconds > 36000 ||
            data['source'] != 'model local' ||
            data['modelVersion'] is! String ||
            (data['modelVersion'] as String).isEmpty ||
            data['updatedAt'] is! String ||
            DateTime.tryParse(data['updatedAt'] as String) == null) {
          return const Text(
            'Chưa có dự đoán hợp lệ. Hãy kiểm tra model và dữ liệu.',
          );
        }
        final time = DateTime.parse(data['updatedAt'] as String).toLocal();
        return Semantics(
          container: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  '${(seconds / 60).ceil()} phút',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('Mô hình trên máy · ${data['modelVersion']}'),
                Text('Tính lúc ${DateFormat('HH:mm dd/MM/yyyy').format(time)}'),
                const SizedBox(height: 8),
                const Text(
                  'Ước tính theo dữ liệu đầu vào, không phải số đo BMS hoặc quyền bật sạc.',
                ),
              ],
            ),
          ),
        );
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
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    icon: Icon(icon, size: 16, color: const Color(0xFF858990)),
  );
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
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: isSelected,
    label: icon == Icons.thumb_up_alt_outlined ? 'Hữu ích' : 'Chưa hữu ích',
    excludeSemantics: true,
    child: IconButton(
      onPressed: onTap,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, a) =>
            ScaleTransition(scale: a, child: child),
        child: Icon(
          isSelected ? activeIcon : icon,
          key: ValueKey(isSelected),
          size: 16,
          color: isSelected ? const Color(0xFF34D399) : const Color(0xFF858990),
        ),
      ),
    ),
  );
}
