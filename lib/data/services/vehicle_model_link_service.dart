import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vehicle_model.dart';
import '../models/vinfast_model_spec.dart';
import '../repositories/vehicle_spec_repository.dart';

/// ========================================================================
/// VehicleModelLinkService — Liên kết xe người dùng ↔ model VinFast
/// ========================================================================
class VehicleModelLinkService {
  final FirebaseFirestore _firestore;

  VehicleModelLinkService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Liên kết xe với model VinFast (manual flow)
  Future<void> linkModel({
    required String vehicleId,
    required VinFastModelSpec spec,
  }) async {
    await _firestore.collection('Vehicles').doc(vehicleId).update({
      'vinfastModelId': spec.modelId,
      'vinfastModelName': spec.modelName,
      'specVersion': spec.specVersion,
      'defaultEfficiency': spec.defaultEfficiencyKmPerPercent,
      'specLinkedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('🔗 Linked $vehicleId → ${spec.modelName} (v${spec.specVersion})');
  }

  /// Bỏ liên kết model
  Future<void> unlinkModel(String vehicleId) async {
    await _firestore.collection('Vehicles').doc(vehicleId).update({
      'vinfastModelId': FieldValue.delete(),
      'vinfastModelName': FieldValue.delete(),
      'specVersion': FieldValue.delete(),
      'specLinkedAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('🔗 Unlinked $vehicleId from VinFast model');
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
final vehicleModelLinkServiceProvider = Provider<VehicleModelLinkService>((ref) {
  return VehicleModelLinkService();
});
