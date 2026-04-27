import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// SyncService - Đồng bộ dữ liệu giữa App và Web Dashboard
/// Xử lý: User sync, Vehicle sync, Battery state sync, Trip prediction sync
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  // API Configuration
  static String get _baseUrl => AppConstants.apiBaseUrl;
  static const Duration _timeout = Duration(seconds: 30);

  // Firestore instances
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Đồng bộ user mới với web dashboard
  Future<bool> syncUserToWeb() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('No user logged in');
        return false;
      }

      // Lấy thông tin user từ Firestore
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};

      // Gửi đến web API
      final response = await http.post(
        Uri.parse('$_baseUrl/api/web/sync/user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName ?? userData['name'] ?? 'User',
          'phoneNumber': user.phoneNumber ?? userData['phone'] ?? '',
          'photoURL': user.photoURL ?? '',
          'createdAt': DateTime.now().toIso8601String(),
          'source': 'flutter_app',
        }),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        print('User synced to web successfully: ${user.uid}');
        
        // Lưu vào SharedPreferences đánh dấu đã sync
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('user_synced_to_web', true);
        await prefs.setString('last_user_sync', DateTime.now().toIso8601String());
        
        return true;
      } else {
        print('Failed to sync user: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error syncing user to web: $e');
      return false;
    }
  }

  /// Đồng bộ vehicle mới với web dashboard
  Future<bool> syncVehicleToWeb(String vehicleId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Lấy thông tin vehicle
      final vehicleDoc = await _firestore.collection('vehicles').doc(vehicleId).get();
      if (!vehicleDoc.exists) {
        print('Vehicle not found: $vehicleId');
        return false;
      }

      final vehicleData = vehicleDoc.data()!;

      // Gửi đến web API
      final response = await http.post(
        Uri.parse('$_baseUrl/api/web/sync/vehicle'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'vehicleId': vehicleId,
          'ownerUid': user.uid,
          'model': vehicleData['model'] ?? 'Unknown',
          'year': vehicleData['year'] ?? DateTime.now().year,
          'batteryCapacity': vehicleData['batteryCapacity'] ?? 0,
          'currentBattery': vehicleData['currentBattery'] ?? 0,
          'stateOfHealth': vehicleData['stateOfHealth'] ?? 100,
          'currentOdo': vehicleData['currentOdo'] ?? 0,
          'defaultEfficiency': vehicleData['defaultEfficiency'] ?? 1.0,
          'lastBatteryPercent': vehicleData['lastBatteryPercent'] ?? 0,
          'syncedAt': DateTime.now().toIso8601String(),
          'source': 'flutter_app',
        }),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        print('Vehicle synced to web: $vehicleId');
        
        // Cập nhật flag trong Firestore
        await _firestore.collection('vehicles').doc(vehicleId).update({
          'syncedToWeb': true,
          'lastWebSync': FieldValue.serverTimestamp(),
        });
        
        return true;
      } else {
        print('Failed to sync vehicle: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Error syncing vehicle to web: $e');
      return false;
    }
  }

  /// Đồng bộ tất cả vehicles của user
  Future<Map<String, int>> syncAllVehiclesToWeb() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return {'total': 0, 'synced': 0, 'failed': 0};

      // Lấy tất cả vehicles
      final snapshot = await _firestore
          .collection('vehicles')
          .where('ownerUid', isEqualTo: user.uid)
          .get();

      int synced = 0;
      int failed = 0;

      for (final doc in snapshot.docs) {
        final success = await syncVehicleToWeb(doc.id);
        if (success) {
          synced++;
        } else {
          failed++;
        }
      }

      return {
        'total': snapshot.docs.length,
        'synced': synced,
        'failed': failed,
      };
    } catch (e) {
      print('Error syncing all vehicles: $e');
      return {'total': 0, 'synced': 0, 'failed': 0};
    }
  }

  /// Đồng bộ battery state với web
  Future<bool> syncBatteryStateToWeb(String vehicleId) async {
    try {
      // Lấy battery state gần nhất
      final snapshot = await _firestore
          .collection('battery_states')
          .where('vehicleId', isEqualTo: vehicleId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        print('No battery state found for vehicle: $vehicleId');
        return false;
      }

      final batteryState = snapshot.docs.first.data();

      final response = await http.post(
        Uri.parse('$_baseUrl/api/web/sync/battery-state'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'vehicleId': vehicleId,
          'percentage': batteryState['percentage'] ?? 0,
          'soh': batteryState['soh'] ?? 100,
          'estimatedRange': batteryState['estimatedRange'] ?? 0,
          'temp': batteryState['temp'] ?? 25.0,
          'timestamp': (batteryState['timestamp'] as Timestamp).toDate().toIso8601String(),
          'source': 'flutter_app',
        }),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        print('Battery state synced to web: $vehicleId');
        return true;
      } else {
        print('Failed to sync battery state: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Error syncing battery state: $e');
      return false;
    }
  }

  /// Đồng bộ trip prediction với web
  Future<bool> syncTripPredictionToWeb(String predictionId) async {
    try {
      final doc = await _firestore.collection('trip_predictions').doc(predictionId).get();
      if (!doc.exists) return false;

      final data = doc.data()!;

      final response = await http.post(
        Uri.parse('$_baseUrl/api/web/sync/trip-prediction'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'predictionId': predictionId,
          'vehicleId': data['vehicleId'],
          'from': data['from'],
          'to': data['to'],
          'distance': data['distance'],
          'duration': data['duration'],
          'consumption': data['consumption'],
          'startBattery': data['startBattery'],
          'endBattery': data['endBattery'],
          'isSafe': data['isSafe'],
          'weather': data['weather'],
          'temperature': data['temperature'],
          'riderWeight': data['riderWeight'],
          'timestamp': (data['timestamp'] as Timestamp).toDate().toIso8601String(),
          'source': 'flutter_app',
        }),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        print('Trip prediction synced to web: $predictionId');
        return true;
      } else {
        print('Failed to sync trip prediction: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Error syncing trip prediction: $e');
      return false;
    }
  }

  /// Thực hiện đồng bộ toàn bộ dữ liệu
  Future<Map<String, dynamic>> performFullSync() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'No user logged in'};
      }

      final results = <String, dynamic>{};

      // 1. Sync user
      results['user'] = await syncUserToWeb();

      // 2. Sync all vehicles
      final vehicleResults = await syncAllVehiclesToWeb();
      results['vehicles'] = vehicleResults;

      // 3. Sync battery states cho mỗi vehicle
      final vehiclesSnapshot = await _firestore
          .collection('vehicles')
          .where('ownerUid', isEqualTo: user.uid)
          .get();

      int batterySynced = 0;
      for (final doc in vehiclesSnapshot.docs) {
        final success = await syncBatteryStateToWeb(doc.id);
        if (success) batterySynced++;
      }
      results['batteryStates'] = {'synced': batterySynced};

      // Lưu thời gian sync cuối
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_full_sync', DateTime.now().toIso8601String());

      print('Full sync completed: $results');
      return {'success': true, 'results': results};
    } catch (e) {
      print('Error performing full sync: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Kiểm tra trạng thái đồng bộ
  Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = _auth.currentUser;

      return {
        'userLoggedIn': user != null,
        'userSynced': prefs.getBool('user_synced_to_web') ?? false,
        'lastUserSync': prefs.getString('last_user_sync'),
        'lastFullSync': prefs.getString('last_full_sync'),
        'webApiAvailable': await _checkWebApiStatus(),
      };
    } catch (e) {
      print('Error getting sync status: $e');
      return {'error': e.toString()};
    }
  }

  /// Kiểm tra Web API status
  Future<bool> _checkWebApiStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Lắng nghe thay đổi và auto-sync (real-time)
  StreamSubscription? _vehicleSubscription;

  void startAutoSync() {
    final user = _auth.currentUser;
    if (user == null) return;

    // Lắng nghe thay đổi vehicles
    _vehicleSubscription = _firestore
        .collection('vehicles')
        .where('ownerUid', isEqualTo: user.uid)
        .where('needsSync', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added ||
            change.type == DocumentChangeType.modified) {
          syncVehicleToWeb(change.doc.id);
        }
      }
    });

    print('Auto sync started for user: ${user.uid}');
  }

  void stopAutoSync() {
    _vehicleSubscription?.cancel();
    _vehicleSubscription = null;
    print('Auto sync stopped');
  }
}
