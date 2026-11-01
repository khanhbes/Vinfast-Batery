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

  // QA 140 (owner's choice): Ultra takes Viber-like pink → violet → blue
  // instead of the violet/cyan/emerald aurora.
  static const pink = Color(0xFFF27FE0);
  static const violet = Color(0xFFA66CFF);
  static const lavender = Color(0xFFB98BFF);
  static const blue = Color(0xFF6C74FF);
  static const cyan = blue;

  /// Ultra's gradient; drawn mirrored so it flows without a seam where it
  /// moves (the Premium page only, QA 140).
  static const aurora = [pink, violet, blue];

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
    glassColors: [Color(0x1AA66CFF), Color(0x0AF27FE0)],
    glassBorder: Color(0x40B98BFF),
    ambient: Color(0xFF19122C),
    glow: PlanColors.violet,
    glowAlt: PlanColors.pink,
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
    this.effects = false,
  });

  /// QA 140: Ultra's effects on interaction and on real activity (dragging
  /// a knob, holding the charge button, Pinova Bot answering, charging),
  /// separate from the ambient colour flow, which now runs only where Ultra
  /// is advertised (the Premium page).
  final bool effects;

  /// Ultra + effects on + motion allowed, in a shown subtree.
  static bool effectsOf(BuildContext context) {
    final motion = context.dependOnInheritedWidgetOfExactType<PlanMotion>();
    return (motion?.effects ?? false) && TickerMode.valuesOf(context).enabled;
  }

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
      running != oldWidget.running ||
      effects != oldWidget.effects ||
      phase != oldWidget.phase;
}

class PlanMotionHost extends StatefulWidget {
  const PlanMotionHost({
    super.key,
    required this.running,
    required this.child,
    this.period = defaultPeriod,
    this.effects = false,
  });

  final bool running;

  /// See [PlanMotion.effects].
  final bool effects;
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
  Widget build(BuildContext context) => PlanMotion(
    phase: _phase,
    running: widget.running,
    effects: widget.effects,
    child: widget.child,
  );
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

/// QA 140: the plan's colour for everything that is not a status. Emerald
/// stays "verified / charging", champagne an estimate, rose an error; any
/// other highlight (selection, links, charts, buttons, loaders) follows the
/// plan on every screen.
extension PlanAccentContext on BuildContext {
  PlanStyle get plan => PlanStyle.of(this);
  Color get planAccent => plan.accent;
  Color get planAccentDeep => plan.accentDeep;
  Color get planAccentGlow => plan.accentGlow;
  Color get planAccentSoft => plan.accentSoft;
  Color get planAccentTint => plan.accentTint;
}

/// The accent's shades, for painters that receive a [PlanStyle] or colour.
extension PlanAccentShades on PlanStyle {
  Color get accentDeep => accentColors.last;
  Color get accentGlow => accent.withValues(alpha: 0x55 / 255);
  Color get accentSoft => accent.withValues(alpha: 0x33 / 255);
  Color get accentTint => accent.withValues(alpha: 0x1A / 255);
}
