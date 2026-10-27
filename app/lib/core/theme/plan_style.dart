import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../data/models/entitlement.dart';
import 'luxe_theme.dart';

/// Per-plan colours (QA 136). Free keeps LUXE (black, platinum, emerald);
/// Pro is brushed silver with a steel edge; Ultra is an aurora of violet,
/// cyan and emerald. Status colours never change with the plan: emerald is
/// still "verified", rose an error, champagne an estimate.
abstract final class PlanColors {
  static const silverHi = Color(0xFFF4F6FA);
  static const silver = Color(0xFFC9D2E0);
  static const steel = Color(0xFF8FA9D6);
  static const steelText = Color(0xFFB4C6E6);

  static const violet = Color(0xFF8B5CF6);
  static const lavender = Color(0xFFB4A2FF);
  static const cyan = Color(0xFF22D3EE);

  /// One aurora loop; drawn mirrored so it flows without a seam.
  static const aurora = [violet, cyan, LuxeColors.emerald];

  /// Text on silver or aurora fills (≥4.5:1 on every stop).
  static const ink = Color(0xFF0B0C14);
}

/// The plan's look, read by the core kit (backdrop, glass, buttons, tab bar,
/// tags, charts) through the theme. `PlanStyle.of(context)`.
@immutable
class PlanStyle extends ThemeExtension<PlanStyle> {
  const PlanStyle._({
    required this.tier,
    required this.accent,
    required this.accentColors,
    required this.glassColors,
    required this.glassBorder,
    required this.ambient,
    required this.glow,
    this.glowAlt,
  });

  final PlanTier tier;

  /// Accent for controls (switch, slider, focus, selected tab). Not a status.
  final Color accent;

  /// Fill of primary buttons, tags, rings and chart bars.
  final List<Color> accentColors;
  final List<Color> glassColors;
  final Color glassBorder;

  /// Backdrop: the pool of light at the top and the corner glow(s).
  final Color ambient;
  final Color glow;
  final Color? glowAlt;

  bool get isUltra => tier == PlanTier.ultra;
  bool get isPro => tier == PlanTier.pro;

  static const free = PlanStyle._(
    tier: PlanTier.free,
    // QA 139: platinum, so emerald means "verified" only.
    accent: LuxeColors.platinumHi,
    accentColors: [
      LuxeColors.platinumHi,
      LuxeColors.platinum,
      Color(0xFFB9BCC1),
    ],
    glassColors: [Color(0x12FFFFFF), Color(0x06FFFFFF)],
    glassBorder: LuxeColors.hairline,
    ambient: LuxeColors.ambient,
    glow: LuxeColors.emerald,
  );

  static const pro = PlanStyle._(
    tier: PlanTier.pro,
    accent: PlanColors.steelText,
    accentColors: [PlanColors.silverHi, PlanColors.silver, PlanColors.steel],
    glassColors: [Color(0x16C9D2E0), Color(0x078FA9D6)],
    glassBorder: Color(0x33B4C6E6),
    ambient: Color(0xFF161B24),
    glow: PlanColors.steel,
  );

  static const ultra = PlanStyle._(
    tier: PlanTier.ultra,
    accent: PlanColors.lavender,
    accentColors: PlanColors.aurora,
    glassColors: [Color(0x188B5CF6), Color(0x0A22D3EE)],
    glassBorder: Color(0x40A99BFF),
    ambient: Color(0xFF17132B),
    glow: PlanColors.cyan,
    glowAlt: PlanColors.violet,
  );

  static PlanStyle forTier(PlanTier tier) => switch (tier) {
    PlanTier.free => free,
    PlanTier.pro => pro,
    PlanTier.ultra => ultra,
  };

  static PlanStyle of(BuildContext context) =>
      Theme.of(context).extension<PlanStyle>() ?? free;

  @override
  PlanStyle copyWith() => this;

  @override
  PlanStyle lerp(covariant PlanStyle? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

/// Ultra's slow colour clock (QA 136): one ticker for the whole app, placed
/// above the navigator. Runs only for Ultra with effects on, without the
/// system "reduce motion", and paints at most ~25 times a second.
class PlanMotion extends InheritedWidget {
  const PlanMotion({
    super.key,
    required this.phase,
    required this.running,
    required super.child,
  });

  /// 0..1, one loop every [PlanMotionHost.period].
  final ValueListenable<double> phase;
  final bool running;

  static final ValueNotifier<double> _still = ValueNotifier(0.18);

  /// The clock and whether it moves here (paused under TickerMode, e.g. a
  /// tab that is not shown).
  static ({ValueListenable<double> phase, bool running}) of(
    BuildContext context,
  ) {
    final motion = context.dependOnInheritedWidgetOfExactType<PlanMotion>();
    final running =
        (motion?.running ?? false) && TickerMode.valuesOf(context).enabled;
    return (phase: running ? motion!.phase : _still, running: running);
  }

  @override
  bool updateShouldNotify(PlanMotion oldWidget) =>
      running != oldWidget.running || phase != oldWidget.phase;
}

class PlanMotionHost extends StatefulWidget {
  const PlanMotionHost({
    super.key,
    required this.running,
    required this.child,
    this.period = defaultPeriod,
  });

  final bool running;
  final Widget child;

  /// One colour loop.
  final Duration period;

  static const defaultPeriod = Duration(seconds: 12);

  @override
  State<PlanMotionHost> createState() => _PlanMotionHostState();
}

class _PlanMotionHostState extends State<PlanMotionHost>
    with SingleTickerProviderStateMixin {
  final _phase = ValueNotifier<double>(0.18);
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  Duration _offset = Duration.zero;
  Duration _seen = Duration.zero;

  void _tick(Duration elapsed) {
    _seen = elapsed;
    // ~25 fps is plenty for a 12 s colour drift and saves battery.
    if (elapsed - _last < const Duration(milliseconds: 40)) return;
    _last = elapsed;
    final total = (_offset + elapsed).inMicroseconds;
    final period = widget.period.inMicroseconds;
    _phase.value = (total % period) / period;
  }

  void _sync() {
    if (widget.running && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!widget.running && _ticker.isActive) {
      _offset += _seen;
      _seen = Duration.zero;
      _ticker.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PlanMotionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PlanMotion(phase: _phase, running: widget.running, child: widget.child);
}

/// Builds [builder] with the Ultra clock: every frame of the clock when it
/// runs, once otherwise. Keep the subtree small.
class PlanFlow extends StatelessWidget {
  const PlanFlow({super.key, required this.builder});

  final Widget Function(BuildContext context, double phase) builder;

  @override
  Widget build(BuildContext context) {
    final motion = PlanMotion.of(context);
    if (!motion.running) return builder(context, motion.phase.value);
    return ValueListenableBuilder<double>(
      valueListenable: motion.phase,
      builder: (context, phase, _) => builder(context, phase),
    );
  }
}

/// A gradient that flows sideways with [phase] (0..1 is one seamless loop).
LinearGradient planFlowGradient(
  double phase, {
  List<Color> colors = PlanColors.aurora,
  AlignmentGeometry begin = Alignment.centerLeft,
  AlignmentGeometry end = Alignment.centerRight,
}) => LinearGradient(
  begin: begin,
  end: end,
  colors: colors,
  tileMode: TileMode.mirror,
  transform: _SlideGradient(phase),
);

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.phase);
  final double phase;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      // A mirrored gradient repeats every two widths.
      Matrix4.translationValues(bounds.width * 2 * phase, 0, 0);
}
