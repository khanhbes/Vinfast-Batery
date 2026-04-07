import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firestore_safe_query.dart';
import '../models/trip_log_model.dart';

/// Repository cho TripLogs collection trên Firestore
class TripLogRepository {
  final FirebaseFirestore _firestore;

  TripLogRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference get _tripLogsRef => _firestore.collection('TripLogs');
  CollectionReference get _vehiclesRef => _firestore.collection('Vehicles');

  /// Lấy tất cả chuyến đi của xe, mới nhất trước (index-safe)
  Future<List<TripLogModel>> getTripLogs(String vehicleId) async {
    final docs = await FirestoreSafeQuery.orderedQuery(
      collection: _tripLogsRef,
      whereField: 'vehicleId',
      whereValue: vehicleId,
      orderByField: 'startTime',
      descending: true,
    );
    return docs.map((doc) => TripLogModel.fromFirestore(doc)).toList();
  }

  /// Lấy N chuyến đi gần nhất (dùng cho tính SoH) — index-safe
  Future<List<TripLogModel>> getRecentTrips(String vehicleId, {int count = 10}) async {
    final docs = await FirestoreSafeQuery.orderedQuery(
      collection: _tripLogsRef,
      whereField: 'vehicleId',
      whereValue: vehicleId,
      orderByField: 'startTime',
      descending: true,
      limit: count,
    );
    return docs.map((doc) => TripLogModel.fromFirestore(doc)).toList();
  }

  /// Lưu log chuyến đi + cập nhật ODO + battery + totalTrips trên Vehicle
  Future<void> saveTripAndUpdateVehicle({
    required TripLogModel trip,
    required String vehicleId,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final vehicleDocRef = _vehiclesRef.doc(vehicleId);
      final vehicleSnapshot = await transaction.get(vehicleDocRef);

      if (!vehicleSnapshot.exists) {
        throw Exception('Không tìm thấy xe: $vehicleId');
      }

      // Tạo trip log
      final newTripRef = _tripLogsRef.doc();
      transaction.set(newTripRef, trip.toFirestore());

      // Cập nhật xe
      transaction.update(vehicleDocRef, {
        'currentOdo': trip.endOdo,
        'currentBattery': trip.endBattery,
        'lastBatteryPercent': trip.endBattery,
        'totalTrips': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Xóa trip log
  Future<void> deleteTripLog(String tripId) async {
    await _tripLogsRef.doc(tripId).delete();
  }

  /// Thống kê chuyến đi
  Future<Map<String, dynamic>> getTripStats(String vehicleId) async {
    final trips = await getTripLogs(vehicleId);
    if (trips.isEmpty) {
      return {
        'totalTrips': 0,
        'totalDistance': 0.0,
        'totalBatteryUsed': 0,
        'avgEfficiency': 0.0,
        'avgDistance': 0.0,
      };
    }

    final totalDistance = trips.fold<double>(0, (s, t) => s + t.distance);
    final totalBattery = trips.fold<int>(0, (s, t) => s + t.batteryConsumed);

    return {
      'totalTrips': trips.length,
      'totalDistance': totalDistance,
      'totalBatteryUsed': totalBattery,
      'avgEfficiency': totalBattery > 0 ? totalDistance / totalBattery : 0.0,
      'avgDistance': totalDistance / trips.length,
    };
  }
}

final tripLogRepositoryProvider = Provider<TripLogRepository>((ref) {
  return TripLogRepository();
});
