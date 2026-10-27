import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/auth_attempt_limiter.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/luxe_kit.dart';
import 'password_reset_screen.dart';
import 'register_screen.dart';
import 'widgets/luxe_auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _limiter = AuthAttemptLimiter();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _autofillEnabled = false;
  Duration _remaining = Duration.zero;
  Timer? _cooldownTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshCooldown() async {
    final remaining = await _limiter.remaining();
    if (!mounted) return;
    setState(() => _remaining = remaining);
    _cooldownTimer?.cancel();
    if (remaining > Duration.zero) {
      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        final next = await _limiter.remaining();
        if (!mounted) return;
        setState(() => _remaining = next);
        if (next <= Duration.zero) _cooldownTimer?.cancel();
      });
    }
  }

  Future<void> _submit() async {
    if (_loading || _remaining > Duration.zero) return;
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await AuthService().login(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );

    if (!mounted) return;
    if (result['success'] == true) {
      TextInput.finishAutofillContext(shouldSave: true);
      await _limiter.reset();
      setState(() => _loading = false);
      return;
    }

    final code = result['code']?.toString();
    if (code == 'invalid-credential' ||
        code == 'wrong-password' ||
        code == 'user-not-found') {
      _remaining = await _limiter.recordInvalidCredential();
    } else if (code == 'too-many-requests') {
      await _limiter.applyCooldown(const Duration(seconds: 60));
      _remaining = await _limiter.remaining();
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = _remaining > Duration.zero
          ? 'Bạn đã thử nhiều lần. Vui lòng đợi ${_remaining.inSeconds} giây.'
          : (_safeLoginMessage(code) ??
                'Chưa thể đăng nhập. Vui lòng thử lại.');
    });
    await _refreshCooldown();
  }

  Future<void> _openPasswordReset() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            PasswordResetScreen(initialEmail: _emailCtrl.text.trim()),
      ),
    );
  }

  String? _safeLoginMessage(String? code) {
    switch (code) {
      case 'invalid-email':
        return 'Email chưa đúng định dạng.';
      case 'user-disabled':
        return 'Tài khoản hiện không thể đăng nhập. Hãy liên hệ hỗ trợ.';
      case 'too-many-requests':
        return 'Yêu cầu đăng nhập đang bị giới hạn. Hãy thử lại sau.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Email hoặc mật khẩu chưa chính xác.';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_loading && _remaining <= Duration.zero;

    return LuxeAuthScaffold(
      children: [
        AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LuxeAuthEmblem(),
                const SizedBox(height: 18),
                const LuxeAuthHeading(
                  eyebrow: 'Pinova',
                  title: 'Chào mừng trở lại',
                  caption: 'Đăng nhập để quản lý pin và sạc xe.',
                ),
                const SizedBox(height: 26),
                LuxeAuthCard(
                  children: [
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(
                        color: LuxeColors.text,
                        fontSize: 15,
                      ),
                      autofillHints: _autofillEnabled
                          ? const [AutofillHints.username, AutofillHints.email]
                          : null,
                      onTap: () {
                        if (!_autofillEnabled) {
                          setState(() => _autofillEnabled = true);
                        }
                      },
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(
                          Icons.alternate_email_rounded,
                          size: 20,
                        ),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return 'Nhập email';
                        if (!RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(email)) {
                          return 'Email chưa đúng định dạng';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(
                        color: LuxeColors.text,
                        fontSize: 15,
                      ),
                      autofillHints: _autofillEnabled
                          ? const [AutofillHints.password]
                          : null,
                      onTap: () {
                        if (!_autofillEnabled) {
                          setState(() => _autofillEnabled = true);
                        }
                      },
                      onFieldSubmitted: canSubmit ? (_) => _submit() : null,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu',
                        prefixIcon: const Icon(
                          Icons.lock_outline_rounded,
                          size: 20,
                        ),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Hiện mật khẩu'
                              : 'Ẩn mật khẩu',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: LuxeColors.platinumMid,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Nhập mật khẩu'
                          : null,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TextButton(
                          onPressed: _loading ? null : _openPasswordReset,
                          style: TextButton.styleFrom(
                            foregroundColor: LuxeColors.platinum,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text(
                            'Quên mật khẩu?',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: luxeDuration(context, 280),
                      curve: LuxeMotion.enter,
                      alignment: Alignment.topCenter,
                      child: _error == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(
                                top: 4,
                                bottom: 12,
                              ),
                              child: LuxeAuthError(_error!),
                            ),
                    ),
                    const SizedBox(height: 6),
                    FilledButton(
                      onPressed: canSubmit ? _submit : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      child: _loading
                          ? const LuxeButtonSpinner()
                          : Text(
                              _remaining > Duration.zero
                                  ? 'Đợi ${_remaining.inSeconds} giây'
                                  : 'Đăng nhập',
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LuxeReveal(
                  index: 4,
                  child: LuxeAuthLink(
                    prefix: 'Chưa có tài khoản? ',
                    action: 'Đăng ký ngay',
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => const RegisterScreen(),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
