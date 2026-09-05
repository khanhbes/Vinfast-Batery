import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/shelly_qr_parser.dart';

void main() {
  group('ShellyQrParser', () {
    test('parses plain Shelly device ID', () {
      final res = ShellyQrParser.parse('shellyplugs3-c049ef87b64c');
      expect(res, isNotNull);
      expect(res!.deviceId, 'shellyplugs3-c049ef87b64c');
      expect(res.model, 'Shelly Plug S Gen3');
    });

    test('parses Shelly URL with id query parameter', () {
      final res = ShellyQrParser.parse(
        'https://shelly-108-eu.shelly.cloud/?id=shellyplugs3-123456abcdef',
      );
      expect(res, isNotNull);
      expect(res!.deviceId, 'shellyplugs3-123456abcdef');
      expect(res.cloudHost, 'https://shelly-108-eu.shelly.cloud');
      expect(res.model, 'Shelly Plug S Gen3');
    });

    test('parses Shelly URL with device_id query param', () {
      final res = ShellyQrParser.parse(
        'https://shelly-api-eu.shelly.cloud/device?device_id=shellyplus1-9876543210ab',
      );
      expect(res, isNotNull);
      expect(res!.deviceId, 'shellyplus1-9876543210ab');
      expect(res.model, 'Shelly Plus 1');
    });

    test('parses JSON config payload', () {
      final jsonStr = '''
      {
        "id": "shellyplugs3-c049ef87b64c",
        "cloud_host": "https://shelly-108-eu.shelly.cloud",
        "model": "S3PL-00112EU",
        "ip": "192.168.1.88"
      }
      ''';
      final res = ShellyQrParser.parse(jsonStr);
      expect(res, isNotNull);
      expect(res!.deviceId, 'shellyplugs3-c049ef87b64c');
      expect(res.cloudHost, 'https://shelly-108-eu.shelly.cloud');
      expect(res.lanAddress, '192.168.1.88');
    });

    test('parses MAC address formatted with colons or hyphens', () {
      final res1 = ShellyQrParser.parse('C0:49:EF:87:B6:4C');
      expect(res1, isNotNull);
      expect(res1!.deviceId, 'shellyplugs3-c049ef87b64c');

      final res2 = ShellyQrParser.parse('c0-49-ef-87-b6-4c');
      expect(res2, isNotNull);
      expect(res2!.deviceId, 'shellyplugs3-c049ef87b64c');
    });

    test('returns null for empty or invalid text', () {
      expect(ShellyQrParser.parse(''), isNull);
      expect(ShellyQrParser.parse('   '), isNull);
      expect(ShellyQrParser.parse('invalid string with spaces ???'), isNull);
    });
  });
}
