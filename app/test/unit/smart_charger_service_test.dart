import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/data/services/smart_charger_service.dart';

void main() {
  test('GET status 200 returns typed model', () async {
    final service = SmartChargerService(
      baseUrl: 'http://gateway:8000/',
      client: MockClient((request) async {
        expect(request.url.path, '/api/charger/status');
        return http.Response(
          jsonEncode({
            'online': true,
            'relay': false,
            'power_w': 0,
            'voltage_v': 229.1,
            'current_a': 0,
            'frequency_hz': 50,
            'temperature_c': null,
            'energy_wh': 12,
          }),
          200,
        );
      }),
    );

    final status = await service.getStatus();
    expect(status.online, isTrue);
    expect(status.powerW, 0.0);
  });

  test('GET status 503 throws typed exception', () async {
    final service = SmartChargerService(
      baseUrl: 'http://gateway:8000',
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({'detail': 'Shelly offline'}), 503),
      ),
    );
    await expectLater(
      service.getStatus(),
      throwsA(
        isA<SmartChargerException>().having(
          (error) => error.statusCode,
          'statusCode',
          503,
        ),
      ),
    );
  });

  test('malformed JSON throws typed exception', () async {
    final service = SmartChargerService(
      baseUrl: 'http://gateway:8000',
      client: MockClient((_) async => http.Response('not-json', 200)),
    );
    await expectLater(
      service.getStatus(),
      throwsA(isA<SmartChargerException>()),
    );
  });

  test('empty baseUrl throws configuration exception', () async {
    final service = SmartChargerService(
      baseUrl: '',
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      service.getStatus(),
      throwsA(
        isA<SmartChargerException>().having(
          (error) => error.message,
          'message',
          contains('chưa được cấu hình'),
        ),
      ),
    );
  });

  test('POST ON and OFF return command results', () async {
    final paths = <String>[];
    final service = SmartChargerService(
      baseUrl: 'http://gateway:8000',
      client: MockClient((request) async {
        paths.add(request.url.path);
        final relay = request.url.path.endsWith('/on');
        return http.Response(
          jsonEncode({
            'success': true,
            'relay': relay,
            'previous_state': !relay,
          }),
          200,
        );
      }),
    );
    expect((await service.turnOn()).relay, isTrue);
    expect((await service.turnOff()).relay, isFalse);
    expect(paths, ['/api/charger/on', '/api/charger/off']);
  });

  test('session POST serializes ISO timestamps and parses id', () async {
    final startedAt = DateTime(2026, 8, 27, 18, 30);
    final predictedFullAt = DateTime(2026, 8, 27, 21, 10);
    late Map<String, dynamic> sent;
    final service = SmartChargerService(
      baseUrl: 'http://gateway:8000',
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'success': true,
            'session_id': 'abcd1234',
            'mode': 'monitor_only',
            'received_at': '2026-08-27T11:30:00Z',
          }),
          200,
        );
      }),
    );

    final response = await service.startMonitoringSession(
      SmartChargingSessionRequest(
        vehicleId: 'VF-001',
        startSoc: 20,
        targetSoc: 80,
        predictedMinutes: 160,
        startedAt: startedAt,
        predictedFullAt: predictedFullAt,
        chargingMode: 'standard',
      ),
    );

    expect(sent['started_at'], startedAt.toIso8601String());
    expect(sent['predicted_full_at'], predictedFullAt.toIso8601String());
    expect(response.sessionId, 'abcd1234');
    expect(response.mode, 'monitor_only');
  });
}
