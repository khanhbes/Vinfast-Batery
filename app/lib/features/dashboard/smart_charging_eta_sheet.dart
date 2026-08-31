import 'package:flutter/material.dart';

import '../../data/services/charge_tracking_service.dart';
import '../ai/smart_charging_control_screen.dart';

/// Compatibility wrapper for callers that still reference the old ETA sheet.
/// Smart Charge is now the only prediction/control flow.
class SmartChargingEtaSheet extends StatelessWidget {
  const SmartChargingEtaSheet({
    super.key,
    required this.vehicleId,
    required this.initialBattery,
    required this.currentOdo,
    required this.chargeService,
  });

  final String vehicleId;
  final int initialBattery;
  final int currentOdo;
  // Retained for source compatibility; never used to control the relay.
  final ChargeTrackingService chargeService;

  @override
  Widget build(BuildContext context) {
    return SmartChargingControlScreen(
      vehicleId: vehicleId,
      currentSoc: initialBattery.toDouble(),
    );
  }
}
