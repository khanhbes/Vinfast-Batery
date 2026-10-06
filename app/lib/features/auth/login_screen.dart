import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/auth_attempt_limiter.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/cockpit_design_system.dart';
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
          : (_safeLoginMessage(code) ??
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
    final theme = Theme.of(context);
    final canSubmit = !_loading && _remaining <= Duration.zero;

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
                      const Color(0xFF00F5D4).withValues(alpha: 0.16),
                      CockpitColors.emerald.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 2. Nội dung chính: Hero Header + Glassmorphic Form Card
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // --- Hero Section: Logo & Branding ---
                          _buildHeroHeader(theme),
                          const SizedBox(height: 28),

                          // --- Glassmorphic Form Card ---
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 24,
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
                                // Email field
                                TextFormField(
                                  controller: _emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                  ),
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
                                  decoration: InputDecoration(
                                    labelText: 'Email',
                                    labelStyle: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.alternate_email_rounded,
                                      color: Color(0xFF00F5D4),
                                      size: 20,
                                    ),
                                    prefixIconConstraints: const BoxConstraints(
                                      minWidth: 44,
                                      minHeight: 44,
                                    ),
                                    filled: true,
                                    fillColor: const Color(
                                      0xFF132238,
                                    ).withValues(alpha: 0.6),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF00F5D4),
                                        width: 1.8,
                                      ),
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFFF5252),
                                        width: 1.2,
                                      ),
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFFF5252),
                                        width: 1.8,
                                      ),
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
                                const SizedBox(height: 16),

                                // Password field
                                TextFormField(
                                  controller: _passwordCtrl,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  style: const TextStyle(
                                    color: Colors.white,
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
                                  onFieldSubmitted: canSubmit
                                      ? (_) => _submit()
                                      : null,
                                  decoration: InputDecoration(
                                    labelText: 'Mật khẩu',
                                    labelStyle: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      color: Color(0xFF00F5D4),
                                      size: 20,
                                    ),
                                    prefixIconConstraints: const BoxConstraints(
                                      minWidth: 44,
                                      minHeight: 44,
                                    ),
                                    filled: true,
                                    fillColor: const Color(
                                      0xFF132238,
                                    ).withValues(alpha: 0.6),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF00F5D4),
                                        width: 1.8,
                                      ),
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFFF5252),
                                        width: 1.2,
                                      ),
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFFF5252),
                                        width: 1.8,
                                      ),
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
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_rounded
                                            : Icons.visibility_rounded,
                                        color: const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ),
                                  validator: (value) =>
                                      value == null || value.isEmpty
                                      ? 'Nhập mật khẩu'
                                      : null,
                                ),

                                // Quên mật khẩu
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: TextButton(
                                      onPressed: _loading
                                          ? null
                                          : _openPasswordReset,
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFF00F5D4,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                      ),
                                      child: const Text(
                                        'Quên mật khẩu?',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Hiển thị lỗi nếu có
                                if (_error != null) ...[
                                  Semantics(
                                    liveRegion: true,
                                    child: Container(
                                      margin: const EdgeInsets.only(
                                        top: 8,
                                        bottom: 12,
                                      ),
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

                                const SizedBox(height: 8),

                                // Action Button: Đăng nhập
                                FilledButton(
                                  onPressed: canSubmit ? _submit : null,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF00F5D4),
                                    foregroundColor: const Color(0xFF04070D),
                                    disabledBackgroundColor: const Color(
                                      0xFF334155,
                                    ),
                                    disabledForegroundColor: const Color(
                                      0xFF64748B,
                                    ),
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
                                          ),
                                        )
                                      : Text(
                                          _remaining > Duration.zero
                                              ? 'Đợi ${_remaining.inSeconds} giây'
                                              : 'Đăng nhập',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Chuyển trang Đăng ký
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => Navigator.of(context).push<void>(
                                    AppMotion.pageRoute<void>(
                                      const RegisterScreen(),
                                    ),
                                  ),
                            style: TextButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: const Text.rich(
                              TextSpan(
                                style: TextStyle(fontSize: 14),
                                children: [
                                  TextSpan(
                                    text: 'Chưa có tài khoản? ',
                                    style: TextStyle(color: Color(0xFF94A3B8)),
                                  ),
                                  TextSpan(
                                    text: 'Đăng ký ngay',
                                    style: TextStyle(
                                      color: Color(0xFF00F5D4),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
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

  /// Compact brand header: keep the fields and primary action prominent.
  Widget _buildHeroHeader(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 56,
          child: ClipOval(
            child: Image.asset(
              'assets/icons/app_icon.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Brand Title
        Text(
          'VinFast Battery',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),

        Text(
          'Đăng nhập để quản lý pin và sạc xe.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF94A3B8),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
