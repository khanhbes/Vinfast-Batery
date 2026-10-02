import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/shelly_connection.dart';
import '../models/shelly_connection_state.dart';
import '../models/smart_charger_binding.dart';
import '../models/smart_charger_status.dart';
import '../repositories/smart_charger_repository.dart';
import 'server_smart_charger_service.dart';
import 'shelly_capability_checker.dart';
import 'shelly_cloud_auth_service.dart';
import 'shelly_discovery_service.dart';
import 'smart_charger_credentials_service.dart';
import 'smart_charger_service.dart';

class ShellyConnectionSnapshot {
  const ShellyConnectionSnapshot({
    required this.state,
    this.devices = const [],
    this.errorMessage,
    this.status,
    this.deviceName,
    this.isPermissionDenied = false,
    this.isWifiUnavailable = false,
    this.isLinked = false,
    this.codeRefreshRequired = false,
  });

  final ShellyConnectionFlowState state;
  final List<DiscoveredShellyDevice> devices;
  final String? errorMessage;
  final SmartChargerStatus? status;
  final String? deviceName;
  final bool isPermissionDenied;
  final bool isWifiUnavailable;
  final bool isLinked;
  final bool codeRefreshRequired;

  String get connectionLabel => switch (state) {
    ShellyConnectionFlowState.connected => 'Đã kết nối Shelly',
    ShellyConnectionFlowState.offline =>
      isLinked ? 'Đã liên kết · Tạm mất kết nối' : 'Tạm mất kết nối',
    ShellyConnectionFlowState.verifying =>
      isLinked
          ? 'Đã liên kết · Đang kiểm tra kết nối'
          : 'Đang kiểm tra kết nối',
    ShellyConnectionFlowState.verificationRequired => 'Cần kiểm tra an toàn',
    _ => isLinked ? 'Đã liên kết Shelly' : 'Chưa kết nối Shelly',
  };

  factory ShellyConnectionSnapshot.fromServerBinding(
    SmartChargerBinding binding, {
    SmartChargerStatus? status,
  }) {
    final evidence =
        binding.model.toUpperCase() == 'S3PL-00112EU' &&
        binding.powerMeterVerified &&
        binding.safeBootVerified &&
        binding.noLoadTestVerified;
    return ShellyConnectionSnapshot(
      state: status == null
          ? ShellyConnectionFlowState.verifying
          : !status.online
          ? ShellyConnectionFlowState.offline
          : evidence
          ? ShellyConnectionFlowState.connected
          : ShellyConnectionFlowState.verificationRequired,
      isLinked: true,
      codeRefreshRequired: binding.codeRefreshRequired,
      devices: [
        DiscoveredShellyDevice(
          id: binding.deviceId,
          address: 'Shelly Cloud',
          model: binding.model,
          name: binding.displayName,
          generation: 3,
        ),
      ],
      deviceName: binding.displayName,
      status: status,
    );
  }
}

/// Shared, LAN-first Normal Mode coordinator. It never accepts Cloud secrets
/// and never actuates the relay until the user explicitly confirms the safety
/// test. Direct control is enabled only after the complete evidence chain.
class ShellyConnectionCoordinator {
  ShellyConnectionCoordinator({
    ShellyDiscoveryService? discovery,
    SmartChargerCredentialsService? credentials,
    SmartChargerService? charger,
    ServerSmartChargerService? serverCharger,
    ShellyCloudAuthService? cloudAuth,
  }) : _discovery = discovery ?? const ShellyDiscoveryService(),
       _credentials = credentials ?? SmartChargerCredentialsService(),
       _charger = charger ?? SmartChargerService(),
       _serverCharger = serverCharger,
       _cloudAuth = cloudAuth;

  static final shared = ShellyConnectionCoordinator();

  final ShellyDiscoveryService _discovery;
  final SmartChargerCredentialsService _credentials;
  final SmartChargerService _charger;
  ServerSmartChargerService? _serverCharger;
  ShellyCloudAuthService? _cloudAuth;

  ServerSmartChargerService get serverCharger =>
      _serverCharger ??= ServerSmartChargerService();
  ShellyCloudAuthService get cloudAuth =>
      _cloudAuth ??= ShellyCloudAuthService();
  final _states = StreamController<ShellyConnectionSnapshot>.broadcast();
  ShellyConnectionSnapshot _current = const ShellyConnectionSnapshot(
    state: ShellyConnectionFlowState.disconnected,
  );
  ShellyConnectionProfile? _pendingProfile;
  DiscoveredShellyDevice? _pendingDevice;
  bool _pendingServerCloud = false;
  bool _busy = false;
  String? _accountUid;
  int _accountGeneration = 0;
  Future<ShellyConnectionSnapshot>? _restoreInFlight;

  /// Clears UI context, not persisted bindings or hardware state.
  void activateAccount(String? uid) {
    if (_accountUid == uid) return;
    _accountUid = uid;
    _accountGeneration++;
    _restoreInFlight = null;
    _busy = false;
    _pendingProfile = null;
    _pendingDevice = null;
    _pendingServerCloud = false;
    _emit(
      const ShellyConnectionSnapshot(
        state: ShellyConnectionFlowState.disconnected,
      ),
    );
  }

  ShellyConnectionSnapshot get current => _current;
  Stream<ShellyConnectionSnapshot> get states => _states.stream;

  void _emit(ShellyConnectionSnapshot value) {
    _current = value;
    if (!_states.isClosed) _states.add(value);
  }

  Future<ShellyConnectionSnapshot> restore() {
    if (_restoreInFlight != null) return _restoreInFlight!;
    late final Future<ShellyConnectionSnapshot> task;
    task = _restore().whenComplete(() {
      if (identical(_restoreInFlight, task)) _restoreInFlight = null;
    });
    _restoreInFlight = task;
    return task;
  }

  void updateCodeNotice(SmartChargerStatus status) {
    if (!_current.isLinked ||
        _current.devices.length != 1 ||
        status.deviceId == null ||
        !_sameDevice(status.deviceId!, _current.devices.single.id) ||
        status.codeRefreshRequired == null) {
      return;
    }
    final old = _current;
    _emit(
      ShellyConnectionSnapshot(
        state: old.state,
        devices: old.devices,
        errorMessage: old.errorMessage,
        status: old.status,
        deviceName: old.deviceName,
        isLinked: old.isLinked,
        isPermissionDenied: old.isPermissionDenied,
        isWifiUnavailable: old.isWifiUnavailable,
        codeRefreshRequired: status.codeRefreshRequired!,
      ),
    );
  }

  Future<ShellyConnectionSnapshot> _restore() async {
    if (_busy) return _current;
    final generation = _accountGeneration;
    final mode = await SmartChargerRepositoryFactory.currentMode();
    if (generation != _accountGeneration) return _current;
    if (mode == SmartChargerConnectionMode.serverCloud) {
      return await _restoreServerCloudBinding() ?? _current;
    }
    final profile = await _credentials.readProfile();
    if (generation != _accountGeneration) return _current;
    if (profile == null) {
      final serverState = await _restoreServerCloudBinding();
      if (serverState != null) return serverState;
      _emit(
        const ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.disconnected,
        ),
      );
      return _current;
    }
    final verification = await _credentials.readVerification();
    if (generation != _accountGeneration) return _current;
    final alreadyVerified =
        verification.readyForControl &&
        verification.verifiedDeviceId == profile.deviceId &&
        verification.verifiedModel == profile.model &&
        (verification.verificationFingerprint?.isNotEmpty ?? false);
    _emit(
      ShellyConnectionSnapshot(
        state: alreadyVerified
            ? ShellyConnectionFlowState.verifying
            : ShellyConnectionFlowState.connecting,
        deviceName: profile.deviceName,
        isLinked: true,
      ),
    );
    _busy = true;
    try {
      final refreshed = await _refreshProfile(profile, generation: generation);
      if (generation != _accountGeneration) return _current;
      final test = await _charger.testConnection(profile: refreshed);
      if (generation != _accountGeneration) return _current;
      final liveFingerprint = SmartChargerCredentialsService.fingerprintFor(
        refreshed,
        initialState: test.initialState,
        autoOn: test.autoOn,
      );
      final identityReady =
          test.deviceVerified &&
          test.model?.toUpperCase() == 'S3PL-00112EU' &&
          refreshed.model.toUpperCase() == 'S3PL-00112EU';
      final safeBootReady =
          test.safeBootVerified &&
          test.initialState?.toLowerCase() == 'off' &&
          test.autoOn == false;
      final ready =
          alreadyVerified &&
          identityReady &&
          safeBootReady &&
          test.powerMeterAvailable &&
          verification.verificationFingerprint == liveFingerprint;
      final liveStatus = test.lanStatus ?? test.cloudStatus;
      if (liveStatus == null || !liveStatus.online) {
        _emit(
          ShellyConnectionSnapshot(
            state: ShellyConnectionFlowState.offline,
            deviceName: refreshed.deviceName,
            isLinked: true,
            status: liveStatus,
          ),
        );
      } else if (!test.powerMeterAvailable) {
        _pendingProfile = refreshed;
        _emit(
          ShellyConnectionSnapshot(
            state: ShellyConnectionFlowState.incompatible,
            errorMessage: 'Thiết bị không trả đủ dữ liệu đo điện năng.',
            deviceName: refreshed.deviceName,
            isLinked: true,
          ),
        );
      } else if (!ready) {
        await _credentials.saveVerification(
          SmartChargerVerificationState.unverified,
        );
        _pendingProfile = refreshed;
        _pendingDevice = DiscoveredShellyDevice(
          id: refreshed.deviceId,
          address: refreshed.lanAddress ?? 'Shelly Cloud',
          model: test.model ?? refreshed.model,
          name: refreshed.deviceName,
          generation: 3,
        );
        _emit(
          ShellyConnectionSnapshot(
            state: ShellyConnectionFlowState.verificationRequired,
            status: test.lanStatus ?? test.cloudStatus,
            deviceName: refreshed.deviceName,
            isLinked: true,
          ),
        );
      } else {
        _emit(
          ShellyConnectionSnapshot(
            state: ShellyConnectionFlowState.connected,
            status: test.lanStatus ?? test.cloudStatus,
            deviceName: refreshed.deviceName,
            isLinked: true,
          ),
        );
      }
    } on Object {
      if (generation != _accountGeneration) return _current;
      debugPrint('[ShellyCoordinator] live probe unavailable');
      if (!alreadyVerified) {
        _emit(
          ShellyConnectionSnapshot(
            state: ShellyConnectionFlowState.offline,
            errorMessage:
                'Shelly đang ngoại tuyến. Hãy kiểm tra nguồn điện và Wi-Fi.',
            deviceName: profile.deviceName,
            isLinked: true,
          ),
        );
      } else {
        _emit(
          ShellyConnectionSnapshot(
            state: ShellyConnectionFlowState.offline,
            errorMessage:
                'Shelly đang ngoại tuyến. Kiểm tra nguồn điện và kết nối mạng rồi thử lại.',
            deviceName: profile.deviceName,
            isLinked: true,
          ),
        );
      }
    } finally {
      if (generation == _accountGeneration) _busy = false;
    }
    return _current;
  }

  Future<ShellyConnectionSnapshot?> _restoreServerCloudBinding() async {
    final generation = _accountGeneration;
    SmartChargerBinding? restoredBinding = await _credentials
        .readCachedServerBinding();
    if (generation != _accountGeneration) return _current;
    if (restoredBinding != null) {
      _emit(ShellyConnectionSnapshot.fromServerBinding(restoredBinding));
    }
    try {
      final binding = await serverCharger.getBinding();
      if (generation != _accountGeneration) return _current;
      if (binding == null ||
          binding.mode != SmartChargerConnectionMode.serverCloud) {
        await _credentials.cacheServerBinding(null);
        if (generation != _accountGeneration) return _current;
        _emit(
          const ShellyConnectionSnapshot(
            state: ShellyConnectionFlowState.disconnected,
          ),
        );
        return null;
      }
      restoredBinding = binding;
      await _credentials.cacheServerBinding(binding);
      if (generation != _accountGeneration) return _current;
      _emit(ShellyConnectionSnapshot.fromServerBinding(binding));
      final status = await serverCharger.getStatus();
      if (generation != _accountGeneration) return _current;
      final device = DiscoveredShellyDevice(
        id: binding.deviceId,
        address: 'Shelly Cloud',
        model: binding.model,
        name: binding.displayName,
        generation: 3,
      );
      final restored = ShellyConnectionSnapshot.fromServerBinding(
        binding,
        status: status,
      );
      _emit(
        ShellyConnectionSnapshot(
          state: restored.state,
          codeRefreshRequired: restored.codeRefreshRequired,
          isLinked: true,
          devices: [device],
          status: status,
          deviceName: binding.displayName,
          errorMessage:
              restored.state == ShellyConnectionFlowState.verificationRequired
              ? 'Shelly cần được kiểm tra an toàn trước khi điều khiển.'
              : null,
        ),
      );
      return _current;
    } on SmartChargerException catch (error) {
      if (generation != _accountGeneration) return _current;
      _emit(
        ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.offline,
          deviceName: restoredBinding?.displayName,
          devices: _current.devices,
          codeRefreshRequired: restoredBinding?.codeRefreshRequired ?? false,
          isLinked: restoredBinding != null,
          errorMessage: error.message,
        ),
      );
      return _current;
    } on Object {
      if (generation != _accountGeneration) return _current;
      _emit(
        ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.offline,
          deviceName: restoredBinding?.displayName,
          devices: _current.devices,
          codeRefreshRequired: restoredBinding?.codeRefreshRequired ?? false,
          isLinked: restoredBinding != null,
          errorMessage:
              'Không thể xác minh Shelly với máy chủ lúc này. Hãy thử lại khi có mạng.',
        ),
      );
      return _current;
    }
  }

  Future<ShellyConnectionSnapshot> autoConnect() async {
    if (_busy) return _current;
    _busy = true;
    _pendingProfile = null;
    _pendingDevice = null;
    _emit(
      const ShellyConnectionSnapshot(
        state: ShellyConnectionFlowState.discovering,
      ),
    );
    try {
      var devices = await _discovery.discoverAndProbe();
      if (devices.isEmpty) {
        devices = await _probeSweepResults(await _discovery.sweepSubnet());
      }
      if (devices.isEmpty) {
        _emit(
          const ShellyConnectionSnapshot(
            state: ShellyConnectionFlowState.connectionFailed,
            errorMessage:
                'Không tìm thấy Shelly trong mạng Wi-Fi này. Hãy kiểm tra nguồn điện và thử lại.',
          ),
        );
      } else if (devices.length == 1) {
        // The only compatible candidate is selected internally; the screen
        // proceeds directly to the connection/safety confirmation.
        await _prepareDevice(devices.single);
      } else {
        _emit(
          ShellyConnectionSnapshot(
            state: ShellyConnectionFlowState.multipleDevices,
            devices: List.unmodifiable(devices),
          ),
        );
      }
    } on SocketException {
      _emit(
        const ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connectionFailed,
          errorMessage:
              'Không tìm thấy mạng Wi-Fi cục bộ. Vui lòng kết nối Wi-Fi cho điện thoại và thử lại.',
          isWifiUnavailable: true,
        ),
      );
    } on TimeoutException {
      _emit(
        const ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connectionFailed,
          errorMessage:
              'Shelly không phản hồi. Hãy kiểm tra nguồn điện và thử lại.',
        ),
      );
    } on Object catch (e) {
      final msg = e.toString().toLowerCase();
      final isPermission =
          msg.contains('permission') ||
          msg.contains('denied') ||
          msg.contains('local network');
      _emit(
        ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connectionFailed,
          errorMessage: isPermission
              ? 'Quyền truy cập mạng cục bộ chưa được cấp. Vui lòng cấp quyền trong Cài đặt.'
              : 'Không thể quét mạng Wi-Fi. Hãy kiểm tra kết nối và thử lại.',
          isPermissionDenied: isPermission,
        ),
      );
    } finally {
      _busy = false;
    }
    return _current;
  }

  Future<ShellyConnectionSnapshot> connectDevice(
    DiscoveredShellyDevice device, {
    String? localPassword,
  }) async {
    if (_busy) return _current;
    _busy = true;
    try {
      await _prepareDevice(device, localPassword: localPassword);
    } finally {
      _busy = false;
    }
    return _current;
  }

  Future<void> _prepareDevice(
    DiscoveredShellyDevice device, {
    String? localPassword,
  }) async {
    _emit(
      ShellyConnectionSnapshot(
        state: ShellyConnectionFlowState.connecting,
        devices: [device],
      ),
    );
    try {
      final probed = await _discovery.probeDevice(device);
      if (probed.authEnabled &&
          (localPassword == null || localPassword.isEmpty)) {
        _pendingDevice = probed;
        _emit(
          ShellyConnectionSnapshot(
            state: ShellyConnectionFlowState.passwordRequired,
            devices: [probed],
          ),
        );
        return;
      }
      if (!const ShellyCapabilityChecker().isCompatible(probed) &&
          !probed.authEnabled) {
        _emit(
          ShellyConnectionSnapshot(
            state: ShellyConnectionFlowState.incompatible,
            devices: [probed],
            errorMessage: 'Thiết bị này không hỗ trợ đầy đủ đo điện năng.',
          ),
        );
        return;
      }
      final profile = ShellyConnectionProfile(
        deviceId: probed.id,
        deviceName: _friendlyName(probed),
        model: probed.model,
        firmware: probed.firmware,
        lanAddress: probed.address,
        localPassword: localPassword,
      );
      final test = await _charger.testConnection(profile: profile);
      if (!test.powerMeterAvailable) {
        _emit(
          ShellyConnectionSnapshot(
            state: ShellyConnectionFlowState.incompatible,
            devices: [probed],
            errorMessage:
                'Shelly không trả đủ công suất, điện áp, dòng và điện năng.',
          ),
        );
        return;
      }
      await serverCharger.claimLanDevice(
        deviceId: profile.deviceId,
        model: profile.model,
      );
      _pendingServerCloud = false;
      _pendingProfile = profile;
      _pendingDevice = probed;
      _emit(
        ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.verificationRequired,
          devices: [probed],
          status: test.lanStatus ?? test.cloudStatus,
          deviceName: profile.deviceName,
        ),
      );
    } on SmartChargerException catch (error) {
      final isAuth =
          error.code == 'authFailed' ||
          error.code == 'unauthorized' ||
          error.message.toLowerCase().contains('mật khẩu') ||
          error.message.toLowerCase().contains('401') ||
          error.message.toLowerCase().contains('auth');
      if (isAuth) {
        _pendingDevice = device;
        _emit(
          ShellyConnectionSnapshot(
            state: ShellyConnectionFlowState.passwordRequired,
            devices: [device],
            deviceName: _friendlyName(device),
            errorMessage: 'Mật khẩu thiết bị không đúng. Vui lòng thử lại.',
          ),
        );
        return;
      }
      _emit(
        ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connectionFailed,
          devices: [device],
          errorMessage: error.message,
          deviceName: _friendlyName(device),
        ),
      );
    } on Object {
      _emit(
        ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connectionFailed,
          devices: [device],
          errorMessage:
              'Không thể kết nối Shelly. Hãy kiểm tra kết nối và thử lại.',
          deviceName: _friendlyName(device),
        ),
      );
    }
  }

  /// The only Normal Mode path that may toggle the relay. The UI must show
  /// explicit user consent before invoking this method.
  Future<ShellyConnectionSnapshot> runConfirmedSafetyTest() async {
    final profile = _pendingProfile;
    final device = _pendingDevice;
    if (_busy || profile == null || device == null) return _current;
    _busy = true;
    _emit(
      ShellyConnectionSnapshot(
        state: ShellyConnectionFlowState.verifying,
        devices: [device],
        deviceName: profile.deviceName,
      ),
    );
    try {
      if (_pendingServerCloud) {
        final result = await serverCharger.runSafetyTest(
          deviceId: profile.deviceId,
          operationId:
              'safety-${DateTime.now().toUtc().microsecondsSinceEpoch}',
        );
        if (result['verified'] != true) {
          throw const SmartChargerException(
            'Shelly chưa vượt qua kiểm tra an toàn.',
            code: 'verificationFailed',
          );
        }
        final status = await serverCharger.getStatus();
        if (status.relay) {
          throw const SmartChargerException(
            'Không xác minh được relay OFF sau kiểm tra.',
            code: 'relayUnverified',
          );
        }
        await SmartChargerRepositoryFactory.setMode(
          SmartChargerConnectionMode.serverCloud,
        );
        _pendingProfile = null;
        _pendingDevice = null;
        _pendingServerCloud = false;
        // Persist the server evidence for restart; a failed read remains linked
        // but offline rather than claiming a connection from historical data.
        await _restoreServerCloudBinding();
        return _current;
      }
      await _charger.configureSafeBoot(profile: profile);
      final test = await _charger.testConnection(profile: profile);
      if (!test.deviceVerified ||
          test.model?.toUpperCase() != 'S3PL-00112EU' ||
          !test.powerMeterAvailable ||
          !test.safeBootVerified ||
          test.initialState?.toLowerCase() != 'off' ||
          test.autoOn != false) {
        throw const SmartChargerException(
          'Không xác minh được power meter hoặc Safe Boot trên Shelly.',
          code: 'verificationFailed',
        );
      }
      final safety = await _charger.runNoLoadTest(profile: profile);
      if (!safety.passed ||
          safety.noLoadPowerW > 5 ||
          safety.noLoadCurrentA > .1 ||
          safety.initialStatus.voltageV < 190 ||
          safety.initialStatus.voltageV > 255) {
        throw const SmartChargerException(
          'Kiểm tra an toàn chưa quan sát đủ ON, timer và OFF.',
          code: 'verificationFailed',
        );
      }
      await _credentials.saveProfile(profile);
      await _credentials.saveVerification(
        SmartChargerVerificationState(
          cloudVerified: test.cloudStatus != null,
          lanVerified: test.lanStatus != null,
          powerMeterVerified: true,
          safeBootVerified: true,
          noLoadTestVerified: true,
          lastVerifiedAt: DateTime.now(),
          verifiedDeviceId: profile.deviceId,
          verifiedModel: profile.model,
          verificationFingerprint:
              SmartChargerCredentialsService.fingerprintFor(
                profile,
                initialState: test.initialState,
                autoOn: test.autoOn,
              ),
        ),
      );
      await SmartChargerRepositoryFactory.setMode(
        SmartChargerConnectionMode.advancedDirect,
      );
      _pendingProfile = null;
      _pendingDevice = null;
      _emit(
        ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connected,
          isLinked: true,
          devices: [device],
          status: test.lanStatus ?? test.cloudStatus,
          deviceName: profile.deviceName,
        ),
      );
    } on SmartChargerException catch (error) {
      _emit(
        ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connectionFailed,
          devices: [device],
          errorMessage: error.message,
          deviceName: profile.deviceName,
        ),
      );
    } on Object {
      _emit(
        ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connectionFailed,
          devices: [device],
          errorMessage:
              'Không hoàn tất được kiểm tra an toàn. Shelly chưa được kích hoạt điều khiển.',
          deviceName: profile.deviceName,
        ),
      );
    } finally {
      _busy = false;
    }
    return _current;
  }

  /// Connects using an admin-generated connection code (Flow 3).
  Future<ShellyConnectionSnapshot> redeemCode(String code) async {
    if (_busy) return _current;
    final generation = _accountGeneration;
    final normalized = code.trim().toUpperCase();
    if (normalized.length != 6) {
      _emit(
        const ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connectionFailed,
          errorMessage: 'Mã kết nối phải có đúng 6 ký tự.',
        ),
      );
      return _current;
    }
    _busy = true;
    _emit(
      const ShellyConnectionSnapshot(
        state: ShellyConnectionFlowState.connecting,
      ),
    );
    try {
      final profile = await serverCharger.redeemConnectionCode(normalized);
      if (generation != _accountGeneration) return _current;
      await SmartChargerRepositoryFactory.setMode(
        SmartChargerConnectionMode.serverCloud,
      );
      if (generation != _accountGeneration) return _current;
      _pendingProfile = profile;
      _pendingServerCloud = true;
      _pendingDevice = DiscoveredShellyDevice(
        id: profile.deviceId,
        address: 'Shelly Cloud',
        model: 'S3PL-00112EU',
        name: profile.deviceName,
        generation: 3,
      );
      // Redeeming a rotated code acknowledges it; it must not discard a
      // previously verified enrollment or force another no-load ON test.
      final restored = await _restoreServerCloudBinding();
      if (generation != _accountGeneration) return _current;
      if (restored?.state == ShellyConnectionFlowState.connected) {
        _pendingProfile = null;
        _pendingDevice = null;
        _pendingServerCloud = false;
      }
    } on SmartChargerException catch (error) {
      if (generation != _accountGeneration) return _current;
      _emit(
        ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connectionFailed,
          errorMessage: error.message,
        ),
      );
    } on Object {
      if (generation != _accountGeneration) return _current;
      _emit(
        ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connectionFailed,
          errorMessage:
              'Chưa thể liên kết Shelly. Kiểm tra kết nối rồi thử lại.',
        ),
      );
    } finally {
      if (generation == _accountGeneration) _busy = false;
    }
    return _current;
  }

  /// Connects using Shelly Cloud credentials (Flow 2).
  Future<ShellyConnectionSnapshot> connectCloudKey(
    String authKey, {
    ShellyCloudDevice? selectedDevice,
  }) async {
    if (_busy) return _current;
    final trimmedKey = authKey.trim();
    if (trimmedKey.isEmpty) {
      _emit(
        const ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connectionFailed,
          errorMessage: 'Vui lòng nhập Cloud Auth Key.',
        ),
      );
      return _current;
    }
    _busy = true;
    _emit(
      const ShellyConnectionSnapshot(
        state: ShellyConnectionFlowState.connecting,
      ),
    );
    try {
      final devices = await cloudAuth.listDevices(authKey: trimmedKey);
      if (devices.isEmpty) {
        _emit(
          const ShellyConnectionSnapshot(
            state: ShellyConnectionFlowState.connectionFailed,
            errorMessage:
                'Không tìm thấy thiết bị nào trong tài khoản Shelly Cloud này.',
          ),
        );
        return _current;
      }

      final target = selectedDevice ?? devices.first;
      final profile = ShellyConnectionProfile(
        cloudHost: target.serverUri?.isNotEmpty == true
            ? target.serverUri!
            : ShellyCloudAuthService.defaultCloudHosts.first,
        cloudAuthKey: target.cloudAuthKey.isNotEmpty
            ? target.cloudAuthKey
            : trimmedKey,
        deviceId: target.id,
        deviceName: target.name.isNotEmpty ? target.name : 'Shelly Plug S Gen3',
        model: target.type.isNotEmpty ? target.type : 'S3PL-00112EU',
      );
      await serverCharger.registerShellyDevice(profile);
      _pendingProfile = profile;
      _pendingServerCloud = true;
      _pendingDevice = DiscoveredShellyDevice(
        id: profile.deviceId,
        address: 'Shelly Cloud',
        model: 'S3PL-00112EU',
        name: profile.deviceName,
        generation: 3,
      );
      _emit(
        ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.verificationRequired,
          deviceName: profile.deviceName,
        ),
      );
    } on SmartChargerException catch (error) {
      _emit(
        ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connectionFailed,
          errorMessage: error.message,
        ),
      );
    } catch (e) {
      _emit(
        ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.connectionFailed,
          errorMessage:
              'Chưa thể kết nối Shelly Cloud. Kiểm tra mạng rồi thử lại.',
        ),
      );
    } finally {
      _busy = false;
    }
    return _current;
  }

  Future<void> disconnect() async {
    final profile = await _credentials.readProfile();
    if (profile == null) {
      _emit(
        const ShellyConnectionSnapshot(
          state: ShellyConnectionFlowState.disconnected,
        ),
      );
      return;
    }
    if (await _charger.hasActiveOrUnknownRelay()) {
      throw const SmartChargerException(
        'Không thể ngắt kết nối khi phiên sạc đang hoạt động hoặc relay chưa xác định. Hãy tắt sạc và xác minh OFF trước.',
        code: 'activeSessionConflict',
      );
    }
    final status = await _charger.getStatus();
    if (status.relay) {
      throw const SmartChargerException(
        'Relay vẫn đang ON. Hãy tắt sạc và xác minh OFF trước khi ngắt kết nối.',
        code: 'relayUnverified',
      );
    }
    await _credentials.clearProfile();
    await SmartChargerRepositoryFactory.setMode(
      SmartChargerConnectionMode.serverCloud,
    );
    _pendingProfile = null;
    _pendingDevice = null;
    _emit(
      const ShellyConnectionSnapshot(
        state: ShellyConnectionFlowState.disconnected,
      ),
    );
  }

  Future<ShellyConnectionProfile> _refreshProfile(
    ShellyConnectionProfile profile, {
    int? generation,
  }) async {
    try {
      await _charger.testConnection(profile: profile);
      return profile;
    } on Object {
      if (!profile.hasLan && profile.hasCloud) {
        // Cấu hình Cloud-only không có IP LAN nên không quét dải mạng nội bộ
        rethrow;
      }
      var candidates = await _discovery.discoverAndProbe();
      if (candidates.isEmpty) {
        candidates = await _probeSweepResults(await _discovery.sweepSubnet());
      }
      for (final candidate in candidates) {
        if (_sameDevice(candidate.id, profile.deviceId)) {
          final updated = profile.copyWith(lanAddress: candidate.address);
          final verification = await _credentials.readVerification();
          if (generation != null && generation != _accountGeneration) {
            throw const SmartChargerException(
              'Phiên đăng nhập đã thay đổi.',
              code: 'account_changed',
            );
          }
          await _credentials.saveProfile(updated);
          if (generation != null && generation != _accountGeneration) {
            throw const SmartChargerException(
              'Phiên đăng nhập đã thay đổi.',
              code: 'account_changed',
            );
          }
          await _credentials.saveVerification(verification);
          return updated;
        }
      }
      rethrow;
    }
  }

  Future<List<DiscoveredShellyDevice>> _probeSweepResults(
    List<DiscoveredShellyDevice> candidates,
  ) async {
    final result = <DiscoveredShellyDevice>[];
    for (final candidate in candidates) {
      try {
        final probed = await _discovery.probeDevice(candidate);
        if (const ShellyCapabilityChecker().isCompatible(probed) ||
            const ShellyCapabilityChecker().isPotentiallyCompatible(probed)) {
          result.add(probed);
        }
      } on Object {
        // Continue scanning: one unreachable LAN address is expected.
      }
    }
    return result;
  }

  String _friendlyName(DiscoveredShellyDevice device) {
    final name = device.name?.trim() ?? '';
    if (name.isEmpty ||
        RegExp(r'^[a-f0-9:-]{8,}$', caseSensitive: false).hasMatch(name)) {
      return device.model.toUpperCase().contains('S3PL')
          ? 'Shelly Plug S'
          : 'Shelly';
    }
    return name;
  }

  bool _sameDevice(String a, String b) =>
      a.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase() ==
      b.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();

  Future<void> dispose() => _states.close();
}
