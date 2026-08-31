import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import 'smart_charging_control_screen.dart';

/// Compatibility entry point. Prediction and relay control intentionally live
/// in one workspace so Dashboard and AI Models cannot diverge.
class AiChargingPredictorScreen extends ConsumerWidget {
  const AiChargingPredictorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedVehicleIdProvider);
    // Never guess a vehicle here.  Smart Charge is scoped to the explicitly
    // selected vehicle so that a legacy entry point cannot control another
    // car (or create a session under the wrong owner/vehicle context).
    if (selectedId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Smart Charge')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Hãy chọn một xe trong Garage trước khi sử dụng Smart Charge.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      );
    }
    final vehicleId = selectedId;
    final vehicle = ref.watch(vehicleProvider(vehicleId)).value;
    if (vehicle == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Smart Charge')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Chưa tải được dữ liệu xe đã chọn. Hãy thử lại sau khi đồng bộ Garage.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return SmartChargingControlScreen(
      vehicleId: vehicleId,
      currentSoc: vehicle.currentBattery.toDouble(),
    );
  }
}
