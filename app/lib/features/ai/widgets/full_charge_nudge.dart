import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/widgets/luxe_kit.dart';

/// Suggests one full charge after several partial ones (QA 147). Only a
/// suggestion: the button fills in the target, charging still needs its usual
/// confirmation, and the wording makes no promise.
class FullChargeNudge extends StatelessWidget {
  const FullChargeNudge({
    super.key,
    required this.chargesSinceFull,
    required this.onChooseFull,
  });

  final int chargesSinceFull;
  final VoidCallback? onChooseFull;

  @override
  Widget build(BuildContext context) {
    return LuxeNotice(
      key: const ValueKey('full-charge-nudge'),
      icon: Icons.battery_charging_full_rounded,
      color: LuxeColors.champagne,
      message:
          'Đã $chargesSinceFull lần sạc chưa đầy. Sạc đầy một lần có thể giúp '
          '% trên đồng hồ chính xác hơn.',
      action: TextButton(
        key: const ValueKey('full-charge-choose'),
        onPressed: onChooseFull,
        child: const Text('Đặt mục tiêu 100%'),
      ),
    );
  }
}
