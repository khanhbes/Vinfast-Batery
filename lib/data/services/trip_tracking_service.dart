import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../models/trip_log_model.dart';
import '../services/battery_logic_service.dart';
import '../services/notification_service.dart';

// =============================================================================
// Trip Start Result — mã trạng thái chi tiết khi bắt đầu chuyến đi
// =============================================================================

enum TripStartStatus {
  success,
  gpsDisabled,
  permissionDenied,
  permissionDeniedForever,
  streamError,
  serviceError,
  unknownError,
}

class TripStartResult {
  final TripStartStatus status;
  final String message;

  const TripStartResult({required this.status, required this.message});

  bool get isSuccess => status == TripStartStatus.success;

  static const TripStartResult ok = TripStartResult(
    status: TripStartStatus.success,
    message: 'Bắt đầu chuyến đi thành công!',
  );
}

// =============================================================================
// Trip Live Snapshot — dữ liệu realtime cho UI map
// =============================================================================

class TripLiveSnapshot {
  final double? latitude;
  final double? longitude;
  final List<ll.LatLng> routePoints;
  final double totalDistance;
  final int currentBattery;
  final int batteryConsumed;
  final Duration elapsed;
  final bool isTracking;

  const TripLiveSnapshot({
    this.latitude,
    this.longitude,
    this.routePoints = const [],
    this.totalDistance = 0,
    this.currentBattery = 100,
    this.batteryConsumed = 0,
    this.elapsed = Duration.zero,
    this.isTracking = false,
  });
}

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

  /// Guard chống gọi startTrip trùng lặp
  bool _isStarting = false;
  bool get isStarting => _isStarting;

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

  /// Route points in-session (chỉ giữ trong RAM, không lưu Firestore)
  final List<ll.LatLng> _routePoints = [];

  StreamSubscription<Position>? _positionStream;
  Timer? _notificationTimer;

  /// Stream controller cho live snapshot — UI map subscribe vào đây
  final _snapshotController = StreamController<TripLiveSnapshot>.broadcast();
  Stream<TripLiveSnapshot> get snapshotStream => _snapshotController.stream;

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

  List<ll.LatLng> get routePoints => List.unmodifiable(_routePoints);
  double? get currentLat => _lastLat;
  double? get currentLon => _lastLon;

  /// Lấy snapshot hiện tại (polling)
  TripLiveSnapshot get currentSnapshot => TripLiveSnapshot(
    latitude: _lastLat,
    longitude: _lastLon,
    routePoints: List.unmodifiable(_routePoints),
    totalDistance: _totalDistance,
    currentBattery: _currentBattery,
    batteryConsumed: _startBattery - _currentBattery,
    elapsed: elapsed,
    isTracking: _isTracking,
  );

  // Callbacks cho UI update
  VoidCallback? onUpdate;

  /// Phát snapshot mới lên stream
  void _emitSnapshot() {
    if (!_snapshotController.isClosed) {
      _snapshotController.add(currentSnapshot);
    }
    onUpdate?.call();
  }

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

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return false;
      }
      if (permission == LocationPermission.deniedForever) return false;
    } catch (e) {
      debugPrint('❌ Resume permission check failed: $e');
      return false;
    }

    _isTracking = true;
    _lastLat = null;
    _lastLon = null;
    _routePoints.clear();

    // Bắt đầu lắng nghe GPS lại
    try {
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(
        _onPositionUpdate,
        onError: (error) {
          debugPrint('❌ GPS stream error on resume: $error');
        },
      );
    } catch (e) {
      debugPrint('❌ Resume GPS stream failed: $e');
      _isTracking = false;
      return false;
    }

    try {
      _notificationTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _updateNotification(),
      );
    } catch (e) {
      debugPrint('⚠ Resume notification timer error (non-fatal): $e');
    }

    debugPrint('🛵 Trip resumed (recovered)');
    _emitSnapshot();
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
    _isStarting = false;
    _vehicleId = '';
    _startBattery = 100;
    _currentBattery = 100;
    _startOdo = 0;
    _totalDistance = 0;
    _startTime = null;
    _lastLat = null;
    _lastLon = null;
    _routePoints.clear();
    _positionStream?.cancel();
    _positionStream = null;
    _notificationTimer?.cancel();
    _notificationTimer = null;
  }

  /// Bắt đầu tracking hành trình — trả về TripStartResult chi tiết
  Future<TripStartResult> startTrip({
    required String vehicleId,
    required PayloadType payload,
    required int currentBattery,
    required int currentOdo,
    required double defaultEfficiency,
  }) async {
    // Guard: đang start rồi thì không cho gọi lại
    if (_isStarting) {
      return const TripStartResult(
        status: TripStartStatus.serviceError,
        message: 'Đang khởi tạo chuyến đi, vui lòng chờ...',
      );
    }
    // Guard: đã tracking thì trả success luôn
    if (_isTracking) {
      return TripStartResult.ok;
    }

    _isStarting = true;
    try {
      return await _doStartTrip(
        vehicleId: vehicleId,
        payload: payload,
        currentBattery: currentBattery,
        currentOdo: currentOdo,
        defaultEfficiency: defaultEfficiency,
      );
    } finally {
      _isStarting = false;
    }
  }

  Future<TripStartResult> _doStartTrip({
    required String vehicleId,
    required PayloadType payload,
    required int currentBattery,
    required int currentOdo,
    required double defaultEfficiency,
  }) async {
    // 1. Kiểm tra GPS service
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const TripStartResult(
          status: TripStartStatus.gpsDisabled,
          message: 'GPS đang tắt. Vui lòng bật định vị trong cài đặt.',
        );
      }
    } catch (e) {
      return TripStartResult(
        status: TripStartStatus.unknownError,
        message: 'Không thể kiểm tra GPS: $e',
      );
    }

    // 2. Kiểm tra / yêu cầu quyền
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return const TripStartResult(
            status: TripStartStatus.permissionDenied,
            message: 'Quyền truy cập vị trí bị từ chối.',
          );
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return const TripStartResult(
          status: TripStartStatus.permissionDeniedForever,
          message: 'Quyền vị trí bị từ chối vĩnh viễn. Vui lòng cấp quyền trong Cài đặt.',
        );
      }
    } catch (e) {
      return TripStartResult(
        status: TripStartStatus.unknownError,
        message: 'Lỗi kiểm tra quyền vị trí: $e',
      );
    }

    // 3. Set state trước khi bắt đầu stream
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
    _routePoints.clear();
    _isTracking = true;

    // 4. Persist state (SharedPreferences)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('trip_active', true);
      await prefs.setString('trip_vehicleId', vehicleId);
      await prefs.setInt('trip_startBattery', currentBattery);
      await prefs.setInt('trip_startOdo', currentOdo);
      await prefs.setString('trip_startTime', _startTime!.toIso8601String());
      await prefs.setString('trip_payload', payload.value);
      await prefs.setDouble('trip_efficiency', defaultEfficiency);
    } catch (e) {
      // SharedPreferences fail → rollback
      _resetState();
      return TripStartResult(
        status: TripStartStatus.serviceError,
        message: 'Lỗi lưu trạng thái: $e',
      );
    }

    // 5. Bắt đầu GPS stream
    try {
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(
        _onPositionUpdate,
        onError: (error) {
          debugPrint('❌ GPS stream error: $error');
          // Không crash — stream lỗi thì tiếp tục tracking nhưng không có GPS mới
        },
      );
    } catch (e) {
      // Stream fail → rollback
      await _clearPersistedState();
      _resetState();
      return TripStartResult(
        status: TripStartStatus.streamError,
        message: 'Không thể bắt đầu theo dõi GPS: $e',
      );
    }

    // 6. Notification timer
    try {
      _notificationTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _updateNotification(),
      );
    } catch (e) {
      debugPrint('⚠ Notification timer error (non-fatal): $e');
      // Non-fatal — tracking vẫn chạy
    }

    debugPrint('🛵 Trip tracking started: $vehicleId, payload: ${payload.label}');
    _emitSnapshot();
    return TripStartResult.ok;
  }

  /// Inject vị trí từ bên ngoài (Reload GPS)
  void injectPosition(Position position) {
    _onPositionUpdate(position);
  }

  /// Xử lý mỗi khi GPS cập nhật vị trí mới
  void _onPositionUpdate(Position pos) {
    if (!_isTracking) return;

    if (_lastLat != null && _lastLon != null) {
      // Tính khoảng cách bằng Haversine
      final dist = BatteryLogicService.haversineDistance(
        _lastLat!, _lastLon!,
        pos.latitude, pos.longitude,
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

    _lastLat = pos.latitude;
    _lastLon = pos.longitude;

    // Thêm vào route points cho map
    _routePoints.add(ll.LatLng(pos.latitude, pos.longitude));

    _emitSnapshot();
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
      debugPrint('✅ Trip saved: ${_totalDistance.toStringAsFixed(1)}km, -$consumed% pin');
    } catch (e) {
      debugPrint('❌ Error saving trip: $e');
    }

    _routePoints.clear();
    _emitSnapshot();
    return trip;
  }

}
