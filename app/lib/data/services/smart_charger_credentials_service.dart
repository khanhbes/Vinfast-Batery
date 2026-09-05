import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/shelly_connection.dart';
import 'server_smart_charger_service.dart';

class SmartChargerCredentialsService {
  SmartChargerCredentialsService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const _profileKey = 'smart_charger.shelly_profile.v1';
  static const _draftKey = 'smart_charger.shelly_profile_draft.v1';
  static const _verificationKey = 'smart_charger.verification.v1';
  static const _legacyTokenKey = 'smart_charger.api_token';
  final FlutterSecureStorage _storage;
  static DateTime? _lastServerSyncAt;

  Future<ShellyConnectionProfile?> readProfile({String? vehicleId}) async {
    try {
      final raw = await _storage.read(key: _profileKey);
      if (raw != null && raw.isNotEmpty) {
        return ShellyConnectionProfile.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      }
      return await restoreFromCloud(vehicleId: vehicleId);
    } catch (error) {
      debugPrint('[SmartChargerCredentials] read failed: $error');
      return await restoreFromCloud(vehicleId: vehicleId);
    }
  }

  /// Khôi phục cấu hình Shelly đã lưu theo tài khoản khi đổi điện thoại.
  /// Resolve a profile through the authenticated API vault. Firestore is not
  /// queried for secrets: it only stores server-managed metadata.
  Future<ShellyConnectionProfile?> restoreFromCloud({
    String? vehicleId,
    bool force = false,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final last = _lastServerSyncAt;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 5)) {
      return null;
    }
    _lastServerSyncAt = DateTime.now();

    try {
      final server = ServerSmartChargerService();
      final metadata = await server.resolveDirectProfile(vehicleId: vehicleId);
      if (metadata == null) return null;
      final deviceId = metadata['deviceId']?.toString() ?? '';
      if (deviceId.isEmpty) return null;
      final serverProfile = await server.restoreDirectProfile(deviceId);
      if (serverProfile != null) {
        final verified = metadata['cloudVerified'] == true &&
            metadata['powerMeterVerified'] == true &&
            metadata['safeBootVerified'] == true &&
            metadata['noLoadTestVerified'] == true;
        if (verified) {
          await saveProfile(serverProfile);
          await saveVerification(
            SmartChargerVerificationState(
              cloudVerified: metadata['cloudVerified'] == true,
              lanVerified: metadata['lanVerified'] == true,
              powerMeterVerified: metadata['powerMeterVerified'] == true,
              safeBootVerified: metadata['safeBootVerified'] == true,
              noLoadTestVerified: metadata['noLoadTestVerified'] == true,
              lastVerifiedAt: DateTime.tryParse(
                metadata['verifiedAt']?.toString() ?? '',
              ),
            ),
          );
        } else {
          // A remote draft is useful for recovery but must not replace a
          // proven active controller until the Android safety test succeeds.
          await saveDraft(serverProfile);
        }
        debugPrint(
          '[SmartChargerCredentials] Restored encrypted Shelly profile from server API',
        );
        return serverProfile;
      }
    } catch (e) {
      debugPrint('[SmartChargerCredentials] Restore from server error: $e');
    }
    return null;
  }

  Future<void> saveProfile(ShellyConnectionProfile profile) async {
    final validation = profile.validate();
    if (validation != null) throw ArgumentError(validation);
    await _storage.write(key: _profileKey, value: jsonEncode(profile.toJson()));
  }

  Future<ShellyConnectionProfile?> readDraft() async {
    final raw = await _storage.read(key: _draftKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return ShellyConnectionProfile.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      return null;
    }
  }

  Future<void> saveDraft(ShellyConnectionProfile profile) async {
    await _storage.write(key: _draftKey, value: jsonEncode(profile.toJson()));
  }

  Future<void> clearDraft() => _storage.delete(key: _draftKey);

  Future<SmartChargerVerificationState> readVerification() async {
    final raw = await _storage.read(key: _verificationKey);
    if (raw == null || raw.isEmpty) {
      return SmartChargerVerificationState.unverified;
    }
    try {
      return SmartChargerVerificationState.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      return SmartChargerVerificationState.unverified;
    }
  }

  Future<void> saveVerification(SmartChargerVerificationState value) =>
      _storage.write(key: _verificationKey, value: jsonEncode(value.toJson()));

  Future<void> invalidateVerification() =>
      saveVerification(SmartChargerVerificationState.unverified);

  Future<void> clearProfile() async {
    await _storage.delete(key: _profileKey);
    await _storage.delete(key: _draftKey);
    await _storage.delete(key: _verificationKey);
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

class SmartChargerVerificationState {
  const SmartChargerVerificationState({
    required this.cloudVerified,
    required this.lanVerified,
    required this.powerMeterVerified,
    required this.safeBootVerified,
    required this.noLoadTestVerified,
    this.lastVerifiedAt,
  });

  final bool cloudVerified;
  final bool lanVerified;
  final bool powerMeterVerified;
  final bool safeBootVerified;
  final bool noLoadTestVerified;
  final DateTime? lastVerifiedAt;

  bool get readyForControl =>
      cloudVerified ||
      (lanVerified && safeBootVerified && noLoadTestVerified);

  static const unverified = SmartChargerVerificationState(
    cloudVerified: false,
    lanVerified: false,
    powerMeterVerified: false,
    safeBootVerified: false,
    noLoadTestVerified: false,
  );

  SmartChargerVerificationState copyWith({
    bool? cloudVerified,
    bool? lanVerified,
    bool? powerMeterVerified,
    bool? safeBootVerified,
    bool? noLoadTestVerified,
    DateTime? lastVerifiedAt,
  }) => SmartChargerVerificationState(
    cloudVerified: cloudVerified ?? this.cloudVerified,
    lanVerified: lanVerified ?? this.lanVerified,
    powerMeterVerified: powerMeterVerified ?? this.powerMeterVerified,
    safeBootVerified: safeBootVerified ?? this.safeBootVerified,
    noLoadTestVerified: noLoadTestVerified ?? this.noLoadTestVerified,
    lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
  );

  Map<String, dynamic> toJson() => {
    'cloudVerified': cloudVerified,
    'lanVerified': lanVerified,
    'powerMeterVerified': powerMeterVerified,
    'safeBootVerified': safeBootVerified,
    'noLoadTestVerified': noLoadTestVerified,
    if (lastVerifiedAt != null)
      'lastVerifiedAt': lastVerifiedAt!.toIso8601String(),
  };

  factory SmartChargerVerificationState.fromJson(Map<String, dynamic> json) =>
      SmartChargerVerificationState(
        cloudVerified: json['cloudVerified'] == true,
        lanVerified: json['lanVerified'] == true,
        powerMeterVerified: json['powerMeterVerified'] == true,
        safeBootVerified: json['safeBootVerified'] == true,
        noLoadTestVerified: json['noLoadTestVerified'] == true,
        lastVerifiedAt: DateTime.tryParse(
          json['lastVerifiedAt']?.toString() ?? '',
        ),
      );
}
