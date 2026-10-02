import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../core/theme/app_ui_colors.dart';

/// Reusable Glassmorphism Container with frosted blur and translucent border
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 16.0,
    this.customBorderRadius,
    this.blur = 12.0,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.border,
    this.gradient,
    this.color,
    this.boxShadow,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final double borderRadius;
  final BorderRadiusGeometry? customBorderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final BoxBorder? border;
  final Gradient? gradient;
  final Color? color;
  final List<BoxShadow>? boxShadow;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final uiColors = AppUiColors.of(context);
    final effectiveRadius = customBorderRadius ?? BorderRadius.circular(borderRadius);

    final effectiveGradient = gradient ??
        (uiColors.dark
            ? LinearGradient(
                colors: [
                  const Color(0xFF1E293B).withValues(alpha: 0.65),
                  const Color(0xFF0F172A).withValues(alpha: 0.75),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.85),
                  Colors.white.withValues(alpha: 0.65),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ));

    final effectiveBorder = border ??
        Border.all(
          color: uiColors.glassBorder,
          width: 1.0,
        );

    final effectiveShadow = boxShadow ??
        [
          BoxShadow(
            color: uiColors.glassShadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ];

    Widget content = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        gradient: color == null ? effectiveGradient : null,
        borderRadius: effectiveRadius,
        border: effectiveBorder,
      ),
      child: child,
    );

    if (blur > 0) {
      content = ClipRRect(
        borderRadius: effectiveRadius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: content,
        ),
      );
    } else {
      content = ClipRRect(
        borderRadius: effectiveRadius,
        clipBehavior: clipBehavior,
        child: content,
      );
    }

    if (effectiveShadow.isNotEmpty || margin != null) {
      content = Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: effectiveRadius,
          boxShadow: effectiveShadow,
        ),
        child: content,
      );
    }

    return content;
  }
}

/// Helper styles and decorations for the AI Chatbot UI/UX
class ChatbotGlassTheme {
  /// User chat bubble decoration (iMessage-inspired blue gradient)
  static BoxDecoration userBubbleDecoration(BuildContext context, {bool isQueued = false}) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    if (isQueued) {
      return BoxDecoration(
        color: primary.withValues(alpha: 0.70),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(6),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
      );
    }

    return BoxDecoration(
      gradient: const LinearGradient(
        colors: [
          Color(0xFF0072BC),
          Color(0xFF005B94),
        ],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(18),
        topRight: Radius.circular(6),
        bottomLeft: Radius.circular(18),
        bottomRight: Radius.circular(18),
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0072BC).withValues(alpha: 0.28),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  /// Bot chat bubble decoration (frosted translucent surface)
  static BoxDecoration botBubbleDecoration(
    BuildContext context, {
    bool hasError = false,
  }) {
    final uiColors = AppUiColors.of(context);

    if (hasError) {
      return BoxDecoration(
        color: uiColors.dangerSurface.withValues(alpha: 0.3),
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: 0.7),
          width: 1.2,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
      );
    }

    return BoxDecoration(
      color: uiColors.dark
          ? const Color(0xFF1E293B).withValues(alpha: 0.75)
          : Colors.white.withValues(alpha: 0.92),
      border: Border.all(
        color: uiColors.glassBorder,
        width: 1.0,
      ),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(6),
        topRight: Radius.circular(18),
        bottomLeft: Radius.circular(18),
        bottomRight: Radius.circular(18),
      ),
      boxShadow: [
        BoxShadow(
          color: uiColors.glassShadow,
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  /// Card decoration with optional colored accent glow
  static BoxDecoration cardDecoration(
    BuildContext context, {
    Color? accentColor,
  }) {
    final uiColors = AppUiColors.of(context);
    final borderCol = accentColor != null
        ? accentColor.withValues(alpha: 0.35)
        : uiColors.glassBorder;

    return BoxDecoration(
      color: uiColors.dark
          ? const Color(0xFF161E2E).withValues(alpha: 0.88)
          : Colors.white.withValues(alpha: 0.95),
      border: Border.all(color: borderCol, width: 1.0),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: accentColor != null
              ? accentColor.withValues(alpha: 0.12)
              : uiColors.glassShadow,
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}
