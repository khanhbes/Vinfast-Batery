import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vinfast_model_spec.dart';

/// ========================================================================
/// VehicleSpecRepository — Lấy catalog VinFast specs
/// Thứ tự fallback: Firestore → SharedPreferences cache → local asset
/// ========================================================================
class VehicleSpecRepository {
  static const _cacheKey = 'global_ev_catalog_cache_v4';
  static const _cacheTimestampKey = 'global_ev_catalog_cache_ts_v4';
  static const _cacheTtlHours = 24;

  final FirebaseFirestore _firestore;

  VehicleSpecRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference get _specsRef => _firestore.collection('VehicleCatalog');
  CollectionReference get _legacySpecsRef =>
      _firestore.collection('VinFastModelSpecs');

  Stream<int> watchCatalogRevision() => _firestore
      .collection('VehicleCatalogMeta')
      .doc('current')
      .snapshots()
      .map((snapshot) => (snapshot.data()?['revision'] as num?)?.toInt() ?? 0)
      .distinct();

  /// Lấy tất cả specs, ưu tiên Firestore → cache → local
  Future<List<VinFastModelSpec>> getAllSpecs() async {
    // 1. Thử Firestore
    try {
      final specs = await _fetchFromFirestore();
      if (specs.isNotEmpty) {
        await _saveToCache(specs);
        return specs;
      }
    } catch (e) {
      debugPrint('⚠️ VehicleSpecRepository: Firestore fetch failed: $e');
    }

    // 2. Thử cache
    try {
      final cached = await _loadFromCache();
      if (cached.isNotEmpty) {
        debugPrint('📦 VehicleSpecRepository: Using cached specs');
        return cached;
      }
    } catch (e) {
      debugPrint('⚠️ VehicleSpecRepository: Cache load failed: $e');
    }

    // 3. Fallback local asset
    debugPrint('📄 VehicleSpecRepository: Using local fallback');
    return _loadFromAsset();
  }

  /// Lấy 1 spec theo modelId
  Future<VinFastModelSpec?> getSpec(String modelId) async {
    final specs = await getAllSpecs();
    try {
      return specs.firstWhere((s) => s.modelId == modelId);
    } catch (_) {
      return null;
    }
  }

  /// Auto-match model từ tên xe
  Future<VinFastModelSpec?> matchByVehicleName(String vehicleName) async {
    if (vehicleName.isEmpty) return null;
    final specs = await getAllSpecs();
    for (final spec in specs) {
      if (spec.matchesName(vehicleName)) return spec;
    }
    return null;
  }

  // ── Firestore ──

  Future<List<VinFastModelSpec>> _fetchFromFirestore() async {
    // This constraint is also enforced by Firestore rules. Archived entries
    // remain available only through the owner-aware mobile detail API.
    final snapshot = await _specsRef.where('selectable', isEqualTo: true).get();
    var documents = snapshot.docs;
    if (documents.isEmpty) {
      // One-release compatibility window while the reviewed global catalog is
      // seeded. Old installs and local development continue to work.
      documents = (await _legacySpecsRef.get()).docs;
      debugPrint(
        'ℹ️ VehicleSpecRepository: global catalog empty; using legacy projection',
      );
    }
    return documents
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final locale =
              WidgetsBinding.instance.platformDispatcher.locale.languageCode;
          return VinFastModelSpec.fromMap(data, id: doc.id, locale: locale);
        })
        .where((spec) => spec.selectable)
        .toList();
  }

  // ── SharedPreferences Cache ──

  Future<void> _saveToCache(List<VinFastModelSpec> specs) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(specs.map((s) => s.toMap()).toList());
    await prefs.setString(_cacheKey, json);
    await prefs.setInt(
      _cacheTimestampKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<List<VinFastModelSpec>> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_cacheTimestampKey) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age > _cacheTtlHours * 3600 * 1000) return [];

    final json = prefs.getString(_cacheKey);
    if (json == null || json.isEmpty) return [];

    final list = jsonDecode(json) as List;
    return list
        .map((e) => VinFastModelSpec.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // ── Local Asset Fallback ──

  Future<List<VinFastModelSpec>> _loadFromAsset() async {
    final raw = await rootBundle.loadString(
      'assets/vinfast_specs_fallback.json',
    );
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => VinFastModelSpec.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}

/// Riverpod provider
final vehicleSpecRepositoryProvider = Provider<VehicleSpecRepository>((ref) {
  return VehicleSpecRepository();
});

/// Provider lấy tất cả specs (cached)
final allVinFastSpecsProvider = FutureProvider<List<VinFastModelSpec>>((ref) {
  ref.watch(vehicleCatalogRevisionProvider);
  return ref.watch(vehicleSpecRepositoryProvider).getAllSpecs();
});

final vehicleCatalogRevisionProvider = StreamProvider<int>((ref) {
  return ref.watch(vehicleSpecRepositoryProvider).watchCatalogRevision();
});
