import 'package:flutter/material.dart';

/// Strategy for intelligently shortening text.
enum ResponsiveTextStrategy {
  /// Default: wrap text, then try name strategy, then middle-truncation.
  auto,

  /// Remove brand prefix (e.g. "VinFast Lux A2.0" → "Lux A2.0").
  name,

  /// Truncate the local part of an email (e.g. "longname@example.com" → "long…@example.com").
  email,

  /// Middle-truncate a monospace identifier (e.g. "abc123def456" → "abc1…f456").
  monoId,
}

/// A text widget that intelligently handles long strings without using ellipsis.
///
/// Priority order:
///  1. Shows the full text if it fits.
///  2. Allows wrapping up to [maxLines].
///  3. If still overflowing, reduces font-size to [minFontSize].
///  4. Applies [strategy]-aware shortening as a last resort.
///  5. Long-press reveals the full text in a tooltip.
class ResponsiveText extends StatelessWidget {
  const ResponsiveText(
    this.text, {
    super.key,
    this.strategy = ResponsiveTextStrategy.auto,
    this.style,
    this.maxLines = 2,
    this.minFontSize = 10.0,
    this.textAlign,
  });

  final String text;
  final ResponsiveTextStrategy strategy;
  final TextStyle? style;
  final int maxLines;
  final double minFontSize;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final baseFontSize = baseStyle.fontSize ?? 14.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Try full text with wrap first
        final fullPainter = TextPainter(
          text: TextSpan(text: text, style: baseStyle),
          maxLines: maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        if (!fullPainter.didExceedMaxLines) {
          fullPainter.dispose();
          return _buildText(text, baseStyle);
        }
        fullPainter.dispose();

        // Try reducing font-size
        for (var size = baseFontSize - 1; size >= minFontSize; size -= 1) {
          final scaledStyle = baseStyle.copyWith(fontSize: size);
          final scaledPainter = TextPainter(
            text: TextSpan(text: text, style: scaledStyle),
            maxLines: maxLines,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: constraints.maxWidth);

          if (!scaledPainter.didExceedMaxLines) {
            scaledPainter.dispose();
            return _buildText(text, scaledStyle);
          }
          scaledPainter.dispose();
        }

        // Apply strategy shortening with minimum font size
        final minStyle = baseStyle.copyWith(fontSize: minFontSize);
        var shortened = text;
        for (var pass = 1; pass <= 4; pass++) {
          shortened = _shorten(shortened, strategy, pass);
          final painter = TextPainter(
            text: TextSpan(text: shortened, style: minStyle),
            maxLines: maxLines,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: constraints.maxWidth);

          if (!painter.didExceedMaxLines) {
            painter.dispose();
            return _buildTooltipText(shortened, minStyle);
          }
          painter.dispose();
        }

        // Last resort: show shortened text with tooltip
        return _buildTooltipText(shortened, minStyle);
      },
    );
  }

  Widget _buildText(String displayText, TextStyle effectiveStyle) {
    return Text(
      displayText,
      style: effectiveStyle,
      maxLines: maxLines,
      textAlign: textAlign,
      softWrap: true,
    );
  }

  Widget _buildTooltipText(String displayText, TextStyle effectiveStyle) {
    return Tooltip(
      message: text,
      preferBelow: true,
      child: Text(
        displayText,
        style: effectiveStyle,
        maxLines: maxLines,
        textAlign: textAlign,
        softWrap: true,
      ),
    );
  }

  static String _shorten(String text, ResponsiveTextStrategy strategy, int pass) {
    if (text.isEmpty || pass <= 0) return text;

    switch (strategy) {
      case ResponsiveTextStrategy.name:
        final parts = text.split(RegExp(r'\s+'));
        if (parts.length <= 1) return text;
        if (pass == 1) return parts.sublist(1).join(' ');
        if (pass == 2 && parts.length > 2) {
          return parts.sublist(1, parts.length - 1).join(' ');
        }
        return parts.sublist(1).join(' ');

      case ResponsiveTextStrategy.email:
        final at = text.indexOf('@');
        if (at <= 3) return text;
        final keep = (at ~/ 2 - pass).clamp(2, at);
        return '${text.substring(0, keep)}…${text.substring(at)}';

      case ResponsiveTextStrategy.monoId:
        if (text.length <= 10) return text;
        final keep = (text.length ~/ 2 - pass * 2).clamp(4, text.length);
        final half = keep ~/ 2;
        return '${text.substring(0, half)}…${text.substring(text.length - half)}';

      case ResponsiveTextStrategy.auto:
        if (text.contains(' ') && pass <= 2) {
          return _shorten(text, ResponsiveTextStrategy.name, pass);
        }
        if (text.length <= 8) return text;
        final keep = (text.length - pass * 3).clamp(6, text.length);
        final half = keep ~/ 2;
        return '${text.substring(0, half)}…${text.substring(text.length - half)}';
    }
  }
}
