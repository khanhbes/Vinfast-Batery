import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../../core/widgets/app_popup.dart';
import 'register_screen.dart';

/// Login Screen — PLAN #3 (enhanced)
/// - Uses AuthService for persistent login
/// - Navigate to RegisterScreen
/// - Forgot password support
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await AuthService().login(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      AppPopup.showSuccess('Đăng nhập thành công');
    } else {
      final msg = result['error'] ?? 'Đăng nhập thất bại';
      setState(() => _error = msg);
      AppPopup.showError(msg);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      AppPopup.showError('Vui lòng nhập email trước');
      return;
    }
    final result = await AuthService().resetPassword(email);
    if (!mounted) return;
    if (result['success'] == true) {
      AppPopup.showSuccess('Email đặt lại mật khẩu đã được gửi');
    } else {
      AppPopup.showError(result['error'] ?? 'Không gửi được email');
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.error.withAlpha(153)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo with gradient glow
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary.withAlpha(40),
                          AppColors.primaryContainer.withAlpha(60),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: AppColors.primary.withAlpha(51),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withAlpha(20),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.electric_bolt_rounded,
                      color: AppColors.primary,
                      size: 38,
                    ),
                  ).animate().fadeIn(duration: 500.ms).scale(
                        begin: const Offset(0.7, 0.7),
                        curve: Curves.easeOutBack,
                      ),
                  const SizedBox(height: 20),

                  const Text(
                    'VinFast Battery',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ).animate().fadeIn(delay: 100.ms),
                  const SizedBox(height: 6),
                  Text(
                    'Đăng nhập để tiếp tục',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ).animate().fadeIn(delay: 150.ms),
                  const SizedBox(height: 36),

                  // Error banner
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.error.withAlpha(77)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: AppColors.error, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: AppColors.error, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn().shake(hz: 3, offset: const Offset(4, 0)),
                    const SizedBox(height: 16),
                  ],

                  // Email
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    decoration: _inputDecoration(
                      label: 'Email',
                      icon: Icons.email_outlined,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Nhập email';
                      if (!v.contains('@')) return 'Email không hợp lệ';
                      return null;
                    },
                  ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.05),
                  const SizedBox(height: 14),

                  // Password
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    decoration: _inputDecoration(
                      label: 'Mật khẩu',
                      icon: Icons.lock_outlined,
                      suffix: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Nhập mật khẩu';
                      if (v.length < 6) return 'Tối thiểu 6 ký tự';
                      return null;
                    },
                  ).animate().fadeIn(delay: 250.ms).slideX(begin: -0.05),

                  // Forgot password
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      child: Text(
                        'Quên mật khẩu?',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 280.ms),
                  const SizedBox(height: 8),

                  // Login Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.background,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation(AppColors.background),
                              ),
                            )
                          : const Text(
                              'Đăng nhập',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
                  const SizedBox(height: 20),

                  // Register link
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RegisterScreen()),
                      );
                    },
                    child: RichText(
                      text: TextSpan(
                        text: 'Chưa có tài khoản? ',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        children: [
                          TextSpan(
                            text: 'Đăng ký ngay',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(delay: 350.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
