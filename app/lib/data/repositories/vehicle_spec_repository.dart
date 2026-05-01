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
  static const _cacheKey = 'vinfast_specs_cache';
  static const _cacheTimestampKey = 'vinfast_specs_cache_ts';
  static const _cacheTtlHours = 24;

  final FirebaseFirestore _firestore;

  VehicleSpecRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference get _specsRef =>
      _firestore.collection('VinFastModelSpecs');

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
    // VinFastModelSpecs is read-only from clients (managed via backend/admin).
    // If Firestore is empty, return [] so the caller falls back to cache/asset.
    final snapshot = await _specsRef.get();
    if (snapshot.docs.isEmpty) {
      debugPrint('ℹ️ VehicleSpecRepository: Firestore VinFastModelSpecs empty (backend-managed)');
      return [];
    }
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return VinFastModelSpec.fromMap(data, id: doc.id);
    }).toList();
  }

  // ── SharedPreferences Cache ──

  Future<void> _saveToCache(List<VinFastModelSpec> specs) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(specs.map((s) => s.toMap()).toList());
    await prefs.setString(_cacheKey, json);
    await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
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
    final raw = await rootBundle.loadString('assets/vinfast_specs_fallback.json');
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
  return ref.watch(vehicleSpecRepositoryProvider).getAllSpecs();
});
