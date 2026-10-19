import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/dashboard_layout_parser.dart';
import 'package:vinfast_battery/data/services/seven_segment_reader.dart';

/// Real frames of the owner's VinFast Feliz cluster (QA 131), cropped to the
/// LCD and stored as gzip'd 8-bit grayscale (u32 width, u32 height, pixels):
/// five camera frames from the scanner's diagnostics and the owner's photo.
/// The cluster shows 68 %, speed 00, ODO 4818 km, 31 °C.
GrayImage _fixture(String name) {
  final bytes = gzip.decode(
    File('test/fixtures/dashboard/$name.gray.gz').readAsBytesSync(),
  );
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  final w = data.getUint32(0, Endian.little);
  final h = data.getUint32(4, Endian.little);
  return GrayImage(w, h, Uint8List.fromList(bytes.sublist(8, 8 + w * h)));
}

const _frames = [
  'feliz_frame0',
  'feliz_frame1',
  'feliz_frame2',
  'feliz_frame3',
  'feliz_frame4',
  'feliz_photo',
];

void main() {
  test('reads the segment digits of most frames', () {
    var soc = 0, odo = 0;
    for (final name in _frames) {
      final texts = [
        for (final t in SevenSegmentReader.read(_fixture(name))) t.text,
      ];
      // ignore: avoid_print
      print('$name $texts');
      if (texts.contains('68')) soc++;
      if (texts.contains('4818')) odo++;
      expect(texts, contains('31'), reason: name);
      expect(texts, contains('C'), reason: name);
    }
    expect(soc, greaterThanOrEqualTo(5));
    expect(odo, greaterThanOrEqualTo(5));
  });

  test('frames parse to 68 % and ODO 4818, never the speed or °C', () {
    var soc = 0, odo = 0;
    for (final name in _frames) {
      final r = DashboardLayoutParser.parse(
        SevenSegmentReader.read(_fixture(name)),
      );
      // One frame misses the "6" and says 8 % (what the owner saw before
      // QA 131): the vote below outnumbers it.
      if (r.soc == 68) soc++;
      if (r.odoKm == 4818) odo++;
      expect(r.soc, isNot(anyOf(0, 31)), reason: name);
      expect(r.odoKm, anyOf(isNull, 4818), reason: name);
    }
    expect(soc, greaterThanOrEqualTo(5));
    expect(odo, greaterThanOrEqualTo(5));
  });

  test('frames vote to lock both values', () {
    final vote = DashboardScanVote();
    for (final name in _frames) {
      vote.add(
        DashboardLayoutParser.parse(SevenSegmentReader.read(_fixture(name))),
      );
    }
    expect(vote.socLocked, 68);
    expect(vote.odoLocked, 4818);
  });

  test('works with the last ODO as a prior too', () {
    final vote = DashboardScanVote();
    for (final name in _frames) {
      vote.add(
        DashboardLayoutParser.parse(
          SevenSegmentReader.read(_fixture(name)),
          lastOdoKm: 4804,
        ),
      );
    }
    expect(vote.socLocked, 68);
    expect(vote.odoLocked, 4818);
  });

  test('a photo turned on its side still reads (orientation unknown)', () {
    final side = _fixture('feliz_photo').rotated(90);
    final texts = [
      for (final t in SevenSegmentReader.read(side.rotated(270))) t.text,
    ];
    expect(texts, containsAll(['68', '4818']));
  });

  test('an upright working image from a rotated camera plane', () {
    // 4×2 sensor image rotated 90° becomes 2×4 upright.
    final plane = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final img = GrayImage.fromLuminance(
      plane,
      width: 4,
      height: 2,
      bytesPerRow: 4,
      rotation: 90,
      targetHeight: 4,
    );
    expect(img.width, 2);
    expect(img.height, 4);
    // Upright top-left is the sensor's bottom-left.
    expect(img.pixels, [5, 1, 6, 2, 7, 3, 8, 4]);
  });
}
