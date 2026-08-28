import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/shelly_connection.dart';

class SmartChargerCredentialsService {
  SmartChargerCredentialsService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const _profileKey = 'smart_charger.shelly_profile.v1';
  static const _legacyTokenKey = 'smart_charger.api_token';
  final FlutterSecureStorage _storage;

  Future<ShellyConnectionProfile?> readProfile() async {
    try {
      final raw = await _storage.read(key: _profileKey);
      if (raw == null || raw.isEmpty) return null;
      return ShellyConnectionProfile.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (error) {
      debugPrint('[SmartChargerCredentials] read failed: $error');
      return null;
    }
  }

  Future<void> saveProfile(ShellyConnectionProfile profile) async {
    final validation = profile.validate();
    if (validation != null) throw ArgumentError(validation);
    await _storage.write(key: _profileKey, value: jsonEncode(profile.toJson()));
  }

  Future<void> clearProfile() async {
    await _storage.delete(key: _profileKey);
    await _storage.delete(key: _legacyTokenKey);
  }

  @Deprecated(
    'Gateway token is no longer used. Read the Shelly profile instead.',
  )
  Future<String?> readToken() async => null;

  @Deprecated('Save a ShellyConnectionProfile instead.')
  Future<void> saveToken(String token) async {
    throw UnsupportedError('Gateway API token is no longer supported.');
  }

  @Deprecated('Clear the Shelly profile instead.')
  Future<void> clearToken() => clearProfile();
}
