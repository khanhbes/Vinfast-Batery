import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/luxe_theme.dart';

/// LUXE kit (Task 117): the shared primitives every pushed screen, sheet and
/// state view is built from, so legacy screens adopt the platinum language
/// without re-deriving it. Purely presentational; all motion is one-shot (or
/// tied to a real state such as loading) and instant under reduced motion.

bool luxeReduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

Duration luxeDuration(BuildContext context, int ms) =>
    luxeReduceMotion(context) ? Duration.zero : Duration(milliseconds: ms);

// ─────────────────────────────────────────────────────────────────────────
// Page chrome
// ─────────────────────────────────────────────────────────────────────────

/// Round glass icon button with a 48dp target and hairline rim.
class LuxeCircleButton extends StatelessWidget {
  const LuxeCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = LuxeColors.text,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      excludeSemantics: true,
      onTap: onPressed,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Ink(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: LuxeColors.glass,
              border: Border.all(color: LuxeColors.hairline),
            ),
            child: Icon(
              icon,
              size: 20,
              color: onPressed == null ? LuxeColors.dim : color,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Transparent app bar for pushed screens: glass back button, quiet title.
class LuxeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LuxeAppBar({
    super.key,
    this.title,
    this.actions,
    this.bottom,
    this.onBack,
    this.showBack = true,
  });

  final String? title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final VoidCallback? onBack;
  final bool showBack;

  @override
  Size get preferredSize =>
      Size.fromHeight(64 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;
    return AppBar(
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleSpacing: showBack && canPop ? 4 : 20,
      leadingWidth: 68,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      leading: showBack && canPop
          ? Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Center(
                child: LuxeCircleButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Quay lại',
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                ),
              ),
            )
          : null,
      title: title == null
          ? null
          : Text(
              title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: LuxeColors.text,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
      actions: [
        if (actions != null)
          for (final a in actions!) ...[a, const SizedBox(width: 4)],
        const SizedBox(width: 12),
      ],
      bottom: bottom,
    );
  }
}

/// Screen frame for pushed LUXE screens: the splash-continuous backdrop under
/// a transparent scaffold. Screens keep their own body widgets.
class LuxeScaffold extends StatelessWidget {
  const LuxeScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.title,
    this.actions,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.resizeToAvoidBottomInset,
    this.backdropAccent = 1,
  });

  final Widget body;

  /// Custom app bar; when null and [title] or [actions] is set, a
  /// [LuxeAppBar] is built.
  final PreferredSizeWidget? appBar;
  final String? title;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool? resizeToAvoidBottomInset;
  final double backdropAccent;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: LuxeBackdrop(accent: backdropAccent)),
      Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        appBar:
            appBar ??
            (title != null || actions != null
                ? LuxeAppBar(title: title, actions: actions)
                : null),
        body: body,
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
      ),
    ],
  );
}

/// Page heading without navigation (pair with [LuxeAppBar]): eyebrow,
/// title and an optional caption.
class LuxePageHeaderText extends StatelessWidget {
  const LuxePageHeaderText({
    super.key,
    required this.title,
    this.eyebrow,
    this.caption,
  });

  final String title;
  final String? eyebrow;
  final String? caption;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (eyebrow != null) ...[
        Text(eyebrow!.toUpperCase(), style: LuxeText.eyebrow),
        const SizedBox(height: 6),
      ],
      Text(title, style: LuxeText.title),
      if (caption != null) ...[
        const SizedBox(height: 6),
        Text(caption!, style: LuxeText.caption),
      ],
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────
// Sheets
// ─────────────────────────────────────────────────────────────────────────

/// Short platinum grab handle used at the top of LUXE sheets.
class LuxeSheetHandle extends StatelessWidget {
  const LuxeSheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      decoration: BoxDecoration(
        color: LuxeColors.platinumLow,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// Sheet header: eyebrow, title and optional caption.
class LuxeSheetHeader extends StatelessWidget {
  const LuxeSheetHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.caption,
    this.trailing,
  });

  final String title;
  final String? eyebrow;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null) ...[
              Text(eyebrow!.toUpperCase(), style: LuxeText.eyebrow),
              const SizedBox(height: 6),
            ],
            Text(title, style: LuxeText.title.copyWith(fontSize: 22)),
            if (caption != null) ...[
              const SizedBox(height: 6),
              Text(caption!, style: LuxeText.caption),
            ],
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

/// The dim behind every sheet (QA 139: sheets used 54, 72 and 75 %).
const luxeSheetBarrier = Color(0xB8000000);

/// Opens a LUXE modal bottom sheet: dark glass body, hairline top rim and a
/// platinum handle. [builder] supplies the content below the handle.
/// Sheets that draw their own frame use [LuxeColors.sheet], a 28 radius and
/// [luxeSheetBarrier] too (QA 139).
Future<T?> showLuxeSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
  Clip? clipBehavior,
}) => showModalBottomSheet<T>(
  context: context,
  clipBehavior: clipBehavior,
  isScrollControlled: isScrollControlled,
  useSafeArea: useSafeArea,
  isDismissible: isDismissible,
  enableDrag: enableDrag,
  useRootNavigator: useRootNavigator,
  showDragHandle: false,
  barrierColor: luxeSheetBarrier,
  backgroundColor: LuxeColors.sheet,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    side: BorderSide(color: LuxeColors.hairline),
  ),
  builder: (ctx) => Theme(
    data: LuxeTheme.of(ctx),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LuxeSheetHandle(),
        Flexible(child: builder(ctx)),
      ],
    ),
  ),
);

// ─────────────────────────────────────────────────────────────────────────
// Numbers & stats
// ─────────────────────────────────────────────────────────────────────────

/// Number that counts up once to [value] (and eases between later values).
class LuxeCountUp extends StatelessWidget {
  const LuxeCountUp({
    super.key,
    required this.value,
    required this.style,
    this.decimals = 0,
    this.suffix = '',
    this.duration = const Duration(milliseconds: 900),
  });

  final double value;
  final TextStyle style;
  final int decimals;
  final String suffix;
  final Duration duration;

  String _format(double v) => '${v.toStringAsFixed(decimals)}$suffix';

  @override
  Widget build(BuildContext context) {
    final reduce = luxeReduceMotion(context);
    final tabular = style.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (reduce) return Text(_format(value), style: tabular);
    return Semantics(
      label: _format(value),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: duration,
        curve: LuxeMotion.enter,
        builder: (context, v, _) => Text(_format(v), style: tabular),
      ),
    );
  }
}

/// Glass stat tile: caption label over a large platinum figure.
class LuxeStatTile extends StatelessWidget {
  const LuxeStatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.accent = LuxeColors.platinum,
    this.numeric,
    this.decimals = 0,
  });

  final String label;

  /// Display text; used when [numeric] is null (e.g. "—").
  final String value;
  final String? unit;
  final IconData? icon;
  final Color accent;

  /// When set, the figure counts up to this number.
  final double? numeric;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    const figure = TextStyle(
      color: LuxeColors.text,
      fontSize: 24,
      fontWeight: FontWeight.w300,
      letterSpacing: -0.6,
      height: 1.1,
    );
    return Semantics(
      container: true,
      label: '$label: $value${unit == null ? '' : ' $unit'}',
      excludeSemantics: true,
      child: LuxeGlass(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: accent),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LuxeText.label,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 4,
              children: [
                if (numeric != null)
                  LuxeCountUp(
                    value: numeric!,
                    decimals: decimals,
                    style: figure,
                  )
                else
                  Text(value, style: figure),
                if (unit != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(unit!, style: LuxeText.caption),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 2D art: ring, sparkline, empty art, shimmer
// ─────────────────────────────────────────────────────────────────────────

/// Progress ring that sweeps once to [value] (0..1) with an emerald arc on a
/// hairline track and a platinum tip. [child] sits in the centre.
class LuxeRing extends StatelessWidget {
  const LuxeRing({
    super.key,
    required this.value,
    this.size = 120,
    this.stroke = 8,
    this.color = LuxeColors.emerald,
    this.child,
    this.semanticLabel,
    this.duration = const Duration(milliseconds: 1100),
  });

  final double value;
  final double size;
  final double stroke;
  final Color color;
  final Widget? child;
  final String? semanticLabel;

  /// Sweep duration; shorten it for rings that follow a live control.
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final v = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    return Semantics(
      label: semanticLabel,
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: v),
          duration: luxeReduceMotion(context) ? Duration.zero : duration,
          curve: LuxeMotion.enter,
          builder: (context, t, child) => CustomPaint(
            painter: _RingPainter(t, stroke, color),
            child: child,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.stroke, this.color);
  final double t;
  final double stroke;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2 + 2);
    canvas.drawArc(
      arcRect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const Color(0x14FFFFFF),
    );
    if (t <= 0) return;
    const start = -math.pi / 2;
    final sweep = math.pi * 2 * t;
    canvas.drawArc(
      arcRect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 6
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawArc(
      arcRect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          transform: const GradientRotation(start),
          colors: [color.withValues(alpha: 0.55), color],
          stops: [0, t.clamp(0.01, 1.0)],
        ).createShader(arcRect),
    );
    final tip =
        arcRect.center +
        Offset(math.cos(start + sweep), math.sin(start + sweep)) *
            (arcRect.width / 2);
    canvas.drawCircle(
      tip,
      stroke * 0.42,
      Paint()..color = LuxeColors.platinumHi,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.t != t || old.stroke != stroke || old.color != color;
}

/// Minimal line chart: hairline grid, a gradient-filled emerald line that
/// draws itself once left-to-right, and a platinum end dot. Only real
/// [points] are drawn; fewer than two points renders nothing.
class LuxeSparkline extends StatelessWidget {
  const LuxeSparkline({
    super.key,
    required this.points,
    this.height = 120,
    this.color = LuxeColors.emerald,
    this.minY,
    this.maxY,
    this.semanticLabel,
  });

  final List<double> points;
  final double height;
  final Color color;
  final double? minY;
  final double? maxY;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final clean = [
      for (final p in points)
        if (p.isFinite) p,
    ];
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: clean.length < 2
            ? null
            : RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: luxeDuration(context, 1200),
                  curve: LuxeMotion.enter,
                  builder: (context, t, _) => CustomPaint(
                    painter: _SparkPainter(clean, t, color, minY, maxY),
                  ),
                ),
              ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.t, this.color, this.minY, this.maxY);
  final List<double> points;
  final double t;
  final Color color;
  final double? minY;
  final double? maxY;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0x12FFFFFF)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    var lo = minY ?? points.reduce(math.min);
    var hi = maxY ?? points.reduce(math.max);
    if (hi - lo < 1e-6) {
      lo -= 1;
      hi += 1;
    }
    const pad = 6.0;
    final h = size.height - pad * 2;
    Offset at(int i) => Offset(
      size.width * i / (points.length - 1),
      pad + h * (1 - (points[i] - lo) / (hi - lo)),
    );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      final a = at(i - 1);
      final b = at(i);
      final mx = (a.dx + b.dx) / 2;
      path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * t, size.height));
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    canvas.restore();
    if (t >= 1) {
      final end = at(points.length - 1);
      canvas.drawCircle(
        end,
        7,
        Paint()
          ..color = color.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(end, 3.5, Paint()..color = LuxeColors.platinumHi);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.t != t ||
      old.color != color ||
      old.minY != minY ||
      old.maxY != maxY ||
      !identical(old.points, points);
}

/// One-shot empty-state emblem: two platinum orbits draw in around a glass
/// medallion holding [icon], then a single emerald spark settles on the
/// outer orbit. No loop.
class LuxeEmptyArt extends StatelessWidget {
  const LuxeEmptyArt({super.key, required this.icon, this.size = 132});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: luxeDuration(context, 1400),
        curve: LuxeMotion.enter,
        builder: (context, t, child) => CustomPaint(
          painter: _OrbitPainter(t),
          child: Center(
            child: Opacity(
              opacity: (t * 2).clamp(0.0, 1.0),
              child: Transform.scale(scale: 0.86 + 0.14 * t, child: child),
            ),
          ),
        ),
        child: Container(
          width: size * 0.42,
          height: size * 0.42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF26282C), Color(0xFF0F1012)],
            ),
            border: Border.all(color: LuxeColors.hairlineStrong),
          ),
          child: Icon(icon, size: size * 0.18, color: LuxeColors.platinum),
        ),
      ),
    ),
  );
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r1 = size.width * 0.47;
    final r2 = size.width * 0.34;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    ring.color = LuxeColors.platinumLow.withValues(alpha: 0.55);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r1),
      -math.pi / 2,
      math.pi * 2 * t,
      false,
      ring,
    );
    ring.color = LuxeColors.platinumLow.withValues(alpha: 0.35);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r2),
      math.pi / 2,
      -math.pi * 2 * t,
      false,
      ring,
    );
    final a = -math.pi / 2 + math.pi * 1.25 * t;
    final spark = c + Offset(math.cos(a), math.sin(a)) * r1;
    canvas.drawCircle(
      spark,
      6,
      Paint()
        ..color = LuxeColors.emerald.withValues(alpha: 0.3 * t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      spark,
      2.5,
      Paint()..color = LuxeColors.emerald.withValues(alpha: t),
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.t != t;
}

/// Brushed-platinum sweep over placeholder shapes while content loads. The
/// loop is tied to the loading state, pauses with [TickerMode] and is static
/// under reduced motion.
/// A fold that grows and shrinks on the luxe curve; under "reduce motion"
/// it shows its child directly. Never `AnimatedSize(duration: zero)`: that
/// asserts "mutated in its own performLayout" (QA 138, QA 139).
class LuxeFold extends StatelessWidget {
  const LuxeFold({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 320),
    this.alignment = Alignment.center,
  });

  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: duration,
          curve: LuxeMotion.enter,
          alignment: alignment,
          child: child,
        );
}

class LuxeShimmer extends StatefulWidget {
  const LuxeShimmer({super.key, required this.child});
  final Widget child;

  @override
  State<LuxeShimmer> createState() => _LuxeShimmerState();
}

class _LuxeShimmerState extends State<LuxeShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (luxeReduceMotion(context)) {
      _c.stop();
      _c.value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) => ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) {
        final x = -1.5 + 3 * _c.value;
        return LinearGradient(
          begin: Alignment(x - 0.6, -0.3),
          end: Alignment(x + 0.6, 0.3),
          colors: const [
            LuxeColors.raised,
            Color(0xFF2A2C30),
            LuxeColors.raised,
          ],
          stops: const [0.2, 0.5, 0.8],
        ).createShader(bounds);
      },
      child: child,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────
// Selection
// ─────────────────────────────────────────────────────────────────────────

/// Segmented pill with a gliding platinum thumb. Equal-width segments.
class LuxeSegmented<T> extends StatelessWidget {
  const LuxeSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final n = segments.length;
    final index = segments.indexWhere((s) => s.$1 == selected);
    final glide = luxeDuration(context, 380);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: LuxeColors.glass,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: LuxeColors.hairline),
      ),
      child: Stack(
        children: [
          if (index >= 0)
            Positioned.fill(
              child: AnimatedAlign(
                duration: glide,
                curve: LuxeMotion.enter,
                alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / n,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x2EFFFFFF), Color(0x12FFFFFF)],
                      ),
                      border: Border.all(color: LuxeColors.hairlineStrong),
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              for (final (value, label) in segments)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: value == selected,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: () {
                        if (value == selected) return;
                        HapticFeedback.selectionClick();
                        onChanged(value);
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            child: AnimatedDefaultTextStyle(
                              duration: glide,
                              style: TextStyle(
                                color: value == selected
                                    ? LuxeColors.text
                                    : LuxeColors.muted,
                                fontSize: 13,
                                fontWeight: value == selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                              child: Text(label, textAlign: TextAlign.center),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Inline notice strip (info / caution / danger) with a hairline rim.
class LuxeNotice extends StatelessWidget {
  const LuxeNotice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.color = LuxeColors.steel,
    this.action,
  });

  final String message;
  final IconData icon;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: color.withValues(alpha: 0.07),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: LuxeColors.text,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
        if (action != null) ...[const SizedBox(width: 8), action!],
      ],
    ),
  );
}
