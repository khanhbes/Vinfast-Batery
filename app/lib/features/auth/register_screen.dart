import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/cockpit_design_system.dart';
import '../../core/utils/app_error_formatter.dart';
import '../../core/widgets/app_popup.dart';

/// Account registration with Dark Cockpit theme and verified validation rules.
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
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
      prefixIcon: Icon(prefixIcon, color: const Color(0xFF00F5D4), size: 20),
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      filled: true,
      fillColor: const Color(0xFF132238).withValues(alpha: 0.6),
      errorMaxLines: 3,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF00F5D4), width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFF5252), width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFF5252), width: 1.8),
      ),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF04070D), // Deep Cockpit Obsidian
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Phông nền hào quang Cockpit (Ambient Radial Glow)
          Positioned(
            top: -60,
            left: 0,
            right: 0,
            height: 380,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.0, -0.4),
                    radius: 0.9,
                    colors: [
                      const Color(0xFF00F5D4).withValues(alpha: 0.14),
                      CockpitColors.emerald.withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 2. Nội dung form đăng ký
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Nút quay lại
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Material(
                            color: Colors.transparent,
                            child: IconButton(
                              tooltip: 'Quay lại đăng nhập',
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(
                                  0xFF0D1B2A,
                                ).withValues(alpha: 0.8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: const Color(
                                      0xFF00F5D4,
                                    ).withValues(alpha: 0.3),
                                  ),
                                ),
                              ),
                              onPressed: _loading
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Color(0xFF00F5D4),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Header tiêu đề
                        Text(
                          'Tạo tài khoản',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            shadows: [
                              Shadow(
                                color: const Color(
                                  0xFF00F5D4,
                                ).withValues(alpha: 0.4),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Nhập thông tin để bắt đầu quản lý pin xe điện.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF94A3B8),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Glassmorphic Form Card
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 22,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF0B132B,
                            ).withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(
                                0xFF00F5D4,
                              ).withValues(alpha: 0.22),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.55),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                              BoxShadow(
                                color: const Color(
                                  0xFF00F5D4,
                                ).withValues(alpha: 0.06),
                                blurRadius: 20,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 1. Họ và tên
                              TextFormField(
                                controller: _nameCtrl,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
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

                              // 2. Email
                              TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
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

                              // 3. Số điện thoại
                              TextFormField(
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(11),
                                ],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
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

                              // 4. Mật khẩu
                              TextFormField(
                                controller: _passCtrl,
                                obscureText: _obscurePass,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                                decoration: _inputDecoration(
                                  label: 'Mật khẩu',
                                  hint: 'Tối thiểu 6 ký tự',
                                  prefixIcon: Icons.lock_outline_rounded,
                                  suffix: IconButton(
                                    tooltip: _obscurePass
                                        ? 'Hiện mật khẩu'
                                        : 'Ẩn mật khẩu',
                                    constraints: const BoxConstraints(
                                      minWidth: 48,
                                      minHeight: 48,
                                    ),
                                    icon: Icon(
                                      _obscurePass
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                    onPressed: () => setState(
                                      () => _obscurePass = !_obscurePass,
                                    ),
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
                              const SizedBox(height: 14),

                              // 5. Xác nhận mật khẩu
                              TextFormField(
                                controller: _confirmPassCtrl,
                                obscureText: _obscureConfirm,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _register(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                                decoration: _inputDecoration(
                                  label: 'Xác nhận mật khẩu',
                                  hint: 'Nhập lại mật khẩu đã chọn',
                                  prefixIcon: Icons.lock_reset_rounded,
                                  suffix: IconButton(
                                    tooltip: _obscureConfirm
                                        ? 'Hiện mật khẩu xác nhận'
                                        : 'Ẩn mật khẩu xác nhận',
                                    constraints: const BoxConstraints(
                                      minWidth: 48,
                                      minHeight: 48,
                                    ),
                                    icon: Icon(
                                      _obscureConfirm
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                    onPressed: () => setState(
                                      () => _obscureConfirm = !_obscureConfirm,
                                    ),
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
                        ),
                        const SizedBox(height: 20),

                        // Hiển thị lỗi nếu có
                        if (_error != null) ...[
                          Semantics(
                            liveRegion: true,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFF5252,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFF5252,
                                  ).withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    color: Color(0xFFFF5252),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        color: Color(0xFFFF8A80),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        // CTA Button: Đăng ký
                        FilledButton(
                          onPressed: _loading ? null : _register,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF00F5D4),
                            foregroundColor: const Color(0xFF04070D),
                            disabledBackgroundColor: const Color(0xFF334155),
                            disabledForegroundColor: const Color(0xFF64748B),
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Color(0xFF04070D),
                                    semanticsLabel: 'Đang đăng ký',
                                  ),
                                )
                              : const Text(
                                  'Đăng ký',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),

                        // Quay lại đăng nhập
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: RichText(
                            text: const TextSpan(
                              style: TextStyle(fontSize: 14),
                              children: [
                                TextSpan(
                                  text: 'Đã có tài khoản? ',
                                  style: TextStyle(color: Color(0xFF94A3B8)),
                                ),
                                TextSpan(
                                  text: 'Đăng nhập',
                                  style: TextStyle(
                                    color: Color(0xFF00F5D4),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
