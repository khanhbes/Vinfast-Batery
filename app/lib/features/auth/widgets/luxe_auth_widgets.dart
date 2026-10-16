import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/widgets/luxe_kit.dart';

/// LUXE auth kit (Task 118): Login, Register and Password reset continue the
/// splash → Getting started language — dark backdrop, platinum emblem, one
/// glass form card and a platinum primary pill. Purely presentational.

/// Frame for auth screens. Always LUXE (it does not inherit the host theme)
/// and scrolls so large text and the keyboard never clip the form.
class LuxeAuthScaffold extends StatelessWidget {
  const LuxeAuthScaffold({super.key, required this.children, this.leading});

  final List<Widget> children;

  /// Optional top-left control (e.g. back button), outside the centred form.
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Theme(
    data: LuxeTheme.of(context),
    child: Scaffold(
      backgroundColor: LuxeColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LuxeBackdrop(drift: 0.12),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (leading != null) ...[
                        Align(alignment: Alignment.centerLeft, child: leading),
                        const SizedBox(height: 12),
                      ],
                      ...children,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// App icon set in a brushed-platinum ring whose rim draws in once, with a
/// single emerald glint settling at the top.
class LuxeAuthEmblem extends StatelessWidget {
  const LuxeAuthEmblem({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: luxeDuration(context, 1200),
          curve: LuxeMotion.enter,
          builder: (context, t, child) => CustomPaint(
            foregroundPainter: _EmblemRimPainter(t),
            child: child,
          ),
          child: Padding(
            padding: EdgeInsets.all(size * 0.1),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33FFFFFF),
                    blurRadius: 24,
                    spreadRadius: -8,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/icons/app_icon.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: LuxeColors.raised,
                    child: Icon(Icons.bolt_rounded, color: LuxeColors.emerald),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _EmblemRimPainter extends CustomPainter {
  _EmblemRimPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * t,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = const SweepGradient(
          colors: [
            LuxeColors.platinumLow,
            LuxeColors.platinumHi,
            LuxeColors.platinumMid,
            LuxeColors.platinumLow,
          ],
        ).createShader(rect),
    );
    final a = -math.pi / 2 + math.pi * 2 * t;
    final p = rect.center + Offset(math.cos(a), math.sin(a)) * (rect.width / 2);
    canvas.drawCircle(
      p,
      5,
      Paint()
        ..color = LuxeColors.emerald.withValues(alpha: 0.35 * t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      p,
      2,
      Paint()..color = LuxeColors.emerald.withValues(alpha: t),
    );
  }

  @override
  bool shouldRepaint(_EmblemRimPainter old) => old.t != t;
}

/// Eyebrow + platinum title + caption, revealed in sequence.
class LuxeAuthHeading extends StatelessWidget {
  const LuxeAuthHeading({
    super.key,
    required this.title,
    this.eyebrow,
    this.caption,
    this.center = true,
  });

  final String title;
  final String? eyebrow;
  final String? caption;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final align = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        if (eyebrow != null)
          LuxeReveal(
            child: Text(
              eyebrow!.toUpperCase(),
              textAlign: align,
              style: LuxeText.eyebrow,
            ),
          ),
        const SizedBox(height: 8),
        LuxeReveal(
          index: 1,
          child: LuxeMetalText(
            title,
            style: LuxeText.title.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w300,
              letterSpacing: -0.6,
            ),
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 8),
          LuxeReveal(
            index: 2,
            child: Text(caption!, textAlign: align, style: LuxeText.body),
          ),
        ],
      ],
    );
  }
}

/// Glass card holding the form fields.
class LuxeAuthCard extends StatelessWidget {
  const LuxeAuthCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LuxeReveal(
    index: 3,
    child: LuxeGlass(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

/// Inline error in quiet rose. Each new message shakes the strip once.
class LuxeAuthError extends StatelessWidget {
  const LuxeAuthError(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: TweenAnimationBuilder<double>(
      key: ValueKey(message),
      tween: Tween(begin: 0, end: 1),
      duration: luxeDuration(context, 480),
      builder: (context, t, child) => Transform.translate(
        offset: Offset(math.sin(t * math.pi * 6) * 6 * (1 - t), 0),
        child: child,
      ),
      child: LuxeNotice(
        message: message,
        icon: Icons.error_outline_rounded,
        color: LuxeColors.danger,
      ),
    ),
  );
}

/// "Prefix? Action" link row (e.g. "Chưa có tài khoản? Đăng ký ngay").
class LuxeAuthLink extends StatelessWidget {
  const LuxeAuthLink({
    super.key,
    required this.prefix,
    required this.action,
    required this.onPressed,
  });

  final String prefix;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    child: Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 14),
        children: [
          TextSpan(
            text: prefix,
            style: const TextStyle(color: LuxeColors.muted),
          ),
          TextSpan(
            text: action,
            style: const TextStyle(
              color: LuxeColors.emerald,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    ),
  );
}

/// Spinner sized for the platinum primary pill.
class LuxeButtonSpinner extends StatelessWidget {
  const LuxeButtonSpinner({super.key, this.semanticsLabel});
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 22,
    child: CircularProgressIndicator(
      strokeWidth: 2.2,
      color: const Color(0xFF0B0C0E),
      semanticsLabel: semanticsLabel,
    ),
  );
}

/// Four hairline segments that light up with password strength. Advisory
/// only — validation rules stay in the form.
class LuxePasswordStrength extends StatelessWidget {
  const LuxePasswordStrength({super.key, required this.password});
  final String password;

  static int score(String p) {
    if (p.isEmpty) return 0;
    var s = 0;
    if (p.length >= 6) s++;
    if (p.length >= 10) s++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) s++;
    if (RegExp(r'\d').hasMatch(p) && RegExp(r'[^A-Za-z0-9]').hasMatch(p)) {
      s++;
    }
    return s.clamp(1, 4);
  }

  @override
  Widget build(BuildContext context) {
    final s = score(password);
    const labels = ['', 'Yếu', 'Khá', 'Tốt', 'Rất mạnh'];
    final color = switch (s) {
      <= 1 => LuxeColors.danger,
      2 => LuxeColors.champagne,
      _ => LuxeColors.emerald,
    };
    final d = luxeDuration(context, 320);
    return Semantics(
      label: s == 0 ? null : 'Độ mạnh mật khẩu: ${labels[s]}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
        child: Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Expanded(
                child: AnimatedContainer(
                  duration: d,
                  curve: LuxeMotion.enter,
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: i < s ? color : const Color(0x1FFFFFFF),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 10),
            SizedBox(
              width: 62,
              child: AnimatedSwitcher(
                duration: d,
                child: Text(
                  labels[s],
                  key: ValueKey(s),
                  textAlign: TextAlign.end,
                  style: LuxeText.label.copyWith(fontSize: 11.5, color: color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
