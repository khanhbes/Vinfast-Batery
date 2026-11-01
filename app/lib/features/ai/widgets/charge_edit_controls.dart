import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/theme/plan_style.dart';
import '../../../core/widgets/luxe_kit.dart';

/// − / + beside a clock time or value (Theo giờ, Đổi giờ ngắt): a 48 dp
/// glass circle in the plan's colours.
class ChargeStepButton extends StatelessWidget {
  const ChargeStepButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final plan = PlanStyle.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Ink(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: plan.glassColors),
              border: Border.all(color: plan.glassBorder),
            ),
            child: Icon(
              icon,
              size: 22,
              color: onTap == null ? LuxeColors.dim : LuxeColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// The verified-change strip of the edit sheets (Đổi mục tiêu, Đổi giờ
/// ngắt): a spinner with [busyLabel] while the server re-arms the outlet,
/// then emerald [doneLabel] once it read the change back.
class ChargeEditProgress extends StatelessWidget {
  const ChargeEditProgress({
    super.key,
    required this.done,
    required this.busyLabel,
    required this.doneLabel,
    required this.keyPrefix,
  });

  final bool done;
  final String busyLabel;
  final String doneLabel;

  /// Keys `<prefix>-busy` / `<prefix>-done` (tests).
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey(done ? '$keyPrefix-done' : '$keyPrefix-busy'),
    height: 60,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(99),
      color: done
          ? LuxeColors.emerald.withValues(alpha: 0.15)
          : LuxeColors.glass,
      border: Border.all(
        color: done
            ? LuxeColors.emerald.withValues(alpha: 0.6)
            : LuxeColors.hairline,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (done)
          const Icon(Icons.check_circle_rounded, color: LuxeColors.emerald)
        else
          SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: LuxeColors.champagne,
              value: luxeReduceMotion(context) ? 0.7 : null,
            ),
          ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            done ? doneLabel : busyLabel,
            style: const TextStyle(color: LuxeColors.text, fontSize: 15),
          ),
        ),
      ],
    ),
  );
}
