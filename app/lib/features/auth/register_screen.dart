import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/utils/app_error_formatter.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_kit.dart';
import 'widgets/luxe_auth_widgets.dart';

/// Account registration in the LUXE language with verified validation rules.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await AuthService()
          .register(
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text,
            name: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;

      if (result['success'] == true) {
        AppPopup.showSuccess('Đăng ký thành công!');
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        setState(() {
          _error = AppErrorFormatter.format(result['code'] ?? result['error']);
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _error =
              'Yêu cầu đang mất nhiều thời gian. Hãy kiểm tra mạng rồi thử đăng nhập lại.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = AppErrorFormatter.format(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData prefixIcon,
    String? hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(prefixIcon, size: 20),
      errorMaxLines: 3,
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
  }

  Widget _visibilityToggle({
    required bool obscured,
    required String showLabel,
    required String hideLabel,
    required VoidCallback onPressed,
  }) => IconButton(
    tooltip: obscured ? showLabel : hideLabel,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: Icon(
      obscured ? Icons.visibility_off_rounded : Icons.visibility_rounded,
      color: LuxeColors.platinumMid,
    ),
    onPressed: onPressed,
  );

  @override
  Widget build(BuildContext context) {
    const fieldStyle = TextStyle(color: LuxeColors.text, fontSize: 15);
    return LuxeAuthScaffold(
      leading: LuxeCircleButton(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Quay lại đăng nhập',
        onPressed: _loading ? null : () => Navigator.of(context).pop(),
      ),
      children: [
        Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LuxeAuthHeading(
                eyebrow: 'Tài khoản mới',
                title: 'Tạo tài khoản',
                caption: 'Nhập thông tin để bắt đầu quản lý pin xe điện.',
                center: false,
              ),
              const SizedBox(height: 22),
              LuxeAuthCard(
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    style: fieldStyle,
                    decoration: _inputDecoration(
                      label: 'Họ và tên',
                      hint: 'Ví dụ: Nguyễn Văn A',
                      prefixIcon: Icons.person_outline_rounded,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Vui lòng nhập họ tên';
                      }
                      if (v.trim().length < 2) {
                        return 'Họ tên quá ngắn';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    style: fieldStyle,
                    decoration: _inputDecoration(
                      label: 'Email',
                      hint: 'name@example.com',
                      prefixIcon: Icons.alternate_email_rounded,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Vui lòng nhập email';
                      }
                      if (!v.contains('@') || !v.contains('.')) {
                        return 'Email không hợp lệ';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                    style: fieldStyle,
                    decoration: _inputDecoration(
                      label: 'Số điện thoại',
                      hint: '09xxxxxxxx',
                      prefixIcon: Icons.phone_android_rounded,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Vui lòng nhập số điện thoại';
                      }
                      if (v.trim().length < 9) {
                        return 'Số điện thoại không hợp lệ';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscurePass,
                    textInputAction: TextInputAction.next,
                    style: fieldStyle,
                    onChanged: (_) => setState(() {}),
                    decoration: _inputDecoration(
                      label: 'Mật khẩu',
                      hint: 'Tối thiểu 6 ký tự',
                      prefixIcon: Icons.lock_outline_rounded,
                      suffix: _visibilityToggle(
                        obscured: _obscurePass,
                        showLabel: 'Hiện mật khẩu',
                        hideLabel: 'Ẩn mật khẩu',
                        onPressed: () =>
                            setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Vui lòng nhập mật khẩu';
                      }
                      if (v.length < 6) {
                        return 'Mật khẩu tối thiểu 6 ký tự';
                      }
                      return null;
                    },
                  ),
                  LuxePasswordStrength(password: _passCtrl.text),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmPassCtrl,
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _register(),
                    style: fieldStyle,
                    decoration: _inputDecoration(
                      label: 'Xác nhận mật khẩu',
                      hint: 'Nhập lại mật khẩu',
                      prefixIcon: Icons.lock_reset_rounded,
                      suffix: _visibilityToggle(
                        obscured: _obscureConfirm,
                        showLabel: 'Hiện mật khẩu xác nhận',
                        hideLabel: 'Ẩn mật khẩu xác nhận',
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Vui lòng xác nhận mật khẩu';
                      }
                      if (v != _passCtrl.text) {
                        return 'Mật khẩu không khớp';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              AnimatedSize(
                duration: luxeDuration(context, 280),
                curve: LuxeMotion.enter,
                alignment: Alignment.topCenter,
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: LuxeAuthError(_error!),
                      ),
              ),
              FilledButton(
                onPressed: _loading ? null : _register,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: _loading
                    ? const LuxeButtonSpinner(semanticsLabel: 'Đang đăng ký')
                    : const Text('Đăng ký'),
              ),
              const SizedBox(height: 10),
              LuxeAuthLink(
                prefix: 'Đã có tài khoản? ',
                action: 'Đăng nhập',
                onPressed: _loading ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
