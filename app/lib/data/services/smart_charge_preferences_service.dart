import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/smart_charge_cost.dart';

class SmartChargePreferencesService {
  SmartChargePreferencesService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    Future<SharedPreferences> Function()? preferences,
  }) : _auth = auth,
       _firestore = firestore,
       _preferences = preferences ?? SharedPreferences.getInstance;

  static const _cachePrefix = 'smart_charge_preferences_v1_';
  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  final Future<SharedPreferences> Function() _preferences;

  Future<SmartChargePreferences> load() async {
    final uid = _firebaseAuth?.currentUser?.uid;
    final cached = await _readCache(uid);
    if (uid == null) return cached;
    final firestore = _firebaseFirestore;
    if (firestore == null) return cached;
    try {
      final document = await firestore
          .collection('users')
          .doc(uid)
          .collection('smartChargePreferences')
          .doc('current')
          .get();
      final data = document.data();
      if (data == null) return cached;
      final updatedAt = data['updatedAt'];
      final value = SmartChargePreferences(
        ownerUid: uid,
        tariffVndPerKwh: (data['tariffVndPerKwh'] as num?)?.toDouble(),
        chargePowerW: (data['chargePowerW'] as num?)?.toDouble() ?? 400.0,
        updatedAt: updatedAt is Timestamp
            ? updatedAt.toDate()
            : DateTime.tryParse(updatedAt?.toString() ?? '') ?? DateTime.now(),
      );
      await _writeCache(value);
      return value;
    } on Object {
      return cached;
    }
  }

  Future<SmartChargePreferences> saveTariff(double? tariffVndPerKwh) async {
    if (tariffVndPerKwh != null &&
        (tariffVndPerKwh <= 0 || tariffVndPerKwh > 100000)) {
      throw ArgumentError.value(
        tariffVndPerKwh,
        'tariffVndPerKwh',
        'Giá điện phải lớn hơn 0 và không quá 100.000 VND/kWh.',
      );
    }
    final uid = _firebaseAuth?.currentUser?.uid;
    if (uid == null) throw StateError('Cần đăng nhập để lưu giá điện.');
    final firestore = _firebaseFirestore;
    if (firestore == null) {
      throw StateError('Firebase chưa sẵn sàng để lưu giá điện.');
    }
    final current = await load();
    final value = current.copyWith(
      ownerUid: uid,
      tariffVndPerKwh: tariffVndPerKwh,
      clearTariff: tariffVndPerKwh == null,
      updatedAt: DateTime.now(),
    );
    await firestore
        .collection('users')
        .doc(uid)
        .collection('smartChargePreferences')
        .doc('current')
        .set({
          'ownerUid': uid,
          'tariffVndPerKwh': tariffVndPerKwh,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
    await _writeCache(value);
    return value;
  }

  Future<SmartChargePreferences> saveChargePower(double? chargePowerW) async {
    if (chargePowerW != null && (chargePowerW <= 0 || chargePowerW > 10000)) {
      throw ArgumentError.value(
        chargePowerW,
        'chargePowerW',
        'Công suất sạc phải lớn hơn 0 và không quá 10.000 W.',
      );
    }
    final uid = _firebaseAuth?.currentUser?.uid;
    if (uid == null) throw StateError('Cần đăng nhập để lưu cấu hình sạc.');
    final firestore = _firebaseFirestore;
    if (firestore == null) {
      throw StateError('Firebase chưa sẵn sàng để lưu cấu hình sạc.');
    }
    final current = await load();
    final value = current.copyWith(
      ownerUid: uid,
      chargePowerW: chargePowerW ?? 400.0,
      updatedAt: DateTime.now(),
    );
    await firestore
        .collection('users')
        .doc(uid)
        .collection('smartChargePreferences')
        .doc('current')
        .set({
          'ownerUid': uid,
          'chargePowerW': chargePowerW ?? 400.0,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
    await _writeCache(value);
    return value;
  }

  Future<SmartChargePreferences> _readCache(String? uid) async {
    final raw = (await _preferences()).getString(
      '$_cachePrefix${uid ?? 'guest'}',
    );
    if (raw == null) return SmartChargePreferences.empty();
    try {
      return SmartChargePreferences.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      return SmartChargePreferences.empty();
    }
  }

  Future<void> _writeCache(SmartChargePreferences value) async {
    await (await _preferences()).setString(
      '$_cachePrefix${value.ownerUid ?? 'guest'}',
      jsonEncode(value.toJson()),
    );
  }

  FirebaseAuth? get _firebaseAuth {
    if (_auth != null) return _auth;
    try {
      return FirebaseAuth.instance;
    } on FirebaseException {
      return null;
    }
  }

  FirebaseFirestore? get _firebaseFirestore {
    if (_firestore != null) return _firestore;
    try {
      return FirebaseFirestore.instance;
    } on FirebaseException {
      return null;
    }
  }
}
