import 'package:flutter/material.dart';

/// Readable, copyable technical values; narrow screens stack label and value.
class AdaptiveDetailRows extends StatelessWidget {
  const AdaptiveDetailRows({super.key, required this.rows});
  final List<(String, String)> rows;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final stacked =
          size.maxWidth < 480 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.$1,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          row.$2,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            row.$1,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: SelectableText(
                            row.$2,
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
            ),
        ],
      );
    },
  );
}
