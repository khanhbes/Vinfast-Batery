import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/plan_style.dart';
import '../models/entitlement.dart';

/// The small-icon tint of Pinova's Android notifications follows the plan
/// (QA 140): platinum, steel or Aurora lavender. The app writes the plan
/// when it changes; a push handled in the background reads it back.
abstract final class NotificationAccent {
  static const _key = 'notification_accent_tier_v1';
  static Color? _color;

  /// The last plan seen (Free before [color] or [setTier] ran).
  static Color get current => _color ?? PlanStyle.free.accent;

  /// The plan's accent; Free until a plan was seen on this phone.
  static Future<Color> color() async {
    final cached = _color;
    if (cached != null) return cached;
    try {
      final id = (await SharedPreferences.getInstance()).getString(_key);
      final tier = PlanTier.values.where((t) => t.name == id).firstOrNull;
      return _color = PlanStyle.forTier(tier ?? PlanTier.free).accent;
    } on Object {
      return PlanStyle.free.accent;
    }
  }

  static PlanTier? _tier;

  /// Called on every theme build; writes only when the plan changed.
  static Future<void> setTier(PlanTier tier) async {
    if (_tier == tier) return;
    _tier = tier;
    _color = PlanStyle.forTier(tier).accent;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, tier.name);
    } on Object {
      // The tint is cosmetic; the next app start writes it again.
    }
  }
}
