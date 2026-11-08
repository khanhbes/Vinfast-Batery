import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/entitlement_provider.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/theme/plan_style.dart';
import '../../data/models/entitlement.dart';
import '../auth/auth_providers.dart';

/// Plays a short plan change once (QA 140): the new plan's light sweeps the
/// screen, its medallion and name arrive, then three of its benefits; about
/// five seconds, a tap skips it, and with "reduce motion" it is a still card
/// for two seconds. The plan last seen is kept per account on this phone,
/// so the first sight of an account (or a reinstall) plays nothing.
class PlanTransitionHost extends ConsumerStatefulWidget {
  const PlanTransitionHost({super.key, required this.child});
  final Widget child;

  static String seenKey(String uid) => 'plan_seen_v1_$uid';

  @override
  ConsumerState<PlanTransitionHost> createState() => _PlanTransitionHostState();
}

class _PlanTransitionHostState extends ConsumerState<PlanTransitionHost> {
  ({PlanTier from, PlanTier to})? _playing;
  String? _checkedFor;

  Future<void> _check(String uid, PlanTier tier) async {
    final key = '$uid/${tier.name}';
    if (_checkedFor == key) return;
    _checkedFor = key;
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getString(PlanTransitionHost.seenKey(uid));
      await prefs.setString(PlanTransitionHost.seenKey(uid), tier.name);
      final from = PlanTier.values.where((t) => t.name == seen).firstOrNull;
      if (from == null || from == tier || !mounted) return;
      setState(() => _playing = (from: from, to: tier));
    } on Object {
      // A missed animation is fine; the plan itself is already applied.
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final plan = ref.watch(entitlementProvider);
    if (uid != null && plan.known) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_check(uid, plan.tier)),
      );
    }
    final playing = _playing;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (playing != null)
          PlanTransitionOverlay(
            key: ValueKey('plan-transition-${playing.to.name}'),
            from: playing.from,
            to: playing.to,
            onDone: () => setState(() => _playing = null),
          ),
      ],
    );
  }
}

/// The plan change as a short film (QA 149): the screen dims, a ring of the
/// new plan's light bursts out with a scatter of sparks (upgrades only), the
/// medallion lands and turns to rest, the name writes itself in and catches
/// one glint, the benefits check in one by one, and the whole card zooms
/// past the viewer back into the app. About five seconds; a tap ends it;
/// under "reduce motion" it is a still card for two seconds.
class PlanTransitionOverlay extends StatefulWidget {
  const PlanTransitionOverlay({
    super.key,
    required this.from,
    required this.to,
    required this.onDone,
  });

  final PlanTier from;
  final PlanTier to;
  final VoidCallback onDone;

  static const duration = Duration(milliseconds: 5000);
  static const stillDuration = Duration(seconds: 2);

  @override
  State<PlanTransitionOverlay> createState() => _PlanTransitionOverlayState();
}

class _PlanTransitionOverlayState extends State<PlanTransitionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: PlanTransitionOverlay.duration,
  );
  Timer? _still;
  bool _started = false;
  bool _reduced = false;

  bool get _upgrade => widget.to.index > widget.from.index;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    HapticFeedback.mediumImpact();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) {
      _t.value = 0.72; // everything shown, nothing moving
      _still = Timer(PlanTransitionOverlay.stillDuration, _finish);
    } else {
      _t.forward().whenComplete(_finish);
      // A second, softer beat as the medallion lands.
      Timer(const Duration(milliseconds: 1100), () {
        if (mounted && _upgrade) HapticFeedback.lightImpact();
      });
    }
  }

  void _finish() {
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _still?.cancel();
    _t.dispose();
    super.dispose();
  }

  /// 0..1 progress of [t] inside the [a, b] slice of the timeline.
  static double _seg(
    double t,
    double a,
    double b, [
    Curve c = Curves.easeOutCubic,
  ]) => c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  List<String> get _benefits => widget.to == PlanTier.free
      ? const [
          'Sạc an toàn, sạc theo giờ và quét đồng hồ vẫn dùng được',
          'Dừng sạc và mọi ngắt an toàn không bao giờ bị khóa',
          'Nâng gói lại bất cứ lúc nào ở Cài đặt → Pinova Premium',
        ]
      : [
          for (final f in PremiumFeature.values)
            if (f.tier == widget.to) f.label,
        ].take(3).toList();

  @override
  Widget build(BuildContext context) {
    final plan = PlanStyle.forTier(widget.to);
    final colors = plan.accentColors;
    final title = 'Pinova ${widget.to.label}';
    final subtitle = _upgrade
        ? 'Đã nâng lên gói ${widget.to.label}'
        : widget.to == PlanTier.free
        ? 'Đã chuyển về gói Free'
        : 'Đã chuyển sang gói ${widget.to.label}';
    return Semantics(
      liveRegion: true,
      label: '$subtitle. ${_benefits.join('. ')}. Chạm để đóng.',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('plan-transition'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _t.stop();
          _finish();
        },
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final t = _t.value;
            final enter = _seg(t, 0, 0.1);
            // The close: the card rushes past the viewer as it fades.
            final out = _seg(t, 0.9, 1.0, Curves.easeInCubic);
            final veil = enter * (1 - out);
            final medal = _seg(t, 0.1, 0.34, Curves.easeOutBack);
            final settle = _seg(t, 0.1, 0.5, Curves.easeOutCubic);
            final eyebrow = _seg(t, 0.24, 0.42);
            final name = _seg(t, 0.28, 0.5, LuxeMotion.enter);
            final glint = _seg(t, 0.48, 0.66, Curves.easeInOutCubic);
            return Opacity(
              opacity: veil,
              child: Material(
                color: Colors.transparent,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: LuxeColors.background.withValues(alpha: 0.94),
                    ),
                    CustomPaint(
                      painter: _StagePainter(
                        t: t,
                        colors: colors,
                        glow: plan.glow,
                        burst: _upgrade && !_reduced,
                      ),
                    ),
                    SafeArea(
                      child: Center(
                        child: Transform.scale(
                          scale: 1 + 0.08 * out,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Transform.scale(
                                  scale: 0.4 + 0.6 * medal,
                                  child: Opacity(
                                    opacity: medal.clamp(0.0, 1.0),
                                    child: SizedBox.square(
                                      dimension: 140,
                                      child: CustomPaint(
                                        painter: _MedalPainter(
                                          // One turn that slows to rest.
                                          turn: 1.6 * (1 - settle),
                                          colors: colors,
                                          flash: math.sin(
                                            _seg(t, 0.2, 0.5) * math.pi,
                                          ),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            widget.to == PlanTier.free
                                                ? Icons.shield_rounded
                                                : Icons
                                                      .workspace_premium_rounded,
                                            size: 54,
                                            color: plan.accent,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 26),
                                Opacity(
                                  opacity: eyebrow,
                                  child: Text(
                                    subtitle.toUpperCase(),
                                    textAlign: TextAlign.center,
                                    style: LuxeText.eyebrow.copyWith(
                                      letterSpacing: 2.2 + 4 * (1 - eyebrow),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _PlanName(
                                  text: title,
                                  colors: colors,
                                  reveal: name,
                                  glint: glint,
                                ),
                                const SizedBox(height: 24),
                                for (var i = 0; i < _benefits.length; i++)
                                  _Benefit(
                                    text: _benefits[i],
                                    colors: colors,
                                    shown: _seg(
                                      t,
                                      0.46 + i * 0.07,
                                      0.6 + i * 0.07,
                                      LuxeMotion.enter,
                                    ),
                                    check: _seg(
                                      t,
                                      0.5 + i * 0.07,
                                      0.62 + i * 0.07,
                                      Curves.easeInOutCubic,
                                    ),
                                  ),
                                const SizedBox(height: 22),
                                Opacity(
                                  opacity: _seg(t, 0.64, 0.76),
                                  child: const Text(
                                    'Chạm để tiếp tục',
                                    style: LuxeText.caption,
                                  ),
                                ),
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
          },
        ),
      ),
    );
  }
}

/// The plan's name in its gradient, wiped in left to right out of a soft
/// edge, then crossed once by a white glint.
class _PlanName extends StatelessWidget {
  const _PlanName({
    required this.text,
    required this.colors,
    required this.reveal,
    required this.glint,
  });
  final String text;
  final List<Color> colors;
  final double reveal;
  final double glint;

  @override
  Widget build(BuildContext context) {
    final g = glint > 0 && glint < 1 ? glint : null;
    return Transform.translate(
      offset: Offset(0, 16 * (1 - reveal)),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => LinearGradient(
          colors: const [Colors.white, Color(0x00FFFFFF)],
          stops: [
            (reveal * 1.25 - 0.25).clamp(0.0, 1.0),
            (reveal * 1.25).clamp(0.0, 1.0),
          ],
        ).createShader(r),
        child: ShaderMask(
          shaderCallback: (r) => LinearGradient(
            colors: g == null
                ? colors
                : [
                    colors.first,
                    colors[1],
                    Colors.white,
                    colors[1],
                    colors.last,
                  ],
            stops: g == null
                ? null
                : [
                    0.0,
                    (g - 0.12).clamp(0.0, 1.0),
                    g.clamp(0.0, 1.0),
                    (g + 0.12).clamp(0.0, 1.0),
                    1.0,
                  ],
          ).createShader(r),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w300,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.text,
    required this.colors,
    required this.shown,
    required this.check,
  });
  final String text;
  final List<Color> colors;
  final double shown;
  final double check;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: shown,
    child: Transform.translate(
      offset: Offset(-22 * (1 - shown), 0),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 20,
              child: CustomPaint(
                painter: _CheckPainter(progress: check, colors: colors),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  color: LuxeColors.text,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A tick that draws itself, in the plan's gradient.
class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress, required this.colors});
  final double progress;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final path = Path()
      ..moveTo(0.18 * s, 0.52 * s)
      ..lineTo(0.42 * s, 0.74 * s)
      ..lineTo(0.84 * s, 0.28 * s);
    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = LinearGradient(
          colors: colors,
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}

/// The stage: a soft pool of the plan's colour, the diagonal sweep of light,
/// and for an upgrade a ring bursting out with a scatter of sparks.
class _StagePainter extends CustomPainter {
  _StagePainter({
    required this.t,
    required this.colors,
    required this.glow,
    required this.burst,
  });
  final double t;
  final List<Color> colors;
  final Color glow;
  final bool burst;

  static double _seg(
    double t,
    double a,
    double b, [
    Curve c = Curves.easeOutCubic,
  ]) => c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  static final _sparks = () {
    final random = math.Random(7);
    return [
      for (var i = 0; i < 44; i++)
        (
          random.nextDouble() * 2 * math.pi,
          0.35 + random.nextDouble() * 0.65,
          1.0 + random.nextDouble() * 2.2,
          random.nextInt(3),
        ),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.36);
    final reach = size.longestSide * 0.7;

    // Pool of the plan's colour that blooms in and stays.
    final pool = _seg(t, 0.04, 0.4);
    canvas.drawCircle(
      c,
      size.width * 0.8,
      Paint()
        ..shader = RadialGradient(
          colors: [
            glow.withValues(alpha: 0.26 * pool),
            colors.last.withValues(alpha: 0.08 * pool),
            glow.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: size.width * 0.8)),
    );

    // Diagonal sweep of light, once.
    final sweep = _seg(t, 0.12, 0.48, Curves.easeInOutCubic);
    if (sweep > 0 && sweep < 1) {
      final d = size.width + size.height;
      final x = -size.height + d * sweep;
      final band = Path()
        ..moveTo(x, 0)
        ..lineTo(x + size.width * 0.35, 0)
        ..lineTo(x + size.width * 0.35 - size.height, size.height)
        ..lineTo(x - size.height, size.height)
        ..close();
      canvas.drawPath(
        band,
        Paint()
          ..shader = LinearGradient(
            colors: [
              colors.first.withValues(alpha: 0),
              ...colors.map((c) => c.withValues(alpha: 0.26)),
              colors.last.withValues(alpha: 0),
            ],
          ).createShader(band.getBounds())
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
      );
    }

    if (!burst) return;
    // The ring that announces the plan: two waves out from the medallion.
    for (final (start, alpha) in [(0.1, 0.7), (0.17, 0.4)]) {
      final w = _seg(t, start, start + 0.36, Curves.easeOutCubic);
      if (w <= 0 || w >= 1) continue;
      final r = 30 + reach * w;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + 10 * (1 - w)
          ..shader = SweepGradient(
            colors: [...colors, colors.first],
          ).createShader(Rect.fromCircle(center: c, radius: r))
          ..color = Colors.white.withValues(alpha: alpha * (1 - w))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 8 * w),
      );
    }

    // Sparks fly out, slow down and fade.
    final fly = _seg(t, 0.11, 0.56, Curves.easeOutQuart);
    if (fly > 0 && fly < 1) {
      for (final (angle, speed, radius, hue) in _sparks) {
        final dist = 40 + reach * 0.62 * speed * fly;
        final p = c + Offset(math.cos(angle), math.sin(angle)) * dist;
        final fade = (1 - fly) * math.min(1.0, fly * 6);
        final color = colors[hue % colors.length];
        canvas.drawCircle(
          p,
          radius * 2.4,
          Paint()
            ..color = color.withValues(alpha: 0.35 * fade)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        canvas.drawCircle(
          p,
          radius * 0.7,
          Paint()..color = Colors.white.withValues(alpha: 0.9 * fade),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_StagePainter old) => old.t != t;
}

/// Brushed ring in the plan's gradient, turning to rest, with a flash of
/// light inside as it lands.
class _MedalPainter extends CustomPainter {
  _MedalPainter({
    required this.turn,
    required this.colors,
    required this.flash,
  });
  final double turn;
  final List<Color> colors;
  final double flash;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 8;
    final rect = Rect.fromCircle(center: c, radius: r);
    final shader = SweepGradient(
      colors: [...colors, colors.first],
      transform: GradientRotation(turn * 2 * math.pi),
    ).createShader(rect);
    canvas.drawCircle(
      c,
      r - 4,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colors[1].withValues(alpha: 0.10 + 0.25 * flash),
            colors.last.withValues(alpha: 0.04),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..shader = shader
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + 8 * flash),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..shader = shader,
    );
    canvas.drawCircle(
      c,
      r - 12,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(_MedalPainter old) =>
      old.turn != turn || old.flash != flash;
}
