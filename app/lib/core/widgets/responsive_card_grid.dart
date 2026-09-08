import 'package:flutter/material.dart';

/// Small groups of cards: equal widths/heights per row without fixed heights.
/// Use for summary cards, not large or lazy lists.
class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({
    super.key,
    required this.children,
    this.maxColumns = 2,
    this.minCardWidth = 140,
    this.spacing = 12,
  });

  final List<Widget> children;
  final int maxColumns;
  final double minCardWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns =
            ((constraints.maxWidth + spacing) /
                    (minCardWidth * (scale < 1 ? 1 : scale) + spacing))
                .floor()
                .clamp(1, maxColumns);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var start = 0; start < children.length; start += columns) ...[
              if (start > 0) SizedBox(height: spacing),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0) SizedBox(width: spacing),
                      Expanded(
                        child: start + column < children.length
                            ? children[start + column]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
