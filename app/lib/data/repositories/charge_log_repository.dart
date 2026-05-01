import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firestore_safe_query.dart';
import '../models/charge_log_model.dart';
import '../models/vehicle_model.dart';

/// Timeout chung cho mọi Firestore one-shot read trong repository này.
/// Nếu mạng treo / cache offline rỗng → ném `TimeoutException` thay vì
/// hang vô hạn ở UI (sẽ bị catch và biến thành `null` / list rỗng).
const _kFirestoreReadTimeout = Duration(seconds: 8);

// =============================================================================
// REPOSITORY — Firebase Cloud Firestore
// =============================================================================

class ChargeLogRepository {
  final FirebaseFirestore _firestore;

  ChargeLogRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference get _chargeLogsRef =>
      _firestore.collection('ChargeLogs');

  CollectionReference get _vehiclesRef =>
      _firestore.collection('Vehicles');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ── Vehicle CRUD ──────────────────────────────────────────────────────────

  /// Lấy thông tin 1 xe theo vehicleId.
  ///
  /// Robust: timeout 8s, swallow `permission-denied` / `not-found` về `null`
  /// để UI fallback nhẹ thay vì hang spinner mãi.
  Future<VehicleModel?> getVehicle(String vehicleId) async {
    if (vehicleId.isEmpty) return null;
    try {
      final doc = await _vehiclesRef
          .doc(vehicleId)
          .get()
          .timeout(_kFirestoreReadTimeout);
      if (!doc.exists) return null;
      return VehicleModel.fromFirestore(doc);
    } on FirebaseException catch (e) {
      // Bad selectedVehicleId (xe đã bị xoá / không thuộc user) → null thay vì throw.
      if (e.code == 'permission-denied' || e.code == 'not-found') {
        debugPrint('[ChargeLogRepo] getVehicle($vehicleId) ${e.code} → null');
        return null;
      }
      rethrow; // network / unavailable / unknown → cho UI hiện error.
    } on TimeoutException {
      debugPrint('[ChargeLogRepo] getVehicle($vehicleId) timed out after 8s');
      throw TimeoutException(
        'Không kết nối được Firestore (8s). Kiểm tra mạng hoặc thử lại.',
        _kFirestoreReadTimeout,
      );
    }
  }

  /// Lấy tất cả xe của user hiện tại.
  ///
  /// KHÔNG seed xe mặc định nữa (PLAN1: client không được auto-write
  /// vào Vehicles với hardcoded ID — gây permission-denied + nuốt UI).
  /// User phải tự thêm xe qua Garage.
  Future<List<VehicleModel>> getAllVehicles() async {
    final uid = _uid;
    Query query = _vehiclesRef;
    if (uid != null) {
      query = query.where('ownerUid', isEqualTo: uid);
    }
    try {
      final snapshot = await query.get().timeout(_kFirestoreReadTimeout);
      return snapshot.docs
          .where((doc) {
            final data = doc.data() as Map<String, dynamic>?;
            return data?['isDeleted'] != true;
          })
          .map((doc) => VehicleModel.fromFirestore(doc))
          .toList();
    } on TimeoutException {
      throw TimeoutException(
        'Không kết nối được Firestore (8s). Kiểm tra mạng hoặc thử lại.',
        _kFirestoreReadTimeout,
      );
    }
  }

  /// Thêm xe mới vào Firestore
  Future<void> addVehicle({
    required String vehicleId,
    required String vehicleName,
    String avatarColor = '#00C853',
  }) async {
    final docRef = _vehiclesRef.doc(vehicleId);
    final existing = await docRef.get();
    if (existing.exists) {
      throw Exception('Mã xe "$vehicleId" đã tồn tại. Vui lòng dùng mã khác.');
    }
    await docRef.set({
      'vehicleId': vehicleId,
      'vehicleName': vehicleName,
      'currentOdo': 0,
      'totalCharges': 0,
      'lastBatteryPercent': 100,
      'avatarColor': avatarColor,
      'ownerUid': _uid,
      'isDeleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Xóa xe và toàn bộ dữ liệu liên quan (ChargeLogs, TripLogs, MaintenanceTasks)
  Future<void> deleteVehicle(String vehicleId) async {
    // Lấy tất cả documents liên quan
    final chargeLogs = await _chargeLogsRef
        .where('vehicleId', isEqualTo: vehicleId)
        .get();
    final tripLogs = await _firestore
        .collection('TripLogs')
        .where('vehicleId', isEqualTo: vehicleId)
        .get();
    final maintenanceTasks = await _firestore
        .collection('MaintenanceTasks')
        .where('vehicleId', isEqualTo: vehicleId)
        .get();

    final batch = _firestore.batch();

    for (final doc in chargeLogs.docs) {
      batch.delete(doc.reference);
    }
    for (final doc in tripLogs.docs) {
      batch.delete(doc.reference);
    }
    for (final doc in maintenanceTasks.docs) {
      batch.delete(doc.reference);
    }

    // Xóa document xe
    batch.delete(_vehiclesRef.doc(vehicleId));

    await batch.commit();
  }

  // ── Charge Log CRUD ───────────────────────────────────────────────────────

  /// Lấy danh sách charge logs theo vehicleId, sắp xếp mới nhất trước (index-safe)
  Future<List<ChargeLogModel>> getChargeLogs(String vehicleId) async {
    final docs = await FirestoreSafeQuery.orderedQuery(
      collection: _chargeLogsRef,
      whereField: 'vehicleId',
      whereValue: vehicleId,
      orderByField: 'startTime',
      descending: true,
    );
    return docs.map((doc) => ChargeLogModel.fromFirestore(doc)).toList();
  }

  /// Lưu charge log mới + cập nhật ODO xe bằng Firestore Transaction
  ///
  /// Transaction đảm bảo tính toàn vẹn dữ liệu:
  /// 1. Tạo document mới trong collection `ChargeLogs`
  /// 2. Cập nhật `currentOdo`, `totalCharges`, `lastBatteryPercent` trong `Vehicles`
  Future<void> saveChargeLogAndUpdateOdo({
    required ChargeLogModel chargeLog,
    required String vehicleId,
    required int newOdo,
  }) async {
    await _firestore.runTransaction((transaction) async {
      // Đọc document xe hiện tại
      final vehicleDocRef = _vehiclesRef.doc(vehicleId);
      final vehicleSnapshot = await transaction.get(vehicleDocRef);

      if (!vehicleSnapshot.exists) {
        throw Exception('Không tìm thấy xe với ID: $vehicleId');
      }

      final currentVehicle = VehicleModel.fromFirestore(vehicleSnapshot);

      // Kiểm tra ODO trong transaction để tránh race condition
      if (newOdo < currentVehicle.currentOdo) {
        throw Exception(
          'ODO ($newOdo km) phải ≥ ODO hiện tại (${currentVehicle.currentOdo} km)',
        );
      }

      // 1. Tạo document mới trong ChargeLogs
      final newChargeLogRef = _chargeLogsRef.doc();
      final logData = chargeLog.toFirestore();
      if (_uid != null) logData['ownerUid'] = _uid;
      logData['isDeleted'] = false;
      transaction.set(newChargeLogRef, logData);

      // 2. Cập nhật xe: ODO + totalCharges + lastBatteryPercent
      transaction.update(vehicleDocRef, {
        'currentOdo': newOdo,
        'totalCharges': FieldValue.increment(1),
        'lastBatteryPercent': chargeLog.endBatteryPercent,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Xóa một charge log 
  Future<void> deleteChargeLog(String logId) async {
    await _chargeLogsRef.doc(logId).delete();
  }

  // ── Statistics ────────────────────────────────────────────────────────────

  /// Lấy thống kê tổng hợp cho xe
  Future<Map<String, dynamic>> getStats(String vehicleId) async {
    final logs = await getChargeLogs(vehicleId);
    if (logs.isEmpty) {
      return {
        'totalCharges': 0,
        'avgChargeGain': 0.0,
        'totalEnergyGained': 0,
        'avgChargeDuration': 0.0,
        'avgStartBattery': 0.0,
        'avgEndBattery': 0.0,
      };
    }

    final totalCharges = logs.length;
    final totalGain = logs.fold<int>(0, (acc, l) => acc + l.chargeGain);
    final totalDurationHours = logs.fold<double>(
      0,
      (acc, l) => acc + l.chargeDuration.inMinutes / 60.0,
    );
    final avgStart =
        logs.fold<int>(0, (acc, l) => acc + l.startBatteryPercent) /
            totalCharges;
    final avgEnd =
        logs.fold<int>(0, (acc, l) => acc + l.endBatteryPercent) /
            totalCharges;

    return {
      'totalCharges': totalCharges,
      'avgChargeGain': totalGain / totalCharges,
      'totalEnergyGained': totalGain,
      'avgChargeDuration': totalDurationHours / totalCharges,
      'avgStartBattery': avgStart,
      'avgEndBattery': avgEnd,
    };
  }
}

/// Riverpod provider cho ChargeLogRepository
final chargeLogRepositoryProvider = Provider<ChargeLogRepository>((ref) {
  return ChargeLogRepository();
});
