import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vinfast_battery/data/models/shelly_connection.dart';
import 'package:vinfast_battery/data/models/shelly_connection_state.dart';
import 'package:vinfast_battery/data/services/shelly_connection_coordinator.dart';
import 'package:vinfast_battery/data/services/shelly_discovery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/data/models/smart_charger_binding.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';
import 'package:vinfast_battery/data/models/smart_charger_capabilities.dart';
import 'package:vinfast_battery/data/services/smart_charger_service.dart';
import 'package:vinfast_battery/data/services/server_smart_charger_service.dart';
import 'package:vinfast_battery/data/services/smart_charger_credentials_service.dart';

class _Credentials extends SmartChargerCredentialsService {
  @override
  Future<SmartChargerBinding?> readCachedServerBinding({
    String? vehicleId,
  }) async => null;
  @override
  Future<void> cacheServerBinding(
    SmartChargerBinding? binding, {
    String? vehicleId,
  }) async {}
}

class _Auth extends Fake implements FirebaseAuth {}

class _Server extends ServerSmartChargerService {
  _Server() : super(auth: _Auth());
  final scopes = <String?>[];
  bool verified = true;
  SmartChargerConnectionMode mode = SmartChargerConnectionMode.serverCloud;
  bool online = true;
  int safetyCommands = 0;
  String? redeemedVehicle;
  bool failRedeem = false;
  bool failStatus = false;
  @override
  Future<SmartChargerBinding?> getBinding({String? vehicleId}) async {
    scopes.add(vehicleId);
    return SmartChargerBinding(
      deviceId: 'qa-device',
      displayName: 'Shelly',
      model: 'S3PL-00112EU',
      provider: 'cloud',
      mode: mode,
      powerMeterVerified: true,
      safeBootVerified: true,
      noLoadTestVerified: verified,
    );
  }

  @override
  Future<SmartChargerStatus> getStatus({String? vehicleId}) async {
    scopes.add(vehicleId);
    if (failStatus) {
      throw const SmartChargerException('QA timeout', code: 'timeout');
    }
    return SmartChargerStatus(
      deviceId: 'qa-device',
      online: online,
      relay: false,
      powerW: 0,
      voltageV: 230,
      currentA: 0,
      frequencyHz: 50,
      temperatureC: 30,
      energyWh: 0,
    );
  }

  @override
  Future<Map<String, dynamic>> getLive({
    String? vehicleId,
    bool shared = false,
  }) async {
    final status = await getStatus(vehicleId: vehicleId);
    final capabilities = await getCapabilities(vehicleId: vehicleId);
    return {'status': status.toJson(), 'capabilities': capabilities.toJson()};
  }

  @override
  Future<SmartChargerCapabilities> getCapabilities({String? vehicleId}) async {
    scopes.add(vehicleId);
    return SmartChargerCapabilities.fromJson({
      'canReadStatus': true,
      'canManualOff': true,
      'controlBlockedCode': 'STAGING_HARDWARE_DISABLED',
    });
  }

  @override
  Future<ShellyConnectionProfile> redeemConnectionCode(
    String code, {
    String? vehicleId,
    String? operationId,
  }) async {
    redeemedVehicle = vehicleId;
    if (failRedeem) {
      throw const SmartChargerException(
        'Mã hết hiệu lực.',
        code: 'connectionCodeUnavailable',
      );
    }
    return const ShellyConnectionProfile(deviceId: 'qa-device');
  }

  @override
  Future<Map<String, dynamic>> runSafetyTest({
    required String deviceId,
    required String operationId,
  }) async {
    safetyCommands++;
    verified = true;
    return {'verified': true};
  }
}

class _Discovery extends ShellyDiscoveryService {
  const _Discovery(this.devices);

  final List<DiscoveredShellyDevice> devices;

  @override
  Future<List<DiscoveredShellyDevice>> discoverAndProbe({
    Duration discoveryTimeout = const Duration(seconds: 5),
    Duration probeTimeout = const Duration(seconds: 3),
  }) async => devices;

  @override
  Future<List<DiscoveredShellyDevice>> sweepSubnet({
    String? baseSubnet,
    Duration timeout = const Duration(milliseconds: 350),
    int batchSize = 30,
    void Function(double progress, int foundCount)? onProgress,
    http.Client? httpClient,
  }) async => const [];

  @override
  Future<DiscoveredShellyDevice> probeDevice(
    DiscoveredShellyDevice device, {
    Duration timeout = const Duration(seconds: 3),
    http.Client? httpClient,
  }) async => device;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'legacy server metadata stays linked without rerunning safety or granting ON',
    () async {
      SharedPreferences.setMockInitialValues({
        'smart_charger.connection_mode.v1': 'server_cloud',
      });
      final server = _Server()
        ..mode = SmartChargerConnectionMode.advancedDirect;
      final coordinator = ShellyConnectionCoordinator(
        credentials: _Credentials(),
        serverCharger: server,
      )..activateAccount('qa-legacy');
      final restored = await coordinator.restore(vehicleId: 'qa-vehicle');
      expect(restored.isLinked, true);
      expect(
        restored.state,
        ShellyConnectionFlowState.serverConnectionRequired,
      );
      expect(restored.serverBinding!.noLoadTestVerified, true);
      expect(restored.readyForControl, false);
      expect(restored.connectionLabel, contains('Cần kết nối qua máy chủ'));
      expect(server.safetyCommands, 0);
      await coordinator.dispose();
    },
  );
  test(
    'settings restore retains charge vehicle scope and account change clears it',
    () async {
      SharedPreferences.setMockInitialValues({
        'smart_charger.connection_mode.v1': 'server_cloud',
      });
      final server = _Server();
      final coordinator = ShellyConnectionCoordinator(
        credentials: _Credentials(),
        serverCharger: server,
      );
      coordinator.activateAccount('qa-account');
      final first = await coordinator.restore(vehicleId: 'qa-vehicle');
      expect(first.isLinked, true);
      expect(first.state, ShellyConnectionFlowState.connected);
      await coordinator.restore();
      expect(server.scopes, everyElement('qa-vehicle'));
      coordinator.activateAccount('qa-other');
      expect(coordinator.current.isLinked, false);
      server.scopes.clear();
      await coordinator.restore();
      expect(server.scopes, everyElement(isNull));
      await coordinator.dispose();
    },
  );
  test(
    'reports a friendly failed state when LAN discovery finds nothing',
    () async {
      final coordinator = ShellyConnectionCoordinator(
        discovery: const _Discovery([]),
      );

      final result = await coordinator.autoConnect();

      expect(result.state, ShellyConnectionFlowState.connectionFailed);
      expect(result.errorMessage, isNotEmpty);
      await coordinator.dispose();
    },
  );
  test(
    'first failed read after app start shows checking, not lost connection',
    () async {
      SharedPreferences.setMockInitialValues({
        'smart_charger.connection_mode.v1': 'server_cloud',
      });
      final server = _Server()..failStatus = true;
      final coordinator = ShellyConnectionCoordinator(
        credentials: _Credentials(),
        serverCharger: server,
      );
      coordinator.activateAccount('qa-account');
      await coordinator.restore(vehicleId: 'qa-vehicle');
      expect(coordinator.current.state, ShellyConnectionFlowState.verifying);
      expect(coordinator.current.connectionLabel, contains('Đang kiểm tra'));
      expect(coordinator.current.readyForControl, false);
      coordinator.markServerUnavailable(
        uid: 'qa-account',
        vehicleId: 'qa-vehicle',
      );
      expect(coordinator.current.state, ShellyConnectionFlowState.verifying);
      server.failStatus = false;
      coordinator.updateCodeNotice(
        await server.getStatus(vehicleId: 'qa-vehicle'),
        uid: 'qa-account',
        vehicleId: 'qa-vehicle',
      );
      expect(coordinator.current.state, ShellyConnectionFlowState.connected);
      await coordinator.dispose();
    },
  );
  test(
    'offline evidence reconnects on shared readback without another safety test',
    () async {
      SharedPreferences.setMockInitialValues({
        'smart_charger.connection_mode.v1': 'server_cloud',
      });
      final server = _Server()..online = false;
      final coordinator = ShellyConnectionCoordinator(
        credentials: _Credentials(),
        serverCharger: server,
      );
      coordinator.activateAccount('qa-account');
      await coordinator.restore(vehicleId: 'qa-vehicle');
      expect(coordinator.current.state, ShellyConnectionFlowState.offline);
      server.online = true;
      coordinator.updateCodeNotice(
        await server.getStatus(vehicleId: 'qa-vehicle'),
        uid: 'qa-account',
        vehicleId: 'qa-vehicle',
      );
      expect(coordinator.current.state, ShellyConnectionFlowState.connected);
      expect(coordinator.current.readyForControl, false);
      expect(coordinator.current.controlBlockedMessage, contains('thử nghiệm'));
      expect(server.safetyCommands, 0);
      coordinator.updateServerSnapshot(
        uid: 'different-account',
        vehicleId: 'qa-vehicle',
        binding: coordinator.current.serverBinding!,
        status: await server.getStatus(),
      );
      expect(coordinator.current.state, ShellyConnectionFlowState.connected);
      await coordinator.dispose();
    },
  );
  test(
    'restored incomplete enrollment can run explicit safety test in the same vehicle scope',
    () async {
      SharedPreferences.setMockInitialValues({
        'smart_charger.connection_mode.v1': 'server_cloud',
      });
      final server = _Server()..verified = false;
      final coordinator = ShellyConnectionCoordinator(
        credentials: _Credentials(),
        serverCharger: server,
      );
      coordinator.activateAccount('qa-account');
      expect(
        (await coordinator.restore(vehicleId: 'qa-vehicle')).state,
        ShellyConnectionFlowState.verificationRequired,
      );
      expect(server.safetyCommands, 0);
      final result = await coordinator.runConfirmedSafetyTest();
      expect(server.safetyCommands, 1);
      expect(result.state, ShellyConnectionFlowState.connected);
      expect(server.scopes, everyElement('qa-vehicle'));
      await coordinator.dispose();
    },
  );
  test(
    'invalid rotated code retains the existing binding and safety evidence',
    () async {
      SharedPreferences.setMockInitialValues({
        'smart_charger.connection_mode.v1': 'server_cloud',
      });
      final server = _Server()..failRedeem = true;
      final coordinator = ShellyConnectionCoordinator(
        credentials: _Credentials(),
        serverCharger: server,
      );
      coordinator.activateAccount('qa-account');
      await coordinator.restore(vehicleId: 'qa-vehicle');
      final result = await coordinator.redeemCode(
        'ABC123',
        vehicleId: 'qa-vehicle',
      );
      expect(server.redeemedVehicle, 'qa-vehicle');
      expect(result.isLinked, true);
      expect(result.serverBinding!.noLoadTestVerified, true);
      expect(result.errorMessage, contains('Mã hết'));
      expect(server.safetyCommands, 0);
      await coordinator.dispose();
    },
  );

  test(
    'accepted code that leaves the legacy link reports an error, not silence',
    () async {
      SharedPreferences.setMockInitialValues({});
      final server = _Server()
        ..mode = SmartChargerConnectionMode.advancedDirect;
      final coordinator = ShellyConnectionCoordinator(
        credentials: _Credentials(),
        serverCharger: server,
      );
      coordinator.activateAccount('qa-account');
      await coordinator.restore(vehicleId: 'qa-vehicle');
      final result = await coordinator.redeemCode(
        'ABC123',
        vehicleId: 'qa-vehicle',
      );
      expect(server.redeemedVehicle, 'qa-vehicle');
      expect(result.state, ShellyConnectionFlowState.serverConnectionRequired);
      expect(result.errorMessage, contains('vẫn giữ liên kết cũ'));
      expect(server.safetyCommands, 0);
      await coordinator.dispose();
    },
  );

  test(
    'requests a simple local password for a protected known Shelly',
    () async {
      const device = DiscoveredShellyDevice(
        id: 'shelly-test',
        address: '192.168.1.20',
        model: 'S3PL-00112EU',
        authEnabled: true,
      );
      final coordinator = ShellyConnectionCoordinator(
        discovery: const _Discovery([device]),
      );

      final result = await coordinator.autoConnect();

      expect(result.state, ShellyConnectionFlowState.passwordRequired);
      await coordinator.dispose();
    },
  );

  test('rejects a discovered relay without complete meter evidence', () async {
    const device = DiscoveredShellyDevice(
      id: 'shelly-test',
      address: '192.168.1.20',
      model: 'Shelly Plus 1',
    );
    final coordinator = ShellyConnectionCoordinator(
      discovery: const _Discovery([device]),
    );

    final result = await coordinator.autoConnect();

    expect(result.state, ShellyConnectionFlowState.incompatible);
    await coordinator.dispose();
  });
}
