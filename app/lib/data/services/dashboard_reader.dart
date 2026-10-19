import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'dashboard_layout_parser.dart';
import 'seven_segment_reader.dart';

/// Battery % and ODO read from a photo of the scooter's dashboard (Task 127).
///
/// The scooter has no BMS/Bluetooth link, so the owner's dashboard is the
/// only ground truth. Text recognition runs on the phone (ML Kit, no upload);
/// the result only pre-fills the form — the owner always checks it.
class DashboardReading {
  const DashboardReading({
    this.soc,
    this.odoKm,
    this.socCandidates = const [],
    this.odoCandidates = const [],
    this.odoFromLabel = false,
    this.rawText = '',
    this.frames = 0,
  });

  final int? soc;
  final double? odoKm;
  final List<int> socCandidates;
  final List<double> odoCandidates;

  /// The ODO number sat next to an "ODO" label (higher confidence).
  final bool odoFromLabel;
  final String rawText;

  /// Camera frames that agreed on the values (live scan, QA 131); 0 for a
  /// single photo.
  final int frames;

  bool get isEmpty => soc == null && odoKm == null;
}

abstract final class DashboardReadingParser {
  static final _time = RegExp(r'\b\d{1,2}[:.]\d{2}\b(?!\s*%)');
  static final _percent = RegExp(r'(\d{1,3})\s*%');
  static final _socLabel = RegExp(r'\b(?:SOC|PIN|BAT+ERY)\D{0,4}(\d{1,3})\b');
  static final _odoLabel = RegExp(r'\bODO(?:METER)?\b\D{0,6}(\d[\d .,]{0,9})');
  static final _kmValue = RegExp(r'(\d[\d .,]{1,9})\s*KM\b(?!\s*/\s*H)');
  static final _number = RegExp(r'\d[\d.,]*');

  /// Parse recognised text (lines in reading order).
  static DashboardReading parse(String text) {
    final upper = _normalize(text);
    final socValues = <int>[];
    for (final match in _percent.allMatches(upper)) {
      final value = int.tryParse(match.group(1)!);
      if (value != null && value >= 0 && value <= 100) socValues.add(value);
    }
    for (final match in _socLabel.allMatches(upper)) {
      final value = int.tryParse(match.group(1)!);
      if (value != null && value >= 0 && value <= 100) socValues.add(value);
    }
    final odoValues = <double>[];
    var fromLabel = false;
    for (final match in _odoLabel.allMatches(upper)) {
      final value = _odoNumber(match.group(1)!);
      if (value != null) {
        odoValues.add(value);
        fromLabel = true;
      }
    }
    if (odoValues.isEmpty) {
      for (final line in upper.split('\n')) {
        if (line.contains('TRIP') || line.contains('KM/H')) continue;
        for (final match in _kmValue.allMatches(line)) {
          final value = _odoNumber(match.group(1)!);
          if (value != null && value >= 10) odoValues.add(value);
        }
      }
    }
    if (odoValues.isEmpty) {
      // Last resort: the longest plain number that is not a %, clock,
      // speed or trip value (dashboards show ODO as 4-6 digits).
      final cleaned = upper
          .replaceAll(_time, ' ')
          .replaceAll(_percent, ' ')
          .split('\n')
          .where((line) => !line.contains('TRIP') && !line.contains('KM/H'))
          .join('\n');
      for (final match in _number.allMatches(cleaned)) {
        final digits = match.group(0)!.replaceAll(RegExp(r'[.,]'), '');
        if (digits.length < 3 || digits.length > 6) continue;
        final value = _odoNumber(match.group(0)!);
        if (value != null && value >= 100) odoValues.add(value);
      }
      odoValues.sort((a, b) => b.compareTo(a));
    }
    final socs = socValues.toSet().toList();
    final odos = odoValues.toSet().toList();
    return DashboardReading(
      soc: socs.isEmpty ? null : socs.first,
      odoKm: odos.isEmpty ? null : odos.first,
      socCandidates: socs,
      odoCandidates: odos.take(4).toList(),
      odoFromLabel: fromLabel,
      rawText: text,
    );
  }

  /// Seven-segment LCDs read as letters: fix them only next to digits.
  static String _normalize(String text) {
    // Keep the "ODO" label apart first (LCD fonts often read it as 0D0).
    final value = text.toUpperCase().replaceAll(RegExp(r'[O0]D[O0]'), ' ODO ');
    const confusions = {'O': '0', 'I': '1', 'L': '1', 'S': '5', 'B': '8'};
    return value.replaceAllMapped(
      RegExp(r'(?<=\d)[OILSB]|[OILSB](?=\d)'),
      (m) => confusions[m.group(0)!] ?? m.group(0)!,
    );
  }

  static double? _odoNumber(String raw) {
    var text = raw.trim().replaceAll(' ', '');
    // "1.234" / "1,234" thousands separators vs "1234.5" one decimal.
    final decimal = RegExp(r'^(\d+)[.,](\d)$').firstMatch(text);
    if (decimal != null) {
      text = '${decimal.group(1)}.${decimal.group(2)}';
    } else {
      text = text.replaceAll(RegExp(r'[.,]'), '');
    }
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value < 0 || value > 500000) {
      return null;
    }
    return value;
  }
}

/// Turns ML Kit output into a reading (QA 131): positions first (the
/// layout tells %, ODO, speed and temperature apart), plain text as the
/// fallback. [lastOdoKm] is the last known ODO — the odometer never goes
/// back, so a lower number is a misread.
abstract final class DashboardOcr {
  static List<OcrToken> tokensOf(RecognizedText result) => [
    for (final block in result.blocks)
      for (final line in block.lines)
        for (final element in line.elements)
          OcrToken(element.text, element.boundingBox),
  ];

  static DashboardReading readingOf(
    RecognizedText result, {
    double? lastOdoKm,
  }) {
    final tokens = tokensOf(result);
    final lines = [
      for (final block in result.blocks)
        for (final line in block.lines) line.text,
    ];
    if (!kReleaseMode) {
      // Profile/debug only: real ML Kit output, read with `adb logcat`.
      final boxes = tokens.map(
        (t) =>
            '${t.text}@${t.box.left.round()},${t.box.top.round()},'
            '${t.box.width.round()}x${t.box.height.round()}',
      );
      debugPrint('[dashboard-ocr] ${boxes.join(' | ')}');
    }
    return combine(
      DashboardLayoutParser.parse(tokens, lastOdoKm: lastOdoKm),
      DashboardReadingParser.parse(lines.join('\n')),
      lastOdoKm: lastOdoKm,
    );
  }

  static DashboardReading combine(
    DashboardLayoutReading layout,
    DashboardReading text, {
    double? lastOdoKm,
    int frames = 0,
  }) {
    bool plausible(double km) =>
        lastOdoKm == null || lastOdoKm <= 0 || km >= lastOdoKm - 1;
    final textOdos = text.odoCandidates.where(plausible).toList();
    final odo =
        layout.odoKm ??
        (text.odoKm != null && plausible(text.odoKm!) ? text.odoKm : null);
    return DashboardReading(
      soc: layout.soc ?? text.soc,
      odoKm: odo,
      socCandidates: {...layout.socCandidates, ...text.socCandidates}.toList(),
      odoCandidates: {...layout.odoCandidates, ...textOdos}.take(4).toList(),
      odoFromLabel: layout.odoConfident || text.odoFromLabel,
      rawText: text.rawText,
      frames: frames,
    );
  }
}

/// Picks or takes a dashboard photo and recognises it on the phone.
class DashboardReader {
  DashboardReader({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// `null` when the owner cancelled.
  Future<DashboardReading?> read({
    required bool camera,
    double? lastOdoKm,
  }) async {
    final photo = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (photo == null) return null;
    return readFile(photo.path, lastOdoKm: lastOdoKm, delete: camera);
  }

  /// Reads an image file; [delete] removes it afterwards (a camera shot is
  /// only needed for this reading).
  static Future<DashboardReading> readFile(
    String path, {
    double? lastOdoKm,
    bool delete = false,
  }) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      // Seven-segment LCD first (QA 131): text recognition cannot read the
      // Feliz digits; it stays the fallback for other dashboards.
      final segments = await readSegments(path, lastOdoKm: lastOdoKm);
      if (segments != null && segments.soc != null && segments.odoKm != null) {
        return segments;
      }
      final result = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      final text = DashboardOcr.readingOf(result, lastOdoKm: lastOdoKm);
      if (segments == null) return text;
      return DashboardReading(
        soc: segments.soc ?? text.soc,
        odoKm: segments.odoKm ?? text.odoKm,
        socCandidates: {
          ...segments.socCandidates,
          ...text.socCandidates,
        }.toList(),
        odoCandidates: {
          ...segments.odoCandidates,
          ...text.odoCandidates,
        }.take(4).toList(),
        odoFromLabel: segments.odoFromLabel || text.odoFromLabel,
        rawText: text.rawText,
      );
    } finally {
      await recognizer.close();
      if (delete) {
        try {
          await File(path).delete();
        } on Object {
          // Temporary file; the OS clears it anyway.
        }
      }
    }
  }

  /// Seven-segment reading of a photo, tried upright and turned (the
  /// photo's orientation may not be applied); null when nothing is read.
  static Future<DashboardReading?> readSegments(
    String path, {
    double? lastOdoKm,
  }) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetHeight: 1280);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width, height = image.height;
      image.dispose();
      codec.dispose();
      if (data == null) return null;
      final rgba = data.buffer.asUint8List();
      final layout = await Isolate.run(() {
        final gray = GrayImage.fromRgba(rgba, width, height);
        DashboardLayoutReading? best;
        for (final turn in const [0, 90, 270, 180]) {
          final reading = DashboardLayoutParser.parse(
            SevenSegmentReader.read(gray.rotated(turn)),
            lastOdoKm: lastOdoKm,
          );
          final score =
              (reading.soc != null ? 1 : 0) + (reading.odoKm != null ? 1 : 0);
          final bestScore = best == null
              ? -1
              : (best.soc != null ? 1 : 0) + (best.odoKm != null ? 1 : 0);
          if (score > bestScore) best = reading;
          if (score == 2) break;
        }
        return best;
      });
      if (layout == null || layout.isEmpty) return null;
      return DashboardReading(
        soc: layout.soc,
        odoKm: layout.odoKm,
        socCandidates: layout.socCandidates,
        odoCandidates: layout.odoCandidates,
        odoFromLabel: layout.odoConfident,
      );
    } on Object {
      return null;
    }
  }
}
