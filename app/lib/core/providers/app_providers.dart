export 'app_state_providers.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/charge_log_model.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/repositories/charge_log_repository.dart';
import '../services/session_service.dart';

// =============================================================================
// Shared Providers for the app
// =============================================================================

/// Selected vehicle ID
final selectedVehicleIdProvider = StateProvider<String>((ref) => '');

/// Restore vehicle ID from secure session storage (with prefs fallback)
final restoreVehicleIdProvider = FutureProvider<String>((ref) async {
  return await SessionService().getSelectedVehicleId() ?? '';
});

/// Get vehicle by ID
final vehicleProvider = FutureProvider.family<VehicleModel?, String>((ref, id) {
  if (id.isEmpty) return Future.value(null);
  return ref.watch(chargeLogRepositoryProvider).getVehicle(id);
});

/// Get all vehicles
final allVehiclesProvider = FutureProvider<List<VehicleModel>>((ref) async {
  final vehicles = await ref.watch(chargeLogRepositoryProvider).getAllVehicles();
  return vehicles;
});

/// Get charge logs for a vehicle
final chargeLogsProvider = FutureProvider.family<List<ChargeLogModel>, String>((ref, id) {
  if (id.isEmpty) return Future.value([]);
  return ref.watch(chargeLogRepositoryProvider).getChargeLogs(id);
});

/// Get vehicle statistics
final vehicleStatsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) {
  if (id.isEmpty) {
    return Future.value({
      'totalCharges': 0,
      'avgChargeGain': 0.0,
      'totalEnergyGained': 0,
      'avgChargeDuration': 0.0,
      'avgStartBattery': 0.0,
      'avgEndBattery': 0.0,
    });
  }
  return ref.watch(chargeLogRepositoryProvider).getStats(id);
});
