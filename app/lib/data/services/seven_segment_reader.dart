import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'dashboard_layout_parser.dart';

/// A grayscale image (one byte per pixel, row-major).
class GrayImage {
  const GrayImage(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;

  /// Upright working image from a camera NV21/YUV luminance plane:
  /// [rotation] (0/90/180/270, clockwise) turns it upright and it is scaled
  /// down to about [targetHeight] pixels tall.
  static GrayImage fromLuminance(
    Uint8List plane, {
    required int width,
    required int height,
    required int bytesPerRow,
    required int rotation,
    int targetHeight = 960,
  }) {
    final quarter = rotation == 90 || rotation == 270;
    final upW = quarter ? height : width;
    final upH = quarter ? width : height;
    final step = math.max(1, (upH / targetHeight).round());
    final outW = upW ~/ step;
    final outH = upH ~/ step;
    final out = Uint8List(outW * outH);
    for (var v = 0; v < outH; v++) {
      for (var u = 0; u < outW; u++) {
        final uu = u * step;
        final vv = v * step;
        int x, y;
        switch (rotation) {
          case 90:
            x = vv;
            y = height - 1 - uu;
          case 180:
            x = width - 1 - uu;
            y = height - 1 - vv;
          case 270:
            x = width - 1 - vv;
            y = uu;
          default:
            x = uu;
            y = vv;
        }
        out[v * outW + u] = plane[y * bytesPerRow + x];
      }
    }
    return GrayImage(outW, outH, out);
  }

  /// iOS camera frames: BGRA, rotated upright and scaled like
  /// [fromLuminance].
  static GrayImage fromBgra(
    Uint8List bgra, {
    required int width,
    required int height,
    required int bytesPerRow,
    required int rotation,
    int targetHeight = 960,
  }) {
    final luma = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * bytesPerRow + x * 4;
        luma[y * width + x] =
            (bgra[i + 2] * 77 + bgra[i + 1] * 150 + bgra[i] * 29) >> 8;
      }
    }
    return fromLuminance(
      luma,
      width: width,
      height: height,
      bytesPerRow: width,
      rotation: rotation,
      targetHeight: targetHeight,
    );
  }

  /// This image turned by [degrees] clockwise (a photo whose orientation
  /// is unknown is tried every way round).
  GrayImage rotated(int degrees) => degrees % 360 == 0
      ? this
      : fromLuminance(
          pixels,
          width: width,
          height: height,
          bytesPerRow: width,
          rotation: degrees % 360,
          targetHeight: (degrees % 180 == 0 ? height : width),
        );

  /// From RGBA bytes (a decoded photo), scaled to about [targetHeight].
  static GrayImage fromRgba(
    Uint8List rgba,
    int width,
    int height, {
    int targetHeight = 960,
  }) {
    final step = math.max(1, (height / targetHeight).round());
    final outW = width ~/ step;
    final outH = height ~/ step;
    final out = Uint8List(outW * outH);
    for (var v = 0; v < outH; v++) {
      for (var u = 0; u < outW; u++) {
        final i = ((v * step) * width + u * step) * 4;
        out[v * outW + u] =
            (rgba[i] * 77 + rgba[i + 1] * 150 + rgba[i + 2] * 29) >> 8;
      }
    }
    return GrayImage(outW, outH, out);
  }
}

/// Reads seven-segment LCD digits (QA 131). On-device text recognition
/// reads the cluster's printed labels ("ODO", "KM", "KM/H") but not its
/// segment digits — "68" came back as "58." or nothing, the ODO never.
/// This finds the lit segments directly: bright strokes on the dark LCD,
/// grouped into digit cells, each cell decoded from its seven segments
/// (italic slant allowed). It returns tokens for [DashboardLayoutParser]:
/// numbers, "%" and the temperature "C". Pure Dart; runs in an isolate.
abstract final class SevenSegmentReader {
  /// Tokens in [image] coordinates.
  static List<OcrToken> read(GrayImage image) {
    var tokens = _read(image, 19);
    // Phone held close: big digits need a wider local window, or thick
    // segments turn hollow.
    final heights = [
      for (final t in tokens)
        if (t.text.length >= 2 && RegExp(r'^\d+$').hasMatch(t.text))
          t.box.height,
    ]..sort();
    if (heights.isNotEmpty && heights[heights.length ~/ 2] > 60) {
      tokens = _read(image, 35);
    }
    return tokens;
  }

  static const _patterns = <int, String>{
    // bits a b c d e f g (a = 64 … g = 1)
    0x7E: '0', 0x30: '1', 0x6D: '2', 0x79: '3', 0x33: '4', 0x5B: '5',
    0x5F: '6', 0x1F: '6', 0x70: '7', 0x72: '7', 0x7F: '8', 0x7B: '9',
    0x73: '9', 0x4E: 'C',
  };

  // u0, u1, v0, v1 per segment a…g.
  static const _zones = <List<double>>[
    [0.28, 0.72, 0.00, 0.16], // a
    [0.74, 1.00, 0.14, 0.42], // b
    [0.74, 1.00, 0.58, 0.86], // c
    [0.28, 0.72, 0.84, 1.00], // d
    [0.00, 0.26, 0.58, 0.86], // e
    [0.00, 0.26, 0.14, 0.42], // f
    [0.28, 0.72, 0.42, 0.58], // g
  ];
  static const _holes = <List<double>>[
    [0.32, 0.68, 0.22, 0.36],
    [0.32, 0.68, 0.64, 0.78],
  ];

  static List<OcrToken> _read(GrayImage image, int window) {
    final w = image.width, h = image.height;
    final mask = _binarize(image, window);
    final labels = Int32List(w * h);
    final blobs = <_Blob>[];
    final stack = <int>[];
    var next = 0;
    for (var start = 0; start < w * h; start++) {
      if (mask[start] == 0 || labels[start] != 0) continue;
      next++;
      final blob = _Blob(next, start % w, start ~/ w);
      labels[start] = next;
      stack.add(start);
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        final px = p % w, py = p ~/ w;
        blob.add(px, py);
        for (var dy = -1; dy <= 1; dy++) {
          final ny = py + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = px + dx;
            if (nx < 0 || nx >= w) continue;
            final q = ny * w + nx;
            if (mask[q] != 0 && labels[q] == 0) {
              labels[q] = next;
              stack.add(q);
            }
          }
        }
      }
      final bw = blob.width, bh = blob.height;
      if (blob.area < 12 || bw * bh > w * h * 0.02) continue;
      final thick = blob.area / math.max(bw, bh);
      // Long thin strokes: frame curves, underlines, bezels.
      if (math.max(bw, bh) / math.max(thick, 0.5) > 12) continue;
      // Sparse boxes: the arcs around the ODO digits.
      if (math.max(bw, bh) > 12 && blob.area / (bw * bh) < 0.2) continue;
      blob.thick = thick;
      blobs.add(blob);
    }

    // Join segments of one digit: boxes that nearly touch.
    final parent = List<int>.generate(blobs.length, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    for (var i = 0; i < blobs.length; i++) {
      final a = blobs[i];
      for (var j = i + 1; j < blobs.length; j++) {
        final b = blobs[j];
        final tm = math.min(a.thick, b.thick);
        final tx = 0.7 * tm + 1;
        var ty = tx;
        // The upper and lower strokes of a "1" stand further apart.
        final va = a.height >= 1.5 * a.width;
        final vb = b.height >= 1.5 * b.width;
        final overlap = math.min(a.x1, b.x1) - math.max(a.x0, b.x0);
        if (va && vb && overlap >= 0.5 * math.min(a.width, b.width)) {
          ty = 1.6 * tm + 1;
        }
        if (a.x0 - tx <= b.x1 &&
            b.x0 - tx <= a.x1 &&
            a.y0 - ty <= b.y1 &&
            b.y0 - ty <= a.y1) {
          final pa = find(i), pb = find(j);
          if (pa != pb) parent[pa] = pb;
        }
      }
    }
    final groups = <int, List<_Blob>>{};
    for (var i = 0; i < blobs.length; i++) {
      groups.putIfAbsent(find(i), () => []).add(blobs[i]);
    }

    final pieces = <_Piece>[];
    final loose = <Rect>[];
    for (final group in groups.values) {
      final box = _Piece.of(group);
      if (box.height < 14) {
        if (box.height >= 6) loose.add(box.rect);
        continue;
      }
      if (box.width > 0.95 * box.height) {
        pieces.addAll(_splitColumns(box, labels, w));
      } else {
        pieces.add(box);
      }
    }

    final cells = <_Cell>[];
    for (final piece in pieces) {
      final ph = piece.height, pw = piece.width;
      if (ph < 10 || piece.members.isEmpty) continue;
      final thicks = [for (final b in piece.members) b.thick]..sort();
      final thick = thicks[thicks.length ~/ 2];
      if (pw < 0.42 * ph) {
        if (ph > 2.5 * pw &&
            ph >= 18 &&
            thick >= 2 &&
            piece.members.length <= 3) {
          cells.add(_Cell('1', piece.rect));
        }
        continue;
      }
      if (pw > 1.0 * ph && !(ph >= 0.8 * pw && piece.members.length >= 3)) {
        continue;
      }
      final ch = _decode(mask, w, h, piece);
      if (ch != null) {
        cells.add(_Cell(ch, piece.rect));
      } else {
        loose.add(piece.rect);
      }
    }
    cells.sort((a, b) => a.box.left.compareTo(b.box.left));

    // Digits on one row form a number.
    final runs = <_Run>[];
    for (final cell in cells) {
      final ch = cell.text;
      final box = cell.box;
      final cellH = box.height;
      final vLeft = ch == '1' ? box.right - 0.6 * cellH : box.left;
      var joined = false;
      for (final run in runs) {
        final last = run.boxes.last;
        final lastH = last.height;
        final sameRow =
            (box.center.dy - last.center.dy).abs() <
            0.3 * math.max(cellH, lastH);
        final ratio = cellH / lastH;
        final small = ch == 'C' && ratio > 0.3 && ratio < 1.3;
        final gap = vLeft - last.right;
        if (sameRow &&
            ((ratio > 0.75 && ratio < 1.33) || small) &&
            gap > -0.3 * lastH &&
            gap < 1.0 * lastH) {
          run.text += ch;
          run.boxes.add(box);
          joined = true;
          break;
        }
      }
      if (!joined) runs.add(_Run(ch, box));
    }

    // A small glyph just right of a number on its baseline is the "%"
    // (it decodes as a random digit, or not at all).
    final big = [
      for (final r in runs)
        if (r.boxes.first.height >= 18) r,
    ];
    final candidates = <(Rect, _Run?)>[
      for (final r in runs)
        if (r.text.length == 1 && !big.contains(r)) (r.boxes.first, r),
      for (final rect in loose) (rect, null),
    ];
    final percents = <Rect>[];
    for (final (rect, run) in candidates) {
      for (final target in big) {
        final tb = target.rect;
        final th = tb.height;
        if (rect.height >= 0.25 * th &&
            rect.height <= 0.65 * th &&
            rect.left - tb.right >= -0.2 * th &&
            rect.left - tb.right <= 0.9 * th &&
            (rect.bottom - tb.bottom).abs() <= 0.3 * th) {
          if (run != null) runs.remove(run);
          percents.add(rect);
          break;
        }
      }
    }

    return [
      for (final r in runs)
        if (r.text != '1' || r.boxes.first.height >= 18)
          OcrToken(r.text, r.rect),
      for (final p in percents) OcrToken('%', p),
    ];
  }

  static Uint8List _binarize(GrayImage image, int window) {
    final w = image.width, h = image.height, px = image.pixels;
    // Integral image for the local mean.
    final integral = Int64List((w + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var row = 0;
      for (var x = 0; x < w; x++) {
        row += px[y * w + x];
        integral[(y + 1) * (w + 1) + x + 1] =
            integral[y * (w + 1) + x + 1] + row;
      }
    }
    final r = window ~/ 2;
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - r), y1 = math.min(h, y + r + 1);
      for (var x = 0; x < w; x++) {
        final v = px[y * w + x];
        if (v <= 100) continue;
        final x0 = math.max(0, x - r), x1 = math.min(w, x + r + 1);
        final sum =
            integral[y1 * (w + 1) + x1] -
            integral[y0 * (w + 1) + x1] -
            integral[y1 * (w + 1) + x0] +
            integral[y0 * (w + 1) + x0];
        final mean = sum / ((x1 - x0) * (y1 - y0));
        if (v > mean + 28) out[y * w + x] = 1;
      }
    }
    return out;
  }

  /// Splits a too-wide group at empty columns ("18", "°C" stuck together).
  static List<_Piece> _splitColumns(_Piece box, Int32List labels, int w) {
    final ids = {for (final b in box.members) b.id};
    final x0 = box.x0, y0 = box.y0;
    final cols = List<bool>.filled(box.width, false);
    for (var y = y0; y < box.y1; y++) {
      for (var x = x0; x < box.x1; x++) {
        if (ids.contains(labels[y * w + x])) cols[x - x0] = true;
      }
    }
    final out = <_Piece>[];
    int? start;
    for (var cx = 0; cx <= cols.length; cx++) {
      final on = cx < cols.length && cols[cx];
      if (on && start == null) {
        start = cx;
      } else if (!on && start != null) {
        var top = box.y1, bottom = y0;
        for (var y = y0; y < box.y1; y++) {
          for (var x = x0 + start; x < x0 + cx; x++) {
            if (ids.contains(labels[y * w + x])) {
              if (y < top) top = y;
              if (y + 1 > bottom) bottom = y + 1;
              break;
            }
          }
        }
        final members = [
          for (final b in box.members)
            if (b.x0 < x0 + cx && b.x1 > x0 + start) b,
        ];
        if (bottom > top) {
          out.add(_Piece(x0 + start, top, x0 + cx, bottom, members));
        }
        start = null;
      }
    }
    return out;
  }

  static String? _decode(Uint8List mask, int w, int h, _Piece cell) {
    final x0 = cell.x0.toDouble(), y0 = cell.y0.toDouble();
    final cellH = cell.height.toDouble(), cellW = cell.width.toDouble();
    final cy = (cell.y0 + cell.y1) / 2;
    String? best;
    var bestConf = -1.0;
    for (final slant in const [0.0, 0.07, 0.14, 0.21]) {
      final cw = cellW - slant * cellH;
      if (cw <= 0) continue;
      final left = x0 + slant * cellH / 2;
      var bits = 0;
      var conf = 0.0;
      for (final z in _zones) {
        final f = _frac(
          mask,
          w,
          h,
          left + z[0] * cw,
          left + z[1] * cw,
          y0 + z[2] * cellH,
          y0 + z[3] * cellH,
          slant,
          cy,
        );
        bits = (bits << 1) | (f >= 0.32 ? 1 : 0);
        conf += (f - 0.32).abs();
      }
      var ch = _patterns[bits];
      if (ch == '0' || ch == '8') {
        for (final z in _holes) {
          final f = _frac(
            mask,
            w,
            h,
            left + z[0] * cw,
            left + z[1] * cw,
            y0 + z[2] * cellH,
            y0 + z[3] * cellH,
            slant,
            cy,
          );
          if (f > 0.18) ch = null;
        }
      }
      if (ch != null && conf > bestConf) {
        best = ch;
        bestConf = conf;
      }
    }
    return best;
  }

  /// Lit fraction of a box sheared by [slant] around row [cy].
  static double _frac(
    Uint8List mask,
    int w,
    int h,
    double x0,
    double x1,
    double y0,
    double y1,
    double slant,
    double cy,
  ) {
    var total = 0, lit = 0;
    final yEnd = y1.ceil();
    for (var y = y0.toInt(); y < yEnd; y++) {
      if (y < 0 || y >= h) continue;
      final dx = slant * (cy - y);
      final a = math.max(0, (x0 + dx).round());
      final b = math.min(w, (x1 + dx).round());
      for (var x = a; x < b; x++) {
        total++;
        lit += mask[y * w + x];
      }
    }
    return total == 0 ? 0 : lit / total;
  }
}

class _Blob {
  _Blob(this.id, int x, int y) : x0 = x, x1 = x + 1, y0 = y, y1 = y + 1;

  final int id;
  int x0, x1, y0, y1;
  int area = 0;
  double thick = 0;

  int get width => x1 - x0;
  int get height => y1 - y0;

  void add(int x, int y) {
    area++;
    if (x < x0) x0 = x;
    if (x + 1 > x1) x1 = x + 1;
    if (y < y0) y0 = y;
    if (y + 1 > y1) y1 = y + 1;
  }
}

class _Piece {
  _Piece(this.x0, this.y0, this.x1, this.y1, this.members);

  factory _Piece.of(List<_Blob> group) => _Piece(
    group.map((b) => b.x0).reduce(math.min),
    group.map((b) => b.y0).reduce(math.min),
    group.map((b) => b.x1).reduce(math.max),
    group.map((b) => b.y1).reduce(math.max),
    group,
  );

  final int x0, y0, x1, y1;
  final List<_Blob> members;

  int get width => x1 - x0;
  int get height => y1 - y0;
  Rect get rect =>
      Rect.fromLTRB(x0.toDouble(), y0.toDouble(), x1.toDouble(), y1.toDouble());
}

class _Cell {
  _Cell(this.text, this.box);

  final String text;
  final Rect box;
}

class _Run {
  _Run(this.text, Rect first) : boxes = [first];

  String text;
  final List<Rect> boxes;

  Rect get rect => boxes.reduce((a, b) => a.expandToInclude(b));
}
