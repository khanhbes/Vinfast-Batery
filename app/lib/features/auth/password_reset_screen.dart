import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/auth_service.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  static const _cooldownKey = 'auth.password_reset_until_ms';
  late final TextEditingController _emailController;
  bool _sending = false;
  bool _sent = false;
  int _cooldownSeconds = 0;
  String? _error;
  Timer? _timer;
  int? _cooldownUntilMs;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
    _restoreCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || _cooldownSeconds > 0) return;
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Nhập địa chỉ email hợp lệ.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final result = await AuthService().resetPassword(email);
    if (!mounted) return;
    setState(() => _sending = false);
    if (result['success'] == true) {
      setState(() {
        _sent = true;
      });
      final until = DateTime.now().add(const Duration(seconds: 60));
      _cooldownUntilMs = until.millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_cooldownKey, _cooldownUntilMs!);
      _startCooldownTimer();
    } else {
      setState(() => _error = _safeResetMessage(result['code']?.toString()));
    }
  }

  String _safeResetMessage(String? code) {
    if (code == 'too-many-requests') {
      return 'Yêu cầu đang được giới hạn. Hãy đợi một chút rồi thử lại.';
    }
    return 'Chưa thể gửi email lúc này. Kiểm tra kết nối rồi thử lại.';
  }

  Future<void> _restoreCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    _cooldownUntilMs = prefs.getInt(_cooldownKey);
    _startCooldownTimer();
  }

  void _startCooldownTimer() {
    _timer?.cancel();
    void refresh() {
      final until = _cooldownUntilMs;
      final seconds = until == null
          ? 0
          : ((until - DateTime.now().millisecondsSinceEpoch) / 1000)
                .ceil()
                .clamp(0, 60);
      if (!mounted) return;
      setState(() => _cooldownSeconds = seconds);
      if (seconds == 0) _timer?.cancel();
    }

    refresh();
    if (_cooldownSeconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Đặt lại mật khẩu')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Nhập email để nhận hướng dẫn đặt lại mật khẩu.',
                    style: TextStyle(fontSize: 16, height: 1.45),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailController,
                    enabled: !_sending,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  ],
                  if (_sent) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Đã ghi nhận yêu cầu. Hãy kiểm tra hộp thư đến và thư rác.',
                      style: TextStyle(height: 1.45),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _sending || _cooldownSeconds > 0 ? null : _send,
                    child: _sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _cooldownSeconds > 0
                                ? 'Gửi lại sau $_cooldownSeconds giây'
                                : _sent
                                ? 'Gửi lại email'
                                : 'Gửi hướng dẫn',
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
