import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/app_providers.dart';
import 'smart_charging_control_screen.dart';

/// Compatibility entry point. Prediction and relay control intentionally live
/// in one workspace so Dashboard and AI Models cannot diverge.
class AiChargingPredictorScreen extends ConsumerWidget {
  const AiChargingPredictorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedVehicleIdProvider);
    final vehicleId = selectedId.isEmpty
        ? AppConstants.defaultVehicleId
        : selectedId;
    final vehicle = ref.watch(vehicleProvider(vehicleId)).value;
    return SmartChargingControlScreen(
      vehicleId: vehicleId,
      currentSoc: vehicle?.currentBattery.toDouble() ?? 20,
    );
  }
}
