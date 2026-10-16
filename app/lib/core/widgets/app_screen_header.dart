import 'package:flutter/material.dart';

import '../theme/luxe_theme.dart';
import 'luxe_kit.dart';
import 'luxe_settings.dart';

/// Screen header in the LUXE language (Task 117): optional glass back button,
/// a metal medallion and a quiet title/subtitle pair. API unchanged.
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
    final canPop = Navigator.canPop(context);

    return LuxeReveal(
      child: Padding(
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
                child: LuxeCircleButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Quay lại',
                  onPressed: onBack ?? () => Navigator.maybePop(context),
                ),
              ),
            LuxeMedallion(
              icon: icon,
              accent: iconColor ?? LuxeColors.emerald,
              size: 44,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: LuxeText.title.copyWith(fontSize: 22),
                    maxLines: 2,
                    softWrap: true,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: LuxeText.caption,
                      maxLines: 2,
                      softWrap: true,
                    ),
                  ],
                ],
              ),
            ),
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(width: 8),
              ...actions!,
            ],
          ],
        ),
      ),
    );
  }
}
