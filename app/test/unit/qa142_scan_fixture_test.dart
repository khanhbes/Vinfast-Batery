import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/dashboard_layout_parser.dart';
import 'package:vinfast_battery/data/services/dashboard_templates.dart';
import 'package:vinfast_battery/data/services/seven_segment_reader.dart';

/// QA 142: the owner's real Feliz 2025 frames (68 %, ODO 4818 km, 31 °C)
/// read through the Feliz 2025 template, battery temperature included.
GrayImage _fixture(String name) {
  final bytes = gzip.decode(
    File('test/fixtures/dashboard/$name.gray.gz').readAsBytesSync(),
  );
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  final w = data.getUint32(0, Endian.little);
  final h = data.getUint32(4, Endian.little);
  return GrayImage(w, h, Uint8List.fromList(bytes.sublist(8, 8 + w * h)));
}

void main() {
  test('every real frame reads 68 %, 4818 km and 31 °C', () {
    for (final name in [
      'feliz_frame0',
      'feliz_frame1',
      'feliz_frame2',
      'feliz_frame3',
      'feliz_frame4',
      'feliz_photo',
    ]) {
      final image = _fixture(name);
      final window = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final r = DashboardLayoutParser.combine([
        for (final pass in SevenSegmentReader.readPasses(image))
          DashboardLayoutParser.parseTemplate(
            pass,
            template: DashboardTemplate.feliz2025,
            window: window,
          ),
      ]);
      expect([r.soc, r.odoKm, r.tempC], [68, 4818, 31], reason: name);
    }
  });
}
