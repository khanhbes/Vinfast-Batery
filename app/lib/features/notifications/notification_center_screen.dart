import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/notification_center_service.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/user_notification.dart';
import '../../navigation/app_navigation.dart';

/// Provider cho stream thông báo
final notificationsProvider = StreamProvider<List<UserNotification>>((ref) {
  return NotificationCenterService().watchNotifications();
});

/// Provider cho unread count
final unreadCountProvider = StreamProvider<int>((ref) {
  return NotificationCenterService().watchUnreadCount();
});

/// Notification Center Screen - hiển thị danh sách thông báo
class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends ConsumerState<NotificationCenterScreen> {
  final _service = NotificationCenterService();

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Thông báo',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          // Mark all read button
          TextButton.icon(
            onPressed: () => _markAllAsRead(),
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('Đọc tất cả'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
      body: notificationsAsync.when(
        data: (notifications) {
          if (notifications.isEmpty) {
            return _buildEmptyState();
          }
          return _buildNotificationList(notifications);
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (error, stack) {
          // Firestore compound query may fail without index — show empty state
          debugPrint('[NotificationCenter] Stream error: $error');
          return _buildEmptyState();
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 64,
            color: AppColors.textSecondary.withAlpha(100),
          ),
          const SizedBox(height: 16),
          Text(
            'Chưa có thông báo',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Các thông báo về model AI, bảo dưỡng\nvà cảnh báo pin sẽ xuất hiện ở đây',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary.withAlpha(150),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList(List<UserNotification> notifications) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: notifications.length,
      itemBuilder: (context, index) {
        final notification = notifications[index];
        return _NotificationCard(
          notification: notification,
          onTap: () => _onNotificationTap(notification),
          onDismiss: () => _dismissNotification(notification),
        );
      },
    );
  }

  Future<void> _markAllAsRead() async {
    await _service.markAllAsRead();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã đánh dấu tất cả là đã đọc')),
      );
    }
  }

  Future<void> _onNotificationTap(UserNotification notification) async {
    // Mark as read
    if (notification.isUnread) {
      await _service.markAsRead(notification.id);
    }

    // Navigate based on actionTarget
    if (notification.actionTarget != null) {
      _navigateToTarget(notification.actionTarget!);
    }
  }

  void _navigateToTarget(String target) {
    // Parse target và navigate
    if (target.startsWith('/ai/')) {
      final modelKey = target.replaceFirst('/ai/', '');
      // Navigate đến AI tab với model cụ thể — PLAN1: AI tab index = 1
      AppNavigation.navigateToTab(context, 1);
    } else if (target == '/ai') {
      AppNavigation.navigateToTab(context, 1);
    } else if (target == '/maintenance') {
      AppNavigation.navigateToTab(context, 3); // Maintenance tab
    } else {
      // Default: just close notification center
      Navigator.pop(context);
    }
  }

  Future<void> _dismissNotification(UserNotification notification) async {
    await _service.archive(notification.id);
  }
}

/// Card hiển thị một thông báo
class _NotificationCard extends StatelessWidget {
  final UserNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(50),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(
          Icons.archive_outlined,
          color: Colors.red,
        ),
      ),
      onDismissed: (_) => onDismiss(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: notification.isUnread
              ? AppColors.primary.withAlpha(20)
              : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notification.isUnread
                ? AppColors.primary.withAlpha(50)
                : AppColors.cardBackground,
            width: 1,
          ),
        ),
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _getIconBackgroundColor(),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getIcon(),
              color: _getIconColor(),
              size: 24,
            ),
          ),
          title: Text(
            notification.title,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: notification.isUnread ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                notification.message,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                _formatTime(notification.createdAt),
                style: TextStyle(
                  color: AppColors.textSecondary.withAlpha(150),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          trailing: notification.isUnread
              ? Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (notification.type) {
      case NotificationType.modelUpdated:
        return Icons.psychology;
      case NotificationType.modelDownloadFailed:
        return Icons.error_outline;
      case NotificationType.syncCompleted:
        return Icons.check_circle_outline;
      case NotificationType.syncFailed:
        return Icons.cancel_outlined;
      case NotificationType.maintenanceDue:
        return Icons.build_outlined;
      case NotificationType.batteryAlert:
        return Icons.battery_alert;
      case NotificationType.chargeReminder:
        return Icons.electrical_services;
      case NotificationType.system:
        return Icons.info_outline;
    }
  }

  Color _getIconBackgroundColor() {
    switch (notification.type) {
      case NotificationType.modelUpdated:
      case NotificationType.syncCompleted:
        return Colors.green.withAlpha(30);
      case NotificationType.modelDownloadFailed:
      case NotificationType.syncFailed:
      case NotificationType.batteryAlert:
        return Colors.red.withAlpha(30);
      case NotificationType.maintenanceDue:
      case NotificationType.chargeReminder:
        return Colors.orange.withAlpha(30);
      case NotificationType.system:
        return Colors.blue.withAlpha(30);
    }
  }

  Color _getIconColor() {
    switch (notification.type) {
      case NotificationType.modelUpdated:
      case NotificationType.syncCompleted:
        return Colors.green;
      case NotificationType.modelDownloadFailed:
      case NotificationType.syncFailed:
      case NotificationType.batteryAlert:
        return Colors.red;
      case NotificationType.maintenanceDue:
      case NotificationType.chargeReminder:
        return Colors.orange;
      case NotificationType.system:
        return Colors.blue;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays > 7) {
      return '${time.day}/${time.month}';
    } else if (diff.inDays > 0) {
      return '${diff.inDays} ngày trước';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} giờ trước';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} phút trước';
    } else {
      return 'Vừa xong';
    }
  }
}
