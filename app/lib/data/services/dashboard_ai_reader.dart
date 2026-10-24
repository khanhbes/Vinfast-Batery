import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/services/pinova_api.dart';
import 'seven_segment_reader.dart';

/// What the server's image model read on the cluster (QA 135).
class DashboardAiResult {
  const DashboardAiResult({this.soc, this.odoKm, this.confidence = 0});

  final int? soc;
  final double? odoKm;
  final double confidence;

  bool get isEmpty => soc == null && odoKm == null;
}

/// The fallback when the on-phone reader cannot lock both numbers (glare,
/// an unusual cluster, an extreme angle): one grayscale crop of the guide
/// window goes to `POST /api/scan/dashboard`, the server asks Gemini (via
/// the existing relay) and stores nothing. Daily limit per plan; the owner
/// still checks the numbers before saving.
class DashboardAiReader {
  DashboardAiReader({PinovaApi? api})
    : _api = api ?? PinovaApi(timeout: const Duration(seconds: 15));

  final PinovaApi _api;

  /// The relay accepts 512 KB; base64 adds a third.
  static const maxPngBytes = 330 * 1024;

  Future<DashboardAiResult> read(Uint8List png, {double? lastOdoKm}) async {
    final data = await _api.post('/api/scan/dashboard', {
      'image': base64Encode(png),
      'mimeType': 'image/png',
      'lastOdoKm': ?lastOdoKm,
    });
    final soc = (data['soc'] as num?)?.toInt();
    final odo = (data['odoKm'] as num?)?.toDouble();
    return DashboardAiResult(
      soc: soc != null && soc >= 0 && soc <= 100 ? soc : null,
      odoKm: odo != null && odo >= 0 && odo < 1000000 ? odo : null,
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  /// A PNG of [image] no larger than [maxPngBytes] (scaled down if needed).
  static Uint8List pngFor(GrayImage image, {int maxSide = 768}) {
    var current = _fit(image, maxSide);
    var png = encodeGrayPng(current);
    while (png.length > maxPngBytes && current.width > 160) {
      current = _fit(
        current,
        (math.max(current.width, current.height) * 0.75).round(),
      );
      png = encodeGrayPng(current);
    }
    return png;
  }

  static GrayImage _fit(GrayImage image, int maxSide) {
    final side = math.max(image.width, image.height);
    if (side <= maxSide) return image;
    final scale = maxSide / side;
    final w = math.max(1, (image.width * scale).round());
    final h = math.max(1, (image.height * scale).round());
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final sy = math.min(image.height - 1, (y / scale).floor());
      for (var x = 0; x < w; x++) {
        final sx = math.min(image.width - 1, (x / scale).floor());
        out[y * w + x] = image.pixels[sy * image.width + sx];
      }
    }
    return GrayImage(w, h, out);
  }
}

/// 8-bit grayscale PNG (no extra package: zlib from dart:io).
Uint8List encodeGrayPng(GrayImage image) {
  final w = image.width, h = image.height;
  final raw = Uint8List((w + 1) * h);
  for (var y = 0; y < h; y++) {
    raw[y * (w + 1)] = 0; // filter: none
    raw.setRange(y * (w + 1) + 1, (y + 1) * (w + 1), image.pixels, y * w);
  }
  final out = BytesBuilder();
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final typeBytes = ascii.encode(type);
    final length = ByteData(4)..setUint32(0, data.length);
    out.add(length.buffer.asUint8List());
    out.add(typeBytes);
    out.add(data);
    final crc = ByteData(4)..setUint32(0, _crc32([...typeBytes, ...data]));
    out.add(crc.buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 0) // grayscale
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder(level: 6).convert(raw));
  chunk('IEND', const []);
  return out.toBytes();
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
