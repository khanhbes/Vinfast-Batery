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
  static const _remoteCheckInterval = Duration(minutes: 15);

  final FirebaseFirestore _firestore;
  List<VinFastModelSpec>? _memoryCache;
  DateTime? _lastRemoteCheck;
  bool _catalogInvalidated = false;
  int? _knownCatalogRevision;

  VehicleSpecRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference get _specsRef => _firestore.collection('VehicleCatalog');
  CollectionReference get _legacySpecsRef =>
      _firestore.collection('VinFastModelSpecs');

  /// Compatibility API; invalidation is now driven by FCM and foreground
  /// bootstrap rather than a permanent Firestore listener.
  Stream<int> watchCatalogRevision() => Stream<int>.value(0);

  bool get needsRemoteRefresh => _catalogInvalidated || _memoryCache == null;

  void invalidateRemoteCache() => _catalogInvalidated = true;

  void applyRemoteRevision(int revision) {
    final previous = _knownCatalogRevision;
    _knownCatalogRevision = revision;
    if (previous != null && previous != revision) _catalogInvalidated = true;
  }

  /// Lấy tất cả specs, ưu tiên Firestore → cache → local
  Future<List<VinFastModelSpec>> getAllSpecs({bool forceRemote = false}) async {
    final now = DateTime.now();
    if (!forceRemote && !_catalogInvalidated && _memoryCache != null &&
        _lastRemoteCheck != null &&
        now.difference(_lastRemoteCheck!) < _remoteCheckInterval) {
      return List.unmodifiable(_memoryCache!);
    }
    if (!forceRemote && !_catalogInvalidated) {
      final cached = await _loadFromCache();
      if (cached.isNotEmpty) {
        _memoryCache = cached;
        _lastRemoteCheck = now;
        _memoryCache = cached;
        _lastRemoteCheck = now;
        return cached;
      }
    }
    // 1. Thử Firestore
    try {
      final specs = await _fetchFromFirestore();
      if (specs.isNotEmpty) {
        await _saveToCache(specs);
        _memoryCache = specs;
        _lastRemoteCheck = now;
        _catalogInvalidated = false;
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
    final fallback = await _loadFromAsset();
    _memoryCache = fallback;
    return fallback;
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
