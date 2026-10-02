import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

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
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = widget.style ??
        theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          height: 1.45,
          fontSize: 14,
        );

    if (widget.text.isEmpty && widget.isStreaming) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('BatteryBot đang soạn câu trả lời', style: textStyle?.copyWith(fontStyle: FontStyle.italic, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(width: 4),
          AnimatedBuilder(
            animation: _cursorController,
            builder: (context, _) {
              return Opacity(
                opacity: _cursorController.value > 0.5 ? 1.0 : 0.0,
                child: Text('▌', style: textStyle?.copyWith(color: theme.colorScheme.primary)),
              );
            },
          ),
        ],
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
          ),
        ),
        if (widget.isStreaming) ...[
          const SizedBox(height: 2),
          AnimatedBuilder(
            animation: _cursorController,
            builder: (context, _) {
              return Opacity(
                opacity: _cursorController.value > 0.5 ? 1.0 : 0.0,
                child: Text('▌', style: textStyle?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
              );
            },
          ),
        ],
      ],
    );
  }
}
