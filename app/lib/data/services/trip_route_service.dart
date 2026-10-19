import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

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

class TripRouteService {
  static const _headers = {
    // Nominatim policy: identify the application (QA 129).
    'User-Agent':
        'VinFastBattery/1.3 (Android app com.bes.vinbatery; trip planner)',
    'Accept-Language': 'vi,en;q=0.8',
  };

  static Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': trimmed,
      'format': 'jsonv2',
      'limit': '6',
      'countrycodes': 'vn',
    });
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Không thể tìm địa điểm (${response.statusCode})');
    }
    final rows = jsonDecode(response.body) as List<dynamic>;
    return rows.map((raw) {
      final row = raw as Map<String, dynamic>;
      return PlaceSuggestion(
        name: row['display_name']?.toString() ?? trimmed,
        point: LatLng(
          double.parse(row['lat'].toString()),
          double.parse(row['lon'].toString()),
        ),
      );
    }).toList();
  }

  static Future<PlannedRoute> route(LatLng start, LatLng end) async =>
      (await routes(start, end)).first;

  /// The fastest route first, then up to two alternatives (Task 126: a
  /// shorter one can save battery).
  static Future<List<PlannedRoute>> routes(LatLng start, LatLng end) async {
    final path =
        '/route/v1/driving/'
        '${start.longitude},${start.latitude};${end.longitude},${end.latitude}';
    final uri = Uri.https('router.project-osrm.org', path, {
      'overview': 'full',
      'geometries': 'geojson',
      'steps': 'false',
      'alternatives': 'true',
    });
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Không thể tính tuyến đường (${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = body['routes'] as List<dynamic>? ?? const [];
    if (rows.isEmpty) throw Exception('Không tìm thấy tuyến đường phù hợp');
    return [
      for (final raw in rows.take(3))
        _parse(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  static PlannedRoute _parse(Map<String, dynamic> row) {
    final coordinates =
        ((row['geometry'] as Map<String, dynamic>)['coordinates'] as List)
            .cast<List<dynamic>>();
    return PlannedRoute(
      distanceKm: (row['distance'] as num).toDouble() / 1000,
      durationMin: (row['duration'] as num).toDouble() / 60,
      geometry: coordinates
          .map(
            (p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()),
          )
          .toList(),
    );
  }
}
