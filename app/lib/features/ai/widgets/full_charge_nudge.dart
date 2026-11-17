import '../../../core/services/dev_view.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/widgets/luxe_kit.dart';
import '../../../data/models/smart_charging_session.dart';

/// QA 157/158: on the owner's charges the two after a full one were within
/// about 1 %; from the third on the gauge had drifted. Shown before that
/// third charge, like the server's trust (used instead when a forecast
/// carries it).
const fullChargeSuggestAfter = 2;

/// Real charges since the last one that reached full, newest first (QA 148).
/// From the history, not from readings: whoever never types a % needs this most.
int chargesSinceFull(Iterable<SmartChargingSession> history) {
  var count = 0;
  for (final session in history) {
    if (!session.state.isTerminal || session.energyUsedWh < 30) continue;
    if (session.stopReason == ChargingStopReason.batteryFull ||
        (session.actualEndSoc ?? 0) >= 99) {
      break;
    }
    count++;
  }
  return count;
}

/// Suggests one full charge after several partial ones (QA 147). Only a
/// suggestion: the button fills in the target, charging still needs its usual
/// confirmation, and the wording makes no promise.
class FullChargeNudge extends StatelessWidget {
  const FullChargeNudge({
    super.key,
    required this.chargesSinceFull,
    required this.onChooseFull,
    this.anchored = true,
  });

  final int chargesSinceFull;

  /// False when no charge has ever reached full (QA 158).
  final bool anchored;
  final VoidCallback? onChooseFull;

  @override
  Widget build(BuildContext context) {
    // QA 158: the button under the text; beside it, it pushed the text past
    // the edge at 320 dp.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeNotice(
          key: const ValueKey('full-charge-nudge'),
          icon: Icons.battery_charging_full_rounded,
          color: LuxeColors.champagne,
          message: !DevViewScope.on(context)
              ? 'Sạc đầy một lần để đồng hồ xe chính xác lại.'
              : anchored
              ? 'Đã $chargesSinceFull lần sạc chưa đầy. Đồng hồ xe lệch dần giữa hai '
                    'lần sạc đầy, nên dự đoán % lần này có thể lệch nhiều hơn. Sạc '
                    'đầy một lần để đồng hồ chỉnh lại.'
              : 'Chưa có lần sạc đầy nào làm mốc cho đồng hồ xe. Sạc đầy một lần để '
                    'đồng hồ chỉnh lại và dự đoán % chính xác hơn.',
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const ValueKey('full-charge-choose'),
            onPressed: onChooseFull,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('Đặt mục tiêu 100%'),
          ),
        ),
      ],
    );
  }
}
