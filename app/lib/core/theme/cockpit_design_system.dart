import 'package:flutter/material.dart';
import 'app_ui_colors.dart';
import 'luxe_theme.dart';

/// Shared EV cockpit tokens used across the application.
///
/// Emerald is intentionally reserved for verified state and primary actions.
/// Estimated values use amber and destructive actions use red.
abstract final class CockpitColors {
  // Task 117: legacy Cockpit names now resolve to the LUXE palette so every
  // older screen shares the platinum + emerald language.
  static const background = LuxeColors.background;
  static const shell = Color(0xFF0B0C0E);
  static const surface = LuxeColors.sheet;
  static const elevated = LuxeColors.raised;
  static const surfaceSoft = LuxeColors.raisedHigh;

  static const emerald = LuxeColors.emerald;
  static const emeraldStrong = LuxeColors.emeraldDeep;
  static const emeraldGlow = Color(0x3334D399);
  static const emeraldSubtle = Color(0x1A34D399);
  static const amber = LuxeColors.champagne;
  static const danger = LuxeColors.danger;
  static const info = LuxeColors.steel;

  static const text = LuxeColors.text;
  static const muted = LuxeColors.muted;
  static const dim = LuxeColors.dim;
  static const border = LuxeColors.rule;
  static const borderStrong = LuxeColors.ruleStrong;
}

/// Theme-adaptive color scheme accessor via `context.cockpit`.
extension CockpitThemeX on BuildContext {
  CockpitColorScheme get cockpit => CockpitColorScheme.of(this);
}

class CockpitColorScheme {
  CockpitColorScheme.of(BuildContext context) : _ui = AppUiColors.of(context);
  final AppUiColors _ui;

  bool get dark => _ui.dark;
  Color get background => _ui.background;
  Color get shell => _ui.shell;
  Color get surface => _ui.surface;
  Color get elevated => _ui.elevated;
  Color get surfaceSoft => _ui.surfaceSoft;
  Color get cardBackground => _ui.cardBackground;
  Color get border => _ui.border;
  Color get borderStrong => _ui.borderStrong;

  Color get text => _ui.text;
  Color get muted => _ui.muted;
  Color get dim => _ui.dim;

  Color get emerald => CockpitColors.emerald;
  Color get emeraldStrong => CockpitColors.emeraldStrong;
  Color get emeraldGlow => CockpitColors.emeraldGlow;
  Color get emeraldSubtle => CockpitColors.emeraldSubtle;
  Color get amber => _ui.amber;
  Color get danger => _ui.danger;
  Color get info => _ui.info;

  TextStyle numbers({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
  }) => CockpitTypography.numbers(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color ?? text,
    letterSpacing: letterSpacing,
  );

  TextStyle heading({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
  }) => CockpitTypography.heading(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color ?? text,
    letterSpacing: letterSpacing,
  );

  TextStyle body({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => CockpitTypography.body(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color ?? text,
    height: height,
    letterSpacing: letterSpacing,
  );

  TextStyle label({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
    double? letterSpacing,
  }) => CockpitTypography.label(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color ?? muted,
    letterSpacing: letterSpacing,
  );
}

abstract final class CockpitSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class CockpitRadius {
  static const small = 12.0;
  static const medium = 16.0;
  static const large = 24.0;
  static const sheet = 28.0;
  static const full = 999.0;
}

abstract final class CockpitButtonTokens {
  static const double height = 48.0;
  static const double iconSize = 22.0;
  static const double radius = 14.0;
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 12,
  );
}

abstract final class CockpitMotion {
  static const fast = Duration(milliseconds: 150);
  static const standard = Duration(milliseconds: 200);
  static const sheet = Duration(milliseconds: 220);
  static const battery = Duration(milliseconds: 300);
  static const chargingGlow = Duration(milliseconds: 2500);
  static const energyWave = Duration(seconds: 4);
  static const glowPulse = Duration(milliseconds: 1800);
  static const ripple = Duration(milliseconds: 650);

  static bool enabled(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations != true;
}

/// Standardized transition curves and durations for consistent animations.
abstract final class CockpitTransitions {
  static const Curve standard = Curves.easeOutCubic;
  static const Curve decelerate = Curves.decelerate;
  static const Curve spring = Curves.easeOutBack;
  static const Curve subtle = Curves.easeInOut;

  static const Duration quick = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration page = Duration(milliseconds: 300);
  static const Duration drawer = Duration(milliseconds: 350);
}

/// Standardized elevation/shadow levels for layered surfaces.
abstract final class CockpitElevation {
  static List<BoxShadow> none = const [];

  static List<BoxShadow> low = const [
    BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static List<BoxShadow> medium = const [
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static List<BoxShadow> high = const [
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
}

/// QA 139: defaults follow LuxeText (semibold titles, light numbers on
/// LUXE screens use explicit weights) so the older Shelly setup screens read
/// like the rest of the app.
abstract final class CockpitTypography {
  static TextStyle numbers({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w600,
    Color color = CockpitColors.text,
    double? letterSpacing,
  }) => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing ?? -0.2,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle heading({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w600,
    Color color = CockpitColors.text,
    double? letterSpacing,
  }) => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing ?? -0.2,
  );

  static TextStyle body({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color color = CockpitColors.text,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );

  static TextStyle label({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w500,
    Color color = CockpitColors.muted,
    double? letterSpacing,
  }) => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing ?? 0.4,
  );
}

/// Restrained surface used only when the region is itself interactive or a
/// meaningful status group. Task 117+: rendered as LUXE glass with a hairline
/// rim; [highlight] lights the rim emerald with a soft halo.
class CockpitSurface extends StatelessWidget {
  const CockpitSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(CockpitSpacing.md),
    this.highlight = false,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool highlight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        gradient: color != null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: highlight
                    ? const [Color(0x1A34D399), Color(0x0834D399)]
                    : const [Color(0x12FFFFFF), Color(0x06FFFFFF)],
              ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: highlight
              ? LuxeColors.emerald.withValues(alpha: .55)
              : LuxeColors.hairline,
        ),
        boxShadow: highlight && CockpitMotion.enabled(context)
            ? [
                BoxShadow(
                  color: LuxeColors.emerald.withValues(alpha: .10),
                  blurRadius: 24,
                  spreadRadius: -4,
                ),
              ]
            : const [],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class CockpitSectionLabel extends StatelessWidget {
  const CockpitSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6, bottom: 10, top: 6),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: LuxeColors.platinumMid,
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.8,
      ),
    ),
  );
}

enum SettingsItemAvailability { enabled, locked, comingSoon }

class CockpitSettingsRow extends StatelessWidget {
  const CockpitSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.availability = SettingsItemAvailability.enabled,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final SettingsItemAvailability availability;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = availability == SettingsItemAvailability.enabled;
    final accent = danger
        ? AppUiColors.of(context).danger
        : AppUiColors.of(context).primary;
    return Semantics(
      button: enabled && onTap != null,
      enabled: enabled,
      label: title,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(CockpitRadius.medium),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 64),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF26282C), Color(0xFF0F1012)],
                    ),
                    border: Border.all(
                      color: (enabled ? accent : LuxeColors.platinumLow)
                          .withValues(alpha: .4),
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: enabled ? accent : AppUiColors.of(context).muted,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: enabled
                              ? (danger
                                    ? AppUiColors.of(context).danger
                                    : AppUiColors.of(context).text)
                              : AppUiColors.of(context).muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: enabled
                                    ? AppUiColors.of(context).muted
                                    : AppUiColors.of(context).muted,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!enabled)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      availability == SettingsItemAvailability.comingSoon
                          ? 'Sắp có'
                          : 'Đã khóa',
                      style: TextStyle(
                        color: AppUiColors.of(context).muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  trailing ??
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: LuxeColors.dim,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
