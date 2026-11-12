import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Touch and sound for the moments that matter (QA 151, owner's choice):
/// three haptic weights instead of one, and two short chimes (charge started,
/// charge finished).
///
/// Sounds are played natively (`com.vinfast.battery/feedback`, Android
/// SoundPool with the "sonification" usage, so the phone's silent mode mutes
/// them). iOS has no player yet: the call is a no-op there. Nothing here may
/// delay a command: every call returns immediately and never throws.
abstract final class LuxeFeedback {
  static const _channel = MethodChannel('com.vinfast.battery/feedback');

  /// Cài đặt → Giao diện → Âm thanh khi sạc. Kept on this phone (a sound is
  /// a matter of where the phone is, not of the account). Haptics follow
  /// the system setting.
  static final ValueNotifier<bool> sound = ValueNotifier<bool>(true);
  static const _soundKey = 'feedback_sound_v1';
  static Future<void>? _loaded;

  static Future<void> _load() => _loaded ??= () async {
    try {
      final prefs = await SharedPreferences.getInstance();
      sound.value = prefs.getBool(_soundKey) ?? true;
    } on Object {
      // Keep the default.
    }
  }();

  /// Reads the saved choice (the settings screen calls it before showing).
  static Future<void> ensureLoaded() => _load();

  static Future<void> setSound(bool on) async {
    sound.value = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_soundKey, on);
    } on Object {
      // Applies until the app closes.
    }
  }

  /// Patterns space their taps with timers; a widget test must not be left
  /// with one pending, so under `flutter test` each pattern is one tap.
  static final bool _underTest = Platform.environment.containsKey(
    'FLUTTER_TEST',
  );

  static Future<void> _pause(int ms) => _underTest
      ? Future<void>.value()
      : Future<void>.delayed(Duration(milliseconds: ms));

  /// Tests read what was asked for instead of touching the platform.
  @visibleForTesting
  static void Function(String event)? probe;

  /// A choice among several (chips, wheels, tabs).
  static void select() {
    probe?.call('select');
    unawaited(_quiet(HapticFeedback.selectionClick));
  }

  /// A confirmed action (saved, armed).
  static void confirm() {
    probe?.call('confirm');
    unawaited(_quiet(HapticFeedback.mediumImpact));
  }

  /// Something was refused or failed: two short knocks.
  static void error() {
    probe?.call('error');
    unawaited(() async {
      await _quiet(HapticFeedback.heavyImpact);
      await _pause(110);
      await _quiet(HapticFeedback.heavyImpact);
    }());
  }

  /// The plug answered ON (read back): a firm tap and the rising chime.
  static void chargeStarted() {
    probe?.call('chargeStarted');
    unawaited(_quiet(HapticFeedback.heavyImpact));
    _play('charge_start');
  }

  /// A session ended normally: light-light-firm and the resolving chime.
  static void chargeDone() {
    probe?.call('chargeDone');
    unawaited(() async {
      await _quiet(HapticFeedback.lightImpact);
      await _pause(140);
      await _quiet(HapticFeedback.lightImpact);
      await _pause(180);
      await _quiet(HapticFeedback.mediumImpact);
    }());
    _play('charge_done');
  }

  static void _play(String name) {
    unawaited(
      _quiet(() async {
        await _load();
        if (!sound.value) return;
        await _channel.invokeMethod<void>('play', name);
      }),
    );
  }

  static Future<void> _quiet(Future<void> Function() call) async {
    try {
      await call();
    } on Object {
      // No haptics engine, no channel (tests, iOS): feedback is optional.
    }
  }
}
