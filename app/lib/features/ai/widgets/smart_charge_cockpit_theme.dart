import 'package:flutter/material.dart';

import '../../../core/theme/cockpit_design_system.dart';

abstract final class SmartChargeCockpitColors {
  static const background = CockpitColors.background;
  static const surface = CockpitColors.surface;
  static const elevated = CockpitColors.elevated;
  static const border = CockpitColors.border;
  static const borderStrong = CockpitColors.borderStrong;
  static const verified = CockpitColors.emerald;
  static const warning = CockpitColors.amber;
  static const danger = CockpitColors.danger;
  static const text = CockpitColors.text;
  static const muted = CockpitColors.muted;
  static const dim = CockpitColors.dim;
}

class SmartChargeCockpitTheme extends StatelessWidget {
  const SmartChargeCockpitTheme({
    super.key,
    required this.child,
    this.adaptive = false,
  });
  final Widget child;
  final bool adaptive;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: adaptive
          ? Theme.of(context).scaffoldBackgroundColor
          : SmartChargeCockpitColors.background,
      child: child,
    );
  }
}

class CockpitPanel extends StatelessWidget {
  const CockpitPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.highlight = false,
    this.adaptive = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final bool highlight;
  final bool adaptive;

  @override
  Widget build(BuildContext context) => adaptive
      ? Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: child,
        )
      : CockpitSurface(padding: padding, highlight: highlight, child: child);
}
