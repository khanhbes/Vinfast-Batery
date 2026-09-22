import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/shelly_connection.dart';
import '../models/shelly_snapshot.dart';
import '../models/smart_charger_status.dart';

class ShellyClientException implements Exception {
  const ShellyClientException(
    this.code,
    this.message, {
    this.retryable = false,
    this.statusCode,
    this.providerCode,
    this.retryAfter,
    this.commandMayHaveReachedDevice = false,
  });
  final SmartChargerErrorCode code;
  final String message;
  final bool retryable;
  final int? statusCode;
  final String? providerCode;
  final Duration? retryAfter;
  final bool commandMayHaveReachedDevice;
  @override
  String toString() => message;
}

class ShellyCloudCommandResult {
  const ShellyCloudCommandResult({
    required this.operationId,
    required this.httpStatus,
    required this.acceptedAt,
    this.providerCode,
    this.ambiguous = false,
  });

  final String operationId;
  final int httpStatus;
  final DateTime acceptedAt;
  final String? providerCode;
  final bool ambiguous;

  bool get accepted => httpStatus == 200 && !ambiguous;
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
        // Keep a safety margin below Shelly Cloud's one-request-per-second
        // limit; this also covers small clock/network scheduling jitter.
        final wait =
            const Duration(milliseconds: 1100) - _clock().difference(previous);
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

  Future<ShellyDeviceSnapshot> getSnapshot(ShellyConnectionProfile profile) =>
      _limited(() async {
        final json = await _post(profile, '/v2/devices/api/get', {
          'ids': [profile.deviceId],
          'select': ['status', 'settings'],
        });
        return parseShellySnapshot(json, profile);
      });

  Future<SmartChargerStatus> getStatus(ShellyConnectionProfile profile) async =>
      (await getSnapshot(profile)).status;

  Future<ShellyCloudCommandResult> setSwitch(
    ShellyConnectionProfile profile, {
    required bool on,
    Duration? toggleAfter,
    String? operationId,
  }) => _limited(() async {
    final id =
        operationId ??
        '${_clock().toUtc().microsecondsSinceEpoch}-${on ? 'on' : 'off'}';
    await _post(profile, '/v2/devices/api/set/switch', {
      'id': profile.deviceId,
      'channel': 0,
      'on': on,
      if (on && toggleAfter != null)
        'toggle_after': max(1, toggleAfter.inSeconds),
    }, decodeResponse: false);
    return ShellyCloudCommandResult(
      operationId: id,
      httpStatus: 200,
      acceptedAt: _clock(),
    );
  });

  Future<Map<String, dynamic>> _post(
    ShellyConnectionProfile profile,
    String path,
    Map<String, dynamic> body, {
    bool decodeResponse = true,
  }) async {
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
      final isCommand = path.contains('/set/');
      Map<String, dynamic>? errorBody;
      final rawBody = response.body.trim();
      if (rawBody.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawBody);
          if (decoded is Map) errorBody = Map<String, dynamic>.from(decoded);
        } on FormatException {
          // The status code remains authoritative; never expose raw text.
        }
      }
      final providerCode = errorBody?['error']?.toString();
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw ShellyClientException(
          SmartChargerErrorCode.cloudAuthInvalid,
          'Cloud Authorization Key không hợp lệ hoặc đã bị thu hồi.',
          statusCode: response.statusCode,
          providerCode: providerCode,
          commandMayHaveReachedDevice: isCommand,
        );
      }
      if (response.statusCode == 429) {
        final retryAfterSeconds = int.tryParse(
          response.headers['retry-after'] ?? '',
        );
        throw ShellyClientException(
          SmartChargerErrorCode.cloudRateLimited,
          'Shelly Cloud đang giới hạn tần suất. Vui lòng thử lại.',
          retryable: true,
          statusCode: response.statusCode,
          providerCode: providerCode,
          retryAfter: retryAfterSeconds == null
              ? null
              : Duration(seconds: retryAfterSeconds),
          commandMayHaveReachedDevice: isCommand && !onSafeReadPath(path),
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final mappedCode = switch (providerCode) {
          'BAD_REQUEST' ||
          'DEVICE_INVALID_CHANNEL' => SmartChargerErrorCode.cloudBadRequest,
          'DEVICE_FAILED_COMMAND' => SmartChargerErrorCode.cloudCommandRejected,
          'DEVICE_NOT_FOUND' ||
          'INSTANCE_NOT_FOUND' => SmartChargerErrorCode.cloudDeviceNotFound,
          'DEVICE_OFFLINE' => SmartChargerErrorCode.deviceOffline,
          _ =>
            response.statusCode >= 500
                ? SmartChargerErrorCode.cloudCommandRejected
                : SmartChargerErrorCode.deviceOffline,
        };
        throw ShellyClientException(
          mappedCode,
          'Shelly Cloud không thể liên lạc với thiết bị.',
          retryable: response.statusCode >= 500,
          statusCode: response.statusCode,
          providerCode: providerCode,
          commandMayHaveReachedDevice: isCommand && response.statusCode >= 500,
        );
      }
      // Shelly Cloud v2 documents HTTP 200 itself as the success signal for
      // control commands. A successful set/switch response is therefore
      // allowed to have an empty or non-JSON body.
      var responseBody = response.body;
      if (responseBody.isNotEmpty && responseBody.codeUnitAt(0) == 0xFEFF) {
        responseBody = responseBody.substring(1);
      }
      responseBody = responseBody.trim();
      if (responseBody.isEmpty) return <String, dynamic>{};
      if (isCommand && !decodeResponse) {
        try {
          final commandDecoded = jsonDecode(responseBody);
          if (commandDecoded is Map && commandDecoded['error'] != null) {
            throw ShellyClientException(
              SmartChargerErrorCode.cloudCommandRejected,
              'Shelly Cloud từ chối lệnh điều khiển.',
              statusCode: response.statusCode,
              providerCode: commandDecoded['error']?.toString(),
              commandMayHaveReachedDevice: true,
            );
          }
        } on ShellyClientException {
          rethrow;
        } on FormatException {
          // HTTP 200 is the documented success signal for commands.
        }
        return <String, dynamic>{};
      }
      final decoded = jsonDecode(responseBody);
      // Cloud Control v2 /devices/api/get returns a top-level JSON array of
      // Device State objects. Commands may return an object (or an empty one).
      // Keep both shapes so the recursive status parser can reach
      // devices[n].status['switch:0'].
      final result = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : decoded is List
          ? <String, dynamic>{'devices': decoded}
          : <String, dynamic>{};
      if (result['isok'] == false || result['error'] != null) {
        throw ShellyClientException(
          SmartChargerErrorCode.cloudCommandRejected,
          'Shelly Cloud từ chối lệnh điều khiển.',
          statusCode: response.statusCode,
          providerCode: result['error']?.toString(),
          commandMayHaveReachedDevice: isCommand,
        );
      }
      return result;
    } on ShellyClientException {
      rethrow;
    } on TimeoutException {
      throw ShellyClientException(
        SmartChargerErrorCode.deviceOffline,
        'Shelly Cloud không phản hồi.',
        retryable: true,
        commandMayHaveReachedDevice: path.contains('/set/'),
      );
    } on SocketException catch (_) {
      throw ShellyClientException(
        SmartChargerErrorCode.deviceOffline,
        'Không có kết nối tới Shelly Cloud.',
        retryable: true,
        commandMayHaveReachedDevice: path.contains('/set/'),
      );
    } on http.ClientException catch (_) {
      throw ShellyClientException(
        SmartChargerErrorCode.deviceOffline,
        'Không có kết nối tới Shelly Cloud.',
        retryable: true,
        commandMayHaveReachedDevice: path.contains('/set/'),
      );
    } on FormatException catch (_) {
      throw ShellyClientException(
        SmartChargerErrorCode.cloudResponseMalformed,
        'Shelly Cloud trả về dữ liệu không hợp lệ.',
        commandMayHaveReachedDevice: path.contains('/set/'),
      );
    }
  }

  bool onSafeReadPath(String path) => path.endsWith('/get');
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

  Future<Map<String, dynamic>> getSwitchConfig(
    ShellyConnectionProfile profile,
  ) => _rpc(profile, 'Switch.GetConfig', {'id': 0});

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

ShellyDeviceSnapshot parseShellySnapshot(
  Map<String, dynamic> json,
  ShellyConnectionProfile profile,
) {
  Map<String, dynamic>? findDevice(Object? value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final id = map['id']?.toString().toLowerCase();
      if (id == profile.deviceId.toLowerCase() &&
          (map.containsKey('status') || map.containsKey('settings'))) {
        return map;
      }
      for (final child in map.values) {
        final found = findDevice(child);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final child in value) {
        final found = findDevice(child);
        if (found != null) return found;
      }
    } else if (value is String &&
        (value.trimLeft().startsWith('{') ||
            value.trimLeft().startsWith('['))) {
      try {
        return findDevice(jsonDecode(value));
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  Map<String, dynamic>? findSwitch(Object? value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final direct = map['switch:0'];
      if (direct is Map) return Map<String, dynamic>.from(direct);
      if (direct is String) {
        try {
          final found = findSwitch(jsonDecode(direct));
          if (found != null) return found;
        } on FormatException {
          return null;
        }
      }
      if (map.containsKey('output')) return map;
      for (final child in map.values) {
        final found = findSwitch(child);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final child in value) {
        final found = findSwitch(child);
        if (found != null) return found;
      }
    } else if (value is String &&
        (value.trimLeft().startsWith('{') ||
            value.trimLeft().startsWith('['))) {
      try {
        return findSwitch(jsonDecode(value));
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  var device = findDevice(json);
  // A few Cloud regions wrap a targeted response in `data` or omit the id
  // because the request already contained a single id. Preserve the targeted
  // identity in that case; never apply this fallback to an arbitrary list.
  if (device == null) {
    final candidate = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json['devices'] is List && (json['devices'] as List).length == 1
        ? (json['devices'] as List).first is Map
              ? Map<String, dynamic>.from(
                  (json['devices'] as List).first as Map,
                )
              : null
        : null;
    if (candidate != null &&
        (candidate.containsKey('status') ||
            candidate.containsKey('settings'))) {
      candidate['id'] = profile.deviceId;
      device = candidate;
    }
  }
  if (device == null) {
    throw const ShellyClientException(
      SmartChargerErrorCode.deviceOffline,
      'Không tìm thấy đúng thiết bị Shelly trong phản hồi Cloud.',
      retryable: true,
    );
  }
  final status = parseShellyStatus(
    {'status': device['status']},
    ShellyTransport.cloud,
    deviceName: profile.deviceName,
  );
  final statusSwitch = findSwitch(device['status']);
  final settingsSwitch = findSwitch(device['settings']);
  final energy = statusSwitch?['aenergy'];
  final powerMeterFieldsPresent =
      statusSwitch != null &&
      statusSwitch.containsKey('apower') &&
      (statusSwitch.containsKey('voltage') ||
          statusSwitch.containsKey('voltage_v')) &&
      (statusSwitch.containsKey('current') ||
          statusSwitch.containsKey('current_a')) &&
      ((energy is Map && energy.containsKey('total')) ||
          statusSwitch.containsKey('energy_wh'));
  final generationRaw = device['gen']?.toString().toUpperCase();
  final generation = int.tryParse(
    generationRaw?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
  );
  final onlineValue = device['online'];
  final online =
      onlineValue == 1 ||
      onlineValue == true ||
      const {
        'true',
        '1',
        'online',
      }.contains(onlineValue?.toString().toLowerCase());
  return ShellyDeviceSnapshot(
    deviceId: device['id']?.toString() ?? profile.deviceId,
    model: (device['code'] ?? device['model'] ?? '').toString(),
    generation: generation,
    online: online,
    status: status,
    powerMeterFieldsPresent: powerMeterFieldsPresent,
    switchConfig: ShellySwitchConfig.fromJson(settingsSwitch),
  );
}

SmartChargerStatus parseShellyStatus(
  Map<String, dynamic> json,
  ShellyTransport transport, {
  String? deviceName,
  DateTime? now,
}) {
  Map<String, dynamic>? findSwitch(Object? value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      // Prefer status branches. Cloud responses also contain settings and the
      // settings switch has no live `output`; walking it first can otherwise
      // make a valid live status look malformed.
      for (final key in const ['status', 'devices_status']) {
        if (map.containsKey(key)) {
          final found = findSwitch(map[key]);
          if (found != null) return found;
        }
      }
      final direct = map['switch:0'];
      if (direct is Map) return Map<String, dynamic>.from(direct);
      if (direct is String) {
        try {
          final found = findSwitch(jsonDecode(direct));
          if (found != null) return found;
        } on FormatException {
          // Continue searching other fields in a partially encoded response.
        }
      }
      if (map.containsKey('output')) {
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
    } else if (value is String &&
        (value.trimLeft().startsWith('{') ||
            value.trimLeft().startsWith('['))) {
      try {
        return findSwitch(jsonDecode(value));
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  double number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  bool explicitlyOffline(Object? value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map.containsKey('id') &&
          (map['online'] == 0 || map['online'] == false)) {
        return true;
      }
      return map.values.any(explicitlyOffline);
    }
    return value is List && value.any(explicitlyOffline);
  }

  final data = findSwitch(json);
  final output = switch (data?['output']) {
    true || 1 || 'true' || 'on' => true,
    false || 0 || 'false' || 'off' => false,
    _ => null,
  };
  if (data == null || output == null) {
    if (explicitlyOffline(json)) {
      throw const ShellyClientException(
        SmartChargerErrorCode.deviceOffline,
        'Shelly đang offline trên Cloud. Kiểm tra nguồn và Wi-Fi của ổ cắm.',
        retryable: true,
      );
    }
    throw const ShellyClientException(
      SmartChargerErrorCode.deviceOffline,
      'Không đọc được trạng thái switch:0 của Shelly.',
    );
  }
  final energy = data['aenergy'];
  final totalEnergy = energy is Map ? energy['total'] : data['energy_wh'];
  final temperature = data['temperature'];
  Object? timerValue = data['timer_remaining'];
  if (timerValue == null &&
      data['timer_started_at'] != null &&
      data['timer_duration'] != null) {
    final reference = now ?? DateTime.now();
    final elapsed =
        reference.millisecondsSinceEpoch / 1000 -
        number(data['timer_started_at']);
    timerValue = max(0, number(data['timer_duration']) - elapsed);
  }
  return SmartChargerStatus(
    online: true,
    relay: output,
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
