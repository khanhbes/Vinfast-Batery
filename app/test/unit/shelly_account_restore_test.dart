import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/data/models/shelly_connection_state.dart';
import 'package:vinfast_battery/data/models/smart_charger_binding.dart';
import 'package:vinfast_battery/data/services/server_smart_charger_service.dart';
import 'package:vinfast_battery/data/services/shelly_connection_coordinator.dart';
import 'package:vinfast_battery/data/services/smart_charger_credentials_service.dart';

class _Auth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Credentials extends SmartChargerCredentialsService {
  int writes = 0;
  @override
  Future<SmartChargerBinding?> readCachedServerBinding() async => null;
  @override
  Future<void> cacheServerBinding(SmartChargerBinding? binding) async {
    writes++;
  }
}

class _Server extends ServerSmartChargerService {
  _Server() : super(auth: _Auth());
  final started = Completer<void>();
  final response = Completer<SmartChargerBinding?>();
  @override
  Future<SmartChargerBinding?> getBinding({String? vehicleId}) {
    started.complete();
    return response.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'late binding response after account change is discarded without caching',
    () async {
      SharedPreferences.setMockInitialValues({});
      final credentials = _Credentials();
      final server = _Server();
      final coordinator = ShellyConnectionCoordinator(
        credentials: credentials,
        serverCharger: server,
      );
      coordinator.activateAccount('account-a');
      final restoring = coordinator.restore();
      await server.started.future.timeout(const Duration(seconds: 2));
      coordinator.activateAccount('account-b');
      server.response.complete(
        const SmartChargerBinding(
          deviceId: 'test-a',
          displayName: 'Device A',
          model: 'S3PL-00112EU',
          provider: 'vault_cloud',
          mode: SmartChargerConnectionMode.serverCloud,
        ),
      );
      await restoring;
      expect(credentials.writes, 0);
      expect(coordinator.current.state, ShellyConnectionFlowState.disconnected);
      expect(coordinator.current.deviceName, isNull);
      await coordinator.dispose();
    },
  );
}
