import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Card kiểu glassmorphism với gradient border — Dark Premium V3
class GradientCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final List<Color>? gradientColors;
  final double borderRadius;
  final VoidCallback? onTap;

  const GradientCard({
    super.key,
    required this.child,
    this.padding,
    this.gradientColors,
    this.borderRadius = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = gradientColors ??
        [
          AppColors.vinfastBlue.withValues(alpha: 0.15),
          AppColors.info.withValues(alpha: 0.05),
        ];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          border: Border.all(
            color: AppColors.glassBorder,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: padding ?? const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
