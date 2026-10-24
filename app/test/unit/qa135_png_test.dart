import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/dashboard_ai_reader.dart';
import 'package:vinfast_battery/data/services/seven_segment_reader.dart';

/// QA 135: the crop sent to the image model is a valid grayscale PNG that
/// fits the relay's 512 KB request limit.
void main() {
  testWidgets('encoded crop decodes to the same pixels', (tester) async {
    const w = 37, h = 21;
    final pixels = Uint8List.fromList([
      for (var i = 0; i < w * h; i++) (i * 7) % 256,
    ]);
    final png = encodeGrayPng(GrayImage(w, h, pixels));
    final decoded = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      return (
        frame.image.width,
        frame.image.height,
        data!.buffer.asUint8List(),
      );
    });
    final (dw, dh, rgba) = decoded!;
    expect((dw, dh), (w, h));
    for (final i in [0, 1, 100, w * h - 1]) {
      expect(rgba[i * 4], pixels[i], reason: 'pixel $i');
    }
  });

  test('a large noisy crop is scaled until it fits the relay', () {
    const w = 1400, h = 900;
    var seed = 7;
    final pixels = Uint8List(w * h);
    for (var i = 0; i < pixels.length; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      pixels[i] = seed & 0xff; // noise compresses badly: the worst case
    }
    final png = DashboardAiReader.pngFor(GrayImage(w, h, pixels));
    expect(png.length, lessThanOrEqualTo(DashboardAiReader.maxPngBytes));
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });
}
