import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/vehicle_model.dart';
import '../../data/repositories/charge_log_repository.dart';
import 'app_providers.dart' show allVehiclesProvider;

final selectedVehicleIdProvider = StateProvider<String>((ref) => '');

/// The vehicle, live (QA 137: was a one-shot read, so a % or ODO saved from
/// a reading, a confirmed charge or the server stayed old on the Overview,
/// Charge tab, Settings and Maintenance until the app restarted). Every
/// change after the first value also refreshes the vehicle list (switcher,
/// garage) so no screen keeps an old %.
final vehicleProvider = StreamProvider.family<VehicleModel?, String>((ref, id) {
  if (id.isEmpty) return Stream.value(null);
  var first = true;
  return ref.watch(chargeLogRepositoryProvider).watchVehicle(id).map((
    vehicle,
  ) {
    if (!first) ref.invalidate(allVehiclesProvider);
    first = false;
    return vehicle;
  });
});
