import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/entitlement.dart';
import '../../features/auth/auth_providers.dart';
import '../services/pinova_api.dart';

/// `/api/billing/*` (QA 135).
class BillingRepository {
  BillingRepository({PinovaApi? api}) : _api = api ?? PinovaApi();

  final PinovaApi _api;

  Future<Entitlement> me() async {
    try {
      return Entitlement.fromMap(await _api.get('/api/billing/me'));
    } on PinovaApiException catch (error) {
      // A server from before QA 135 has no billing: nothing is gated.
      if (error.notDeployed) return Entitlement.legacyServer;
      rethrow;
    }
  }

  Future<Entitlement> startTrial() async =>
      Entitlement.fromMap(await _api.post('/api/billing/trial'));

  Future<PromoQuote> redeemPromo(String code) async {
    final quote = PromoQuote.fromMap(
      await _api.post('/api/billing/promo', {'code': code}),
    );
    if (quote == null) throw const PinovaApiException('promoInvalid');
    return quote;
  }

  Future<void> clearPromo() => _api.delete('/api/billing/promo');
}

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => BillingRepository(),
);

final _billingUidProvider = Provider<String?>((ref) {
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

/// The plan of the signed-in account: the phone's cached copy first, then
/// the server's answer; refreshed when the app returns to the foreground.
class EntitlementNotifier extends Notifier<Entitlement> {
  static const _cachePrefix = 'pinova_entitlement_v1_';
  String? _uid;
  int _generation = 0;
  AppLifecycleListener? _lifecycle;

  @override
  Entitlement build() {
    _uid = ref.watch(_billingUidProvider);
    final generation = ++_generation;
    try {
      _lifecycle?.dispose();
      _lifecycle = AppLifecycleListener(onResume: () => refresh());
    } on Object {
      _lifecycle = null; // no binding (plain unit tests)
    }
    ref.onDispose(() => _lifecycle?.dispose());
    if (_uid == null) return const Entitlement();
    () async {
      final cached = await _cached(_uid!);
      if (cached != null && generation == _generation && !state.known) {
        state = cached;
      }
      await _load(generation);
    }();
    return const Entitlement();
  }

  Future<void> refresh() => _load(++_generation);

  Future<void> _load(int generation) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final value = await ref.read(billingRepositoryProvider).me();
      if (generation != _generation) return;
      state = value;
      if (value.serverSupportsBilling) await _cache(uid, value);
    } on Object {
      // Offline: keep the cached plan; the server still decides every gate.
    }
  }

  /// Starts the 7-day trial; throws [PinovaApiException] with the server's
  /// message when the account already used it.
  Future<Entitlement> startTrial() async {
    final value = await ref.read(billingRepositoryProvider).startTrial();
    _generation++;
    state = value;
    if (_uid != null) await _cache(_uid!, value);
    return value;
  }

  Future<PromoQuote> redeemPromo(String code) async {
    final quote = await ref.read(billingRepositoryProvider).redeemPromo(code);
    _generation++;
    state = Entitlement(
      tier: state.tier,
      status: state.status,
      expiresAt: state.expiresAt,
      trialAvailable: state.trialAvailable,
      trialDays: state.trialDays,
      features: state.features,
      limits: state.limits,
      pendingPromo: quote,
      enforced: state.enforced,
      known: state.known,
      serverSupportsBilling: state.serverSupportsBilling,
    );
    return quote;
  }

  Future<void> clearPromo() async {
    await ref.read(billingRepositoryProvider).clearPromo();
    await refresh();
  }

  Future<Entitlement?> _cached(String uid) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        '$_cachePrefix$uid',
      );
      if (raw == null) return null;
      return Entitlement.fromMap(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _cache(String uid, Entitlement value) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        '$_cachePrefix$uid',
        jsonEncode(value.toMap()),
      );
    } on Object {
      // Cache only.
    }
  }
}

final entitlementProvider = NotifierProvider<EntitlementNotifier, Entitlement>(
  EntitlementNotifier.new,
);
