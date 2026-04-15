import 'package:cloud_firestore/cloud_firestore.dart';

/// Helper truy vấn an toàn cho Firestore.
/// Nếu gặp `failed-precondition` (thiếu composite index) → tự fallback
/// sang query không orderBy, sort + limit ở client.
class FirestoreSafeQuery {
  /// Truy vấn với orderBy an toàn: nếu Firestore chưa tạo composite index,
  /// sẽ fallback về query đơn giản rồi sort ở client.
  static Future<List<QueryDocumentSnapshot>> orderedQuery({
    required CollectionReference collection,
    required String whereField,
    required Object whereValue,
    required String orderByField,
    bool descending = true,
    int? limit,
  }) async {
    try {
      Query query = collection
          .where(whereField, isEqualTo: whereValue)
          .orderBy(orderByField, descending: descending);
      if (limit != null) query = query.limit(limit);
      final snapshot = await query.get();
      return snapshot.docs;
    } catch (e) {
      if (_isIndexError(e)) {
        // Fallback: query không orderBy, sort ở client
        final snapshot = await collection
            .where(whereField, isEqualTo: whereValue)
            .get();
        final docs = snapshot.docs.toList();
        docs.sort((a, b) {
          final aVal = _getTimestamp(a, orderByField);
          final bVal = _getTimestamp(b, orderByField);
          if (aVal == null && bVal == null) return 0;
          if (aVal == null) return descending ? 1 : -1;
          if (bVal == null) return descending ? -1 : 1;
          return descending ? bVal.compareTo(aVal) : aVal.compareTo(bVal);
        });
        if (limit != null && docs.length > limit) {
          return docs.sublist(0, limit);
        }
        return docs;
      }
      rethrow;
    }
  }

  /// Kiểm tra lỗi có phải thiếu composite index không
  static bool _isIndexError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('failed-precondition') ||
        msg.contains('failed_precondition') ||
        msg.contains('requires an index') ||
        msg.contains('indexes?create_composite');
  }

  /// Lấy giá trị Timestamp từ document để sort ở client
  static DateTime? _getTimestamp(QueryDocumentSnapshot doc, String field) {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;
      final val = data[field];
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      return null;
    } catch (_) {
      return null;
    }
  }
}
