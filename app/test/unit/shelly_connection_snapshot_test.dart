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
}
