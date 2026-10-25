import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/coach_mark_overlay.dart';
import 'guide_registry.dart';

/// First-run guides for each screen (QA 135): Sạc pin, Lịch sử, Cài đặt,
/// Pinova Premium, Pinova Bot and the dashboard scanner. Each shows once
/// per account *on this install* (kept only on the phone, so a reinstall
/// shows them again, like the owner asked) and only after the Overview
/// tour, so a new owner meets one guide at a time.
abstract final class ScreenTour {
  static const charge = 'tour_charge_v1';
  static const history = 'tour_history_v1';
  static const settings = 'tour_settings_v1';
  static const premium = 'tour_premium_v1';
  static const bot = 'tour_bot_v1';
  static const scan = 'tour_scan_v1';

  /// The Overview tour, replayed once per install (QA 135: reinstall).
  static const overviewInstall = 'tour_overview_install_v1';

  static const _prefix = 'screen_tours_seen_v1';

  /// Tests and the "Xem lại hướng dẫn" entry.
  static Future<SharedPreferences> Function() preferences =
      SharedPreferences.getInstance;
  static String? Function() currentUid = _firebaseUid;

  static String? _firebaseUid() {
    try {
      return Firebase.apps.isEmpty
          ? null
          : FirebaseAuth.instance.currentUser?.uid;
    } on Object {
      return null;
    }
  }

  static String _key(String uid) => '$_prefix.$uid';

  static Future<bool> seen(String tourId, {String? uid}) async {
    final id = uid ?? currentUid();
    if (id == null) return true;
    try {
      final list = (await preferences()).getStringList(_key(id)) ?? const [];
      return list.contains(tourId);
    } on Object {
      return true; // never trap the owner in a guide loop
    }
  }

  static Future<void> markSeen(String tourId, {String? uid}) async {
    final id = uid ?? currentUid();
    if (id == null) return;
    try {
      final prefs = await preferences();
      final list = {...?prefs.getStringList(_key(id)), tourId}.toList();
      await prefs.setStringList(_key(id), list);
    } on Object {
      // A guide shown twice is harmless.
    }
  }

  /// Forget every screen guide of this account (Cài đặt → Xem lại hướng dẫn).
  static Future<void> reset({String? uid}) async {
    final id = uid ?? currentUid();
    if (id == null) return;
    try {
      await (await preferences()).remove(_key(id));
    } on Object {
      // Nothing to reset.
    }
  }

  /// Shows [steps] once for [tourId] when every anchor is on screen and the
  /// Overview tour was already seen. Safe to call on every visit.
  static Future<bool> maybeShow(
    BuildContext context,
    String tourId,
    List<CoachMarkStep> steps,
  ) async {
    if (CoachMarkOverlay.hasActive || steps.isEmpty) return false;
    final uid = currentUid();
    if (uid == null) return false;
    if (await seen(tourId, uid: uid)) return false;
    // One guide at a time: after the Overview one.
    if (tourId != overviewInstall && !await seen(overviewInstall, uid: uid)) {
      return false;
    }
    // Let the screen finish its first layout and entrance animation.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!context.mounted ||
        ModalRoute.of(context)?.isCurrent == false ||
        CoachMarkOverlay.hasActive) {
      return false;
    }
    // Steps whose target is not built yet (lower in a long list) are left
    // out; the first one must be there or the guide waits for a later visit.
    if (steps.first.anchorKey.currentContext == null) return false;
    final visible = [
      for (final step in steps)
        if (step.anchorKey.currentContext != null) step,
    ];
    void done() => markSeen(tourId, uid: uid);

    final entry = CoachMarkOverlay.show(
      context: context,
      steps: visible,
      showDontShowAgain: false,
      onFinish: done,
      onSkip: done,
    );
    return entry != null;
  }
}
