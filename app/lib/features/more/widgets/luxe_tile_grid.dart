import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/widgets/luxe_settings.dart';
import '../../../data/models/entitlement.dart';
import '../../../data/models/shelly_connection_state.dart';
import '../../../data/services/shelly_connection_coordinator.dart';
import '../../home/widgets/luxe_dashboard_cards.dart' show LuxePressable;
import '../../premium/premium_gate.dart';

/// Glass tile grid shared by Cài đặt and Tiện ích (QA 140): two columns,
/// one at large text or below 300 dp.
class LuxeTile {
  const LuxeTile({
    this.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.accent,
    this.shelly = false,
    this.lockedBy,
  });
  final Key? key;
  final IconData icon;
  final String title;
  final String? value;
  final Color? accent;
  final VoidCallback onTap;

  /// Live Shelly status from the shared connection coordinator.
  final bool shelly;

  /// Outside the plan the tile is greyed and only its tag opens Premium
  /// (QA 136).
  final PremiumFeature? lockedBy;
}

class LuxeTileGrid extends StatelessWidget {
  const LuxeTileGrid({super.key, required this.tiles});
  final List<LuxeTile> tiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final big = MediaQuery.textScalerOf(context).scale(14) > 20;
      final columns = big || box.maxWidth < 300 ? 1 : 2;
      Widget cell(LuxeTile t) => KeyedSubtree(
        key: t.key,
        child: t.lockedBy == null
            ? _TileCard(tile: t)
            : PremiumLocked(
                feature: t.lockedBy!,
                tagPadding: const EdgeInsets.all(10),
                child: _TileCard(tile: t),
              ),
      );
      if (columns == 1) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, t) in tiles.indexed) ...[
              if (i > 0) const SizedBox(height: 12),
              cell(t),
            ],
          ],
        );
      }
      // QA 141: the two tiles of a row share one height (a longer line
      // made one taller than its neighbour).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cell(tiles[i])),
                  const SizedBox(width: 12),
                  Expanded(
                    child: i + 1 < tiles.length
                        ? cell(tiles[i + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _TileCard extends StatelessWidget {
  const _TileCard({required this.tile});
  final LuxeTile tile;

  @override
  Widget build(BuildContext context) {
    Widget body(String value, Color? dot) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            LuxeMedallion(icon: tile.icon, accent: tile.accent, size: 38),
            const Spacer(),
            if (dot != null)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dot,
                  boxShadow: [
                    BoxShadow(color: dot.withValues(alpha: 0.6), blurRadius: 8),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          tile.title,
          maxLines: 2,
          style: const TextStyle(
            color: LuxeColors.text,
            fontSize: 15,
            height: 1.25,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          // QA 140: the Shelly line ("Đang tắt · 0 W · 230 V") needs three.
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: LuxeText.caption.copyWith(fontSize: 12.5),
        ),
      ],
    );

    return LuxePressable(
      radius: 22,
      // QA 141: one announcement (TalkBack read the title twice).
      semanticsLabel: tile.value == null || tile.shelly
          ? tile.title
          : '${tile.title}. ${tile.value}',
      onTap: () {
        HapticFeedback.selectionClick();
        tile.onTap();
      },
      child: LuxeGlass(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 124),
          child: ExcludeSemantics(
            excluding: !tile.shelly,
            child: tile.shelly
                ? StreamBuilder<ShellyConnectionSnapshot>(
                    stream: ShellyConnectionCoordinator.shared.states,
                    initialData: ShellyConnectionCoordinator.shared.current,
                    builder: (context, snap) {
                      final s = snap.data;
                      final ok =
                          s?.state == ShellyConnectionFlowState.connected &&
                          s?.controlUncertain != true;
                      final linked = s?.isLinked == true;
                      return body(
                        // Same label as Sạc pin / BatteryBot (Task 108).
                        [
                          s?.connectionLabel ?? 'Chưa kết nối Shelly',
                          // QA 141: relay state only; volts and amps are for Sạc pin.
                          ?s?.metricsLine?.split(' · ').first,
                        ].join('\n'),
                        ok
                            ? LuxeColors.emerald
                            : (linked ? LuxeColors.champagne : LuxeColors.dim),
                      );
                    },
                  )
                : body(tile.value ?? '', null),
          ),
        ),
      ),
    );
  }
}
