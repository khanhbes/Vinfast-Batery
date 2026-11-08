import 'dart:math' as math;
import 'dart:ui';

/// Where each number sits on one model's instrument cluster (QA 142). The
/// scanner draws the cluster's outline and its zones; the owner lines the
/// real screen up with it, and every digit is read from its own zone.
///
/// All shapes are fractions of the cluster's glass, (0,0) its top-left
/// corner and (1,1) its bottom-right, so they scale with the viewfinder.
class DashboardTemplate {
  const DashboardTemplate({
    required this.id,
    required this.label,
    required this.aspect,
    required this.outline,
    required this.soc,
    required this.odo,
    required this.temp,
    required this.ignore,
    this.glass,
  });

  /// QA 149: the glass as a smooth closed curve, the way the cluster really
  /// looks (the polygon in [outline] drew a hard trapezoid). Each entry is
  /// `[x, y]` (a line, the first one moves) or `[c1x, c1y, c2x, c2y, x, y]`
  /// (a cubic curve), all fractions of the glass.
  final List<List<double>>? glass;

  /// The glass traced in [r]: the smooth curve when there is one, otherwise
  /// the outline polygon with softened corners.
  Path glassPath(Rect r) {
    Offset at(double x, double y) =>
        Offset(r.left + x * r.width, r.top + y * r.height);
    final path = Path();
    final curve = glass;
    if (curve != null && curve.isNotEmpty) {
      for (var i = 0; i < curve.length; i++) {
        final s = curve[i];
        if (i == 0 || s.length == 2) {
          final p = at(s[s.length - 2], s[s.length - 1]);
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        } else {
          final c1 = at(s[0], s[1]), c2 = at(s[2], s[3]), p = at(s[4], s[5]);
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p.dx, p.dy);
        }
      }
      return path..close();
    }
    // Rounded polygon: each corner cut a fifth of its shorter edge.
    final points = [for (final p in outline) at(p.dx, p.dy)];
    for (var i = 0; i < points.length; i++) {
      final prev = points[(i - 1 + points.length) % points.length];
      final p = points[i];
      final next = points[(i + 1) % points.length];
      final cut = 0.2 * (math.min((p - prev).distance, (next - p).distance));
      final a = p + (prev - p) / (prev - p).distance * cut;
      final b = p + (next - p) / (next - p).distance * cut;
      i == 0 ? path.moveTo(a.dx, a.dy) : path.lineTo(a.dx, a.dy);
      path.quadraticBezierTo(p.dx, p.dy, b.dx, b.dy);
    }
    return path..close();
  }

  final String id;

  /// Shown under the viewfinder ("Màn hình VinFast Feliz 2025").
  final String label;

  /// Width / height of the cluster's glass.
  final double aspect;

  /// The glass, as a polygon to trace.
  final List<Offset> outline;

  /// Battery %, ODO and battery temperature zones.
  final Rect soc;
  final Rect odo;
  final Rect temp;

  /// Digits read here are never one of the three (the speed).
  final Rect ignore;

  /// VinFast Feliz 2025 (measured on the owner's photo, 01/11/2026): a
  /// trapezoid LCD; "68 %" top left, the speed "00 KM/H" in the middle,
  /// "ODO 4818 KM" under the battery bar, "31°C" at the bottom.
  static const feliz2025 = DashboardTemplate(
    id: 'feliz-2025',
    label: 'Màn hình VinFast Feliz 2025',
    aspect: 1.42,
    outline: [
      Offset(0.02, 0.02),
      Offset(0.98, 0.02),
      Offset(0.80, 0.98),
      Offset(0.20, 0.98),
    ],
    soc: Rect.fromLTRB(0.19, 0.24, 0.37, 0.39),
    odo: Rect.fromLTRB(0.11, 0.58, 0.49, 0.73),
    temp: Rect.fromLTRB(0.36, 0.74, 0.63, 0.89),
    ignore: Rect.fromLTRB(0.40, 0.32, 0.68, 0.57),
    // QA 149: a badge, not a trapezoid: the top is square with soft
    // corners, the sides run straight down most of the way and then sweep
    // in to a rounded bottom (the owner's photos, 01/11/2026).
    glass: [
      [0.08, 0.0],
      [0.92, 0.0],
      [0.97, 0.0, 1.0, 0.03, 1.0, 0.09],
      [1.0, 0.62],
      [1.0, 0.80, 0.95, 0.92, 0.86, 0.975],
      [0.83, 0.992, 0.80, 1.0, 0.76, 1.0],
      [0.24, 1.0],
      [0.20, 1.0, 0.17, 0.992, 0.14, 0.975],
      [0.05, 0.92, 0.0, 0.80, 0.0, 0.62],
      [0.0, 0.09],
      [0.0, 0.03, 0.03, 0.0, 0.08, 0.0],
    ],
  );

  static const all = [feliz2025];

  /// The template for a vehicle's model, or null (a plain window) for the
  /// models that have none yet. Matches "Feliz" from 2025 on, or a Feliz
  /// without a year (the catalog's current Feliz is the 2025 one).
  static DashboardTemplate? forModel(String? modelName, {int? year}) {
    final name = (modelName ?? '').toLowerCase();
    if (!name.contains('feliz')) return null;
    final named = RegExp(r'20\d\d').firstMatch(name);
    final y = year ?? (named == null ? null : int.parse(named.group(0)!));
    if (y != null && y < 2025) return null;
    // "Feliz S" / "Feliz Lite" have other clusters.
    if (RegExp(r'feliz\s*(s|lite|neo)\b').hasMatch(name)) return null;
    return feliz2025;
  }

  static DashboardTemplate? byId(String? id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}
