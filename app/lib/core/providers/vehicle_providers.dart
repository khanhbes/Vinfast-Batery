import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/vehicle_model.dart';
import '../../data/repositories/charge_log_repository.dart';

final selectedVehicleIdProvider = StateProvider<String>((ref) => '');

final vehicleProvider = FutureProvider.family<VehicleModel?, String>((ref, id) {
  if (id.isEmpty) return Future.value(null);
  return ref.watch(chargeLogRepositoryProvider).getVehicle(id);
});
