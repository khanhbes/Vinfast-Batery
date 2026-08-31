import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/vehicle_charger_binding.dart';

/// Explicit vehicle → physical Shelly binding. A shared device can be bound
/// to multiple vehicles, but the server still serializes active sessions.
class VehicleChargerBindingService {
  VehicleChargerBindingService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      _firestore
          .collection('users')
          .doc(uid)
          .collection('vehicleChargerBindings');

  Future<VehicleChargerBinding?> get(String vehicleId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || vehicleId.isEmpty) return null;
    final snapshot = await _collection(uid).doc(vehicleId).get();
    if (!snapshot.exists) return null;
    final data = snapshot.data();
    if (data == null) return null;
    data['vehicleId'] = vehicleId;
    return VehicleChargerBinding.fromMap(data);
  }

  Future<void> save(VehicleChargerBinding binding) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Cần đăng nhập để lưu binding Shelly.');
    await _collection(uid).doc(binding.vehicleId).set({
      ...binding.toMap(),
      'ownerUid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> remove(String vehicleId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _collection(uid).doc(vehicleId).set({
      'active': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
