import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/shelly_connection_state.dart';
import 'package:vinfast_battery/data/models/smart_charger_binding.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';
import 'package:vinfast_battery/data/services/shelly_connection_coordinator.dart';

const binding = SmartChargerBinding(
  deviceId: 'test-device',
  displayName: 'Shelly',
  model: 'S3PL-00112EU',
  provider: 'vault_cloud',
  mode: SmartChargerConnectionMode.serverCloud,
  powerMeterVerified: true,
  safeBootVerified: true,
  noLoadTestVerified: true,
);
SmartChargerStatus status(bool online) => SmartChargerStatus(
  deviceId: 'test-device',
  online: online,
  relay: false,
  powerW: 0,
  voltageV: 230,
  currentA: 0,
  frequencyHz: 50,
  temperatureC: 30,
  energyWh: 0,
);

void main() {
  test('restored enrollment checks connection without forgetting evidence', () {
    final pending = ShellyConnectionSnapshot.fromServerBinding(binding);
    expect(pending.isLinked, true);
    expect(pending.state, ShellyConnectionFlowState.verifying);
    expect(pending.connectionLabel, 'Đã liên kết · Đang kiểm tra kết nối');
  });
  test('offline verified device is not sent back to safety test', () {
    final snapshot = ShellyConnectionSnapshot.fromServerBinding(
      binding,
      status: status(false),
    );
    expect(snapshot.isLinked, true);
    expect(snapshot.state, ShellyConnectionFlowState.offline);
    expect(snapshot.connectionLabel, 'Đã liên kết · Tạm mất kết nối');
  });
  test('online plus complete evidence is connected', () {
    final snapshot = ShellyConnectionSnapshot.fromServerBinding(
      binding,
      status: status(true),
    );
    expect(snapshot.state, ShellyConnectionFlowState.connected);
    expect(snapshot.connectionLabel, 'Đã kết nối Shelly');
  });
  test('uncertain operation retains linking but never advertises control', () {
    const snapshot = ShellyConnectionSnapshot(
      state: ShellyConnectionFlowState.verifying,
      isLinked: true,
      serverBinding: binding,
      controlUncertain: true,
    );
    expect(snapshot.connectionLabel, contains('Chưa xác minh'));
    expect(snapshot.controlBlockedMessage, contains('không bật lại'));
    expect(snapshot.readyForControl, false);
  });
  test('online alone never grants control readiness', () {
    const incomplete = SmartChargerBinding(
      deviceId: 'test-device',
      displayName: 'Shelly',
      model: 'S3PL-00112EU',
      provider: 'vault_cloud',
      mode: SmartChargerConnectionMode.serverCloud,
    );
    expect(
      ShellyConnectionSnapshot.fromServerBinding(
        incomplete,
        status: status(true),
      ).state,
      ShellyConnectionFlowState.verificationRequired,
    );
  });

  test('cached binding never restores online or grants live connection', () {
    final restored = SmartChargerBinding.fromJson(binding.toJson());
    expect(restored.online, false);
    expect(restored.noLoadTestVerified, true);
    expect(
      ShellyConnectionSnapshot.fromServerBinding(restored).state,
      ShellyConnectionFlowState.verifying,
    );
  });
  test('online readback for another device never claims connected', () {
    final wrong = SmartChargerStatus.fromJson({
      'online': true,
      'relay': false,
      'device_id': 'other-device',
    });
    final snapshot = ShellyConnectionSnapshot.fromServerBinding(
      binding,
      status: wrong,
    );
    expect(snapshot.state, ShellyConnectionFlowState.verificationRequired);
    expect(snapshot.readyForControl, false);
    expect(snapshot.errorMessage, contains('đúng Shelly'));
  });
  test(
    'historical no-load evidence and online never authorize ON by themselves',
    () {
      final snapshot = ShellyConnectionSnapshot.fromServerBinding(
        binding,
        status: status(true),
      );
      expect(snapshot.readyForControl, false);
      expect(sameShellyDevice('AA:BB:CC', 'aabbcc'), true);
      expect(sameShellyDevice('', ''), false);
    },
  );
}
