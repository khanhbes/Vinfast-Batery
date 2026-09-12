import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/api_service.dart';

import '../models/vehicle_model.dart';
import '../models/vinfast_model_spec.dart';
import '../repositories/vehicle_spec_repository.dart';

/// ========================================================================
/// VehicleModelLinkService — Liên kết xe người dùng ↔ model VinFast
/// ========================================================================
class VehicleModelLinkService {
  VehicleModelLinkService();

  /// Liên kết xe với model VinFast (manual flow)
  Future<void> linkModel({
    required String vehicleId,
    required VinFastModelSpec spec,
  }) async {
    final result = await ApiService().put(
      '/api/user/vehicles/$vehicleId/catalog',
      {'catalogId': spec.modelId},
    );
    if (result['success'] != true) {
      throw StateError(result['error']?.toString() ?? 'Catalog link failed');
    }
    debugPrint(
      '🔗 Linked $vehicleId → ${spec.modelName} (v${spec.specVersion})',
    );
  }

  /// Bỏ liên kết model
  Future<void> unlinkModel(String vehicleId) async {
    throw UnsupportedError(
      'Catalog links cannot be cleared; select another published vehicle instead.',
    );
  }

  /// Auto-match: thử tìm model phù hợp theo tên xe
  Future<VinFastModelSpec?> autoMatch({
    required VehicleModel vehicle,
    required VehicleSpecRepository specRepo,
  }) async {
    if (vehicle.hasModelLink) return null; // Đã link rồi
    return specRepo.matchByVehicleName(vehicle.vehicleName);
  }

  /// Auto-match + link nếu tìm thấy. Trả về spec đã link hoặc null.
  Future<VinFastModelSpec?> autoMatchAndLink({
    required VehicleModel vehicle,
    required VehicleSpecRepository specRepo,
  }) async {
    final spec = await autoMatch(vehicle: vehicle, specRepo: specRepo);
    if (spec != null) {
      await linkModel(vehicleId: vehicle.vehicleId, spec: spec);
    }
    return spec;
  }
}

/// Riverpod provider
final vehicleModelLinkServiceProvider = Provider<VehicleModelLinkService>((
  ref,
) {
  return VehicleModelLinkService();
});
