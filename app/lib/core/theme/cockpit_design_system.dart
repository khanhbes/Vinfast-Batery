import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared EV cockpit tokens used across the application.
///
/// Emerald is intentionally reserved for verified state and primary actions.
/// Estimated values use amber and destructive actions use red.
abstract final class CockpitColors {
  static const background = Color(0xFF050505);
  static const shell = Color(0xFF0C0C0C);
  static const surface = Color(0xFF101216);
  static const elevated = Color(0xFF171A20);
  static const surfaceSoft = Color(0xFF1D2128);

  static const emerald = Color(0xFF34D399);
  static const emeraldStrong = Color(0xFF10B981);
  static const amber = Color(0xFFFBBF24);
  static const danger = Color(0xFFF87171);
  static const info = Color(0xFF60A5FA);

  static const text = Color(0xFFF8FAFC);
  static const muted = Color(0xFF94A3B8);
  static const dim = Color(0xFF64748B);
  static const border = Color(0x14FFFFFF);
  static const borderStrong = Color(0x24FFFFFF);
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
}

abstract final class CockpitMotion {
  static const fast = Duration(milliseconds: 150);
  static const standard = Duration(milliseconds: 200);
  static const sheet = Duration(milliseconds: 220);
  static const battery = Duration(milliseconds: 300);
  static const chargingGlow = Duration(milliseconds: 2500);
  static const energyWave = Duration(seconds: 4);

  static bool enabled(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations != true;
}

abstract final class CockpitTypography {
  static TextStyle numbers({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w700,
    Color color = CockpitColors.text,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Restrained surface used only when the region is itself interactive or a
/// meaningful status group.
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color ?? CockpitColors.surface,
      borderRadius: BorderRadius.circular(CockpitRadius.large),
      border: Border.all(
        color: highlight
            ? CockpitColors.emerald.withValues(alpha: .34)
            : CockpitColors.border,
      ),
      boxShadow: highlight && CockpitMotion.enabled(context)
          ? [
              BoxShadow(
                color: CockpitColors.emerald.withValues(alpha: .09),
                blurRadius: 28,
                spreadRadius: 1,
              ),
            ]
          : const [],
    ),
    child: Padding(padding: padding, child: child),
  );
}

class CockpitSectionLabel extends StatelessWidget {
  const CockpitSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: CockpitColors.muted,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
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
    final accent = danger ? CockpitColors.danger : CockpitColors.emerald;
    return Semantics(
      button: enabled && onTap != null,
      enabled: enabled,
      label: title,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(CockpitRadius.medium),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: enabled ? .12 : .06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 19,
                    color: enabled ? accent : CockpitColors.dim,
                  ),
                ),
                const SizedBox(width: 12),
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
                                    ? CockpitColors.danger
                                    : CockpitColors.text)
                              : CockpitColors.dim,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: enabled
                                    ? CockpitColors.muted
                                    : CockpitColors.dim,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!enabled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      availability == SettingsItemAvailability.comingSoon
                          ? 'Sắp có'
                          : 'Đã khóa',
                      style: const TextStyle(
                        color: CockpitColors.dim,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  trailing ??
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: CockpitColors.dim,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
