import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/dashboard_layout_parser.dart';
import 'package:vinfast_battery/data/services/dashboard_templates.dart';
import 'package:vinfast_battery/data/services/seven_segment_reader.dart';

/// QA 156: how often one camera frame of the owner's Feliz cluster
/// (68 %, ODO 4818 km, 31 °C; photo of 13/11/2026) is read right when the
/// phone is not lined up: shifted, nearer or further, tilted, darker or
/// brighter, out of focus, noisy. Each trial cuts the frame the way the
/// scanner does (the guide window plus its margin, at the scanner's
/// resolution) and reads it through the Feliz 2025 template.
///
/// A wrong number is worse than no number: the vote locks on agreement.
GrayImage _fixture() {
  final bytes = gzip.decode(
    File('test/fixtures/dashboard/feliz_photo_full.gray.gz').readAsBytesSync(),
  );
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  final w = data.getUint32(0, Endian.little);
  final h = data.getUint32(4, Endian.little);
  return GrayImage(w, h, Uint8List.fromList(bytes.sublist(8, 8 + w * h)));
}

GrayImage fixtureForProbe() => _fixture();

/// The cluster's glass in the fixture (measured on the photo).
const glass = Rect.fromLTRB(101, 180, 1024, 830);

class Shot {
  const Shot({
    this.dx = 0,
    this.dy = 0,
    this.scale = 1,
    this.tilt = 0,
    this.gain = 1,
    this.blur = 0,
    this.noise = 0,
    this.seed = 0,
  });

  /// Guide window off the glass, as fractions of the glass.
  final double dx, dy;

  /// Guide window size over the glass (above 1: the phone is further).
  final double scale;
  final double tilt;
  final double gain;
  final int blur;
  final double noise;
  final int seed;

  @override
  String toString() =>
      'dx=${dx.toStringAsFixed(2)} dy=${dy.toStringAsFixed(2)} '
      'scale=${scale.toStringAsFixed(2)} tilt=${tilt.toStringAsFixed(1)} '
      'gain=${gain.toStringAsFixed(2)} blur=$blur '
      'noise=${noise.toStringAsFixed(1)}';
}

/// The crop the scanner would read for [shot], and the guide window in it.
({GrayImage image, Rect window}) frameFor(GrayImage src, Shot shot) {
  final ww = glass.width * shot.scale, wh = glass.height * shot.scale;
  final cx = glass.center.dx + shot.dx * glass.width;
  final cy = glass.center.dy + shot.dy * glass.height;
  // Same margins as `_guideRoi`.
  final roiW = ww * 1.24, roiH = wh * 1.36;
  final k = SevenSegmentReader.frameSide / math.max(roiW, roiH);
  final outW = (roiW * k).round(), outH = (roiH * k).round();
  final rad = shot.tilt * math.pi / 180;
  final cosT = math.cos(rad), sinT = math.sin(rad);
  final out = Float32List(outW * outH);
  for (var v = 0; v < outH; v++) {
    for (var u = 0; u < outW; u++) {
      final ox = (u - outW / 2) / k, oy = (v - outH / 2) / k;
      final x = cx + cosT * ox - sinT * oy;
      final y = cy + sinT * ox + cosT * oy;
      final x0 = x.floor().clamp(0, src.width - 2);
      final y0 = y.floor().clamp(0, src.height - 2);
      final fx = (x - x0).clamp(0.0, 1.0), fy = (y - y0).clamp(0.0, 1.0);
      final i = y0 * src.width + x0;
      final a = src.pixels[i], b = src.pixels[i + 1];
      final c = src.pixels[i + src.width], d = src.pixels[i + src.width + 1];
      out[v * outW + u] =
          (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;
    }
  }
  var img = out;
  for (var pass = 0; pass < shot.blur; pass++) {
    final next = Float32List(outW * outH);
    for (var v = 0; v < outH; v++) {
      for (var u = 0; u < outW; u++) {
        var sum = 0.0;
        var n = 0;
        for (var dv = -1; dv <= 1; dv++) {
          final vv = v + dv;
          if (vv < 0 || vv >= outH) continue;
          for (var du = -1; du <= 1; du++) {
            final uu = u + du;
            if (uu < 0 || uu >= outW) continue;
            sum += img[vv * outW + uu];
            n++;
          }
        }
        next[v * outW + u] = sum / n;
      }
    }
    img = next;
  }
  final random = math.Random(shot.seed);
  final pixels = Uint8List(outW * outH);
  for (var i = 0; i < pixels.length; i++) {
    var value = img[i] * shot.gain;
    if (shot.noise > 0) {
      // Sum of three uniforms: close enough to a bell curve.
      value +=
          (random.nextDouble() + random.nextDouble() + random.nextDouble() -
              1.5) *
          2 *
          shot.noise;
    }
    pixels[i] = value.round().clamp(0, 255);
  }
  final left = (outW - ww * k) / 2, top = (outH - wh * k) / 2;
  return (
    image: GrayImage(outW, outH, pixels),
    window: Rect.fromLTWH(left, top, ww * k, wh * k),
  );
}

DashboardLayoutReading readFrame(
  ({GrayImage image, Rect window}) frame, {
  double? lastOdoKm,
}) => SevenSegmentReader.readFrame(
  frame.image,
  template: DashboardTemplate.feliz2025,
  window: frame.window,
  lastOdoKm: lastOdoKm,
);

List<Shot> shots(int count, {double spread = 1}) {
  final r = math.Random(156);
  double span(double a, double b) => a + (b - a) * r.nextDouble();
  return [
    for (var i = 0; i < count; i++)
      Shot(
        dx: span(-0.08, 0.08) * spread,
        dy: span(-0.08, 0.08) * spread,
        scale: 1 + span(-0.15, 0.20) * spread,
        tilt: span(-7, 7) * spread,
        gain: 1 + span(-0.45, 0.30) * spread,
        blur: r.nextInt(3),
        noise: span(0, 8) * spread,
        seed: i,
      ),
  ];
}

class Tally {
  int right = 0, missing = 0, wrong = 0;
  void add(num? got, num want) {
    if (got == null) {
      missing++;
    } else if (got == want) {
      right++;
    } else {
      wrong++;
    }
  }

  int get total => right + missing + wrong;
  double get rightRate => right / total;
  double get wrongRate => wrong / total;
  @override
  String toString() =>
      '${(100 * rightRate).toStringAsFixed(1)}% right, '
      '${(100 * missing / total).toStringAsFixed(1)}% none, '
      '${(100 * wrongRate).toStringAsFixed(1)}% wrong';
}

void main() {
  final src = _fixture();

  test('the photo lined up reads 68 %, 4818 km, 31 °C', () {
    final r = readFrame(frameFor(src, const Shot()));
    expect([r.soc, r.odoKm, r.tempC], [68, 4818, 31]);
  });

  for (final lastOdo in <double?>[
    4800,
    if (Platform.environment['SCAN_BENCH_N'] == null || Platform.environment['SCAN_BENCH_NULL'] == '1') null,
  ]) {
    test('400 frames not lined up, last ODO $lastOdo', () {
      final soc = Tally(), odo = Tally(), temp = Tally();
      final failures = <String>[];
      final watch = Stopwatch();
      for (final shot in shots(_count, spread: _spread)) {
        final frame = frameFor(src, shot);
        watch.start();
        final r = readFrame(frame, lastOdoKm: lastOdo);
        watch.stop();
        soc.add(r.soc, 68);
        odo.add(r.odoKm, 4818);
        temp.add(r.tempC, 31);
        if (r.soc != 68 || r.odoKm != 4818) {
          failures.add('$shot → ${r.soc} / ${r.odoKm} / ${r.tempC}');
        }
      }
      // ignore: avoid_print
      print(
        'last ODO $lastOdo, ${watch.elapsedMilliseconds ~/ 400} ms/frame\n'
        '  %:    $soc\n  ODO:  $odo\n  temp: $temp',
      );
      if (Platform.environment['SCAN_BENCH_VERBOSE'] == '1') {
        // ignore: avoid_print
        failures.take(60).forEach(print);
      }
      expect(soc.wrongRate, lessThanOrEqualTo(_maxWrong));
      expect(odo.wrongRate, lessThanOrEqualTo(_maxWrong));
      expect(soc.rightRate, greaterThanOrEqualTo(_minRight));
      expect(odo.rightRate, greaterThanOrEqualTo(_minRight));
    });
  }
}

final _count = int.parse(Platform.environment['SCAN_BENCH_N'] ?? '200');
final _spread = double.parse(
  Platform.environment['SCAN_BENCH_SPREAD'] ?? '1',
);
// Measured 13/11/2026: 100 % right on 150 frames (before QA 156: the %
// was right on 54 % and wrong on 41 %).
const _maxWrong = 0.01;
const _minRight = 0.95;
