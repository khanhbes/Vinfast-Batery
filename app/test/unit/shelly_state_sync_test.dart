import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/data/models/shelly_connection_state.dart';
import 'package:vinfast_battery/data/models/smart_charger_binding.dart';
import 'package:vinfast_battery/data/models/smart_charger_capabilities.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';
import 'package:vinfast_battery/data/services/server_smart_charger_service.dart';
import 'package:vinfast_battery/data/services/shelly_connection_coordinator.dart';
import 'package:vinfast_battery/data/services/smart_charger_credentials_service.dart';
import 'package:vinfast_battery/data/services/smart_charger_service.dart';

/// Task108: one Shelly state across relaunch, grace on failed reads, fewer reads.
class _MemoryCredentials extends SmartChargerCredentialsService {
  final bindings = <String?, SmartChargerBinding?>{};
  final snapshots = <String, CachedServerSnapshot>{};

  @override
  Future<SmartChargerBinding?> readCachedServerBinding({
    String? vehicleId,
  }) async => bindings[vehicleId];

  @override
  Future<void> cacheServerBinding(
    SmartChargerBinding? binding, {
    String? vehicleId,
  }) async => bindings[vehicleId] = binding;

  @override
  Future<void> cacheServerSnapshot({
    required String vehicleId,
    required SmartChargerStatus status,
    SmartChargerCapabilities? capabilities,
    DateTime? updatedAt,
  }) async => snapshots[vehicleId] = CachedServerSnapshot(
    status: status,
    capabilities: capabilities,
    updatedAt: updatedAt,
  );

  @override
  Future<CachedServerSnapshot?> readCachedServerSnapshot({
    required String vehicleId,
  }) async => snapshots[vehicleId];
}

class _Auth extends Fake implements FirebaseAuth {}

class _Server extends ServerSmartChargerService {
  _Server() : super(auth: _Auth());
  bool fail = false;
  int liveReads = 0;

  static const binding = SmartChargerBinding(
    deviceId: 'qa-device',
    displayName: 'Shelly',
    model: 'S3PL-00112EU',
    provider: 'vault_cloud',
    mode: SmartChargerConnectionMode.serverCloud,
    powerMeterVerified: true,
    safeBootVerified: true,
    noLoadTestVerified: true,
  );

  @override
  Future<SmartChargerBinding?> getBinding({String? vehicleId}) async {
    if (fail) throw const SmartChargerException('down', code: 'timeout');
    return binding;
  }

  @override
  Future<Map<String, dynamic>> getLive({
    String? vehicleId,
    bool shared = false,
  }) async {
    liveReads++;
    if (fail) throw const SmartChargerException('down', code: 'timeout');
    return {
      'status': const SmartChargerStatus(
        deviceId: 'qa-device',
        online: true,
        relay: false,
        powerW: 0,
        voltageV: 228.3,
        currentA: 0,
        frequencyHz: 50,
        temperatureC: 30,
        energyWh: 0,
      ).toJson(),
      'capabilities': const SmartChargerCapabilities(
        canReadStatus: true,
        canManualOn: true,
        canManualOff: true,
        supportsDeviceTimer: true,
        canReadPower: true,
        canConfigureSafeBoot: false,
        cloudAvailable: true,
        lanAvailable: false,
        readyForControl: true,
        safeBootVerified: true,
        noLoadTestVerified: true,
      ).toJson(),
    };
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'smart_charger.connection_mode.v1': 'server_cloud',
    });
  });

  test('a failed read keeps the last readback but blocks control', () async {
    final server = _Server();
    final coordinator = ShellyConnectionCoordinator(
      credentials: _MemoryCredentials(),
      serverCharger: server,
    );
    coordinator.activateAccount('qa-a');
    final ready = await coordinator.restore(vehicleId: 'qa-vehicle');
    expect(ready.state, ShellyConnectionFlowState.connected);
    expect(ready.readyForControl, true);
    expect(ready.metricsLine, contains('228 V'));

    coordinator.markServerUnavailable(uid: 'qa-a', vehicleId: 'qa-vehicle');
    final held = coordinator.current;
    expect(held.state, ShellyConnectionFlowState.connected);
    expect(held.syncDelayed, true);
    expect(held.status, isNotNull);
    expect(held.capabilities, isNull);
    expect(held.readyForControl, false);
    expect(held.connectionLabel, contains('Đang đồng bộ lại'));
    await coordinator.dispose();
  });

  test(
    'relaunch shows the cached connection without granting control',
    () async {
      final credentials = _MemoryCredentials();
      final first = ShellyConnectionCoordinator(
        credentials: credentials,
        serverCharger: _Server(),
      );
      first.activateAccount('qa-a');
      await first.restore(vehicleId: 'qa-vehicle');
      await Future<void>.delayed(Duration.zero); // let the snapshot persist
      await first.dispose();
      expect(credentials.snapshots['qa-vehicle'], isNotNull);

      final offline = _Server()..fail = true;
      final relaunched = ShellyConnectionCoordinator(
        credentials: credentials,
        serverCharger: offline,
      );
      relaunched.activateAccount('qa-a');
      final shown = await relaunched.restore(vehicleId: 'qa-vehicle');
      expect(shown.isLinked, true);
      expect(shown.state, ShellyConnectionFlowState.connected);
      expect(shown.status?.voltageV, 228.3);
      expect(shown.readyForControl, false);
      await relaunched.dispose();
    },
  );

  test('repeated restore within the TTL does not re-read the server', () async {
    final server = _Server();
    final coordinator = ShellyConnectionCoordinator(
      credentials: _MemoryCredentials(),
      serverCharger: server,
    );
    coordinator.activateAccount('qa-a');
    await coordinator.restore(vehicleId: 'qa-vehicle');
    final reads = server.liveReads;
    await coordinator.restore(vehicleId: 'qa-vehicle');
    await coordinator.restore();
    expect(server.liveReads, reads);
    await coordinator.restore(vehicleId: 'qa-vehicle', force: true);
    expect(server.liveReads, reads + 1);
    await coordinator.dispose();
  });
}
