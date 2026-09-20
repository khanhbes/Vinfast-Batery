import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_ui_colors.dart';

/// Standard unified screen header matching the Cockpit Design System.
/// Supports both dark and light themes seamlessly.
class AppScreenHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final List<Widget>? actions;
  final Widget? leading;
  final VoidCallback? onBack;
  final bool showBackButton;

  const AppScreenHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.actions,
    this.leading,
    this.onBack,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppUiColors.of(context);
    final effectiveIconColor = iconColor ?? colors.primary;
    final canPop = Navigator.canPop(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          if (leading != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: leading!,
            )
          else if (showBackButton && canPop)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: colors.text,
                  size: 20,
                ),
                onPressed: onBack ?? () => Navigator.maybePop(context),
                tooltip: 'Quay lại',
                style: IconButton.styleFrom(
                  backgroundColor: colors.surfaceSoft.withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

          // Icon badge container
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: effectiveIconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: effectiveIconColor.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(
              icon,
              color: effectiveIconColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),

          // Title & subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 2,
                  softWrap: true,
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    softWrap: true,
                  ),
              ],
            ),
          ),

          // Actions
          if (actions != null && actions!.isNotEmpty) ...[
            const SizedBox(width: 8),
            ...actions!,
          ],
        ],
      ),
    ).appFadeSlideIn(index: 1);
  }
}
