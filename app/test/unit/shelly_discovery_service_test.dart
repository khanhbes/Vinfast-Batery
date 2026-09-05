import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinfast_battery/data/services/shelly_discovery_service.dart';

void main() {
  group('ShellyDiscoveryService.sweepSubnet', () {
    test('sweeps subnet and discovers Shelly device on matching IP', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == '192.168.1.50' &&
            request.url.path == '/rpc/Shelly.GetDeviceInfo') {
          return http.Response(
            jsonEncode({
              'id': 'shellyplugs3-c049ef87b64c',
              'app': 'PlugSGen3',
              'ver': '1.4.4',
              'auth_en': false,
              'name': 'Living Room Charger',
            }),
            200,
          );
        }
        if (request.url.host == '192.168.1.75' &&
            request.url.path == '/rpc/Shelly.GetDeviceInfo') {
          return http.Response('Unauthorized', 401);
        }
        // Others timeout or 404
        return http.Response('Not Found', 404);
      });

      const service = ShellyDiscoveryService();
      double lastProgress = 0.0;
      int foundInCallback = 0;

      final devices = await service.sweepSubnet(
        baseSubnet: '192.168.1.',
        timeout: const Duration(milliseconds: 100),
        batchSize: 50,
        httpClient: mockClient,
        onProgress: (progress, found) {
          lastProgress = progress;
          foundInCallback = found;
        },
      );

      expect(lastProgress, 1.0);
      expect(devices.length, 2);
      expect(foundInCallback, 2);

      final openDevice = devices.firstWhere((d) => d.address == '192.168.1.50');
      expect(openDevice.id, 'shellyplugs3-c049ef87b64c');
      expect(openDevice.name, 'Living Room Charger');
      expect(openDevice.model, 'PlugSGen3');
      expect(openDevice.authEnabled, false);

      final protectedDevice = devices.firstWhere((d) => d.address == '192.168.1.75');
      expect(protectedDevice.authEnabled, true);
    });
  });
}
