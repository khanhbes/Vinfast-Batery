import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../ai/smart_charging_control_screen.dart';

/// Vehicle-scoped Smart Charge entry point for the V4 Charge tab.
class ChargeScreen extends ConsumerWidget {
  const ChargeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleContext = ref.watch(vehicleContextProvider);
    final vehicleId = vehicleContext.vehicleId;
    if (vehicleId.isEmpty) {
      return const Center(child: Text('Hãy chọn xe để sử dụng Smart Charge'));
    }
    // The context owns the identity; the async provider preserves a distinct
    // loading/error state instead of showing an endless spinner on failure.
    final vehicle = ref.watch(vehicleProvider(vehicleId));
    return vehicle.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Không thể tải thông tin xe: $error')),
      data: (value) => value == null
          ? const Center(child: Text('Chưa có dữ liệu xe đã chọn'))
          : SmartChargingControlScreen(
              vehicleId: vehicleId,
              currentSoc: value.currentBattery.toDouble(),
            ),
    );
  }
}
