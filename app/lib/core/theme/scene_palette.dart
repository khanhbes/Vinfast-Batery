import 'dart:ui';

import 'plan_style.dart';

/// Colours of the story screens (QA 149): the Getting started pages and the
/// plan change. Each scene owns three stops, and neighbouring scenes share
/// one, so swiping blends one into the next like a single shot: teal and
/// cyan for the battery, blue for charging, violet for the scanner, pink for
/// Pinova Bot. Story art only: statuses keep their LUXE colours (emerald
/// verified, champagne estimate, rose error).
abstract final class SceneColors {
  static const teal = Color(0xFF2DD4BF);
  static const cyan = Color(0xFF22D3EE);
  static const sky = Color(0xFF38BDF8);
  static const indigo = PlanColors.blue;
  static const violet = PlanColors.violet;
  static const lavender = PlanColors.lavender;
  static const pink = PlanColors.pink;
  static const coral = Color(0xFFFF8FA3);
  static const peach = Color(0xFFFFC28A);

  /// One scene per Getting started page, in order.
  static const scenes = <List<Color>>[
    [teal, cyan, sky],
    [sky, indigo, violet],
    [violet, lavender, pink],
    [pink, coral, peach],
  ];

  /// The palette at a fractional [page] (0 = first scene), blending the two
  /// scenes around it.
  static List<Color> at(double page) {
    final last = scenes.length - 1;
    final p = page.clamp(0.0, last.toDouble());
    final i = p.floor().clamp(0, last);
    final j = (i + 1).clamp(0, last);
    final t = p - i;
    return [
      for (var k = 0; k < 3; k++) Color.lerp(scenes[i][k], scenes[j][k], t)!,
    ];
  }
}
