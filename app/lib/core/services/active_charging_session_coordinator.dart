import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/smart_charging_session.dart';

enum CrossDeviceControlState {
  displayOnly,
  verifying,
  stopAllowed,
  stopping,
  offVerified,
  unknown,
}

class ActiveChargingSessionSnapshot {
  const ActiveChargingSessionSnapshot({
    required this.uid,
    required this.sessionId,
    required this.vehicleId,
    required this.state,
    required this.relay,
    required this.targetSoc,
    required this.updatedAt,
    required this.source,
    this.deviceId,
    this.model,
    this.timerRemainingSeconds,
    this.powerW,
    this.voltageV,
    this.currentA,
    this.energyWh,
    this.session,
    this.revision = 0,
    this.controlState = CrossDeviceControlState.displayOnly,
  });

  final String uid;
  final String sessionId;
  final String vehicleId;
  final String state;
  final bool? relay;
  final double? targetSoc;
  final DateTime updatedAt;
  final String source;
  final String? deviceId;
  final String? model;
  final int? timerRemainingSeconds;
  final double? powerW;
  final double? voltageV;
  final double? currentA;
  final double? energyWh;
  final SmartChargingSession? session;
  final int revision;
  final CrossDeviceControlState controlState;

  bool get isActive => const {
    'arming',
    'starting',
    'active',
    'stopping',
    'unknown',
  }.contains(state);

  bool get isStale => DateTime.now().toUtc().difference(updatedAt).inMinutes >= 2;

  Duration? get remaining => timerRemainingSeconds == null
      ? session?.remaining(DateTime.now())
      : Duration(seconds: timerRemainingSeconds!.clamp(0, 86400).toInt());

  Map<String, dynamic> toCacheJson() => {
    'uid': uid,
    'sessionId': sessionId,
    'vehicleId': vehicleId,
    'state': state,
    'relay': relay,
    'targetSoc': targetSoc,
    'updatedAt': updatedAt.toIso8601String(),
    'source': source,
    'deviceId': deviceId,
    'model': model,
    'timerRemainingSeconds': timerRemainingSeconds,
    'powerW': powerW,
    'voltageV': voltageV,
    'currentA': currentA,
    'energyWh': energyWh,
    'revision': revision,
  };

  static ActiveChargingSessionSnapshot? fromCacheJson(Map<String, dynamic> json) {
    final uid = json['uid']?.toString();
    final sessionId = json['sessionId']?.toString();
    final vehicleId = json['vehicleId']?.toString();
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    if (uid == null || sessionId == null || vehicleId == null || updatedAt == null) {
      return null;
    }
    return ActiveChargingSessionSnapshot(
      uid: uid,
      sessionId: sessionId,
      vehicleId: vehicleId,
      state: json['state']?.toString() ?? 'unknown',
      relay: json['relay'] as bool?,
      targetSoc: (json['targetSoc'] as num?)?.toDouble(),
      updatedAt: updatedAt.toUtc(),
      source: json['source']?.toString() ?? 'shelly_smart_charging',
      deviceId: json['deviceId']?.toString(),
      model: json['model']?.toString(),
      timerRemainingSeconds: (json['timerRemainingSeconds'] as num?)?.toInt(),
      powerW: (json['powerW'] as num?)?.toDouble(),
      voltageV: (json['voltageV'] as num?)?.toDouble(),
      currentA: (json['currentA'] as num?)?.toDouble(),
      energyWh: (json['energyWh'] as num?)?.toDouble(),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Account-scoped live view of charging sessions. It is intentionally
/// independent of the selected vehicle so a session started on another
/// device remains visible in the shell and can be reconciled safely.
class ActiveChargingSessionCoordinator extends ChangeNotifier {
  ActiveChargingSessionCoordinator({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  String? _uid;
  List<ActiveChargingSessionSnapshot> _sessions = const [];
  bool _loading = false;
  DateTime? _lastErrorAt;

  List<ActiveChargingSessionSnapshot> get sessions => _sessions;
  bool get loading => _loading;
  DateTime? get lastErrorAt => _lastErrorAt;

  Future<void> bindUser(String uid) async {
    if (uid.trim().isEmpty) return;
    if (_uid == uid && _subscription != null) return;
    await _subscription?.cancel();
    _uid = uid;
    _sessions = const [];
    _loading = true;
    notifyListeners();
    await _loadCache(uid);
    final query = _firestore
        .collection('ChargeLogs')
        .where('ownerUid', isEqualTo: uid)
        .limit(100);
    _subscription = query.snapshots().listen(
      (snapshot) {
        if (_uid != uid) return;
        _sessions = snapshot.docs
            .map((doc) => _fromDocument(doc))
            .whereType<ActiveChargingSessionSnapshot>()
            .where((item) => item.isActive)
            .toList(growable: false)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        _loading = false;
        _lastErrorAt = null;
        unawaited(_persistCache(uid));
        notifyListeners();
      },
      onError: (_) {
        if (_uid != uid) return;
        _loading = false;
        _lastErrorAt = DateTime.now().toUtc();
        notifyListeners();
      },
    );
  }

  void clear() {
    _subscription?.cancel();
    _subscription = null;
    _uid = null;
    _sessions = const [];
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('active_charge_sessions.v1.$uid');
      if (raw == null || _uid != uid) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _sessions = decoded
          .whereType<Map>()
          .map((item) => ActiveChargingSessionSnapshot.fromCacheJson(
                Map<String, dynamic>.from(item),
              ))
          .whereType<ActiveChargingSessionSnapshot>()
          .where((item) => item.uid == uid)
          .where((item) => item.isActive)
          .toList(growable: false);
      notifyListeners();
    } on Object {
      // Cache is an optimization; Firestore remains authoritative.
    }
  }

  Future<void> _persistCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_uid != uid) return;
      await prefs.setString(
        'active_charge_sessions.v1.$uid',
        jsonEncode(_sessions.map((item) => item.toCacheJson()).toList()),
      );
    } on Object {
      // Ignore cache write failures; never block relay safety.
    }
  }

  ActiveChargingSessionSnapshot? forVehicle(String vehicleId) {
    for (final item in _sessions) {
      if (item.vehicleId == vehicleId) return item;
    }
    return null;
  }

  ActiveChargingSessionSnapshot? _fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data['source']?.toString() != 'shelly_smart_charging') return null;
    final state = data['sessionState']?.toString() ?? data['status']?.toString();
    if (state == null ||
        !const {'arming', 'starting', 'active', 'stopping', 'unknown'}
            .contains(state)) {
      return null;
    }
    final raw = data['smartChargingSession'];
    SmartChargingSession? session;
    if (raw is Map && state != 'unknown') {
      try {
        session = SmartChargingSession.fromJson(Map<String, dynamic>.from(raw));
      } on Object {
        session = null;
      }
    }
    DateTime? date(Object? value) {
      if (value is Timestamp) return value.toDate().toUtc();
      return DateTime.tryParse(value?.toString() ?? '')?.toUtc();
    }
    final updated = date(data['updatedAt']) ??
        session?.updatedAt.toUtc() ??
        DateTime.now().toUtc();
    final owner = _uid;
    if (owner == null) return null;
    final target = (data['targetSoc'] as num?)?.toDouble() ?? session?.targetSoc;
    final timer = (data['timerRemainingSeconds'] as num?)?.toInt();
    return ActiveChargingSessionSnapshot(
      uid: owner,
      sessionId: document.id,
      vehicleId: data['vehicleId']?.toString() ?? session?.vehicleId ?? '',
      state: state,
      relay: data['relay'] as bool?,
      targetSoc: target,
      updatedAt: updated,
      source: data['source']?.toString() ?? 'shelly_smart_charging',
      deviceId: data['deviceId']?.toString(),
      model: data['model']?.toString(),
      timerRemainingSeconds: timer,
      powerW: (data['latestPowerW'] as num?)?.toDouble(),
      voltageV: (data['latestVoltageV'] as num?)?.toDouble(),
      currentA: (data['latestCurrentA'] as num?)?.toDouble(),
      energyWh: (data['energyWh'] as num?)?.toDouble(),
      session: session,
      revision: (data['revision'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
