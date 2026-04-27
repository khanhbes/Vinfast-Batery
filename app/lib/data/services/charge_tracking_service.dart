import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/charge_log_model.dart';
import '../models/charge_sample_model.dart';
import '../services/notification_service.dart';

/// ========================================================================
/// Charge Tracking Service
/// Timer chạy ngầm mô phỏng quá trình sạc pin
/// ========================================================================
class ChargeTrackingService {
  static final ChargeTrackingService _instance = ChargeTrackingService._();
  factory ChargeTrackingService() => _instance;
  ChargeTrackingService._();

  // State
  bool _isCharging = false;
  bool get isCharging => _isCharging;

  String _vehicleId = '';
  String? _ownerUid;
  String? _chargeSessionId;
  int _startBattery = 0;
  int _currentBattery = 0;
  int _currentOdo = 0;
  int _targetBattery = 100;
  DateTime? _startTime;
  DateTime? _estimatedCompleteAt;

  /// Tốc độ sạc mặc định: 0.38% / phút
  /// (~4.4 giờ từ 0 → 100%)
  double _chargeRatePerMin = 0.38;

  Timer? _chargeTimer;
  bool _notified80 = false;
  bool _notified100 = false;
  bool _notifiedTarget = false;
  DateTime? _lastSampleSyncAt;

  // Getters cho UI
  int get currentBattery => _currentBattery;
  int get batteryGained => _currentBattery - _startBattery;
  int get targetBattery => _targetBattery;
  DateTime? get estimatedCompleteAt => _estimatedCompleteAt;
  Duration get elapsed => _startTime != null
      ? DateTime.now().difference(_startTime!)
      : Duration.zero;
  String get elapsedText {
    final d = elapsed;
    return '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }
  double get chargeRate => _chargeRatePerMin;

  // Callbacks
  VoidCallback? onUpdate;

  /// Kiểm tra và khôi phục session sạc sau khi app restart
  Future<bool> checkAndRecover() async {
    final prefs = await SharedPreferences.getInstance();
    final wasCharging = prefs.getBool('charge_active') ?? false;
    if (!wasCharging || _isCharging) return false;

    final vehicleId = prefs.getString('charge_vehicleId');
    final startBattery = prefs.getInt('charge_startBattery');
    final startTimeStr = prefs.getString('charge_startTime');
    final currentOdo = prefs.getInt('charge_currentOdo') ?? 0;
    final chargeRate = prefs.getDouble('charge_rate') ?? 0.38;
    final targetBattery = prefs.getInt('charge_targetBattery') ?? 100;
    final ownerUid = prefs.getString('charge_ownerUid');
    final sessionId = prefs.getString('charge_sessionId');

    if (vehicleId == null || startBattery == null || startTimeStr == null) {
      await _clearPersistedState();
      return false;
    }

    _vehicleId = vehicleId;
    _startBattery = startBattery;
    _currentOdo = currentOdo;
    _ownerUid = ownerUid ?? FirebaseAuth.instance.currentUser?.uid;
    _chargeSessionId = sessionId;
    _chargeRatePerMin = chargeRate;
    _targetBattery = targetBattery;
    _startTime = DateTime.tryParse(startTimeStr);
    if (_startTime == null) {
      await _clearPersistedState();
      return false;
    }

    // Tính battery hiện tại dựa trên thời gian đã trôi qua
    final elapsedMin = DateTime.now().difference(_startTime!).inSeconds / 60.0;
    final gained = (elapsedMin * _chargeRatePerMin).floor();
    _currentBattery = (_startBattery + gained).clamp(0, 100);
    _notified80 = _currentBattery >= 80;
    _notified100 = _currentBattery >= 100;
    _notifiedTarget = _currentBattery >= _targetBattery;
    _updateEta();

    // Recover AI prediction data if available
    final aiPredictionJson = prefs.getString('charge_aiPrediction');
    if (aiPredictionJson != null) {
      try {
        _aiPrediction = AiPredictionData.fromJson(jsonDecode(aiPredictionJson));
        debugPrint('🔮 AI prediction recovered: ${_aiPrediction!.formattedDuration}');
      } catch (e) {
        debugPrint('⚠️ Failed to recover AI prediction: $e');
      }
    }

    // Reschedule reminder if still charging and predicted stop time hasn't passed
    if (_aiPrediction != null && _aiPrediction!.predictedStopAt != null) {
      final predictedStop = _aiPrediction!.predictedStopAt!;
      if (predictedStop.isAfter(DateTime.now()) && !_notifiedTarget) {
        await _scheduleReminder(predictedStop);
        debugPrint('🔔 Reminder rescheduled after recovery');
      }
    }

    return true; // Có session cần recovery
  }

  /// Resume session sạc đã recover
  void resumeCharging() {
    if (_startTime == null) return;
    _isCharging = true;

    _chargeTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _onChargeTick(),
    );

    debugPrint('🔌 Charging resumed: $_currentBattery% (recovered)');
    _updateNotification();
    onUpdate?.call();
  }

  /// Hủy session sạc cũ mà không lưu
  Future<void> discardRecovery() async {
    await _clearPersistedState();
    _resetState();
    debugPrint('🗑 Charge recovery discarded');
  }

  Future<void> _clearPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('charge_active');
    await prefs.remove('charge_vehicleId');
    await prefs.remove('charge_startBattery');
    await prefs.remove('charge_startTime');
    await prefs.remove('charge_currentOdo');
    await prefs.remove('charge_rate');
    await prefs.remove('charge_targetBattery');
    await prefs.remove('charge_ownerUid');
    await prefs.remove('charge_sessionId');
    await prefs.remove('charge_aiPrediction'); // Clear AI prediction data
  }

  void _resetState() {
    _isCharging = false;
    _vehicleId = '';
    _ownerUid = null;
    _chargeSessionId = null;
    _startBattery = 0;
    _currentBattery = 0;
    _currentOdo = 0;
    _targetBattery = 100;
    _startTime = null;
    _estimatedCompleteAt = null;
    _chargeTimer?.cancel();
    _chargeTimer = null;
    _notified80 = false;
    _notified100 = false;
    _notifiedTarget = false;
    _lastSampleSyncAt = null;
  }

  /// Bắt đầu sạc với AI prediction metadata
  Future<void> startCharging({
    required String vehicleId,
    required int currentBattery,
    required int currentOdo,
    double? chargeRatePerMin,
    int targetBatteryPercent = 80,
    // AI prediction data from backend
    double? predictedDurationSec,
    DateTime? predictedStopAt,
    String? modelSource,
    String? modelVersion,
    bool? reminderEnabled,
  }) async {
    _vehicleId = vehicleId;
    _startBattery = currentBattery;
    _currentBattery = currentBattery;
    _currentOdo = currentOdo;
    _ownerUid = FirebaseAuth.instance.currentUser?.uid;
    _chargeSessionId ??= FirebaseFirestore.instance.collection('ChargeLogs').doc().id;
    _startTime = DateTime.now();
    _isCharging = true;
    _targetBattery = targetBatteryPercent.clamp(currentBattery + 1, 100);
    _notified80 = currentBattery >= 80;
    _notified100 = currentBattery >= 100;
    _notifiedTarget = false;

    // Store AI prediction data
    if (predictedDurationSec != null && predictedDurationSec > 0) {
      _aiPrediction = AiPredictionData(
        requestedAt: _startTime,
        startBatteryPercent: currentBattery,
        targetBatteryPercent: _targetBattery,
        predictedDurationSec: predictedDurationSec,
        predictedStopAt: predictedStopAt ?? _startTime!.add(Duration(seconds: predictedDurationSec.toInt())),
        modelSource: modelSource ?? 'heuristic_fallback',
        modelVersion: modelVersion ?? 'heuristic-v1',
        isBeta: true,
      );

      // Calculate charge rate from predicted duration
      final gain = _targetBattery - _startBattery;
      if (gain > 0) {
        _chargeRatePerMin = gain / (predictedDurationSec / 60);
      }

      // Schedule reminder if enabled
      if (reminderEnabled == true && predictedStopAt != null) {
        await _scheduleReminder(predictedStopAt);
      }

      debugPrint('🔌 AI Charging started: ${currentBattery}% → ${_targetBattery}%, '
          'predicted ${_aiPrediction!.formattedDuration}, source: ${modelSource}');
    } else {
      // Fallback to provided rate or default
      if (chargeRatePerMin != null && chargeRatePerMin > 0) {
        _chargeRatePerMin = chargeRatePerMin;
      }
      debugPrint('🔌 Charging started: $_currentBattery% → target 100% (heuristic)');
    }

    _updateEta();

    // Persist trạng thái
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('charge_active', true);
    await prefs.setString('charge_vehicleId', vehicleId);
    await prefs.setInt('charge_startBattery', _startBattery);
    await prefs.setString('charge_startTime', _startTime!.toIso8601String());
    await prefs.setInt('charge_currentOdo', _currentOdo);
    await prefs.setDouble('charge_rate', _chargeRatePerMin);
    await prefs.setInt('charge_targetBattery', _targetBattery);
    if (_ownerUid != null) {
      await prefs.setString('charge_ownerUid', _ownerUid!);
    }
    if (_chargeSessionId != null) {
      await prefs.setString('charge_sessionId', _chargeSessionId!);
    }
    // Persist AI prediction data for recovery after app restart
    if (_aiPrediction != null) {
      await prefs.setString('charge_aiPrediction', jsonEncode(_aiPrediction!.toJson()));
    }

    // Timer cập nhật mỗi 30 giây
    _chargeTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _onChargeTick(),
    );
    _syncChargeSample(event: 'start', force: true);
    _updateNotification();
    onUpdate?.call();
  }

  /// Mỗi tick: cộng % pin + kiểm tra mốc target / 80% / 100%
  void _onChargeTick() {
    if (!_isCharging) return;

    final elapsedMin = elapsed.inSeconds / 60.0;
    final gained = (elapsedMin * _chargeRatePerMin).floor();
    _currentBattery = (_startBattery + gained).clamp(0, 100);

    _updateEta();

    // Thông báo đạt target
    if (_currentBattery >= _targetBattery && !_notifiedTarget) {
      _notifiedTarget = true;
      NotificationService().notifyChargeTarget(_currentBattery, _targetBattery);
      debugPrint('📢 Battery hit target $_targetBattery%!');
    }

    // Thông báo mốc 80%
    if (_currentBattery >= 80 && !_notified80) {
      _notified80 = true;
      if (_targetBattery != 80) {
        NotificationService().notifyCharge80(_currentBattery);
      }
      debugPrint('📢 Battery hit 80%!');
    }

    // Thông báo mốc 100%
    if (_currentBattery >= 100 && !_notified100) {
      _notified100 = true;
      NotificationService().notifyCharge100();
      debugPrint('📢 Battery hit 100%!');
    }

    _updateNotification();
    _syncChargeSample(event: 'tick');
    onUpdate?.call();
  }

  Future<void> _syncChargeSample({required String event, bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastSampleSyncAt != null && now.difference(_lastSampleSyncAt!) < const Duration(seconds: 25)) {
      return;
    }
    _lastSampleSyncAt = now;
    try {
      await FirebaseFirestore.instance.collection('ChargeSamples').add({
        'sessionId': _chargeSessionId,
        'event': event,
        'vehicleId': _vehicleId,
        if (_ownerUid != null) 'ownerUid': _ownerUid,
        'timestamp': now.toUtc().toIso8601String(),
        'batteryPercent': _currentBattery,
        'targetBatteryPercent': _targetBattery,
        'elapsedSec': elapsed.inSeconds,
        'chargeRatePerMin': _chargeRatePerMin,
        'estimatedCompleteAt': _estimatedCompleteAt?.toUtc().toIso8601String(),
        'odoAtCharge': _currentOdo,
        'isDeleted': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠ Charge sample sync failed: $e');
    }
  }

  /// Cập nhật ETA dự kiến sạc đến target
  void _updateEta() {
    if (_chargeRatePerMin <= 0 || _currentBattery >= _targetBattery) {
      _estimatedCompleteAt = null;
      return;
    }
    final remainPercent = _targetBattery - _currentBattery;
    final minutesLeft = remainPercent / _chargeRatePerMin;
    _estimatedCompleteAt = DateTime.now().add(
      Duration(minutes: minutesLeft.ceil()),
    );
  }

  /// ETA text dạng "~XXh YYm"
  String get etaText {
    if (_estimatedCompleteAt == null || _currentBattery >= _targetBattery) {
      return 'Đã đạt mục tiêu';
    }
    final diff = _estimatedCompleteAt!.difference(DateTime.now());
    if (diff.isNegative) return 'Sắp xong';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return '~${h}h ${m}m';
    return '~${m}m';
  }

  /// Cập nhật foreground notification
  Future<void> _updateNotification() async {
    if (!_isCharging) return;
    await NotificationService().showChargingOngoing(_currentBattery, elapsedText);
  }

  /// AI prediction data for the current session
  AiPredictionData? _aiPrediction;

  /// Schedule reminder notification using NotificationService
  Future<void> _scheduleReminder(DateTime reminderTime) async {
    if (_targetBattery != null) {
      await NotificationService().scheduleChargeReminder(reminderTime, _targetBattery!);
      debugPrint('🔔 Reminder scheduled for: $reminderTime (target: $_targetBattery%)');
    }
  }

  /// Cancel scheduled reminder
  Future<void> _cancelReminder() async {
    await NotificationService().cancelChargeReminder();
    debugPrint('🔔 Reminder cancelled');
  }

  /// Kết thúc sạc và lưu log vào Firestore
  /// [actualBatteryPercent] - % pin thực tế khi dừng (required by user confirmation)
  Future<ChargeLogModel?> stopCharging({int? actualBatteryPercent}) async {
    if (!_isCharging) return null;
    _isCharging = false;

    _chargeTimer?.cancel();
    _chargeTimer = null;

    // Hủy notification và reminder
    await NotificationService().cancel(NotificationService.idChargeOngoing);
    await _cancelReminder();

    // Update actual battery if provided (override simulated value)
    if (actualBatteryPercent != null && actualBatteryPercent != _currentBattery) {
      debugPrint('🔋 Actual battery override: $_currentBattery -> $actualBatteryPercent');
      _currentBattery = actualBatteryPercent;
    }

    final endTime = DateTime.now();
    final durationMin = endTime.difference(_startTime!).inMinutes;
    final durationSec = endTime.difference(_startTime!).inSeconds.toDouble();

    // Update AI prediction with actual results
    AiPredictionData? finalAiPrediction;
    if (_aiPrediction != null) {
      finalAiPrediction = _aiPrediction!.copyWithActual(_currentBattery, endTime);
    }

    final chargeLog = ChargeLogModel(
      logId: _chargeSessionId,
      vehicleId: _vehicleId,
      ownerUid: _ownerUid,
      startTime: _startTime!,
      endTime: endTime,
      startBatteryPercent: _startBattery,
      endBatteryPercent: _currentBattery,
      odoAtCharge: _currentOdo,
      targetBatteryPercent: _targetBattery,
      estimatedCompleteAt: _estimatedCompleteAt,
      aiPrediction: finalAiPrediction,
    );

    // Lưu vào Firestore
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore.runTransaction((transaction) async {
        final logRef = firestore.collection('ChargeLogs').doc(_chargeSessionId ?? firestore.collection('ChargeLogs').doc().id);
        transaction.set(logRef, {
          ...chargeLog.toFirestore(),
          'sessionId': _chargeSessionId,
          'durationMin': durationMin,
          'chargeGainPercent': batteryGained,
          'avgChargeRatePercentPerHour': durationMin > 0 ? (batteryGained * 60 / durationMin) : 0,
          'aiFeatures': {
            'startBatteryPercent': _startBattery,
            'endBatteryPercent': _currentBattery,
            'targetBatteryPercent': _targetBattery,
            'chargeRatePerMin': _chargeRatePerMin,
            'durationMin': durationMin,
            'durationSec': durationSec,
          },
          'createdAt': FieldValue.serverTimestamp(),
          'isDeleted': false,
          'source': 'app_live_charge',
        });

        final vehicleRef = firestore.collection('Vehicles').doc(_vehicleId);
        transaction.update(vehicleRef, {
          'currentBattery': _currentBattery,
          'lastBatteryPercent': _currentBattery,
          'totalCharges': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      debugPrint('✅ Charge saved: +$batteryGained% in ${durationMin}min');
    } catch (e) {
      debugPrint('❌ Error saving charge: $e');
    }

    _syncChargeSample(event: 'stop', force: true);

    onUpdate?.call();
    return chargeLog;
  }
}
