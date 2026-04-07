import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip_log_model.dart';
import '../services/battery_logic_service.dart';
import '../services/notification_service.dart';

/// ========================================================================
/// Trip Tracking Service
/// Chạy ngầm dùng Foreground Notification + GPS Geolocator
/// ========================================================================
class TripTrackingService {
  static final TripTrackingService _instance = TripTrackingService._();
  factory TripTrackingService() => _instance;
  TripTrackingService._();

  // State
  bool _isTracking = false;
  bool get isTracking => _isTracking;

  PayloadType _payload = PayloadType.onePerson;
  PayloadType get payload => _payload;

  String _vehicleId = '';
  double _defaultEfficiency = 1.2;
  int _startBattery = 100;
  int _currentBattery = 100;
  int _startOdo = 0;
  double _totalDistance = 0;
  DateTime? _startTime;

  double? _lastLat;
  double? _lastLon;

  StreamSubscription<Position>? _positionStream;
  Timer? _notificationTimer;

  // Getters cho UI
  double get totalDistance => _totalDistance;
  int get currentBattery => _currentBattery;
  int get batteryConsumed => _startBattery - _currentBattery;
  Duration get elapsed => _startTime != null
      ? DateTime.now().difference(_startTime!)
      : Duration.zero;
  String get elapsedText {
    final d = elapsed;
    return '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  // Callbacks cho UI update
  VoidCallback? onUpdate;

  /// Kiểm tra và khôi phục session trip sau khi app restart
  Future<bool> checkAndRecover() async {
    final prefs = await SharedPreferences.getInstance();
    final wasTracking = prefs.getBool('trip_active') ?? false;
    if (!wasTracking || _isTracking) return false;

    final vehicleId = prefs.getString('trip_vehicleId');
    final startBattery = prefs.getInt('trip_startBattery');
    final startOdo = prefs.getInt('trip_startOdo');
    final startTimeStr = prefs.getString('trip_startTime');
    final payloadStr = prefs.getString('trip_payload') ?? '1_person';
    final efficiency = prefs.getDouble('trip_efficiency') ?? 1.2;

    if (vehicleId == null || startBattery == null || startOdo == null || startTimeStr == null) {
      await _clearPersistedState();
      return false;
    }

    _vehicleId = vehicleId;
    _startBattery = startBattery;
    _currentBattery = startBattery; // Sẽ được tính lại khi GPS resume
    _startOdo = startOdo;
    _defaultEfficiency = efficiency;
    _payload = PayloadType.fromString(payloadStr);
    _startTime = DateTime.tryParse(startTimeStr);
    _totalDistance = 0; // Reset, sẽ tính lại từ GPS

    if (_startTime == null) {
      await _clearPersistedState();
      return false;
    }

    return true; // Có session cần recovery
  }

  /// Resume session trip đã recover — bắt đầu lại GPS tracking
  Future<bool> resumeTrip() async {
    if (_startTime == null) return false;

    final permission = await _checkPermission();
    if (!permission) return false;

    _isTracking = true;
    _lastLat = null;
    _lastLon = null;

    // Bắt đầu lắng nghe GPS lại
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(_onPositionUpdate);

    _notificationTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _updateNotification(),
    );

    debugPrint('🛵 Trip resumed (recovered)');
    return true;
  }

  /// Hủy session trip cũ mà không lưu
  Future<void> discardRecovery() async {
    await _clearPersistedState();
    _resetState();
    debugPrint('🗑 Trip recovery discarded');
  }

  Future<void> _clearPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('trip_active', false);
    await prefs.remove('trip_vehicleId');
    await prefs.remove('trip_startBattery');
    await prefs.remove('trip_startOdo');
    await prefs.remove('trip_startTime');
    await prefs.remove('trip_payload');
    await prefs.remove('trip_efficiency');
  }

  void _resetState() {
    _isTracking = false;
    _vehicleId = '';
    _startBattery = 100;
    _currentBattery = 100;
    _startOdo = 0;
    _totalDistance = 0;
    _startTime = null;
    _lastLat = null;
    _lastLon = null;
    _positionStream?.cancel();
    _positionStream = null;
    _notificationTimer?.cancel();
    _notificationTimer = null;
  }

  /// Bắt đầu tracking hành trình
  Future<bool> startTrip({
    required String vehicleId,
    required PayloadType payload,
    required int currentBattery,
    required int currentOdo,
    required double defaultEfficiency,
  }) async {
    // Kiểm tra quyền GPS
    final permission = await _checkPermission();
    if (!permission) return false;

    _vehicleId = vehicleId;
    _payload = payload;
    _startBattery = currentBattery;
    _currentBattery = currentBattery;
    _startOdo = currentOdo;
    _defaultEfficiency = defaultEfficiency;
    _totalDistance = 0;
    _startTime = DateTime.now();
    _lastLat = null;
    _lastLon = null;
    _isTracking = true;

    // Lưu trạng thái vào SharedPreferences (persist qua restart)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('trip_active', true);
    await prefs.setString('trip_vehicleId', vehicleId);
    await prefs.setInt('trip_startBattery', currentBattery);
    await prefs.setInt('trip_startOdo', currentOdo);
    await prefs.setString('trip_startTime', _startTime!.toIso8601String());
    await prefs.setString('trip_payload', payload.value);
    await prefs.setDouble('trip_efficiency', defaultEfficiency);

    // Bắt đầu lắng nghe GPS
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Cập nhật mỗi 10m di chuyển
      ),
    ).listen(_onPositionUpdate);

    // Timer cập nhật notification
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _updateNotification(),
    );

    debugPrint('🛵 Trip tracking started: $vehicleId, payload: ${payload.label}');
    return true;
  }

  /// Xử lý mỗi khi GPS cập nhật vị trí mới
  void _onPositionUpdate(Position position) {
    if (!_isTracking) return;

    if (_lastLat != null && _lastLon != null) {
      // Tính khoảng cách bằng Haversine
      final dist = BatteryLogicService.haversineDistance(
        _lastLat!, _lastLon!,
        position.latitude, position.longitude,
      );

      // Lọc nhiễu GPS: bỏ qua nếu < 5m hoặc > 1km (nhảy GPS)
      if (dist >= 0.005 && dist <= 1.0) {
        _totalDistance += dist;

        // Tính % pin tiêu hao
        final drain = BatteryLogicService.batteryDrainForDistance(
          dist, _defaultEfficiency, _payload,
        );
        _currentBattery = (_currentBattery - drain).clamp(0, 100);
      }
    }

    _lastLat = position.latitude;
    _lastLon = position.longitude;

    onUpdate?.call();
  }

  /// Cập nhật notification ongoing
  Future<void> _updateNotification() async {
    if (!_isTracking) return;
    await NotificationService().showTripOngoing(_totalDistance, _currentBattery);
  }

  /// Kết thúc hành trình và lưu vào Firestore
  Future<TripLogModel?> stopTrip() async {
    if (!_isTracking) return null;
    _isTracking = false;

    // Dừng GPS
    await _positionStream?.cancel();
    _positionStream = null;

    // Dừng notification timer
    _notificationTimer?.cancel();
    _notificationTimer = null;

    // Xóa notification
    await NotificationService().cancel(NotificationService.idTripOngoing);

    // Xóa trạng thái persisted
    await _clearPersistedState();

    final endTime = DateTime.now();
    final consumed = _startBattery - _currentBattery;
    final efficiency = consumed > 0 ? _totalDistance / consumed : 0.0;
    final endOdo = _startOdo + _totalDistance.round();

    final trip = TripLogModel(
      vehicleId: _vehicleId,
      startTime: _startTime!,
      endTime: endTime,
      distance: double.parse(_totalDistance.toStringAsFixed(2)),
      payloadType: _payload,
      startBattery: _startBattery,
      endBattery: _currentBattery,
      batteryConsumed: consumed,
      efficiency: double.parse(efficiency.toStringAsFixed(3)),
      startOdo: _startOdo,
      endOdo: endOdo,
      entryMode: TripEntryMode.live,
      distanceSource: DistanceSource.gps,
    );

    // Lưu vào Firestore
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore.runTransaction((transaction) async {
        final tripRef = firestore.collection('TripLogs').doc();
        transaction.set(tripRef, trip.toFirestore());

        final vehicleRef = firestore.collection('Vehicles').doc(_vehicleId);
        transaction.update(vehicleRef, {
          'currentOdo': endOdo,
          'currentBattery': _currentBattery,
          'lastBatteryPercent': _currentBattery,
          'totalTrips': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      debugPrint('✅ Trip saved: ${_totalDistance.toStringAsFixed(1)}km, -${consumed}% pin');
    } catch (e) {
      debugPrint('❌ Error saving trip: $e');
    }

    onUpdate?.call();
    return trip;
  }

  /// Kiểm tra quyền GPS
  Future<bool> _checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('❌ GPS service disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('❌ GPS permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('❌ GPS permission permanently denied');
      return false;
    }

    return true;
  }
}
