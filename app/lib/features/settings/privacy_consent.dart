import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/pinova_api.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/theme/plan_style.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_kit.dart';

/// Chính sách bảo mật and the owner's consent (QA 140, Nghị định 13/2023 and
/// the Luật Bảo vệ dữ liệu cá nhân). The server holds the text and its
/// version; the app asks once per version and records the answer there.
abstract final class PrivacyConsent {
  /// Must match `web/support/privacy.py` VERSION.
  static const version = '2026-11-01';

  static Uri get policyUri => Uri.parse(
    '${AppConstants.apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '')}'
    '/chinh-sach-bao-mat',
  );

  static Future<void> openPolicy() async {
    final ok = await launchUrl(policyUri, mode: LaunchMode.externalApplication);
    if (!ok) {
      AppPopup.showMessage('Chưa mở được trang chính sách. Thử lại sau.');
    }
  }

  /// Records consent; false when the server is unreachable (asked again
  /// later).
  static Future<bool> accept({required String source}) async {
    try {
      await PinovaApi().post('/api/account/privacy-consent', {
        'version': version,
        'source': source,
      });
      return true;
    } on Object {
      return false;
    }
  }

  /// True when this account accepted the current version; null when the
  /// server could not say (never block the app on that).
  static Future<bool?> accepted() async {
    try {
      final data = await PinovaApi().get('/api/account/privacy-consent');
      return data['accepted'] == true && data['version'] == version;
    } on Object {
      return null;
    }
  }

  static bool _asking = false;

  /// After sign-in: an account that has not accepted this version is asked
  /// once (the sheet cannot be swiped away; the owner may also sign out).
  static Future<void> askIfNeeded(
    BuildContext context, {
    required Future<void> Function() onSignOut,
  }) async {
    if (_asking) return;
    final ok = await accepted();
    if (ok != false || !context.mounted) return;
    _asking = true;
    try {
      await showLuxeSheet<void>(
        context,
        isDismissible: false,
        enableDrag: false,
        builder: (sheet) => _ConsentSheet(onSignOut: onSignOut),
      );
    } finally {
      _asking = false;
    }
  }
}

/// "Tôi đã đọc và đồng ý Chính sách bảo mật" with the policy link.
class PrivacyConsentCheckbox extends StatelessWidget {
  const PrivacyConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: value,
    label: 'Đồng ý Chính sách bảo mật',
    child: InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: const ValueKey('privacy-consent-checkbox'),
              value: value,
              onChanged: (v) => onChanged(v ?? false),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      color: LuxeColors.muted,
                      fontSize: 13,
                      height: 1.45,
                    ),
                    children: [
                      const TextSpan(text: 'Tôi đã đọc và đồng ý '),
                      TextSpan(
                        text: 'Chính sách bảo mật',
                        style: TextStyle(
                          color: context.planAccent,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () =>
                              unawaited(PrivacyConsent.openPolicy()),
                      ),
                      const TextSpan(
                        text:
                            ', gồm việc dữ liệu của tôi được lưu và xử lý ở '
                            'nước ngoài (Firebase, Azure, Gemini) để cung cấp '
                            'dịch vụ.',
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
  );
}

class _ConsentSheet extends StatefulWidget {
  const _ConsentSheet({required this.onSignOut});
  final Future<void> Function() onSignOut;

  @override
  State<_ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends State<_ConsentSheet> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    final ok = await PrivacyConsent.accept(source: 'login');
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
      AppPopup.showMessage('Chưa lưu được. Kiểm tra mạng rồi thử lại.');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const LuxeSheetHeader(
              eyebrow: 'Quyền riêng tư',
              title: 'Chính sách bảo mật Pinova',
              caption: 'Bản cập nhật ${PrivacyConsent.version}',
            ),
            const SizedBox(height: 14),
            const Text(
              'Pinova dùng dữ liệu tài khoản, xe, phiên sạc và ổ Shelly để '
              'điều khiển sạc an toàn, ước tính pin và gửi thông báo. Dữ liệu '
              'được lưu và xử lý ở nước ngoài qua Firebase (Hoa Kỳ), Azure '
              '(Hồng Kông, Nhật Bản), Gemini và Shelly Cloud. Bạn có thể xem, '
              'tắt học cá nhân hoặc xóa tài khoản bất cứ lúc nào.',
              style: TextStyle(
                color: LuxeColors.text,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => unawaited(PrivacyConsent.openPolicy()),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Đọc toàn bộ chính sách'),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const ValueKey('privacy-consent-accept'),
              onPressed: _busy ? null : _accept,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Đồng ý và tiếp tục'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      Navigator.of(context).pop();
                      await widget.onSignOut();
                    },
              child: const Text('Không đồng ý, đăng xuất'),
            ),
          ],
        ),
      ),
    ),
  );
}
