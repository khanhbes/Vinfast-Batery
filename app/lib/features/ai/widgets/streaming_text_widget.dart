import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'typing_indicator_dots.dart';

class StreamingTextWidget extends StatefulWidget {
  const StreamingTextWidget({
    super.key,
    required this.text,
    required this.isStreaming,
    this.style,
  });

  final String text;
  final bool isStreaming;
  final TextStyle? style;

  @override
  State<StreamingTextWidget> createState() => _StreamingTextWidgetState();
}

class _StreamingTextWidgetState extends State<StreamingTextWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  void _syncAnimation() {
    if (widget.isStreaming && !MediaQuery.disableAnimationsOf(context)) {
      if (!_cursorController.isAnimating) {
        _cursorController.repeat(reverse: true);
      }
    } else {
      _cursorController.stop();
      _cursorController.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant StreamingTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textStyle =
        widget.style ??
        theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          height: 1.45,
          fontSize: 14,
        );

    // Khi bot đang bắt đầu soạn (chưa có text trả về)
    if (widget.text.isEmpty && widget.isStreaming) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TypingIndicatorDots(
              dotColor: theme.colorScheme.primary,
              dotSize: 7.0,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Đang chuẩn bị câu trả lời…',
                style: textStyle?.copyWith(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MarkdownBody(
          data: widget.text,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
            p: textStyle,
            strong: textStyle?.copyWith(fontWeight: FontWeight.bold),
            listBullet: textStyle?.copyWith(color: theme.colorScheme.primary),
            blockquote: textStyle?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
            code: TextStyle(
              fontSize: 12.5,
              fontFamily: 'monospace',
              color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1),
              backgroundColor: isDark
                  ? const Color(0xFF0F172A)
                  : const Color(0xFFF1F5F9),
            ),
            codeblockDecoration: BoxDecoration(
              color: isDark ? const Color(0xFF0B0F17) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFE2E8F0),
                width: 1.0,
              ),
            ),
            codeblockPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
          ),
        ),
        if (widget.isStreaming) ...[
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: _cursorController,
            builder: (context, _) {
              return Opacity(
                opacity: _cursorController.value > 0.5 ? 1.0 : 0.0,
                child: Text(
                  '▌',
                  style: textStyle?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
