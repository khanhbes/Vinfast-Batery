import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final voiceInputServiceProvider = Provider<VoiceInputService>((ref) {
  final service = VoiceInputService();
  ref.onDispose(service.dispose);
  return service;
});

enum VoiceInputState { uninitialized, ready, listening, processing, error }

/// No native speech recognizer is wired yet. Fail closed rather than showing
/// random sound levels or requesting microphone access without a usable feature.
class VoiceInputService {
  static bool get isSupported => false;

  VoiceInputState _state = VoiceInputState.uninitialized;
  VoiceInputState get state => _state;
  bool get isListening => _state == VoiceInputState.listening;

  final _soundLevelController = StreamController<double>.broadcast();
  Stream<double> get soundLevelStream => _soundLevelController.stream;

  Future<bool> requestMicrophonePermission() async => false;

  Future<bool> initialize() async {
    _state = VoiceInputState.error;
    return false;
  }

  Future<bool> startListening({
    String localeId = 'vi_VN',
    required void Function(String text) onResult,
    void Function(double level)? onSoundLevel,
    void Function()? onDone,
  }) async {
    _state = VoiceInputState.error;
    return false;
  }

  void updateTranscript(String text) {
    // Never accept synthetic results while recognition is unavailable.
  }

  Future<String> stopListening() async {
    _state = VoiceInputState.error;
    return '';
  }

  Future<void> cancelListening() async {
    _state = VoiceInputState.error;
  }

  void dispose() {
    _soundLevelController.close();
  }
}
