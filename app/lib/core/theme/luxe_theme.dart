import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/bootstrap_splash.dart';

/// LUXE — the platinum + emerald language shared by the splash, Getting
/// started and the first-run survey. Dark only: these screens continue the
/// splash, then hand over to the app theme.
abstract final class LuxeColors {
  static const background = BootstrapSplash.background;
  static const ambient = Color(0xFF16181B);
  static const glass = Color(0x0FFFFFFF);
  static const glassStrong = Color(0x17FFFFFF);
  static const hairline = Color(0x1FFFFFFF);
  static const hairlineStrong = Color(0x38FFFFFF);

  static const platinumHi = Color(0xFFF7F7F5);
  static const platinum = Color(0xFFD6D8DB);
  static const platinumMid = Color(0xFF9EA2A8);
  static const platinumLow = Color(0xFF5E6268);

  static const text = Color(0xFFF2F2F0);
  static const muted = Color(0xFF9A9EA5);
  static const dim = Color(0xFF6B6F76);

  static const emerald = Color(0xFF34D399);
  static const emeraldDeep = Color(0xFF10B981);
  static const emeraldGlow = Color(0x5534D399);
  static const danger = Color(0xFFF59E9E);

  static const platinumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [platinumHi, platinum, platinumMid],
    stops: [0.0, 0.55, 1.0],
  );
}

/// Explicit styles: luxe screens never inherit the app's light/dark text.
abstract final class LuxeText {
  static const eyebrow = TextStyle(
    color: LuxeColors.emerald,
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.2,
  );
  static const title = TextStyle(
    color: LuxeColors.text,
    fontSize: 26,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );
  static const body = TextStyle(
    color: LuxeColors.muted,
    fontSize: 14,
    height: 1.5,
  );
  static const item = TextStyle(
    color: LuxeColors.text,
    fontSize: 15.5,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );
  static const caption = TextStyle(
    color: LuxeColors.muted,
    fontSize: 13,
    height: 1.4,
  );
  static const label = TextStyle(
    color: LuxeColors.muted,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
  );
}

abstract final class LuxeMotion {
  static const reveal = Duration(milliseconds: 520);
  static const stagger = Duration(milliseconds: 70);
  static const Curve enter = Cubic(0.16, 1.0, 0.3, 1.0);
  static const Curve exit = Cubic(0.7, 0.0, 0.84, 0.0);
}

abstract final class LuxeTheme {
  /// Luxe theme for [context]. Deliberately does not inherit the app's
  /// Google Fonts family: it registers one family per weight, so inheriting
  /// it would flatten the thin/light weights this language relies on. Luxe
  /// screens use the platform face (Roboto on Android), like the splash.
  static ThemeData of(BuildContext context) => data();

  /// Material theme for luxe screens: every stock control inherits the
  /// platinum/emerald styling, so screen logic keeps plain Material widgets.
  static ThemeData data() {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark);
    const scheme = ColorScheme.dark(
      primary: LuxeColors.emerald,
      onPrimary: Color(0xFF04140D),
      primaryContainer: Color(0xFF0E2A20),
      onPrimaryContainer: LuxeColors.text,
      secondary: LuxeColors.platinum,
      onSecondary: Color(0xFF0B0C0E),
      surface: LuxeColors.background,
      onSurface: LuxeColors.text,
      onSurfaceVariant: LuxeColors.muted,
      surfaceContainerLowest: Color(0xFF08090A),
      surfaceContainerLow: Color(0xFF0E0F11),
      surfaceContainer: Color(0xFF121315),
      surfaceContainerHigh: Color(0xFF17181B),
      surfaceContainerHighest: Color(0xFF1D1F22),
      outline: Color(0xFF44474D),
      outlineVariant: Color(0xFF2A2C30),
      error: LuxeColors.danger,
      onError: Color(0xFF1A0505),
    );
    final text = base.textTheme.apply(
      bodyColor: LuxeColors.text,
      displayColor: LuxeColors.text,
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: LuxeColors.hairline),
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: LuxeColors.background,
      canvasColor: LuxeColors.background,
      textTheme: text,
      dividerTheme: const DividerThemeData(
        color: LuxeColors.hairline,
        thickness: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          elevation: const WidgetStatePropertyAll(0),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? LuxeColors.dim
                : const Color(0xFF0B0C0E),
          ),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: const WidgetStatePropertyAll(Color(0x14000000)),
          // Brushed platinum pill; a quiet glass pill when disabled.
          backgroundBuilder: (context, states, child) {
            final disabled = states.contains(WidgetState.disabled);
            return DecoratedBox(
              decoration: ShapeDecoration(
                shape: StadiumBorder(
                  side: BorderSide(
                    color: disabled
                        ? LuxeColors.hairline
                        : const Color(0x66FFFFFF),
                  ),
                ),
                gradient: disabled
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          LuxeColors.platinumHi,
                          LuxeColors.platinum,
                          Color(0xFFB9BCC1),
                        ],
                        stops: [0.0, 0.6, 1.0],
                      ),
                color: disabled ? LuxeColors.glass : null,
                shadows: disabled
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x33FFFFFF),
                          blurRadius: 18,
                          spreadRadius: -6,
                        ),
                      ],
              ),
              child: child,
            );
          },
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          foregroundColor: LuxeColors.text,
          side: const BorderSide(color: LuxeColors.hairlineStrong),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: LuxeColors.muted,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: LuxeColors.text),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LuxeColors.glass,
        labelStyle: const TextStyle(color: LuxeColors.muted),
        floatingLabelStyle: const TextStyle(color: LuxeColors.emerald),
        hintStyle: const TextStyle(color: LuxeColors.dim),
        helperStyle: const TextStyle(color: LuxeColors.dim),
        prefixIconColor: LuxeColors.platinumMid,
        suffixIconColor: LuxeColors.platinumMid,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: LuxeColors.emerald, width: 1.4),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: LuxeColors.danger),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: LuxeColors.danger, width: 1.4),
        ),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        activeTrackColor: LuxeColors.emerald,
        inactiveTrackColor: Color(0x24FFFFFF),
        thumbColor: LuxeColors.platinumHi,
        overlayColor: Color(0x2234D399),
        activeTickMarkColor: Color(0x00000000),
        inactiveTickMarkColor: Color(0x00000000),
        valueIndicatorColor: Color(0xFF1D1F22),
        valueIndicatorTextStyle: TextStyle(color: LuxeColors.text),
        thumbShape: _LuxeThumbShape(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: LuxeColors.glass,
        selectedColor: const Color(0x2634D399),
        side: const BorderSide(color: LuxeColors.hairline),
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(
          color: LuxeColors.text,
          fontWeight: FontWeight.w500,
        ),
        checkmarkColor: LuxeColors.emerald,
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: Color(0xFF121315),
        headerBackgroundColor: Color(0xFF17181B),
        headerForegroundColor: LuxeColors.text,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF1D1F22),
        contentTextStyle: TextStyle(color: LuxeColors.text),
      ),
    );
  }
}

/// Platinum thumb with a soft emerald halo.
class _LuxeThumbShape extends SliderComponentShape {
  const _LuxeThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(11);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final active = activationAnimation.value;
    canvas.drawCircle(
      center,
      14 + 6 * active,
      Paint()
        ..color = LuxeColors.emerald.withValues(alpha: 0.18 + 0.12 * active)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      center,
      10,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.5),
          colors: [LuxeColors.platinumHi, LuxeColors.platinumMid],
        ).createShader(Rect.fromCircle(center: center, radius: 10)),
    );
    canvas.drawCircle(center, 3, Paint()..color = LuxeColors.emeraldDeep);
  }
}

/// Splash-continuous backdrop: a cool pool of light, a soft emerald hint
/// and a radial vignette. [drift] (0..1) slowly moves the light.
class LuxeBackdrop extends StatelessWidget {
  const LuxeBackdrop({super.key, this.drift = 0, this.accent = 1});

  final double drift;
  final double accent;

  @override
  Widget build(BuildContext context) {
    final a = drift * 2 * math.pi;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: LuxeColors.background),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(
                  0.15 * math.sin(a),
                  -0.55 + 0.05 * math.cos(a),
                ),
                radius: 1.0,
                colors: const [LuxeColors.ambient, Color(0x00050506)],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.9 - 0.2 * math.cos(a), 1.1),
                radius: 0.9,
                colors: [
                  LuxeColors.emerald.withValues(alpha: 0.07 * accent),
                  const Color(0x0034D399),
                ],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.2,
                colors: [Color(0x00000000), Color(0x80000000)],
                stops: [0.6, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Glass surface with a hairline border; [selected] lights the edge emerald.
class LuxeGlass extends StatelessWidget {
  const LuxeGlass({
    super.key,
    required this.child,
    this.selected = false,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
  });

  final Widget child;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    return AnimatedContainer(
      duration: duration,
      curve: LuxeMotion.enter,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: selected
              ? const [Color(0x2234D399), Color(0x0A34D399)]
              : const [Color(0x12FFFFFF), Color(0x06FFFFFF)],
        ),
        border: Border.all(
          color: selected
              ? LuxeColors.emerald.withValues(alpha: 0.75)
              : LuxeColors.hairline,
          width: selected ? 1.3 : 1,
        ),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x2234D399),
                  blurRadius: 24,
                  spreadRadius: -4,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// One-shot entrance: fade + rise, delayed by [index] × stagger. Uses the
/// widget's own ticker (no timers), and appears instantly in reduced motion.
class LuxeReveal extends StatefulWidget {
  const LuxeReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 14,
  });

  final Widget child;
  final int index;
  final double offset;

  @override
  State<LuxeReveal> createState() => _LuxeRevealState();
}

class _LuxeRevealState extends State<LuxeReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    final delay = LuxeMotion.stagger * widget.index.clamp(0, 8);
    final total = delay + LuxeMotion.reveal;
    _ctrl = AnimationController(vsync: this, duration: total);
    _t = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: LuxeMotion.enter,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctrl.status == AnimationStatus.dismissed) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _ctrl.value = 1;
      } else {
        _ctrl.forward();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _t.value,
      child: Transform.translate(
        offset: Offset(0, widget.offset * (1 - _t.value)),
        child: child,
      ),
    ),
  );
}

/// Platinum gradient text (wordmarks, hero numerals).
class LuxeMetalText extends StatelessWidget {
  const LuxeMetalText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (bounds) => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        LuxeColors.platinumHi,
        LuxeColors.platinum,
        LuxeColors.platinumMid,
      ],
      stops: [0.0, 0.55, 1.0],
    ).createShader(bounds),
    child: Text(text, style: style.copyWith(color: Colors.white)),
  );
}
