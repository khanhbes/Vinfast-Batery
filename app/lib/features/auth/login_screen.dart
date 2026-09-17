import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/cockpit_design_system.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/ev_energy_animations.dart';
import 'register_screen.dart';

/// Login Screen — Cockpit Design System Edition
/// Minimalist EV battery theme, no generic icons, custom 2D energy animations.
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
    HapticFeedback.lightImpact();
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
    String? hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: CockpitTypography.label(
        fontSize: 13,
        color: CockpitColors.muted,
      ),
      hintText: hint,
      hintStyle: CockpitTypography.body(
        fontSize: 13,
        color: CockpitColors.dim,
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: CockpitColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CockpitRadius.small),
        borderSide: const BorderSide(color: CockpitColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CockpitRadius.small),
        borderSide: const BorderSide(color: CockpitColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CockpitRadius.small),
        borderSide: const BorderSide(
          color: CockpitColors.emeraldStrong,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CockpitRadius.small),
        borderSide: BorderSide(
          color: CockpitColors.danger.withValues(alpha: 0.6),
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CockpitRadius.small),
        borderSide: const BorderSide(
          color: CockpitColors.danger,
          width: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CockpitColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated Energy Orb Header (Replaces static icon)
                  const EvEnergyOrb(
                    size: 80,
                    showParticles: true,
                  ).appScalePop(),
                  const SizedBox(height: 20),

                  Text(
                    'EV Battery',
                    style: CockpitTypography.heading(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: CockpitColors.text,
                      letterSpacing: 0.5,
                    ),
                  ).appFadeSlideIn(index: 1),
                  const SizedBox(height: 6),
                  Text(
                    'Hệ thống quản lý năng lượng xe điện thông minh',
                    textAlign: TextAlign.center,
                    style: CockpitTypography.body(
                      fontSize: 13,
                      color: CockpitColors.muted,
                    ),
                  ).appFadeSlideIn(index: 1),

                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 120,
                    child: EvGlowLine(height: 1.2),
                  ).appFadeSlideIn(index: 1),
                  const SizedBox(height: 28),

                  // Error banner
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: CockpitColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(CockpitRadius.small),
                        border: Border.all(
                          color: CockpitColors.danger.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: CockpitTypography.body(
                          fontSize: 12.5,
                          color: CockpitColors.danger,
                        ),
                      ),
                    ).appFadeSlideIn(slide: 0),
                    const SizedBox(height: 16),
                  ],

                  // Email Input
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: CockpitTypography.body(
                      fontSize: 14,
                      color: CockpitColors.text,
                    ),
                    decoration: _inputDecoration(
                      label: 'Email',
                      hint: 'name@example.com',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Nhập email';
                      if (!v.contains('@')) return 'Email không hợp lệ';
                      return null;
                    },
                  ).appFadeSlideIn(index: 2),
                  const SizedBox(height: 14),

                  // Password Input
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    style: CockpitTypography.body(
                      fontSize: 14,
                      color: CockpitColors.text,
                    ),
                    decoration: _inputDecoration(
                      label: 'Mật khẩu',
                      hint: 'Tối thiểu 6 ký tự',
                      suffix: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: CockpitColors.muted,
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
                  ).appFadeSlideIn(index: 2),

                  // Forgot password
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      child: Text(
                        'Quên mật khẩu?',
                        style: CockpitTypography.label(
                          fontSize: 12.5,
                          color: CockpitColors.emeraldStrong,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ).appFadeSlideIn(index: 2),
                  const SizedBox(height: 12),

                  // Submit Button with EvChargingWave on loading
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: double.infinity,
                      minHeight: 50,
                    ),
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CockpitColors.emeraldStrong,
                        foregroundColor: CockpitColors.background,
                        disabledBackgroundColor:
                            CockpitColors.emeraldStrong.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(CockpitRadius.small),
                        ),
                        elevation: 0,
                      ),
                      child: _loading
                          ? const Center(
                              child: EvChargingWave(
                                width: 56,
                                height: 14,
                                color: CockpitColors.background,
                              ),
                            )
                          : Text(
                              'Đăng nhập',
                              style: CockpitTypography.heading(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: CockpitColors.background,
                              ),
                            ),
                    ),
                  ).appTactile(enabled: !_loading).appFadeSlideIn(index: 3),
                  const SizedBox(height: 24),

                  // Register link with subtle separator
                  const EvGlowLine(height: 1.0).appFadeSlideIn(index: 3),
                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      );
                    },
                    child: RichText(
                      textScaler: MediaQuery.textScalerOf(context),
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        text: 'Chưa có tài khoản? ',
                        style: CockpitTypography.body(
                          fontSize: 13,
                          color: CockpitColors.muted,
                        ),
                        children: [
                          TextSpan(
                            text: 'Đăng ký ngay',
                            style: CockpitTypography.body(
                              fontSize: 13,
                              color: CockpitColors.emeraldStrong,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).appFadeSlideIn(index: 3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
