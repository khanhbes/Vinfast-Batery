import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/cockpit_design_system.dart';
import '../../../data/models/smart_charging_session.dart';

/// Recent sessions section for the Smart Charge tab bottom area.
/// Shows the 3 most recent charging sessions with premium styling.
class RecentSessionsSectionV2 extends StatelessWidget {
  const RecentSessionsSectionV2({
    super.key,
    required this.sessions,
    required this.onViewAll,
    required this.onOpen,
    this.syncedAt,
  });

  final List<SmartChargingSession> sessions;
  final VoidCallback onViewAll;
  final ValueChanged<SmartChargingSession> onOpen;
  final DateTime? syncedAt;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return _EmptyState(onViewAll: onViewAll);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: CockpitColors.emerald,
                ),
                const SizedBox(width: 8),
                Text(
                  'Lịch sử gần đây',
                  style: TextStyle(
                    color: CockpitColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            InkWell(
              onTap: onViewAll,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Tất cả',
                      style: TextStyle(
                        color: CockpitColors.emerald,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: CockpitColors.emerald,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        if (syncedAt != null) ...[
          const SizedBox(height: 4),
          Text(
            'Đồng bộ lần cuối ${DateFormat('HH:mm').format(syncedAt!.toLocal())}',
            style: TextStyle(
              color: CockpitColors.dim,
              fontSize: 10,
            ),
          ),
        ],

        const SizedBox(height: 12),

        // Session tiles
        for (final session in sessions.take(3)) ...[
          _SessionTile(session: session, onTap: () => onOpen(session)),
          if (session != sessions.take(3).last)
            Divider(
              height: 1,
              color: CockpitColors.border,
              indent: 42,
            ),
        ],
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.onTap});
  final SmartChargingSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isAi = session.strategy != ChargingStrategy.manualTimed;
    final endSoc = session.estimatedSoc ?? session.targetSoc;
    final duration = (session.stoppedAt ?? session.updatedAt).difference(
      session.startedAt ?? session.createdAt,
    );
    final energy = session.energyUsedWh >= 1000
        ? '${(session.energyUsedWh / 1000).toStringAsFixed(2)} kWh'
        : '${session.energyUsedWh.toStringAsFixed(0)} Wh';

    // Terminal state styling
    final isCompleted = session.state == ChargingSessionState.completed;
    final stateColor = isCompleted ? CockpitColors.emerald : CockpitColors.amber;
    final stateLabel = isCompleted ? 'Hoàn thành' : 'Đã dừng';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              // Icon
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isAi
                      ? Icons.auto_awesome_rounded
                      : Icons.timer_rounded,
                  size: 16,
                  color: stateColor,
                ),
              ),
              const SizedBox(width: 10),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${session.startSoc.toStringAsFixed(0)}%',
                          style: CockpitTypography.numbers(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 12,
                            color: CockpitColors.muted,
                          ),
                        ),
                        Text(
                          '${endSoc.toStringAsFixed(0)}%',
                          style: CockpitTypography.numbers(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: stateColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: stateColor.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            stateLabel,
                            style: TextStyle(
                              color: stateColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${DateFormat('dd/MM · HH:mm').format(session.createdAt.toLocal())} · ${_compactDuration(duration)} · $energy',
                      style: TextStyle(
                        color: CockpitColors.muted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Chevron
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: CockpitColors.dim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onViewAll});
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(
            Icons.history_rounded,
            size: 18,
            color: CockpitColors.emerald,
          ),
          const SizedBox(width: 8),
          Text(
            'Lịch sử gần đây',
            style: TextStyle(
              color: CockpitColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Center(
        child: Column(
          children: [
            Icon(
              Icons.electric_bolt_rounded,
              size: 32,
              color: CockpitColors.emerald.withValues(alpha: .4),
            ),
            const SizedBox(height: 10),
            Text(
              'Chưa có phiên sạc',
              style: TextStyle(
                color: CockpitColors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Phiên Smart Charge hoàn tất sẽ xuất hiện tại đây.',
              style: TextStyle(
                color: CockpitColors.dim,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ],
  );
}

String _compactDuration(Duration value) {
  final minutes = value.inMinutes.clamp(0, 10 * 60);
  final hours = minutes ~/ 60;
  final remaining = minutes % 60;
  if (hours == 0) return '$remaining phút';
  return remaining == 0 ? '$hours giờ' : '$hours giờ $remaining phút';
}
