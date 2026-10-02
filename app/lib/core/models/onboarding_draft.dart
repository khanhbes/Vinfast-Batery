import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

enum OnboardingDraftState {
  localPending,
  syncing,
  synced,
  failedRetryable,
  failedPermanent,
}

class OnboardingDraft {
  static const Object _unset = Object();

  const OnboardingDraft({
    required this.uid,
    required this.operationId,
    required this.revision,
    required this.state,
    required this.name,
    required this.catalogId,
    this.finalizedAt,
    this.phone,
    this.dateOfBirth,
    this.avgDailyDistanceKm,
    this.usagePurpose,
    this.typicalSocWhenCharge,
    this.nickname,
    this.licensePlate,
    this.initialOdo,
    this.shellyStatus = 'skipped',
    this.attemptCount = 0,
    this.nextAttemptAt,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.updatedAt,
  });

  final String uid;
  final String operationId;
  final int revision;
  final OnboardingDraftState state;
  final String name;
  final String? phone;
  final String? dateOfBirth;
  final double? avgDailyDistanceKm;
  final String? usagePurpose;
  final double? typicalSocWhenCharge;
  final String catalogId;
  final DateTime? finalizedAt;
  final String? nickname;
  final String? licensePlate;
  final int? initialOdo;
  final String shellyStatus;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final DateTime? updatedAt;

  /// A selected vehicle is only a draft. Neither AuthGate nor a sync worker
  /// may treat it as completed until the user confirms the review step.
  bool get isEligibleForCommit =>
      finalizedAt != null &&
      name.trim().isNotEmpty &&
      catalogId.trim().isNotEmpty &&
      state != OnboardingDraftState.failedPermanent;

  factory OnboardingDraft.create({
    required String uid,
    required String name,
    required String catalogId,
    String? phone,
    String? dateOfBirth,
    double? avgDailyDistanceKm,
    String? usagePurpose,
    double? typicalSocWhenCharge,
    String? nickname,
    String? licensePlate,
    int? initialOdo,
    String shellyStatus = 'skipped',
  }) => OnboardingDraft(
    uid: uid,
    operationId: const Uuid().v4(),
    revision: 0,
    state: OnboardingDraftState.localPending,
    name: name.trim(),
    phone: phone?.trim(),
    dateOfBirth: dateOfBirth,
    avgDailyDistanceKm: avgDailyDistanceKm,
    usagePurpose: usagePurpose,
    typicalSocWhenCharge: typicalSocWhenCharge,
    catalogId: catalogId.trim(),
    finalizedAt: null,
    nickname: nickname?.trim(),
    licensePlate: licensePlate?.trim(),
    initialOdo: initialOdo?.clamp(0, 9999999).toInt(),
    shellyStatus: shellyStatus == 'connected' ? 'connected' : 'skipped',
    updatedAt: DateTime.now().toUtc(),
  );

  OnboardingDraft copyWith({
    int? revision,
    OnboardingDraftState? state,
    String? name,
    Object? phone = _unset,
    Object? dateOfBirth = _unset,
    Object? avgDailyDistanceKm = _unset,
    Object? usagePurpose = _unset,
    Object? typicalSocWhenCharge = _unset,
    String? catalogId,
    Object? finalizedAt = _unset,
    Object? nickname = _unset,
    Object? licensePlate = _unset,
    Object? initialOdo = _unset,
    String? shellyStatus,
    int? attemptCount,
    Object? nextAttemptAt = _unset,
    Object? lastErrorCode = _unset,
    Object? lastErrorMessage = _unset,
    Object? updatedAt = _unset,
  }) => OnboardingDraft(
    uid: uid,
    operationId: operationId,
    revision: revision ?? this.revision,
    state: state ?? this.state,
    name: name ?? this.name,
    phone: identical(phone, _unset) ? this.phone : phone as String?,
    dateOfBirth: identical(dateOfBirth, _unset)
        ? this.dateOfBirth
        : dateOfBirth as String?,
    avgDailyDistanceKm: identical(avgDailyDistanceKm, _unset)
        ? this.avgDailyDistanceKm
        : avgDailyDistanceKm as double?,
    usagePurpose: identical(usagePurpose, _unset)
        ? this.usagePurpose
        : usagePurpose as String?,
    typicalSocWhenCharge: identical(typicalSocWhenCharge, _unset)
        ? this.typicalSocWhenCharge
        : typicalSocWhenCharge as double?,
    catalogId: catalogId ?? this.catalogId,
    finalizedAt: identical(finalizedAt, _unset)
        ? this.finalizedAt
        : finalizedAt as DateTime?,
    nickname: identical(nickname, _unset) ? this.nickname : nickname as String?,
    licensePlate: identical(licensePlate, _unset)
        ? this.licensePlate
        : licensePlate as String?,
    initialOdo: identical(initialOdo, _unset)
        ? this.initialOdo
        : initialOdo as int?,
    shellyStatus: shellyStatus ?? this.shellyStatus,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: identical(nextAttemptAt, _unset)
        ? this.nextAttemptAt
        : nextAttemptAt as DateTime?,
    lastErrorCode: identical(lastErrorCode, _unset)
        ? this.lastErrorCode
        : lastErrorCode as String?,
    lastErrorMessage: identical(lastErrorMessage, _unset)
        ? this.lastErrorMessage
        : lastErrorMessage as String?,
    updatedAt: identical(updatedAt, _unset)
        ? this.updatedAt
        : updatedAt as DateTime?,
  );

  Map<String, dynamic> toMap() => {
    'schemaVersion': 2,
    'state': state.name,
    'revision': revision,
    'operationId': operationId,
    'name': name,
    if (phone != null) 'phone': phone,
    if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
    if (avgDailyDistanceKm != null) 'avgDailyDistanceKm': avgDailyDistanceKm,
    if (usagePurpose != null) 'usagePurpose': usagePurpose,
    if (typicalSocWhenCharge != null)
      'typicalSocWhenCharge': typicalSocWhenCharge,
    'catalogId': catalogId,
    if (finalizedAt != null) 'finalizedAt': finalizedAt!.toIso8601String(),
    if (nickname != null) 'nickname': nickname,
    if (licensePlate != null) 'licensePlate': licensePlate,
    if (initialOdo != null) 'initialOdo': initialOdo,
    'shellyStatus': shellyStatus,
    'attemptCount': attemptCount,
    if (nextAttemptAt != null)
      'nextAttemptAt': nextAttemptAt!.toIso8601String(),
    if (lastErrorCode != null) 'lastErrorCode': lastErrorCode,
    if (lastErrorMessage != null) 'lastErrorMessage': lastErrorMessage,
    'updatedAt': (updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
  };

  factory OnboardingDraft.fromMap(String uid, Map<String, dynamic> map) {
    DateTime? parse(dynamic value) => value is Timestamp
        ? value.toDate().toUtc()
        : DateTime.tryParse(value?.toString() ?? '')?.toUtc();
    final state = OnboardingDraftState.values.firstWhere(
      (item) => item.name == map['state'],
      orElse: () => OnboardingDraftState.localPending,
    );
    return OnboardingDraft(
      uid: uid,
      operationId: map['operationId']?.toString() ?? const Uuid().v4(),
      revision: (map['revision'] as num?)?.toInt() ?? 0,
      state: state,
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString(),
      dateOfBirth: map['dateOfBirth']?.toString(),
      avgDailyDistanceKm: (map['avgDailyDistanceKm'] as num?)?.toDouble(),
      usagePurpose: map['usagePurpose']?.toString(),
      typicalSocWhenCharge: (map['typicalSocWhenCharge'] as num?)?.toDouble(),
      catalogId: map['catalogId']?.toString() ?? '',
      finalizedAt: parse(map['finalizedAt']),
      nickname: map['nickname']?.toString(),
      licensePlate: map['licensePlate']?.toString(),
      initialOdo: (map['initialOdo'] as num?)?.toInt(),
      shellyStatus: map['shellyStatus']?.toString() == 'connected'
          ? 'connected'
          : 'skipped',
      attemptCount: (map['attemptCount'] as num?)?.toInt() ?? 0,
      nextAttemptAt: parse(map['nextAttemptAt']),
      lastErrorCode: map['lastErrorCode']?.toString(),
      lastErrorMessage: map['lastErrorMessage']?.toString(),
      updatedAt: parse(map['updatedAt']),
    );
  }
}

class OnboardingDraftRepository {
  OnboardingDraftRepository({
    FirebaseFirestore? firestore,
    FlutterSecureStorage? storage,
    Future<Map<String, dynamic>?> Function(String uid)? loadRemote,
  }) : _firestore = firestore,
       _loadRemote = loadRemote,
       _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(encryptedSharedPreferences: true),
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.first_unlock_this_device,
             ),
           );

  final FirebaseFirestore? _firestore;
  final Future<Map<String, dynamic>?> Function(String uid)? _loadRemote;
  final FlutterSecureStorage _storage;
  FirebaseFirestore get _database => _firestore ?? FirebaseFirestore.instance;

  // Repository instances are created by the form, AuthGate and worker. Their
  // local read/compare/write operations must share the same UID-scoped lock.
  static final Map<String, Future<void>> _localOperations = {};

  Future<T> _withLocalLock<T>(String uid, Future<T> Function() action) async {
    final previous = _localOperations[uid];
    final completion = Completer<void>();
    _localOperations[uid] = completion.future;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      completion.complete();
      if (identical(_localOperations[uid], completion.future)) {
        _localOperations.remove(uid);
      }
    }
  }

  String _key(String uid) => 'vinfast.onboarding.draft.$uid';

  Future<OnboardingDraft?> _readLocal(String uid) async {
    final cached = await _storage.read(key: _key(uid));
    if (cached == null || cached.isEmpty) return null;
    try {
      return OnboardingDraft.fromMap(
        uid,
        Map<String, dynamic>.from(jsonDecode(cached) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<OnboardingDraft?> load(String uid) async {
    try {
      final remote =
          await (_loadRemote != null
                  ? _loadRemote(uid)
                  : _database
                        .collection('users')
                        .doc(uid)
                        .collection('onboardingDrafts')
                        .doc('current')
                        .get()
                        .then((snapshot) => snapshot.data()))
              .timeout(const Duration(seconds: 8));
      if (remote != null) {
        final draft = OnboardingDraft.fromMap(uid, remote);
        return await _withLocalLock(uid, () async {
          // Read AFTER the network wait, not before it: a final confirmation
          // may have been saved while this stale remote request was in flight.
          final local = await _readLocal(uid);
          // Firestore can be an older replica after an offline edit. Never
          // replace a newer local revision with stale remote data.
          final localUpdated = local?.updatedAt;
          final remoteUpdated = draft.updatedAt;
          final localIsNewer =
              local != null &&
              (local.revision > draft.revision ||
                  (local.revision == draft.revision &&
                      localUpdated != null &&
                      (remoteUpdated == null ||
                          localUpdated.isAfter(remoteUpdated))));
          if (!localIsNewer) {
            await _storage.write(
              key: _key(uid),
              value: jsonEncode(draft.toMap()),
            );
            return draft;
          }
          return local;
        });
      }
    } catch (_) {
      // Secure local cache is the offline fallback.
    }
    return _withLocalLock(uid, () => _readLocal(uid));
  }

  Future<bool> save(OnboardingDraft draft) async {
    final accepted = await _withLocalLock(draft.uid, () async {
      final current = await _readLocal(draft.uid);
      if (current != null && current.operationId == draft.operationId) {
        // A delayed form/worker save must not roll back a newer revision or
        // erase a final confirmation from this same onboarding operation.
        if (current.revision > draft.revision ||
            (current.finalizedAt != null && draft.finalizedAt == null)) {
          return false;
        }
      }
      await _storage.write(
        key: _key(draft.uid),
        value: jsonEncode(draft.toMap()),
      );
      return true;
    });
    if (!accepted) return false;
    try {
      await _database
          .collection('users')
          .doc(draft.uid)
          .collection('onboardingDrafts')
          .doc('current')
          // Replace the whole draft so a skipped optional answer does not
          // survive a previous merge as a stale Firestore field.
          .set(draft.toMap())
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear(String uid) async {
    await _withLocalLock(uid, () => _storage.delete(key: _key(uid)));
    try {
      await _database
          .collection('users')
          .doc(uid)
          .collection('onboardingDrafts')
          .doc('current')
          .delete()
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }
}
