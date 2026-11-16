import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'dashboard_layout_parser.dart';
import 'dashboard_templates.dart';

/// QA 159: a part of the camera frame cut again at a better size. Pixel p
/// of [image] sits at [origin] + p / [scale] in the image read first.
typedef Recut = ({GrayImage image, Offset origin, double scale});

/// Cuts [box] (coordinates of the image read first) again from the camera
/// frame, [side] pixels on its long side; null when it cannot.
typedef RecutFn = Recut? Function(Rect box, int side);

/// One frame's reading (QA 156) and, with a template, where its glass was
/// found and the angle it was turned level by (QA 159).
typedef FrameScan = ({
  DashboardLayoutReading reading,
  bool hasDigits,
  Rect? glass,
  double angle,
});

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

  /// This image turned by a small angle [degrees] (clockwise) about its
  /// centre onto a canvas just big enough for all of it (a same-size turn
  /// cut the corners, where the % and the ODO sit), bilinear so LCD
  /// segments keep their edges; the new corners are dark (unlit). QA 140:
  /// a phone held a few degrees off level slopes the digit rows and the %
  /// or ODO went unread.
  GrayImage rotatedBy(double degrees) {
    if (degrees == 0) return this;
    final rad = degrees * math.pi / 180;
    final cosA = math.cos(rad), sinA = math.sin(rad);
    final outW = (width * cosA.abs() + height * sinA.abs()).ceil();
    final outH = (width * sinA.abs() + height * cosA.abs()).ceil();
    final cx = (width - 1) / 2, cy = (height - 1) / 2;
    final ox = (outW - 1) / 2, oy = (outH - 1) / 2;
    final out = Uint8List(outW * outH);
    for (var y = 0; y < outH; y++) {
      final dy = y - oy;
      for (var x = 0; x < outW; x++) {
        final dx = x - ox;
        // Source point: the output rotated back by -degrees.
        final sx = cosA * dx + sinA * dy + cx;
        final sy = -sinA * dx + cosA * dy + cy;
        final x0 = sx.floor(), y0 = sy.floor();
        if (x0 < 0 || y0 < 0 || x0 >= width - 1 || y0 >= height - 1) continue;
        final fx = sx - x0, fy = sy - y0;
        final i = y0 * width + x0;
        final top = pixels[i] + (pixels[i + 1] - pixels[i]) * fx;
        final bottom =
            pixels[i + width] +
            (pixels[i + width + 1] - pixels[i + width]) * fx;
        out[y * outW + x] = (top + (bottom - top) * fy).round();
      }
    }
    return GrayImage(outW, outH, out);
  }

  /// QA 156: a dim frame (dusk, a garage) brought up so its brightest
  /// pixels are near white. The reader's thresholds are absolute: at
  /// half the light thin segments fell under them and "68" read "63".
  /// A frame that is already bright comes back unchanged.
  GrayImage stretched() {
    final histogram = Int32List(256);
    for (final p in pixels) {
      histogram[p]++;
    }
    // The level only 0.3 % of the pixels exceed: the lit segments.
    var left = (pixels.length * 0.003).ceil();
    var hi = 255;
    while (hi > 0 && (left -= histogram[hi]) > 0) {
      hi--;
    }
    if (hi >= 215 || hi < 24) return this;
    final gain = math.min(3.0, 235 / hi);
    final table = Uint8List(256);
    for (var v = 0; v < 256; v++) {
      table[v] = math.min(255, (v * gain).round());
    }
    final out = Uint8List(pixels.length);
    for (var i = 0; i < pixels.length; i++) {
      out[i] = table[pixels[i]];
    }
    return GrayImage(width, height, out);
  }

  /// [box] of this image resampled to [side] pixels on its long side,
  /// bilinear; larger than the box when [upscale] (QA 159: small digits read
  /// at the size the decoder was tuned for). Null for an empty box.
  Recut? region(Rect box, int side, {bool upscale = true}) {
    final left = box.left.clamp(0.0, width.toDouble());
    final top = box.top.clamp(0.0, height.toDouble());
    final right = box.right.clamp(0.0, width.toDouble());
    final bottom = box.bottom.clamp(0.0, height.toDouble());
    final w = right - left, h = bottom - top;
    if (w < 4 || h < 4) return null;
    var scale = side / math.max(w, h);
    if (!upscale) scale = math.min(1.0, scale);
    final outW = math.max(1, (w * scale).round());
    final outH = math.max(1, (h * scale).round());
    final out = Uint8List(outW * outH);
    for (var v = 0; v < outH; v++) {
      final y = (top + (v + 0.5) / scale - 0.5).clamp(0.0, height - 1.001);
      final y0 = y.floor();
      final fy = y - y0;
      for (var u = 0; u < outW; u++) {
        final x = (left + (u + 0.5) / scale - 0.5).clamp(0.0, width - 1.001);
        final x0 = x.floor();
        final fx = x - x0;
        final i = y0 * width + x0;
        final top0 = pixels[i] + (pixels[i + 1] - pixels[i]) * fx;
        final bottom0 =
            pixels[i + width] +
            (pixels[i + width + 1] - pixels[i + width]) * fx;
        out[v * outW + u] = (top0 + (bottom0 - top0) * fy).round();
      }
    }
    return (
      image: GrayImage(outW, outH, out),
      origin: Offset(left, top),
      scale: scale,
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

  /// The part of a camera frame inside [roi] (fractions of the upright
  /// frame), at full sensor resolution up to [maxSide] pixels (QA 135).
  /// Reading only the guide window keeps the LCD digits two to three times
  /// larger than shrinking the whole 1080p frame did, and drops the clutter
  /// around the cluster. Bilinear, so small digits keep their edges.
  static GrayCrop crop(
    Uint8List bytes, {
    required int width,
    required int height,
    required int bytesPerRow,
    required int rotation,
    required bool bgra,
    required Rect roi,
    int maxSide = 720,
    bool upscale = false,
  }) {
    final quarter = rotation == 90 || rotation == 270;
    final upW = quarter ? height : width;
    final upH = quarter ? width : height;
    final left = (roi.left.clamp(0.0, 1.0) * upW).toDouble();
    final top = (roi.top.clamp(0.0, 1.0) * upH).toDouble();
    final right = (roi.right.clamp(0.0, 1.0) * upW).toDouble();
    final bottom = (roi.bottom.clamp(0.0, 1.0) * upH).toDouble();
    final cropW = math.max(1.0, right - left),
        cropH = math.max(1.0, bottom - top);
    // QA 159: a second, closer look may enlarge (bilinear) so the digits
    // reach the size the decoder was tuned for.
    final fit = maxSide / math.max(cropW, cropH);
    final scale = upscale ? fit : math.min(1.0, fit);
    final outW = math.max(1, (cropW * scale).round());
    final outH = math.max(1, (cropH * scale).round());
    int luma(int x, int y) {
      if (x < 0) x = 0;
      if (y < 0) y = 0;
      if (x >= width) x = width - 1;
      if (y >= height) y = height - 1;
      if (!bgra) return bytes[y * bytesPerRow + x];
      final i = y * bytesPerRow + x * 4;
      return (bytes[i + 2] * 77 + bytes[i + 1] * 150 + bytes[i] * 29) >> 8;
    }

    final out = Uint8List(outW * outH);
    for (var v = 0; v < outH; v++) {
      final uy = top + (v + 0.5) / scale - 0.5;
      for (var u = 0; u < outW; u++) {
        final ux = left + (u + 0.5) / scale - 0.5;
        // Upright (ux, uy) → sensor (sx, sy), as in [fromLuminance].
        final double sx, sy;
        switch (rotation) {
          case 90:
            sx = uy;
            sy = height - 1 - ux;
          case 180:
            sx = width - 1 - ux;
            sy = height - 1 - uy;
          case 270:
            sx = width - 1 - uy;
            sy = ux;
          default:
            sx = ux;
            sy = uy;
        }
        final x0 = sx.floor(), y0 = sy.floor();
        final fx = sx - x0, fy = sy - y0;
        final value =
            luma(x0, y0) * (1 - fx) * (1 - fy) +
            luma(x0 + 1, y0) * fx * (1 - fy) +
            luma(x0, y0 + 1) * (1 - fx) * fy +
            luma(x0 + 1, y0 + 1) * fx * fy;
        out[v * outW + u] = value.round();
      }
    }
    return GrayCrop(GrayImage(outW, outH, out), left, top, scale);
  }

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

/// A [GrayImage] cut from a larger upright frame: [toFrame] maps a box
/// found in the crop back to the frame (to outline it on the preview).
class GrayCrop {
  const GrayCrop(this.image, this.left, this.top, this.scale);

  final GrayImage image;
  final double left, top, scale;

  Rect toFrame(Rect box) => Rect.fromLTRB(
    left + box.left / scale,
    top + box.top / scale,
    left + box.right / scale,
    top + box.bottom / scale,
  );
}

/// Reads seven-segment LCD digits (QA 131). On-device text recognition
/// reads the cluster's printed labels ("ODO", "KM", "KM/H") but not its
/// segment digits — "68" came back as "58." or nothing, the ODO never.
/// This finds the lit segments directly: bright strokes on the dark LCD,
/// grouped into digit cells, each cell decoded from its seven segments
/// (italic slant allowed). It returns tokens for [DashboardLayoutParser]:
/// numbers, "%" and the temperature "C". Pure Dart; runs in an isolate.
abstract final class SevenSegmentReader {
  /// Tokens in [image] coordinates (one pass at the default threshold).
  static List<OcrToken> read(GrayImage image) => readPasses(image).first;

  /// Battery % and ODO in [image]: every pass parsed, then their consensus
  /// (QA 135). [lastOdoKm] anchors the ODO when the label is unreadable.
  static DashboardLayoutReading readDashboard(
    GrayImage image, {
    double? lastOdoKm,
  }) {
    // QA 156: a dim photo brought up and a tilted one turned level first,
    // like a camera frame.
    final bright = image.stretched();
    final angle = levelAngle(bright);
    if (angle == 0) return _readLevel(bright, lastOdoKm: lastOdoKm);
    final level = bright.rotatedBy(angle);
    return _unrotated(
      _readLevel(level, lastOdoKm: lastOdoKm),
      angle,
      image,
      level,
    );
  }

  static DashboardLayoutReading _readLevel(
    GrayImage image, {
    double? lastOdoKm,
  }) {
    final passes = [
      for (final pass in readPasses(image))
        DashboardLayoutParser.parse(pass, lastOdoKm: lastOdoKm),
    ];
    final straight = DashboardLayoutParser.combine(passes);
    // A one-digit % is rare and is what a tilted "12" or "100" loses down
    // to: let the turned copies vote on it too.
    final shortSoc = straight.soc != null && straight.soc! < 10;
    if (_score(straight) >= _complete && !shortSoc) return straight;
    // QA 140: the phone a little off level. Turned copies vote with the
    // level passes (a level pass of a tilted "12" read a confident "1";
    // the longer number wins the vote, as between thresholds).
    final turned = <(double, DashboardLayoutReading)>[];
    for (final angle in tiltAngles) {
      final copy = image.rotatedBy(angle);
      for (final pass in readPasses(copy)) {
        turned.add((
          angle,
          _unrotated(
            DashboardLayoutParser.parse(pass, lastOdoKm: lastOdoKm),
            angle,
            image,
            copy,
          ),
        ));
      }
    }
    return DashboardLayoutParser.combine([
      ...passes,
      for (final (_, reading) in turned) reading,
    ]);
  }

  /// QA 156: one camera frame, the way the scanner reads it: every
  /// threshold pass parsed (by zone when the owner lines the cluster up
  /// with [template], whose glass is [window] in [image]), then their
  /// consensus. The scanner and the accuracy benchmark both call this.
  ///
  /// QA 159: with a template, the glass is found from the speed digits;
  /// when it is small in [image] (the phone held far) and [recut] can cut
  /// the camera frame again, the glass is read a second time at the size
  /// the decoder was tuned for. The % comes only from that second reading.
  /// [FrameScan.glass] is where the glass was found, in [image].
  static FrameScan scanFrame(
    GrayImage image, {
    DashboardTemplate? template,
    Rect? window,
    double? lastOdoKm,
    RecutFn? recut,
  }) {
    final first = _scanOnce(
      image,
      template: template,
      window: window,
      lastOdoKm: lastOdoKm,
    );
    final glass = first.glass;
    if (template == null || recut == null || glass == null) return first;
    final tilt = math.sin(first.angle.abs() * math.pi / 180);
    final box = Rect.fromLTRB(
      glass.left - 0.06 * glass.width - tilt * glass.height / 2,
      glass.top - 0.08 * glass.height - tilt * glass.width / 2,
      glass.right + 0.06 * glass.width + tilt * glass.height / 2,
      glass.bottom + 0.08 * glass.height + tilt * glass.width / 2,
    );
    // A second read when it makes the digits clearly larger, or when the
    // first one gave no % (on the owner's 37 % the "3" ran into the battery
    // icon; the camera's own pixels part them more often). A frame read
    // well the first time stays fast.
    if (frameSide / math.max(box.width, box.height) < recutGain &&
        first.reading.soc != null) {
      return first;
    }
    final cut = recut(box, frameSide);
    if (cut == null) return first;
    Rect toCut(Rect r) => Rect.fromLTRB(
      (r.left - cut.origin.dx) * cut.scale,
      (r.top - cut.origin.dy) * cut.scale,
      (r.right - cut.origin.dx) * cut.scale,
      (r.bottom - cut.origin.dy) * cut.scale,
    );
    Rect? back(Rect? r) => r == null
        ? null
        : Rect.fromLTRB(
            cut.origin.dx + r.left / cut.scale,
            cut.origin.dy + r.top / cut.scale,
            cut.origin.dx + r.right / cut.scale,
            cut.origin.dy + r.bottom / cut.scale,
          );
    final second = _scanOnce(
      cut.image,
      template: template,
      window: toCut(glass),
      lastOdoKm: lastOdoKm,
    );
    if (!second.hasDigits) return first;
    final a = second.reading, b = first.reading;
    final odo = a.odoKm != null;
    final temp = a.tempC != null;
    return (
      reading: DashboardLayoutReading(
        // The % only from the closer look: the far one is what read "7".
        soc: a.soc,
        socBox: back(a.socBox),
        socConfident: a.socConfident,
        socCandidates: a.socCandidates,
        odoKm: odo ? a.odoKm : b.odoKm,
        odoBox: odo ? back(a.odoBox) : b.odoBox,
        odoConfident: odo ? a.odoConfident : b.odoConfident,
        odoCandidates: odo ? a.odoCandidates : b.odoCandidates,
        tempC: temp ? a.tempC : b.tempC,
        tempBox: temp ? back(a.tempBox) : b.tempBox,
        tempConfident: temp ? a.tempConfident : b.tempConfident,
      ),
      hasDigits: true,
      glass: back(second.glass) ?? glass,
      angle: first.angle,
    );
  }

  /// A second read happens when it makes the glass at least this much
  /// larger, or when the first read has no % (QA 159).
  static const recutGain = 1.25;

  /// One read of [image]: brightened, turned level, every pass parsed.
  static FrameScan _scanOnce(
    GrayImage image, {
    DashboardTemplate? template,
    Rect? window,
    double? lastOdoKm,
  }) {
    // QA 156: bring a dim frame up, then turn it level. A phone held a
    // few degrees off lost one digit of "68" in four frames out of ten.
    final bright = image.stretched();
    final angle = levelAngle(bright);
    if (angle != 0) {
      final level = bright.rotatedBy(angle);
      final rad = angle * math.pi / 180;
      final cosA = math.cos(rad), sinA = math.sin(rad);
      final cx = (image.width - 1) / 2, cy = (image.height - 1) / 2;
      final ox = (level.width - 1) / 2, oy = (level.height - 1) / 2;
      Rect? turned;
      if (window != null) {
        final dx = window.center.dx - cx, dy = window.center.dy - cy;
        turned = Rect.fromCenter(
          center: Offset(
            cosA * dx - sinA * dy + ox,
            sinA * dx + cosA * dy + oy,
          ),
          width: window.width,
          height: window.height,
        );
      }
      final scan = _scanLevel(
        level,
        template: template,
        window: turned,
        lastOdoKm: lastOdoKm,
      );
      Rect? back(Rect? box) {
        if (box == null) return null;
        final dx = box.center.dx - ox, dy = box.center.dy - oy;
        return Rect.fromCenter(
          center: Offset(
            cosA * dx + sinA * dy + cx,
            -sinA * dx + cosA * dy + cy,
          ),
          width: box.width,
          height: box.height,
        );
      }

      final r = scan.reading;
      return (
        reading: DashboardLayoutReading(
          soc: r.soc,
          odoKm: r.odoKm,
          socBox: back(r.socBox),
          odoBox: back(r.odoBox),
          socConfident: r.socConfident,
          odoConfident: r.odoConfident,
          socCandidates: r.socCandidates,
          odoCandidates: r.odoCandidates,
          tempC: r.tempC,
          tempBox: back(r.tempBox),
          tempConfident: r.tempConfident,
        ),
        hasDigits: scan.hasDigits,
        glass: back(scan.glass),
        angle: angle,
      );
    }
    return _scanLevel(
      bright,
      template: template,
      window: window,
      lastOdoKm: lastOdoKm,
    );
  }

  /// The angle (degrees, for [GrayImage.rotatedBy]) that turns [image]
  /// level, or 0 when it already is or nothing tells. An LCD is rows:
  /// digit bars, the battery bars, the underline. Turned level, the lit
  /// pixels pile up on a few rows; the angle with the sharpest pile wins.
  static double levelAngle(GrayImage image, {double maxDegrees = 12}) {
    final w = image.width, h = image.height;
    final mask = _binarize(image, 19, offset: 36, floor: 100);
    var lit = 0;
    for (final m in mask) {
      lit += m;
    }
    if (lit < 200) return 0;
    final stride = math.max(1, lit ~/ 9000);
    final xs = <double>[], ys = <double>[];
    var seen = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (mask[y * w + x] == 0) continue;
        if (seen++ % stride != 0) continue;
        xs.add(x - w / 2);
        ys.add(y - h / 2);
      }
    }
    final span = (w + h).toDouble();
    final bins = Int32List(span.ceil() + 2);
    double sharpness(double degrees) {
      final rad = degrees * math.pi / 180;
      final s = math.sin(rad), c = math.cos(rad);
      bins.fillRange(0, bins.length, 0);
      for (var i = 0; i < xs.length; i++) {
        bins[(s * xs[i] + c * ys[i] + span / 2).round()]++;
      }
      var sum = 0.0;
      for (final b in bins) {
        sum += b * b;
      }
      return sum;
    }

    final flat = sharpness(0);
    var best = 0.0, bestScore = flat;
    for (var a = -maxDegrees; a <= maxDegrees; a += 1) {
      final score = sharpness(a);
      if (score > bestScore) {
        bestScore = score;
        best = a;
      }
    }
    final coarse = best;
    for (final d in const [-0.5, 0.5]) {
      final score = sharpness(coarse + d);
      if (score > bestScore) {
        bestScore = score;
        best = coarse + d;
      }
    }
    // Turning costs sharpness (resampling): only for a clear gain.
    if (best.abs() < 1 || bestScore < 1.06 * flat) return 0;
    return best;
  }

  static FrameScan _scanLevel(
    GrayImage image, {
    DashboardTemplate? template,
    Rect? window,
    double? lastOdoKm,
  }) {
    final passes = readPasses(image);
    final hasDigits = passes.any(
      (p) => p.any((t) => RegExp(r'\d').hasMatch(t.text)),
    );
    // QA 159: start from the glass the speed digits show, when they do.
    final located = template != null && window != null
        ? DashboardLayoutParser.locateGlass(
            passes,
            template: template,
            window: window,
          )
        : null;
    // QA 160: the speed digits' glass is checked against the owner's
    // window: whichever puts more numbers in their zones wins (on the
    // owner's 2.1.6 scans the % was found and the ODO and temperature
    // were not). A tie stays with the speed digits.
    Rect? fitted;
    if (template != null && window != null) {
      final fromWindow = DashboardLayoutParser.fitWindowScored(
        passes,
        template: template,
        window: window,
      );
      fitted = fromWindow.window;
      if (located != null) {
        final fromSpeed = DashboardLayoutParser.fitWindowScored(
          passes,
          template: template,
          window: located,
        );
        if (fromSpeed.score >= fromWindow.score - 0.5) {
          fitted = fromSpeed.window;
        }
      }
    }
    final reading = DashboardLayoutParser.combine([
      for (final p in passes)
        template != null && fitted != null
            ? DashboardLayoutParser.parseTemplate(
                p,
                template: template,
                window: fitted,
                lastOdoKm: lastOdoKm,
              )
            : DashboardLayoutParser.parse(p, lastOdoKm: lastOdoKm),
    ]);
    return (reading: reading, hasDigits: hasDigits, glass: fitted, angle: 0.0);
  }

  static DashboardLayoutReading readFrame(
    GrayImage image, {
    DashboardTemplate? template,
    Rect? window,
    double? lastOdoKm,
    RecutFn? recut,
  }) => scanFrame(
    image,
    template: template,
    window: window,
    lastOdoKm: lastOdoKm,
    recut: recut,
  ).reading;

  /// Tried in order when the level image misses the % or the ODO.
  static const tiltAngles = <double>[-6, 6, -12, 12];

  /// Both numbers found and confident.
  static const _complete = 4;

  /// Found % and ODO count 1 each, a confident one 2.
  static int _score(DashboardLayoutReading r) =>
      (r.soc == null ? 0 : (r.socConfident ? 2 : 1)) +
      (r.odoKm == null ? 0 : (r.odoConfident ? 2 : 1));

  /// Boxes found on the turned image moved back onto the camera frame.
  static DashboardLayoutReading _unrotated(
    DashboardLayoutReading r,
    double degrees,
    GrayImage source,
    GrayImage turned,
  ) {
    Rect? back(Rect? box) {
      if (box == null) return null;
      final rad = degrees * math.pi / 180;
      final cx = (source.width - 1) / 2, cy = (source.height - 1) / 2;
      final dx = box.center.dx - (turned.width - 1) / 2;
      final dy = box.center.dy - (turned.height - 1) / 2;
      final x = math.cos(rad) * dx + math.sin(rad) * dy + cx;
      final y = -math.sin(rad) * dx + math.cos(rad) * dy + cy;
      return Rect.fromCenter(
        center: Offset(x, y),
        width: box.width,
        height: box.height,
      );
    }

    return DashboardLayoutReading(
      soc: r.soc,
      odoKm: r.odoKm,
      socBox: back(r.socBox),
      odoBox: back(r.odoBox),
      socConfident: r.socConfident,
      odoConfident: r.odoConfident,
      socCandidates: r.socCandidates,
      odoCandidates: r.odoCandidates,
      tempC: r.tempC,
      tempBox: back(r.tempBox),
      tempConfident: r.tempConfident,
    );
  }

  /// The same image read with several thresholds (QA 135). One threshold
  /// never suits every frame: glare merges the "6" of "68" into its
  /// neighbour at one setting and thins it away at another, and the gap
  /// in "48 18" splits the ODO at some. [DashboardLayoutParser.combine]
  /// takes the consensus.
  static List<List<OcrToken>> readPasses(GrayImage image) {
    return _passes(image);
  }

  static List<List<OcrToken>> _passes(GrayImage image) {
    final first = readPass(image, 19);
    // Phone held close: big digits need a wider local window, or thick
    // segments turn hollow.
    final heights = [
      for (final t in first)
        if (t.text.length >= 2 && RegExp(r'^\d+$').hasMatch(t.text))
          t.box.height,
    ]..sort();
    final big = heights.isNotEmpty && heights[heights.length ~/ 2] > 60;
    final narrow = big ? 35 : 19;
    final wide = big ? 51 : 27;
    return [
      big ? readPass(image, narrow) : first,
      readPass(image, narrow, offset: 36),
      readPass(image, wide, offset: 36),
      readPass(image, big ? narrow : 15, offset: 22),
    ];
  }

  static const _shortGlyphs = {'1', '4', '7'};

  /// Long side, in pixels, of the guide-window crop the scanner reads
  /// (QA 156: 720 before; with the phone a little far the % digits were
  /// 25 px tall and a soft frame read "68" as "63").
  static const frameSide = 900;

  /// QA 159: lit share of the cell left of a number above which a digit
  /// is there but was not read.
  static const lostDigitLit = 0.08;

  static double _litShare(
    Uint8List mask,
    int w, {
    required int h0,
    required Rect cell,
  }) {
    final x0 = math.max(0, cell.left.floor()),
        x1 = math.min(w, cell.right.ceil());
    final y0 = math.max(0, cell.top.floor()),
        y1 = math.min(h0, cell.bottom.ceil());
    if (x1 - x0 < 2 || y1 - y0 < 2) return 0;
    var lit = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        lit += mask[y * w + x];
      }
    }
    return lit / ((x1 - x0) * (y1 - y0));
  }

  /// Token text of a digit-sized shape the reader could not decode.
  static const unreadGlyph = DashboardLayoutParser.unreadGlyph;

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

  /// One pass: local window [window] px, a pixel is lit when it is
  /// [offset] above the local mean (and brighter than [floor]).
  static List<OcrToken> readPass(
    GrayImage image,
    int window, {
    int offset = 28,
    int floor = 100,
  }) => _read(image, window, offset: offset, floor: floor);

  static List<OcrToken> _read(
    GrayImage image,
    int window, {
    required int offset,
    required int floor,
  }) {
    final w = image.width, h = image.height;
    final mask = _binarize(image, window, offset: offset, floor: floor);
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

    // Every digit of one display leans the same way: one slant for the
    // pass (median of the tall pieces) instead of each digit's own
    // estimate, which a "7"'s top bar or a "4"'s open top tilts (QA 135).
    final estimates = [
      for (final piece in pieces)
        if (piece.height >= 18 && piece.width >= 0.3 * piece.height)
          ?_estimateSlant(mask, w, piece),
    ]..sort();
    final slant = estimates.isEmpty
        ? null
        : estimates[estimates.length ~/ 2].clamp(-0.12, 0.4).toDouble();
    String? decode(_Piece piece, {double? width}) =>
        _decode(mask, w, h, piece, width: width, slant: slant);
    ({String? ch, double conf}) scored(_Piece piece, {double? width}) =>
        _decodeScored(mask, w, h, piece, width: width, slant: slant);

    final cells = <_Cell>[];
    // QA 156: digit-sized shapes that did not decode. A number next to
    // one is missing a digit ("68" came out "8"); the parser drops it.
    final unread = <Rect>[];
    for (final piece in pieces) {
      final ph = piece.height, pw = piece.width;
      if (ph < 10 || piece.members.isEmpty) continue;
      final thicks = [for (final b in piece.members) b.thick]..sort();
      final thick = thicks[thicks.length ~/ 2];
      // A "1" leans with the italic: its box is the stroke plus the slant
      // (QA 135: a slanted "1" was decoded as a "2").
      // A "1" is strokes only: no row is lit much wider than a stroke. A
      // "3" or "7" is as narrow (no left column) but has its bars.
      final thinnest = [
        for (final b in piece.members) b.thick,
      ].reduce(math.min);
      final barless =
          _longestRun(mask, w, piece) <=
          1.35 * math.min(thick, thinnest + 2) + 2;
      final one =
          barless &&
          ph >= 18 &&
          thick >= 2 &&
          piece.members.length <= 3 &&
          ph >= 3.0 * thick &&
          // It leans with the italic: stroke plus slant (QA 135: a slanted
          // "1" was decoded as a "2").
          pw <= thick + 0.38 * ph &&
          pw < 0.55 * ph;
      if (one) {
        cells.add(_Cell('1', piece.rect));
        continue;
      }
      if (pw < 0.42 * ph) {
        if (ph >= 18 && !barless) {
          // "3" and "7" have no left column: decode them in a cell of the
          // usual width ending at their right edge (QA 135: "47" read
          // "41", "123" read "12").
          final ch = decode(piece, width: 0.56 * ph);
          if (ch == '7' || ch == '3') {
            cells.add(_Cell(ch!, piece.rect));
            continue;
          }
        }
        if (ph >= 18) unread.add(piece.rect);
        continue;
      }
      if (pw > 1.0 * ph && !(ph >= 0.8 * pw && piece.members.length >= 3)) {
        if (ph >= 18) unread.add(piece.rect);
        continue;
      }
      final natural = scored(piece);
      var ch = natural.ch;
      if (pw < 0.75 * ph &&
          !barless &&
          (ch == null || ch == '1' || ch == '3' || ch == '7')) {
        // "7" and "3" have no left column, so their measured cell is too
        // narrow and the zones crowd the right column: a tilted "7" read
        // "3" (QA 135). Decode in the usual cell width too, keep the
        // better match.
        final virtual = scored(piece, width: 0.56 * ph);
        if ((virtual.ch == '7' || virtual.ch == '3') &&
            (ch == null || ch == '1' || virtual.conf > natural.conf)) {
          ch = virtual.ch;
        }
      }
      if (ch == '1' && !barless) ch = null;
      if (ch != null) {
        cells.add(_Cell(ch, piece.rect));
      } else {
        loose.add(piece.rect);
        if (ph >= 18) unread.add(piece.rect);
      }
    }
    cells.sort((a, b) => a.box.left.compareTo(b.box.left));
    // A "1" with a short bar on its top is a "7" whose top bar came apart
    // at this threshold (QA 135: "47" read "41").
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      if (cell.text != '1') continue;
      final b = cell.box;
      for (final bar in loose) {
        if (bar.height <= 0.32 * b.height &&
            bar.width >= 0.22 * b.height &&
            bar.width <= 0.75 * b.height &&
            bar.bottom >= b.top - 0.12 * b.height &&
            bar.top <= b.top + 0.08 * b.height &&
            bar.right >= b.left - 0.15 * b.height &&
            bar.right <= b.right + 0.15 * b.height &&
            bar.left < b.left) {
          cells[i] = _Cell('7', b.expandToInclude(bar));
          break;
        }
      }
    }

    // Digits on one row form a number. "1", "4" and "7" have no top or
    // bottom bar, so they stand shorter than their neighbours (QA 135:
    // "12" read "1", "4818" read "488"): a row is a band as tall as its
    // full digits, and those three may fill only part of it.
    final runs = <_Run>[];
    for (final cell in cells) {
      final ch = cell.text;
      final box = cell.box;
      final short = _shortGlyphs.contains(ch);
      var joined = false;
      for (final run in runs) {
        // Follow the row's slope (phone a few degrees off level): the band
        // moves with the line through the run's digits (QA 135).
        final band = run.band.shift(
          Offset(0, run.slope * (box.center.dx - run.band.center.dx)),
        );
        final bandH = math.max(band.height, short ? 0 : box.height);
        final rowH = math.max(bandH, box.height);
        final inBand =
            box.top >= band.top - 0.25 * rowH &&
            box.bottom <= band.bottom + 0.25 * rowH &&
            (box.center.dy - band.center.dy).abs() < 0.3 * rowH;
        final ratio = box.height / math.max(1, band.height);
        // The "°C" C is as tall as its digits; the small "%" is not (it
        // must never turn "68 %" into the temperature "68C").
        final sizeOk = ch == 'C'
            ? ratio > 0.7 && ratio < 1.3
            : short
            ? ratio > 0.55 && ratio < 1.33
            : (ratio > 0.75 && ratio < 1.33) ||
                  // The run so far holds only short glyphs ("1" then "2").
                  (run.allShort && ratio >= 1.0 && ratio < 1.85);
        // A "1" sits at the right of its cell.
        final vLeft = ch == '1' ? box.right - 0.6 * rowH : box.left;
        final gap = vLeft - run.right;
        if (inBand && sizeOk && gap > -0.3 * rowH && gap < 1.0 * rowH) {
          run.add(ch, box, short: short);
          joined = true;
          break;
        }
      }
      if (!joined) runs.add(_Run(ch, box, short: short));
    }

    // A small glyph just right of a number on its baseline is the "%"
    // (it decodes as a random digit, or not at all).
    final big = [
      for (final r in runs)
        if (r.boxes.first.height >= 18) r,
    ];
    // Any lone glyph, small or not: a "%" can decode as a digit (QA 135).
    final candidates = <(Rect, _Run?)>[
      for (final r in runs)
        if (r.text.length == 1) (r.boxes.first, r),
      for (final rect in loose) (rect, null),
    ];
    final percents = <Rect>[];
    for (final (rect, run) in candidates) {
      for (final target in big) {
        if (identical(target, run)) continue;
        // Its digits' height and its last digit, not the whole run's box:
        // a tilted run's box is taller than its digits, and a trailing "1"
        // then passed for a "%" (QA 135: 25031 read 2503).
        final heights = [for (final b in target.boxes) b.height]..sort();
        final th = heights[heights.length ~/ 2];
        final last = target.boxes.last;
        final maxRatio = run?.text == '1' ? 0.5 : 0.65;
        if (rect.height >= 0.25 * th &&
            rect.height <= maxRatio * th &&
            rect.left - last.right >= -0.2 * th &&
            rect.left - last.right <= 0.9 * th &&
            (rect.bottom - last.bottom).abs() <= 0.3 * th) {
          if (run != null) runs.remove(run);
          percents.add(rect);
          break;
        }
      }
    }

    // QA 159: a number with lit segments just left of its first digit has
    // lost that digit (the "3" of "37" ran into the battery icon under
    // it and read as one tall shape: the owner's 37 % locked as 7 %). The
    // cell is marked unread, so the number is not taken. A real one-digit
    // number has a dark cell there; a "0" in front is read as a digit.
    final lost = <Rect>[];
    final taken = [for (final r in runs) r.rect];
    for (final r in runs) {
      final first = r.boxes.first;
      final h = first.height;
      if (h < 18 || !RegExp(r'\d').hasMatch(r.text)) continue;
      final cell = Rect.fromLTRB(
        first.left - 0.72 * h,
        first.top + 0.12 * h,
        first.left - 0.1 * h,
        first.bottom - 0.12 * h,
      );
      // Another number there ("48 18") is not a lost digit.
      final covered = taken.any(
        (other) =>
            other != r.rect &&
            other.overlaps(cell) &&
            math.min(other.right, cell.right) -
                    math.max(other.left, cell.left) >
                0.3 * cell.width,
      );
      if (!covered &&
          _litShare(mask, w, h0: image.height, cell: cell) > lostDigitLit) {
        lost.add(
          Rect.fromLTRB(
            first.left - 0.7 * h,
            first.top,
            first.left - 0.1 * h,
            first.bottom,
          ),
        );
      }
    }

    return [
      for (final r in runs)
        if (r.text != '1' || r.boxes.first.height >= 18)
          OcrToken(r.text, r.rect),
      for (final p in percents) OcrToken('%', p),
      for (final u in unread)
        if (!percents.contains(u)) OcrToken(unreadGlyph, u),
      for (final u in lost) OcrToken(DashboardLayoutParser.lostGlyph, u),
    ];
  }

  static Uint8List _binarize(
    GrayImage image,
    int window, {
    required int offset,
    required int floor,
  }) {
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
        if (v <= floor) continue;
        final x0 = math.max(0, x - r), x1 = math.min(w, x + r + 1);
        final sum =
            integral[y1 * (w + 1) + x1] -
            integral[y0 * (w + 1) + x1] -
            integral[y1 * (w + 1) + x0] +
            integral[y0 * (w + 1) + x0];
        final mean = sum / ((x1 - x0) * (y1 - y0));
        if (v > mean + offset) out[y * w + x] = 1;
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

  /// The glyph in [cell]. [width] fixes the cell width (a "3" or "7"
  /// without its left column); otherwise it is measured per slant.
  static String? _decode(
    Uint8List mask,
    int w,
    int h,
    _Piece cell, {
    double? width,
    double? slant,
  }) => _decodeScored(mask, w, h, cell, width: width, slant: slant).ch;

  static ({String? ch, double conf}) _decodeScored(
    Uint8List mask,
    int w,
    int h,
    _Piece cell, {
    double? width,
    double? slant,
  }) {
    final y0 = cell.y0.toDouble();
    final cellH = cell.height.toDouble();
    final cy = (cell.y0 + cell.y1) / 2;
    String? best;
    var bestConf = -1.0;
    // Italic LCD digits plus the camera's tilt (QA 135): search around the
    // display's slant.
    final slants = slant == null
        ? const [0.0, 0.07, 0.14, 0.21]
        : [
            for (final d in const [-0.06, -0.03, 0.0, 0.03, 0.06])
              (slant + d).clamp(-0.12, 0.4).toDouble(),
          ];
    for (final slant in slants) {
      // The cell in un-sheared coordinates (u = x - slant·(cy - y)): its
      // box edges are then the glyph's columns whatever segments it has.
      // Taking the plain box made digits without an "e" ("9", "4", "7")
      // sit half a slant off and lose their "f" (QA 135: 99 read 33).
      var uMin = double.infinity, uMax = -double.infinity;
      for (var y = cell.y0; y < cell.y1; y++) {
        final dx = slant * (cy - y);
        for (var x = cell.x0; x < cell.x1; x++) {
          if (mask[y * w + x] == 0) continue;
          final u = x - dx;
          if (u < uMin) uMin = u;
          if (u + 1 > uMax) uMax = u + 1;
        }
      }
      if (!uMax.isFinite) return (ch: null, conf: 0.0);
      final cw = width ?? (uMax - uMin);
      if (cw <= 0) continue;
      final left = width == null ? uMin : uMax - width;
      final lit = [
        for (final z in _zones)
          _frac(
            mask,
            w,
            h,
            left + z[0] * cw,
            left + z[1] * cw,
            y0 + z[2] * cellH,
            y0 + z[3] * cellH,
            slant,
            cy,
          ),
      ];
      // Soft match against every glyph (QA 135): a zone half on a stroke
      // no longer flips a hard 0.32 threshold and voids the digit.
      String? ch;
      var conf = -1.0, second = -1.0;
      for (final entry in _patterns.entries) {
        var score = 0.0;
        for (var z = 0; z < 7; z++) {
          final on = (entry.key >> (6 - z)) & 1 == 1;
          final f = lit[z];
          score += on
              ? ((f - 0.1) / 0.4).clamp(0.0, 1.0)
              : ((0.45 - f) / 0.35).clamp(0.0, 1.0);
        }
        if (score > conf) {
          if (_patterns[entry.key] != ch) second = conf;
          conf = score;
          ch = entry.value;
        } else if (score > second && entry.value != ch) {
          second = score;
        }
      }
      if (conf < 5.6 || conf - second < 0.35) ch = null;
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
    return (ch: best, conf: bestConf);
  }

  /// Slant of [cell]'s right edge (positive = top leans right), or null
  /// when the glyph has too few rows to tell.
  static double? _estimateSlant(Uint8List mask, int w, _Piece cell) {
    final rows = cell.height;
    if (rows < 12) return null;
    double? band(int from, int to) {
      var sum = 0.0, n = 0;
      for (var y = from; y < to; y++) {
        for (var x = cell.x1 - 1; x >= cell.x0; x--) {
          if (mask[y * w + x] != 0) {
            sum += x;
            n++;
            break;
          }
        }
      }
      return n < 2 ? null : sum / n;
    }

    final third = rows ~/ 3;
    final top = band(cell.y0, cell.y0 + third);
    final bottom = band(cell.y1 - third, cell.y1);
    if (top == null || bottom == null) return null;
    return (top - bottom) / (rows - third);
  }

  /// Longest run of lit pixels on one row of [piece].
  static int _longestRun(Uint8List mask, int w, _Piece piece) {
    var best = 0;
    for (var y = piece.y0; y < piece.y1; y++) {
      var run = 0;
      for (var x = piece.x0; x < piece.x1; x++) {
        if (mask[y * w + x] != 0) {
          run++;
          if (run > best) best = run;
        } else {
          run = 0;
        }
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
  _Run(this.text, Rect first, {required bool short})
    : boxes = [first],
      allShort = short,
      band = first;

  String text;
  final List<Rect> boxes;

  /// Every glyph so far is a short one (1, 4, 7).
  bool allShort;

  /// The vertical extent of the row's full-height digits (or of the short
  /// glyphs while there are no others yet).
  Rect band;

  double get right => boxes.last.right;

  /// Vertical drift per pixel along the row, from the first and last of
  /// its full-height digits (0 until there are two).
  double slope = 0;
  Rect? _firstFull;

  void add(String ch, Rect box, {required bool short}) {
    text += ch;
    boxes.add(box);
    if (!short) {
      final first = _firstFull ??= allShort ? null : band;
      if (first != null && box.center.dx - first.center.dx > first.height) {
        slope =
            (box.center.dy - first.center.dy) /
            (box.center.dx - first.center.dx);
      }
    }
    // The band is the latest full digit (moved along the slope when it is
    // used): the union of a tilted row is taller than its digits, and a
    // "1" then looked too short to belong (QA 135).
    if (!short) {
      band = box;
      allShort = false;
    } else if (allShort) {
      band = band.expandToInclude(box);
    }
  }

  Rect get rect => boxes.reduce((a, b) => a.expandToInclude(b));
}
