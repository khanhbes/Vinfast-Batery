import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/luxe_kit.dart';
import 'widgets/luxe_auth_widgets.dart';

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
    final canPop = Navigator.of(context).canPop();
    return LuxeAuthScaffold(
      leading: canPop
          ? LuxeCircleButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Quay lại',
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      children: [
        const LuxeAuthHeading(
          eyebrow: 'Khôi phục',
          title: 'Đặt lại mật khẩu',
          center: false,
        ),
        const SizedBox(height: 10),
        const LuxeReveal(
          index: 2,
          child: Text(
            'Nhập email để nhận hướng dẫn đặt lại mật khẩu.',
            style: TextStyle(
              color: LuxeColors.muted,
              fontSize: 15,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 22),
        LuxeAuthCard(
          children: [
            TextField(
              controller: _emailController,
              enabled: !_sending,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              style: const TextStyle(color: LuxeColors.text, fontSize: 15),
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
              ),
              onSubmitted: (_) => _send(),
            ),
            AnimatedSize(
              duration: luxeDuration(context, 280),
              curve: LuxeMotion.enter,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    LuxeAuthError(_error!),
                  ],
                  if (_sent) ...[
                    const SizedBox(height: 14),
                    const _SentNotice(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _sending || _cooldownSeconds > 0 ? null : _send,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              child: _sending
                  ? const LuxeButtonSpinner()
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
      ],
    );
  }
}

/// Confirmation: an emerald check that draws itself once, then the copy.
class _SentNotice extends StatelessWidget {
  const _SentNotice();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: LuxeColors.emerald.withValues(alpha: 0.07),
        border: Border.all(color: LuxeColors.emerald.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: SizedBox.square(
              dimension: 22,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: luxeDuration(context, 700),
                curve: LuxeMotion.enter,
                builder: (context, t, _) =>
                    CustomPaint(painter: _CheckPainter(t)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Đã ghi nhận yêu cầu. Hãy kiểm tra hộp thư đến và thư rác.',
              style: TextStyle(
                color: LuxeColors.text,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      size.width / 2 - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = LuxeColors.emerald.withValues(alpha: 0.5 * t),
    );
    final path = Path()
      ..moveTo(size.width * 0.28, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.67)
      ..lineTo(size.width * 0.73, size.height * 0.36);
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = LuxeColors.emerald,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}
