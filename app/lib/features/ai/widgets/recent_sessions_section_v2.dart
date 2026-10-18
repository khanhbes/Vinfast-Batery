import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../data/models/smart_charging_session.dart';

/// Recent sessions on glass: start → end level as a small platinum/emerald
/// bar, the state and a compact meta line.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Lịch sử gần đây',
                style: TextStyle(
                  color: LuxeColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            TextButton(
              onPressed: onViewAll,
              style: TextButton.styleFrom(foregroundColor: LuxeColors.emerald),
              child: const Text('Tất cả'),
            ),
          ],
        ),
        if (syncedAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Đồng bộ lần cuối ${DateFormat('HH:mm').format(syncedAt!.toLocal())}',
              style: const TextStyle(color: LuxeColors.dim, fontSize: 12),
            ),
          ),
        if (sessions.isEmpty)
          const LuxeGlass(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 22),
            child: Column(
              children: [
                Icon(
                  Icons.history_toggle_off_rounded,
                  size: 28,
                  color: LuxeColors.platinumMid,
                ),
                SizedBox(height: 10),
                Text(
                  'Chưa có phiên sạc',
                  style: TextStyle(
                    color: LuxeColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Phiên Smart Charge hoàn tất sẽ xuất hiện tại đây.',
                  textAlign: TextAlign.center,
                  style: LuxeText.caption,
                ),
              ],
            ),
          )
        else
          LuxeGlass(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < sessions.take(5).length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 12, endIndent: 12),
                  _SessionTile(
                    session: sessions[i],
                    onTap: () => onOpen(sessions[i]),
                  ),
                ],
              ],
            ),
          ),
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
    // The owner's reading wins over the estimate (QA 128: 17/10 showed the
    // 80 % estimate although 79 % was confirmed); estimates carry a "~".
    final confirmed = session.actualEndSoc;
    final endSoc = confirmed ?? session.estimatedSoc ?? session.targetSoc;
    final duration = (session.stoppedAt ?? session.updatedAt).difference(
      session.startedAt ?? session.createdAt,
    );
    final energy = session.energyUsedWh >= 1000
        ? '${(session.energyUsedWh / 1000).toStringAsFixed(2)} kWh'
        : '${session.energyUsedWh.toStringAsFixed(0)} Wh';
    final (label, color) = switch (session.state) {
      ChargingSessionState.completed => ('Hoàn thành', LuxeColors.emerald),
      ChargingSessionState.cancelled => ('Đã dừng', LuxeColors.platinumMid),
      ChargingSessionState.interrupted ||
      ChargingSessionState.failed => ('Gián đoạn', LuxeColors.champagne),
      _ => ('Đang sạc', LuxeColors.emerald),
    };

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.3, -0.4),
                    colors: [Color(0x24FFFFFF), Color(0x08FFFFFF)],
                  ),
                  border: Border.all(color: LuxeColors.hairline),
                ),
                child: Icon(
                  isAi ? Icons.auto_awesome_rounded : Icons.schedule_rounded,
                  size: 17,
                  color: LuxeColors.platinum,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${session.startSoc.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: LuxeColors.platinum,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 13,
                            color: LuxeColors.dim,
                          ),
                        ),
                        Text(
                          '${confirmed == null ? '~' : ''}${endSoc.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: LuxeColors.emerald,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          label,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _LevelBar(start: session.startSoc / 100, end: endSoc / 100),
                    const SizedBox(height: 6),
                    Text(
                      '${DateFormat('dd/MM · HH:mm').format(session.createdAt.toLocal())} · ${_compactDuration(duration)} · $energy',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: LuxeColors.dim,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.start, required this.end});
  final double start;
  final double end;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 4,
    child: LayoutBuilder(
      builder: (context, c) {
        final s = start.clamp(0.0, 1.0) * c.maxWidth;
        final e = end.clamp(0.0, 1.0) * c.maxWidth;
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: const Color(0x14FFFFFF),
              ),
            ),
            Container(
              width: s,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: const Color(0x66D6D8DB),
              ),
            ),
            if (e > s)
              Positioned(
                left: s,
                width: e - s,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: const LinearGradient(
                      colors: [LuxeColors.emeraldDeep, LuxeColors.emerald],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

String _compactDuration(Duration value) {
  final minutes = value.inMinutes.clamp(0, 10 * 60);
  final hours = minutes ~/ 60;
  final remaining = minutes % 60;
  if (hours == 0) return '$remaining phút';
  return remaining == 0 ? '$hours giờ' : '$hours giờ $remaining phút';
}
