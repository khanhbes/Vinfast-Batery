import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/connection_coordinator.dart';
import '../../features/ai/controllers/smart_charging_controller.dart';

/// Persistent, low-noise indicator for the selected vehicle's active session.
/// It is rendered by the shell rather than by an individual tab, so changing
/// tabs cannot hide the emergency stop/status affordance.
class GlobalChargingPill extends ConsumerWidget {
  const GlobalChargingPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    if (vehicleId.isEmpty) return const SizedBox.shrink();
    final vehicle = ref.watch(vehicleProvider(vehicleId));
    return vehicle.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (value) {
        if (value == null) return const SizedBox.shrink();
        final args = SmartChargingControllerArgs(
          vehicleId: vehicleId,
          currentSoc: value.currentBattery.toDouble(),
        );
        final state = ref.watch(smartChargingControllerProvider(args));
        if (state.hasActiveSession) {
          final remaining =
              state.chargerStatus?.timerRemaining ??
              state.session?.remaining(state.now);
          return _pill(
            context,
            ref,
            vehicleId,
            state.session?.targetSoc,
            remaining,
            value.vehicleName,
          );
        }
        // A session on vehicle A must remain discoverable after switching to
        // vehicle B. The local snapshot is only a display/recovery hint; the
        // Shelly timer remains the safety authority.
        return FutureBuilder<List<ActiveChargingSnapshot>>(
          future: ConnectionCoordinator().loadSnapshots(),
          builder: (context, snapshot) {
            final others = (snapshot.data ?? const <ActiveChargingSnapshot>[])
                .where(
                  (item) =>
                      item.vehicleId != vehicleId &&
                      item.lastKnownRelay &&
                      item.effectiveStopAt.isAfter(DateTime.now()),
                )
                .toList(growable: false);
            if (others.isEmpty) return const SizedBox.shrink();
            if (others.length == 1) {
              final other = others.first;
              final name =
                  ref
                      .watch(vehicleProvider(other.vehicleId))
                      .valueOrNull
                      ?.vehicleName ??
                  other.vehicleId;
              return _pill(
                context,
                ref,
                other.vehicleId,
                other.targetSoc,
                other.effectiveStopAt.difference(DateTime.now()),
                name,
              );
            }
            return _multiPill(context, ref, others);
          },
        );
      },
    );
  }

  Widget _pill(
    BuildContext context,
    WidgetRef ref,
    String vehicleId,
    double? targetSoc,
    Duration? remaining,
    String vehicleName,
  ) {
    final label = remaining == null
        ? 'ĐANG SẠC'
        : 'ĐANG SẠC · ${remaining.inHours.toString().padLeft(2, '0')}:${(remaining.inMinutes % 60).toString().padLeft(2, '0')}';
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
        child: Semantics(
          button: true,
          label:
              'Phiên sạc xe $vehicleName đang diễn ra. $label. Mở Smart Charge',
          child: Material(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
            elevation: 4,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                ref.read(selectedVehicleIdProvider.notifier).state = vehicleId;
                ref.read(currentTabProvider.notifier).state = 1;
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    if (targetSoc != null && targetSoc > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        'mục tiêu ~${targetSoc.round()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _multiPill(
    BuildContext context,
    WidgetRef ref,
    List<ActiveChargingSnapshot> sessions,
  ) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
        child: Semantics(
          button: true,
          label:
              '${sessions.length} phiên sạc đang diễn ra. Chọn xe để mở Smart Charge',
          child: Material(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
            elevation: 4,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _showSessionChooser(context, ref, sessions),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${sessions.length} XE ĐANG SẠC',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSessionChooser(
    BuildContext context,
    WidgetRef ref,
    List<ActiveChargingSnapshot> sessions,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            Text(
              'Phiên sạc đang diễn ra',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ...sessions.map((session) {
              final vehicle = ref
                  .read(vehicleProvider(session.vehicleId))
                  .valueOrNull;
              final remaining = session.effectiveStopAt.difference(
                DateTime.now(),
              );
              return ListTile(
                leading: const Icon(Icons.ev_station_rounded),
                title: Text(vehicle?.vehicleName ?? session.vehicleId),
                subtitle: Text(
                  'Mục tiêu ~${session.targetSoc.round()}% · còn ${remaining.inHours}g ${remaining.inMinutes % 60}p',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(sheetContext).pop(session.vehicleId),
              );
            }),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    ref.read(selectedVehicleIdProvider.notifier).state = selected;
    ref.read(currentTabProvider.notifier).state = 1;
  }
}
