import 'package:flutter/material.dart';

import '../../../data/models/smart_charging_session.dart';

class PersistentChargingPill extends StatelessWidget {
  const PersistentChargingPill({
    super.key,
    required this.session,
    required this.now,
    required this.onTap,
  });

  final SmartChargingSession session;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (session.state.isTerminal) return const SizedBox.shrink();
    final remaining = session.remaining(now);
    return Semantics(
      button: true,
      label:
          'Đang sạc, mục tiêu ${session.targetSoc.round()} phần trăm, còn ${remaining.inHours} giờ ${remaining.inMinutes.remainder(60)} phút',
      child: Material(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt_rounded, size: 20),
                const SizedBox(width: 6),
                Text(
                  'Đang sạc · Mục tiêu ${session.targetSoc.round()}% · ${remaining.inHours}g${remaining.inMinutes.remainder(60).toString().padLeft(2, '0')}p',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
