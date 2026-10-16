import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/luxe_theme.dart';

/// Luxe settings kit shared by the Settings tab, System settings, Profile and
/// Guide: hairline glass groups, monochrome platinum medallions, a platinum
/// toggle and quiet section labels. Purely presentational.

Duration _motion(BuildContext context, int ms) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: ms);

/// Spaced uppercase label above a group.
class LuxeSectionLabel extends StatelessWidget {
  const LuxeSectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 26, 6, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: LuxeText.label.copyWith(
              letterSpacing: 1.8,
              fontSize: 11.5,
              color: LuxeColors.platinumMid,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Glass group with hairline dividers inset past the medallion.
class LuxeSettingsGroup extends StatelessWidget {
  const LuxeSettingsGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LuxeGlass(
    radius: 22,
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1)
            const Divider(height: 1, indent: 70, endIndent: 16),
        ],
      ],
    ),
  );
}

/// Round brushed-metal icon well. [accent] tints the glyph and the rim.
class LuxeMedallion extends StatelessWidget {
  const LuxeMedallion({
    super.key,
    required this.icon,
    this.accent,
    this.size = 40,
  });
  final IconData icon;
  final Color? accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final a = accent ?? LuxeColors.platinum;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF26282C), Color(0xFF0F1012)],
        ),
        border: Border.all(color: a.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, size: size * 0.46, color: a),
    );
  }
}

/// One settings row. Tap feedback is a soft highlight; disabled rows (no
/// [onTap] and [comingSoon]) show a quiet "Sắp có" tag instead of a chevron.
class LuxeSettingsRow extends StatelessWidget {
  const LuxeSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.accent,
    this.comingSoon = false,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? accent;
  final bool comingSoon;

  /// Small inline tag next to the title (counts, status).
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !comingSoon;
    final trail =
        trailing ??
        (comingSoon
            ? const LuxeTag('Sắp có')
            : (onTap == null
                  ? null
                  : const Icon(
                      Icons.chevron_right_rounded,
                      color: LuxeColors.dim,
                      size: 22,
                    )));
    return Semantics(
      button: enabled,
      enabled: enabled || trailing != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap!();
                }
              : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              child: Row(
                children: [
                  Opacity(
                    opacity: comingSoon ? 0.5 : 1,
                    child: LuxeMedallion(icon: icon, accent: accent),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: comingSoon
                                    ? LuxeColors.muted
                                    : LuxeColors.text,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w500,
                                height: 1.25,
                              ),
                            ),
                            ?badge,
                          ],
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            style: LuxeText.caption.copyWith(fontSize: 12.5),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trail != null) ...[const SizedBox(width: 8), trail],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny hairline tag ("Sắp có", "Sẵn sàng", "65 huy hiệu").
class LuxeTag extends StatelessWidget {
  const LuxeTag(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? LuxeColors.platinumMid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: c.withValues(alpha: 0.1),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Platinum toggle: the knob slides on a dark track that lights emerald.
class LuxeSwitch extends StatelessWidget {
  const LuxeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final d = _motion(context, 260);
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      label: semanticLabel,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onChanged!(!value);
              },
        child: SizedBox(
          width: 60,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: d,
              curve: LuxeMotion.enter,
              width: 52,
              height: 30,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: value
                    ? LuxeColors.emerald.withValues(alpha: 0.28)
                    : const Color(0xFF17181B),
                border: Border.all(
                  color: value
                      ? LuxeColors.emerald.withValues(alpha: 0.7)
                      : LuxeColors.hairlineStrong,
                ),
              ),
              child: AnimatedAlign(
                duration: d,
                curve: LuxeMotion.enter,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: value
                          ? const [LuxeColors.platinumHi, LuxeColors.platinum]
                          : const [
                              LuxeColors.platinumMid,
                              LuxeColors.platinumLow,
                            ],
                    ),
                    boxShadow: value
                        ? const [
                            BoxShadow(
                              color: LuxeColors.emeraldGlow,
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quiet danger pill used for "Đăng xuất".
class LuxeDangerButton extends StatelessWidget {
  const LuxeDangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.logout_rounded,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: LuxeColors.danger,
      side: BorderSide(color: LuxeColors.danger.withValues(alpha: 0.4)),
      backgroundColor: LuxeColors.danger.withValues(alpha: 0.05),
      minimumSize: const Size.fromHeight(54),
    ),
    icon: Icon(icon, size: 20),
    label: Text(label),
  );
}

/// Luxe confirm dialog for sign-out style decisions. Returns true on confirm.
Future<bool?> showLuxeConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = true,
}) => showDialog<bool>(
  context: context,
  builder: (ctx) => Theme(
    data: LuxeTheme.of(ctx),
    child: AlertDialog(
      backgroundColor: const Color(0xFF121315),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: LuxeColors.hairline),
      ),
      title: Text(title, style: LuxeText.item.copyWith(fontSize: 18)),
      content: Text(message, style: LuxeText.body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Hủy'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(
            foregroundColor: danger ? LuxeColors.danger : LuxeColors.emerald,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  ),
);

/// Page title block for pushed luxe pages: glass back button, eyebrow,
/// title and an optional caption.
class LuxePageHeader extends StatelessWidget {
  const LuxePageHeader({
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
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (canPop)
              Tooltip(
                message: 'Quay lại',
                child: Material(
                  type: MaterialType.transparency,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: LuxeColors.glass,
                        border: Border.all(color: LuxeColors.hairline),
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        size: 20,
                        color: LuxeColors.text,
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            ?trailing,
          ],
        ),
        const SizedBox(height: 18),
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
}
