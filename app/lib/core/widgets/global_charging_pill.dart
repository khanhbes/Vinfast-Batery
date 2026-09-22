import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/active_charging_session_coordinator.dart';
import '../../features/ai/controllers/smart_charging_controller.dart';

/// Persistent account-scoped indicator for an active charging session.
class GlobalChargingPill extends ConsumerWidget {
  const GlobalChargingPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleId = ref.watch(selectedVehicleIdProvider);
    final coordinator = ref.watch(activeChargingSessionProvider);
    if (vehicleId.isEmpty) {
      // A fresh device can receive the account-scoped session before its
      // vehicle picker has restored a selection. Keep the session visible
      // instead of silently hiding cross-device charging.
      if (coordinator.sessions.length == 1) {
        final remote = coordinator.sessions.single;
        return _pill(
          context,
          ref,
          remote.vehicleId,
          remote.targetSoc,
          remote.remaining,
          remote.vehicleId,
          synced: true,
          stale: remote.isStale,
        );
      }
      if (coordinator.sessions.length > 1) {
        return _multiPill(context, ref, coordinator.sessions);
      }
      return const SizedBox.shrink();
    }
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
          return _pill(
            context,
            ref,
            vehicleId,
            state.session?.targetSoc,
            state.chargerStatus?.timerRemaining ??
                state.session?.remaining(state.now),
            value.vehicleName,
            synced: false,
          );
        }
        final remote = coordinator.forVehicle(vehicleId);
        if (remote != null) {
          return _pill(
            context,
            ref,
            vehicleId,
            remote.targetSoc,
            remote.remaining,
            value.vehicleName,
            synced: true,
            stale: remote.isStale,
          );
        }
        final others = coordinator.sessions
            .where((item) => item.vehicleId != vehicleId)
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
            other.remaining,
            name,
            synced: true,
            stale: other.isStale,
          );
        }
        return _multiPill(context, ref, others);
      },
    );
  }

  Widget _pill(
    BuildContext context,
    WidgetRef ref,
    String vehicleId,
    double? targetSoc,
    Duration? remaining,
    String vehicleName, {
    required bool synced,
    bool stale = false,
  }) {
    final prefix = !synced
        ? 'ĐANG SẠC'
        : stale
        ? 'ĐANG SẠC · DỮ LIỆU CŨ'
        : 'ĐANG SẠC · ĐỒNG BỘ';
    final label = remaining == null
        ? prefix
        : '$prefix · ${remaining.inHours.toString().padLeft(2, '0')}:${(remaining.inMinutes % 60).toString().padLeft(2, '0')}';
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
        child: Semantics(
          button: true,
          label: 'Phiên sạc xe $vehicleName đang diễn ra. $label.',
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
    List<ActiveChargingSessionSnapshot> sessions,
  ) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
        child: Semantics(
          button: true,
          label: '${sessions.length} phiên sạc đang diễn ra.',
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
                    const Icon(Icons.expand_more, size: 18),
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
    List<ActiveChargingSessionSnapshot> sessions,
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
            ...sessions.map(
              (session) => ListTile(
                leading: const Icon(Icons.ev_station_rounded),
                title: Text(session.vehicleId),
                subtitle: Text(
                  session.isStale
                      ? 'Dữ liệu cũ — cần xác minh'
                      : 'Đang đồng bộ',
                ),
                onTap: () => Navigator.of(sheetContext).pop(session.vehicleId),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    ref.read(selectedVehicleIdProvider.notifier).state = selected;
    ref.read(currentTabProvider.notifier).state = 1;
  }
}
