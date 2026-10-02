import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinfast_battery/data/services/shelly_api_transport.dart';
import 'package:vinfast_battery/data/services/smart_charger_service.dart';

void main() {
  test('TLS failure is typed, redacted and never retried', () async {
    var attempts = 0;
    final client = MockClient((_) async {
      attempts++;
      throw const HandshakeException('private-host secret-token');
    });
    addTearDown(client.close);
    await expectLater(
      ShellyApiTransport.send(
        client,
        http.Request('POST', Uri.https('example.org', '/on')),
      ),
      throwsA(
        isA<SmartChargerException>()
            .having((e) => e.code, 'code', 'tls_failed')
            .having((e) => e.retryable, 'retryable', false)
            .having((e) => e.commandMayHaveReachedDevice, 'ambiguous', true)
            .having(
              (e) => e.message,
              'redacted',
              isNot(contains('secret-token')),
            ),
      ),
    );
    expect(attempts, 1);
  });

  test('wrapped IO client handshake failure is classified as TLS', () async {
    final client = MockClient(
      (_) async => throw http.ClientException(
        'HandshakeException: private-host',
        Uri.https('example.org'),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      ShellyApiTransport.send(
        client,
        http.Request('GET', Uri.https('example.org')),
      ),
      throwsA(
        isA<SmartChargerException>()
            .having((e) => e.code, 'code', 'tls_failed')
            .having(
              (e) => e.commandMayHaveReachedDevice,
              'read is not ON',
              false,
            ),
      ),
    );
  });

  test('deadline includes stalled response body', () async {
    final body = StreamController<List<int>>();
    final client = MockClient.streaming(
      (_, _) async => http.StreamedResponse(body.stream, 200),
    );
    addTearDown(client.close);
    await expectLater(
      ShellyApiTransport.send(
        client,
        http.Request('GET', Uri.https('example.org')),
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(
        isA<SmartChargerException>().having((e) => e.code, 'code', 'timeout'),
      ),
    );
    await body.close();
  });

  test('accepted response is returned unchanged without retries', () async {
    final client = MockClient(
      (_) async => http.Response('{"success":true}', 200),
    );
    addTearDown(client.close);
    final response = await ShellyApiTransport.send(
      client,
      http.Request('GET', Uri.https('example.org')),
    );
    expect(response.statusCode, 200);
    expect(response.body, '{"success":true}');
  });
}
