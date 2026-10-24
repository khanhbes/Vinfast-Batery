import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/notification_center_service.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/user_notification.dart';
import '../../navigation/app_navigation.dart';
import '../support/help_center_screen.dart';

/// Provider cho stream thông báo
final notificationsProvider = StreamProvider.autoDispose
    .family<List<UserNotification>, String>((ref, uid) {
      return NotificationCenterService().watchNotifications(expectedUid: uid);
    });

/// Provider cho unread count
final unreadCountProvider = StreamProvider.autoDispose.family<int, String>((
  ref,
  uid,
) {
  return NotificationCenterService().watchUnreadCount(expectedUid: uid);
});

/// Notification Center Screen - hiển thị danh sách thông báo
class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({
    super.key,
    this.initialUid,
    this.accountChanges,
    this.refreshTimeout = const Duration(seconds: 20),
  });

  // Injectable account lifecycle for widget tests; repository access remains
  // protected by Firebase authentication and expectedUid checks.
  final String? initialUid;
  final Stream<String?>? accountChanges;
  final Duration refreshTimeout;

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  final _service = NotificationCenterService();
  bool _isDeletingAll = false;
  late String _currentUid;
  StreamSubscription<String?>? _authSubscription;
  List<UserNotification>? _lastNotifications;
  Object? _refreshError;
  int _refreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    _currentUid =
        widget.initialUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    final accounts =
        widget.accountChanges ??
        FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);
    _authSubscription = accounts.listen((account) {
      final uid = account ?? '';
      if (mounted && uid != _currentUid) {
        setState(() {
          _currentUid = uid;
          _lastNotifications = null;
          _refreshError = null;
          _refreshGeneration++;
        });
      }
    });
  }

  @override
  void dispose() {
    _refreshGeneration++;
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsProvider(_currentUid));
    final hasItems = notificationsAsync.asData?.value.isNotEmpty == true;
    final compactHeader = MediaQuery.textScalerOf(context).scale(10) > 14;

    return LuxeScaffold(
      appBar: LuxeAppBar(
        actions: [
          LuxeCircleButton(
            tooltip: 'Đánh dấu tất cả là đã đọc',
            onPressed: () => _markAllAsRead(),
            icon: Icons.done_all_rounded,
            color: LuxeColors.emerald,
          ),
          _isDeletingAll
              ? const SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: LuxeColors.danger,
                      ),
                    ),
                  ),
                )
              : LuxeCircleButton(
                  tooltip: 'Xóa tất cả thông báo',
                  onPressed: hasItems ? _confirmDeleteAll : null,
                  icon: Icons.delete_sweep_outlined,
                ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // With enlarged text only the title stays, so the list keeps room.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: LuxeReveal(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!compactHeader) ...[
                    const Text('TRUNG TÂM', style: LuxeText.eyebrow),
                    const SizedBox(height: 6),
                  ],
                  const Text('Thông báo', style: LuxeText.title),
                  if (!compactHeader) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Cập nhật về pin, sạc và bảo dưỡng',
                      style: LuxeText.caption,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: LuxeColors.emerald,
              backgroundColor: LuxeColors.raised,
              onRefresh: _refresh,
              child: notificationsAsync.when(
                data: (notifications) {
                  _lastNotifications = notifications;
                  return _refreshError == null
                      ? _buildContent(notifications)
                      : _buildStaleContent(notifications);
                },
                loading: () => _refreshError != null
                    ? (_lastNotifications != null
                          ? _buildStaleContent(_lastNotifications!)
                          : _buildScrollableState(
                              _buildErrorState(_refreshError!),
                            ))
                    : _lastNotifications != null
                    ? _buildContent(_lastNotifications!)
                    : const Padding(
                        padding: EdgeInsets.all(16),
                        child: LoadingSkeleton(layout: SkeletonLayout.list),
                      ),
                error: (error, stack) {
                  debugPrint(
                    '[NotificationCenter] Stream error (${error.runtimeType})',
                  );
                  return _lastNotifications != null
                      ? _buildStaleContent(_lastNotifications!)
                      : _buildScrollableState(_buildErrorState(error));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    final uid = _currentUid;
    final generation = ++_refreshGeneration;
    setState(() => _refreshError = null);
    ref.invalidate(notificationsProvider(uid));
    try {
      final notifications = await ref
          .read(notificationsProvider(uid).future)
          .timeout(widget.refreshTimeout);
      if (!mounted || uid != _currentUid || generation != _refreshGeneration) {
        return;
      }
      setState(() {
        _lastNotifications = notifications;
        _refreshError = null;
      });
      ref.invalidate(unreadCountProvider(uid));
    } catch (error) {
      if (!mounted || uid != _currentUid || generation != _refreshGeneration) {
        return;
      }
      setState(() => _refreshError = error);
    }
  }

  Widget _buildContent(List<UserNotification> notifications) {
    if (notifications.isNotEmpty) return _buildNotificationList(notifications);
    return _buildScrollableState(
      const EmptyState(
        icon: Icons.notifications_off_outlined,
        title: 'Chưa có thông báo',
        message: 'Thông báo về pin, phiên sạc và bảo dưỡng sẽ xuất hiện ở đây.',
      ),
    );
  }

  Widget _buildStaleContent(List<UserNotification> notifications) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: LuxeNotice(
          icon: Icons.cloud_off_rounded,
          color: LuxeColors.champagne,
          message: 'Chưa cập nhật được. Đang hiển thị dữ liệu cũ.',
          action: TextButton(
            onPressed: _refresh,
            style: TextButton.styleFrom(foregroundColor: LuxeColors.emerald),
            child: const Text('Thử lại'),
          ),
        ),
      ),
      Expanded(child: _buildContent(notifications)),
    ],
  );

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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ErrorState.fromError(
          error: error,
          prefix: 'Không tải được thông báo',
          onRetry: _refresh,
        ),
      ),
    );
  }

  static String _dayGroup(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Hôm nay';
    if (diff == 1) return 'Hôm qua';
    return 'Trước đó';
  }

  Widget _buildNotificationList(List<UserNotification> notifications) {
    // Flatten into day headers + cards, keeping the service order.
    final entries = <Object>[];
    String? group;
    for (final n in notifications) {
      final g = _dayGroup(n.createdAt);
      if (g != group) {
        entries.add(g);
        group = g;
      }
      entries.add(n);
    }
    var cardIndex = 0;
    final revealIndex = <String, int>{
      for (final e in entries)
        if (e is UserNotification) e.id: cardIndex++,
    };
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 32),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry is String) return LuxeSectionLabel(entry);
        final notification = entry as UserNotification;
        final i = revealIndex[notification.id] ?? 0;
        final card = _NotificationCard(
          notification: notification,
          onTap: () => _onNotificationTap(notification),
          onDismiss: () => _dismissNotification(notification),
        );
        return i < 8 ? LuxeReveal(index: i, child: card) : card;
      },
    );
  }

  Future<void> _markAllAsRead() async {
    final uid = _currentUid;
    final success = await _service.markAllAsRead();
    if (_currentUid != uid) return;
    if (mounted) {
      if (success) {
        ref.invalidate(notificationsProvider(uid));
        ref.invalidate(unreadCountProvider(uid));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Đã đánh dấu tất cả là đã đọc'
                : 'Không thể đánh dấu đã đọc. Vui lòng thử lại.',
          ),
        ),
      );
    }
  }

  Future<void> _confirmDeleteAll() async {
    final confirmed = await showLuxeConfirm(
      context,
      title: 'Xóa tất cả thông báo?',
      message: 'Tất cả thông báo trong tài khoản này sẽ bị xóa vĩnh viễn.',
      confirmLabel: 'Xóa tất cả',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingAll = true);
    final deleted = await _service.deleteAll();
    if (!mounted) return;
    setState(() => _isDeletingAll = false);
    if (deleted) {
      ref.invalidate(notificationsProvider(_currentUid));
      ref.invalidate(unreadCountProvider(_currentUid));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? 'Đã xóa tất cả thông báo'
              : 'Không thể xóa thông báo. Vui lòng thử lại.',
        ),
      ),
    );
  }

  Future<void> _onNotificationTap(UserNotification notification) async {
    final uid = _currentUid;
    if (uid.isEmpty || notification.userId != uid) return;
    if (notification.isUnread) {
      final marked = await _service.markAsRead(notification.id);
      if (marked && mounted && _currentUid == uid) {
        ref.invalidate(notificationsProvider(uid));
        ref.invalidate(unreadCountProvider(uid));
      }
    }

    if (!mounted || _currentUid != uid) return;

    // Show full-detail bottom sheet FIRST so the user sees the whole message
    await showLuxeSheet<void>(
      context,
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
    // Do not silently mutate the global selected vehicle from a notification
    // deep-link. The target vehicle/session remains explicit in the URL and
    // the user can switch context deliberately from the app shell.
    if (target.startsWith('/smart-charge') || target.startsWith('/ai/')) {
      final uri = Uri.tryParse(target);
      final vehicleId = uri?.queryParameters['vehicleId'];
      final sessionId = uri?.queryParameters['sessionId'];
      if (vehicleId != null &&
          vehicleId.isNotEmpty &&
          sessionId != null &&
          sessionId.isNotEmpty) {
        ref.read(pendingSmartChargeTargetProvider.notifier).state = (
          vehicleId: vehicleId,
          sessionId: sessionId,
        );
      }
      AppNavigation.navigateToTab(context, 1);
      if (Navigator.canPop(context)) Navigator.pop(context);
    } else if (target == '/ai') {
      AppNavigation.navigateToTab(context, 1);
      if (Navigator.canPop(context)) Navigator.pop(context);
    } else if (target == '/maintenance') {
      AppNavigation.navigateToTab(context, 3);
      if (Navigator.canPop(context)) Navigator.pop(context);
    } else if (target.startsWith('/support')) {
      // QA 135: a reply from the Pinova team.
      final ticketId = Uri.tryParse(target)?.queryParameters['ticketId'];
      HelpCenterScreen.open(context, ticketId: ticketId);
    } else {
      Navigator.pop(context); // pop notification center
    }
  }

  Future<bool> _dismissNotification(UserNotification notification) async {
    final uid = _currentUid;
    final archived = await _service.archive(notification.id);
    if (!mounted || uid != _currentUid) return false;
    if (archived) {
      ref.invalidate(notificationsProvider(uid));
      ref.invalidate(unreadCountProvider(uid));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể lưu thay đổi. Vui lòng thử lại.'),
        ),
      );
    }
    return archived;
  }
}

/// Card hiển thị một thông báo: glass row, metal medallion tinted by type,
/// an emerald rim + dot while unread. Swipe left to archive.
class _NotificationCard extends StatelessWidget {
  final UserNotification notification;
  final VoidCallback onTap;
  final Future<bool> Function() onDismiss;

  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, accent, _) = _typeStyle(notification.type);
    final unread = notification.isUnread;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: Key(notification.id),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(
            color: LuxeColors.danger.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: LuxeColors.danger.withValues(alpha: 0.3)),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Lưu trữ',
                style: TextStyle(
                  color: LuxeColors.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.archive_outlined, color: LuxeColors.danger),
            ],
          ),
        ),
        confirmDismiss: (_) => onDismiss(),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: LuxeGlass(
              selected: unread,
              radius: 20,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LuxeMedallion(icon: icon, accent: accent, size: 42),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          style: TextStyle(
                            color: LuxeColors.text,
                            fontSize: 15,
                            height: 1.3,
                            fontWeight: unread
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notification.message,
                          style: LuxeText.caption.copyWith(fontSize: 13),
                          softWrap: true,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatTime(notification.createdAt),
                          style: LuxeText.label.copyWith(
                            fontSize: 11,
                            color: LuxeColors.dim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (unread)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 6),
                      child: Semantics(
                        label: 'Chưa đọc',
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: LuxeColors.emerald,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: LuxeColors.emeraldGlow,
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
    final (icon, accent, typeLabel) = _typeStyle(notification.type);
    final metadata = _metadataRows();

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LuxeMedallion(icon: icon, accent: accent, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LuxeTag(typeLabel, color: accent),
                      const SizedBox(height: 6),
                      Text(
                        _formatTime(notification.createdAt),
                        style: LuxeText.caption.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              notification.title,
              style: LuxeText.title.copyWith(fontSize: 20, height: 1.3),
            ),
            const SizedBox(height: 10),
            Text(
              notification.message,
              style: const TextStyle(
                color: LuxeColors.text,
                fontSize: 14.5,
                height: 1.6,
              ),
            ),
            if (metadata.isNotEmpty) ...[
              const SizedBox(height: 18),
              LuxeGlass(
                radius: 16,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: metadata,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (onNavigate != null)
              FilledButton.icon(
                onPressed: onNavigate,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Xem chi tiết'),
              )
            else
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Đóng'),
              ),
          ],
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
          // Only fields with a Vietnamese label: raw ids such as sessionId
          // or vehicleId are not user information (Task 125).
          final label = _humanizePayloadKey(entry.key);
          if (label == null) continue;
          add(label, entry.value);
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
                  style: LuxeText.label.copyWith(fontSize: 12),
                ),
              ),
              Expanded(
                child: Text(
                  rows[i].value,
                  style: const TextStyle(
                    color: LuxeColors.text,
                    fontSize: 13,
                    height: 1.4,
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

  String? _humanizePayloadKey(String key) {
    switch (key) {
      case 'version':
        return 'Phiên bản';
      case 'latestBuild':
        return 'Bản dựng';
      case 'latestVersion':
        return 'Phiên bản';
      case 'forceUpdate':
        return 'Bắt buộc';
      case 'targetPercent':
        return 'Mục tiêu pin (%)';
      default:
        return null;
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

/// Icon, accent and label per notification type (LUXE palette).
(IconData, Color, String) _typeStyle(NotificationType type) => switch (type) {
  NotificationType.modelUpdated => (
    Icons.psychology_rounded,
    LuxeColors.emerald,
    'Model AI',
  ),
  NotificationType.modelDownloadFailed => (
    Icons.error_outline_rounded,
    LuxeColors.danger,
    'Lỗi tải model',
  ),
  NotificationType.syncCompleted => (
    Icons.check_circle_outline_rounded,
    LuxeColors.emerald,
    'Đồng bộ xong',
  ),
  NotificationType.syncFailed => (
    Icons.cancel_outlined,
    LuxeColors.danger,
    'Lỗi đồng bộ',
  ),
  NotificationType.maintenanceDue => (
    Icons.build_outlined,
    LuxeColors.champagne,
    'Bảo dưỡng',
  ),
  NotificationType.batteryAlert => (
    Icons.battery_alert_rounded,
    LuxeColors.danger,
    'Cảnh báo pin',
  ),
  NotificationType.chargeReminder => (
    Icons.electrical_services_rounded,
    LuxeColors.champagne,
    'Nhắc sạc',
  ),
  NotificationType.system => (
    Icons.info_outline_rounded,
    LuxeColors.steel,
    'Hệ thống',
  ),
};
