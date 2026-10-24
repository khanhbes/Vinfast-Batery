import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/dashboard_layout_parser.dart';
import 'package:vinfast_battery/data/services/seven_segment_reader.dart';

/// QA 135: synthetic seven-segment clusters — 1, 2 or 3 digit battery %,
/// 3–6 digit ODO, italic, tilted, small and noisy — so the reader is tested
/// beyond the owner's one Feliz (68 % / 4818 km).
const _segments = {
  '0': 'abcdef',
  '1': 'bc',
  '2': 'abdeg',
  '3': 'abcdg',
  '4': 'bcfg',
  '5': 'acdfg',
  '6': 'acdefg',
  '7': 'abc',
  '8': 'abcdefg',
  '9': 'abcdfg',
  'C': 'adef',
};

class _Canvas {
  _Canvas(this.w, this.h, {int background = 22})
    : px = Uint8List(w * h)..fillRange(0, w * h, background);
  final int w, h;
  final Uint8List px;

  /// A segment box, sheared by [slant] around row [cy].
  void box(
    double x0,
    double y0,
    double x1,
    double y1,
    double slant,
    double cy, {
    int value = 235,
  }) {
    for (var y = y0.floor(); y < y1.ceil(); y++) {
      if (y < 0 || y >= h) continue;
      final dx = slant * (cy - y);
      for (var x = (x0 + dx).floor(); x < (x1 + dx).ceil(); x++) {
        if (x >= 0 && x < w) px[y * w + x] = value;
      }
    }
  }

  /// A seven-segment glyph whose cell is [hgt] tall at ([x], [y]).
  double digit(String ch, double x, double y, double hgt, double slant) {
    final cw = 0.56 * hgt, t = 0.13 * hgt, g = 0.03 * hgt;
    final cy = y + hgt / 2;
    final lit = _segments[ch]!;
    final rects = <String, List<double>>{
      'a': [x + t + g, y, x + cw - t - g, y + t],
      'b': [x + cw - t, y + t + g, x + cw, y + hgt / 2 - g],
      'c': [x + cw - t, y + hgt / 2 + g, x + cw, y + hgt - t - g],
      'd': [x + t + g, y + hgt - t, x + cw - t - g, y + hgt],
      'e': [x, y + hgt / 2 + g, x + t, y + hgt - t - g],
      'f': [x, y + t + g, x + t, y + hgt / 2 - g],
      'g': [
        x + t + g,
        y + hgt / 2 - t / 2,
        x + cw - t - g,
        y + hgt / 2 + t / 2,
      ],
    };
    for (final MapEntry(key: segment, value: r) in rects.entries) {
      if (lit.contains(segment)) box(r[0], r[1], r[2], r[3], slant, cy);
    }
    return cw + 0.22 * hgt;
  }

  double number(
    String text,
    double x,
    double y,
    double hgt,
    double slant, {
    double groupGap = 0,
  }) {
    var cx = x;
    for (var i = 0; i < text.length; i++) {
      // The Feliz ODO prints "48 18": a gap in the middle of four digits.
      if (groupGap > 0 && text.length >= 4 && i == text.length - 2) {
        cx += groupGap;
      }
      cx += digit(text[i], cx, y, hgt, slant);
    }
    return cx;
  }

  /// A small "%" glyph: two dots and a stroke.
  void percent(double x, double y, double hgt, double slant) {
    final cy = y + hgt / 2;
    final d = 0.28 * hgt;
    box(x, y, x + d, y + d, slant, cy);
    box(x + 0.5 * hgt, y + hgt - d, x + 0.5 * hgt + d, y + hgt, slant, cy);
    for (var i = 0; i < 6; i++) {
      final fy = y + hgt * i / 6;
      final fx = x + 0.7 * hgt * (1 - i / 6);
      box(fx, fy, fx + 0.14 * hgt, fy + hgt / 6 + 1, slant, cy);
    }
  }

  void blur() {
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0, n = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
            sum += px[yy * w + xx];
            n++;
          }
        }
        out[y * w + x] = sum ~/ n;
      }
    }
    px.setAll(0, out);
  }

  /// A soft bright spot (a lamp reflected on the LCD glass).
  void glare(double cx, double cy, double radius, int strength) {
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final d = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
        if (d >= radius) continue;
        final add = strength * (1 - d / radius);
        px[y * w + x] = (px[y * w + x] + add).round().clamp(0, 255);
      }
    }
  }

  void noise(math.Random random, int amount) {
    for (var i = 0; i < px.length; i++) {
      px[i] = (px[i] + random.nextInt(2 * amount + 1) - amount).clamp(0, 255);
    }
  }

  /// Rotated by [degrees] and scaled by [scale] around the centre;
  /// [keystone] narrows the top (camera below the dashboard).
  GrayImage transformed(double degrees, double scale, {double keystone = 0}) {
    final ow = (w * scale).round(), oh = (h * scale).round();
    final out = Uint8List(ow * oh)..fillRange(0, ow * oh, px[0]);
    final a = degrees * math.pi / 180;
    final cosA = math.cos(a), sinA = math.sin(a);
    for (var y = 0; y < oh; y++) {
      for (var x = 0; x < ow; x++) {
        final ky = 1 - keystone * (1 - y / oh);
        final ux = (x - ow / 2) / scale / ky, uy = (y - oh / 2) / scale;
        final sx = cosA * ux + sinA * uy + w / 2;
        final sy = -sinA * ux + cosA * uy + h / 2;
        final ix = sx.floor(), iy = sy.floor();
        if (ix < 0 || iy < 0 || ix >= w - 1 || iy >= h - 1) continue;
        final fx = sx - ix, fy = sy - iy;
        final v =
            px[iy * w + ix] * (1 - fx) * (1 - fy) +
            px[iy * w + ix + 1] * fx * (1 - fy) +
            px[(iy + 1) * w + ix] * (1 - fx) * fy +
            px[(iy + 1) * w + ix + 1] * fx * fy;
        out[y * ow + x] = v.round();
      }
    }
    return GrayImage(ow, oh, out);
  }
}

/// A Feliz-like cluster: "%" big top-left with a small "%", the temperature
/// "31 C" small, and the ODO lower right with its gap.
GrayImage _cluster(
  int soc,
  int odo, {
  double slant = 0.12,
  double degrees = 0,
  double scale = 1,
  double keystone = 0,
  bool glare = false,
  int noise = 10,
  String speed = '00',
  int seed = 1,
}) {
  final c = _Canvas(640, 400);
  final end = c.number('$soc', 40, 50, 64, slant);
  c.percent(end + 6, 50 + 64 - 26, 26, slant);
  final t = c.number('31', 420, 50, 34, slant);
  c.digit('C', t + 8, 50, 34, slant);
  // The speed: the largest digits on the cluster, never the battery.
  c.number(speed, 40, 170, 110, slant);
  c.number('$odo', 250, 290, 56, slant, groupGap: 24);
  c.blur();
  if (glare) c.glare(330, 200, 140, 60);
  c.noise(math.Random(seed), noise);
  return c.transformed(degrees, scale, keystone: keystone);
}

DashboardLayoutReading _readCombined(GrayImage image) =>
    DashboardLayoutParser.combine([
      for (final p in SevenSegmentReader.readPasses(image))
        DashboardLayoutParser.parse(p),
    ]);

void main() {
  const socs = [5, 8, 12, 47, 68, 99, 100];
  const odos = [123, 4818, 25031, 108452];
  // (slant, rotation °, scale, keystone, glare, noise)
  final variants = <(double, double, double, double, bool, int)>[
    (0.12, 0, 1.0, 0, false, 10),
    (0.12, 4, 1.0, 0, false, 10),
    (0.12, -4, 0.8, 0, false, 10),
    (0.0, 0, 0.6, 0, false, 10),
    (0.20, 2, 0.7, 0, false, 10),
    (0.12, 7, 0.9, 0, false, 14),
    (0.12, -7, 0.7, 0.15, false, 10),
    (0.12, 0, 0.5, 0, false, 8),
    (0.12, 3, 0.8, 0.25, true, 12),
    (0.08, -2, 1.0, 0.1, true, 18),
  ];

  test('1–3 digit battery % and 3–6 digit ODO, tilted and small', () {
    var total = 0, socOk = 0, odoOk = 0;
    final misses = <String>[];
    for (final (slant, degrees, scale, keystone, glare, noise) in variants) {
      for (final soc in socs) {
        for (final odo in odos) {
          total++;
          final r = _readCombined(
            _cluster(
              soc,
              odo,
              slant: slant,
              degrees: degrees,
              scale: scale,
              keystone: keystone,
              glare: glare,
              noise: noise,
              speed: total.isEven ? '00' : '25',
              seed: total,
            ),
          );
          if (r.soc == soc) {
            socOk++;
          } else {
            misses.add(
              'soc $soc→${r.soc} @$slant/$degrees°/×$scale/k$keystone${glare ? '/glare' : ''}',
            );
          }
          if (r.odoKm == odo.toDouble()) {
            odoOk++;
          } else {
            misses.add(
              'odo $odo→${r.odoKm} @$slant/$degrees°/×$scale/k$keystone${glare ? '/glare' : ''}',
            );
          }
        }
      }
    }
    // ignore: avoid_print
    print(
      'synthetic: soc $socOk/$total, odo $odoOk/$total\n${misses.take(30).join('\n')}',
    );
    expect(socOk / total, greaterThanOrEqualTo(0.95));
    expect(odoOk / total, greaterThanOrEqualTo(0.95));
  });

  test('frames vote a short misread into the longer number', () {
    final vote = DashboardScanVote();
    for (final soc in [8, 8, 68, 68, 68]) {
      vote.add(
        DashboardLayoutReading(
          soc: soc,
          socConfident: true,
          odoKm: 4818,
          odoConfident: true,
        ),
      );
    }
    expect(vote.socLocked, 68);
    final early = DashboardScanVote();
    for (final soc in [8, 8, 8]) {
      early.add(DashboardLayoutReading(soc: soc, socConfident: true));
    }
    // Three "8" in a row with no longer reading in view is a real 8 %.
    expect(early.socLocked, 8);
    final odo = DashboardScanVote();
    for (final v in [48.0, 4818.0, 48.0, 4818.0]) {
      odo.add(DashboardLayoutReading(odoKm: v, odoConfident: true));
    }
    expect(odo.odoLocked, 4818);
  });

  test('combine keeps the longer reading inside one frame', () {
    final r = DashboardLayoutParser.combine(const [
      DashboardLayoutReading(
        soc: 8,
        socConfident: true,
        odoKm: 4818,
        odoConfident: true,
      ),
      DashboardLayoutReading(
        soc: 68,
        socConfident: true,
        odoKm: 48,
        odoConfident: true,
      ),
      DashboardLayoutReading(soc: 63, odoKm: 4818, odoConfident: true),
    ]);
    expect(r.soc, 68);
    expect(r.odoKm, 4818);
    expect(r.socConfident, isTrue);
  });
}
