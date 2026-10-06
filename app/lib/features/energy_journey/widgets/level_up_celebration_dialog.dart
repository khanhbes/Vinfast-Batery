import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/cockpit_design_system.dart';
import '../models/energy_level.dart';

/// Modal dialog celebrating a new unlocked Energy Level.
class LevelUpCelebrationDialog extends StatefulWidget {
  const LevelUpCelebrationDialog({
    super.key,
    required this.level,
    required this.onDismiss,
  });

  final EnergyLevel level;
  final VoidCallback onDismiss;

  static Future<void> show(
    BuildContext context, {
    required EnergyLevel level,
    required VoidCallback onDismiss,
  }) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: .85),
        builder: (_) => LevelUpCelebrationDialog(
          level: level,
          onDismiss: onDismiss,
        ),
      );

  @override
  State<LevelUpCelebrationDialog> createState() =>
      _LevelUpCelebrationDialogState();
}

class _LevelUpCelebrationDialogState extends State<LevelUpCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.level;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: CockpitColors.shell,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: level.badgeColor.withValues(alpha: .5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: level.badgeColor.withValues(alpha: .2),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top sparkling banner
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: level.badgeColor,
                ),
                const SizedBox(width: 6),
                Text(
                  'HÀNH TRÌNH NĂNG LƯỢNG',
                  style: TextStyle(
                    color: level.badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: level.badgeColor,
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Animated glowing badge icon
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: level.badgeColor.withValues(alpha: .15),
                    border: Border.all(
                      color: level.badgeColor.withValues(
                        alpha: _glowAnimation.value,
                      ),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: level.badgeColor.withValues(
                          alpha: _glowAnimation.value * .4,
                        ),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      level.icon,
                      size: 46,
                      color: level.badgeColor,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Celebration title
            const Text(
              'CHÚC MỪNG LÊN CẤP!',
              style: TextStyle(
                color: CockpitColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),

            const SizedBox(height: 8),

            // Level & name pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: level.badgeColor.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: level.badgeColor.withValues(alpha: .35),
                ),
              ),
              child: Text(
                'Cấp ${level.level}: ${level.name}',
                style: TextStyle(
                  color: level.badgeColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Tier & description
            Text(
              'Nhóm: ${level.tierName}',
              style: const TextStyle(
                color: CockpitColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              level.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CockpitColors.dim,
                fontSize: 12,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 24),

            // Continue button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.onDismiss();
                  Navigator.of(context).pop();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: level.badgeColor,
                  foregroundColor: CockpitColors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CockpitRadius.medium),
                  ),
                ),
                child: const Text(
                  'TIẾP TỤC HÀNH TRÌNH',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
