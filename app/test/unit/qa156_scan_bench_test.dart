import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/dashboard_layout_parser.dart';
import 'package:vinfast_battery/data/services/dashboard_templates.dart';
import 'package:vinfast_battery/data/services/seven_segment_reader.dart';

/// QA 156 / QA 159: how often one camera frame of the owner's Feliz cluster
/// is read right when the phone is not lined up: shifted, nearer or
/// further, tilted, darker or brighter, out of focus, noisy.
///
/// Two real photos: 68 %, ODO 4818 km, 31 °C (13/11/2026) and 37 %, ODO
/// 5494 km, 22 °C (15/11/2026, the one the scanner read as 7 %).
///
/// Each trial builds what the phone has: a camera frame whose guide window
/// spans about 950 px (a 1080 px wide portrait stream), the guide window
/// plus its margin cut from it at the scanner's resolution, and the camera
/// frame itself for a second, closer cut (QA 159).
///
/// A wrong number is worse than no number: the vote locks on agreement.
class Photo {
  const Photo(this.file, this.glass, this.soc, this.odo, this.temp);
  final String file;

  /// The cluster's glass in the photo (measured by hand).
  final Rect glass;
  final int soc;
  final double odo;
  final int temp;

  GrayImage load() {
    final bytes = gzip.decode(
      File('test/fixtures/dashboard/$file.gray.gz').readAsBytesSync(),
    );
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final w = data.getUint32(0, Endian.little);
    final h = data.getUint32(4, Endian.little);
    return GrayImage(w, h, Uint8List.fromList(bytes.sublist(8, 8 + w * h)));
  }
}

const photos = [
  Photo('feliz_photo_full', Rect.fromLTRB(101, 180, 1024, 830), 68, 4818, 31),
  Photo('feliz_photo_37', Rect.fromLTRB(150, 110, 812, 580), 37, 5494, 22),
];

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

/// Camera pixels across the guide window (1080 px stream, window 88 %).
const cameraWindowPx = 950.0;

class Frame {
  const Frame(this.image, this.window, this.camera, this.toCamera);

  /// What the scanner reads first, and the guide window in it.
  final GrayImage image;
  final Rect window;

  /// The camera frame around the guide window; [toCamera] maps a point of
  /// [image] to it.
  final GrayImage camera;
  final double toCamera;

  /// The scanner's second cut (QA 159): [box] of [image] from the camera.
  Recut? recut(Rect box, int side) {
    final c = Rect.fromLTRB(
      box.left * toCamera,
      box.top * toCamera,
      box.right * toCamera,
      box.bottom * toCamera,
    );
    final cut = camera.region(c, side);
    if (cut == null) return null;
    return (
      image: cut.image,
      origin: Offset(cut.origin.dx / toCamera, cut.origin.dy / toCamera),
      scale: cut.scale * toCamera,
    );
  }
}

/// What the phone has for [shot] of [src].
Frame frameFor(Photo photo, GrayImage src, Shot shot) {
  final glass = photo.glass;
  final ww = glass.width * shot.scale, wh = glass.height * shot.scale;
  final cx = glass.center.dx + shot.dx * glass.width;
  final cy = glass.center.dy + shot.dy * glass.height;
  // Same margins as `_guideRoi`.
  final roiW = ww * 1.24, roiH = wh * 1.36;
  final kc = cameraWindowPx / ww; // camera px per photo px
  final camW = (roiW * kc).round(), camH = (roiH * kc).round();
  final rad = shot.tilt * math.pi / 180;
  final cosT = math.cos(rad), sinT = math.sin(rad);
  var img = Float32List(camW * camH);
  for (var v = 0; v < camH; v++) {
    for (var u = 0; u < camW; u++) {
      final ox = (u - camW / 2) / kc, oy = (v - camH / 2) / kc;
      final x = cx + cosT * ox - sinT * oy;
      final y = cy + sinT * ox + cosT * oy;
      final x0 = x.floor().clamp(0, src.width - 2);
      final y0 = y.floor().clamp(0, src.height - 2);
      final fx = (x - x0).clamp(0.0, 1.0), fy = (y - y0).clamp(0.0, 1.0);
      final i = y0 * src.width + x0;
      final a = src.pixels[i], b = src.pixels[i + 1];
      final c = src.pixels[i + src.width], d = src.pixels[i + src.width + 1];
      img[v * camW + u] =
          (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;
    }
  }
  for (var pass = 0; pass < shot.blur; pass++) {
    final next = Float32List(camW * camH);
    for (var v = 0; v < camH; v++) {
      for (var u = 0; u < camW; u++) {
        var sum = 0.0;
        var n = 0;
        for (var dv = -1; dv <= 1; dv++) {
          final vv = v + dv;
          if (vv < 0 || vv >= camH) continue;
          for (var du = -1; du <= 1; du++) {
            final uu = u + du;
            if (uu < 0 || uu >= camW) continue;
            sum += img[vv * camW + uu];
            n++;
          }
        }
        next[v * camW + u] = sum / n;
      }
    }
    img = next;
  }
  final random = math.Random(shot.seed);
  final cam = Uint8List(camW * camH);
  for (var i = 0; i < cam.length; i++) {
    var value = img[i] * shot.gain;
    if (shot.noise > 0) {
      value +=
          (random.nextDouble() +
              random.nextDouble() +
              random.nextDouble() -
              1.5) *
          2 *
          shot.noise;
    }
    cam[i] = value.round().clamp(0, 255);
  }
  final camera = GrayImage(camW, camH, cam);
  // The scanner's first cut: the whole guide window at its resolution.
  final first = camera.region(
    Rect.fromLTWH(0, 0, camW.toDouble(), camH.toDouble()),
    SevenSegmentReader.frameSide,
    upscale: false,
  )!;
  final k = first.scale; // read px per camera px
  final left = (camW - ww * kc) / 2 * k, top = (camH - wh * kc) / 2 * k;
  return Frame(
    first.image,
    Rect.fromLTWH(left, top, ww * kc * k, wh * kc * k),
    camera,
    1 / k,
  );
}

DashboardLayoutReading readFrame(Frame frame, {double? lastOdoKm}) =>
    SevenSegmentReader.readFrame(
      frame.image,
      template: DashboardTemplate.feliz2025,
      window: frame.window,
      lastOdoKm: lastOdoKm,
      recut: frame.recut,
    );

List<Shot> shots(int count, {double spread = 1, bool far = false}) {
  final r = math.Random(156);
  double span(double a, double b) => a + (b - a) * r.nextDouble();
  return [
    for (var i = 0; i < count; i++)
      Shot(
        dx: span(-0.08, 0.08) * spread,
        dy: span(-0.08, 0.08) * spread,
        // QA 159: the owner's real scan had the glass at about 60 % of the
        // window, a window 1.6 times the glass.
        scale: far ? span(1.3, 1.9) : 1 + span(-0.15, 0.20) * spread,
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

final _count = int.parse(Platform.environment['SCAN_BENCH_N'] ?? '200');
final _spread = double.parse(Platform.environment['SCAN_BENCH_SPREAD'] ?? '1');

void main() {
  for (final photo in photos) {
    final src = photo.load();

    test('${photo.file} lined up reads ${photo.soc} %', () {
      final r = readFrame(frameFor(photo, src, const Shot()));
      expect([r.soc, r.odoKm, r.tempC], [photo.soc, photo.odo, photo.temp]);
    });

    for (final far in [false, true]) {
      test(
        '${photo.file}: $_count frames ${far ? 'held far' : 'not lined up'}',
        () {
          final soc = Tally(), odo = Tally(), temp = Tally();
          final failures = <String>[];
          final watch = Stopwatch();
          for (final shot in shots(_count, spread: _spread, far: far)) {
            final frame = frameFor(photo, src, shot);
            watch.start();
            final r = readFrame(frame, lastOdoKm: photo.odo - 20);
            watch.stop();
            soc.add(r.soc, photo.soc);
            odo.add(r.odoKm, photo.odo);
            temp.add(r.tempC, photo.temp);
            if (r.soc != photo.soc || r.odoKm != photo.odo) {
              failures.add('$shot → ${r.soc} / ${r.odoKm} / ${r.tempC}');
            }
          }
          // ignore: avoid_print
          print(
            '${photo.file} ${far ? 'FAR' : 'near'}, '
            '${watch.elapsedMilliseconds ~/ _count} ms/frame\n'
            '  %:    $soc\n  ODO:  $odo\n  temp: $temp',
          );
          if (Platform.environment['SCAN_BENCH_VERBOSE'] == '1') {
            // ignore: avoid_print
            failures.take(40).forEach(print);
          }
          // A wrong % is what the owner saw: never more than 1 in 100.
          expect(soc.wrongRate, lessThanOrEqualTo(_maxWrong));
          expect(odo.wrongRate, lessThanOrEqualTo(_maxWrong));
          if (!far) {
            expect(soc.rightRate, greaterThanOrEqualTo(_minRight));
            expect(odo.rightRate, greaterThanOrEqualTo(_minRight));
          }
        },
      );
    }
  }
}

// Measured 13/11/2026: 100 % right on 150 frames (before QA 156: the %
// was right on 54 % and wrong on 41 %). QA 159 adds the frames held far.
const _maxWrong = 0.01;
const _minRight = 0.95;
