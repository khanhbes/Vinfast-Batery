import 'dart:convert';

import 'package:crypto/crypto.dart';
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
  String? _scopedKey(String base) {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      return uid == null ? null : '$base.$uid';
    } on Object {
      // Firebase is not initialized in pure unit tests. Keep the injected
      // storage usable there without weakening the signed-out production path.
      return base;
    }
  }
  static DateTime? _lastServerSyncAt;
  static String? _lastServerSyncUid;
  static Future<ShellyConnectionProfile?>? _serverRestoreInFlight;
  static String? _serverRestoreUid;

  static String fingerprintFor(
    ShellyConnectionProfile profile, {
    String? initialState,
    bool? autoOn,
  }) => sha256
      .convert(
        utf8.encode(
          '${profile.deviceId}|${profile.model}|${initialState ?? ''}|${autoOn ?? ''}',
        ),
      )
      .toString();

  Future<ShellyConnectionProfile?> readProfile({String? vehicleId}) async {
    try {
      final key = _scopedKey(_profileKey);
      if (key == null) return null;
      final raw = await _storage.read(key: key);
      if (raw != null && raw.isNotEmpty) {
        return ShellyConnectionProfile.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      }
      return await restoreFromCloud(vehicleId: vehicleId);
    } catch (_) {
      debugPrint('[SmartChargerCredentials] local profile read failed');
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
    if (!force &&
        _lastServerSyncUid == uid &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 5)) {
      return null;
    }
    final existing = _serverRestoreInFlight;
    if (existing != null && _serverRestoreUid == uid) return existing;
    final operation = () async {
      try {
        final server = ServerSmartChargerService();
        final metadata = await server.resolveDirectProfile(
          vehicleId: vehicleId,
        );
        if (metadata == null) return null;
        final deviceId = metadata['deviceId']?.toString() ?? '';
        if (deviceId.isEmpty) return null;
        final serverProfile = await server.restoreDirectProfile(deviceId);
        if (serverProfile != null) {
          final verified =
              metadata['cloudVerified'] == true &&
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
                verifiedDeviceId: metadata['verifiedDeviceId']?.toString(),
                verifiedModel: metadata['verifiedModel']?.toString(),
                verificationFingerprint: metadata['verificationFingerprint']
                    ?.toString(),
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
          _lastServerSyncAt = DateTime.now();
          _lastServerSyncUid = uid;
          return serverProfile;
        }
      } catch (_) {
        debugPrint('[SmartChargerCredentials] server profile restore failed');
      }
      return null;
    }();
    _serverRestoreInFlight = operation;
    _serverRestoreUid = uid;
    try {
      return await operation;
    } finally {
      _serverRestoreInFlight = null;
      _serverRestoreUid = null;
    }
  }

  Future<void> saveProfile(ShellyConnectionProfile profile) async {
    final validation = profile.validate();
    if (validation != null) throw ArgumentError(validation);
    final encoded = jsonEncode(profile.toJson());
    final key = _scopedKey(_profileKey);
    if (key == null) throw StateError('Cần đăng nhập để lưu cấu hình Shelly.');
    final previous = await _storage.read(key: key);
    // Verification belongs to the exact saved configuration, not a new device
    // or changed credentials. Invalidate first so a failed write stays safe.
    if (previous != encoded) await invalidateVerification();
    await _storage.write(key: key, value: encoded);
    await clearDraft();
  }

  Future<ShellyConnectionProfile?> readDraft() async {
    final key = _scopedKey(_draftKey);
    if (key == null) return null;
    final raw = await _storage.read(key: key);
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
    final key = _scopedKey(_draftKey);
    if (key != null) {
      await _storage.write(key: key, value: jsonEncode(profile.toJson()));
    }
  }

  Future<void> clearDraft() async {
    final key = _scopedKey(_draftKey);
    if (key != null) await _storage.delete(key: key);
  }

  Future<SmartChargerVerificationState> readVerification() async {
    final key = _scopedKey(_verificationKey);
    if (key == null) return SmartChargerVerificationState.unverified;
    final raw = await _storage.read(key: key);
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
      _scopedKey(_verificationKey) == null
          ? Future.value()
          : _storage.write(
              key: _scopedKey(_verificationKey)!,
              value: jsonEncode(value.toJson()),
            );

  Future<void> invalidateVerification() =>
      saveVerification(SmartChargerVerificationState.unverified);

  Future<void> clearProfile() async {
    final keys = <String?>[
      _scopedKey(_profileKey),
      _scopedKey(_draftKey),
      _scopedKey(_verificationKey),
      _scopedKey(_legacyTokenKey),
    ];
    for (final key in keys.whereType<String>()) {
      await _storage.delete(key: key);
    }
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
  static const _unset = Object();
  const SmartChargerVerificationState({
    required this.cloudVerified,
    required this.lanVerified,
    required this.powerMeterVerified,
    required this.safeBootVerified,
    required this.noLoadTestVerified,
    this.lastVerifiedAt,
    this.verifiedDeviceId,
    this.verifiedModel,
    this.verificationFingerprint,
  });

  final bool cloudVerified;
  final bool lanVerified;
  final bool powerMeterVerified;
  final bool safeBootVerified;
  final bool noLoadTestVerified;
  final DateTime? lastVerifiedAt;
  final String? verifiedDeviceId;
  final String? verifiedModel;
  final String? verificationFingerprint;

  /// Relay ON requires all hardware safety checks. Transport availability
  /// (Cloud/LAN) alone must never unlock control.
  bool get readyForControl =>
      powerMeterVerified &&
      safeBootVerified &&
      noLoadTestVerified &&
      (cloudVerified || lanVerified);

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
    Object? lastVerifiedAt = _unset,
    Object? verifiedDeviceId = _unset,
    Object? verifiedModel = _unset,
    Object? verificationFingerprint = _unset,
  }) => SmartChargerVerificationState(
    cloudVerified: cloudVerified ?? this.cloudVerified,
    lanVerified: lanVerified ?? this.lanVerified,
    powerMeterVerified: powerMeterVerified ?? this.powerMeterVerified,
    safeBootVerified: safeBootVerified ?? this.safeBootVerified,
    noLoadTestVerified: noLoadTestVerified ?? this.noLoadTestVerified,
    lastVerifiedAt: identical(lastVerifiedAt, _unset)
        ? this.lastVerifiedAt
        : lastVerifiedAt as DateTime?,
    verifiedDeviceId: identical(verifiedDeviceId, _unset)
        ? this.verifiedDeviceId
        : verifiedDeviceId as String?,
    verifiedModel: identical(verifiedModel, _unset)
        ? this.verifiedModel
        : verifiedModel as String?,
    verificationFingerprint: identical(verificationFingerprint, _unset)
        ? this.verificationFingerprint
        : verificationFingerprint as String?,
  );

  Map<String, dynamic> toJson() => {
    'cloudVerified': cloudVerified,
    'lanVerified': lanVerified,
    'powerMeterVerified': powerMeterVerified,
    'safeBootVerified': safeBootVerified,
    'noLoadTestVerified': noLoadTestVerified,
    if (lastVerifiedAt != null)
      'lastVerifiedAt': lastVerifiedAt!.toIso8601String(),
    if (verifiedDeviceId != null) 'verifiedDeviceId': verifiedDeviceId,
    if (verifiedModel != null) 'verifiedModel': verifiedModel,
    if (verificationFingerprint != null)
      'verificationFingerprint': verificationFingerprint,
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
        verifiedDeviceId: json['verifiedDeviceId']?.toString(),
        verifiedModel: json['verifiedModel']?.toString(),
        verificationFingerprint: json['verificationFingerprint']?.toString(),
      );
}
