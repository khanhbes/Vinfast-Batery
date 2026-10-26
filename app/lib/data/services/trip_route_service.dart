import 'package:latlong2/latlong.dart';

import '../../core/services/api_service.dart';

class PlaceSuggestion {
  final String name;
  final LatLng point;

  const PlaceSuggestion({required this.name, required this.point});
}

class PlannedRoute {
  final double distanceKm;
  final double durationMin;
  final List<LatLng> geometry;

  const PlannedRoute({
    required this.distanceKm,
    required this.durationMin,
    required this.geometry,
  });
}

/// The answer of the Pinova API, for the screen's own fixed messages.
class TripRouteException implements Exception {
  const TripRouteException(this.code);
  final String code;

  @override
  String toString() => 'TripRouteException($code)';
}

/// Places and routes for the trip planner. QA 138 (QA-11): through the
/// Pinova API (`/api/trip/places`, `/api/trip/routes`, Pro), which talks to
/// the map services with one User-Agent, spacing and a cache, and can move
/// off the public OSRM demo server without an app update.
class TripRouteService {
  /// Seams for tests.
  static Future<Map<String, dynamic>> Function(String endpoint) getJson =
      (endpoint) => ApiService().get(endpoint);
  static Future<Map<String, dynamic>> Function(
    String endpoint,
    Map<String, dynamic> body,
  )
  postJson = (endpoint, body) => ApiService().post(endpoint, body);

  static List<Map<String, dynamic>> _items(Map<String, dynamic> response) {
    if (response['success'] != true) {
      throw TripRouteException(response['code']?.toString() ?? 'failed');
    }
    final data = response['data'];
    final items = data is Map ? data['items'] : null;
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  static Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];
    final rows = _items(
      await getJson('/api/trip/places?q=${Uri.encodeQueryComponent(trimmed)}'),
    );
    return [
      for (final row in rows)
        if (row['lat'] is num && row['lon'] is num)
          PlaceSuggestion(
            name: row['name']?.toString() ?? trimmed,
            point: LatLng(
              (row['lat'] as num).toDouble(),
              (row['lon'] as num).toDouble(),
            ),
          ),
    ];
  }

  static Future<PlannedRoute> route(LatLng start, LatLng end) async =>
      (await routes(start, end)).first;

  /// The fastest route first, then up to two alternatives (Task 126: a
  /// shorter one can save battery).
  static Future<List<PlannedRoute>> routes(LatLng start, LatLng end) async {
    final rows = _items(
      await postJson('/api/trip/routes', {
        'from': {'lat': start.latitude, 'lon': start.longitude},
        'to': {'lat': end.latitude, 'lon': end.longitude},
      }),
    );
    final parsed = [
      for (final row in rows.take(3))
        if (row['km'] is num && row['minutes'] is num) _parse(row),
    ];
    if (parsed.isEmpty) throw const TripRouteException('noRoute');
    return parsed;
  }

  static PlannedRoute _parse(Map<String, dynamic> row) {
    final shape = row['geometry'];
    return PlannedRoute(
      distanceKm: (row['km'] as num).toDouble(),
      durationMin: (row['minutes'] as num).toDouble(),
      geometry: [
        if (shape is List)
          for (final p in shape)
            if (p is List && p.length >= 2 && p[0] is num && p[1] is num)
              LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
      ],
    );
  }
}
