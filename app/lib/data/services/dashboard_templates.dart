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
  });

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
