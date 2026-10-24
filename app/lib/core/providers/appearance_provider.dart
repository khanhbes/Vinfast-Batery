import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/app_appearance.dart';
import '../../data/models/entitlement.dart';
import '../../features/auth/auth_providers.dart';
import 'entitlement_provider.dart';

/// Reads and writes the appearance per account (QA 131):
/// `users/{uid}/smartChargePreferences/appearance` (existing rules allow
/// the owner's documents there), cached on the phone so the app opens with
/// the owner's layout before the network answers.
class AppearanceStore {
  AppearanceStore({
    FirebaseFirestore? firestore,
    Future<SharedPreferences> Function()? preferences,
  }) : _firestore = firestore,
       _preferences = preferences ?? SharedPreferences.getInstance;

  static const _cachePrefix = 'app_appearance_v1_';
  final FirebaseFirestore? _firestore;
  final Future<SharedPreferences> Function() _preferences;

  Future<AppAppearance> cached(String? uid) async {
    try {
      final raw = (await _preferences()).getString(
        '$_cachePrefix${uid ?? 'guest'}',
      );
      if (raw == null) return const AppAppearance();
      return AppAppearance.fromMap(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      return const AppAppearance();
    }
  }

  /// The account's copy, or null when offline / not signed in.
  Future<AppAppearance?> remote(String? uid) async {
    final firestore = _db;
    if (uid == null || firestore == null) return null;
    try {
      final doc = await _doc(firestore, uid).get();
      final data = doc.data();
      if (data == null) return null;
      final value = AppAppearance.fromMap(data);
      await _cache(uid, value);
      return value;
    } on Object {
      return null;
    }
  }

  Future<void> save(String? uid, AppAppearance value) async {
    await _cache(uid, value);
    final firestore = _db;
    if (uid == null || firestore == null) return;
    try {
      await _doc(firestore, uid).set({
        ...value.toMap(),
        'ownerUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on Object {
      // The phone keeps the choice; it syncs on the next change.
    }
  }

  Future<void> _cache(String? uid, AppAppearance value) async {
    try {
      await (await _preferences()).setString(
        '$_cachePrefix${uid ?? 'guest'}',
        jsonEncode(value.toMap()),
      );
    } on Object {
      // Cache only.
    }
  }

  DocumentReference<Map<String, dynamic>> _doc(
    FirebaseFirestore firestore,
    String uid,
  ) => firestore
      .collection('users')
      .doc(uid)
      .collection('smartChargePreferences')
      .doc('appearance');

  FirebaseFirestore? get _db {
    if (_firestore != null) return _firestore;
    try {
      return FirebaseFirestore.instance;
    } on Object {
      return null;
    }
  }
}

final appearanceStoreProvider = Provider<AppearanceStore>(
  (ref) => AppearanceStore(),
);

/// The signed-in uid, or null where Firebase is unavailable (tests).
final _appearanceUidProvider = Provider<String?>((ref) {
  try {
    return ref.watch(currentUidProvider);
  } on Object {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } on Object {
      return null;
    }
  }
});

class AppearanceNotifier extends Notifier<AppAppearance> {
  String? _uid;
  int _generation = 0;

  @override
  AppAppearance build() {
    _uid = ref.watch(_appearanceUidProvider);
    final generation = ++_generation;
    final store = ref.read(appearanceStoreProvider);
    () async {
      final cached = await store.cached(_uid);
      if (generation == _generation && cached != state) state = cached;
      final remote = await store.remote(_uid);
      if (remote != null && generation == _generation && remote != state) {
        state = remote;
      }
    }();
    return const AppAppearance();
  }

  Future<void> set(AppAppearance value) async {
    if (value == state) return;
    _generation++; // a pending load must not overwrite the owner's choice
    state = value;
    await ref.read(appearanceStoreProvider).save(_uid, value);
  }

  Future<void> setDashboard(DashboardStyle style) =>
      set(state.copyWith(dashboard: style));
  Future<void> setCharge(ChargeStyle style) =>
      set(state.copyWith(charge: style));
  Future<void> setConfirm(ChargeConfirmStyle style) =>
      set(state.copyWith(confirm: style));
}

final appearanceProvider = NotifierProvider<AppearanceNotifier, AppAppearance>(
  AppearanceNotifier.new,
);

/// What the screens draw (QA 135): the Overview and Charge layouts are a
/// Pro feature, so without it they fall back to the defaults (the owner's
/// choice is kept and comes back with the plan). The ON confirmation style
/// stays free: it is a safety/accessibility choice.
final effectiveAppearanceProvider = Provider<AppAppearance>((ref) {
  final chosen = ref.watch(appearanceProvider);
  final allowed = ref.watch(
    entitlementProvider.select(
      (plan) => plan.allows(PremiumFeature.appearance),
    ),
  );
  if (allowed) return chosen;
  return chosen.copyWith(
    dashboard: const AppAppearance().dashboard,
    charge: const AppAppearance().charge,
  );
});
