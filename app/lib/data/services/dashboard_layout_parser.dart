import 'dart:math' as math;
import 'dart:ui';

/// One piece of recognised text and where it sits in the (upright) image.
class OcrToken {
  const OcrToken(this.text, this.box);

  final String text;
  final Rect box;

  @override
  String toString() => 'OcrToken($text, $box)';
}

/// What one camera frame or photo says about the dashboard.
class DashboardLayoutReading {
  const DashboardLayoutReading({
    this.soc,
    this.odoKm,
    this.socBox,
    this.odoBox,
    this.socConfident = false,
    this.odoConfident = false,
    this.socCandidates = const [],
    this.odoCandidates = const [],
  });

  final int? soc;
  final double? odoKm;

  /// Where the numbers were found (upright image coordinates), to draw
  /// them over the camera preview.
  final Rect? socBox;
  final Rect? odoBox;

  /// The % sat right next to the number / the ODO matched its label or
  /// the last known reading.
  final bool socConfident;
  final bool odoConfident;
  final List<int> socCandidates;
  final List<double> odoCandidates;

  bool get isEmpty => soc == null && odoKm == null;
}

/// Reads battery % and ODO from recognised text *with positions*
/// (QA 131). The VinFast Feliz cluster is a seven-segment LCD: "68 %" with
/// a small % on the right, the speed "00 KM/H" in big digits, "ODO" above
/// "48 18" (a gap splits the four digits) with "KM" below, and "31°C".
/// Plain text could not tell those numbers apart; their layout can.
abstract final class DashboardLayoutParser {
  /// Highest ODO step accepted from the last known reading without being
  /// treated as a misread (a long trip between two readings).
  static const double maxOdoJumpKm = 3000;

  static DashboardLayoutReading parse(
    List<OcrToken> tokens, {
    double? lastOdoKm,
  }) {
    final items = [for (final t in tokens) _Item.from(t)];
    final percents = items.where((i) => i.isPercent).toList();
    final speedLabels = items.where((i) => i.isSpeedLabel).toList();
    final kmLabels = items.where((i) => i.isKmLabel).toList();
    final odoLabels = items.where((i) => i.isOdoLabel).toList();
    final tempLabels = items.where((i) => i.isTempLabel).toList();
    final numbers = _merge(items.where((i) => i.digits != null).toList());
    if (numbers.isEmpty) return const DashboardLayoutReading();

    final heights = [for (final n in numbers) n.box.height]..sort();
    // Lower median: with two numbers (battery + speed) the upper one would
    // be the speed itself and never stand out.
    final medianHeight = heights[(heights.length - 1) ~/ 2];

    bool isSpeed(_Item n) {
      if (n.inlineSpeed) return true;
      for (final label in speedLabels) {
        if (_rightOf(label, n, maxGap: 3) && _sameRow(n, label, tolerance: 1)) {
          return true;
        }
      }
      // The speed digits are by far the largest on the cluster.
      return n.digits!.length <= 3 &&
          numbers.length > 1 &&
          n.box.height > medianHeight * 1.7;
    }

    bool isTemp(_Item n) {
      if (n.inlineTemp) return true;
      for (final label in tempLabels) {
        // The "°" may be missing: "31" … "C" stand well apart.
        if (_rightOf(label, n, maxGap: 2.0) && _sameRow(n, label)) return true;
      }
      return false;
    }

    // ── Battery % ────────────────────────────────────────────────────────
    final socs = <({int value, Rect box, double score})>[];
    for (final n in numbers) {
      if (n.digits!.length > 3 || n.digits!.contains('.')) continue;
      final value = int.tryParse(n.digits!);
      if (value == null || value > 100) continue;
      if (isSpeed(n) || isTemp(n)) continue;
      var score = 0.0;
      if (n.inlinePercent) score += 3;
      for (final p in percents) {
        if (_rightOf(p, n, maxGap: 1.6) && _verticalOverlap(n, p)) {
          score += 3;
          break;
        }
      }
      if (score > 0) socs.add((value: value, box: n.box, score: score));
    }
    socs.sort((a, b) => b.score.compareTo(a.score));

    // ── ODO ──────────────────────────────────────────────────────────────
    final socBoxes = {for (final s in socs) s.box};
    final odos = <({double value, Rect box, double score, bool anchored})>[];
    for (final n in numbers) {
      if (socBoxes.contains(n.box) || n.inlinePercent) continue;
      if (isSpeed(n) || isTemp(n)) continue;
      final value = double.tryParse(n.digits!);
      if (value == null || value < 0 || value > 500000) continue;
      final digitCount = n.digits!.replaceAll('.', '').length;
      var score = 0.0;
      var anchored = false;
      for (final label in odoLabels) {
        if (_labelAboveOrLeft(label, n)) {
          score += 3;
          anchored = true;
          break;
        }
      }
      for (final label in kmLabels) {
        if (_labelBelow(label, n) ||
            (_rightOf(label, n, maxGap: 2) &&
                _sameRow(n, label, tolerance: 1))) {
          score += 2;
          anchored = true;
          break;
        }
      }
      if (digitCount >= 3 && digitCount <= 6) score += 1;
      if (digitCount <= 2 && !anchored) continue;
      final last = lastOdoKm;
      if (last != null && last > 0) {
        if (value < last - 1) {
          score -= 6; // the odometer never goes back
        } else if (value <= last + maxOdoJumpKm) {
          score += 3;
          anchored = true;
        } else {
          score -= 2;
        }
      }
      if (score > 0) {
        odos.add((value: value, box: n.box, score: score, anchored: anchored));
      }
    }
    odos.sort((a, b) => b.score.compareTo(a.score));

    var soc = socs.isEmpty ? null : socs.first;
    final odo = odos.isEmpty ? null : odos.first;

    // The small "%" is often not recognised on an LCD: then the battery is
    // the largest remaining 1–3 digit number ≤ 100 that is not the speed,
    // the temperature or the ODO. Weak on its own; frames still vote and
    // the owner checks it before saving.
    if (soc == null) {
      final rest = [
        for (final n in numbers)
          if (n.box != odo?.box &&
              !n.inlinePercent &&
              !n.digits!.contains('.') &&
              n.digits!.length <= 3 &&
              !isSpeed(n) &&
              !isTemp(n) &&
              (int.tryParse(n.digits!) ?? 999) <= 100 &&
              // Same digit size as the ODO when there is one (the Feliz
              // prints both alike): drops stray strokes and small glyphs.
              (odo == null ||
                  (n.box.height >= 0.7 * odo.box.height &&
                      n.box.height <= 1.45 * odo.box.height)))
            n,
      ]..sort((a, b) => b.box.height.compareTo(a.box.height));
      if (rest.isNotEmpty) {
        final n = rest.first;
        soc = (value: int.parse(n.digits!), box: n.box, score: 0.5);
      }
    }

    // A lone 3–6 digit number left after % / speed / °C is the ODO even
    // without a readable "ODO"/"KM" label.
    final lone =
        odo != null &&
        odos.length == 1 &&
        odo.value >= 100 &&
        odo.value == odo.value.roundToDouble();
    return DashboardLayoutReading(
      soc: soc?.value,
      odoKm: odo?.value,
      socBox: soc?.box,
      odoBox: odo?.box,
      socConfident: soc != null && soc.score >= 3,
      odoConfident: odo != null && ((odo.anchored && odo.score >= 3) || lone),
      socCandidates: {for (final s in socs) s.value}.toList(),
      odoCandidates: {for (final o in odos) o.value}.take(4).toList(),
    );
  }

  /// One frame read with several thresholds → one reading (QA 135).
  /// Each pass votes for its % and ODO (a confident one counts double); a
  /// longer number that contains a shorter one ("68" ⊃ "8", "4818" ⊃
  /// "48") takes its votes, because a segment pass loses a digit far more
  /// often than it invents one.
  static DashboardLayoutReading combine(List<DashboardLayoutReading> passes) {
    if (passes.isEmpty) return const DashboardLayoutReading();
    if (passes.length == 1) return passes.single;
    final soc = _consensus<int>([
      for (final p in passes)
        if (p.soc != null) (p.soc!, p.socConfident, p.socBox),
    ], (v) => '$v');
    final odo = _consensus<double>([
      for (final p in passes)
        if (p.odoKm != null) (p.odoKm!, p.odoConfident, p.odoBox),
    ], _odoDigits);
    return DashboardLayoutReading(
      soc: soc?.value,
      odoKm: odo?.value,
      socBox: soc?.box,
      odoBox: odo?.box,
      socConfident: soc?.confident ?? false,
      odoConfident: odo?.confident ?? false,
      socCandidates: {for (final p in passes) ...p.socCandidates}.toList(),
      odoCandidates: {
        for (final p in passes) ...p.odoCandidates,
      }.take(4).toList(),
    );
  }

  static String _odoDigits(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';

  /// [longer] holds all of [shorter]'s digits at its start or end.
  static bool contains(String longer, String shorter) =>
      longer.length > shorter.length &&
      (longer.startsWith(shorter) || longer.endsWith(shorter));

  static ({T value, Rect? box, bool confident})? _consensus<T>(
    List<(T, bool, Rect?)> votes,
    String Function(T) digits,
  ) {
    if (votes.isEmpty) return null;
    final score = <T, double>{};
    final confident = <T, bool>{};
    final boxes = <T, Rect?>{};
    for (final (value, sure, box) in votes) {
      score[value] = (score[value] ?? 0) + (sure ? 2 : 1);
      confident[value] = (confident[value] ?? false) || sure;
      boxes[value] ??= box;
    }
    // Absorb: the shorter value's votes go to the longest that contains it.
    final values = score.keys.toList()
      ..sort((a, b) => digits(b).length.compareTo(digits(a).length));
    for (final short in values.reversed.toList()) {
      final host = values.firstWhere(
        (long) => contains(digits(long), digits(short)),
        orElse: () => short,
      );
      if (host == short) continue;
      score[host] = score[host]! + score[short]!;
      confident[host] = confident[host]! || confident[short]!;
      score[short] = 0;
    }
    final best = score.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (best.value <= 0) return null;
    // Two or more passes agreeing is as good as a % / label next to it.
    final sure = confident[best.key]! || best.value >= 3;
    return (value: best.key, box: boxes[best.key], confident: sure);
  }

  /// Joins digit groups on one row separated by a segment gap ("48 18").
  static List<_Item> _merge(List<_Item> numbers) {
    final sorted = [...numbers]
      ..sort((a, b) => a.box.left.compareTo(b.box.left));
    final out = <_Item>[];
    for (final item in sorted) {
      final joined = out.indexWhere((prev) {
        final h = math.max(prev.box.height, item.box.height);
        final ratio = item.box.height / prev.box.height;
        final gap = item.box.left - prev.box.right;
        return _sameRow(prev, item) &&
            ratio > 0.7 &&
            ratio < 1.43 &&
            gap > -0.3 * h &&
            gap < 1.6 * h &&
            !prev.inlinePercent &&
            !prev.inlineTemp &&
            !prev.inlineSpeed;
      });
      if (joined < 0) {
        out.add(item);
      } else {
        out[joined] = out[joined].join(item);
      }
    }
    return out;
  }

  static bool _sameRow(_Item a, _Item b, {double tolerance = 0.45}) {
    final h = math.max(a.box.height, b.box.height);
    return (a.box.center.dy - b.box.center.dy).abs() < tolerance * h;
  }

  static bool _verticalOverlap(_Item a, _Item b) =>
      b.box.center.dy > a.box.top - 0.2 * a.box.height &&
      b.box.center.dy < a.box.bottom + 0.2 * a.box.height;

  /// [label] starts just right of [n].
  static bool _rightOf(_Item label, _Item n, {required double maxGap}) {
    final gap = label.box.left - n.box.right;
    return gap > -0.4 * n.box.height && gap < maxGap * n.box.height;
  }

  /// "ODO" printed above (and usually left of) the ODO digits.
  static bool _labelAboveOrLeft(_Item label, _Item n) {
    final h = n.box.height;
    final above = n.box.top - label.box.bottom;
    final horizontal =
        label.box.right > n.box.left - 2.5 * h && label.box.left < n.box.right;
    if (above > -0.5 * h && above < 1.6 * h && horizontal) return true;
    // Or on the same row, just left of the digits.
    return _sameRow(n, label, tolerance: 0.8) &&
        n.box.left - label.box.right > -0.3 * h &&
        n.box.left - label.box.right < 2.5 * h;
  }

  /// "KM" printed right under the ODO digits.
  static bool _labelBelow(_Item label, _Item n) {
    final h = n.box.height;
    final below = label.box.top - n.box.bottom;
    return below > -0.4 * h &&
        below < 1.3 * h &&
        label.box.center.dx > n.box.left - 0.3 * h &&
        label.box.center.dx < n.box.right + 0.3 * h;
  }
}

/// A token after seven-segment clean-up.
class _Item {
  _Item({
    required this.box,
    this.digits,
    this.isPercent = false,
    this.isSpeedLabel = false,
    this.isKmLabel = false,
    this.isOdoLabel = false,
    this.isTempLabel = false,
    this.inlinePercent = false,
    this.inlineSpeed = false,
    this.inlineTemp = false,
  });

  final Rect box;
  final String? digits;
  final bool isPercent;
  final bool isSpeedLabel;
  final bool isKmLabel;
  final bool isOdoLabel;
  final bool isTempLabel;
  final bool inlinePercent;
  final bool inlineSpeed;
  final bool inlineTemp;

  /// Seven-segment glyphs ML Kit reads as letters.
  static const _segment = {
    'O': '0', 'D': '0', 'Q': '0', 'U': '0', //
    'I': '1', 'L': '1', '|': '1', '!': '1', 'J': '1', ']': '1', '[': '1',
    'Z': '2', 'S': '5', 'G': '6', 'B': '8', 'T': '7', 'A': '4', 'Y': '4',
  };
  static const _lower = {'b': '6', 'g': '9', 'q': '9', 'l': '1', 'o': '0'};

  // Needs the D: a real "000" odometer must stay a number.
  static final _odoLabel = RegExp(r'^[O0Q]D[O0Q]$');
  // "KM/H" is read as KMH, KMIH, KMIM, KM/ …
  static final _speedLabel = RegExp(r'^K[MN][/|I1L\]?[HM]$|^K[MN]/$');
  static final _kmLabel = RegExp(r'^K[MN]$');
  static final _tempLabel = RegExp(r'^°?[C€]$|^°$');
  static final _tempInline = RegExp(
    r'^[0-9OIL|ZSBGTA ]{1,3}\s*°\s*[C€]?$|^[0-9OIL|ZSBGTA]{1,3}\s*[C€]$',
  );

  factory _Item.from(OcrToken token) {
    final raw = token.text.trim();
    final upper = raw.toUpperCase();
    final compact = upper.replaceAll(' ', '');
    if (compact == '%') return _Item(box: token.box, isPercent: true);
    if (_odoLabel.hasMatch(compact)) {
      return _Item(box: token.box, isOdoLabel: true);
    }
    if (_speedLabel.hasMatch(compact)) {
      return _Item(box: token.box, isSpeedLabel: true);
    }
    if (_kmLabel.hasMatch(compact)) {
      return _Item(box: token.box, isKmLabel: true);
    }
    if (_tempLabel.hasMatch(compact)) {
      return _Item(box: token.box, isTempLabel: true);
    }
    var body = raw;
    var inlinePercent = false;
    var inlineSpeed = false;
    var inlineTemp = false;
    if (body.endsWith('%')) {
      inlinePercent = true;
      body = body.substring(0, body.length - 1);
    } else if (RegExp(r'K[MN]/?H$', caseSensitive: false).hasMatch(body)) {
      inlineSpeed = true;
      body = body.replaceAll(RegExp(r'K[MN]/?H$', caseSensitive: false), '');
    } else if (_tempInline.hasMatch(compact)) {
      inlineTemp = true;
      body = body.replaceAll(RegExp(r'[°C€c]'), '');
    }
    final digits = digitize(body);
    if (digits == null) return _Item(box: token.box);
    return _Item(
      box: token.box,
      digits: digits,
      inlinePercent: inlinePercent,
      inlineSpeed: inlineSpeed,
      inlineTemp: inlineTemp,
    );
  }

  /// Digits of a token that is mostly digits (letters fixed as segments),
  /// or null for words such as "ECO".
  static String? digitize(String text) {
    final chars = text.replaceAll(RegExp(r'\s'), '').split('');
    if (chars.isEmpty || chars.length > 8) return null;
    var real = 0;
    final out = StringBuffer();
    for (final c in chars) {
      if (RegExp(r'[0-9]').hasMatch(c)) {
        real++;
        out.write(c);
      } else if (c == '.' || c == ',') {
        out.write('.');
      } else if (_lower.containsKey(c)) {
        out.write(_lower[c]);
      } else if (_segment.containsKey(c.toUpperCase())) {
        out.write(_segment[c.toUpperCase()]);
      } else {
        return null;
      }
    }
    // A word made only of look-alike letters ("ECO" fails above, "SOS",
    // "BOOT") must carry at least one real digit unless it is short.
    if (real == 0 && chars.length > 2) return null;
    var value = out.toString();
    if (value.startsWith('.') || value.endsWith('.')) {
      value = value.replaceAll('.', '');
    }
    if ('.'.allMatches(value).length > 1) value = value.replaceAll('.', '');
    return value.isEmpty ? null : value;
  }

  _Item join(_Item other) => _Item(
    box: box.expandToInclude(other.box),
    digits: '${digits ?? ''}${other.digits ?? ''}',
    inlinePercent: other.inlinePercent,
    inlineSpeed: other.inlineSpeed,
    inlineTemp: other.inlineTemp,
  );
}

/// Locks a value once several frames agree (QA 131): one frame can misread
/// a segment through glare; the same number in 3 of the last 6 frames —
/// and most frames that saw a number — is what the dashboard says.
class DashboardScanVote {
  DashboardScanVote({this.window = 6, this.needed = 3});

  final int window;
  final int needed;
  final List<int?> _socs = [];
  final List<double?> _odos = [];

  int? socLocked;
  double? odoLocked;

  /// The latest reading of each field, for the "reading…" preview.
  int? socSeen;
  double? odoSeen;

  void add(DashboardLayoutReading reading) {
    _push(_socs, reading.soc);
    // Only anchored ODO values vote (label, "KM" or the last reading).
    _push(_odos, reading.odoConfident ? reading.odoKm : null);
    socSeen = reading.soc ?? socSeen;
    odoSeen = reading.odoKm ?? odoSeen;
    socLocked ??= _winner(_socs);
    odoLocked ??= _winner(_odos);
  }

  bool get bothLocked => socLocked != null && odoLocked != null;
  bool get anyLocked => socLocked != null || odoLocked != null;

  void reset() {
    _socs.clear();
    _odos.clear();
    socLocked = null;
    odoLocked = null;
    socSeen = null;
    odoSeen = null;
  }

  void _push<T>(List<T?> list, T? value) {
    list.add(value);
    if (list.length > window) list.removeAt(0);
  }

  T? _winner<T>(List<T?> list) {
    final counts = <T, int>{};
    var seen = 0;
    for (final v in list) {
      if (v == null) continue;
      seen++;
      counts[v] = (counts[v] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    // QA 135: "8" when another frame read "68" is the same reading with a
    // lost digit, never a rival: it counts for "68". A short value that a
    // longer one contains cannot win while that longer one is in view (the
    // owner's 68 % locked as 8 % because the "6" failed first).
    String digits(T v) =>
        v is double && v == v.roundToDouble() ? v.round().toString() : '$v';
    final keys = counts.keys.toList();
    final merged = {...counts};
    for (final short in keys) {
      final hosts = keys.where(
        (long) => DashboardLayoutParser.contains(digits(long), digits(short)),
      );
      if (hosts.isEmpty) continue;
      final host = hosts.reduce((a, b) => counts[a]! >= counts[b]! ? a : b);
      merged[host] = merged[host]! + counts[short]!;
      merged.remove(short);
    }
    final best = merged.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.value >= needed && best.value >= seen * 0.6 ? best.key : null;
  }
}
