import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

/// ChargingFeedbackService — PLAN #2
/// Saves charging prediction vs actual results to local CSV
/// for fine-tuning the AI model later.
class ChargingFeedbackService {
  static final ChargingFeedbackService _instance = ChargingFeedbackService._internal();
  factory ChargingFeedbackService() => _instance;
  ChargingFeedbackService._internal();

  static const _fileName = 'charging_feedback.csv';
  static const _csvHeader =
      'timestamp,vehicle_id,start_soc,target_soc,actual_soc,predicted_minutes,actual_minutes,charging_mode,temperature,completion_time,accuracy_score\n';

  /// Get the CSV file path
  Future<String> get _filePath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_fileName';
  }

  /// Ensure CSV file exists with header
  Future<File> _ensureFile() async {
    final path = await _filePath;
    final file = File(path);
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString(_csvHeader);
      debugPrint('[ChargingFeedback] Created CSV at $path');
    }
    return file;
  }

  /// Log a charging feedback entry
  Future<void> logFeedback({
    required String vehicleId,
    required double startSOC,
    required double targetSOC,
    required double actualSOC,
    required int predictedMinutes,
    int? actualMinutes,
    required String chargingMode,
    double? temperature,
    String? completionTime,
  }) async {
    try {
      final file = await _ensureFile();
      final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

      // Calculate accuracy score (0-100)
      double accuracyScore = 0;
      if (targetSOC > 0 && actualSOC > 0) {
        final diff = (actualSOC - targetSOC).abs();
        accuracyScore = ((1 - diff / 100) * 100).clamp(0, 100);
      }

      final row = [
        now,
        vehicleId,
        startSOC.toStringAsFixed(1),
        targetSOC.toStringAsFixed(1),
        actualSOC.toStringAsFixed(1),
        predictedMinutes.toString(),
        (actualMinutes ?? 0).toString(),
        chargingMode,
        (temperature ?? 0).toStringAsFixed(1),
        completionTime ?? '',
        accuracyScore.toStringAsFixed(1),
      ].join(',');

      await file.writeAsString('$row\n', mode: FileMode.append);
      debugPrint('[ChargingFeedback] Logged: $row');
    } catch (e) {
      debugPrint('[ChargingFeedback] Error logging: $e');
    }
  }

  /// Read all feedback entries
  Future<List<Map<String, String>>> readAllFeedback() async {
    try {
      final file = await _ensureFile();
      final content = await file.readAsString();
      final lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();

      if (lines.length <= 1) return []; // Only header

      final headers = lines[0].split(',');
      return lines.skip(1).map((line) {
        final values = line.split(',');
        final map = <String, String>{};
        for (var i = 0; i < headers.length && i < values.length; i++) {
          map[headers[i].trim()] = values[i].trim();
        }
        return map;
      }).toList();
    } catch (e) {
      debugPrint('[ChargingFeedback] Error reading: $e');
      return [];
    }
  }

  /// Get total feedback count
  Future<int> getFeedbackCount() async {
    final data = await readAllFeedback();
    return data.length;
  }

  /// Get average accuracy score
  Future<double> getAverageAccuracy() async {
    final data = await readAllFeedback();
    if (data.isEmpty) return 0;

    double total = 0;
    int count = 0;
    for (final entry in data) {
      final score = double.tryParse(entry['accuracy_score'] ?? '0') ?? 0;
      if (score > 0) {
        total += score;
        count++;
      }
    }
    return count > 0 ? total / count : 0;
  }

  /// Export CSV file path (for sharing)
  Future<String> getExportPath() async {
    final file = await _ensureFile();
    return file.path;
  }

  /// Clear all feedback data
  Future<void> clearAll() async {
    final file = await _ensureFile();
    await file.writeAsString(_csvHeader);
    debugPrint('[ChargingFeedback] Cleared all data');
  }
}
