import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/data/models/shelly_connection.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';
import 'package:vinfast_battery/data/services/smart_charger_credentials_service.dart';
import 'package:vinfast_battery/data/services/shelly_clients.dart';
import 'package:vinfast_battery/data/services/smart_charger_service.dart';

void main() {
  const validProfile = ShellyConnectionProfile(
    cloudHost: 'https://shelly-123-eu.shelly.cloud',
    cloudAuthKey: 'secret-key',
    deviceId: 'aabbccddeeff',
    lanAddress: '192.168.1.50',
  );

  group('ShellyConnectionProfile', () {
    test('requires HTTPS shelly.cloud host and a key/device ID', () {
      expect(validProfile.validate(), isNull);
      expect(
        const ShellyConnectionProfile(
          cloudHost: 'http://evil.example',
          cloudAuthKey: 'x',
          deviceId: 'x',
        ).validate(),
        isNotNull,
      );
    });

    test('only accepts private/link-local IP or .local for LAN HTTP', () {
      expect(isAllowedLanAddress('10.0.0.5'), isTrue);
      expect(isAllowedLanAddress('172.31.8.2'), isTrue);
      expect(isAllowedLanAddress('shellyplugsg3.local'), isTrue);
      expect(isAllowedLanAddress('8.8.8.8'), isFalse);
      expect(isAllowedLanAddress('example.com'), isFalse);
    });

    test('mDNS candidate only accepts Plug S generation 3', () {
      expect(
        const DiscoveredShellyDevice(
          id: 'x',
          address: '192.168.1.2',
          model: 'PlugSG3',
          generation: 3,
        ).isPlugSGen3,
        isTrue,
      );
      expect(
        const DiscoveredShellyDevice(
          id: 'x',
          address: '192.168.1.2',
          model: 'PlugS',
          generation: 2,
        ).isPlugSGen3,
        isFalse,
      );
    });
  });

  test(
    'Cloud status request uses v2 shape and parses switch timer/meter',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': {
              'devices_status': {
                'aabbccddeeff': {
                  'switch:0': {
                    'output': true,
                    'timer_remaining': 120,
                    'apower': 612.5,
                    'voltage': 231.2,
                    'current': 2.65,
                    'freq': 50,
                    'aenergy': {'total': 825},
                    'temperature': {'tC': 39.1},
                  },
                },
              },
            },
          }),
          200,
        );
      });
      final status = await ShellyCloudClient(
        client: client,
      ).getStatus(validProfile);
      expect(captured.url.scheme, 'https');
      expect(captured.url.path, '/v2/devices/api/get');
      expect(captured.url.queryParameters['auth_key'], 'secret-key');
      expect(jsonDecode(captured.body), {
        'ids': ['aabbccddeeff'],
        'select': ['status', 'settings'],
      });
      expect(status.relay, isTrue);
      expect(status.timerRemaining, const Duration(seconds: 120));
      expect(status.powerW, 612.5);
      expect(status.energyWh, 825);
      expect(status.transport, ShellyTransport.cloud);
    },
  );

  test('Cloud v2 parses official top-level Device State list', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode([
          {
            'id': 'aabbccddeeff',
            'type': 'relay',
            'code': 'S3PL-00112EU',
            'gen': 'G3',
            'online': 1,
            'status': {
              'switch:0': {
                'id': 0,
                'output': false,
                'apower': 0,
                'voltage': 230.4,
                'current': 0,
                'aenergy': {'total': 12.5},
              },
            },
          },
        ]),
        200,
      ),
    );

    final status = await ShellyCloudClient(
      client: client,
    ).getStatus(validProfile);
    expect(status.relay, isFalse);
    expect(status.voltageV, 230.4);
    expect(status.energyWh, 12.5);
  });

  test('status derives remaining timer from Gen2+ timer fields', () {
    final status = parseShellyStatus(
      {
        'status': {
          'switch:0': {
            'output': true,
            'timer_started_at': 1000,
            'timer_duration': 120,
          },
        },
      },
      ShellyTransport.cloud,
      now: DateTime.fromMillisecondsSinceEpoch(1030 * 1000),
    );
    expect(status.timerRemaining, const Duration(seconds: 90));
  });

  test('status parser accepts Cloud status encoded as JSON text', () {
    final status = parseShellyStatus({
      'devices': [
        {
          'id': 'aabbccddeeff',
          'online': 1,
          'status': jsonEncode({
            'switch:0': {'output': 1, 'apower': 605, 'timer_remaining': 45},
          }),
        },
      ],
    }, ShellyTransport.cloud);
    expect(status.relay, isTrue);
    expect(status.powerW, 605);
    expect(status.timerRemaining, const Duration(seconds: 45));
  });

  test('official offline device returns an actionable error', () {
    expect(
      () => parseShellyStatus({
        'devices': [
          {'id': 'aabbccddeeff', 'online': 0},
        ],
      }, ShellyTransport.cloud),
      throwsA(
        isA<ShellyClientException>().having(
          (error) => error.message,
          'message',
          contains('offline'),
        ),
      ),
    );
  });

  test('Cloud switch command uses on and toggle_after', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      // Cloud Control v2 may acknowledge a successful command with an empty
      // body; HTTP 200 is the documented success signal.
      return http.Response('', 200);
    });
    await ShellyCloudClient(client: client).setSwitch(
      validProfile,
      on: true,
      toggleAfter: const Duration(minutes: 42),
    );
    expect(captured.url.path, '/v2/devices/api/set/switch');
    expect(jsonDecode(captured.body), {
      'id': 'aabbccddeeff',
      'channel': 0,
      'on': true,
      'toggle_after': 2520,
    });
  });

  test('Cloud status accepts UTF-8 BOM before the JSON payload', () async {
    final client = MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(
          '\uFEFF${jsonEncode([
            {
              'id': 'aabbccddeeff',
              'online': 1,
              'status': {
                'switch:0': {'output': false, 'apower': 0},
              },
            },
          ])}',
        ),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final status = await ShellyCloudClient(
      client: client,
    ).getStatus(validProfile);
    expect(status.relay, isFalse);
  });

  test('Cloud maps auth and rate-limit responses to typed errors', () async {
    for (final entry in const [
      (401, SmartChargerErrorCode.cloudAuthInvalid),
      (429, SmartChargerErrorCode.cloudRateLimited),
    ]) {
      final client = MockClient((_) async => http.Response('{}', entry.$1));
      expect(
        () => ShellyCloudClient(client: client).getStatus(validProfile),
        throwsA(
          isA<ShellyClientException>().having(
            (error) => error.code,
            'code',
            entry.$2,
          ),
        ),
      );
    }
  });

  test('Digest SHA-256 creates an auth header without exposing password', () {
    final header = buildDigestAuthorization(
      challenge:
          'Digest realm="shelly", nonce="abc", algorithm=SHA-256, qop="auth"',
      method: 'POST',
      uri: '/rpc',
      username: 'admin',
      password: 'private-password',
      cnonce: '1234',
    );
    expect(header, startsWith('Digest username="admin"'));
    expect(header, contains('algorithm=SHA-256'));
    expect(header, contains('qop=auth'));
    expect(header, isNot(contains('private-password')));
  });

  group('power calibration', () {
    test('requires at least six positive samples', () {
      expect(
        SmartChargerService.calibratedRemainingMinutes(
          remainingBatteryWh: 1000,
          powerSamplesW: const [600, 601, 599, 602, 598],
        ),
        0,
      );
    });

    test('uses median power and 90 percent efficiency', () {
      expect(
        SmartChargerService.calibratedRemainingMinutes(
          remainingBatteryWh: 900,
          powerSamplesW: const [590, 600, 600, 600, 610, 4000],
        ),
        100,
      );
    });
  });

  test(
    'arm falls back to LAN and only becomes active after timer readback',
    () async {
      SharedPreferences.setMockInitialValues({});
      final cloud = _FakeCloud(fail: true);
      final lan = _FakeLan();
      final service = SmartChargerService(
        credentials: _FakeCredentials(validProfile),
        cloudClient: cloud,
        lanClient: lan,
        delay: (_) async {},
      );
      final session = await service.armSmartCharge(
        const SmartChargePlan(
          vehicleId: 'VF-001',
          currentSoc: 20,
          targetSoc: 80,
          duration: Duration(minutes: 90),
          estimatedCapacityWh: 2400,
          predictionSource: 'ai',
        ),
      );
      expect(lan.lastOn, isTrue);
      expect(lan.lastTimer, const Duration(minutes: 90));
      expect(session.state.name, 'active');
      expect(session.transport, 'lan');
      expect(session.relayVerified, isTrue);
    },
  );

  test('unverified readback sends OFF and returns timerNotArmed', () async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 1, 1, 12);
    final cloud = _FakeCloud(statusFails: true);
    final lan = _FakeLan(statusFails: true);
    final service = SmartChargerService(
      credentials: _FakeCredentials(validProfile),
      cloudClient: cloud,
      lanClient: lan,
      clock: () => now,
      delay: (duration) async => now = now.add(duration),
    );
    await expectLater(
      service.armSmartCharge(
        const SmartChargePlan(
          vehicleId: 'VF-001',
          currentSoc: 20,
          targetSoc: 80,
          duration: Duration(minutes: 30),
          estimatedCapacityWh: 2400,
          predictionSource: 'ai',
        ),
      ),
      throwsA(
        isA<SmartChargerException>().having(
          (error) => error.code,
          'code',
          'timerNotArmed',
        ),
      ),
    );
    expect(cloud.offCount, greaterThan(0));
    expect(lan.lastOn, isFalse);
  });

  test(
    'direct arm is idempotent and rejects a competing active session',
    () async {
      SharedPreferences.setMockInitialValues({});
      final cloud = _FakeCloud();
      final service = SmartChargerService(
        credentials: _FakeCredentials(validProfile),
        cloudClient: cloud,
        delay: (_) async {},
      );
      const plan = SmartChargePlan(
        vehicleId: 'VF-001',
        currentSoc: 20,
        targetSoc: 80,
        duration: Duration(minutes: 30),
        estimatedCapacityWh: 2400,
        predictionSource: 'ai_model',
      );
      final first = await service.armSmartCharge(
        plan,
        idempotencyKey: 'same-command',
      );
      final duplicate = await service.armSmartCharge(
        plan,
        idempotencyKey: 'same-command',
      );
      expect(duplicate.sessionId, first.sessionId);
      expect(cloud.onCount, 1);
      await expectLater(
        service.armSmartCharge(plan, idempotencyKey: 'different-command'),
        throwsA(
          isA<SmartChargerException>().having(
            (error) => error.code,
            'code',
            'activeSessionConflict',
          ),
        ),
      );
    },
  );
}

class _FakeCredentials extends SmartChargerCredentialsService {
  _FakeCredentials(this.profile);
  final ShellyConnectionProfile profile;
  @override
  Future<ShellyConnectionProfile?> readProfile() async => profile;
}

class _FakeCloud extends ShellyCloudClient {
  _FakeCloud({this.fail = false, this.statusFails = false});
  final bool fail;
  final bool statusFails;
  int offCount = 0;
  int onCount = 0;

  @override
  Future<void> setSwitch(
    ShellyConnectionProfile profile, {
    required bool on,
    Duration? toggleAfter,
  }) async {
    if (on) onCount++;
    if (!on) offCount++;
    if (fail && on) {
      throw const ShellyClientException(
        SmartChargerErrorCode.deviceOffline,
        'cloud offline',
        retryable: true,
      );
    }
  }

  @override
  Future<SmartChargerStatus> getStatus(ShellyConnectionProfile profile) async {
    if (fail || statusFails) {
      throw const ShellyClientException(
        SmartChargerErrorCode.deviceOffline,
        'cloud offline',
        retryable: true,
      );
    }
    return _status(ShellyTransport.cloud);
  }
}

class _FakeLan extends ShellyLanClient {
  _FakeLan({this.statusFails = false});
  final bool statusFails;
  bool? lastOn;
  Duration? lastTimer;

  @override
  Future<void> setSwitch(
    ShellyConnectionProfile profile, {
    required bool on,
    Duration? toggleAfter,
  }) async {
    lastOn = on;
    lastTimer = toggleAfter;
  }

  @override
  Future<SmartChargerStatus> getStatus(ShellyConnectionProfile profile) async {
    if (statusFails) {
      throw const ShellyClientException(
        SmartChargerErrorCode.lanUnavailable,
        'lan offline',
        retryable: true,
      );
    }
    return _status(ShellyTransport.lan);
  }
}

SmartChargerStatus _status(ShellyTransport transport) => SmartChargerStatus(
  online: true,
  relay: true,
  powerW: 600,
  voltageV: 230,
  currentA: 2.6,
  frequencyHz: 50,
  temperatureC: 38,
  energyWh: 1000,
  timerRemaining: const Duration(minutes: 90),
  transport: transport,
);
