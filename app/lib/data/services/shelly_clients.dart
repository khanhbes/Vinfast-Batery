import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/shelly_connection.dart';
import '../models/smart_charger_status.dart';

class ShellyClientException implements Exception {
  const ShellyClientException(
    this.code,
    this.message, {
    this.retryable = false,
  });
  final SmartChargerErrorCode code;
  final String message;
  final bool retryable;
  @override
  String toString() => message;
}

class ShellyCloudClient {
  ShellyCloudClient({http.Client? client, DateTime Function()? clock})
    : _client = client ?? http.Client(),
      _clock = clock ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _clock;
  Future<void> _tail = Future.value();
  DateTime? _lastRequestAt;

  Future<T> _limited<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      final previous = _lastRequestAt;
      if (previous != null) {
        final wait = const Duration(seconds: 1) - _clock().difference(previous);
        if (wait.isPositive) await Future<void>.delayed(wait);
      }
      _lastRequestAt = _clock();
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<SmartChargerStatus> getStatus(ShellyConnectionProfile profile) =>
      _limited(() async {
        final json = await _post(profile, '/v2/devices/api/get', {
          'ids': [profile.deviceId],
          'select': ['status', 'settings'],
        });
        return parseShellyStatus(
          json,
          ShellyTransport.cloud,
          deviceName: profile.deviceName,
        );
      });

  Future<void> setSwitch(
    ShellyConnectionProfile profile, {
    required bool on,
    Duration? toggleAfter,
  }) => _limited(() async {
    await _post(profile, '/v2/devices/api/set/switch', {
      'id': profile.deviceId,
      'channel': 0,
      'on': on,
      if (on && toggleAfter != null)
        'toggle_after': max(1, toggleAfter.inSeconds),
    });
  });

  Future<Map<String, dynamic>> _post(
    ShellyConnectionProfile profile,
    String path,
    Map<String, dynamic> body,
  ) async {
    final validation = profile.validate();
    if (validation != null) {
      throw ShellyClientException(
        SmartChargerErrorCode.invalidProfile,
        validation,
      );
    }
    final base = profile.cloudUri!;
    final uri = base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}$path',
      queryParameters: {'auth_key': profile.cloudAuthKey.trim()},
    );
    try {
      final response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ShellyClientException(
          SmartChargerErrorCode.cloudAuthInvalid,
          'Cloud Authorization Key không hợp lệ hoặc đã bị thu hồi.',
        );
      }
      if (response.statusCode == 429) {
        throw const ShellyClientException(
          SmartChargerErrorCode.cloudRateLimited,
          'Shelly Cloud đang giới hạn tần suất. Vui lòng thử lại.',
          retryable: true,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ShellyClientException(
          SmartChargerErrorCode.deviceOffline,
          'Shelly Cloud không thể liên lạc với thiết bị.',
          retryable: response.statusCode >= 500,
        );
      }
      final decoded = jsonDecode(response.body);
      final result = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      if (result['isok'] == false || result['error'] != null) {
        throw const ShellyClientException(
          SmartChargerErrorCode.deviceOffline,
          'Shelly Cloud từ chối lệnh điều khiển.',
        );
      }
      return result;
    } on ShellyClientException {
      rethrow;
    } on TimeoutException {
      throw const ShellyClientException(
        SmartChargerErrorCode.deviceOffline,
        'Shelly Cloud không phản hồi.',
        retryable: true,
      );
    } on SocketException catch (_) {
      throw const ShellyClientException(
        SmartChargerErrorCode.deviceOffline,
        'Không có kết nối tới Shelly Cloud.',
        retryable: true,
      );
    } on http.ClientException catch (_) {
      throw const ShellyClientException(
        SmartChargerErrorCode.deviceOffline,
        'Không có kết nối tới Shelly Cloud.',
        retryable: true,
      );
    } on FormatException catch (_) {
      throw const ShellyClientException(
        SmartChargerErrorCode.deviceOffline,
        'Shelly Cloud trả về dữ liệu không hợp lệ.',
      );
    }
  }
}

class ShellyLanClient {
  ShellyLanClient({http.Client? client, Random? random})
    : _client = client ?? http.Client(),
      _random = random ?? Random.secure();

  final http.Client _client;
  final Random _random;

  Future<Map<String, dynamic>> getDeviceInfo(ShellyConnectionProfile profile) =>
      _get(profile, '/shelly');

  Future<SmartChargerStatus> getStatus(ShellyConnectionProfile profile) async {
    final json = await _rpc(profile, 'Switch.GetStatus', {'id': 0});
    return parseShellyStatus(
      json,
      ShellyTransport.lan,
      deviceName: profile.deviceName,
    );
  }

  Future<void> setSwitch(
    ShellyConnectionProfile profile, {
    required bool on,
    Duration? toggleAfter,
  }) async {
    await _rpc(profile, 'Switch.Set', {
      'id': 0,
      'on': on,
      if (on && toggleAfter != null)
        'toggle_after': max(1, toggleAfter.inSeconds),
    });
  }

  Future<void> configureSafeBoot(ShellyConnectionProfile profile) async {
    await _rpc(profile, 'Switch.SetConfig', {
      'id': 0,
      'config': {'initial_state': 'off', 'auto_on': false},
    });
  }

  Future<Map<String, dynamic>> _rpc(
    ShellyConnectionProfile profile,
    String method,
    Map<String, dynamic> params,
  ) => _request(profile, 'POST', '/rpc', {
    'id': DateTime.now().microsecondsSinceEpoch,
    'method': method,
    'params': params,
  });

  Future<Map<String, dynamic>> _get(
    ShellyConnectionProfile profile,
    String path,
  ) => _request(profile, 'GET', path, null);

  Future<Map<String, dynamic>> _request(
    ShellyConnectionProfile profile,
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final address = profile.lanAddress;
    if (address == null || !isAllowedLanAddress(address)) {
      throw const ShellyClientException(
        SmartChargerErrorCode.lanUnavailable,
        'Địa chỉ LAN Shelly không hợp lệ hoặc chưa cấu hình.',
      );
    }
    final base = Uri.parse(
      address.contains('://') ? address : 'http://$address',
    );
    if (base.scheme != 'http') {
      throw const ShellyClientException(
        SmartChargerErrorCode.lanUnavailable,
        'Kết nối LAN Shelly phải dùng HTTP nội bộ.',
      );
    }
    final uri = base.replace(path: path);
    final encoded = body == null ? null : jsonEncode(body);
    try {
      var response = await _send(method, uri, encoded, const {});
      if (response.statusCode == 401 &&
          profile.localPassword?.isNotEmpty == true) {
        final challenge = response.headers['www-authenticate'];
        if (challenge != null) {
          final authorization = buildDigestAuthorization(
            challenge: challenge,
            method: method,
            uri: uri.path,
            username: profile.localUsername,
            password: profile.localPassword!,
            cnonce: _random.nextInt(0x7fffffff).toRadixString(16),
          );
          response = await _send(method, uri, encoded, {
            'Authorization': authorization,
          });
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ShellyClientException(
          SmartChargerErrorCode.lanUnavailable,
          response.statusCode == 401
              ? 'Mật khẩu local Shelly không đúng hoặc còn thiếu.'
              : 'Shelly LAN không phản hồi lệnh.',
          retryable: response.statusCode >= 500,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      final result = Map<String, dynamic>.from(decoded);
      if (result['error'] != null) {
        throw const ShellyClientException(
          SmartChargerErrorCode.lanUnavailable,
          'Shelly từ chối lệnh LAN.',
        );
      }
      return result['result'] is Map
          ? Map<String, dynamic>.from(result['result'] as Map)
          : result;
    } on ShellyClientException {
      rethrow;
    } on TimeoutException {
      throw const ShellyClientException(
        SmartChargerErrorCode.lanUnavailable,
        'Shelly không phản hồi trong mạng LAN.',
        retryable: true,
      );
    } on SocketException catch (_) {
      throw const ShellyClientException(
        SmartChargerErrorCode.lanUnavailable,
        'Không tìm thấy Shelly trong mạng LAN.',
        retryable: true,
      );
    } on http.ClientException catch (_) {
      throw const ShellyClientException(
        SmartChargerErrorCode.lanUnavailable,
        'Không tìm thấy Shelly trong mạng LAN.',
        retryable: true,
      );
    } on FormatException catch (_) {
      throw const ShellyClientException(
        SmartChargerErrorCode.lanUnavailable,
        'Shelly LAN trả về dữ liệu không hợp lệ.',
      );
    }
  }

  Future<http.Response> _send(
    String method,
    Uri uri,
    String? body,
    Map<String, String> extraHeaders,
  ) {
    final headers = {'Content-Type': 'application/json', ...extraHeaders};
    final call = method == 'GET'
        ? _client.get(uri, headers: headers)
        : _client.post(uri, headers: headers, body: body);
    return call.timeout(const Duration(seconds: 3));
  }
}

String buildDigestAuthorization({
  required String challenge,
  required String method,
  required String uri,
  required String username,
  required String password,
  required String cnonce,
  String nonceCount = '00000001',
}) {
  final values = <String, String>{};
  final payload = challenge.replaceFirst(
    RegExp(r'^Digest\s+', caseSensitive: false),
    '',
  );
  for (final match in RegExp(
    r'(\w+)=(?:"([^"]*)"|([^,\s]+))',
  ).allMatches(payload)) {
    values[match.group(1)!.toLowerCase()] = match.group(2) ?? match.group(3)!;
  }
  final realm = values['realm'] ?? '';
  final nonce = values['nonce'] ?? '';
  final opaque = values['opaque'];
  final algorithm = (values['algorithm'] ?? 'SHA-256').toUpperCase();
  if (algorithm != 'SHA-256' || realm.isEmpty || nonce.isEmpty) {
    throw const ShellyClientException(
      SmartChargerErrorCode.lanUnavailable,
      'Shelly yêu cầu cơ chế xác thực local không được hỗ trợ.',
    );
  }
  String hash(String value) => sha256.convert(utf8.encode(value)).toString();
  final ha1 = hash('$username:$realm:$password');
  final ha2 = hash('$method:$uri');
  final response = hash('$ha1:$nonce:$nonceCount:$cnonce:auth:$ha2');
  return 'Digest username="$username", realm="$realm", nonce="$nonce", '
      'uri="$uri", algorithm=SHA-256, response="$response", qop=auth, '
      'nc=$nonceCount, cnonce="$cnonce"'
      '${opaque == null ? '' : ', opaque="$opaque"'}';
}

SmartChargerStatus parseShellyStatus(
  Map<String, dynamic> json,
  ShellyTransport transport, {
  String? deviceName,
}) {
  Map<String, dynamic>? findSwitch(Object? value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final direct = map['switch:0'];
      if (direct is Map) return Map<String, dynamic>.from(direct);
      if (map.containsKey('output') &&
          (map.containsKey('apower') || map.containsKey('timer_remaining'))) {
        return map;
      }
      for (final child in map.values) {
        final found = findSwitch(child);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final child in value) {
        final found = findSwitch(child);
        if (found != null) return found;
      }
    }
    return null;
  }

  double number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  final data = findSwitch(json);
  if (data == null || data['output'] is! bool) {
    throw const ShellyClientException(
      SmartChargerErrorCode.deviceOffline,
      'Không đọc được trạng thái switch:0 của Shelly.',
    );
  }
  final energy = data['aenergy'];
  final totalEnergy = energy is Map ? energy['total'] : data['energy_wh'];
  final temperature = data['temperature'];
  final timerValue = data['timer_remaining'];
  return SmartChargerStatus(
    online: true,
    relay: data['output'] as bool,
    powerW: number(data['apower'] ?? data['power_w']),
    voltageV: number(data['voltage'] ?? data['voltage_v']),
    currentA: number(data['current'] ?? data['current_a']),
    frequencyHz: number(data['freq'] ?? data['frequency_hz']),
    temperatureC: temperature is Map
        ? number(temperature['tC'])
        : temperature == null
        ? null
        : number(temperature),
    energyWh: number(totalEnergy),
    timerRemaining: timerValue == null
        ? null
        : Duration(seconds: max(0, number(timerValue).round())),
    transport: transport,
    deviceName: deviceName,
  );
}

extension on Duration {
  bool get isPositive => inMicroseconds > 0;
}
