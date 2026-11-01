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

  bool get _upgrade => widget.to.index > widget.from.index;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    HapticFeedback.mediumImpact();
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.value = 0.6; // everything shown, nothing moving
      _still = Timer(PlanTransitionOverlay.stillDuration, _finish);
    } else {
      _t.forward().whenComplete(_finish);
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
            final enter = _seg(t, 0, 0.12);
            final exit = 1 - _seg(t, 0.9, 1.0, Curves.easeInCubic);
            final fade = enter * exit;
            final sweep = _seg(t, 0.06, 0.42, Curves.easeInOutCubic);
            final medal = _seg(t, 0.12, 0.34, Curves.easeOutBack);
            final name = _seg(t, 0.26, 0.46);
            return Opacity(
              opacity: fade,
              child: Material(
                color: Colors.transparent,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: LuxeColors.background.withValues(alpha: 0.92),
                    ),
                    CustomPaint(
                      painter: _SweepPainter(
                        progress: sweep,
                        colors: plan.accentColors,
                        glow: plan.glow,
                      ),
                    ),
                    SafeArea(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.scale(
                                scale: 0.6 + 0.4 * medal,
                                child: Opacity(
                                  opacity: medal.clamp(0.0, 1.0),
                                  child: SizedBox.square(
                                    dimension: 132,
                                    child: CustomPaint(
                                      painter: _MedalPainter(
                                        turn: t,
                                        colors: plan.accentColors,
                                      ),
                                      child: Center(
                                        child: Icon(
                                          widget.to == PlanTier.free
                                              ? Icons.shield_rounded
                                              : Icons.workspace_premium_rounded,
                                          size: 52,
                                          color: plan.accent,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 26),
                              Opacity(
                                opacity: name,
                                child: Transform.translate(
                                  offset: Offset(0, 18 * (1 - name)),
                                  child: Column(
                                    children: [
                                      Text(
                                        subtitle.toUpperCase(),
                                        textAlign: TextAlign.center,
                                        style: LuxeText.eyebrow,
                                      ),
                                      const SizedBox(height: 8),
                                      ShaderMask(
                                        shaderCallback: (r) => LinearGradient(
                                          colors: plan.accentColors,
                                        ).createShader(r),
                                        child: Text(
                                          title,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 34,
                                            fontWeight: FontWeight.w300,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              for (var i = 0; i < _benefits.length; i++)
                                _Benefit(
                                  text: _benefits[i],
                                  accent: plan.accent,
                                  shown: _seg(
                                    t,
                                    0.44 + i * 0.08,
                                    0.6 + i * 0.08,
                                  ),
                                ),
                              const SizedBox(height: 22),
                              Opacity(
                                opacity: _seg(t, 0.6, 0.72),
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

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.text,
    required this.accent,
    required this.shown,
  });
  final String text;
  final Color accent;
  final double shown;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: shown,
    child: Transform.translate(
      offset: Offset(0, 12 * (1 - shown)),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 18, color: accent),
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

/// A diagonal band of the plan's light crossing the screen once.
class _SweepPainter extends CustomPainter {
  _SweepPainter({
    required this.progress,
    required this.colors,
    required this.glow,
  });
  final double progress;
  final List<Color> colors;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) {
      // A soft pool of the plan's colour stays behind the medallion.
      if (progress >= 1) _pool(canvas, size, 1);
      return;
    }
    _pool(canvas, size, progress);
    final d = size.width + size.height;
    final x = -size.height + d * progress;
    final band = Path()
      ..moveTo(x, 0)
      ..lineTo(x + size.width * 0.35, 0)
      ..lineTo(x + size.width * 0.35 - size.height, size.height)
      ..lineTo(x - size.height, size.height)
      ..close();
    final bounds = band.getBounds();
    canvas.drawPath(
      band,
      Paint()
        ..shader = LinearGradient(
          colors: [
            colors.first.withValues(alpha: 0),
            ...colors.map((c) => c.withValues(alpha: 0.28)),
            colors.last.withValues(alpha: 0),
          ],
        ).createShader(bounds)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
  }

  void _pool(Canvas canvas, Size size, double k) {
    final c = Offset(size.width / 2, size.height * 0.36);
    canvas.drawCircle(
      c,
      size.width * 0.7,
      Paint()
        ..shader = RadialGradient(
          colors: [
            glow.withValues(alpha: 0.22 * k),
            glow.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: size.width * 0.7)),
    );
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.progress != progress;
}

/// Brushed ring in the plan's gradient, turning a little as it settles.
class _MedalPainter extends CustomPainter {
  _MedalPainter({required this.turn, required this.colors});
  final double turn;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 6;
    final rect = Rect.fromCircle(center: c, radius: r);
    final shader = SweepGradient(
      colors: [...colors, colors.first],
      transform: GradientRotation(turn * math.pi),
    ).createShader(rect);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = shader,
    );
    canvas.drawCircle(c, r - 10, Paint()..color = const Color(0x14FFFFFF));
  }

  @override
  bool shouldRepaint(_MedalPainter old) => old.turn != turn;
}
