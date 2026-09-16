import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/cockpit_design_system.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/ev_energy_animations.dart';

/// Professional Registration Screen — Cockpit Design System Edition
/// Captures: Full Name, Email, Phone Number, Password
/// Minimalist EV battery theme, no generic icons, custom 2D energy animations.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(
    text: kDebugMode ? 'Le Hoang EV' : '',
  );
  late final _emailCtrl = TextEditingController(
    text: kDebugMode
        ? 'lehoang.${DateTime.now().millisecondsSinceEpoch % 10000}@vinfast.test'
        : '',
  );
  late final _phoneCtrl = TextEditingController(
    text: kDebugMode ? '0912345678' : '',
  );
  late final _passCtrl = TextEditingController(
    text: kDebugMode ? 'VinFast2026@' : '',
  );
  late final _confirmPassCtrl = TextEditingController(
    text: kDebugMode ? 'VinFast2026@' : '',
  );
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
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await AuthService().register(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
    );

    if (!mounted) return;

    setState(() => _loading = false);

    if (result['success'] == true) {
      AppPopup.showSuccess('Đăng ký thành công!');
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      final msg = result['error'] ?? 'Đăng ký thất bại';
      setState(() => _error = msg);
      AppPopup.showError(msg);
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
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
                  const SizedBox(height: 12),
                  // Back button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: CockpitColors.surface,
                          borderRadius:
                              BorderRadius.circular(CockpitRadius.small),
                          border: Border.all(color: CockpitColors.border),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: CockpitColors.text,
                          size: 18,
                        ),
                      ),
                    ),
                  ).appFadeSlideIn(index: 0),
                  const SizedBox(height: 16),

                  // Header Orb
                  const EvEnergyOrb(
                    size: 72,
                    showParticles: true,
                  ).appScalePop(),
                  const SizedBox(height: 16),

                  Text(
                    'Tạo tài khoản',
                    style: CockpitTypography.heading(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: CockpitColors.text,
                      letterSpacing: 0.5,
                    ),
                  ).appFadeSlideIn(index: 1),
                  const SizedBox(height: 6),
                  Text(
                    'Nhập thông tin để bắt đầu quản lý pin xe điện',
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
                  const SizedBox(height: 24),

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
                        borderRadius:
                            BorderRadius.circular(CockpitRadius.small),
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

                  // Full Name
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    style: CockpitTypography.body(
                      fontSize: 14,
                      color: CockpitColors.text,
                    ),
                    decoration: _inputDecoration(
                      label: 'Họ và Tên',
                      hint: 'Ví dụ: Nguyễn Văn A',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Vui lòng nhập họ tên';
                      }
                      if (v.trim().length < 2) return 'Họ tên quá ngắn';
                      return null;
                    },
                  ).appFadeSlideIn(index: 2),
                  const SizedBox(height: 14),

                  // Email
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
                      if (v == null || v.trim().isEmpty) {
                        return 'Vui lòng nhập email';
                      }
                      if (!v.contains('@') || !v.contains('.')) {
                        return 'Email không hợp lệ';
                      }
                      return null;
                    },
                  ).appFadeSlideIn(index: 2),
                  const SizedBox(height: 14),

                  // Phone Number
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: CockpitTypography.body(
                      fontSize: 14,
                      color: CockpitColors.text,
                    ),
                    decoration: _inputDecoration(
                      label: 'Số điện thoại',
                      hint: '09xxxxxxxx',
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
                  ).appFadeSlideIn(index: 3),
                  const SizedBox(height: 14),

                  // Password
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscurePass,
                    style: CockpitTypography.body(
                      fontSize: 14,
                      color: CockpitColors.text,
                    ),
                    decoration: _inputDecoration(
                      label: 'Mật khẩu',
                      hint: 'Tối thiểu 6 ký tự',
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePass
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: CockpitColors.muted,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Vui lòng nhập mật khẩu';
                      }
                      if (v.length < 6) return 'Mật khẩu tối thiểu 6 ký tự';
                      return null;
                    },
                  ).appFadeSlideIn(index: 3),
                  const SizedBox(height: 14),

                  // Confirm Password
                  TextFormField(
                    controller: _confirmPassCtrl,
                    obscureText: _obscureConfirm,
                    style: CockpitTypography.body(
                      fontSize: 14,
                      color: CockpitColors.text,
                    ),
                    decoration: _inputDecoration(
                      label: 'Xác nhận mật khẩu',
                      hint: 'Nhập lại mật khẩu đã chọn',
                      suffix: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: CockpitColors.muted,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Vui lòng xác nhận mật khẩu';
                      }
                      if (v != _passCtrl.text) return 'Mật khẩu không khớp';
                      return null;
                    },
                  ).appFadeSlideIn(index: 4),
                  const SizedBox(height: 24),

                  // Register Button with EvChargingWave on loading
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: double.infinity,
                      minHeight: 50,
                    ),
                    child: ElevatedButton(
                      onPressed: _loading ? null : _register,
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
                              'Đăng ký',
                              style: CockpitTypography.heading(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: CockpitColors.background,
                              ),
                            ),
                    ),
                  ).appFadeSlideIn(index: 4),
                  const SizedBox(height: 20),

                  // Back to login with separator
                  const EvGlowLine(height: 1.0).appFadeSlideIn(index: 5),
                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: RichText(
                      text: TextSpan(
                        text: 'Đã có tài khoản? ',
                        style: CockpitTypography.body(
                          fontSize: 13,
                          color: CockpitColors.muted,
                        ),
                        children: [
                          TextSpan(
                            text: 'Đăng nhập',
                            style: CockpitTypography.body(
                              fontSize: 13,
                              color: CockpitColors.emeraldStrong,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).appFadeSlideIn(index: 5),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
