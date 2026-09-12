import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session_service.dart';
import 'vehicle_providers.dart';
import '../models/vehicle_context.dart';
import '../models/resolved_vehicle_context.dart';
import '../../data/repositories/vehicle_spec_repository.dart';

/// Single source of truth for the selected vehicle across all V4 screens.
final vehicleContextProvider = Provider<VehicleContext>((ref) {
  final id = ref.watch(selectedVehicleIdProvider);
  final vehicle = id.isEmpty
      ? null
      : ref.watch(vehicleProvider(id)).valueOrNull;
  return VehicleContext(vehicleId: id, vehicle: vehicle);
});

/// Restores the last vehicle once at app startup without changing charging
/// session identity.
final vehicleContextRestoreProvider = FutureProvider<void>((ref) async {
  final id = await SessionService().getSelectedVehicleId();
  if (id != null && id.isNotEmpty) {
    ref.read(selectedVehicleIdProvider.notifier).state = id;
  }
});

final resolvedVehicleContextProvider = FutureProvider<ResolvedVehicleContext?>((
  ref,
) async {
  final context = ref.watch(vehicleContextProvider);
  final vehicle = context.vehicle;
  if (vehicle == null) return null;
  final catalogId = vehicle.catalogId ?? vehicle.vinfastModelId;
  final catalog = catalogId == null || catalogId.isEmpty
      ? null
      : await ref.watch(vehicleSpecRepositoryProvider).getSpec(catalogId);
  return ResolvedVehicleContext(vehicle: vehicle, catalog: catalog);
});
