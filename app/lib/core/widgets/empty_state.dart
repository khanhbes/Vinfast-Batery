import 'package:flutter/material.dart';

import '../theme/luxe_theme.dart';
import 'luxe_kit.dart';

/// Empty state — LUXE (Task 117): a one-shot orbit emblem, quiet copy and an
/// optional outlined platinum action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_rounded,
    this.title = 'Không có dữ liệu',
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuxeEmptyArt(icon: icon),
          const SizedBox(height: 18),
          LuxeReveal(
            index: 1,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: LuxeText.item.copyWith(fontSize: 17),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            LuxeReveal(
              index: 2,
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: LuxeText.body,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 22),
            LuxeReveal(
              index: 3,
              child: OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(actionLabel!),
                style: OutlinedButton.styleFrom(
                  foregroundColor: LuxeColors.text,
                  iconColor: LuxeColors.emerald,
                  side: const BorderSide(color: LuxeColors.hairlineStrong),
                  minimumSize: const Size(48, 48),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
