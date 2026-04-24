import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Workspace card chuẩn Design System V3 — Dark Premium, glass border
class WorkspaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  const WorkspaceCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: padding ?? const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color ?? AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor ?? AppColors.glassBorder,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}
