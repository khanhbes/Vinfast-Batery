import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinfast_battery/data/services/shelly_cloud_auth_service.dart';

void main() {
  group('ShellyCloudAuthService', () {
    test('returns empty list for empty key', () async {
      final service = ShellyCloudAuthService();
      final list = await service.listDevices(authKey: '');
      expect(list, isEmpty);
    });

    test('parses devices list from interface/device/list format', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/interface/device/list');
        expect(request.url.queryParameters['auth_key'], 'test-auth-key');
        return http.Response(
          jsonEncode({
            'isok': true,
            'data': {
              'devices': {
                'shellyplugs3-c049ef87b64c': {
                  'id': 'shellyplugs3-c049ef87b64c',
                  'name': 'Bếp Sạc',
                  'type': 'S3PL-00112EU',
                  'online': true,
                },
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = ShellyCloudAuthService(client: client);
      final list = await service.listDevices(
        authKey: 'test-auth-key',
        cloudHost: 'https://shelly-108-eu.shelly.cloud',
      );

      expect(list.length, 1);
      expect(list.first.id, 'shellyplugs3-c049ef87b64c');
      expect(list.first.name, 'Bếp Sạc');
      expect(list.first.isOnline, isTrue);
    });

    test('parses devices list from device/all_status fallback format', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/interface/device/list') {
          return http.Response('Not found', 404);
        }
        expect(request.url.path, '/device/all_status');
        return http.Response(
          jsonEncode({
            'isok': true,
            'data': {
              'devices_status': {
                'shellyplugs3-123456abcdef': {
                  'name': 'Gara Xe',
                  'type': 'relay',
                  'online': true,
                },
              },
            },
          }),
          200,
        );
      });

      final service = ShellyCloudAuthService(client: client);
      final list = await service.listDevices(
        authKey: 'test-auth-key',
        cloudHost: 'https://shelly-108-eu.shelly.cloud',
      );

      expect(list.length, 1);
      expect(list.first.id, 'shellyplugs3-123456abcdef');
      expect(list.first.name, 'Gara Xe');
      expect(list.first.isOnline, isTrue);
    });
  });
}
