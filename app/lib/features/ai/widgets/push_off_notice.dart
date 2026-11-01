import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/theme/plan_style.dart';
import '../../../core/widgets/app_popup.dart';
import '../../../core/widgets/luxe_kit.dart';
import '../../../data/services/push_notification_service.dart';

/// QA 141: the charging notification (%, time left, Dừng on the lock
/// screen) and the "đã sạc xong" alert need push. When the owner has it off,
/// the Charge tab says so once, with a button; "Để sau" hides it for 30 days.
class PushOffNotice extends StatefulWidget {
  const PushOffNotice({super.key, this.service});

  /// Seam for tests.
  final PushNotificationService? service;

  static const dismissedKey = 'push_off_notice_dismissed_at';
  static const quiet = Duration(days: 30);

  @override
  State<PushOffNotice> createState() => _PushOffNoticeState();
}

class _PushOffNoticeState extends State<PushOffNotice> {
  bool _show = false;
  bool _busy = false;

  PushNotificationService get _push =>
      widget.service ?? PushNotificationService.instance;

  @override
  void initState() {
    super.initState();
    _push.userChoice.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    _push.userChoice.removeListener(_check);
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getInt(PushOffNotice.dismissedKey);
      final quiet =
          dismissed != null &&
          DateTime.now()
                  .difference(DateTime.fromMillisecondsSinceEpoch(dismissed))
                  .abs() <
              PushOffNotice.quiet;
      final enabled = await _push.isEnabledByUser();
      if (mounted) setState(() => _show = !enabled && !quiet);
    } on Object {
      // No plugins (widget tests): nothing to suggest.
    }
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    final enabled = await _push.setEnabledByUser(true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _show = !enabled;
    });
    if (enabled) {
      AppPopup.showMessage('Đã bật thông báo sạc', kind: AppNoticeKind.success);
    } else {
      AppPopup.showWarning(
        'Thông báo chưa được bật',
        detail: 'Bạn có thể cho phép thông báo trong Cài đặt của điện thoại.',
      );
    }
  }

  Future<void> _later() async {
    setState(() => _show = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      PushOffNotice.dismissedKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final accent = context.planAccent;
    return Padding(
      key: const ValueKey('push-off-notice'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LuxeNotice(
            icon: Icons.notifications_off_rounded,
            color: LuxeColors.champagne,
            message:
                'Thông báo đang tắt: bạn sẽ không thấy % pin, giờ còn lại và '
                'nút Dừng trên màn khóa, cũng không được báo khi sạc xong.',
          ),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                key: const ValueKey('push-off-later'),
                onPressed: _busy ? null : _later,
                style: TextButton.styleFrom(foregroundColor: LuxeColors.muted),
                child: const Text('Để sau'),
              ),
              TextButton(
                key: const ValueKey('push-off-enable'),
                onPressed: _busy ? null : _enable,
                style: TextButton.styleFrom(foregroundColor: accent),
                child: const Text('Bật thông báo'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
