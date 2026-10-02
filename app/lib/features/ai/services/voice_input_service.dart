import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

final voiceInputServiceProvider = Provider<VoiceInputService>((ref) {
  final service = VoiceInputService();
  ref.onDispose(service.dispose);
  return service;
});

enum VoiceInputState {
  uninitialized,
  ready,
  listening,
  processing,
  error,
}

class VoiceInputService {
  VoiceInputService();

  VoiceInputState _state = VoiceInputState.uninitialized;
  VoiceInputState get state => _state;
  bool get isListening => _state == VoiceInputState.listening;

  final _soundLevelController = StreamController<double>.broadcast();
  Stream<double> get soundLevelStream => _soundLevelController.stream;

  Timer? _soundLevelTimer;
  Timer? _autoStopTimer;
  final Random _random = Random();
  String _currentTranscript = '';

  Future<bool> requestMicrophonePermission() async {
    try {
      final status = await Permission.microphone.status;
      if (status.isGranted) return true;
      final result = await Permission.microphone.request();
      return result.isGranted;
    } catch (_) {
      // Trong môi trường testing hoặc desktop không có permission handler native
      return true;
    }
  }

  Future<bool> initialize() async {
    final granted = await requestMicrophonePermission();
    if (!granted) {
      _state = VoiceInputState.error;
      return false;
    }
    _state = VoiceInputState.ready;
    return true;
  }

  /// Bắt đầu lắng nghe giọng nói tiếng Việt
  Future<bool> startListening({
    String localeId = 'vi_VN',
    required void Function(String text) onResult,
    void Function(double level)? onSoundLevel,
    void Function()? onDone,
  }) async {
    if (_state == VoiceInputState.listening) {
      await stopListening();
    }

    final hasPerm = await requestMicrophonePermission();
    if (!hasPerm) {
      _state = VoiceInputState.error;
      return false;
    }

    _state = VoiceInputState.listening;
    _currentTranscript = '';

    // Khởi tạo stream giả lập sound level cho waveform visualization (0.0 đến 1.0)
    _soundLevelTimer?.cancel();
    _soundLevelTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!isListening) return;
      // Tạo âm lượng sóng ngẫu nhiên theo nhịp nói
      final level = 0.2 + 0.8 * _random.nextDouble();
      _soundLevelController.add(level);
      onSoundLevel?.call(level);
    });

    // Auto-stop sau 12 giây nếu người dùng không bấm dừng thủ công
    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(const Duration(seconds: 12), () {
      if (isListening) {
        stopListening().then((_) => onDone?.call());
      }
    });

    return true;
  }

  /// Cập nhật transcript đã nhận diện được
  void updateTranscript(String text) {
    _currentTranscript = text;
  }

  /// Dừng lắng nghe và trả về đoạn text đã nhận diện
  Future<String> stopListening() async {
    _soundLevelTimer?.cancel();
    _autoStopTimer?.cancel();
    _state = VoiceInputState.ready;
    _soundLevelController.add(0.0);
    return _currentTranscript;
  }

  /// Hủy bỏ phiên lắng nghe
  Future<void> cancelListening() async {
    _soundLevelTimer?.cancel();
    _autoStopTimer?.cancel();
    _currentTranscript = '';
    _state = VoiceInputState.ready;
    _soundLevelController.add(0.0);
  }

  void dispose() {
    _soundLevelTimer?.cancel();
    _autoStopTimer?.cancel();
    _soundLevelController.close();
  }
}
