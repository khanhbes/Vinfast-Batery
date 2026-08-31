import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChargingConnectionState {
  const ChargingConnectionState({
    this.internetAvailable = true,
    this.apiReachable = true,
    this.firebaseReachable = true,
    this.gatewayReachable = true,
    this.shellyReachable = true,
    this.reconnecting = false,
    this.lastSuccessfulStatusAt,
    this.lastSuccessfulSessionAt,
  });

  final bool internetAvailable;
  final bool apiReachable;
  final bool firebaseReachable;
  final bool gatewayReachable;
  final bool shellyReachable;
  final bool reconnecting;
  final DateTime? lastSuccessfulStatusAt;
  final DateTime? lastSuccessfulSessionAt;

  bool get fullyConnected =>
      internetAvailable && apiReachable && firebaseReachable && shellyReachable;
  bool get chargingProtected => shellyReachable;

  ChargingConnectionState copyWith({
    bool? internetAvailable,
    bool? apiReachable,
    bool? firebaseReachable,
    bool? gatewayReachable,
    bool? shellyReachable,
    bool? reconnecting,
    DateTime? lastSuccessfulStatusAt,
    DateTime? lastSuccessfulSessionAt,
  }) => ChargingConnectionState(
    internetAvailable: internetAvailable ?? this.internetAvailable,
    apiReachable: apiReachable ?? this.apiReachable,
    firebaseReachable: firebaseReachable ?? this.firebaseReachable,
    gatewayReachable: gatewayReachable ?? this.gatewayReachable,
    shellyReachable: shellyReachable ?? this.shellyReachable,
    reconnecting: reconnecting ?? this.reconnecting,
    lastSuccessfulStatusAt:
        lastSuccessfulStatusAt ?? this.lastSuccessfulStatusAt,
    lastSuccessfulSessionAt:
        lastSuccessfulSessionAt ?? this.lastSuccessfulSessionAt,
  );
}

class ActiveChargingSnapshot {
  const ActiveChargingSnapshot({
    required this.sessionId,
    required this.vehicleId,
    required this.targetSoc,
    required this.effectiveStopAt,
    required this.lastEstimatedSoc,
    required this.lastSessionEnergyWh,
    required this.lastKnownRelay,
  });

  final String sessionId;
  final String vehicleId;
  final double targetSoc;
  final DateTime effectiveStopAt;
  final double lastEstimatedSoc;
  final double lastSessionEnergyWh;
  final bool lastKnownRelay;
}

class ConnectionCoordinator {
  ConnectionCoordinator({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  static const _snapshotPrefix = 'smart_charge.active_snapshot.v3.';
  static const _backoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  final Connectivity _connectivity;
  final _controller = StreamController<ChargingConnectionState>.broadcast();
  StreamSubscription<ConnectivityResult>? _subscription;
  Timer? _retryTimer;
  int _retryIndex = 0;
  ChargingConnectionState _state = const ChargingConnectionState();

  ChargingConnectionState get state => _state;
  Stream<ChargingConnectionState> get stream => _controller.stream;

  Future<void> start() async {
    try {
      // EventChannel creates its subscription outside the returned Future. A
      // binding check avoids an uncaught asynchronous error in pure Dart unit
      // tests while remaining a no-op on supported app runtimes.
      ServicesBinding.instance;
      _subscription ??= _connectivity.onConnectivityChanged.listen(
        _onNetwork,
        onError: (_) {
          // Reachability probes remain authoritative. Connectivity is only a
          // hint and must never replace the current charging workspace.
        },
      );
      _onNetwork(await _connectivity.checkConnectivity());
    } catch (_) {
      // MissingPluginException is expected in unit tests and unsupported
      // platforms. Keep the optimistic initial state and let API/Shelly
      // readbacks update each independent reachability flag.
    }
  }

  void markStatusSuccess({required bool shellyReachable}) {
    _retryIndex = 0;
    _retryTimer?.cancel();
    _emit(
      _state.copyWith(
        apiReachable: true,
        gatewayReachable: true,
        shellyReachable: shellyReachable,
        reconnecting: false,
        lastSuccessfulStatusAt: DateTime.now(),
      ),
    );
  }

  void markSessionSuccess() => _emit(
    _state.copyWith(
      apiReachable: true,
      lastSuccessfulSessionAt: DateTime.now(),
    ),
  );

  void markFailure({
    bool api = false,
    bool firebase = false,
    bool gateway = false,
    bool shelly = false,
    Future<void> Function()? retry,
  }) {
    _emit(
      _state.copyWith(
        apiReachable: api ? false : _state.apiReachable,
        firebaseReachable: firebase ? false : _state.firebaseReachable,
        gatewayReachable: gateway ? false : _state.gatewayReachable,
        shellyReachable: shelly ? false : _state.shellyReachable,
        reconnecting: true,
      ),
    );
    if (retry != null) _scheduleRetry(retry);
  }

  Future<void> retryNow(Future<void> Function() action) async {
    _retryTimer?.cancel();
    _emit(_state.copyWith(reconnecting: true));
    await action();
  }

  Future<void> saveSnapshot(ActiveChargingSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('$_snapshotPrefix${snapshot.sessionId}', [
      snapshot.vehicleId,
      snapshot.targetSoc.toString(),
      snapshot.effectiveStopAt.toUtc().toIso8601String(),
      snapshot.lastEstimatedSoc.toString(),
      snapshot.lastSessionEnergyWh.toString(),
      snapshot.lastKnownRelay.toString(),
    ]);
  }

  Future<void> clearSnapshot(String sessionId) async =>
      (await SharedPreferences.getInstance()).remove(
        '$_snapshotPrefix$sessionId',
      );

  /// Returns locally persisted active-session snapshots for the shell pill.
  /// Snapshots contain no credentials and allow an active vehicle to remain
  /// visible after the user switches context to another vehicle.
  Future<List<ActiveChargingSnapshot>> loadSnapshots() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <ActiveChargingSnapshot>[];
    for (final key in prefs.getKeys().where((key) => key.startsWith(_snapshotPrefix))) {
      final values = prefs.getStringList(key);
      if (values == null || values.length < 6) continue;
      final stopAt = DateTime.tryParse(values[2]);
      final target = double.tryParse(values[1]);
      final soc = double.tryParse(values[3]);
      final energy = double.tryParse(values[4]);
      final relay = values[5].toLowerCase() == 'true';
      if (stopAt == null || target == null || soc == null || energy == null) continue;
      result.add(ActiveChargingSnapshot(
        sessionId: key.substring(_snapshotPrefix.length),
        vehicleId: values[0],
        targetSoc: target,
        effectiveStopAt: stopAt,
        lastEstimatedSoc: soc,
        lastSessionEnergyWh: energy,
        lastKnownRelay: relay,
      ));
    }
    return result;
  }

  void _onNetwork(ConnectivityResult result) {
    final online = result != ConnectivityResult.none;
    _emit(
      _state.copyWith(
        internetAvailable: online,
        reconnecting: !online || _state.reconnecting,
      ),
    );
  }

  void _scheduleRetry(Future<void> Function() action) {
    if (_retryTimer?.isActive == true) return;
    final delay = _backoff[_retryIndex.clamp(0, _backoff.length - 1)];
    _retryIndex = (_retryIndex + 1).clamp(0, _backoff.length - 1);
    _retryTimer = Timer(delay, () async {
      try {
        await action();
      } catch (_) {
        _scheduleRetry(action);
      }
    });
  }

  void _emit(ChargingConnectionState value) {
    _state = value;
    if (!_controller.isClosed) _controller.add(value);
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    await _subscription?.cancel();
    await _controller.close();
  }
}
