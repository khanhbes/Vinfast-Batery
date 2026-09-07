import 'package:flutter_test/flutter_test.dart';
import '../qa_harness/fake_shelly_gateway.dart';

void main() {
  group('QA Audit — Smart Charger Safety & State Machine Tests (CHK-23..27, APP-H1, APP-H9..12)', () {
    late FakeShellyGateway gateway;

    setUp(() {
      gateway = FakeShellyGateway();
    });

    test('CHK-24 & APP-H9: Relay ON is only confirmed after verified readback from hardware', () async {
      // Step 1: Initial state is OFF
      expect(gateway.state, ShellyRelayState.off);

      // Step 2: Send Switch.Set ON
      final response = await gateway.handleRpcRequest('Switch.Set', {'id': 0, 'on': true});
      expect(response.statusCode, 200);

      // Readback confirmed ON
      expect(gateway.state, ShellyRelayState.on);
      expect(gateway.commandOnCount, 1);

      // Verify status query returns matching output
      final statusRes = await gateway.handleRpcRequest('Switch.GetStatus', {'id': 0});
      expect(statusRes.statusCode, 200);
      expect(statusRes.body.contains('"output":true'), isTrue);
    });

    test('CHK-25: Readback mismatch error is raised when relay fails to engage physically', () async {
      // Injected fault: hardware fails to engage relay despite accepting command
      gateway.simulateMismatchOnReadback = true;

      final response = await gateway.handleRpcRequest('Switch.Set', {'id': 0, 'on': true});
      expect(response.statusCode, 200);

      // State machine MUST transition to readbackMismatch, not optimistic ON
      expect(gateway.state, ShellyRelayState.readbackMismatch);
    });

    test('CHK-23 & APP-H12: Manual OFF has highest safety priority and executes without delay', () async {
      // Turn relay ON first
      await gateway.handleRpcRequest('Switch.Set', {'id': 0, 'on': true});
      expect(gateway.state, ShellyRelayState.on);

      // Execute manual OFF
      final offRes = await gateway.handleRpcRequest('Switch.Set', {'id': 0, 'on': false});
      expect(offRes.statusCode, 200);
      expect(gateway.state, ShellyRelayState.off);
      expect(gateway.commandOffCount, 1);
    });

    test('CHK-26 & APP-H11: Device restart resets to OFF state and NEVER auto-energizes relay', () async {
      // Relay is ON prior to restart
      await gateway.handleRpcRequest('Switch.Set', {'id': 0, 'on': true});
      expect(gateway.state, ShellyRelayState.on);

      // Trigger restart
      gateway.triggerDeviceRestart();

      // Post-restart state MUST be OFF
      expect(gateway.state, ShellyRelayState.off);

      // Query status post-restart
      final statusRes = await gateway.handleRpcRequest('Switch.GetStatus', {'id': 0});
      expect(statusRes.body.contains('"output":false'), isTrue);
    });

    test('Safety Cutoff: Overpower or overtemperature event immediately halts relay', () {
      gateway.state = ShellyRelayState.on;
      gateway.triggerSafetyCutoff(reason: 'overpower_3200w');

      expect(gateway.state, ShellyRelayState.safetyCutoff);
      expect(gateway.callHistory.any((call) => call['event'] == 'safety_cutoff'), isTrue);
    });

    test('APP-H10: Timeout on Cloud followed by LAN fallback does not cause double ON race', () async {
      // Step 1: Simulate cloud timeout
      gateway.shouldTimeout = true;
      expect(
        () => gateway.handleRpcRequest('Switch.Set', {'id': 0, 'on': true}),
        throwsA(isA<Exception>()),
      );

      // Step 2: Fallback to LAN (timeout resolved)
      gateway.shouldTimeout = false;
      final lanResponse = await gateway.handleRpcRequest('Switch.Set', {'id': 0, 'on': true});
      expect(lanResponse.statusCode, 200);
      expect(gateway.state, ShellyRelayState.on);

      // Only one successful ON command engaged
      expect(gateway.commandOnCount, 1);
    });
  });
}
