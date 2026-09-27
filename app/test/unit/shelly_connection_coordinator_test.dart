import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vinfast_battery/data/models/shelly_connection.dart';
import 'package:vinfast_battery/data/models/shelly_connection_state.dart';
import 'package:vinfast_battery/data/services/shelly_connection_coordinator.dart';
import 'package:vinfast_battery/data/services/shelly_discovery_service.dart';

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
