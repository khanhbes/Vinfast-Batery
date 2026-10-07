import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinfast_battery/core/constants/app_constants.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/models/shelly_connection_state.dart';
import 'package:vinfast_battery/data/repositories/smart_charger_repository.dart';
import 'package:vinfast_battery/data/services/account_reminder_service.dart';
import 'package:vinfast_battery/data/services/server_smart_charger_service.dart';
import 'package:vinfast_battery/data/services/shelly_connection_coordinator.dart';
import 'package:vinfast_battery/features/ai/services/app_chat_tool_gateway.dart';
import 'package:vinfast_battery/features/ai/services/local_chat_engine.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'qa-a';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'qa-token';
}

class _Auth extends Fake implements FirebaseAuth {
  final user = _User();
  @override
  User? get currentUser => user;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String? uid;
  late String device;
  late bool relay, allowOn, timeoutOn, wrongReadback;
  late int onRequests, offRequests;
  late Map<String, dynamic>? session;
  late ServerSmartChargerService service;
  late ShellyConnectionCoordinator connections;
  late BatteryBotLocalEngine engine;
  late AccountReminderService reminders;
  late List<http.Request> requests;
  Map<String, dynamic> status() => {
    'online': true,
    'relay': relay,
    'device_id': wrongReadback ? 'wrong-plug' : device,
    'power_w': relay ? 2 : 0,
    'voltage_v': 230,
    'current_a': 0,
    'energy_wh': 2,
    'temperature_c': 30,
    'shelly_temperature_c': 31,
    'battery_temperature_c': 25,
    'timer_remaining': relay ? 300 : 0,
    'codeRefreshRequired': true,
  };
  Map<String, dynamic> binding() => {
    'deviceId': device,
    'displayName': 'Bộ sạc QA',
    'model': 'S3PL-00112EU',
    'connectionMode': 'server_cloud',
    'powerMeterVerified': true,
    'safeBootVerified': true,
    'noLoadTestVerified': true,
  };
  Map<String, dynamic> activeSession() => {
    'session_id': 'qa-session',
    'vehicle_id': 'qa-vehicle',
    'device_id': device,
    'version': 1,
    'state': 'active',
    'strategy': 'manual_timed',
    'relay_verified': true,
    'timer_verified': true,
    for (final key in [
      'created_at',
      'updated_at',
      'ai_stop_at',
      'hard_deadline_at',
      'effective_stop_at',
      'absolute_safety_stop_at',
    ])
      key: '2026-10-07T10:00:00Z',
  };
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AppConstants.setCustomApiBaseUrl('https://qa.example.org');
    uid = 'qa-a';
    device = 'qa-plug';
    relay = false;
    allowOn = true;
    timeoutOn = false;
    wrongReadback = false;
    onRequests = 0;
    offRequests = 0;
    session = null;
    requests = [];
    service = ServerSmartChargerService(
      auth: _Auth(),
      client: MockClient((request) async {
        requests.add(request);
        expect(request.headers['Authorization'], 'Bearer qa-token');
        dynamic data;
        switch (request.url.path) {
          case '/api/shelly/device':
            data = binding();
          case '/api/shelly/capabilities':
            data = {
              'canReadStatus': true,
              'canManualOn': allowOn,
              'canManualOff': true,
              'supportsDeviceTimer': true,
              'canReadPower': true,
              'safeBootVerified': true,
              'noLoadTestVerified': true,
              'readyForControl': allowOn,
              if (!allowOn) 'controlBlockedCode': 'STAGING_HARDWARE_DISABLED',
            };
          case '/api/smart-charging/status':
            data = status();
          case '/api/smart-charging/live':
            data = {'status': status(), 'session': session};
          case '/api/shelly/redeem-code':
            data = {'profile': binding()};
          case '/api/smart-charging/on':
            onRequests++;
            expect(jsonDecode(request.body)['expectedDeviceId'], device);
            expect(request.headers['Idempotency-Key'], isNotEmpty);
            if (timeoutOn) throw TimeoutException('simulated lost ON response');
            relay = true;
            session = activeSession();
            data = session;
          case '/api/smart-charging/off':
            offRequests++;
            expect(jsonDecode(request.body)['expectedDeviceId'], device);
            expect(request.headers['Idempotency-Key'], isNotEmpty);
            relay = false;
            session = null;
            data = null;
          case '/api/smart-charging/session/qa-session/stop':
            offRequests++;
            relay = false;
            data = {...session!, 'state': 'cancelled', 'relay_verified': true};
            session = null;
          default:
            throw StateError('Unexpected QA endpoint ${request.url.path}');
        }
        if (request.url.path != '/api/smart-charging/session/qa-session/stop') {
          expect(
            request.url.queryParameters['vehicleId'] ??
                (request.body.isEmpty
                    ? null
                    : jsonDecode(request.body)['vehicleId']),
            'qa-vehicle',
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'data': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    connections = ShellyConnectionCoordinator(serverCharger: service)
      ..activateAccount(uid);
    reminders = AccountReminderService(uidResolver: () => uid);
    engine = BatteryBotLocalEngine(
      tools: AppChatToolGateway(
        uidResolver: () => uid,
        selectedVehicle: () => VehicleModel(
          vehicleId: 'qa-vehicle',
          ownerUid: uid,
          vehicleName: 'Feliz QA',
          currentOdo: 0,
          currentBattery: 20,
          hasBatteryData: true,
        ),
        reminders: reminders,
        serverRepository: ServerSmartChargerRepository(service),
        connectionCoordinator: connections,
      ),
    );
  });
  tearDown(() async {
    engine.dispose();
    reminders.dispose();
    service.close();
    await connections.dispose();
    AppConstants.setCustomApiBaseUrl(null);
  });

  test(
    'scoped status preserves identity, code notice and both temperatures',
    () async {
      final readback = await service.getStatus(vehicleId: 'qa-vehicle');
      expect(readback.deviceId, device);
      expect(readback.codeRefreshRequired, true);
      expect(readback.shellyTemperatureC, 31);
      expect(readback.batteryTemperatureC, 25);
      expect(readback.deviceName, 'Bộ sạc QA');
    },
  );
  test(
    'redeem sends selected vehicle and stable operation without exposing secrets',
    () async {
      final profile = await service.redeemConnectionCode(
        'abc123',
        vehicleId: 'qa-vehicle',
        operationId: 'qa-op',
      );
      final body = jsonDecode(requests.single.body);
      expect(body['code'], 'ABC123');
      expect(body['operationId'], 'qa-op');
      expect(profile.deviceName, 'Bộ sạc QA');
      expect(profile.cloudAuthKey, isEmpty);
    },
  );
  test(
    'real engine and HTTP adapter send ON only after confirmation, double-tap sends once',
    () async {
      final proposal = await engine.reply('bật sạc 5 phút');
      expect(proposal.action, isNotNull);
      expect(onRequests, 0);
      expect(proposal.action!.args, isEmpty);
      final results = await Future.wait([
        engine.confirm(proposal.action!.callId, true),
        engine.confirm(proposal.action!.callId, true),
      ]);
      expect(results.any((result) => result['success'] == true), true);
      expect(onRequests, 1);
      expect(connections.current.status!.relay, true);
      expect(connections.current.state, ShellyConnectionFlowState.connected);
      final stop = await engine.reply('dừng sạc');
      expect(stop.action, isNotNull);
      expect(offRequests, 0);
      expect(
        (await engine.confirm(stop.action!.callId, true))['success'],
        true,
      );
      expect(offRequests, 1);
      expect(connections.current.status!.relay, false);
    },
  );
  test('staging policy produces explanation and zero ON requests', () async {
    allowOn = false;
    final reply = await engine.reply('bật sạc 5 phút');
    expect(reply.action, isNull);
    expect(reply.text, contains('thử nghiệm'));
    expect(onRequests, 0);
    expect(connections.current.readyForControl, false);
  });
  test(
    'lost ON response keeps unknown and confirming again never retries ON',
    () async {
      timeoutOn = true;
      final proposal = await engine.reply('bật sạc 5 phút');
      expect(
        (await engine.confirm(proposal.action!.callId, true))['status'],
        'unknown',
      );
      await engine.confirm(proposal.action!.callId, true);
      expect(onRequests, 1);
      expect(connections.current.controlUncertain, true);
      expect(connections.current.readyForControl, false);
      expect(connections.current.status, isNull);
      expect(connections.current.connectionLabel, contains('Chưa xác minh'));
      // A fresh OFF readback may resolve presentation; never replay the ON.
      await engine.reply('trạng thái Shelly');
      expect(connections.current.controlUncertain, false);
      expect(connections.current.status!.relay, false);
      expect(onRequests, 1);
    },
  );
  test(
    'shared device without private session supports confirmed backend OFF with readback',
    () async {
      relay = true;
      final proposal = await engine.reply('tắt Shelly');
      expect(proposal.action, isNotNull);
      expect(offRequests, 0);
      expect(
        (await engine.confirm(proposal.action!.callId, true))['success'],
        true,
      );
      expect(offRequests, 1);
      expect(connections.current.status!.relay, false);
      expect(onRequests, 0);
    },
  );
  test(
    'changed binding expires confirmation without commanding different hardware',
    () async {
      final proposal = await engine.reply('bật sạc 5 phút');
      device = 'different-plug';
      expect(
        (await engine.confirm(proposal.action!.callId, true))['status'],
        'expired',
      );
      expect(onRequests, 0);
    },
  );
  test(
    'UID switch expires proposal and cannot publish previous account status',
    () async {
      final proposal = await engine.reply('bật sạc 5 phút');
      uid = 'qa-b';
      connections.activateAccount(uid);
      expect(
        (await engine.confirm(proposal.action!.callId, true))['status'],
        'expired',
      );
      expect(connections.current.isLinked, false);
      expect(onRequests, 0);
    },
  );
  test(
    'wrong device readback is never reported as verified connection or control',
    () async {
      wrongReadback = true;
      final reply = await engine.reply('trạng thái Shelly');
      expect(reply.text, contains('đúng Shelly'));
      expect(
        connections.current.state,
        ShellyConnectionFlowState.verificationRequired,
      );
      expect((await engine.reply('bật sạc 5 phút')).action, isNull);
      expect(onRequests, 0);
    },
  );
}
