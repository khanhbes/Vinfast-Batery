import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/vehicle_learning_status.dart';
import '../../data/services/server_smart_charger_service.dart';
import '../../data/services/trip_energy_model.dart';
import '../../features/auth/auth_providers.dart';
import '../constants/app_constants.dart';

/// What the server learned for one vehicle (Task 127), read once and shared
/// so every screen shows the same km/% and charge time (QA 129: Overview,
/// Battery monitor, AI cá nhân and the trip planner disagreed).
class LearnedModels {
  const LearnedModels({this.trip, this.whPerPct, this.powerW, this.status});

  /// Trained trip model, or null while only the catalog prior exists.
  final TripModelParams? trip;

  /// Wall Wh per 1 % and typical charging power learned from real charges.
  final double? whPerPct;
  final double? powerW;
  final VehicleLearningStatus? status;

  static LearnedModels fromStatus(VehicleLearningStatus? status) {
    if (status == null) return const LearnedModels();
    double? positive(Object? value) {
      final number = value is num ? value.toDouble() : null;
      return number != null && number.isFinite && number > 0 ? number : null;
    }

    final charge = status.charge.raw;
    final trip = status.tripParams;
    return LearnedModels(
      trip: trip != null && trip.source == TripKmSource.model ? trip : null,
      whPerPct: positive(charge['whPerPct']),
      powerW: positive(charge['powerW']),
      status: status,
    );
  }
}

/// Invalidate after training so every screen picks up the new model.
final learnedModelsProvider = FutureProvider.family<LearnedModels, String>((
  ref,
  vehicleId,
) async {
  // Re-read once the session is signed in: a read during app start, before
  // auth was ready, used to stick for the whole run (QA 130: the Xiaomi
  // showed the catalog 1.20 km/% instead of the learned 1.21).
  String? uid;
  try {
    uid = ref.watch(currentUidProvider);
  } on Object {
    uid = null;
  }
  if (vehicleId.isEmpty || uid == null || !AppConstants.isApiConfigured) {
    return const LearnedModels();
  }
  ServerSmartChargerService? api;
  try {
    api = ServerSmartChargerService();
    return LearnedModels.fromStatus(await api.learningStatus(vehicleId));
  } on Object {
    // Offline or a slow server: fall back to the catalog numbers (screens
    // say so) and try again shortly instead of keeping the failure.
    final retry = Timer(const Duration(seconds: 30), ref.invalidateSelf);
    ref.onDispose(retry.cancel);
    return const LearnedModels();
  } finally {
    api?.close();
  }
});
