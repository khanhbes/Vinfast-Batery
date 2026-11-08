import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/dashboard_layout_parser.dart';
import 'package:vinfast_battery/data/services/dashboard_templates.dart';
import 'package:vinfast_battery/data/services/seven_segment_reader.dart';

/// QA 149: the scanner sometimes locked a wrong number even with the frame.
/// A lock must be the dashboard's number or nothing: these runs feed it the
/// owner's real Feliz frames, roughened like a hand-held phone (noise, glare
/// on the glass, exposure, a frame that is a little off), and count wrong
/// locks next to the votes a misread can win on its own.
GrayImage _fixture(String name) {
  final bytes = gzip.decode(
    File('test/fixtures/dashboard/$name.gray.gz').readAsBytesSync(),
  );
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  final w = data.getUint32(0, Endian.little);
  final h = data.getUint32(4, Endian.little);
  return GrayImage(w, h, Uint8List.fromList(bytes.sublist(8, 8 + w * h)));
}

const _names = [
  'feliz_frame0',
  'feliz_frame1',
  'feliz_frame2',
  'feliz_frame3',
  'feliz_frame4',
  'feliz_photo',
];

/// One hand-held frame: shifted a few pixels, exposure and contrast moved,
/// sensor noise and sometimes a lamp reflected on the glass.
GrayImage _roughen(GrayImage image, math.Random random) {
  final w = image.width, h = image.height;
  final out = Uint8List(w * h);
  final dx = random.nextInt(9) - 4, dy = random.nextInt(9) - 4;
  final gain = 0.85 + random.nextDouble() * 0.3;
  final lift = random.nextInt(25) - 12;
  final glare = random.nextDouble() < 0.5;
  final gx = random.nextDouble() * w, gy = random.nextDouble() * h;
  final gr = (0.15 + random.nextDouble() * 0.2) * w;
  final gs = 30 + random.nextInt(60);
  for (var y = 0; y < h; y++) {
    final sy = (y + dy).clamp(0, h - 1);
    for (var x = 0; x < w; x++) {
      final sx = (x + dx).clamp(0, w - 1);
      var v = image.pixels[sy * w + sx] * gain + lift;
      if (glare) {
        final d = math.sqrt((x - gx) * (x - gx) + (y - gy) * (y - gy));
        if (d < gr) v += gs * (1 - d / gr);
      }
      v += random.nextInt(17) - 8;
      out[y * w + x] = v.round().clamp(0, 255);
    }
  }
  return GrayImage(w, h, out);
}

DashboardLayoutReading _read(GrayImage image) {
  final window = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  return DashboardLayoutParser.combine([
    for (final pass in SevenSegmentReader.readPasses(image))
      DashboardLayoutParser.parseTemplate(
        pass,
        template: DashboardTemplate.feliz2025,
        window: window,
        lastOdoKm: 4790,
      ),
  ]);
}

DashboardLayoutReading _r({int? soc, double? odo}) => DashboardLayoutReading(
  soc: soc,
  socConfident: soc != null,
  odoKm: odo,
  odoConfident: odo != null,
);

void main() {
  group('a lock needs a clear majority (QA 149)', () {
    test('one spurious longer reading does not take a real 8 %', () {
      final vote = DashboardScanVote();
      for (final soc in [8, 8, 88, 8, 8]) {
        vote.add(_r(soc: soc));
      }
      expect(vote.socLocked, 8);
    });

    test('a split between two readings locks neither', () {
      final vote = DashboardScanVote();
      for (final soc in [68, 63, 68, 63, 63, 68]) {
        vote.add(_r(soc: soc));
      }
      expect(vote.socLocked, isNull);
      // The dashboard settles: the majority becomes clear.
      for (final soc in [68, 68, 68]) {
        vote.add(_r(soc: soc));
      }
      expect(vote.socLocked, 68);
    });

    test('a lost digit still counts for the longer number seen twice', () {
      final vote = DashboardScanVote();
      for (final soc in [8, 68, 8, 68, 68]) {
        vote.add(_r(soc: soc));
      }
      expect(vote.socLocked, 68);
      final odo = DashboardScanVote();
      for (final v in [48.0, 4818.0, 48.0, 4818.0]) {
        odo.add(_r(odo: v));
      }
      expect(odo.odoLocked, 4818);
    });

    test('three frames alone are not enough any more', () {
      final vote = DashboardScanVote();
      for (final soc in [8, 8, 8]) {
        vote.add(_r(soc: soc));
      }
      expect(vote.socLocked, isNull);
      vote.add(_r(soc: 8));
      expect(vote.socLocked, 8);
    });
  });

  test('an ODO far beyond the last one is not trusted', () {
    final tokens = [
      // ODO zone of a 1000 × 704 window.
      OcrToken('9818', const Rect.fromLTWH(150, 440, 250, 64)),
    ];
    final reading = DashboardLayoutParser.parseTemplate(
      tokens,
      template: DashboardTemplate.feliz2025,
      window: const Rect.fromLTWH(0, 0, 1000, 704),
      lastOdoKm: 4818,
    );
    expect(reading.odoKm, isNull);
    final near = DashboardLayoutParser.parseTemplate(
      [OcrToken('4878', const Rect.fromLTWH(150, 440, 250, 64))],
      template: DashboardTemplate.feliz2025,
      window: const Rect.fromLTWH(0, 0, 1000, 704),
      lastOdoKm: 4818,
    );
    expect(near.odoKm, 4878);
  });

  test('the speed\'s big digits are never read as the battery %', () {
    // A frame lined up a little low: the speed's "00" reaches the % zone.
    final reading = DashboardLayoutParser.parseTemplate(
      [OcrToken('00', const Rect.fromLTWH(200, 170, 160, 150))],
      template: DashboardTemplate.feliz2025,
      window: const Rect.fromLTWH(0, 0, 1000, 704),
    );
    expect(reading.soc, isNull);
  });

  test('hand-held frames of the real cluster never lock a wrong number', () {
    final random = math.Random(149);
    var runs = 0, bothLocked = 0, wrong = 0, frames = 0;
    final notes = <String>[];
    for (final name in _names) {
      final source = _fixture(name);
      for (var run = 0; run < 3; run++) {
        runs++;
        final vote = DashboardScanVote();
        for (var f = 0; f < 10 && !vote.bothLocked; f++) {
          frames++;
          vote.add(_read(_roughen(source, random)));
        }
        if (vote.socLocked != null && vote.socLocked != 68) {
          wrong++;
          notes.add('$name: soc ${vote.socLocked}');
        }
        if (vote.odoLocked != null && vote.odoLocked != 4818) {
          wrong++;
          notes.add('$name: odo ${vote.odoLocked}');
        }
        if (vote.bothLocked) bothLocked++;
      }
    }
    // ignore: avoid_print
    print(
      'hand-held: $bothLocked/$runs locked both in $frames frames, '
      '$wrong wrong ${notes.join('; ')}',
    );
    expect(wrong, 0);
    expect(bothLocked, greaterThanOrEqualTo(runs * 0.8));
  });
}
