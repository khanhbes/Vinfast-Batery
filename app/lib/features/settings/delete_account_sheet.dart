import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/services/api_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_submit_button.dart';
import '../auth/auth_gate.dart';

/// The owner deletes their own account (QA 138, Google Play and App Store
/// rule). The password signs them in again (the server wants a sign-in from
/// the last 10 minutes), typing XÓA guards against a slip, and the server
/// refuses while a charge is running.
class DeleteAccountSheet extends ConsumerStatefulWidget {
  const DeleteAccountSheet({
    super.key,
    this.reauthenticate,
    this.deleteAccount,
    this.afterDelete,
  });

  /// Seams for tests; the app uses Firebase, the API and the auth gate.
  final Future<String?> Function(String password)? reauthenticate;
  final Future<Map<String, dynamic>> Function()? deleteAccount;
  final Future<void> Function()? afterDelete;

  static Future<void> open(BuildContext context) =>
      showLuxeSheet<void>(context, builder: (_) => const DeleteAccountSheet());

  @override
  ConsumerState<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<DeleteAccountSheet> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _confirmed {
    final typed = _confirm.text.trim().toUpperCase();
    return typed == 'XÓA' || typed == 'XOA';
  }

  @override
  void initState() {
    super.initState();
    _password.addListener(_refresh);
    _confirm.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<bool> _delete() async {
    setState(() => _error = null);
    final reauthenticate =
        widget.reauthenticate ?? AuthService().reauthenticate;
    final problem = await reauthenticate(_password.text);
    if (problem != null) {
      if (mounted) setState(() => _error = problem);
      return false;
    }
    final result = await (widget.deleteAccount ?? _deleteOnServer)();
    if (result['success'] != true) {
      if (mounted) {
        setState(
          () => _error =
              result['userMessage']?.toString() ??
              'Chưa xóa được tài khoản. Hãy thử lại.',
        );
      }
      return false;
    }
    await (widget.afterDelete ?? _leave)();
    return true;
  }

  static Future<Map<String, dynamic>> _deleteOnServer() =>
      ApiService().delete('/api/account', {'confirm': 'XOA TAI KHOAN'});

  Future<void> _leave() async {
    await AuthService().signOut();
    if (!mounted) return;
    ref.read(selectedVehicleIdProvider.notifier).state = '';
    ref.read(currentTabProvider.notifier).state = 0;
    AppPopup.showSuccess('Đã xóa tài khoản Pinova.');
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AuthGate()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LuxeSheetHeader(
            key: ValueKey('delete-account-sheet'),
            eyebrow: 'Tài khoản',
            title: 'Xóa tài khoản',
          ),
          const SizedBox(height: 10),
          const Text(
            'Xóa vĩnh viễn tài khoản và dữ liệu: hồ sơ, xe, lịch sử sạc và '
            'chuyến đi, số đọc pin và ODO, dữ liệu AI cá nhân, liên kết ổ '
            'Shelly, thông báo, kế hoạch sạc đêm, yêu cầu hỗ trợ và gói '
            'Premium. Không hoàn tác được.',
            style: LuxeText.body,
          ),
          const SizedBox(height: 12),
          const LuxeNotice(
            icon: Icons.power_settings_new_rounded,
            color: LuxeColors.champagne,
            message: 'Đang sạc thì hãy dừng sạc trước khi xóa.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('delete-account-password'),
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(
              labelText: 'Mật khẩu hiện tại',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('delete-account-confirm'),
            controller: _confirm,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Gõ XÓA để xác nhận',
              prefixIcon: Icon(Icons.warning_amber_rounded),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            LuxeNotice(
              key: const ValueKey('delete-account-error'),
              icon: Icons.error_outline_rounded,
              color: LuxeColors.danger,
              message: _error!,
            ),
          ],
          const SizedBox(height: 18),
          LuxeSubmitButton(
            key: const ValueKey('delete-account-submit'),
            label: 'Xóa vĩnh viễn',
            busyLabel: 'Đang xóa…',
            doneLabel: 'Đã xóa',
            icon: Icons.delete_forever_rounded,
            onBusyChanged: (busy) => setState(() => _busy = busy),
            onPressed: _password.text.isNotEmpty && _confirmed ? _delete : null,
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Để sau'),
          ),
        ],
      ),
    ),
  );
}
