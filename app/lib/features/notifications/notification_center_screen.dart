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
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
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
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          // Invalidate provider để tạo lại stream → retry query
          ref.invalidate(notificationsProvider);
          // Đợi 1 frame để stream re-subscribe
          await Future<void>.delayed(const Duration(milliseconds: 200));
        },
        child: notificationsAsync.when(
          data: (notifications) {
            if (notifications.isEmpty) {
              return _buildScrollableState(_buildEmptyState());
            }
            return _buildNotificationList(notifications);
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (error, stack) {
            debugPrint('[NotificationCenter] Stream error: $error');
            return _buildScrollableState(_buildErrorState(error));
          },
        ),
      ),
    );
  }

  /// Bọc widget trong scroll view để pull-to-refresh hoạt động khi list rỗng/lỗi.
  Widget _buildScrollableState(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    final message = error.toString();
    final isIndex =
        message.contains('failed-precondition') ||
        message.toLowerCase().contains('index');
    final isPermission =
        message.contains('permission-denied') ||
        message.toLowerCase().contains('permission');

    final hint = isIndex
        ? 'Query Firestore cần composite index. Hãy deploy `firestore.indexes.json` mới nhất.'
        : isPermission
        ? 'Bạn không có quyền đọc thông báo. Vui lòng đăng nhập lại.'
        : 'Đã xảy ra lỗi khi tải thông báo. Vui lòng thử lại.';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 56, color: Colors.red.withAlpha(180)),
          const SizedBox(height: 16),
          Text(
            'Không tải được thông báo',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (kDebugMode)
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary.withAlpha(140),
                fontSize: 11,
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => ref.invalidate(notificationsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
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
    // Mark as read silently in the background
    if (notification.isUnread) {
      await _service.markAsRead(notification.id);
    }

    if (!mounted) return;

    // Show full-detail bottom sheet FIRST so the user sees the whole message
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationDetailSheet(
        notification: notification,
        onNavigate: notification.actionTarget != null
            ? () => _navigateToTarget(notification.actionTarget!)
            : null,
      ),
    );
  }

  void _navigateToTarget(String target) {
    // Close sheet, switch the root tab, then close notification center.
    Navigator.pop(context); // pop detail sheet
    if (target.startsWith('/ai/')) {
      AppNavigation.navigateToTab(context, 1);
      if (Navigator.canPop(context)) Navigator.pop(context);
    } else if (target == '/ai') {
      AppNavigation.navigateToTab(context, 1);
      if (Navigator.canPop(context)) Navigator.pop(context);
    } else if (target == '/maintenance') {
      AppNavigation.navigateToTab(context, 3);
      if (Navigator.canPop(context)) Navigator.pop(context);
    } else {
      Navigator.pop(context); // pop notification center
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
        child: const Icon(Icons.archive_outlined, color: Colors.red),
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _getIconBackgroundColor(),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_getIcon(), color: _getIconColor(), size: 24),
          ),
          title: Text(
            notification.title,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: notification.isUnread
                  ? FontWeight.w700
                  : FontWeight.w600,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                notification.message,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
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

// =============================================================================
// Notification Detail Bottom Sheet
// =============================================================================

class _NotificationDetailSheet extends StatelessWidget {
  final UserNotification notification;
  final VoidCallback? onNavigate;

  const _NotificationDetailSheet({required this.notification, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: screenHeight * 0.86),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomPadding),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Icon + type chip row
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _iconBg(),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(_icon(), color: _iconColor(), size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _iconBg(),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _typeLabel(),
                            style: TextStyle(
                              color: _iconColor(),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTime(notification.createdAt),
                          style: TextStyle(
                            color: AppColors.textSecondary.withAlpha(160),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Full title
              Text(
                notification.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),

              // Full message — no maxLines truncation
              Text(
                notification.message,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),

              // Optional user-facing context. Internal debug payload keys are
              // intentionally hidden from the notification surface.
              if (_metadataRows().isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withAlpha(40)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _metadataRows(),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action button
              if (onNavigate != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onNavigate,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Xem chi tiết'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                        color: AppColors.textSecondary.withAlpha(60),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Đóng'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _metadataRows() {
    final payload = notification.payload;
    if (payload == null || payload.isEmpty) return const [];

    final rows = <({String label, String value})>[];
    void add(String label, dynamic value) {
      if (value == null) return;
      final text = value.toString().trim();
      if (text.isEmpty) return;
      rows.add((label: label, value: text));
    }

    switch (notification.type) {
      case NotificationType.modelUpdated:
        add('Model', payload['modelName']);
        add('Phiên bản', payload['version']);
        final mobileCompatible = payload['mobileCompatible'];
        if (mobileCompatible is bool) {
          add(
            'Kênh sử dụng',
            mobileCompatible ? 'Có thể tải về app' : 'Chạy qua server',
          );
        }
        break;
      case NotificationType.modelDownloadFailed:
        add('Model', payload['modelName']);
        add('Lỗi', payload['error']);
        break;
      case NotificationType.maintenanceDue:
        add('Xe', payload['vehicleName']);
        add('Hạng mục', payload['taskName']);
        break;
      case NotificationType.chargeReminder:
        add('Mức pin', _percent(payload['targetPercent']));
        add('Thời gian', _dateTimeText(payload['scheduledAt']));
        break;
      case NotificationType.system:
        final latestVersion = payload['latestVersion'];
        final latestBuild = payload['latestBuild'];
        if (latestVersion != null) {
          add(
            'Phiên bản mới',
            latestBuild == null ? latestVersion : '$latestVersion+$latestBuild',
          );
        }
        final forceUpdate = payload['forceUpdate'];
        if (forceUpdate is bool) {
          add('Cập nhật', forceUpdate ? 'Bắt buộc' : 'Tùy chọn');
        }
        break;
      case NotificationType.syncCompleted:
      case NotificationType.syncFailed:
      case NotificationType.batteryAlert:
        const hiddenKeys = {
          'modelKey',
          'isNew',
          'mobileCompatible',
          'actionTarget',
        };
        for (final entry in payload.entries) {
          if (hiddenKeys.contains(entry.key) || entry.value == null) continue;
          add(_humanizePayloadKey(entry.key), entry.value);
        }
        break;
    }

    return [
      for (var i = 0; i < rows.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  rows[i].label,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  rows[i].value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  String? _percent(dynamic value) {
    if (value == null) return null;
    return '$value%';
  }

  String? _dateTimeText(dynamic value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return _formatTime(parsed);
  }

  String _humanizePayloadKey(String key) {
    switch (key) {
      case 'version':
        return 'Phiên bản';
      case 'latestBuild':
        return 'Build';
      case 'latestVersion':
        return 'Phiên bản';
      case 'forceUpdate':
        return 'Bắt buộc';
      default:
        return key;
    }
  }

  IconData _icon() {
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

  Color _iconBg() {
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

  Color _iconColor() {
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

  String _typeLabel() {
    switch (notification.type) {
      case NotificationType.modelUpdated:
        return 'Model AI';
      case NotificationType.modelDownloadFailed:
        return 'Lỗi tải model';
      case NotificationType.syncCompleted:
        return 'Đồng bộ xong';
      case NotificationType.syncFailed:
        return 'Lỗi đồng bộ';
      case NotificationType.maintenanceDue:
        return 'Bảo dưỡng';
      case NotificationType.batteryAlert:
        return 'Cảnh báo pin';
      case NotificationType.chargeReminder:
        return 'Nhắc sạc';
      case NotificationType.system:
        return 'Hệ thống';
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays > 7) {
      final h = time.hour.toString().padLeft(2, '0');
      final m = time.minute.toString().padLeft(2, '0');
      return '${time.day}/${time.month}/${time.year} $h:$m';
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
