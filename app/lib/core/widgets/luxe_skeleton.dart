import 'package:flutter/material.dart';

import '../theme/luxe_theme.dart';
import 'luxe_kit.dart';

/// Placeholder in the shape of what is loading (QA 151): a spinner in an
/// empty screen made the content jump in when it arrived. Blocks shimmer
/// while the load is real and stand still with "Giảm chuyển động".
class LuxeSkeleton extends StatelessWidget {
  const LuxeSkeleton({super.key, required this.blocks, this.label});

  /// A card with a ring and three lines, then a second shorter card:
  /// AI cá nhân, Sức khỏe pin.
  const LuxeSkeleton.cards({super.key, this.label})
    : blocks = const [220, 160, 96];

  /// A summary card and rows: Lịch sử, Thói quen sạc.
  const LuxeSkeleton.list({super.key, this.label})
    : blocks = const [240, 84, 84, 84];

  /// Heights of the stacked blocks, top to bottom.
  final List<double> blocks;

  /// What TalkBack says instead of reading nothing.
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label ?? 'Đang tải',
    liveRegion: true,
    child: ExcludeSemantics(
      child: LuxeShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < blocks.length; i++)
              Container(
                height: blocks[i],
                margin: EdgeInsets.only(top: i == 0 ? 0 : 12),
                decoration: BoxDecoration(
                  color: LuxeColors.raised,
                  borderRadius: BorderRadius.circular(i == 0 ? 24 : 20),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
