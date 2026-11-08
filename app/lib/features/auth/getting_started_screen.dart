import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/theme/plan_style.dart';
import '../../core/theme/scene_palette.dart';
import '../../core/widgets/battery_bot_mascot.dart';
import '../../data/services/dashboard_templates.dart';
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
        const Duration(milliseconds: 620),
      ),
      switchInCurve: LuxeMotion.enter,
      switchOutCurve: Curves.easeInCubic,
      // The intro hands over like a cut in a film: it lifts away a little
      // larger while the next screen settles in from slightly behind.
      transitionBuilder: (child, animation) {
        final incoming = child.key == const ValueKey('entry-login');
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: incoming ? 0.96 : 1.04,
              end: 1,
            ).animate(animation),
            child: child,
          ),
        );
      },
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
    '03 · QUÉT ĐỒNG HỒ',
    'Đưa camera vào,',
    'tự đọc % pin và ODO',
    'Căn khung theo màn hình xe, app tự đọc số trên đồng hồ. Bạn chỉ cần xem lại rồi lưu.',
  ),
  _IntroPage(
    '04 · PINOVA BOT',
    'Trợ lý',
    'luôn bên cạnh',
    'Hỏi về pin, nhận nhắc bảo dưỡng. Mọi lệnh bật hay tắt sạc đều chờ bạn xác nhận.',
  ),
];

/// 0..1 progress of [t] inside [a, b], eased.
double _seg(double t, double a, double b, [Curve curve = LuxeMotion.enter]) =>
    curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

/// Getting started (QA 149): four short scenes, each with its own colours.
/// A scene plays when its page comes into view and rewinds once it has left,
/// so swiping back plays it again; the colours of neighbouring scenes blend
/// under the finger. Every movement is one pass (no endless loop) and the
/// pages are still under "reduce motion".
class GettingStartedScreen extends StatefulWidget {
  const GettingStartedScreen({
    super.key,
    required this.onCreateAccount,
    required this.onSignIn,
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;

  /// One scene, from the page appearing to its last detail settling.
  static const sceneDuration = Duration(milliseconds: 2600);

  @override
  State<GettingStartedScreen> createState() => _GettingStartedScreenState();
}

class _GettingStartedScreenState extends State<GettingStartedScreen>
    with TickerProviderStateMixin {
  final _pager = PageController();
  late final List<AnimationController> _scene = List.generate(
    _pages.length,
    (_) => AnimationController(
      vsync: this,
      duration: GettingStartedScreen.sceneDuration,
    ),
  );
  int _index = 0;
  bool _reduced = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _pager.addListener(_syncScenes);
  }

  /// A page starts its scene as soon as it peeks in under the finger, so it
  /// plays while it slides in, and rewinds once it is fully off screen, so
  /// coming back replays it.
  void _syncScenes() {
    if (_reduced) return;
    final page = _page;
    for (var i = 0; i < _scene.length; i++) {
      final distance = (page - i).abs();
      final scene = _scene[i];
      if (distance >= 0.995) {
        if (!scene.isDismissed) scene.value = 0;
      } else if (distance < 0.92 && scene.isDismissed) {
        scene.forward();
      }
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
      for (final c in _scene) {
        c.value = 1;
      }
    } else {
      for (var i = 0; i < _scene.length; i++) {
        if (i != _index) _scene[i].value = 0;
      }
      _scene[_index].forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    for (final c in _scene) {
      c.dispose();
    }
    super.dispose();
  }

  void _onPageChanged(int index) {
    HapticFeedback.selectionClick();
    setState(() => _index = index);
    if (!_reduced && _scene[index].isDismissed) _scene[index].forward();
  }

  void _goTo(int index) {
    if (_reduced) {
      _pager.jumpToPage(index);
      return;
    }
    final distance = (index - _page).abs();
    _pager.animateToPage(
      index,
      duration: Duration(milliseconds: (560 + 220 * distance).round()),
      curve: const Cubic(0.65, 0.0, 0.35, 1.0),
    );
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
                animation: Listenable.merge([_pager, ..._scene]),
                builder: (context, _) {
                  final page = _page;
                  final i = page.round().clamp(0, _pages.length - 1);
                  return CustomPaint(
                    painter: _StoryBackdrop(page: page, scene: _scene[i].value),
                  );
                },
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
    final palette = SceneColors.scenes[i];
    return LayoutBuilder(
      builder: (context, constraints) {
        final art = math.min(
          constraints.maxWidth - 64,
          (constraints.maxHeight * 0.54).clamp(150.0, 330.0),
        );
        return AnimatedBuilder(
          animation: Listenable.merge([_pager, _scene[i]]),
          builder: (context, _) {
            final delta = (_page - i).clamp(-1.0, 1.0);
            final visibility = 1 - delta.abs();
            final e = _scene[i].value;
            final artIn = _seg(e, 0.0, 0.32);
            final eyebrow = _seg(e, 0.16, 0.44);
            final headline = _seg(e, 0.22, 0.58);
            final body = _seg(e, 0.36, 0.70);
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // The art turns away in depth as the page leaves and
                    // travels further than the copy (parallax).
                    Transform.translate(
                      offset: Offset(-delta * 140, 0),
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0012)
                          ..rotateY(delta * 0.6),
                        child: Transform.scale(
                          scale:
                              (0.86 + 0.14 * artIn) * (1 - 0.1 * delta.abs()),
                          child: Opacity(
                            opacity: (artIn * (0.2 + 0.8 * visibility)).clamp(
                              0.0,
                              1.0,
                            ),
                            child: SizedBox.square(
                              dimension: art,
                              child: _illustration(i, e, palette),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Transform.translate(
                      offset: Offset(-delta * 48, 0),
                      child: Opacity(
                        opacity: visibility,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Eyebrow(
                                text: page.eyebrow,
                                palette: palette,
                                t: eyebrow,
                              ),
                              const SizedBox(height: 12),
                              _Headline(
                                lead: page.lead,
                                emphasis: page.emphasis,
                                palette: palette,
                                t: headline,
                              ),
                              const SizedBox(height: 14),
                              Opacity(
                                opacity: body,
                                child: Transform.translate(
                                  offset: Offset(0, 14 * (1 - body)),
                                  child: Text(
                                    page.body,
                                    style: const TextStyle(
                                      color: LuxeColors.muted,
                                      fontSize: 14,
                                      height: 1.55,
                                    ),
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

  Widget _illustration(int i, double e, List<Color> palette) {
    final painter = switch (i) {
      0 => _GaugePainter(enter: e, palette: palette),
      1 => _ChargePainter(enter: e, palette: palette),
      2 => _ScanPainter(enter: e, palette: palette),
      _ => null,
    };
    return ExcludeSemantics(
      child: painter == null
          ? _BotScene(enter: e, palette: palette)
          : CustomPaint(painter: painter),
    );
  }

  Widget _bottomBar(bool last) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
    child: AnimatedBuilder(
      animation: Listenable.merge([_pager, _scene[_index]]),
      builder: (context, _) {
        final page = _page;
        final palette = SceneColors.at(page);
        // The button catches the light once, as each scene settles.
        final shine = _reduced
            ? 0.0
            : _seg(_scene[_index].value, 0.62, 0.95, Curves.easeInOutCubic);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Indicator(page: page, count: _pages.length, palette: palette),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('intro-cta'),
                onPressed: last
                    ? widget.onCreateAccount
                    : () => _goTo(_index + 1),
                style: ButtonStyle(
                  backgroundBuilder: (context, states, child) => _CtaFill(
                    palette: palette,
                    shine: shine,
                    pressed: states.contains(WidgetState.pressed),
                    child: child,
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: AppMotion.durationFor(context, AppMotion.base),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.4),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
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
        );
      },
    ),
  );
}

/// Section label in the scene's colours, its letters closing in as it fades
/// up (a title card's tracking).
class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.text, required this.palette, required this.t});
  final String text;
  final List<Color> palette;
  final double t;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: t,
    child: Transform.translate(
      offset: Offset(-20 * (1 - t), 0),
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) =>
            LinearGradient(colors: palette).createShader(bounds),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.4 + 5 * (1 - t),
          ),
        ),
      ),
    ),
  );
}

/// The headline wipes in top to bottom out of a soft blur; its second line
/// carries the scene's gradient.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.lead,
    required this.emphasis,
    required this.palette,
    required this.t,
  });
  final String lead;
  final String emphasis;
  final List<Color> palette;
  final double t;

  @override
  Widget build(BuildContext context) {
    final text = Semantics(
      header: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$lead\n',
              style: const TextStyle(
                fontWeight: FontWeight.w300,
                color: LuxeColors.platinum,
              ),
            ),
            TextSpan(
              text: emphasis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                foreground: Paint()
                  ..shader = ui.Gradient.linear(
                    Offset.zero,
                    const Offset(300, 40),
                    palette,
                    const [0.0, 0.55, 1.0],
                  ),
              ),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 30, height: 1.18, letterSpacing: -0.4),
      ),
    );
    if (t >= 1) return text;
    // Mask first, then blur the masked result: blurring inside the mask let
    // the soft edge spill past it as a glowing box.
    Widget masked = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Colors.white, Color(0x00FFFFFF)],
        stops: [(t * 1.3 - 0.3).clamp(0.0, 1.0), (t * 1.3).clamp(0.0, 1.0)],
      ).createShader(bounds),
      child: text,
    );
    final blur = 6 * (1 - t);
    if (blur > 0.05) {
      masked = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: TileMode.decal,
        ),
        child: masked,
      );
    }
    return Transform.translate(offset: Offset(0, 22 * (1 - t)), child: masked);
  }
}

/// The CTA pill: the scene's gradient, one pass of light, and a little give
/// when pressed.
class _CtaFill extends StatelessWidget {
  const _CtaFill({
    required this.palette,
    required this.shine,
    required this.pressed,
    required this.child,
  });
  final List<Color> palette;
  final double shine;
  final bool pressed;
  final Widget? child;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: pressed ? 0.97 : 1,
    duration: AppMotion.durationFor(context, const Duration(milliseconds: 140)),
    curve: Curves.easeOutCubic,
    child: DecoratedBox(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(side: BorderSide(color: Color(0x66FFFFFF))),
        gradient: LinearGradient(colors: palette),
        shadows: [
          BoxShadow(
            color: palette[1].withValues(alpha: 0.45),
            blurRadius: 24,
            spreadRadius: -6,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: shine > 0 && shine < 1 ? _ShinePainter(shine) : null,
        child: child,
      ),
    ),
  );
}

class _ShinePainter extends CustomPainter {
  _ShinePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.save();
    canvas.clipRRect(rrect);
    final x = -size.height + (size.width + 2 * size.height) * t;
    final band = Path()
      ..moveTo(x, 0)
      ..lineTo(x + size.height * 0.8, 0)
      ..lineTo(x, size.height)
      ..lineTo(x - size.height * 0.8, size.height)
      ..close();
    canvas.drawPath(
      band,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.38 * math.sin(t * math.pi))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShinePainter old) => old.t != t;
}

/// Pill indicator that stretches with the swipe, in the scene's colours.
class _Indicator extends StatelessWidget {
  const _Indicator({
    required this.page,
    required this.count,
    required this.palette,
  });
  final double page;
  final int count;
  final List<Color> palette;

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
                width: 6 + 24 * t,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: t > 0 ? null : LuxeColors.hairlineStrong,
                  gradient: t > 0
                      ? LinearGradient(
                          colors: [
                            for (final c in palette)
                              Color.lerp(LuxeColors.hairlineStrong, c, t)!,
                          ],
                        )
                      : null,
                  boxShadow: t > 0.5
                      ? [
                          BoxShadow(
                            color: palette[1].withValues(alpha: 0.5 * t),
                            blurRadius: 12,
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
// The backdrop: three pools of the scene's light that follow the swipe, a
// field of fine dust in depth, and one sweep of light as a scene arrives.
// ═══════════════════════════════════════════════════════════════════════════

class _StoryBackdrop extends CustomPainter {
  _StoryBackdrop({required this.page, required this.scene});

  /// Fractional page: the colours blend between neighbouring scenes.
  final double page;

  /// The current scene's progress: it blooms as the scene arrives.
  final double scene;

  static final _dust = () {
    final random = math.Random(149);
    return [
      for (var i = 0; i < 46; i++)
        (
          random.nextDouble(),
          random.nextDouble(),
          0.4 + random.nextDouble() * 1.6,
          0.2 + random.nextDouble() * 0.8,
        ),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final palette = SceneColors.at(page);
    final bloom = 0.85 + 0.3 * math.sin(_seg(scene, 0.0, 0.7) * math.pi);
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = LuxeColors.background);
    final long = size.longestSide;
    void pool(Offset center, double radius, Color color, double alpha) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            radius,
            [
              color.withValues(alpha: alpha * bloom),
              color.withValues(alpha: alpha * bloom * 0.35),
              color.withValues(alpha: 0),
            ],
            const [0.0, 0.45, 1.0],
          ),
      );
    }

    final w = size.width, h = size.height;
    pool(
      Offset(w * (0.15 + 0.12 * math.sin(page * 1.3)), h * 0.12),
      long * 0.62,
      palette[0],
      0.30,
    );
    pool(
      Offset(w * (0.95 - 0.1 * math.cos(page * 0.9)), h * (0.42 + 0.04 * page)),
      long * 0.5,
      palette[1],
      0.24,
    );
    pool(
      Offset(w * (0.3 + 0.15 * math.sin(page * 0.7 + 1)), h * 1.02),
      long * 0.6,
      palette[2],
      0.22,
    );

    // Dust: nearer specks drift further with the swipe.
    for (final (x, y, r, depth) in _dust) {
      final dx = (x * w - page * 26 * depth) % w;
      final glow = _seg(scene, 0.1 + 0.3 * (1 - depth), 0.8);
      canvas.drawCircle(
        Offset(dx, y * h),
        r,
        Paint()
          ..color = Color.lerp(
            Colors.white,
            palette[1],
            0.5,
          )!.withValues(alpha: (0.06 + 0.22 * depth) * (0.4 + 0.6 * glow)),
      );
    }

    // One soft sweep of light as the scene arrives.
    final sweep = _seg(scene, 0.04, 0.6, Curves.easeInOutCubic);
    if (sweep > 0 && sweep < 1) {
      final x = -w + (2.4 * w) * sweep;
      final band = Path()
        ..moveTo(x, 0)
        ..lineTo(x + w * 0.35, 0)
        ..lineTo(x + w * 0.35 - h * 0.6, h)
        ..lineTo(x - h * 0.6, h)
        ..close();
      canvas.drawPath(
        band,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x - h * 0.3, 0),
            Offset(x + w * 0.35, 0),
            [
              Colors.white.withValues(alpha: 0),
              palette[1].withValues(alpha: 0.10 * math.sin(sweep * math.pi)),
              Colors.white.withValues(alpha: 0),
            ],
            const [0.0, 0.5, 1.0],
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
      );
    }

    // Vignette.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          size.center(Offset.zero),
          long * 0.75,
          [const Color(0x00000000), const Color(0x99000000)],
          const [0.55, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_StoryBackdrop old) =>
      old.page != page || old.scene != scene;
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGE 1 — Gauge: the bezel draws on, ticks sweep in, the arc counts to 82%.
// ═══════════════════════════════════════════════════════════════════════════

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.enter, required this.palette});
  final double enter;
  final List<Color> palette;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;
  static const _value = 0.82;

  double _p(double a, double b, [Curve curve = LuxeMotion.enter]) =>
      _seg(enter, a, b, curve);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final r = s * 0.36;
    final ring = _p(0.0, 0.4);
    final ticks = _p(0.08, 0.55, Curves.easeInOutCubic);
    final fill = _p(0.3, 0.92, const Cubic(0.65, 0.0, 0.35, 1.0));
    final glow = math.sin(_p(0.3, 1.0) * math.pi);

    // A pool of the scene's light under the dial.
    canvas.drawCircle(
      c,
      r * 1.4,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          r * 1.4,
          [
            palette[1].withValues(alpha: 0.18 * fill + 0.08 * glow),
            palette[2].withValues(alpha: 0.05 * fill),
            palette[2].withValues(alpha: 0),
          ],
          const [0.0, 0.6, 1.0],
        ),
    );

    // Bezel drawn on clockwise.
    final bezelR = r + s * 0.075;
    final bezelRect = Rect.fromCircle(center: c, radius: bezelR);
    canvas.drawArc(
      bezelRect,
      -math.pi / 2,
      2 * math.pi * ring,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = ui.Gradient.sweep(
          c,
          [
            LuxeColors.platinumHi.withValues(alpha: 0.8),
            palette[1].withValues(alpha: 0.7),
            LuxeColors.platinumLow.withValues(alpha: 0.4),
            LuxeColors.platinumHi.withValues(alpha: 0.8),
          ],
          const [0.0, 0.35, 0.7, 1.0],
        ),
    );
    canvas.drawCircle(
      c,
      r - s * 0.06,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Color.fromRGBO(255, 255, 255, 0.10 * ring),
    );

    // A highlight travels once round the bezel.
    final travel = _p(0.2, 0.95, Curves.easeInOutCubic);
    if (travel > 0 && travel < 1) {
      final a = -math.pi / 2 + travel * 2 * math.pi;
      canvas.drawArc(
        bezelRect,
        a,
        0.6,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(
            alpha: 0.7 * math.sin(travel * math.pi),
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }

    // Ticks sweep in; the lit ones take the scene's gradient.
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
      final hue = f < 0.5
          ? Color.lerp(palette[0], palette[1], f * 2)!
          : Color.lerp(palette[1], palette[2], f * 2 - 1)!;
      canvas.drawLine(
        c + dir * r0,
        c + dir * r1,
        Paint()
          ..strokeWidth = major ? 1.7 : 1
          ..strokeCap = StrokeCap.round
          ..color = lit
              ? hue.withValues(alpha: major ? 1 : 0.7)
              : Color.fromRGBO(255, 255, 255, major ? 0.42 : 0.16),
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
        ..color = Color.fromRGBO(255, 255, 255, 0.07 * ring),
    );
    final valueSweep = _sweep * _value * fill;
    if (valueSweep > 0.001) {
      final shader = ui.Gradient.sweep(
        c,
        palette,
        const [0.0, 0.5, 1.0],
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
          ..strokeWidth = s * 0.06
          ..strokeCap = StrokeCap.round
          ..shader = shader
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 9 + 6 * glow),
      );
      canvas.drawArc(
        arcRect,
        _start,
        valueSweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.032
          ..strokeCap = StrokeCap.round
          ..shader = shader,
      );
      final head = _start + valueSweep;
      final hp = c + Offset(math.cos(head), math.sin(head)) * r;
      canvas.drawCircle(
        hp,
        s * 0.035,
        Paint()
          ..color = palette[2].withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(hp, s * 0.017, Paint()..color = LuxeColors.platinumHi);
    }

    // Numerals count up with the arc.
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
              color: palette[1].withValues(alpha: ring),
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
          color: palette[0].withValues(alpha: _p(0.7, 1.0)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, c + Offset(-label.width / 2, big.height * 0.42));
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.enter != enter || old.palette != palette;
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGE 2 — Socket → cable → battery: the cable draws, energy runs along it,
// the cell fills and the hardware timer ring counts down.
// ═══════════════════════════════════════════════════════════════════════════

class _ChargePainter extends CustomPainter {
  _ChargePainter({required this.enter, required this.palette});
  final double enter;
  final List<Color> palette;

  double _p(double a, double b, [Curve curve = LuxeMotion.enter]) =>
      _seg(enter, a, b, curve);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    Offset p(double x, double y) => Offset(x * s, y * s);
    final appear = _p(0.0, 0.32);
    final cableT = _p(0.16, 0.56, Curves.easeInOutCubic);
    final level = _p(0.42, 1.0, const Cubic(0.65, 0.0, 0.35, 1.0));
    // Energy runs while the cell fills, then settles.
    final flow = _p(0.5, 0.6) * (1 - _p(0.9, 1.0, Curves.easeInCubic));

    // Glow behind the scene.
    canvas.drawCircle(
      p(0.55, 0.52),
      0.5 * s,
      Paint()
        ..shader = ui.Gradient.radial(p(0.55, 0.52), 0.5 * s, [
          palette[1].withValues(alpha: 0.16 * level + 0.04),
          palette[1].withValues(alpha: 0),
        ]),
    );

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
    // Status LED lights in the scene's colour once energy runs.
    final ledOn = _p(0.5, 0.65);
    final ledPos = Offset(socket.right - 0.04 * s, socket.top + 0.04 * s);
    canvas.drawCircle(
      ledPos,
      0.024 * s,
      Paint()
        ..color = palette[0].withValues(alpha: 0.7 * ledOn)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      ledPos,
      0.009 * s,
      Paint()
        ..color = Color.lerp(
          LuxeColors.platinumLow,
          palette[0],
          ledOn,
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
      Paint()..color = Color.fromRGBO(255, 255, 255, 0.05 * appear),
    );
    final inner = cell.deflate(0.018 * s);
    final top = inner.bottom - inner.height * 0.76 * level;
    if (level > 0) {
      canvas.save();
      canvas.clipRRect(inner);
      // The surface ripples while it rises and calms as it settles.
      final ripple = 0.010 * s * (1 - _p(0.85, 1.0));
      final wave = Path()..moveTo(inner.left, inner.bottom);
      const steps = 24;
      for (var k = 0; k <= steps; k++) {
        final x = inner.left + inner.width * k / steps;
        final y =
            top +
            math.sin(k / steps * 2 * math.pi + enter * 6 * math.pi) * ripple;
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
            [palette[0], palette[1], palette[2]],
            const [0.0, 0.5, 1.0],
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
      Paint()..color = Color.fromRGBO(255, 255, 255, 0.9 * appear),
    );

    // ── Cable: socket → cell, drawn on ──
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
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          socket.center,
          cell.outerRect.bottomLeft,
          [
            palette[0].withValues(alpha: 0.7),
            palette[2].withValues(alpha: 0.7),
          ],
        ),
    );
    // Energy pulses running the cable.
    if (flow > 0) {
      final run = enter * 5;
      for (var k = 0; k < 5; k++) {
        final t = (run + k / 5) % 1.0;
        final tan = metric.getTangentForOffset(metric.length * t);
        if (tan == null) continue;
        final fade = math.sin(t * math.pi) * flow;
        canvas.drawCircle(
          tan.position,
          0.024 * s,
          Paint()
            ..color = palette[1].withValues(alpha: 0.55 * fade)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawCircle(
          tan.position,
          0.007 * s,
          Paint()..color = Colors.white.withValues(alpha: fade),
        );
      }
    }

    // ── Hardware timer badge counts down a little, then holds ──
    final timer = _p(0.58, 0.95);
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
      final remaining = 1 - 0.25 * _p(0.6, 1.0, Curves.linear);
      canvas.drawArc(
        Rect.fromCircle(center: tc, radius: tr),
        -math.pi / 2,
        2 * math.pi * remaining,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.sweep(tc, palette, const [0.0, 0.5, 1.0]),
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
      old.enter != enter || old.palette != palette;
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGE 3 — The scanner: the Feliz glass appears, a beam reads it top to
// bottom, the battery % and ODO lock and lift out as results.
// ═══════════════════════════════════════════════════════════════════════════

class _ScanPainter extends CustomPainter {
  _ScanPainter({required this.enter, required this.palette});
  final double enter;
  final List<Color> palette;

  static const _segments = {
    '0': 'abcdef',
    '1': 'bc',
    '3': 'abcdg',
    '4': 'bcfg',
    '6': 'acdefg',
    '8': 'abcdefg',
  };

  double _p(double a, double b, [Curve curve = LuxeMotion.enter]) =>
      _seg(enter, a, b, curve);

  /// A seven-segment number, [h] tall, leaning like the cluster's italics.
  void _digits(Canvas canvas, String text, Offset at, double h, Paint paint) {
    final cw = 0.54 * h, t = 0.13 * h, g = 0.035 * h;
    var x = at.dx;
    for (final ch in text.split('')) {
      if (ch == ' ') {
        x += 0.4 * h;
        continue;
      }
      final lit = _segments[ch] ?? '';
      final y = at.dy;
      Rect r(double l, double tp, double rt, double b) =>
          Rect.fromLTRB(x + l, y + tp, x + rt, y + b);
      final rects = {
        'a': r(t + g, 0, cw - t - g, t),
        'b': r(cw - t, t + g, cw, h / 2 - g),
        'c': r(cw - t, h / 2 + g, cw, h - t - g),
        'd': r(t + g, h - t, cw - t - g, h),
        'e': r(0, h / 2 + g, t, h - t - g),
        'f': r(0, t + g, t, h / 2 - g),
        'g': r(t + g, h / 2 - t / 2, cw - t - g, h / 2 + t / 2),
      };
      canvas.save();
      // Italic lean around the digit's middle.
      canvas.translate(x + cw / 2, y + h / 2);
      canvas.transform(
        Float64List.fromList([
          1,
          0,
          0,
          0,
          -0.12,
          1,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          1,
        ]),
      );
      canvas.translate(-(x + cw / 2), -(y + h / 2));
      for (final MapEntry(key: k, value: rect) in rects.entries) {
        if (!lit.contains(k)) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(t * 0.4)),
          paint,
        );
      }
      canvas.restore();
      x += cw + 0.2 * h;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final template = DashboardTemplate.feliz2025;
    final w = s * 0.94;
    final h = w / template.aspect;
    final glass = Rect.fromCenter(
      center: size.center(Offset(0, -0.04 * s)),
      width: w,
      height: h,
    );
    final appear = _p(0.0, 0.3);
    final beam = _p(0.22, 0.68, Curves.easeInOutCubic);
    final lock = _p(0.66, 0.82, Curves.easeOutBack);
    final results = _p(0.74, 1.0);
    final path = template.glassPath(glass);
    Rect zone(Rect z) => Rect.fromLTRB(
      glass.left + z.left * glass.width,
      glass.top + z.top * glass.height,
      glass.left + z.right * glass.width,
      glass.top + z.bottom * glass.height,
    );

    // Glow and the glass itself.
    canvas.drawPath(
      path.shift(const Offset(0, 10)),
      Paint()
        ..color = palette[1].withValues(alpha: 0.28 * appear)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(glass.topCenter, glass.bottomCenter, [
          const Color(0xFF15161A).withValues(alpha: appear),
          const Color(0xFF08090B).withValues(alpha: appear),
        ]),
    );
    canvas.save();
    canvas.clipPath(path);

    // The LCD: battery %, the speed (dim), ODO and the temperature.
    final lcd = Paint()
      ..color = LuxeColors.platinumHi.withValues(alpha: 0.85 * appear);
    final dim = Paint()
      ..color = LuxeColors.platinumHi.withValues(alpha: 0.28 * appear);
    final socZone = zone(template.soc);
    final odoZone = zone(template.odo);
    final tempZone = zone(template.temp);
    final speedZone = zone(template.ignore);
    final digitH = socZone.height * 0.78;
    _digits(
      canvas,
      '68',
      socZone.topLeft + Offset(0, 0.1 * socZone.height),
      digitH,
      lcd,
    );
    _digits(
      canvas,
      '00',
      speedZone.topLeft +
          Offset(0.08 * speedZone.width, 0.1 * speedZone.height),
      speedZone.height * 0.78,
      dim,
    );
    _digits(
      canvas,
      '48 18',
      odoZone.topLeft + Offset(0.06 * odoZone.width, 0.12 * odoZone.height),
      odoZone.height * 0.74,
      lcd,
    );
    _digits(
      canvas,
      '31',
      tempZone.topLeft + Offset(0.12 * tempZone.width, 0.12 * tempZone.height),
      tempZone.height * 0.7,
      dim,
    );

    // The beam reads top to bottom and leaves a soft trail.
    if (beam > 0 && beam < 1) {
      final y = glass.top + glass.height * beam;
      canvas.drawRect(
        Rect.fromLTRB(glass.left, y - glass.height * 0.22, glass.right, y),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, y - glass.height * 0.22),
            Offset(0, y),
            [
              palette[1].withValues(alpha: 0),
              palette[1].withValues(alpha: 0.22),
            ],
          ),
      );
      canvas.drawLine(
        Offset(glass.left, y),
        Offset(glass.right, y),
        Paint()
          ..strokeWidth = 2
          ..shader = ui.Gradient.linear(
            Offset(glass.left, y),
            Offset(glass.right, y),
            [
              palette[0].withValues(alpha: 0),
              palette[2],
              palette[0].withValues(alpha: 0),
            ],
            const [0.0, 0.5, 1.0],
          ),
      );
    }
    canvas.restore();

    // The glass edge, drawn on with the beam.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = ui.Gradient.linear(
          glass.topLeft,
          glass.bottomRight,
          [
            LuxeColors.platinumHi.withValues(alpha: 0.85 * appear),
            palette[1].withValues(alpha: 0.85 * appear),
            palette[2].withValues(alpha: 0.6 * appear),
          ],
          const [0.0, 0.6, 1.0],
        ),
    );

    // Zones lock as the beam has passed them.
    for (final (z, seen) in [
      (socZone, beam > template.soc.bottom),
      (odoZone, beam > template.odo.bottom),
    ]) {
      if (!seen) continue;
      final k = lock.clamp(0.0, 1.2);
      final box = RRect.fromRectAndRadius(
        z.inflate(4 + 6 * (1 - k.clamp(0.0, 1.0))),
        const Radius.circular(10),
      );
      canvas.drawRRect(
        box,
        Paint()..color = palette[1].withValues(alpha: 0.14 * k.clamp(0.0, 1.0)),
      );
      canvas.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = palette[0].withValues(alpha: 0.9 * k.clamp(0.0, 1.0)),
      );
    }

    // Results lift out under the glass.
    if (results > 0) {
      final y = glass.bottom + 0.05 * s + 14 * (1 - results);
      final chips = ['68%', '4 818 km'];
      var total = 0.0;
      final painters = [
        for (final label in chips)
          TextPainter(
            text: TextSpan(
              text: label,
              style: TextStyle(
                fontSize: 0.05 * s,
                fontWeight: FontWeight.w600,
                color: PlanColors.ink,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(),
      ];
      for (final tp in painters) {
        total += tp.width + 0.07 * s;
      }
      total += 0.03 * s * (painters.length - 1);
      var x = size.width / 2 - total / 2;
      for (var i = 0; i < painters.length; i++) {
        final tp = painters[i];
        final chip = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, tp.width + 0.07 * s, tp.height + 0.03 * s),
          const Radius.circular(99),
        );
        final a = _p(0.74 + 0.06 * i, 1.0);
        canvas.saveLayer(
          chip.outerRect.inflate(20),
          Paint()..color = Colors.white.withValues(alpha: a),
        );
        canvas.drawRRect(
          chip,
          Paint()
            ..shader = ui.Gradient.linear(
              chip.outerRect.centerLeft,
              chip.outerRect.centerRight,
              palette,
              const [0.0, 0.5, 1.0],
            ),
        );
        tp.paint(canvas, Offset(x + 0.035 * s, y + 0.015 * s));
        canvas.restore();
        x += chip.width + 0.03 * s;
      }
    }
  }

  @override
  bool shouldRepaint(_ScanPainter old) =>
      old.enter != enter || old.palette != palette;
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGE 4 — Pinova Bot with a short, confirmed conversation.
// ═══════════════════════════════════════════════════════════════════════════

class _BotScene extends StatelessWidget {
  const _BotScene({required this.enter, required this.palette});
  final double enter;
  final List<Color> palette;

  double _phase(double a, double b) => _seg(enter, a, b);

  Widget _pop(double t, Alignment origin, Widget child) => Opacity(
    opacity: t.clamp(0.0, 1.0),
    child: Transform.scale(
      scale: 0.88 + 0.12 * t,
      alignment: origin,
      child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final s = c.biggest.shortestSide;
      final scale = (s / 300).clamp(0.6, 1.2);
      final glow = math.sin(_phase(0.0, 1.0) * math.pi);
      return MediaQuery.withNoTextScaling(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Pinova Bot stands bottom-right on a pool of the scene's light;
            // the conversation stacks to its left without covering it.
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
                    Positioned(
                      bottom: -s * 0.05,
                      child: Container(
                        width: s * 0.42,
                        height: s * 0.42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              palette[0].withValues(alpha: 0.22 + 0.12 * glow),
                              palette[1].withValues(alpha: 0.06),
                              palette[1].withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.6, 1.0],
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
                _phase(0.18, 0.46),
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
                _phase(0.38, 0.66),
                Alignment.bottomRight,
                _Bubble(
                  scale: scale,
                  text: 'Bật sạc 2 giờ',
                  mine: true,
                  palette: palette,
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: s * 0.42,
              width: s * 0.64,
              child: _pop(
                _phase(0.58, 0.9),
                Alignment.topLeft,
                _ConfirmCard(scale: scale, palette: palette, glow: glow),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.scale,
    this.mine = false,
    this.palette,
  });
  final String text;
  final double scale;
  final bool mine;
  final List<Color>? palette;

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
          ? LinearGradient(colors: palette ?? SceneColors.scenes.last)
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
        color: mine ? PlanColors.ink : LuxeColors.text,
      ),
    ),
  );
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({
    required this.scale,
    required this.palette,
    required this.glow,
  });
  final double scale;
  final List<Color> palette;
  final double glow;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(12 * scale),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16 * scale),
      color: const Color(0xE6101113),
      border: Border.all(color: palette[0].withValues(alpha: 0.6)),
      boxShadow: [
        BoxShadow(
          color: palette[1].withValues(alpha: 0.12 + 0.12 * glow),
          blurRadius: 26,
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.bolt_rounded, size: 16 * scale, color: palette[0]),
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

  Widget _chip(String label, double scale, {required bool filled}) => Container(
    padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(99),
      gradient: filled ? LinearGradient(colors: palette) : null,
      border: filled ? null : Border.all(color: LuxeColors.hairlineStrong),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5 * scale,
        fontWeight: FontWeight.w600,
        color: filled ? PlanColors.ink : LuxeColors.muted,
      ),
    ),
  );
}
