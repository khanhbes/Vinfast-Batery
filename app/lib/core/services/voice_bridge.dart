import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The phone has no speech recognizer to open (no Google app, or it is off).
class VoiceUnavailable implements Exception {
  const VoiceUnavailable();
}

/// QA 164 (owner's choice): talk to Pinova Bot and hear its answers, on
/// Android only. Listening opens the system's own speech screen (the Google
/// app holds the microphone), so Pinova asks for no permission; reading
/// uses the phone's text-to-speech in Vietnamese. iOS comes later (it needs
/// the microphone and speech permissions).
abstract final class VoiceBridge {
  static const _channel = MethodChannel('com.vinfast.battery/voice');
  static bool _handler = false;

  /// The message being read aloud (its id), null when silent.
  static final speaking = ValueNotifier<String?>(null);

  /// Tests turn it off.
  @visibleForTesting
  static bool? supportedOverride;

  static bool get supported =>
      supportedOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static void _listenToNative() {
    if (_handler) return;
    _handler = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'done') speaking.value = null;
    });
  }

  /// What the owner said, null when they closed the screen or said nothing.
  /// Throws [VoiceUnavailable] when the phone cannot listen.
  static Future<String?> listen() async {
    if (!supported) throw const VoiceUnavailable();
    final Object? result;
    try {
      result = await _channel.invokeMethod<Object?>('listen', {
        'prompt': 'Hỏi Pinova Bot',
      });
    } on MissingPluginException {
      throw const VoiceUnavailable();
    } on PlatformException {
      throw const VoiceUnavailable();
    }
    if (result is Map && result['error'] != null) {
      throw const VoiceUnavailable();
    }
    final text = result is String ? result.trim() : '';
    return text.isEmpty ? null : text;
  }

  /// Reads [text] aloud for message [id]. False when the phone has no
  /// Vietnamese voice (the owner installs one in the phone's settings).
  static Future<bool> speak(String id, String text) async {
    if (!supported) return false;
    _listenToNative();
    final spoken = plain(text);
    if (spoken.isEmpty) return false;
    bool ok;
    try {
      ok =
          await _channel.invokeMethod<bool>('speak', {'text': spoken}) ?? false;
    } on Object {
      ok = false;
    }
    speaking.value = ok ? id : null;
    return ok;
  }

  static Future<void> stop() async {
    speaking.value = null;
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on Object {
      // Nothing was being read.
    }
  }

  /// The answer as it should sound: no Markdown marks, links read by name.
  static String plain(String markdown) {
    var text = markdown
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
        .replaceAll(RegExp(r'[*_`#>]+'), '')
        .replaceAll(RegExp(r'^\s*[-•]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
    return text.length > 3900 ? text.substring(0, 3900) : text;
  }
}
