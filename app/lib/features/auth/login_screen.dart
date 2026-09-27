import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/auth_attempt_limiter.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_motion.dart';
import 'password_reset_screen.dart';
import 'register_screen.dart';

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
          : (result['error']?.toString() ??
                'Chưa thể đăng nhập. Vui lòng thử lại.');
    });
    await _refreshCooldown();
  }

  Future<void> _openPasswordReset() async {
    await Navigator.of(context).push<void>(
      AppMotion.pageRoute<void>(
        PasswordResetScreen(initialEmail: _emailCtrl.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canSubmit = !_loading && _remaining <= Duration.zero;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: _autofillEnabled
                            ? const [
                                AutofillHints.username,
                                AutofillHints.email,
                              ]
                            : null,
                        onTap: () {
                          if (!_autofillEnabled) {
                            setState(() => _autofillEnabled = true);
                          }
                        },
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
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
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Hiện mật khẩu'
                                : 'Ẩn mật khẩu',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Nhập mật khẩu'
                            : null,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _loading ? null : _openPasswordReset,
                          child: const Text('Quên mật khẩu?'),
                        ),
                      ),
                      if (_error != null) ...[
                        Semantics(
                          liveRegion: true,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                        ),
                      ],
                      FilledButton(
                        onPressed: canSubmit ? _submit : null,
                        child: _loading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _remaining > Duration.zero
                                    ? 'Đợi ${_remaining.inSeconds} giây'
                                    : 'Đăng nhập',
                              ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => Navigator.of(context).push<void>(
                                AppMotion.pageRoute<void>(
                                  const RegisterScreen(),
                                ),
                              ),
                        child: const Text('Chưa có tài khoản? Đăng ký'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
