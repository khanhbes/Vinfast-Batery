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
  final _focusNode = FocusNode();
  late final VoiceInputService _voiceService;
  bool _ownsVoiceService = false;
  bool _hasText = false;
  bool _isListening = false;
  bool _showEmojiRow = false;
  double _soundLevel = 0.5;

  static const _quickEmojis = ['⚡', '🔋', '🚗', '⏱️', '❓', '🛠️'];

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

    _focusNode.addListener(() {
      if (_focusNode.hasFocus && !_showEmojiRow) {
        setState(() => _showEmojiRow = true);
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
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isStreaming) return;
    _controller.clear();
    setState(() => _showEmojiRow = false);
    widget.onSend(text);
  }

  void _insertEmoji(String emoji) {
    final currentText = _controller.text;
    final selection = _controller.selection;
    if (selection.isValid && selection.start >= 0) {
      final newText = currentText.replaceRange(
        selection.start,
        selection.end,
        emoji,
      );
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + emoji.length,
        ),
      );
    } else {
      _controller.text = currentText + emoji;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  void _showAttachmentOptions() {
    final uiColors = AppUiColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: uiColors.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: uiColors.glassBorder),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: uiColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Đính kèm dữ liệu & hình ảnh',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: uiColors.text,
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: uiColors.primary.withValues(alpha: 0.15),
                    child: Icon(
                      Icons.camera_alt_rounded,
                      color: uiColors.primary,
                    ),
                  ),
                  title: const Text('Chụp đồng hồ ODO / Cụm pin'),
                  subtitle: const Text('AI nhận diện số km và cảnh báo taplo'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _controller.text = '📸 [Đã chụp ODO] ';
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal.withValues(alpha: 0.15),
                    child: const Icon(
                      Icons.photo_library_rounded,
                      color: Colors.teal,
                    ),
                  ),
                  title: const Text('Chọn ảnh từ thư viện'),
                  subtitle: const Text(
                    'Gửi hóa đơn, thông số sạc hoặc hình ảnh xe',
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _controller.text = '🖼️ [Đính kèm ảnh] ';
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.amber.withValues(alpha: 0.15),
                    child: Icon(
                      Icons.bolt_rounded,
                      color: Colors.amber.shade800,
                    ),
                  ),
                  title: const Text('Gửi dữ liệu pin tức thì'),
                  subtitle: const Text(
                    'Trích xuất điện áp, nhiệt độ pack pin và SoC',
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    widget.onSend('Báo cáo chi tiết thông số pin hiện tại');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleVoiceInput() async {
    if (widget.isStreaming) return;

    if (_isListening) {
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: uiColors.dark
            ? const Color(0xFF0F172A).withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: uiColors.border.withValues(alpha: 0.5),
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Quick action emoji row when focused / toggled
            if (_showEmojiRow) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
                child: Row(
                  children: [
                    for (final emoji in _quickEmojis)
                      Expanded(
                        child: InkWell(
                          onTap: () => _insertEmoji(emoji),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Center(
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                        ),
                      ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: uiColors.muted,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      tooltip: 'Đóng thanh emoji',
                      onPressed: () => setState(() => _showEmojiRow = false),
                    ),
                  ],
                ),
              ),
            ],

            Row(
              children: [
                // Nút Đính kèm ảnh / dữ liệu (Attachment button)
                IconButton(
                  icon: Icon(
                    Icons.add_circle_outline_rounded,
                    color: uiColors.primary,
                    size: 22,
                  ),
                  tooltip: 'Đính kèm ảnh / dữ liệu',
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  onPressed: widget.isStreaming ? null : _showAttachmentOptions,
                ),

                // Ô nhập liệu hoặc Waveform ghi âm
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: uiColors.dark
                          ? const Color(0xFF1E293B).withValues(alpha: 0.6)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: _isListening
                            ? uiColors.primary
                            : uiColors.glassBorder,
                        width: _isListening ? 1.5 : 1.0,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _isListening
                        ? Row(
                            children: [
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.redAccent,
                                ),
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
                            focusNode: _focusNode,
                            textInputAction: TextInputAction.send,
                            keyboardType: TextInputType.text,
                            minLines: 1,
                            maxLines: 4,
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              hintText: widget.isStreaming
                                  ? 'BatteryBot đang trả lời...'
                                  : 'Hỏi về pin, sạc, xe...',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 9,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 6),

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
                        boxShadow: _hasText && !widget.isStreaming
                            ? [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
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
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          child: widget.isStreaming
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
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
                                  size: 19,
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
          ],
        ),
      ),
    );
  }
}
