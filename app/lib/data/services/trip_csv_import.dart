import 'dart:convert';

/// Rides from a CSV file (Task 127), e.g. the owner's own logger export:
/// `trip_id,distance_km,duration_min,avg_speed_kmh,…,payload_kg,
/// ambient_temp_c,weather_condition,…,start_soc,end_soc,soc_delta,…`.
/// Columns are sent as-is; the server validates every row
/// (`assistant.trip_model.normalize_sample`).
abstract final class TripCsvImport {
  static const int maxRows = 2000;
  static const int batchSize = 500;
  static const Set<String> _required = {'distance_km'};
  static const Set<String> _useful = {
    'trip_id',
    'distance_km',
    'duration_min',
    'avg_speed_kmh',
    'payload_kg',
    'ambient_temp_c',
    'weather_condition',
    'start_soc',
    'end_soc',
    'soc_delta',
  };

  /// Parsed rows, or a Vietnamese error message.
  static ({List<Map<String, dynamic>> rows, String? error}) parse(
    List<int> bytes,
  ) {
    String text;
    try {
      text = utf8.decode(bytes, allowMalformed: true);
    } on Object {
      return (rows: const [], error: 'Không đọc được file.');
    }
    if (text.startsWith('﻿')) text = text.substring(1);
    final lines = const LineSplitter()
        .convert(text)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) {
      return (rows: const [], error: 'File không có chuyến đi nào.');
    }
    final header = _split(
      lines.first,
    ).map((h) => h.trim().toLowerCase()).toList();
    if (!_required.every(header.contains) ||
        !(header.contains('soc_delta') ||
            (header.contains('start_soc') && header.contains('end_soc')))) {
      return (
        rows: const [],
        error:
            'File cần cột distance_km và soc_delta (hoặc start_soc, end_soc).',
      );
    }
    final rows = <Map<String, dynamic>>[];
    for (final line in lines.skip(1).take(maxRows)) {
      final cells = _split(line);
      final row = <String, dynamic>{};
      for (var i = 0; i < header.length && i < cells.length; i++) {
        if (_useful.contains(header[i])) row[header[i]] = cells[i].trim();
      }
      final id = row['trip_id'];
      if (id is String && id.isNotEmpty) row['clientId'] = id;
      rows.add(row);
    }
    return (rows: rows, error: null);
  }

  /// Minimal CSV split: commas, double-quoted cells with "" escapes.
  static List<String> _split(String line) {
    final cells = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buffer.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          buffer.write(char);
        }
      } else if (char == '"') {
        quoted = true;
      } else if (char == ',') {
        cells.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    cells.add(buffer.toString());
    return cells;
  }
}
