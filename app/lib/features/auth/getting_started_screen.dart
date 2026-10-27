import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/battery_bot_mascot.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// First-run flag. The intro shows once per install, before sign-in.
abstract final class GettingStartedPrefs {
  static const key = 'getting_started_seen_v1';
  static Future<bool>? _seen;

  /// Last resolved value, so a warm entry can build without a blank frame.
  static bool? cached;

  static Future<bool> seen() => _seen ??= () async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return cached = prefs.getBool(key) ?? false;
    } on Object {
      // Never trap a returning user behind the intro if storage fails.
      return cached = true;
    }
  }();

  @visibleForTesting
  static void debugReset() {
    _seen = null;
    cached = null;
  }

  static Future<void> markSeen() async {
    cached = true;
    _seen = Future.value(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, true);
    } on Object {
      // Best effort: the intro is skippable either way.
    }
  }
}

/// Signed-out root: Getting started on first run, otherwise Login.
class SignedOutEntry extends StatefulWidget {
  const SignedOutEntry({super.key});

  @override
  State<SignedOutEntry> createState() => _SignedOutEntryState();
}

class _SignedOutEntryState extends State<SignedOutEntry> {
  bool? _intro;

  @override
  void initState() {
    super.initState();
    final cached = GettingStartedPrefs.cached;
    _intro = cached == null ? null : !cached;
    if (cached == null) {
      unawaited(
        GettingStartedPrefs.seen().then((seen) {
          if (mounted) setState(() => _intro = !seen);
        }),
      );
    }
  }

  void _finish({required bool register}) {
    unawaited(GettingStartedPrefs.markSeen());
    setState(() => _intro = false);
    if (!register) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const RegisterScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final intro = _intro;
    return AnimatedSwitcher(
      duration: AppMotion.durationFor(
        context,
        const Duration(milliseconds: 520),
      ),
      switchInCurve: LuxeMotion.enter,
      switchOutCurve: Curves.easeInCubic,
      child: intro == null
          ? const ColoredBox(
              key: ValueKey('entry-wait'),
              color: LuxeColors.background,
              child: SizedBox.expand(),
            )
          : intro
          ? GettingStartedScreen(
              key: const ValueKey('entry-intro'),
              onCreateAccount: () => _finish(register: true),
              onSignIn: () => _finish(register: false),
            )
          : const LoginScreen(key: ValueKey('entry-login')),
    );
  }
}

class _IntroPage {
  const _IntroPage(this.eyebrow, this.lead, this.emphasis, this.body);
  final String eyebrow;
  final String lead;
  final String emphasis;
  final String body;
}

const _pages = [
  _IntroPage(
    '01 · THEO DÕI PIN',
    'Hiểu rõ',
    'viên pin của bạn',
    'Mức pin, sức khỏe pin và quãng đường còn lại của từng xe, rõ ràng trong một chạm.',
  ),
  _IntroPage(
    '02 · SẠC THÔNG MINH',
    'Sạc thông minh,',
    'có bảo vệ an toàn',
    'Kết nối ổ cắm Shelly để hẹn giờ sạc. Rơ-le tự ngắt theo bộ đếm phần cứng, kể cả khi điện thoại mất mạng.',
  ),
  _IntroPage(
    '03 · BATTERYBOT',
    'Trợ lý',
    'luôn bên cạnh',
    'Hỏi về pin, nhận nhắc bảo dưỡng. Mọi lệnh bật hay tắt sạc đều chờ bạn xác nhận.',
  ),
];

/// Getting started: three swipeable pages with animated 2D illustrations.
class GettingStartedScreen extends StatefulWidget {
  const GettingStartedScreen({
    super.key,
    required this.onCreateAccount,
    required this.onSignIn,
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;

  @override
  State<GettingStartedScreen> createState() => _GettingStartedScreenState();
}

class _GettingStartedScreenState extends State<GettingStartedScreen>
    with TickerProviderStateMixin {
  final _pager = PageController();
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );
  late final List<AnimationController> _enter = List.generate(
    _pages.length,
    (_) => AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    ),
  );
  int _index = 0;
  bool _reduced = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _pager.addListener(_startVisibleEntrances);
  }

  /// A page starts its entrance as soon as it peeks in during a swipe, so the
  /// incoming page is never blank under the finger.
  void _startVisibleEntrances() {
    if (_reduced) return;
    final page = _page;
    for (var i = 0; i < _enter.length; i++) {
      if ((page - i).abs() < 0.85 && _enter[i].isDismissed) _enter[i].forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (_started && reduced == _reduced) return;
    _started = true;
    _reduced = reduced;
    if (reduced) {
      _loop.stop();
      _drift.stop();
      for (final c in _enter) {
        c.value = 1;
      }
    } else {
      // QA 139 (QA-13): one pass when shown; no endless decorative loop.
      _loop.forward();
      _drift.forward();
      _enter[_index].forward();
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    _loop.dispose();
    _drift.dispose();
    for (final c in _enter) {
      c.dispose();
    }
    super.dispose();
  }

  void _onPageChanged(int index) {
    HapticFeedback.selectionClick();
    setState(() => _index = index);
    if (!_reduced) _enter[index].forward();
  }

  void _goTo(int index) {
    if (_reduced) {
      _pager.jumpToPage(index);
    } else {
      _pager.animateToPage(
        index,
        duration: const Duration(milliseconds: 620),
        curve: const Cubic(0.65, 0.0, 0.35, 1.0),
      );
    }
  }

  double get _page => _pager.hasClients && _pager.position.haveDimensions
      ? _pager.page ?? _index.toDouble()
      : _index.toDouble();

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return Theme(
      data: LuxeTheme.of(context),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: LuxeColors.background,
        ),
        child: Scaffold(
          backgroundColor: LuxeColors.background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: _drift,
                builder: (context, _) => LuxeBackdrop(drift: _drift.value),
              ),
              SafeArea(
                child: Column(
                  children: [
                    _topBar(last),
                    Expanded(
                      child: PageView.builder(
                        controller: _pager,
                        itemCount: _pages.length,
                        onPageChanged: _onPageChanged,
                        itemBuilder: (context, i) => _pageBody(i),
                      ),
                    ),
                    _bottomBar(last),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(bool last) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
    child: SizedBox(
      height: 48,
      child: Row(
        children: [
          const Expanded(
            child: LuxeReveal(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: LuxeMetalText(
                    'PINOVA',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 3.6,
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: last ? 0 : 1,
            duration: AppMotion.durationFor(context, AppMotion.base),
            child: IgnorePointer(
              ignoring: last,
              child: TextButton(
                onPressed: () => _goTo(_pages.length - 1),
                child: const Text('Bỏ qua'),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _pageBody(int i) {
    final page = _pages[i];
    return LayoutBuilder(
      builder: (context, constraints) {
        final art = math.min(
          constraints.maxWidth - 64,
          (constraints.maxHeight * 0.56).clamp(150.0, 330.0),
        );
        return AnimatedBuilder(
          animation: Listenable.merge([_pager, _loop, _enter[i]]),
          builder: (context, _) {
            final delta = (_page - i).clamp(-1.0, 1.0);
            final visibility = 1 - delta.abs();
            final e = _enter[i].value;
            double phase(double a, double b) =>
                LuxeMotion.enter.transform(((e - a) / (b - a)).clamp(0.0, 1.0));
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Illustration drifts further than the copy (parallax).
                    Transform.translate(
                      offset: Offset(-delta * 90, 0),
                      child: Opacity(
                        opacity: (0.25 + 0.75 * visibility).clamp(0.0, 1.0),
                        child: SizedBox.square(
                          dimension: art,
                          child: _illustration(i, e, _loop.value),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Transform.translate(
                      offset: Offset(-delta * 40, 0),
                      child: Opacity(
                        opacity: visibility,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _rise(
                                phase(0.25, 0.65),
                                Text(
                                  page.eyebrow,
                                  style: const TextStyle(
                                    color: LuxeColors.emerald,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2.4,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _rise(
                                phase(0.32, 0.75),
                                Semantics(
                                  header: true,
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${page.lead}\n',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w300,
                                            color: LuxeColors.platinum,
                                          ),
                                        ),
                                        TextSpan(
                                          text: page.emphasis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: LuxeColors.text,
                                          ),
                                        ),
                                      ],
                                    ),
                                    style: const TextStyle(
                                      fontSize: 30,
                                      height: 1.18,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              _rise(
                                phase(0.42, 0.85),
                                Text(
                                  page.body,
                                  style: const TextStyle(
                                    color: LuxeColors.muted,
                                    fontSize: 14,
                                    height: 1.55,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _rise(double t, Widget child) => Opacity(
    opacity: t,
    child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
  );

  Widget _illustration(int i, double enter, double loop) {
    switch (i) {
      case 0:
        return ExcludeSemantics(
          child: CustomPaint(
            painter: _GaugePainter(enter: enter, loop: loop),
          ),
        );
      case 1:
        return ExcludeSemantics(
          child: CustomPaint(
            painter: _ChargePainter(enter: enter, loop: loop),
          ),
        );
      default:
        return ExcludeSemantics(
          child: _BotScene(enter: enter, loop: loop),
        );
    }
  }

  Widget _bottomBar(bool last) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pager,
          builder: (context, _) =>
              _Indicator(page: _page, count: _pages.length),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: last ? widget.onCreateAccount : () => _goTo(_index + 1),
            child: AnimatedSwitcher(
              duration: AppMotion.durationFor(context, AppMotion.fast),
              child: Row(
                key: ValueKey(last),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      last ? 'Tạo tài khoản' : 'Tiếp tục',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: widget.onSignIn,
          child: const Text.rich(
            TextSpan(
              text: 'Tôi đã có tài khoản · ',
              children: [
                TextSpan(
                  text: 'Đăng nhập',
                  style: TextStyle(
                    color: LuxeColors.platinumHi,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}

/// Pill indicator that stretches continuously with the swipe.
class _Indicator extends StatelessWidget {
  const _Indicator({required this.page, required this.count});
  final double page;
  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Trang ${page.round() + 1} trên $count',
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Builder(
            builder: (context) {
              final t = (1 - (page - i).abs()).clamp(0.0, 1.0);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 6 + 22 * t,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: Color.lerp(
                    const Color(0x40FFFFFF),
                    LuxeColors.emerald,
                    t,
                  ),
                  boxShadow: t > 0.5
                      ? [
                          BoxShadow(
                            color: LuxeColors.emerald.withValues(
                              alpha: 0.4 * t,
                            ),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
              );
            },
          ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGE 1 — Platinum gauge: ticks sweep in, emerald arc counts up to 82%.
// ═══════════════════════════════════════════════════════════════════════════

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.enter, required this.loop});
  final double enter;
  final double loop;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;
  static const _value = 0.82;

  double _phase(double a, double b, [Curve curve = LuxeMotion.enter]) =>
      curve.transform(((enter - a) / (b - a)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final r = s * 0.36;
    final ring = _phase(0.0, 0.35);
    final ticks = _phase(0.05, 0.55, Curves.easeInOutCubic);
    final fill = _phase(0.3, 0.95, const Cubic(0.65, 0.0, 0.35, 1.0));
    final breath = 0.5 + 0.5 * math.sin(loop * 2 * math.pi);

    // Soft emerald pool beneath the dial.
    canvas.drawCircle(
      c,
      r * 1.25,
      Paint()
        ..shader = ui.Gradient.radial(c, r * 1.25, [
          LuxeColors.emerald.withValues(
            alpha: 0.10 * fill * (0.8 + 0.2 * breath),
          ),
          const Color(0x0034D399),
        ]),
    );

    // Bezel: outer platinum ring and inner hairline.
    final bezel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = ui.Gradient.linear(c.translate(-r, -r), c.translate(r, r), [
        LuxeColors.platinumHi.withValues(alpha: 0.75 * ring),
        LuxeColors.platinumLow.withValues(alpha: 0.35 * ring),
      ]);
    canvas.drawCircle(c, r + s * 0.075, bezel);
    canvas.drawCircle(
      c,
      r - s * 0.06,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Color.fromRGBO(255, 255, 255, 0.10 * ring),
    );

    // A slow highlight travelling round the bezel.
    if (ring > 0) {
      final a = loop * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r + s * 0.075),
        a,
        0.7,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.sweep(
            c,
            [
              const Color(0x00FFFFFF),
              Color.fromRGBO(255, 255, 255, 0.7 * ring),
              const Color(0x00FFFFFF),
            ],
            [0.0, 0.5, 1.0],
            TileMode.clamp,
            a,
            a + 0.7,
          ),
      );
    }

    // Tick marks sweep in clockwise.
    const count = 60;
    for (var k = 0; k <= count; k++) {
      final f = k / count;
      if (f > ticks) break;
      final ang = _start + _sweep * f;
      final major = k % 5 == 0;
      final lit = f <= _value * fill;
      final r0 = r + s * (major ? 0.022 : 0.03);
      final r1 = r + s * 0.05;
      final dir = Offset(math.cos(ang), math.sin(ang));
      canvas.drawLine(
        c + dir * r0,
        c + dir * r1,
        Paint()
          ..strokeWidth = major ? 1.6 : 1
          ..strokeCap = StrokeCap.round
          ..color = lit
              ? LuxeColors.emerald.withValues(alpha: major ? 0.95 : 0.6)
              : Color.fromRGBO(255, 255, 255, major ? 0.45 : 0.18),
      );
    }

    // Track and value arc.
    final arcRect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
      arcRect,
      _start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.03
        ..strokeCap = StrokeCap.round
        ..color = Color.fromRGBO(255, 255, 255, 0.06 * ring),
    );
    final valueSweep = _sweep * _value * fill;
    if (valueSweep > 0.001) {
      final shader = ui.Gradient.sweep(
        c,
        const [LuxeColors.emeraldDeep, LuxeColors.emerald, Color(0xFFCFF7E6)],
        const [0.0, 0.8, 1.0],
        TileMode.clamp,
        _start,
        _start + valueSweep,
      );
      canvas.drawArc(
        arcRect,
        _start,
        valueSweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.05
          ..strokeCap = StrokeCap.round
          ..shader = shader
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 + 4 * breath),
      );
      canvas.drawArc(
        arcRect,
        _start,
        valueSweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.03
          ..strokeCap = StrokeCap.round
          ..shader = shader,
      );
      final head = _start + valueSweep;
      final hp = c + Offset(math.cos(head), math.sin(head)) * r;
      canvas.drawCircle(
        hp,
        s * 0.03,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(hp, s * 0.016, Paint()..color = LuxeColors.platinumHi);
    }

    // Numerals.
    final pct = (82 * fill).round();
    final big = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$pct',
            style: TextStyle(
              fontSize: s * 0.2,
              fontWeight: FontWeight.w200,
              color: Color.fromRGBO(247, 247, 245, ring),
              letterSpacing: -2,
            ),
          ),
          TextSpan(
            text: '%',
            style: TextStyle(
              fontSize: s * 0.075,
              fontWeight: FontWeight.w300,
              color: LuxeColors.muted.withValues(alpha: ring),
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    big.paint(canvas, c - Offset(big.width / 2, big.height * 0.62));
    final label = TextPainter(
      text: TextSpan(
        text: 'SỨC KHỎE PIN  98%',
        style: TextStyle(
          fontSize: s * 0.034,
          letterSpacing: s * 0.006,
          fontWeight: FontWeight.w500,
          color: LuxeColors.emerald.withValues(alpha: _phase(0.7, 1.0)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, c + Offset(-label.width / 2, big.height * 0.42));
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.enter != enter || old.loop != loop;
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGE 2 — Socket → cable → battery: the cable draws, energy flows, the
// cell fills and a hardware timer ring counts down.
// ═══════════════════════════════════════════════════════════════════════════

class _ChargePainter extends CustomPainter {
  _ChargePainter({required this.enter, required this.loop});
  final double enter;
  final double loop;

  double _phase(double a, double b, [Curve curve = LuxeMotion.enter]) =>
      curve.transform(((enter - a) / (b - a)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    Offset p(double x, double y) => Offset(x * s, y * s);
    final appear = _phase(0.0, 0.35);
    final cableT = _phase(0.2, 0.6, Curves.easeInOutCubic);
    final level = _phase(0.45, 1.0, const Cubic(0.65, 0.0, 0.35, 1.0));
    final flow = ((enter - 0.55) / 0.2).clamp(0.0, 1.0);

    // ── Socket (Shelly plug) ──
    final socket = RRect.fromRectAndRadius(
      Rect.fromLTRB(0.06 * s, 0.38 * s, 0.32 * s, 0.64 * s),
      Radius.circular(0.06 * s),
    );
    canvas.drawRRect(
      socket.shift(const Offset(0, 8)),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, 0.5 * appear)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawRRect(
      socket,
      Paint()
        ..shader = ui.Gradient.linear(
          socket.outerRect.topLeft,
          socket.outerRect.bottomRight,
          [
            LuxeColors.platinumHi.withValues(alpha: appear),
            LuxeColors.platinumMid.withValues(alpha: appear),
          ],
        ),
    );
    // Recessed face with two pin holes.
    final face = Rect.fromCircle(center: socket.center, radius: 0.075 * s);
    canvas.drawOval(
      face,
      Paint()..color = Color.fromRGBO(40, 42, 46, 0.9 * appear),
    );
    for (final dx in [-0.026, 0.026]) {
      canvas.drawCircle(
        socket.center + Offset(dx * s, 0),
        0.011 * s,
        Paint()..color = Color.fromRGBO(10, 10, 12, appear),
      );
    }
    // Status LED: emerald, breathing once energy flows.
    final led = 0.5 + 0.5 * math.sin(loop * 2 * math.pi * 2);
    final ledPos = Offset(socket.right - 0.04 * s, socket.top + 0.04 * s);
    canvas.drawCircle(
      ledPos,
      0.02 * s,
      Paint()
        ..color = LuxeColors.emerald.withValues(alpha: 0.6 * flow * led)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      ledPos,
      0.008 * s,
      Paint()
        ..color = Color.lerp(
          LuxeColors.platinumLow,
          LuxeColors.emerald,
          flow,
        )!.withValues(alpha: appear),
    );

    // ── Battery cell ──
    final cell = RRect.fromRectAndRadius(
      Rect.fromLTRB(0.62 * s, 0.26 * s, 0.88 * s, 0.82 * s),
      Radius.circular(0.05 * s),
    );
    final cap = RRect.fromRectAndRadius(
      Rect.fromLTRB(0.71 * s, 0.215 * s, 0.79 * s, 0.26 * s),
      Radius.circular(0.012 * s),
    );
    canvas.drawRRect(
      cap,
      Paint()..color = LuxeColors.platinumMid.withValues(alpha: appear),
    );
    canvas.drawRRect(
      cell,
      Paint()..color = Color.fromRGBO(255, 255, 255, 0.04 * appear),
    );
    // Fill with a gently moving surface.
    final inner = cell.deflate(0.018 * s);
    final top = inner.bottom - inner.height * 0.76 * level;
    if (level > 0) {
      canvas.save();
      canvas.clipRRect(inner);
      final wave = Path()..moveTo(inner.left, inner.bottom);
      const steps = 24;
      for (var k = 0; k <= steps; k++) {
        final x = inner.left + inner.width * k / steps;
        final y =
            top +
            math.sin(k / steps * 2 * math.pi + loop * 2 * math.pi) * 0.008 * s;
        wave.lineTo(x, y);
      }
      wave
        ..lineTo(inner.right, inner.bottom)
        ..close();
      canvas.drawPath(
        wave,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, top),
            Offset(0, inner.bottom),
            const [Color(0xFF6EE7B7), LuxeColors.emeraldDeep],
          ),
      );
      canvas.restore();
    }
    canvas.drawRRect(
      cell,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = ui.Gradient.linear(
          cell.outerRect.topLeft,
          cell.outerRect.bottomRight,
          [
            LuxeColors.platinumHi.withValues(alpha: appear),
            LuxeColors.platinumLow.withValues(alpha: appear),
          ],
        ),
    );
    // Bolt mark on the cell.
    final bolt = Path()
      ..moveTo(0.765 * s, 0.43 * s)
      ..lineTo(0.72 * s, 0.56 * s)
      ..lineTo(0.755 * s, 0.56 * s)
      ..lineTo(0.735 * s, 0.67 * s)
      ..lineTo(0.8 * s, 0.52 * s)
      ..lineTo(0.765 * s, 0.52 * s)
      ..close();
    canvas.drawPath(
      bolt,
      Paint()..color = Color.fromRGBO(255, 255, 255, 0.85 * appear),
    );

    // ── Cable: socket → cell, drawn progressively ──
    final cable = Path()
      ..moveTo(socket.right, socket.center.dy)
      ..cubicTo(0.48 * s, 0.5 * s, 0.42 * s, 0.86 * s, 0.62 * s, 0.72 * s);
    final metric = cable.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * cableT);
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.022 * s
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF2A2C30),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..color = Color.fromRGBO(220, 222, 226, 0.6 * appear),
    );
    // Energy particles travelling the cable.
    if (flow > 0) {
      for (var k = 0; k < 5; k++) {
        final t = (loop * 2 + k / 5) % 1.0;
        final tan = metric.getTangentForOffset(metric.length * t);
        if (tan == null) continue;
        final fade = math.sin(t * math.pi) * flow;
        canvas.drawCircle(
          tan.position,
          0.022 * s,
          Paint()
            ..color = LuxeColors.emerald.withValues(alpha: 0.45 * fade)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawCircle(
          tan.position,
          0.007 * s,
          Paint()..color = Colors.white.withValues(alpha: fade),
        );
      }
    }

    // ── Hardware timer badge ──
    final timer = _phase(0.6, 1.0);
    if (timer > 0) {
      final tc = p(0.47, 0.22);
      final tr = 0.085 * s;
      canvas.drawCircle(
        tc,
        tr,
        Paint()..color = Color.fromRGBO(255, 255, 255, 0.05 * timer),
      );
      canvas.drawCircle(
        tc,
        tr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Color.fromRGBO(255, 255, 255, 0.2 * timer),
      );
      final remaining = 1 - loop;
      canvas.drawArc(
        Rect.fromCircle(center: tc, radius: tr),
        -math.pi / 2,
        2 * math.pi * remaining,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = LuxeColors.emerald.withValues(alpha: timer),
      );
      final minutes = (120 * remaining).ceil();
      final label = TextPainter(
        text: TextSpan(
          text:
              '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}',
          style: TextStyle(
            fontSize: 0.042 * s,
            fontWeight: FontWeight.w500,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
            color: LuxeColors.text.withValues(alpha: timer),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, tc - Offset(label.width / 2, label.height / 2));
      final caption = TextPainter(
        text: TextSpan(
          text: 'HẸN GIỜ',
          style: TextStyle(
            fontSize: 0.026 * s,
            letterSpacing: 0.004 * s,
            fontWeight: FontWeight.w600,
            color: LuxeColors.muted.withValues(alpha: timer),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      caption.paint(canvas, tc + Offset(-caption.width / 2, tr + 0.02 * s));
    }
  }

  @override
  bool shouldRepaint(_ChargePainter old) =>
      old.enter != enter || old.loop != loop;
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGE 3 — BatteryBot with a short, confirmed conversation.
// ═══════════════════════════════════════════════════════════════════════════

class _BotScene extends StatelessWidget {
  const _BotScene({required this.enter, required this.loop});
  final double enter;
  final double loop;

  double _phase(double a, double b) =>
      LuxeMotion.enter.transform(((enter - a) / (b - a)).clamp(0.0, 1.0));

  Widget _pop(double t, Alignment origin, Widget child) => Opacity(
    opacity: t,
    child: Transform.scale(
      scale: 0.92 + 0.08 * t,
      alignment: origin,
      child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final s = c.biggest.shortestSide;
      final scale = (s / 300).clamp(0.6, 1.2);
      return MediaQuery.withNoTextScaling(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // BatteryBot stands bottom-right on a soft emerald pool; the
            // conversation stacks to its left without covering it.
            Positioned(
              right: 0,
              bottom: 0,
              width: s * 0.34,
              height: s * 0.46,
              child: Opacity(
                opacity: _phase(0.0, 0.3),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Circular pool (no box edges) under the mascot.
                    Positioned(
                      bottom: -s * 0.04,
                      child: Container(
                        width: s * 0.36,
                        height: s * 0.36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              LuxeColors.emerald.withValues(
                                alpha:
                                    0.12 + 0.05 * math.sin(loop * 2 * math.pi),
                              ),
                              const Color(0x0034D399),
                            ],
                          ),
                        ),
                      ),
                    ),
                    FittedBox(
                      child: BatteryBotMascot(
                        size: BatteryBotSize.md,
                        mood: enter >= 0.75
                            ? BatteryBotMood.charging
                            : BatteryBotMood.happy,
                        enableFloating: !MediaQuery.disableAnimationsOf(
                          context,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: s * 0.86,
              child: _pop(
                _phase(0.2, 0.5),
                Alignment.bottomLeft,
                Align(
                  alignment: Alignment.centerLeft,
                  child: _Bubble(
                    scale: scale,
                    text: 'Pin còn 82%, đủ cho khoảng 64 km.',
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: s * 0.22,
              child: _pop(
                _phase(0.4, 0.7),
                Alignment.bottomRight,
                _Bubble(scale: scale, text: 'Bật sạc 2 giờ', mine: true),
              ),
            ),
            Positioned(
              left: 0,
              top: s * 0.42,
              width: s * 0.64,
              child: _pop(
                _phase(0.6, 0.92),
                Alignment.topLeft,
                _ConfirmCard(scale: scale, loop: loop),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.scale, this.mine = false});
  final String text;
  final double scale;
  final bool mine;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(16 * scale),
        topRight: Radius.circular(16 * scale),
        bottomLeft: Radius.circular((mine ? 16 : 4) * scale),
        bottomRight: Radius.circular((mine ? 4 : 16) * scale),
      ),
      gradient: mine
          ? const LinearGradient(
              colors: [LuxeColors.platinumHi, LuxeColors.platinum],
            )
          : const LinearGradient(
              colors: [LuxeColors.hairline, Color(0x0DFFFFFF)],
            ),
      border: Border.all(
        color: mine ? const Color(0x66FFFFFF) : LuxeColors.hairline,
      ),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13 * scale,
        height: 1.35,
        fontWeight: mine ? FontWeight.w600 : FontWeight.w400,
        color: mine ? LuxeColors.shell : LuxeColors.text,
      ),
    ),
  );
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({required this.scale, required this.loop});
  final double scale;
  final double loop;

  @override
  Widget build(BuildContext context) {
    final pulse = 0.5 + 0.5 * math.sin(loop * 2 * math.pi * 2);
    return Container(
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16 * scale),
        color: const Color(0xE6101113),
        border: Border.all(color: LuxeColors.emerald.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: LuxeColors.emerald.withValues(alpha: 0.10 + 0.08 * pulse),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.bolt_rounded,
                size: 16 * scale,
                color: LuxeColors.emerald,
              ),
              SizedBox(width: 6 * scale),
              Expanded(
                child: Text(
                  'Bật sạc · 2 giờ',
                  style: TextStyle(
                    fontSize: 12.5 * scale,
                    fontWeight: FontWeight.w600,
                    color: LuxeColors.text,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          Wrap(
            spacing: 8 * scale,
            runSpacing: 6 * scale,
            children: [
              _chip('Hủy', scale, filled: false),
              _chip('Xác nhận', scale, filled: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, double scale, {required bool filled}) => Container(
    padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(99),
      color: filled ? LuxeColors.emerald : null,
      border: filled ? null : Border.all(color: LuxeColors.hairlineStrong),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5 * scale,
        fontWeight: FontWeight.w600,
        color: filled ? const Color(0xFF04140D) : LuxeColors.muted,
      ),
    ),
  );
}
