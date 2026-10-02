import 'package:flutter/material.dart';

import '../../../core/theme/app_ui_colors.dart';
import '../services/voice_input_service.dart';
import 'animated_voice_waveform.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    this.isStreaming = false,
    this.voiceService,
  });

  final void Function(String text) onSend;
  final bool isStreaming;
  final VoiceInputService? voiceService;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  late final VoiceInputService _voiceService;
  bool _ownsVoiceService = false;
  bool _hasText = false;
  bool _isListening = false;
  double _soundLevel = 0.5;

  @override
  void initState() {
    super.initState();
    if (widget.voiceService != null) {
      _voiceService = widget.voiceService!;
    } else {
      _voiceService = VoiceInputService();
      _ownsVoiceService = true;
    }

    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
      }
    });
  }

  @override
  void dispose() {
    if (_isListening) {
      _voiceService.stopListening();
    }
    if (_ownsVoiceService) {
      _voiceService.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isStreaming) return;
    _controller.clear();
    widget.onSend(text);
  }

  Future<void> _toggleVoiceInput() async {
    if (widget.isStreaming) return;

    if (_isListening) {
      // Dừng ghi âm
      final recognized = await _voiceService.stopListening();
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _soundLevel = 0.0;
      });
      if (recognized.trim().isNotEmpty) {
        _controller.text = recognized;
        _submit();
      }
    } else {
      // Bắt đầu ghi âm tiếng Việt
      final success = await _voiceService.startListening(
        localeId: 'vi_VN',
        onResult: (text) {
          if (!mounted) return;
          _voiceService.updateTranscript(text);
          setState(() {
            _controller.text = text;
          });
        },
        onSoundLevel: (level) {
          if (!mounted) return;
          setState(() {
            _soundLevel = level;
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            _soundLevel = 0.0;
          });
        },
      );

      if (success && mounted) {
        setState(() {
          _isListening = true;
        });
      }
    }
  }

  void _cancelVoiceInput() {
    _voiceService.cancelListening();
    setState(() {
      _isListening = false;
      _soundLevel = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final uiColors = AppUiColors.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: uiColors.cardBackground,
        border: Border(
          top: BorderSide(
            color: uiColors.border.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Ô nhập liệu hoặc Waveform ghi âm
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: uiColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isListening
                        ? uiColors.primary
                        : uiColors.border.withValues(alpha: 0.7),
                    width: _isListening ? 1.5 : 1.0,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _isListening
                    ? Row(
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                            tooltip: 'Hủy ghi âm',
                            onPressed: _cancelVoiceInput,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AnimatedVoiceWaveform(
                              isListening: true,
                              soundLevel: _soundLevel,
                              height: 28,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Đang nghe...',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: uiColors.primary,
                            ),
                          ),
                        ],
                      )
                    : TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.send,
                        keyboardType: TextInputType.text,
                        minLines: 1,
                        maxLines: 4,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText: widget.isStreaming
                              ? 'BatteryBot đang trả lời...'
                              : 'Hỏi BatteryBot về pin, sạc, xe...',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 8),

            // Nút hành động: Gửi (khi có chữ) HOẶC Mic / Dừng (khi trống)
            Semantics(
              button: true,
              label: _hasText
                  ? 'Gửi tin nhắn'
                  : _isListening
                      ? 'Dừng ghi âm và gửi'
                      : 'Nhập bằng giọng nói tiếng Việt',
              child: Material(
                color: Colors.transparent,
                child: Ink(
                  decoration: BoxDecoration(
                    color: _isListening
                        ? Colors.redAccent
                        : _hasText && !widget.isStreaming
                            ? theme.colorScheme.primary
                            : theme.colorScheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: InkWell(
                    key: const Key('chat_input_action_button'),
                    onTap: widget.isStreaming
                        ? null
                        : _hasText
                            ? _submit
                            : _toggleVoiceInput,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      child: widget.isStreaming
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.primary,
                                ),
                              ),
                            )
                          : Icon(
                              _isListening
                                  ? Icons.stop_rounded
                                  : _hasText
                                      ? Icons.arrow_upward_rounded
                                      : Icons.mic_rounded,
                              size: 20,
                              color: _isListening || _hasText
                                  ? Colors.white
                                  : theme.colorScheme.primary,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
