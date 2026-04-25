import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/charge_sample_model.dart';
import '../../core/services/api_service.dart';

/// Repository để gửi ChargeSample (training data) về backend
/// 
/// Tối ưu hóa: Offline queue → auto-sync khi có mạng
class ChargeSampleRepository {
  static final ChargeSampleRepository _instance = ChargeSampleRepository._internal();
  factory ChargeSampleRepository() => _instance;
  ChargeSampleRepository._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ApiService _apiService = ApiService();

  /// Check connectivity
  Future<bool> _hasConnection() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Tạo và gửi ChargeSample từ dữ liệu session sạc
  /// 
  /// Flow:
  /// 1. Nhận prediction metadata từ ChargeLog
  /// 2. Thu thập location
  /// 3. Tạo ChargeSample
  /// 4. Save local → queue for sync
  Future<void> logChargeSession({
    required String sessionId,
    required String vehicleId,
    required String ownerUid,
    required DateTime requestedAt,
    required int startBatteryPercent,
    required int targetBatteryPercent,
    required double predictedDurationSec,
    required DateTime predictedStopAt,
    required String modelSource,
    required String modelVersion,
    required bool isBeta,
    required int? actualStopBatteryPercent,
    required DateTime? actualStopAt,
    required bool eligibleForTraining,
  }) async {
    // Thu thập location (best effort)
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint('📍 Location not available: $e');
    }

    // Tạo ChargeSample
    final sample = ChargeSampleModel(
      sessionId: sessionId,
      ownerUid: ownerUid,
      vehicleId: vehicleId,
      startBatteryPercent: startBatteryPercent,
      targetBatteryPercent: targetBatteryPercent,
      predictedDurationSec: predictedDurationSec,
      predictedStopAt: predictedStopAt,
      modelSource: modelSource,
      modelVersion: modelVersion,
      actualEndBatteryPercent: actualStopBatteryPercent,
      actualEndTime: actualStopAt,
      actualDurationSec: actualStopAt != null
          ? actualStopAt.difference(requestedAt).inSeconds.toDouble()
          : null,
      latitude: position?.latitude,
      longitude: position?.longitude,
      eligibleForTraining: eligibleForTraining,
      createdAt: requestedAt,
    );

    // Lưu vào Firestore (local cache)
    try {
      await _firestore
          .collection('ChargeSamples')
          .doc(sessionId)
          .set(sample.toFirestore());
      debugPrint('💾 ChargeSample saved to Firestore: $sessionId');
    } catch (e) {
      debugPrint('⚠️ Failed to save ChargeSample: $e');
    }

    // Sync to backend ngay nếu có mạng
    if (await _hasConnection()) {
      await _syncToBackend(sample);
    }
  }

  /// Sync ChargeSample to backend training endpoint
  Future<void> _syncToBackend(ChargeSampleModel sample) async {
    try {
      final response = await http.post(
        Uri.parse('${_apiService.baseUrl}/api/ai/charge-sample'),
        headers: await _apiService.getHeaders(),
        body: jsonEncode(sample.toFirestore()),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        // Update synced flag
        await _firestore
            .collection('ChargeSamples')
            .doc(sample.sessionId)
            .update({'syncedToBackend': true, 'syncedAt': FieldValue.serverTimestamp()});
        debugPrint('☁️ ChargeSample synced to backend: ${sample.sessionId}');
      } else {
        debugPrint('⚠️ Failed to sync ChargeSample: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ Error syncing ChargeSample: $e');
    }
  }

  /// Sync all unsynced samples (call periodically or on connectivity change)
  Future<void> syncAllPending() async {
    if (!await _hasConnection()) return;

    try {
      final pending = await _firestore
          .collection('ChargeSamples')
          .where('syncedToBackend', isEqualTo: false)
          .where('isDeleted', isEqualTo: false)
          .limit(50)
          .get();

      for (final doc in pending.docs) {
        final sample = ChargeSampleModel.fromFirestore(doc);
        await _syncToBackend(sample);
      }

      debugPrint('☁️ Synced ${pending.docs.length} pending ChargeSamples');
    } catch (e) {
      debugPrint('⚠️ Error syncing pending samples: $e');
    }
  }

  /// Get training-eligible samples for the current user
  Stream<List<ChargeSampleModel>> getUserTrainingSamples(String ownerUid) {
    return _firestore
        .collection('ChargeSamples')
        .where('ownerUid', isEqualTo: ownerUid)
        .where('eligibleForTraining', isEqualTo: true)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((d) => ChargeSampleModel.fromFirestore(d)).toList());
  }

  /// Delete a sample (soft delete)
  Future<void> deleteSample(String sessionId) async {
    await _firestore.collection('ChargeSamples').doc(sessionId).update({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }
}
