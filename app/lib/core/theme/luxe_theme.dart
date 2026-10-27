import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/entitlement.dart';
import '../widgets/bootstrap_splash.dart';
import 'plan_style.dart';

/// LUXE — the platinum + emerald language of the whole app (Task 117: the
/// app is dark only and every screen inherits [LuxeTheme.data]).
abstract final class LuxeColors {
  static const background = BootstrapSplash.background;
  static const ambient = Color(0xFF16181B);

  /// Bar and shell surface just above the background (QA 139).
  static const shell = Color(0xFF0B0C0E);
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
  // Raised in Task 121 so secondary text keeps ≥4.5:1 on every surface.
  static const dim = Color(0xFF858990);

  static const emerald = Color(0xFF34D399);
  static const emeraldDeep = Color(0xFF10B981);
  static const emeraldGlow = Color(0x5534D399);
  // QA 139: tints that older screens wrote as hex (Cockpit, AppColors).
  static const emeraldSoft = Color(0x3334D399);
  static const emeraldTint = Color(0x1A34D399);
  static const danger = Color(0xFFF59E9E);

  /// Champagne gold: estimated values and cautions (never verified state).
  static const champagne = Color(0xFFE8C170);

  /// Steel blue: neutral information.
  static const steel = Color(0xFF9DB8E8);

  /// Opaque surface steps (sheets, dialogs, raised wells).
  static const surface = Color(0xFF0E0F11);
  static const sheet = Color(0xFF121315);
  static const raised = Color(0xFF17181B);
  static const raisedHigh = Color(0xFF1D1F22);

  /// Opaque hairlines for surfaces drawn without alpha blending.
  static const rule = Color(0xFF222428);
  static const ruleStrong = Color(0xFF33363B);

  static const platinumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [platinumHi, platinum, platinumMid],
    stops: [0.0, 0.55, 1.0],
  );
}

/// Explicit styles: luxe screens never inherit the app's light/dark text.
abstract final class LuxeText {
  /// The type scale (QA 139): every hard-coded `fontSize` from 10 up uses
  /// one of these steps. Text 11–26; numbers on dials and heroes 28–60.
  /// `test/widget/qa139_ui_fixes_test.dart` checks the sources.
  static const scale = <double>[
    11, 11.5, 12.5, 13, 14, 15, 15.5, 17, 19, 22, 24, 26, //
    28, 30, 34, 36, 40, 44, 46, 48, 52, 56, 60,
  ];

  // Platinum, not emerald: emerald is reserved for verified states, and
  // every section label in the app used it (Task 125).
  static const eyebrow = TextStyle(
    color: LuxeColors.platinumMid,
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
  static ThemeData of(BuildContext context) =>
      data(tier: PlanStyle.of(context).tier);

  /// Material theme for the whole app (dark only since Task 117): every stock
  /// control inherits the platinum/emerald styling, so screen logic keeps
  /// plain Material widgets. QA 136: one theme per plan (Free keeps LUXE,
  /// Pro silver/steel, Ultra aurora), each built once.
  static ThemeData data({PlanTier tier = PlanTier.free}) =>
      _cache[tier] ??= _build(PlanStyle.forTier(tier));

  static final Map<PlanTier, ThemeData> _cache = {};

  static ThemeData _build(PlanStyle plan) {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark);
    // Controls take the plan's accent; status colours stay fixed.
    final accent = plan.accent;
    final scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: PlanColors.ink,
      primaryContainer: Color.alphaBlend(
        accent.withValues(alpha: 0.18),
        LuxeColors.background,
      ),
      onPrimaryContainer: LuxeColors.text,
      secondary: LuxeColors.platinum,
      onSecondary: const Color(0xFF0B0C0E),
      surface: LuxeColors.background,
      onSurface: LuxeColors.text,
      onSurfaceVariant: LuxeColors.muted,
      surfaceContainerLowest: const Color(0xFF08090A),
      surfaceContainerLow: const Color(0xFF0E0F11),
      surfaceContainer: const Color(0xFF121315),
      surfaceContainerHigh: const Color(0xFF17181B),
      surfaceContainerHighest: const Color(0xFF1D1F22),
      outline: const Color(0xFF44474D),
      outlineVariant: const Color(0xFF2A2C30),
      error: LuxeColors.danger,
      onError: const Color(0xFF1A0505),
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
      extensions: [plan],
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
                : PlanColors.ink,
          ),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: const WidgetStatePropertyAll(Color(0x14000000)),
          // Brushed platinum pill (Pro: silver to steel; Ultra: a flowing
          // aurora); a quiet glass pill when disabled.
          backgroundBuilder: (context, states, child) {
            final disabled = states.contains(WidgetState.disabled);
            if (!disabled && plan.isUltra) {
              return PlanFlow(
                builder: (context, phase) => DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(
                      side: BorderSide(color: Color(0x66FFFFFF)),
                    ),
                    gradient: planFlowGradient(phase),
                    shadows: const [
                      BoxShadow(
                        color: Color(0x558B5CF6),
                        blurRadius: 22,
                        spreadRadius: -6,
                      ),
                    ],
                  ),
                  child: child,
                ),
              );
            }
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
                    : LinearGradient(
                        begin: plan.isPro
                            ? Alignment.topLeft
                            : Alignment.topCenter,
                        end: plan.isPro
                            ? Alignment.bottomRight
                            : Alignment.bottomCenter,
                        colors: plan.accentColors,
                        stops: const [0.0, 0.6, 1.0],
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
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LuxeColors.glass,
        labelStyle: const TextStyle(color: LuxeColors.muted),
        floatingLabelStyle: TextStyle(color: accent),
        // QA 139: muted, dim was 3.8–4.4:1 on the field fill.
        hintStyle: const TextStyle(color: LuxeColors.muted),
        helperStyle: const TextStyle(color: LuxeColors.muted),
        prefixIconColor: LuxeColors.platinumMid,
        suffixIconColor: LuxeColors.platinumMid,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: LuxeColors.danger),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: LuxeColors.danger, width: 1.4),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: accent,
        inactiveTrackColor: const Color(0x24FFFFFF),
        thumbColor: LuxeColors.platinumHi,
        overlayColor: accent.withValues(alpha: 0.13),
        activeTickMarkColor: const Color(0x00000000),
        inactiveTickMarkColor: const Color(0x00000000),
        valueIndicatorColor: const Color(0xFF1D1F22),
        valueIndicatorTextStyle: const TextStyle(color: LuxeColors.text),
        thumbShape: _LuxeThumbShape(accent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: LuxeColors.glass,
        selectedColor: accent.withValues(alpha: 0.15),
        side: const BorderSide(color: LuxeColors.hairline),
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(
          color: LuxeColors.text,
          fontWeight: FontWeight.w500,
        ),
        checkmarkColor: accent,
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: Color(0xFF121315),
        headerBackgroundColor: Color(0xFF17181B),
        headerForegroundColor: LuxeColors.text,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: LuxeColors.raisedHigh,
        contentTextStyle: const TextStyle(
          color: LuxeColors.text,
          fontSize: 14,
          height: 1.4,
        ),
        actionTextColor: accent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: LuxeColors.hairlineStrong),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: LuxePageTransitionsBuilder(),
          TargetPlatform.iOS: LuxePageTransitionsBuilder(),
          TargetPlatform.fuchsia: LuxePageTransitionsBuilder(),
          TargetPlatform.linux: LuxePageTransitionsBuilder(),
          TargetPlatform.macOS: LuxePageTransitionsBuilder(),
          TargetPlatform.windows: LuxePageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: LuxeColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: LuxeColors.text,
          fontSize: 19,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: LuxeColors.text),
      ),
      cardTheme: CardThemeData(
        color: LuxeColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: LuxeColors.hairline),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: LuxeColors.platinum,
        textColor: LuxeColors.text,
        minTileHeight: 56,
        titleTextStyle: TextStyle(
          color: LuxeColors.text,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          color: LuxeColors.muted,
          fontSize: 13,
          height: 1.4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: LuxeColors.sheet,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: LuxeColors.hairline),
        ),
        titleTextStyle: const TextStyle(
          color: LuxeColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: LuxeColors.muted,
          fontSize: 14,
          height: 1.5,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: LuxeColors.sheet,
        modalBackgroundColor: LuxeColors.sheet,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Color(0xB3000000),
        elevation: 0,
        modalElevation: 0,
        dragHandleColor: LuxeColors.platinumLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          side: BorderSide(color: LuxeColors.hairline),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 52),
          backgroundColor: LuxeColors.raised,
          foregroundColor: LuxeColors.text,
          disabledBackgroundColor: LuxeColors.glass,
          disabledForegroundColor: LuxeColors.dim,
          elevation: 0,
          shape: const StadiumBorder(
            side: BorderSide(color: LuxeColors.hairlineStrong),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: LuxeColors.text,
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: LuxeColors.platinum,
        foregroundColor: Color(0xFF0B0C0E),
        elevation: 0,
        highlightElevation: 0,
        shape: StadiumBorder(),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: LuxeColors.background,
        selectedItemColor: accent,
        unselectedItemColor: LuxeColors.muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? LuxeColors.platinumHi
              : LuxeColors.platinumMid,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accent.withValues(alpha: 0.32)
              : LuxeColors.raised,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accent.withValues(alpha: 0.7)
              : LuxeColors.hairlineStrong,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(PlanColors.ink),
        side: const BorderSide(color: LuxeColors.platinumMid, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accent
              : LuxeColors.platinumMid,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: const Color(0x1FFFFFFF),
        circularTrackColor: const Color(0x14FFFFFF),
        linearMinHeight: 3,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          side: const WidgetStatePropertyAll(
            BorderSide(color: LuxeColors.hairlineStrong),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? accent.withValues(alpha: 0.16)
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? LuxeColors.text
                : LuxeColors.muted,
          ),
          iconColor: WidgetStatePropertyAll(accent),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: LuxeColors.text,
        unselectedLabelColor: LuxeColors.muted,
        indicatorColor: accent,
        dividerColor: LuxeColors.hairline,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: LuxeColors.raised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: const TextStyle(color: LuxeColors.text, fontSize: 14.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: LuxeColors.hairlineStrong),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: LuxeColors.raisedHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: LuxeColors.hairlineStrong),
        ),
        textStyle: const TextStyle(color: LuxeColors.text, fontSize: 12.5),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: accent,
        collapsedIconColor: LuxeColors.platinumMid,
        textColor: LuxeColors.text,
        collapsedTextColor: LuxeColors.text,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.33),
        selectionHandleColor: accent,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: accent,
        textColor: PlanColors.ink,
      ),
    );
  }
}

/// Route transition for every MaterialPageRoute: the incoming page fades and
/// rises on the luxe curve while the page beneath recedes a touch, so pushes
/// read as depth rather than a slide. Instant under reduced motion.
class LuxePageTransitionsBuilder extends PageTransitionsBuilder {
  const LuxePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    final enter = CurvedAnimation(
      parent: animation,
      curve: LuxeMotion.enter,
      reverseCurve: LuxeMotion.exit,
    );
    final recede = CurvedAnimation(
      parent: secondaryAnimation,
      curve: LuxeMotion.enter,
      reverseCurve: Curves.easeOutCubic,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([enter, recede]),
      child: child,
      builder: (context, child) {
        final t = enter.value;
        final r = recede.value;
        return Opacity(
          opacity: (t * (1 - 0.35 * r)).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 28 * (1 - t)),
            child: Transform.scale(scale: 1 - 0.02 * r, child: child),
          ),
        );
      },
    );
  }
}

/// Platinum thumb with a soft emerald halo.
class _LuxeThumbShape extends SliderComponentShape {
  const _LuxeThumbShape(this.accent);

  final Color accent;

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
        ..color = accent.withValues(alpha: 0.18 + 0.12 * active)
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
    canvas.drawCircle(
      center,
      3,
      Paint()..color = Color.lerp(accent, Colors.black, 0.2)!,
    );
  }
}

/// Splash-continuous backdrop: a cool pool of light, a soft emerald hint
/// and a radial vignette. [drift] (0..1) slowly moves the light.
/// QA 136: the light takes the plan's colour (Pro steel; Ultra a violet and
/// cyan aurora that drifts with the Ultra clock).
class LuxeBackdrop extends StatelessWidget {
  const LuxeBackdrop({super.key, this.drift = 0, this.accent = 1});

  final double drift;
  final double accent;

  @override
  Widget build(BuildContext context) {
    final plan = PlanStyle.of(context);
    if (!plan.isUltra) return _layers(plan, drift);
    return PlanFlow(builder: (context, phase) => _layers(plan, drift + phase));
  }

  Widget _layers(PlanStyle plan, double t) {
    final a = t * 2 * math.pi;
    final glow = plan.isUltra ? 0.16 : (plan.isPro ? 0.09 : 0.07);
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
                colors: [plan.ambient, plan.ambient.withValues(alpha: 0)],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.9 - 0.2 * math.cos(a), 1.1),
                radius: plan.isUltra ? 1.05 : 0.9,
                colors: [
                  plan.glow.withValues(alpha: glow * accent),
                  plan.glow.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          if (plan.glowAlt != null)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(
                    -0.95 + 0.25 * math.sin(a),
                    -0.2 + 0.3 * math.cos(a),
                  ),
                  radius: 0.85,
                  colors: [
                    plan.glowAlt!.withValues(alpha: 0.14 * accent),
                    plan.glowAlt!.withValues(alpha: 0),
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
    // QA 136: Pro glass has a steel edge, Ultra a violet/cyan tint.
    final plan = PlanStyle.of(context);
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
              : plan.glassColors,
        ),
        border: Border.all(
          color: selected
              ? LuxeColors.emerald.withValues(alpha: 0.75)
              : plan.glassBorder,
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
